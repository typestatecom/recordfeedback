import Cocoa

// One file, read by the overlay and by the CLI, so that the keys the terminal
// prints are the keys the overlay registered. It lives beside the sessions and
// not in UserDefaults, because a shell script cannot read a plist the way it
// can read JSON.
final class Settings {
  static let shared = Settings()

  private(set) var shortcuts: [Action: Shortcut] = [:]

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

  func load() {
    shortcuts = [:]
    for action in Action.allCases { shortcuts[action] = action.fallback }
    guard let data = FileManager.default.contents(atPath: path),
          let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let bound = root["shortcuts"] as? [String: Any] else { return }
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
    let root: [String: Any] = ["shortcuts": bound]
    guard let data = try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return }
    let folder = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: folder,
                                             withIntermediateDirectories: true)
    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
  }
}
