// What a hotkey is and what it is called. The names here are the settings
// file's vocabulary and the CLI's, so they are written once and never spelled
// out again.
import Cocoa
import Carbon.HIToolbox


// What a hotkey does. The name is what the settings file calls it and what the
// CLI prints, so it is written once here and never spelled out again.
enum Action: String, CaseIterable {
  case draw, screenshot, region, undo, clear, hide, listen, stop

  var title: String {
    switch self {
    case .draw: return "Draw"
    case .screenshot: return "Screenshot"
    case .region: return "Screenshot a region"
    case .undo: return "Undo the last mark"
    case .clear: return "Clear the marks"
    case .hide: return "Hide the marks"
    case .listen: return "Listen for spoken commands"
    case .stop: return "Stop the session"
    }
  }

  // Option and shift, because a session takes the keys away from every other
  // application for as long as it runs, and command pairs are what those
  // applications use. The cost is the characters option-shift types, which is
  // the trade the tool's own user made.
  var fallback: Shortcut {
    switch self {
    case .draw: return Shortcut(keyCode: kVK_ANSI_D)
    case .screenshot: return Shortcut(keyCode: kVK_ANSI_X)
    case .region: return Shortcut(keyCode: kVK_ANSI_R)
    case .undo: return Shortcut(keyCode: kVK_ANSI_Z)
    case .clear: return Shortcut(keyCode: kVK_ANSI_C)
    case .hide: return Shortcut(keyCode: kVK_ANSI_H)
    case .listen: return Shortcut(keyCode: kVK_ANSI_V)
    case .stop: return Shortcut(keyCode: kVK_ANSI_S)
    }
  }
}

struct Shortcut: Equatable {
  var keyCode: Int
  var option = true
  var shift = true
  var command = false
  var control = false

  // The Carbon modifier mask, which is not the AppKit one.
  var carbonModifiers: UInt32 {
    var mask: Int = 0
    if option { mask |= optionKey }
    if shift { mask |= shiftKey }
    if command { mask |= cmdKey }
    if control { mask |= controlKey }
    return UInt32(mask)
  }

  var isEmpty: Bool { !option && !shift && !command && !control }

  // What the palette and the menus show. The symbols are in the order macOS
  // writes them, so a key read here is a key recognised anywhere else.
  var display: String {
    var text = ""
    if control { text += "\u{2303}" }
    if option { text += "\u{2325}" }
    if shift { text += "\u{21E7}" }
    if command { text += "\u{2318}" }
    return text + Keys.name(for: keyCode)
  }

  // What a terminal prints, where the symbols are unreadable.
  var plain: String {
    var parts: [String] = []
    if control { parts.append("ctrl") }
    if option { parts.append("opt") }
    if shift { parts.append("shift") }
    if command { parts.append("cmd") }
    parts.append(Keys.name(for: keyCode))
    return parts.joined(separator: "-")
  }
}

// The keys a shortcut is allowed to use. Letters and digits only: this is the
// whole set the settings window can record, so a key with no name here cannot
// be bound and cannot end up in the file.
enum Keys {
  static let table: [(Int, String)] = [
    (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"),
    (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"),
    (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
    (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"), (kVK_ANSI_P, "P"),
    (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
    (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
    (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z"),
    (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
    (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"),
    (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
  ]

  static func name(for keyCode: Int) -> String {
    table.first { $0.0 == keyCode }?.1 ?? "?"
  }

  static func code(for name: String) -> Int? {
    table.first { $0.1 == name.uppercased() }?.0
  }
}
