import Cocoa

// One file, read by the overlay and by the CLI, so that the keys the terminal
// prints are the keys the overlay registered. It lives beside the sessions and
// not in UserDefaults, because a shell script cannot read a plist the way it
// can read JSON.
final class Settings {
  static let shared = Settings()

  private(set) var shortcuts: [Action: Shortcut] = [:]

  // Voice control is off until it is asked for. It needs a macOS permission of
  // its own, and a tool that starts listening for orders because it was
  // installed is not one a person can predict.
  private(set) var voiceEnabled = false
  private(set) var voiceTrigger = "let's"
  private(set) var voiceEscape = "not a command"
  private(set) var voicePhrases: [VoiceCommand: [String]] = [:]

  var path: String {
    let home = ProcessInfo.processInfo.environment["RF_HOME"]
      ?? NSHomeDirectory() + "/.recordfeedback"
    return home + "/settings.json"
  }

  private init() { load() }

  func shortcut(_ action: Action) -> Shortcut {
    shortcuts[action] ?? action.fallback
  }

  // The first action that already holds this combination, so the settings
  // window can refuse a binding rather than register a key that silently
  // shadows another one.
  func conflict(_ candidate: Shortcut, ignoring action: Action) -> Action? {
    Action.allCases.first { $0 != action && shortcut($0) == candidate }
  }

  func set(_ action: Action, to candidate: Shortcut) {
    shortcuts[action] = candidate
    save()
  }

  func reset() {
    shortcuts = [:]
    for action in Action.allCases { shortcuts[action] = action.fallback }
    save()
  }

  func grammar() -> VoiceGrammar {
    VoiceGrammar(trigger: voiceTrigger, escape: voiceEscape, phrases: phrasesOrDefaults())
  }

  func phrasesOrDefaults() -> [VoiceCommand: [String]] {
    var out: [VoiceCommand: [String]] = [:]
    for command in VoiceCommand.allCases {
      let saved = voicePhrases[command]
      out[command] = (saved?.isEmpty ?? true) ? command.defaultPhrases : saved!
    }
    return out
  }

  func setVoiceEnabled(_ on: Bool) {
    voiceEnabled = on
    save()
  }

  func setVoicePhrases(_ command: VoiceCommand, to list: [String]) {
    let cleaned = list.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    voicePhrases[command] = cleaned
    save()
  }

  func setVoiceWords(trigger: String, escape: String) {
    let wantedTrigger = trigger.trimmingCharacters(in: .whitespaces)
    let wantedEscape = escape.trimmingCharacters(in: .whitespaces)
    // An empty trigger would make every phrase in the table a command, so the
    // sentence "the rectangle is wrong" would change the tool. The old one
    // stands rather than the session being handed a grammar that fires on
    // ordinary speech.
    if !wantedTrigger.isEmpty { voiceTrigger = wantedTrigger }
    voiceEscape = wantedEscape
    save()
  }

  func resetVoicePhrases() {
    voicePhrases = [:]
    save()
  }

  func load() {
    shortcuts = [:]
    for action in Action.allCases { shortcuts[action] = action.fallback }
    voiceEnabled = false
    voiceTrigger = "let's"
    voiceEscape = "not a command"
    voicePhrases = [:]
    guard let data = FileManager.default.contents(atPath: path),
          let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return }
    // Each block is read on its own. Requiring the shortcuts block before
    // reading the voice one threw the whole file away when it was missing, and
    // a file with a voice block and no shortcuts is exactly what --voice writes
    // on a machine where this window has never saved anything.
    if let voice = root["voice"] as? [String: Any] {
      voiceEnabled = (voice["enabled"] as? Bool) ?? false
      if let word = voice["trigger"] as? String,
         !word.trimmingCharacters(in: .whitespaces).isEmpty {
        voiceTrigger = word
      }
      if let word = voice["escape"] as? String { voiceEscape = word }
      if let saved = voice["phrases"] as? [String: [String]] {
        for command in VoiceCommand.allCases {
          guard let list = saved[command.rawValue] else { continue }
          let cleaned = list.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
          if !cleaned.isEmpty { voicePhrases[command] = cleaned }
        }
      }
    }
    guard let bound = root["shortcuts"] as? [String: Any] else { return }
    for action in Action.allCases {
      guard let entry = bound[action.rawValue] as? [String: Any],
            let name = entry["key"] as? String,
            let code = Keys.code(for: name) else { continue }
      let modifiers = (entry["modifiers"] as? [String]) ?? []
      let candidate = Shortcut(keyCode: code,
                               option: modifiers.contains("option"),
                               shift: modifiers.contains("shift"),
                               command: modifiers.contains("command"),
                               control: modifiers.contains("control"))
      // A binding with no modifier is a letter taken away from every other
      // application on the machine, so it is not one this file may ask for.
      guard !candidate.isEmpty else { continue }
      shortcuts[action] = candidate
    }
  }

  func save() {
    var bound: [String: Any] = [:]
    for action in Action.allCases {
      let one = shortcut(action)
      var modifiers: [String] = []
      if one.control { modifiers.append("control") }
      if one.option { modifiers.append("option") }
      if one.shift { modifiers.append("shift") }
      if one.command { modifiers.append("command") }
      bound[action.rawValue] = ["key": Keys.name(for: one.keyCode),
                                "modifiers": modifiers,
                                "shows": one.display]
    }
    var phrases: [String: [String]] = [:]
    let resolved = phrasesOrDefaults()
    for command in VoiceCommand.allCases { phrases[command.rawValue] = resolved[command] }
    // Written out in full, defaults included, because the file is where a
    // person goes to see what they can say and a key that is not there is a
    // sentence they never find out about.
    let root: [String: Any] = [
      "shortcuts": bound,
      "voice": ["enabled": voiceEnabled,
                "trigger": voiceTrigger,
                "escape": voiceEscape,
                "phrases": phrases],
    ]
    guard let data = try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return }
    let folder = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: folder,
                                             withIntermediateDirectories: true)
    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
  }
}
