// Listening for spoken commands during a session.
//
// The audio comes from the recorder's own segment output and not from a second
// capture of the microphone. Two consumers of one device is a thing that can
// half fail, and a recogniser hearing a stream the recording never got would
// act on words that are not in the transcript. Reading what the recorder wrote
// also means the offsets here and the offsets whisper produces are the same
// clock, which is what lets the words be taken back out of the transcript.
//
// Recognition is on device. This tool records everything a person says while
// they work, and sending that to a server to be told whether they said "let's
// draw" is not a trade its user agreed to.
import AVFoundation
import Foundation
import Speech

protocol VoiceListenerDelegate: AnyObject {
  func voiceHeard(_ matches: [VoiceMatch], at offset: TimeInterval)
  func voiceFailed(_ reason: String)
}

final class VoiceListener {
  weak var delegate: VoiceListenerDelegate?

  private let directory: String
  private let startReference: Date
  private let grammar: VoiceGrammar
  private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000,
                                     channels: 1, interleaved: true)

  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var timer: Timer?

  // Which segments have already been fed. Segments are overwritten in place
  // under segment_wrap, so the mark is the time one was written and not its
  // name.
  private var consumedThrough = Date.distantPast
  private var segmentOffset: TimeInterval = 0

  // A recogniser revises the sentence it is building, handing the whole thing
  // back on every partial result. Without a mark of what has already been acted
  // on, one "let's draw" fires on every revision that follows it.
  private var firedThrough = 0
  private var lastFired: [VoiceCommand: Date] = [:]

  // Apple ends a recognition task of its own accord after about a minute, and a
  // session is longer than that, so the task is replaced before it expires
  // rather than after it has stopped answering.
  private var taskStarted = Date.distantPast
  private let taskLife: TimeInterval = 50

  private(set) var running = false

  static func locale() -> String {
    let wanted = ProcessInfo.processInfo.environment["RF_LANG"] ?? "auto"
    if wanted.isEmpty || wanted == "auto" {
      return Locale.current.identifier
    }
    // RF_LANG is whisper's two letter code, and a recogniser wants a region
    // with it. The system's own region is the best guess available.
    if wanted.count == 2, let region = Locale.current.regionCode {
      return wanted + "_" + region
    }
    return wanted
  }

  init(session: String, grammar: VoiceGrammar, startedAt: Date) {
    directory = session + "/levels"
    self.grammar = grammar
    startReference = startedAt
  }

  // Asks for the permission and starts listening, or says why it cannot. It
  // says so rather than failing quietly, because a person who turned this on is
  // about to talk to a tool that is not listening.
  func start() {
    SFSpeechRecognizer.requestAuthorization { [weak self] status in
      DispatchQueue.main.async { self?.authorized(status) }
    }
  }

  private func authorized(_ status: SFSpeechRecognizerAuthorizationStatus) {
    switch status {
    case .authorized:
      break
    case .denied:
      delegate?.voiceFailed("Speech Recognition permission was refused. Turn it on in"
        + " System Settings, Privacy and Security, Speech Recognition.")
      return
    case .restricted:
      delegate?.voiceFailed("this machine does not allow speech recognition.")
      return
    case .notDetermined:
      delegate?.voiceFailed("the Speech Recognition prompt was not answered.")
      return
    @unknown default:
      delegate?.voiceFailed("speech recognition is unavailable.")
      return
    }

    // The language whisper is told to transcribe in, so a person who set
    // RF_LANG is not listened to in a language they are not speaking. "auto"
    // is whisper's, not a locale, and there is nothing to detect from before
    // the first word, so the system's own language is the honest default.
    let name = Self.locale()
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: name))
    guard let recognizer = recognizer, recognizer.isAvailable else {
      delegate?.voiceFailed("no speech recogniser is available for " + name + ".")
      return
    }
    guard recognizer.supportsOnDeviceRecognition else {
      // The alternative is uploading the session, which is not a choice this
      // tool makes quietly on somebody's behalf.
      delegate?.voiceFailed("this machine has no on device recogniser for " + name
        + ", and recordfeedback will not send a recording of your session to a"
        + " server. Download the offline dictation voice in System Settings,"
        + " Keyboard, Dictation.")
      return
    }
    self.recognizer = recognizer
    running = true
    restartTask()

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
    request?.endAudio()
    task?.cancel()
    task = nil
    request = nil
  }

  private func restartTask() {
    request?.endAudio()
    task?.cancel()

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    // Commands have to land while the user is still looking at the thing they
    // asked about, so the partial sentence is acted on rather than the final
    // one that arrives when they stop talking.
    request.shouldReportPartialResults = true
    self.request = request
    firedThrough = 0
    taskStarted = Date()
    task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
      guard let self = self else { return }
      if error != nil {
        // A task that ended is replaced on the next pump rather than treated as
        // a failure. Apple ends them routinely, on silence above all.
        self.taskStarted = .distantPast
        return
      }
      guard let result = result else { return }
      self.consider(result.bestTranscription.formattedString)
    }
  }

  private func consider(_ heard: String) {
    let matches = grammar.matches(in: heard)
    guard !matches.isEmpty else { return }
    var fresh: [VoiceMatch] = []
    let now = Date()
    for one in matches where one.wordIndex >= firedThrough {
      // A revised partial can re-offer a command that was just acted on under a
      // different index. Two screenshots from one sentence is worse than a
      // missed repeat, and nobody says the same command twice in a second.
      if let last = lastFired[one.command], now.timeIntervalSince(last) < 1.5 { continue }
      lastFired[one.command] = now
      fresh.append(one)
      firedThrough = one.wordIndex + one.phrase.split(separator: " ").count
    }
    guard !fresh.isEmpty else { return }
    let offset = segmentOffset
    DispatchQueue.main.async { [weak self] in
      self?.delegate?.voiceHeard(fresh, at: offset)
    }
  }

  // Feeds every segment the recorder has finished since the last pass.
  private func pump() {
    guard running else { return }
    if Date().timeIntervalSince(taskStarted) > taskLife { restartTask() }

    let manager = FileManager.default
    guard let names = try? manager.contentsOfDirectory(atPath: directory) else { return }

    var finished: [(Date, String, Int)] = []
    var newest = Date.distantPast
    for name in names where name.hasSuffix(".pcm") {
      let path = directory + "/" + name
      guard let attrs = try? manager.attributesOfItem(atPath: path),
            let modified = attrs[.modificationDate] as? Date,
            let size = attrs[.size] as? Int, size > 0 else { continue }
      newest = max(newest, modified)
      finished.append((modified, path, size))
    }

    // The newest file is the one being written into right now, and half of a
    // second fed as though it were a whole one is a word cut in half. Every
    // other one is closed and complete.
    for (modified, path, _) in finished.sorted(by: { $0.0 < $1.0 })
    where modified > consumedThrough && modified < newest {
      guard let data = manager.contents(atPath: path), !data.isEmpty else { continue }
      feed(data)
      consumedThrough = modified
      // The recorder runs in real time, so when a segment was written is where
      // it sits in the recording. That is the same clock whisper timestamps
      // against, which is what lets these words be taken back out of it.
      segmentOffset = modified.timeIntervalSince(startReference)
    }
  }

  private func feed(_ data: Data) {
    guard let format = format else { return }
    let frames = AVAudioFrameCount(data.count / 2)
    guard frames > 0,
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
          let channel = buffer.int16ChannelData else { return }
    buffer.frameLength = frames
    data.withUnsafeBytes { raw in
      guard let base = raw.bindMemory(to: Int16.self).baseAddress else { return }
      channel[0].update(from: base, count: Int(frames))
    }
    request?.append(buffer)
  }
}
