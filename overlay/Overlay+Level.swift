// Whether the recorder is hearing anything, read from the recorder's own
// output. The overlay does not open the microphone to ask: a second capture can
// be healthy while the one being written to disk is silent, and it is the one
// on disk that gets transcribed.
import Foundation

final class InputLevel {
  // Written by the recorder's segment output, one second of 16 kHz mono s16le
  // per file, rotated in place.
  private let directory: String
  private let deadBelow: Double
  private let graceSeconds: TimeInterval

  // Nothing until the recorder closes its first segment. Not knowing is its own
  // answer and must never be drawn as silence.
  private(set) var dbfs: Double?
  private(set) var deadSince: Date?

  init(session: String) {
    directory = session + "/levels"
    // The CLI decides this and hands it over, so the number that refuses a
    // session at start and the number that raises the alarm mid session cannot
    // drift apart.
    let environment = ProcessInfo.processInfo.environment
    deadBelow = environment["RF_DEAD_DBFS"].flatMap(Double.init) ?? -85
    graceSeconds = environment["RF_DEAD_SECONDS"].flatMap(Double.init) ?? 4
  }

  var reported: Bool { dbfs != nil }

  var isDead: Bool {
    guard let dbfs = dbfs else { return false }
    return dbfs <= deadBelow
  }

  // The alarm waits out a grace period, because one lost second is a hiccup and
  // four in a row is a microphone that is not there. A room with nobody talking
  // in it still carries a noise floor far above the threshold, so a pause in
  // the conversation never reaches this.
  var alarming: Bool {
    guard let since = deadSince else { return false }
    return Date().timeIntervalSince(since) >= graceSeconds
  }

  // Where the needle sits, from the quietest room to a raised voice. Speech
  // lands around a third to two thirds of the way up, which leaves the top of
  // the scale for the moment a person leans into the microphone.
  var meter: Double {
    guard let dbfs = dbfs, dbfs.isFinite else { return 0 }
    return min(1, max(0, (dbfs + 65) / 50))
  }

  var reading: String {
    guard let dbfs = dbfs else { return "no reading yet" }
    return dbfs.isFinite ? String(format: "%.0f dBFS", dbfs) : "-inf dBFS"
  }

  func poll() {
    guard let measured = measure() else {
      // Every segment was caught mid write, which says nothing about the
      // microphone. The last real reading stands rather than a gap being
      // reported as silence.
      return
    }
    dbfs = measured
    if measured <= deadBelow {
      if deadSince == nil { deadSince = Date() }
    } else {
      deadSince = nil
    }
  }

  // The loudest recent second. The loudest and not the latest, because a person
  // draws breath mid sentence and a window that lands in the pause is silent
  // for a reason that has nothing wrong with it.
  private func measure() -> Double? {
    let manager = FileManager.default
    guard let names = try? manager.contentsOfDirectory(atPath: directory) else { return nil }
    let now = Date()
    var best = 0.0
    var seen = false

    for name in names where name.hasSuffix(".pcm") {
      let path = directory + "/" + name
      guard let attrs = try? manager.attributesOfItem(atPath: path),
            let modified = attrs[.modificationDate] as? Date,
            let size = attrs[.size] as? Int else { continue }
      // Segments are overwritten in place under segment_wrap, so age and not
      // the name is what says whether one is still evidence. A recorder that
      // died leaves loud segments behind and they must not read as alive.
      if now.timeIntervalSince(modified) > 8 { continue }
      // Below an eighth of a second the file is the one being written right
      // now and holds a sliver of a second, which is not a measurement.
      if size < 4000 { continue }
      guard let data = manager.contents(atPath: path), data.count >= 4000 else { continue }
      seen = true
      best = max(best, Self.rms(of: data))
    }

    guard seen else { return nil }
    // Digital silence has no logarithm. Negative infinity is the honest answer
    // and it compares correctly against the threshold.
    return best == 0 ? -Double.infinity : 20 * log10(best / 32768)
  }

  private static func rms(of data: Data) -> Double {
    let count = data.count / 2
    guard count > 0 else { return 0 }
    var total = 0.0
    data.withUnsafeBytes { raw in
      let samples = raw.bindMemory(to: Int16.self)
      for index in 0..<count {
        let value = Double(Int16(littleEndian: samples[index]))
        total += value * value
      }
    }
    return (total / Double(count)).squareRoot()
  }
}

extension Overlay {
  // The words the alarm says. A red row that names nothing is a row the user
  // stares at while the session goes on recording nothing.
  var silenceAlarmText: String {
    "NO SOUND, check the microphone input"
  }
}
