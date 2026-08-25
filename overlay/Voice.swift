// Listening for spoken commands during a session.
//
// The audio comes from the recorder's own segment output and not from a second
// capture of the microphone. Two consumers of one device is a thing that can
// half fail, and a recogniser hearing a stream the recording never got would
// act on words that are not in the transcript. Reading what the recorder wrote
// also means the offsets here and the offsets whisper produces are the same
// clock, which is what lets the words be taken back out of the transcript.
//
// The recogniser is whisper, the same one that writes the transcript, chosen by
// measuring all of them against 28 recordings of this tool's own user saying
// commands into it:
//
//   Apple's recogniser, as it comes                 5 of 28
//   Apple's, told which phrases to expect           9 of 28
//   whisper, plain                                 13 of 28
//   whisper, told which phrases to expect          20 of 28
//
// Apple's heard "let's draw" as "let's throw" and "let's arrow" as "that's
// arrow". Whisper reads this voice four times better, needs no permission of
// its own, and is the model the tool already requires.
//
// The bias is only ever applied here. The transcript is a separate run over the
// whole recording with no prompt at all, so nothing about listening for
// commands can put words into what the user actually said.
import Foundation

protocol VoiceListenerDelegate: AnyObject {
  func voiceHeard(_ matches: [VoiceMatch], at offset: TimeInterval)
  func voiceFailed(_ reason: String)
}

final class VoiceListener {
  weak var delegate: VoiceListenerDelegate?

  private let directory: String
  private let startReference: Date
  private let grammar: VoiceGrammar

  // Long enough to hold the longest command with room either side, and short
  // enough that whisper reads it in well under the time the next one takes to
  // arrive. Measured on this machine: about 0.9 seconds for a window this size.
  private let windowSeconds = 3.0
  // Windows overlap, so a command spoken across the edge of one is whole in the
  // next. Without the overlap a boundary swallows a command every few seconds
  // and there is no way to tell which ones.
  private let strideSeconds = 1.5

  private var buffer = Data()
  private var timer: Timer?
  private var reading = false
  private var lastRead = Date.distantPast
  private var previousText = ""
  private var lastWindowBytes = 0

  // Which segments have already been read. Segments are overwritten in place
  // under segment_wrap, so the mark is the time one was written and not its
  // name.
  private var consumedThrough = Date.distantPast
  private var segmentOffset: TimeInterval = 0

  private var lastFired: [VoiceCommand: Date] = [:]
  private var fedAnything = false

  private(set) var running = false
  // The last thing whisper said it heard. Read by the replay probe, so a case
  // can report what a person's voice actually became before saying whether the
  // right command came out of it.
  private(set) var lastHeard = ""
  // Called once a replayed clip has been read, so a case can move on to the
  // next one instead of waiting out a fixed timer for each.
  var onSettled: (() -> Void)?

  private let queue = DispatchQueue(label: "recordfeedback.voice")

  init(session: String, grammar: VoiceGrammar, startedAt: Date) {
    directory = session + "/levels"
    self.grammar = grammar
    startReference = startedAt
  }

  // MARK: what it needs to run at all

  static func whisperBinary() -> String? {
    let environment = ProcessInfo.processInfo.environment
    if let given = environment["RF_WHISPER"],
       FileManager.default.isExecutableFile(atPath: given) {
      return given
    }
    for path in ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"]
    where FileManager.default.isExecutableFile(atPath: path) {
      return path
    }
    return nil
  }

  static func model() -> String? {
    let environment = ProcessInfo.processInfo.environment
    if let given = environment["RF_MODEL"], FileManager.default.fileExists(atPath: given) {
      return given
    }
    let home = environment["RF_HOME"] ?? NSHomeDirectory() + "/.recordfeedback"
    let guess = home + "/models/ggml-large-v3-turbo-q5_0.bin"
    return FileManager.default.fileExists(atPath: guess) ? guess : nil
  }

  static func language() -> String {
    let wanted = ProcessInfo.processInfo.environment["RF_LANG"] ?? "auto"
    return wanted.isEmpty ? "auto" : wanted
  }

  // Why it cannot listen, or nothing. The same two things the transcript needs,
  // so a machine that can finish a session can also listen during one.
  static func unavailable() -> String? {
    if whisperBinary() == nil {
      return "whisper-cli is not installed, so there is nothing to listen with."
        + " Install it with: brew install whisper-cpp"
    }
    if model() == nil {
      return "there is no whisper model to listen with. The README says where to"
        + " download one, and RF_MODEL points at it."
    }
    return nil
  }

  // MARK: listening

  func start() {
    if let reason = Self.unavailable() {
      delegate?.voiceFailed(reason)
      return
    }
    running = true
    warn("voice control is listening, with whisper in " + Self.language() + ".")
    // Twice a second, which is faster than segments arrive, so a finished one
    // is picked up in the same half second it was closed.
    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      self?.pump()
    }
  }

  func stop() {
    running = false
    timer?.invalidate()
    timer = nil
  }

  // Feeds every segment the recorder has finished since the last pass.
  private func pump() {
    guard running else { return }
    let manager = FileManager.default
    guard let names = try? manager.contentsOfDirectory(atPath: directory) else { return }

    var finished: [(Date, String)] = []
    var newest = Date.distantPast
    for name in names where name.hasSuffix(".pcm") {
      let path = directory + "/" + name
      guard let attrs = try? manager.attributesOfItem(atPath: path),
            let modified = attrs[.modificationDate] as? Date,
            let size = attrs[.size] as? Int, size > 0 else { continue }
      newest = max(newest, modified)
      finished.append((modified, path))
    }

    // The newest file is the one being written into right now, and half of a
    // second read as though it were a whole one is a word cut in half. Every
    // other one is closed and complete.
    for (modified, path) in finished.sorted(by: { $0.0 < $1.0 })
    where modified > consumedThrough && modified < newest {
      guard let data = manager.contents(atPath: path), !data.isEmpty else { continue }
      append(data)
      if !fedAnything {
        fedAnything = true
        warn("voice control is receiving audio from the recorder.")
      }
      consumedThrough = modified
      // The recorder runs in real time, so when a segment was written is where
      // it sits in the recording. That is the same clock whisper timestamps
      // against, which is what lets these words be taken back out of it.
      segmentOffset = modified.timeIntervalSince(startReference)
    }

    if Date().timeIntervalSince(lastRead) >= strideSeconds { read() }
  }

  private func append(_ data: Data) {
    buffer.append(data)
    let limit = Int(windowSeconds * 16000) * 2
    if buffer.count > limit { buffer.removeFirst(buffer.count - limit) }
  }

  // MARK: reading a window

  private func read() {
    // One at a time. Whisper takes about as long as the stride, and two of them
    // racing would read the same seconds twice and act on them twice.
    guard !reading, running else { return }
    let leastUseful = Int(0.8 * 16000) * 2
    guard buffer.count >= leastUseful else { return }
    // Whisper hands back its own prompt when there is nothing in the audio to
    // read, so a window with no speech in it does not produce silence, it
    // produces an invented command. Nothing is asked of it unless somebody
    // spoke.
    guard Self.carriesSpeech(buffer) else { return }
    reading = true
    lastRead = Date()
    let window = buffer
    lastWindowBytes = window.count
    let offset = segmentOffset

    queue.async { [weak self] in
      guard let self = self else { return }
      let text = self.transcribe(window) ?? ""
      DispatchQueue.main.async {
        self.reading = false
        self.finish(text, at: offset)
      }
    }
  }

  private func finish(_ text: String, at offset: TimeInterval) {
    lastHeard = text
    // Each window is its own reading rather than one sentence being revised, so
    // a command is settled once two windows in a row say the same thing:
    // nothing more is arriving to lengthen it.
    let settled = !text.isEmpty && text == previousText
    previousText = text
    consider(text, settled: settled, at: offset,
             seconds: Double(lastWindowBytes) / (16000 * 2))
  }

  // Runs whisper over one window, told which phrases to expect.
  private func transcribe(_ window: Data) -> String? {
    guard let binary = Self.whisperBinary(), let model = Self.model() else { return nil }
    let wav = NSTemporaryDirectory() + "rf-voice-\(UInt32.random(in: 0...UInt32.max)).wav"
    defer { try? FileManager.default.removeItem(atPath: wav) }
    guard write(window, to: wav) else { return nil }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: binary)
    task.arguments = [
      "-m", model, "-f", wav, "-l", Self.language(),
      "-nt", "-np", "-t", "8",
      // Whisper writes music notes, applause and other non speech markers into
      // quiet audio, and the same unsureness is what makes it repeat the prompt
      // back. Suppressing them costs nothing here: none of the commands are
      // non speech.
      "-sns",
      // The phrases this tool is listening for. Whisper weighs what it has been
      // told to expect, and without this "let's draw" comes back as "let's
      // throw": these are short, out of context, and every word in them has a
      // common neighbour that sounds like it. Measured against real recordings
      // it is the difference between 13 of 28 and 20 of 28.
      "--prompt", grammar.expectedPhrases().joined(separator: ". "),
    ]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    do { try task.run() } catch { return nil }
    let out = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { return nil }
    return String(data: out, encoding: .utf8)?
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // Whether a window has anything worth reading in it. The peak and not the
  // average, because a window is mostly the silence around a sentence and an
  // average drops with the length of the pause rather than with the voice.
  static func carriesSpeech(_ pcm: Data) -> Bool {
    var peak: Int32 = 0
    pcm.withUnsafeBytes { raw in
      let samples = raw.bindMemory(to: Int16.self)
      for index in 0..<samples.count {
        let value = Int32(Int16(littleEndian: samples[index]).magnitude)
        if value > peak { peak = value }
      }
    }
    guard peak > 0 else { return false }
    // Measured across the recordings this was tuned on: a spoken command peaks
    // between -24 and -28 dBFS, and a window carrying only room tone stays
    // below -40.
    return 20 * log10(Double(peak) / 32768) > -40
  }

  // A 16 kHz mono PCM wav, which is what the recorder writes and what whisper
  // reads without resampling anything.
  private func write(_ pcm: Data, to path: String) -> Bool {
    var header = Data()
    func put32(_ value: UInt32) {
      withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
    }
    func put16(_ value: UInt16) {
      withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
    }
    header.append(contentsOf: Array("RIFF".utf8))
    put32(UInt32(36 + pcm.count))
    header.append(contentsOf: Array("WAVEfmt ".utf8))
    put32(16)
    put16(1)
    put16(1)
    put32(16000)
    put32(16000 * 2)
    put16(2)
    put16(16)
    header.append(contentsOf: Array("data".utf8))
    put32(UInt32(pcm.count))
    return FileManager.default.createFile(atPath: path, contents: header + pcm)
  }

  // MARK: deciding

  // The least time one of these takes to say, with the pause around it.
  // Measured against the recordings: two commands inside two seconds is the
  // recogniser repeating itself, and two inside three seconds is a person
  // saying the same thing twice, which they do.
  private let secondsPerCommand = 1.1

  private func consider(_ heard: String, settled: Bool, at offset: TimeInterval,
                        seconds: TimeInterval) {
    let matches = grammar.matches(in: heard)
    guard !matches.isEmpty else { return }

    // Whisper loops when it is unsure, repeating a phrase it was told to expect
    // until it runs out of room. One recording of this user saying "let's draw"
    // came back as "let's take a screenshot" three times inside two seconds.
    //
    // Repeating is not itself the tell: a person testing this says "let's
    // finish" twice in a row and means both. What gives it away is the rate.
    // Nobody says three commands in two seconds, so a reading that claims more
    // commands than the audio has room for is the recogniser talking to itself
    // and none of it is trustworthy.
    let room = max(1, Int(seconds / secondsPerCommand))
    if matches.count > room {
      warn("voice control ignored a reading of "
           + String(format: "%.1f", seconds) + "s claiming \(matches.count) commands: "
           + heard)
      return
    }

    var fresh: [VoiceMatch] = []
    let now = Date()
    for one in matches {
      // This window is still short of a longer command that begins the same
      // way, so the rest of it may be in the next one. Acting now takes the
      // wrong picture.
      if one.couldGrow && !settled { continue }
      // Windows overlap and each is read on its own, so the same command is
      // seen more than once by design. Nobody says one twice this fast.
      if let last = lastFired[one.command],
         now.timeIntervalSince(last) < windowSeconds { continue }
      lastFired[one.command] = now
      fresh.append(one)
    }
    guard !fresh.isEmpty else { return }
    delegate?.voiceHeard(fresh, at: offset)
  }

  // MARK: replay, for the cases built out of real recordings

  // Reads a whole recording in one go, instead of waiting for a recorder to
  // write it a second at a time. The only part of the live path it skips is
  // reading the segment files, which has a case of its own.
  func replay(wav: String, whenDone: @escaping () -> Void) {
    guard let data = FileManager.default.contents(atPath: wav), data.count > 44 else {
      delegate?.voiceFailed("no audio at " + wav)
      whenDone()
      return
    }
    running = true
    lastFired = [:]
    // A clip is one utterance and there is no next window to wait for, so it is
    // settled by the time it has been read.
    let body = Data(data.dropFirst(44))
    queue.async { [weak self] in
      guard let self = self else { return }
      let text = self.transcribe(body) ?? ""
      DispatchQueue.main.async {
        self.lastHeard = text
        self.consider(text, settled: true, at: 0,
                      seconds: Double(body.count) / (16000 * 2))
        let done = self.onSettled
        self.onSettled = nil
        done?()
        whenDone()
      }
    }
  }

  func startForReplay() -> Bool {
    guard Self.unavailable() == nil else { return false }
    running = true
    return true
  }
}
