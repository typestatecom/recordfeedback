// The annotation overlay. The CLI launches one of these per session with
// RF_SESSION set, and it belongs to that session for its whole life. It never
// reads ~/.recordfeedback/current, because a session that ended is not this
// process's business.
import Cocoa
import Carbon.HIToolbox

// -------------------------------------------------------------- the settings

// What a hotkey does. The name is what the settings file calls it and what the
// CLI prints, so it is written once here and never spelled out again.
enum Action: String, CaseIterable {
  case draw, screenshot, region, undo, clear, hide, stop

  var title: String {
    switch self {
    case .draw: return "Draw"
    case .screenshot: return "Screenshot"
    case .region: return "Screenshot a region"
    case .undo: return "Undo the last mark"
    case .clear: return "Clear the marks"
    case .hide: return "Hide the marks"
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

// ---------------------------------------------------------------- the model

enum Tool: Int, CaseIterable {
  case pen, arrow, rect, highlighter, text

  var letter: String {
    switch self {
    case .pen: return "P"
    case .arrow: return "A"
    case .rect: return "R"
    case .highlighter: return "H"
    case .text: return "T"
    }
  }

  var name: String {
    switch self {
    case .pen: return "pen"
    case .arrow: return "arrow"
    case .rect: return "rectangle"
    case .highlighter: return "highlighter"
    case .text: return "text"
    }
  }

  // The highlighter is useless at a pen's width and a pen is useless at the
  // highlighter's, so the width belongs to the tool and not to the session.
  var defaultWidth: CGFloat {
    switch self {
    case .highlighter: return 24
    case .text: return 6
    default: return 4
    }
  }
}

struct Shape {
  var tool: Tool
  var colorIndex: Int
  var width: CGFloat
  var screen: Int
  var points: [NSPoint]
  var text: String = ""
}

// Defined in sRGB rather than by name so that what is drawn is the same colour
// on every display, which is what makes the pixel test able to assert one.
let palette: [NSColor] = [
  NSColor(srgbRed: 1.00, green: 0.00, blue: 0.00, alpha: 1),
  NSColor(srgbRed: 1.00, green: 0.55, blue: 0.00, alpha: 1),
  NSColor(srgbRed: 1.00, green: 0.90, blue: 0.00, alpha: 1),
  NSColor(srgbRed: 0.15, green: 0.80, blue: 0.25, alpha: 1),
  NSColor(srgbRed: 0.00, green: 0.48, blue: 1.00, alpha: 1),
  NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
]

// ------------------------------------------------------------- global keys

// Carbon hot keys need no Accessibility permission and a CGEventTap does, so a
// session starts without the user being sent to System Settings.
final class Hotkeys {
  static let shared = Hotkeys()
  private var handlers: [UInt32: () -> Void] = [:]
  private var refs: [EventHotKeyRef] = []
  private var nextID: UInt32 = 1

  func install() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                             eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
      var id = EventHotKeyID()
      GetEventParameter(event, EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID), nil,
                        MemoryLayout<EventHotKeyID>.size, nil, &id)
      Hotkeys.shared.fire(id.id)
      return noErr
    }, 1, &spec, nil, nil)
  }

  func register(_ key: Shortcut, handler: @escaping () -> Void) {
    let id = nextID
    nextID += 1
    var ref: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(signature: OSType(0x52464244), id: id)
    let status = RegisterEventHotKey(UInt32(key.keyCode), key.carbonModifiers,
                                     hotKeyID, GetApplicationEventTarget(), 0, &ref)
    if status != noErr || ref == nil {
      warn("could not register \(key.plain), another application already owns it.")
      warn("  fix: quit whatever owns \(key.plain), or change the key in the")
      warn("  overlay's settings, which the menu bar item opens.")
      return
    }
    handlers[id] = handler
    refs.append(ref!)
  }

  // A rebound key has to stop firing the thing it used to do, and Carbon keeps
  // the old registration alive until it is told otherwise.
  func unregisterAll() {
    for ref in refs { UnregisterEventHotKey(ref) }
    refs.removeAll()
    handlers.removeAll()
  }

  private func fire(_ id: UInt32) { handlers[id]?() }
}

func warn(_ message: String) {
  FileHandle.standardError.write(("rf-overlay: " + message + "\n").data(using: .utf8)!)
}

// -------------------------------------------------------------- the windows

final class MarkWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

final class MarkView: NSView {
  var index = 0
  weak var owner: Overlay?

  override var isOpaque: Bool { false }
  override var acceptsFirstResponder: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    owner?.drawMarks(screen: index, in: bounds)
  }

  override func mouseDown(with event: NSEvent) {
    owner?.beginStroke(at: convert(event.locationInWindow, from: nil), screen: index)
  }

  override func mouseDragged(with event: NSEvent) {
    owner?.extendStroke(to: convert(event.locationInWindow, from: nil))
  }

  override func mouseUp(with event: NSEvent) {
    owner?.endStroke(at: convert(event.locationInWindow, from: nil))
  }
}

// A non activating panel, so clicking a tool does not take the keyboard away
// from the editor the user is talking about.
final class PaletteWindow: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

final class PaletteView: NSView, NSViewToolTipOwner {
  weak var owner: Overlay?
  private var hits: [(NSRect, () -> Void)] = []
  private var tips: [(NSRect, String)] = []
  private var installedTips: [(NSRect, String)] = []
  private var dragOrigin: NSPoint?

  override var isFlipped: Bool { false }

  // The row sits over the work for the whole session. It steps back while the
  // user is talking and comes forward when they reach for it.
  private(set) var pointerInside = false

  override func draw(_ dirtyRect: NSRect) {
    owner?.drawPalette(in: self)
    syncTips()
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
  }

  override func mouseEntered(with event: NSEvent) {
    pointerInside = true
    owner?.paletteAttentionChanged()
  }

  override func mouseExited(with event: NSEvent) {
    pointerInside = false
    owner?.paletteAttentionChanged()
  }

  func clearHits() { hits.removeAll() }

  func addHit(_ rect: NSRect, _ action: @escaping () -> Void) {
    hits.append((rect, action))
  }

  // The rectangles the drawing code actually registered, which is the only
  // honest source for a test asking whether two controls sit on top of one
  // another. A layout read off the source is a layout nobody laid out.
  var hitRects: [NSRect] { hits.map { $0.0 } }

  // The label a control names itself with when the pointer rests on it. A
  // control the row never names is a control only its author can find.
  var tipTexts: [String] { tips.map { $0.1 } }

  // Where a named control ended up. The probe asks for controls by name
  // because what changes between the two layouts is how many sit between them.
  private(set) var namedRects: [String: NSRect] = [:]

  func clearNames() { namedRects.removeAll() }

  // Where the key hints were actually drawn. They are text under a button
  // rather than inside it, so a hint wider than its own control runs into its
  // neighbour's, and neither of them can be read.
  private(set) var hintRects: [NSRect] = []

  func clearHints() { hintRects.removeAll() }

  func addHint(_ rect: NSRect) { hintRects.append(rect) }

  func name(_ key: String, _ rect: NSRect) { namedRects[key] = rect }

  func clearTips() { tips.removeAll() }

  func addTip(_ rect: NSRect, _ text: String) { tips.append((rect, text)) }

  // The palette redraws twice a second to pulse the dot, and reinstalling the
  // tips on every one of those frames restarts the hover timer, so a tip never
  // gets to appear. They are only reinstalled when the row actually changes.
  private func syncTips() {
    let same = installedTips.count == tips.count
      && !zip(installedTips, tips).contains { pair in
        pair.0.0 != pair.1.0 || pair.0.1 != pair.1.1
      }
    guard !same else { return }
    removeAllToolTips()
    for (rect, _) in tips { addToolTip(rect, owner: self, userData: nil) }
    installedTips = tips
  }

  func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
            userData: UnsafeMutableRawPointer?) -> String {
    for (rect, text) in tips where rect.contains(point) { return text }
    return ""
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    for (rect, action) in hits where rect.contains(point) {
      action()
      return
    }
    // Not on a control, so this is the grab handle for the whole panel.
    dragOrigin = event.locationInWindow
  }

  override func mouseDragged(with event: NSEvent) {
    guard let grab = dragOrigin, let window = window else { return }
    let onScreen = event.locationInWindow
    var frame = window.frame
    frame.origin.x += onScreen.x - grab.x
    frame.origin.y += onScreen.y - grab.y
    window.setFrameOrigin(frame.origin)
  }

  override func mouseUp(with event: NSEvent) {
    guard dragOrigin != nil, let window = window else { return }
    dragOrigin = nil
    owner?.rememberPalettePosition(window.frame.origin)
  }
}

// ------------------------------------------------------------ the settings UI

// A session takes seven key combinations away from every other application on
// the machine for as long as it runs, so which seven has to be the user's
// choice and not the author's. Recording a key rather than typing its name is
// the only way to bind one without a table of key codes in a README.
final class SettingsWindow: NSWindowController {
  private weak var overlay: Overlay?
  private var rows: [Action: NSButton] = [:]
  private var notes: [Action: NSTextField] = [:]
  private var recording: Action?
  private var monitor: Any?

  init(overlay: Overlay) {
    self.overlay = overlay
    let size = NSSize(width: 460, height: CGFloat(Action.allCases.count) * 40 + 132)
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable], backing: .buffered,
                          defer: false)
    window.title = "recordfeedback shortcuts"
    window.isReleasedWhenClosed = false
    super.init(window: window)
    build(in: window)
  }

  required init?(coder: NSCoder) { fatalError("not loaded from a nib") }

  func show() {
    refresh()
    window?.center()
    window?.makeKeyAndOrderFront(nil)
  }

  private func build(in window: NSWindow) {
    guard let content = window.contentView else { return }
    var y = window.frame.height - 62

    let heading = NSTextField(labelWithString:
      "These keys belong to recordfeedback for as long as a session is"
      + " running, and to nothing else.")
    heading.frame = NSRect(x: 20, y: y + 14, width: 420, height: 32)
    heading.font = NSFont.systemFont(ofSize: 11)
    heading.textColor = .secondaryLabelColor
    heading.lineBreakMode = .byWordWrapping
    heading.maximumNumberOfLines = 2
    content.addSubview(heading)

    for action in Action.allCases {
      y -= 40
      let label = NSTextField(labelWithString: action.title)
      label.frame = NSRect(x: 20, y: y + 6, width: 200, height: 18)
      label.font = NSFont.systemFont(ofSize: 13)
      content.addSubview(label)

      let button = NSButton(title: "", target: self, action: #selector(startRecording(_:)))
      button.frame = NSRect(x: 224, y: y, width: 104, height: 28)
      button.bezelStyle = .rounded
      button.tag = Action.allCases.firstIndex(of: action) ?? 0
      content.addSubview(button)
      rows[action] = button

      let note = NSTextField(labelWithString: "")
      note.frame = NSRect(x: 334, y: y + 6, width: 108, height: 18)
      note.font = NSFont.systemFont(ofSize: 10)
      note.textColor = .systemRed
      content.addSubview(note)
      notes[action] = note
    }

    let reset = NSButton(title: "Restore defaults", target: self,
                         action: #selector(restoreDefaults))
    reset.frame = NSRect(x: 20, y: 20, width: 150, height: 30)
    reset.bezelStyle = .rounded
    content.addSubview(reset)

    let where_ = NSTextField(labelWithString: Settings.shared.path)
    where_.frame = NSRect(x: 180, y: 26, width: 262, height: 16)
    where_.font = NSFont.systemFont(ofSize: 9)
    where_.textColor = .tertiaryLabelColor
    where_.lineBreakMode = .byTruncatingHead
    content.addSubview(where_)
  }

  private func refresh() {
    for (action, button) in rows {
      button.title = recording == action ? "Press keys" : Settings.shared.shortcut(action).display
    }
  }

  @objc private func startRecording(_ sender: NSButton) {
    guard sender.tag < Action.allCases.count else { return }
    let action = Action.allCases[sender.tag]
    stopRecording()
    recording = action
    notes[action]?.stringValue = ""
    refresh()

    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.captured(event)
      return nil
    }
  }

  private func captured(_ event: NSEvent) {
    guard let action = recording else { return }
    let flags = event.modifierFlags
    if Int(event.keyCode) == kVK_Escape && !flags.contains(.option) {
      stopRecording()
      refresh()
      return
    }
    let candidate = Shortcut(keyCode: Int(event.keyCode),
                             option: flags.contains(.option),
                             shift: flags.contains(.shift),
                             command: flags.contains(.command),
                             control: flags.contains(.control))

    // A key with no name here cannot be registered, and a key with no modifier
    // would be taken away from every application on the machine.
    if Keys.name(for: candidate.keyCode) == "?" {
      notes[action]?.stringValue = "letters and digits"
    } else if candidate.isEmpty {
      notes[action]?.stringValue = "needs a modifier"
    } else if let clash = Settings.shared.conflict(candidate, ignoring: action) {
      notes[action]?.stringValue = "held by " + clash.rawValue
    } else {
      Settings.shared.set(action, to: candidate)
      notes[action]?.stringValue = ""
      overlay?.reinstallHotkeys()
      stopRecording()
    }
    refresh()
  }

  private func stopRecording() {
    if let monitor = monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    recording = nil
  }

  @objc private func restoreDefaults() {
    Settings.shared.reset()
    for note in notes.values { note.stringValue = "" }
    overlay?.reinstallHotkeys()
    refresh()
  }
}

// ----------------------------------------------------------- the controller

final class Overlay: NSObject, NSApplicationDelegate {
  let session = ProcessInfo.processInfo.environment["RF_SESSION"] ?? ""
  private var markWindows: [MarkWindow] = []
  private var markViews: [MarkView] = []
  private var paletteWindow: PaletteWindow?
  private var paletteView: PaletteView?

  private var shapes: [Shape] = []
  private var drawing = false
  private var marksHidden = false
  private var tool: Tool = .pen
  private var colorIndex = 0
  private var widths: [Tool: CGFloat] = {
    var w: [Tool: CGFloat] = [:]
    for t in Tool.allCases { w[t] = t.defaultWidth }
    return w
  }()
  private var editing: Int?
  private var startedAt = Date()
  private var pulseOn = true
  private var shots = 0
  private var shutterFlash = false
  private var keyMonitor: Any?
  private var statusItem: NSStatusItem?
  private var settingsWindow: SettingsWindow?
  // Set the instant Stop is pressed, so the row and the menu bar can say the
  // click landed before anything downstream has had time to answer it.
  private(set) var stopping = false
  private var stopRequestedAt = Date()

  private var width: CGFloat {
    get { widths[tool] ?? tool.defaultWidth }
    set { widths[tool] = max(1, min(64, newValue)) }
  }

  private var inbox: String { session + "/inbox" }

  // MARK: lifecycle

  func applicationDidFinishLaunching(_ notification: Notification) {
    if session.isEmpty {
      warn("RF_SESSION is not set, so there is no session to draw for.")
      warn("  fix: start the overlay through: recordfeedback start")
      exit(2)
    }
    try? FileManager.default.createDirectory(atPath: inbox,
                                             withIntermediateDirectories: true)
    startedAt = sessionStart()
    shots = countShots()

    buildWindows()
    buildPalette()
    installHotkeys()

    NotificationCenter.default.addObserver(
      self, selector: #selector(screensChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)

    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      self.pulseOn.toggle()
      self.paletteView?.needsDisplay = true
      self.refreshStatusItem()
    }

    // A stuck overlay swallows clicks and cannot be debugged with the mouse, so
    // it always has an end even if nothing ever stops it.
    Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: false) { _ in
      warn("four hours is the limit for one session, quitting.")
      NSApp.terminate(nil)
    }

    if ProcessInfo.processInfo.environment["RF_OVERLAY_SELFTEST"] == "1" {
      drawSelfTestStroke()
    }
    if ProcessInfo.processInfo.environment["RF_OVERLAY_SELFTEST"] == "palette" {
      probePalette()
    }
    if ProcessInfo.processInfo.environment["RF_OVERLAY_SELFTEST"] == "tools" {
      probeTools()
    }
    if ProcessInfo.processInfo.environment["RF_OVERLAY_SELFTEST"] == "capture" {
      probeCapture()
    }
    if ProcessInfo.processInfo.environment["RF_OVERLAY_SELFTEST"] == "layout" {
      probeLayout()
    }
    // Presses the stop button, with nothing at all watching for the answer.
    if ProcessInfo.processInfo.environment["RF_OVERLAY_SELFTEST"] == "rescue" {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.stopSession() }
    }
    if ProcessInfo.processInfo.environment["RF_OVERLAY_SELFTEST"] == "leave" {
      probeLeave()
    }
    if ProcessInfo.processInfo.environment["RF_OVERLAY_SELFTEST"] == "width" {
      probeWidth()
    }
    if ProcessInfo.processInfo.environment["RF_OVERLAY_SELFTEST"] == "arrow" {
      probeArrow()
    }
    buildStatusItem()

    // Written last, so a test that waits for it knows the windows are up.
    FileManager.default.createFile(atPath: session + "/overlay.ready", contents: nil)
  }

  private func sessionStart() -> Date {
    let path = session + "/start.ref"
    if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
       let date = attrs[.modificationDate] as? Date {
      return date
    }
    return Date()
  }

  @objc private func screensChanged() {
    // Shapes are held in the coordinates of the screen they were drawn on, so
    // rebuilding the windows keeps every mark where the user put it.
    buildWindows()
  }

  private func buildWindows() {
    for window in markWindows { window.orderOut(nil) }
    markWindows.removeAll()
    markViews.removeAll()

    for (index, screen) in NSScreen.screens.enumerated() {
      let window = MarkWindow(contentRect: screen.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
      window.setFrame(screen.frame, display: true)
      window.backgroundColor = .clear
      window.isOpaque = false
      window.hasShadow = false
      window.level = .statusBar
      window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
      window.ignoresMouseEvents = !drawing
      // Leaving draw mode hides the application to give the keyboard back, and
      // a mark window that hides with it takes every mark the user drew off the
      // screen. Putting the pen down is not rubbing the drawing out, and the
      // shutter frame is drawn here too, so hiding these also leaves a capture
      // taken outside draw mode with no confirmation at all.
      window.canHide = false

      let view = MarkView(frame: NSRect(origin: .zero, size: screen.frame.size))
      view.index = index
      view.owner = self
      window.contentView = view
      window.orderFrontRegardless()

      markWindows.append(window)
      markViews.append(view)
    }
    redrawMarks()
  }

  // The controls that exist in both rows, and so have to sit still between
  // them. Draw mode is entered by clicking in this row.
  let anchoredControls = ["shots", "region", "camera", "stop"]

  private let paletteHeight: CGFloat = 52
  private var paletteWidth: CGFloat { drawing ? 894 : 446 }

  private func buildPalette() {
    // The idle width. The tools, the colours and the width control belong to
    // draw mode, and the row grows leftwards to take them: the right hand end
    // is the anchor, so Stop and the capture buttons never move.
    let size = NSSize(width: paletteWidth, height: paletteHeight)
    let window = PaletteWindow(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = true
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    // Set before the level, because this puts the panel back down at the
    // floating level and would undo it.
    window.isFloatingPanel = true
    // A level above the mark windows and not merely in front of them. Entering
    // draw mode makes a mark window key, and from underneath the palette every
    // press of Stop draws a dot instead, which leaves a key the only way out.
    window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    // Leaving draw mode hides the application to give the keyboard back, and a
    // hidden palette takes the clock and the Stop button off the screen for the
    // rest of the session.
    window.canHide = false
    // The only window that stays clickable while idle. The full screen mark
    // windows stay click through, so everything under them is untouched.
    window.ignoresMouseEvents = false

    let view = PaletteView(frame: NSRect(origin: .zero, size: size))
    view.owner = self
    window.contentView = view
    window.setFrameOrigin(paletteOrigin(for: size))
    window.orderFrontRegardless()

    paletteWindow = window
    paletteView = view
  }

  // The saved position is the right hand end and not the left, because that is
  // the end that stays put when the row changes width.
  private func paletteOrigin(for size: NSSize) -> NSPoint {
    let defaults = UserDefaults.standard
    if let saved = defaults.string(forKey: "palette.anchor") {
      let anchor = NSPointFromString(saved)
      for screen in NSScreen.screens where screen.frame.contains(anchor) {
        let limit = screen.frame
        // Room for the wide row, so that entering draw mode never runs the
        // left hand end off the edge of the screen.
        let right = min(max(anchor.x, limit.minX + 894), limit.maxX)
        return NSPoint(x: right - size.width,
                       y: min(anchor.y, limit.maxY - size.height))
      }
    }
    guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
    return NSPoint(x: screen.frame.midX - size.width / 2,
                   y: screen.frame.minY + 40)
  }

  func rememberPalettePosition(_ origin: NSPoint) {
    let anchor = NSPoint(x: origin.x + (paletteWindow?.frame.width ?? 0), y: origin.y)
    UserDefaults.standard.set(NSStringFromPoint(anchor), forKey: "palette.anchor")
  }

  // Growing the row leftwards, so the end the user's cursor is at stays where
  // it is. Called whenever the set of controls changes.
  private func resizePalette() {
    guard let window = paletteWindow else { return }
    let right = window.frame.maxX
    let size = NSSize(width: paletteWidth, height: paletteHeight)
    window.setFrame(NSRect(x: right - size.width, y: window.frame.minY,
                           width: size.width, height: size.height),
                    display: true)
    paletteView?.frame = NSRect(origin: .zero, size: size)
    paletteView?.needsDisplay = true
  }

  // Full strength while the pen is down or the pointer is on the row, and a
  // step back the rest of the time: the row is over the work for the whole
  // session and most of that session is spent talking, not clicking.
  func paletteAttentionChanged() {
    let wanted = drawing || (paletteView?.pointerInside ?? false) ? 1.0 : 0.7
    paletteWindow?.animator().alphaValue = wanted
  }

  private func installHotkeys() {
    Hotkeys.shared.install()
    reinstallHotkeys()
  }

  // Called again whenever the settings change, so a rebound key takes effect
  // without ending the session the user is in the middle of.
  func reinstallHotkeys() {
    Hotkeys.shared.unregisterAll()
    for action in Action.allCases {
      let key = Settings.shared.shortcut(action)
      Hotkeys.shared.register(key) { [weak self] in self?.perform(action) }
    }
    paletteView?.needsDisplay = true
    rebuildMenu()
  }

  func perform(_ action: Action) {
    switch action {
    case .draw: setDrawing(!drawing)
    case .screenshot: capture(region: false)
    case .region: capture(region: true)
    case .undo: undo()
    case .clear: clear()
    case .hide: toggleHidden()
    case .stop: stopSession()
    }
  }

  // MARK: the menu bar

  // The palette can be dragged off a screen that was unplugged, covered by a
  // full screen application, or left behind by an overlay whose CLI died. The
  // menu bar is the one place on macOS that none of that can reach, so it
  // carries the proof that recording is live and, more importantly, a way out.
  private func buildStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.imagePosition = .noImage
    statusItem = item
    rebuildMenu()
    refreshStatusItem()
    // The bar lays its items out from the right, and on a display with a notch
    // it will place one in the hole rather than refuse it. The item is then
    // drawn, clickable and invisible, which is worse than absent, so the one
    // thing the tool can do is say which of those happened.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.checkStatusItemVisible() }
  }

  private func checkStatusItemVisible() {
    guard let bar = statusItem?.button?.window else {
      warn("the menu bar had no room for the recording indicator.")
      warn("  fix: remove an icon from the menu bar, then start again.")
      warn("  the palette on the screen and recordfeedback stop both still work.")
      return
    }
    guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(bar.frame) }),
          let left = screen.auxiliaryTopLeftArea,
          let right = screen.auxiliaryTopRightArea else { return }
    guard bar.frame.maxX > left.maxX && bar.frame.minX < right.minX else { return }
    warn("the recording indicator landed behind this display's notch, so it is"
         + " there but cannot be seen.")
    warn("  the menu bar is full: the strips beside the notch are"
         + " \(Int(left.width)) and \(Int(right.width)) points wide and both are taken.")
    warn("  fix: remove an icon from the menu bar, or hold command and drag one"
         + " off it, then start the session again.")
    warn("  the palette on the screen and recordfeedback stop both still work.")
  }

  private func refreshStatusItem() {
    guard let button = statusItem?.button else { return }
    let elapsed = Int(Date().timeIntervalSince(startedAt))
    let clock = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    let text = NSMutableAttributedString()
    let dot = NSAttributedString(
      string: stopping ? "\u{25A0} " : "\u{25CF} ",
      attributes: [.foregroundColor: stopping
                     ? NSColor.secondaryLabelColor
                     : NSColor(srgbRed: 0.90, green: 0.20, blue: 0.17,
                               alpha: pulseOn ? 1.0 : 0.35),
                   .font: NSFont.systemFont(ofSize: 11)])
    text.append(dot)
    text.append(NSAttributedString(
      string: stopping ? "stopping" : clock,
      attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]))
    button.attributedTitle = text
    button.toolTip = stopping
      ? "recordfeedback is finishing the session"
      : "recordfeedback is recording. \(shots) screenshot"
        + (shots == 1 ? "" : "s") + " so far."
  }

  func rebuildMenu() {
    guard let item = statusItem else { return }
    let menu = NSMenu()
    menu.autoenablesItems = false

    let header = NSMenuItem(title: "Recording this session", action: nil, keyEquivalent: "")
    header.isEnabled = false
    menu.addItem(header)
    menu.addItem(.separator())

    for action in [Action.draw, .screenshot, .region, .undo, .clear, .hide] {
      menu.addItem(menuItem(action))
    }

    menu.addItem(.separator())
    let settings = NSMenuItem(title: "Shortcuts and settings...",
                              action: #selector(openSettings), keyEquivalent: "")
    settings.target = self
    menu.addItem(settings)

    menu.addItem(.separator())
    menu.addItem(menuItem(.stop))

    // The way out of an overlay whose session nobody is listening to any more.
    // It says what it leaves behind, because quitting the window is not the
    // same as ending the recording and the user has to know which one they got.
    let quit = NSMenuItem(title: "Force quit the overlay",
                          action: #selector(forceQuit), keyEquivalent: "")
    quit.target = self
    quit.toolTip = "Closes this window only. The recording keeps running, and"
      + " recordfeedback stop still finishes the session with nothing lost."
    menu.addItem(quit)

    item.menu = menu
  }

  // The shortcut is written into the title rather than bound as a key
  // equivalent, because the same combination is already a global hotkey and
  // binding it twice fires it twice while the overlay is frontmost.
  private func menuItem(_ action: Action) -> NSMenuItem {
    let key = Settings.shared.shortcut(action)
    let item = NSMenuItem(title: action.title + "  (" + key.display + ")",
                          action: #selector(menuAction(_:)), keyEquivalent: "")
    item.target = self
    item.representedObject = action.rawValue
    if action == .draw { item.state = drawing ? .on : .off }
    if action == .hide { item.state = marksHidden ? .on : .off }
    return item
  }

  @objc private func menuAction(_ sender: NSMenuItem) {
    guard let raw = sender.representedObject as? String,
          let action = Action(rawValue: raw) else { return }
    perform(action)
    rebuildMenu()
  }

  @objc private func forceQuit() {
    warn("force quit from the menu bar. The recording is still running.")
    warn("  finish the session with: recordfeedback stop")
    NSApp.terminate(nil)
  }

  @objc func openSettings() {
    if settingsWindow == nil {
      settingsWindow = SettingsWindow(overlay: self)
    }
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.show()
  }

  // MARK: modes

  private func setDrawing(_ on: Bool) {
    if !on { commitText() }
    drawing = on
    for window in markWindows { window.ignoresMouseEvents = !on }
    if on {
      NSApp.activate(ignoringOtherApps: true)
      markWindows.first?.makeKeyAndOrderFront(nil)
      if keyMonitor == nil {
        // A local monitor catches the plain tool keys whichever screen's window
        // happens to be key, which a per view keyDown does not.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
          [weak self] event in
          self?.handleKey(event) == true ? nil : event
        }
      }
    } else {
      if let monitor = keyMonitor {
        NSEvent.removeMonitor(monitor)
        keyMonitor = nil
      }
      NSApp.hide(nil)
    }
    resizePalette()
    paletteAttentionChanged()
  }

  // The palette's own way out, so that leaving draw mode is never only a key.
  private func leaveDrawing() { setDrawing(false) }

  private func toggleHidden() {
    marksHidden.toggle()
    redrawMarks()
    paletteView?.needsDisplay = true
  }

  // The tool is the control a person reaches for first, so it is also the one
  // they press to put the pen down. Without this the only way out is a key the
  // palette does not name, while the overlay is holding every click on screen.
  private func select(_ newTool: Tool) {
    commitText()
    if drawing && newTool == tool {
      setDrawing(false)
      return
    }
    tool = newTool
    if !drawing { setDrawing(true) }
    paletteView?.needsDisplay = true
  }

  // MARK: shapes

  func beginStroke(at point: NSPoint, screen: Int) {
    guard drawing else { return }
    if tool == .text {
      commitText()
      shapes.append(Shape(tool: .text, colorIndex: colorIndex, width: width,
                          screen: screen, points: [point], text: ""))
      editing = shapes.count - 1
      redrawMarks()
      paletteView?.needsDisplay = true
      return
    }
    shapes.append(Shape(tool: tool, colorIndex: colorIndex, width: width,
                        screen: screen, points: [point]))
    redrawMarks()
  }

  func extendStroke(to point: NSPoint) {
    guard drawing, editing == nil, var shape = shapes.last else { return }
    switch shape.tool {
    case .pen, .highlighter:
      shape.points.append(point)
    case .arrow, .rect:
      // Two points only, and the second one follows the mouse.
      if shape.points.count < 2 { shape.points.append(point) } else { shape.points[1] = point }
    case .text:
      return
    }
    shapes[shapes.count - 1] = shape
    redrawMarks()
  }

  func endStroke(at point: NSPoint) {
    guard drawing, editing == nil, let shape = shapes.last else { return }
    // A click with no drag leaves a one point shape that draws nothing.
    if shape.points.count < 2 && shape.tool != .text {
      if shape.tool == .pen || shape.tool == .highlighter {
        shapes[shapes.count - 1].points.append(point)
      } else {
        shapes.removeLast()
      }
    }
    redrawMarks()
  }

  private func undo() {
    if editing != nil { commitText(); return }
    guard !shapes.isEmpty else { return }
    shapes.removeLast()
    redrawMarks()
  }

  private func clear() {
    editing = nil
    shapes.removeAll()
    redrawMarks()
  }

  private func commitText() {
    guard let index = editing else { return }
    editing = nil
    if index < shapes.count && shapes[index].text.isEmpty {
      shapes.remove(at: index)
    }
    redrawMarks()
    paletteView?.needsDisplay = true
  }

  private func redrawMarks() {
    for view in markViews { view.needsDisplay = true }
  }

  // MARK: keys inside draw mode

  private func handleKey(_ event: NSEvent) -> Bool {
    guard drawing else { return false }
    let code = Int(event.keyCode)

    if editing != nil {
      // The one place in the overlay where a plain letter means two things, so
      // the palette says which mode is on.
      switch code {
      case kVK_Escape, kVK_Return, kVK_ANSI_KeypadEnter:
        commitText()
      case kVK_Delete:
        if let index = editing, !shapes[index].text.isEmpty {
          shapes[index].text.removeLast()
          redrawMarks()
        }
      default:
        if let characters = event.characters, !characters.isEmpty,
           !event.modifierFlags.contains(.command) {
          shapes[editing!].text += characters
          redrawMarks()
        }
      }
      return true
    }

    switch code {
    case kVK_Escape: setDrawing(false)
    case kVK_ANSI_P: select(.pen)
    case kVK_ANSI_A: select(.arrow)
    case kVK_ANSI_R: select(.rect)
    case kVK_ANSI_H: select(.highlighter)
    case kVK_ANSI_T: select(.text)
    case kVK_ANSI_U: undo()
    case kVK_ANSI_C: clear()
    case kVK_ANSI_1: pick(0)
    case kVK_ANSI_2: pick(1)
    case kVK_ANSI_3: pick(2)
    case kVK_ANSI_4: pick(3)
    case kVK_ANSI_5: pick(4)
    case kVK_ANSI_6: pick(5)
    case kVK_ANSI_LeftBracket: widen(-1)
    case kVK_ANSI_RightBracket: widen(+1)
    default: return false
    }
    return true
  }

  // One step of the width control, wherever it is asked for: the bracket keys
  // and the two buttons in the palette have to agree on what a step is.
  private func widen(_ steps: Int) {
    width += 2 * CGFloat(steps)
    paletteView?.needsDisplay = true
  }

  private func pick(_ index: Int) {
    colorIndex = index
    paletteView?.needsDisplay = true
  }

  // MARK: drawing

  func drawMarks(screen: Int, in bounds: NSRect) {
    // Ahead of the hidden check, because hiding the marks is not a reason to
    // stop telling the user their screenshot was taken.
    if shutterFlash {
      let frame = NSBezierPath(rect: bounds.insetBy(dx: 4, dy: 4))
      frame.lineWidth = 8
      NSColor(white: 1, alpha: 0.9).setStroke()
      frame.stroke()
    }
    guard !marksHidden else { return }
    for shape in shapes where shape.screen == screen {
      stroke(shape)
    }
  }

  private func stroke(_ shape: Shape) {
    let color = palette[shape.colorIndex]
    guard shape.points.count > 0 else { return }

    switch shape.tool {
    case .text:
      let size = max(16, shape.width * 4)
      let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: .semibold),
        .foregroundColor: color,
      ]
      var text = shape.text
      // A caret is the only thing that says which text is being typed into.
      if let index = editing, index < shapes.count,
         shapes[index].points.first == shape.points.first { text += "|" }
      (text as NSString).draw(at: shape.points[0], withAttributes: attributes)

    case .rect:
      guard shape.points.count >= 2 else { return }
      let path = NSBezierPath(rect: rectBetween(shape.points[0], shape.points[1]))
      path.lineWidth = shape.width
      color.setStroke()
      path.stroke()

    case .arrow:
      guard shape.points.count >= 2 else { return }
      drawArrow(from: shape.points[0], to: shape.points[1],
                width: shape.width, color: color)

    case .pen, .highlighter:
      guard shape.points.count >= 2 else { return }
      let path = NSBezierPath()
      path.move(to: shape.points[0])
      for point in shape.points.dropFirst() { path.line(to: point) }
      path.lineWidth = shape.width
      path.lineCapStyle = .round
      path.lineJoinStyle = .round
      let alpha: CGFloat = shape.tool == .highlighter ? 0.35 : 1.0
      color.withAlphaComponent(alpha).setStroke()
      path.stroke()
    }
  }

  private func rectBetween(_ a: NSPoint, _ b: NSPoint) -> NSRect {
    NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
           width: abs(a.x - b.x), height: abs(a.y - b.y))
  }

  private func drawArrow(from start: NSPoint, to end: NSPoint,
                         width: CGFloat, color: NSColor) {
    color.setStroke()
    color.setFill()

    let angle = atan2(end.y - start.y, end.x - start.x)
    let span = hypot(end.x - start.x, end.y - start.y)
    // Every part of the arrow is sized from a width that is usually small. At
    // the wide end a head of four widths is longer than a short drag, and the
    // point of the arrow then sits outside the two ends the user dragged
    // between, with the barbs running back out through the tail.
    let length = min(max(14, width * 4), span)
    let spread = CGFloat.pi / 7

    // Butt capped and stopped inside the head. A round cap carries half a
    // width of ink past the tip, which at a wide setting is a blob hanging off
    // the point, and half a width behind the tail.
    let neck = NSPoint(x: end.x - length * 0.85 * cos(angle),
                       y: end.y - length * 0.85 * sin(angle))
    let shaft = NSBezierPath()
    shaft.move(to: start)
    shaft.line(to: neck)
    shaft.lineWidth = width
    shaft.lineCapStyle = .butt
    shaft.stroke()

    let head = NSBezierPath()
    head.move(to: end)
    head.line(to: NSPoint(x: end.x - length * cos(angle - spread),
                          y: end.y - length * sin(angle - spread)))
    head.line(to: NSPoint(x: end.x - length * cos(angle + spread),
                          y: end.y - length * sin(angle + spread)))
    head.close()
    head.fill()
  }

  // MARK: the palette

  func drawPalette(in view: PaletteView) {
    view.clearHits()
    view.clearTips()
    view.clearNames()
    view.clearHints()
    let bounds = view.bounds
    let shell = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                             xRadius: 13, yRadius: 13)
    NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 0.94).setFill()
    shell.fill()
    NSColor(white: 1, alpha: 0.14).setStroke()
    shell.lineWidth = 1
    shell.stroke()

    // Every control sits on this line and names its key underneath it, so the
    // keys are readable without hovering over anything. This tool is used by
    // someone talking to their computer, who cannot go looking for a tooltip.
    let mid = bounds.midY + 4

    drawAnchoredEnd(in: view, bounds: bounds, mid: mid)
    var x: CGFloat = 14

    // The red dot and the clock are the proof that recording is live, which a
    // silent tool cannot give a person who is talking instead of watching.
    let dot = NSRect(x: x, y: mid - 5, width: 10, height: 10)
    NSColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: pulseOn ? 1.0 : 0.35).setFill()
    NSBezierPath(ovalIn: dot).fill()
    x += 18

    let elapsed = Int(Date().timeIntervalSince(startedAt))
    label(String(format: "%02d:%02d", elapsed / 60, elapsed % 60),
          at: NSPoint(x: x, y: mid - 8), size: 14, weight: .medium,
          color: NSColor(white: 1, alpha: 0.95))
    x += 48

    separator(at: x, middle: mid); x += 13

    if drawing {
      for candidate in Tool.allCases {
        let rect = NSRect(x: x, y: mid - 15, width: 30, height: 30)
        control(rect, in: view, on: candidate == tool,
                key: candidate.letter.lowercased(),
                tip: candidate.name + " (" + candidate.letter.lowercased() + ")") {
          [weak self] in self?.select(candidate)
        }
        drawToolIcon(candidate, in: rect,
                     color: NSColor(white: 1, alpha: candidate == tool ? 1.0 : 0.72))
        x += 33
      }
      x += 5

      // Leaving draw mode is the thing a person needs most and guesses least,
      // so it is a button and not only a key.
      let done = NSRect(x: x, y: mid - 15, width: 56, height: 30)
      control(done, in: view, on: false, key: "esc", tip: "stop drawing (esc)") {
        [weak self] in self?.leaveDrawing()
      }
      label("Done", at: NSPoint(x: done.midX - 19, y: mid - 7), size: 13,
            weight: .semibold, color: NSColor(white: 1, alpha: 0.95))
      x += 62

      separator(at: x, middle: mid); x += 13

      for (index, colour) in palette.enumerated() {
        let swatch = NSRect(x: x, y: mid - 10, width: 20, height: 20)
        let target = swatch.insetBy(dx: -3, dy: -5)
        colour.setFill()
        NSBezierPath(roundedRect: swatch, xRadius: 5, yRadius: 5).fill()
        if index == colorIndex {
          NSColor.white.setStroke()
          let ring = NSBezierPath(roundedRect: swatch.insetBy(dx: -3, dy: -3),
                                  xRadius: 7, yRadius: 7)
          ring.lineWidth = 1.5
          ring.stroke()
        }
        view.addHit(target) { [weak self] in self?.pick(index) }
        view.addTip(target, "colour \(index + 1)")
        hint("\(index + 1)", under: swatch, view: view)
        // The swatch target is grown to 26, so the step has to clear it or the
        // seam between two colours belongs to both of them.
        x += 27
      }

      x += 5
      separator(at: x, middle: mid); x += 13

      let thinner = NSRect(x: x, y: mid - 13, width: 24, height: 26)
      control(thinner, in: view, on: false, key: "[", tip: "thinner ([)") {
        [weak self] in self?.widen(-1)
      }
      label("\u{2212}", at: NSPoint(x: thinner.midX - 5, y: mid - 8), size: 14,
            weight: .semibold, color: NSColor(white: 1, alpha: 0.85))
      x += 28

      // The number said nothing about the mark it was going to make. The dot
      // is the mark, at the size it will be drawn at.
      let preview = NSRect(x: x, y: mid - 13, width: 30, height: 26)
      let size = min(width, 22)
      palette[colorIndex].setFill()
      NSBezierPath(ovalIn: NSRect(x: preview.midX - size / 2, y: preview.midY - size / 2,
                                  width: size, height: size)).fill()
      hint(String(format: "%.0f", width), under: preview, view: view)
      x += 34

      let thicker = NSRect(x: x, y: mid - 13, width: 24, height: 26)
      control(thicker, in: view, on: false, key: "]", tip: "thicker (])") {
        [weak self] in self?.widen(+1)
      }
      label("+", at: NSPoint(x: thicker.midX - 5, y: mid - 8), size: 14,
            weight: .semibold, color: NSColor(white: 1, alpha: 0.85))
      x += 28
    } else {
      // One way in, named, so the row does not have to carry the whole tray
      // while the user is talking.
      let draw = NSRect(x: x, y: mid - 15, width: 78, height: 30)
      let drawKey = Settings.shared.shortcut(.draw)
      control(draw, in: view, on: false, key: drawKey.display,
              tip: "draw (" + drawKey.plain + ")") {
        [weak self] in self?.setDrawing(true)
      }
      drawToolIcon(tool, in: NSRect(x: draw.minX + 4, y: draw.minY, width: 24,
                                    height: draw.height),
                   color: NSColor(white: 1, alpha: 0.9))
      label("Draw", at: NSPoint(x: draw.minX + 28, y: mid - 7), size: 13,
            weight: .semibold, color: NSColor(white: 1, alpha: 0.95))
    }

    if editing != nil {
      label("typing", at: NSPoint(x: 14, y: bounds.maxY - 13), size: 9,
            weight: .regular,
            color: NSColor(srgbRed: 1, green: 0.9, blue: 0.3, alpha: 0.9))
    } else if marksHidden {
      label("marks hidden", at: NSPoint(x: 14, y: bounds.maxY - 13), size: 9,
            weight: .regular, color: NSColor(white: 1, alpha: 0.6))
    }
  }

  // Laid out from the right hand edge inwards, because these are the controls
  // that have to sit still while everything to their left comes and goes.
  private func drawAnchoredEnd(in view: PaletteView, bounds: NSRect, mid: CGFloat) {
    var right = bounds.maxX - 14

    // Flushing the recorder, transcribing and merging all take time and none of
    // them show. Without this the button reads as broken and gets pressed
    // again, which is what its own user did.
    let stop = NSRect(x: right - 54, y: mid - 15, width: 54, height: 30)
    if stopping {
      NSColor(white: 1, alpha: 0.13).setFill()
    } else {
      NSColor(srgbRed: 0.85, green: 0.20, blue: 0.17, alpha: 0.95).setFill()
    }
    NSBezierPath(roundedRect: stop, xRadius: 7, yRadius: 7).fill()
    label(stopping ? "Ending" : "Stop",
          at: NSPoint(x: stop.midX - (stopping ? 21 : 16), y: mid - 7), size: 13,
          weight: .semibold, color: NSColor(white: 1, alpha: stopping ? 0.75 : 1))
    view.addHit(stop) { [weak self] in self?.stopSession() }
    view.addTip(stop, stopping
                  ? "finishing the session, this takes a moment"
                  : "end the session (" + Settings.shared.shortcut(.stop).plain + ")")
    view.name("stop", stop)
    hint(stopping ? "please wait" : Settings.shared.shortcut(.stop).display,
         under: stop, view: view)
    right = stop.minX - 12

    let count = NSRect(x: right - 46, y: mid - 9, width: 46, height: 18)
    label(shots == 1 ? "1 shot" : "\(shots) shots",
          at: NSPoint(x: count.minX, y: mid - 7), size: 12, weight: .medium,
          color: NSColor(white: 1, alpha: shots > 0 ? 0.85 : 0.4))
    view.name("shots", count)
    right = count.minX - 10

    // The menu bar is where this lives, and on a full menu bar macOS puts the
    // item behind the notch, where it is drawn and invisible. The row is the
    // one place the user can always reach.
    let gear = NSRect(x: right - 30, y: mid - 15, width: 30, height: 30)
    control(gear, in: view, on: false, key: "", tip: "shortcuts and settings") {
      [weak self] in self?.openSettings()
    }
    drawGearIcon(in: gear, color: NSColor(white: 1, alpha: 0.8))
    view.name("settings", gear)
    right = gear.minX - 12

    let region = NSRect(x: right - 32, y: mid - 15, width: 32, height: 30)
    let regionKey = Settings.shared.shortcut(.region)
    control(region, in: view, on: false, key: regionKey.display,
            tip: "screenshot a region (" + regionKey.plain + ")") {
      [weak self] in self?.capture(region: true)
    }
    drawRegionIcon(in: region, color: NSColor(white: 1, alpha: 0.85))
    view.name("region", region)
    right = region.minX - 7

    // The frame that confirms a shot is drawn at the edges of the screen, and
    // the eye of someone mid sentence is on neither edge. The row is where they
    // last looked, so the confirmation is repeated on the control itself.
    let camera = NSRect(x: right - 32, y: mid - 15, width: 32, height: 30)
    let shotKey = Settings.shared.shortcut(.screenshot)
    control(camera, in: view, on: shutterFlash, key: shotKey.display,
            tip: "screenshot (" + shotKey.plain + ")") {
      [weak self] in self?.capture(region: false)
    }
    drawCameraIcon(in: camera, color: NSColor(white: 1, alpha: 0.9))
    view.name("camera", camera)
  }

  // The chrome that says a thing can be clicked, and the key underneath that
  // says what reaches it without the mouse.
  private func control(_ rect: NSRect, in view: PaletteView, on: Bool,
                       key: String, tip: String, action: @escaping () -> Void) {
    if on {
      NSColor(srgbRed: 0.20, green: 0.50, blue: 1.0, alpha: 0.92).setFill()
    } else {
      NSColor(white: 1, alpha: 0.13).setFill()
    }
    let shape = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
    shape.fill()
    NSColor(white: 1, alpha: on ? 0.35 : 0.16).setStroke()
    shape.lineWidth = 1
    shape.stroke()
    view.addHit(rect, action)
    view.addTip(rect, tip)
    hint(key, under: rect, view: view)
  }

  private func hint(_ text: String, under rect: NSRect, view: PaletteView) {
    guard !text.isEmpty else { return }
    let font = NSFont.systemFont(ofSize: 8, weight: .medium)
    let size = (text as NSString).size(withAttributes: [.font: font])
    let at = NSPoint(x: rect.midX - size.width / 2, y: 4)
    label(text, at: at, size: 8, weight: .medium,
          color: NSColor(white: 1, alpha: 0.45))
    view.addHint(NSRect(origin: at, size: size))
  }

  private func drawGearIcon(in rect: NSRect, color: NSColor) {
    color.setStroke()
    color.setFill()
    let centre = NSPoint(x: rect.midX, y: rect.midY)
    let teeth = 8
    let path = NSBezierPath()
    for tooth in 0..<teeth {
      let angle = CGFloat(tooth) * .pi * 2 / CGFloat(teeth)
      let inner = NSPoint(x: centre.x + cos(angle) * 4.5, y: centre.y + sin(angle) * 4.5)
      let outer = NSPoint(x: centre.x + cos(angle) * 7.5, y: centre.y + sin(angle) * 7.5)
      path.move(to: inner)
      path.line(to: outer)
    }
    path.lineWidth = 2.5
    path.lineCapStyle = .round
    path.stroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: centre.x - 5, y: centre.y - 5,
                                           width: 10, height: 10))
    ring.lineWidth = 2
    ring.stroke()
  }

  // A dashed corner rather than a full frame, which is what a region capture
  // looks like while it is being dragged out.
  private func drawRegionIcon(in rect: NSRect, color: NSColor) {
    let box = NSRect(x: rect.midX - 8, y: rect.midY - 7, width: 16, height: 14)
    color.setStroke()
    let path = NSBezierPath(rect: box)
    path.lineWidth = 1.5
    path.setLineDash([3, 2.5], count: 2, phase: 0)
    path.stroke()
    color.setFill()
    let cross = NSBezierPath()
    cross.move(to: NSPoint(x: box.midX - 3, y: box.midY))
    cross.line(to: NSPoint(x: box.midX + 3, y: box.midY))
    cross.move(to: NSPoint(x: box.midX, y: box.midY - 3))
    cross.line(to: NSPoint(x: box.midX, y: box.midY + 3))
    cross.lineWidth = 1.5
    cross.stroke()
  }

  // A ring on its own reads as a colour swatch, a record button or a full stop,
  // which is every wrong guess at what this control does. The body and the bump
  // are what make the ring a lens.
  private func drawCameraIcon(in rect: NSRect, color: NSColor) {
    let body = NSRect(x: rect.midX - 9, y: rect.midY - 6, width: 18, height: 13)
    let bump = NSRect(x: rect.midX - 3.5, y: body.maxY - 1, width: 7, height: 3)
    color.setFill()
    let shell = NSBezierPath(roundedRect: body, xRadius: 2.5, yRadius: 2.5)
    shell.append(NSBezierPath(roundedRect: bump, xRadius: 1, yRadius: 1))
    shell.fill()

    // Filled dark rather than left clear, so the lens reads the same over the
    // plain button and over the blue one that confirms a shot.
    let hole = NSBezierPath(ovalIn: NSRect(x: body.midX - 4, y: body.midY - 4,
                                           width: 8, height: 8))
    NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1).setFill()
    hole.fill()
    color.setStroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: body.midX - 2.5, y: body.midY - 2.5,
                                           width: 5, height: 5))
    ring.lineWidth = 1.5
    ring.stroke()
  }

  // Five letters in a row read as one word and not as five controls, which is
  // what happened: P A R H T told a first time user nothing about what any of
  // them draws. A shape drawn in the button is the tool's own output.
  private func drawToolIcon(_ candidate: Tool, in box: NSRect, color: NSColor) {
    func at(_ fx: CGFloat, _ fy: CGFloat) -> NSPoint {
      NSPoint(x: box.minX + box.width * fx, y: box.minY + box.height * fy)
    }
    color.setFill()
    color.setStroke()

    switch candidate {
    case .pen:
      let body = NSBezierPath()
      body.move(to: at(0.22, 0.22))
      body.line(to: at(0.38, 0.29))
      body.line(to: at(0.78, 0.69))
      body.line(to: at(0.69, 0.78))
      body.line(to: at(0.29, 0.38))
      body.close()
      body.fill()
    case .arrow:
      let shaft = NSBezierPath()
      shaft.move(to: at(0.24, 0.24))
      shaft.line(to: at(0.68, 0.68))
      shaft.lineWidth = 2
      shaft.lineCapStyle = .round
      shaft.stroke()
      let head = NSBezierPath()
      head.move(to: at(0.80, 0.80))
      head.line(to: at(0.80, 0.52))
      head.line(to: at(0.52, 0.80))
      head.close()
      head.fill()
    case .rect:
      let outline = NSBezierPath(roundedRect: box.insetBy(dx: box.width * 0.24,
                                                          dy: box.height * 0.28),
                                 xRadius: 3, yRadius: 3)
      outline.lineWidth = 2
      outline.stroke()
    case .highlighter:
      let bar = NSBezierPath()
      bar.move(to: at(0.22, 0.32))
      bar.line(to: at(0.78, 0.68))
      bar.lineWidth = box.width * 0.30
      bar.lineCapStyle = .butt
      color.withAlphaComponent(color.alphaComponent * 0.55).setStroke()
      bar.stroke()
    case .text:
      // A serif T is the one glyph that is already an icon everywhere else, so
      // it stays a letter while the other four stop being letters.
      let font = NSFont(name: "Times New Roman", size: box.height * 0.62)
        ?? NSFont.boldSystemFont(ofSize: box.height * 0.58)
      let glyph = "T" as NSString
      let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color,
      ]
      let size = glyph.size(withAttributes: attributes)
      glyph.draw(at: NSPoint(x: box.midX - size.width / 2,
                             y: box.midY - size.height / 2),
                 withAttributes: attributes)
    }
  }

  private func separator(at x: CGFloat, middle: CGFloat) {
    NSColor(white: 1, alpha: 0.15).setFill()
    NSBezierPath(rect: NSRect(x: x, y: middle - 12, width: 1, height: 24)).fill()
  }

  private func label(_ text: String, at point: NSPoint, size: CGFloat,
                     weight: NSFont.Weight, color: NSColor) {
    (text as NSString).draw(at: point, withAttributes: [
      .font: NSFont.systemFont(ofSize: size, weight: weight),
      .foregroundColor: color,
    ])
  }

  // MARK: screenshots

  private func countShots() -> Int {
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: inbox)) ?? []
    return contents.filter { !$0.hasPrefix(".") }.count
  }

  // The overlay owns the capture keys so that it can take its own furniture out
  // of the picture. A shot in the session inbox also needs no access to the
  // folder macOS protects.
  private func capture(region: Bool) {
    let wasVisible = paletteWindow?.isVisible ?? false
    paletteWindow?.orderOut(nil)

    // The window server needs a moment to drop the panel out of the composite,
    // and without the wait the palette lands in the file it was hidden for.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      let name = String(format: "shot-%03d.png", self.countShots() + 1)
      let path = self.inbox + "/" + name
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
      task.arguments = region ? ["-i", path] : ["-x", path]

      DispatchQueue.global().async {
        do {
          try task.run()
          task.waitUntilExit()
        } catch {
          warn("screencapture would not run: \(error.localizedDescription)")
          warn("  command: /usr/sbin/screencapture \(task.arguments!.joined(separator: " "))")
          warn("  fix: give this terminal Screen Recording in System Settings, Privacy and Security.")
        }
        let wrote = FileManager.default.fileExists(atPath: path)
        DispatchQueue.main.async {
          if wasVisible { self.paletteWindow?.orderFrontRegardless() }
          self.shots = self.countShots()
          if wrote {
            self.confirmShot()
          } else if !region {
            // A region capture writes nothing when the user presses escape,
            // which is not a failure. A full screen one always should.
            warn("screencapture wrote no file, so that screenshot was lost.")
            warn("  command: /usr/sbin/screencapture -x \(path)")
            warn("  fix: give this terminal Screen Recording in System Settings, Privacy and Security.")
          }
          self.paletteView?.needsDisplay = true
        }
      }
    }
  }

  // The shot is taken with -x so the shutter sound stays out of the recording,
  // and a silent capture is indistinguishable from a key that did nothing. The
  // frame is the confirmation, drawn after the file is on disk so that it can
  // never appear in the shot it is confirming.
  //
  // Long enough to be caught by someone who is talking rather than watching. A
  // confirmation that is missed is a key pressed again, and pressing it again
  // is another file: the session that found this holds four near identical
  // shots taken across three seconds.
  private func confirmShot() {
    shutterFlash = true
    redrawMarks()
    paletteView?.needsDisplay = true
    Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
      self?.shutterFlash = false
      self?.redrawMarks()
      self?.paletteView?.needsDisplay = true
    }
  }

  // MARK: stop

  private func stopSession() {
    guard !stopping else { return }
    // Answering the click is the first thing that happens, before anything
    // that can take time. Stopping a session means flushing the recorder,
    // transcribing and merging, and none of that has any effect the user can
    // see: the row and the menu bar have to say the click landed by
    // themselves, or the button reads as broken and gets pressed again.
    stopping = true
    stopRequestedAt = Date()
    paletteView?.needsDisplay = true
    refreshStatusItem()
    rebuildMenu()

    // The session path comes from the environment the CLI set, so this always
    // stops the session this overlay belongs to and never a later one.
    FileManager.default.createFile(atPath: session + "/stop", contents: nil)

    // The stop file is a request, and it is only answered by whoever is
    // watching for it. Nobody is, if the CLI died or was never waiting, and
    // then this window stays on the screen with its stop button doing nothing
    // anybody can see, while the recorder runs on. So the request has a
    // deadline, after which the overlay finishes the session itself.
    let deadline = Double(ProcessInfo.processInfo.environment["RF_RESCUE_SECONDS"]
                            ?? "") ?? 30
    Timer.scheduledTimer(withTimeInterval: deadline, repeats: false) { [weak self] _ in
      self?.finishSessionAlone()
    }
  }

  // Everything that makes a session worth having is written by the CLI: the
  // recorder is flushed with its own q command, the words are transcribed and
  // the document is merged. So this runs the CLI rather than reimplementing
  // any of it in Swift, where a second copy would be a second thing to get
  // wrong about somebody's recording.
  private func finishSessionAlone() {
    let cli = ProcessInfo.processInfo.environment["RF_CLI"] ?? ""
    warn("stop was pressed \(Int(Date().timeIntervalSince(stopRequestedAt)))s ago"
         + " and nothing was listening for it.")
    guard !cli.isEmpty, FileManager.default.isExecutableFile(atPath: cli) else {
      warn("  RF_CLI is not set, so this overlay cannot finish the session"
           + " itself and is leaving it alone rather than losing it.")
      warn("  the recording is still running and nothing has been lost.")
      warn("  fix: recordfeedback stop \(session)")
      NSApp.terminate(nil)
      return
    }
    warn("  finishing it here instead, with: \(cli) stop \(session)")
    warn("  nothing is lost: the recorder is flushed the same way, and the"
         + " document is written to \(session)/feedback.md.")

    // Detached, because this process is about to end and the work outlives it.
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = ["-c", "nohup " + shellQuoted(cli) + " stop " + shellQuoted(session)
                      + " >> " + shellQuoted(session + "/rescue.log") + " 2>&1 &"]
    do {
      try task.run()
      task.waitUntilExit()
    } catch {
      warn("  that would not run: \(error.localizedDescription)")
      warn("  fix: recordfeedback stop \(session)")
    }
    NSApp.terminate(nil)
  }

  // macOS names screenshots with spaces in them, and a session directory sits
  // under a home directory that can have one too.
  private func shellQuoted(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  // MARK: the palette probe

  // Posting a synthetic click needs Accessibility, so the test asks the window
  // server the question a click asks: which window is in front at this point.
  private func probePalette() {
    setDrawing(true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      guard let palette = self.paletteWindow else { return }
      let centre = NSPoint(x: palette.frame.midX, y: palette.frame.midY)
      var lines = [
        "palette \(palette.windowNumber)",
        "hit \(NSWindow.windowNumber(at: centre, belowWindowWithWindowNumber: 0))",
      ]
      for window in self.markWindows { lines.append("mark \(window.windowNumber)") }
      self.setDrawing(false)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        lines.append("visible-after-drawing \(palette.isVisible ? 1 : 0)")
        try? (lines.joined(separator: "\n") + "\n")
          .write(toFile: self.session + "/palette.probe", atomically: true,
                 encoding: .utf8)
      }
    }
  }

  // MARK: the tool and capture probes

  // Picking a tool is the only control the user reaches with the mouse, so the
  // question the probe asks is the one they asked: does pressing it again put
  // the drawing away.
  private func probeTools() {
    var lines: [String] = []
    select(.pen)
    lines.append("after-pick \(drawing ? 1 : 0) \(tool.name)")
    select(.pen)
    lines.append("after-pick-again \(drawing ? 1 : 0)")
    select(.arrow)
    lines.append("after-switch \(drawing ? 1 : 0) \(tool.name)")
    select(.rect)
    lines.append("after-second-switch \(drawing ? 1 : 0) \(tool.name)")
    select(.rect)
    lines.append("after-second-switch-again \(drawing ? 1 : 0)")
    setDrawing(false)
    try? (lines.joined(separator: "\n") + "\n")
      .write(toFile: session + "/tools.probe", atomically: true, encoding: .utf8)
  }

  // In draw mode the app is frontmost and its windows cover every screen, so a
  // capture asked for from inside draw mode is a different situation from one
  // asked for outside it, and it is the one the user reported losing.
  private func probeCapture() {
    setDrawing(true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      self.capture(region: false)
      // The confirmation is deliberately brief, so it has to be watched for
      // rather than looked at once, the way the user's eye would catch it.
      var sawFlash = false
      var ticks = 0
      Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
        ticks += 1
        if self.shutterFlash { sawFlash = true }
        guard ticks >= 100 else { return }
        timer.invalidate()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: self.inbox))
          ?? []
        let lines = ["drawing \(self.drawing ? 1 : 0)",
                     "files \(names.sorted().joined(separator: " "))",
                     "confirmed \(sawFlash ? 1 : 0)",
                     "still-flashing \(self.shutterFlash ? 1 : 0)"]
        self.setDrawing(false)
        try? (lines.joined(separator: "\n") + "\n")
          .write(toFile: self.session + "/capture.probe", atomically: true,
                 encoding: .utf8)
      }
    }
  }

  // The row carries two layouts now, and the thing that has to hold across
  // both of them is where the controls sit on the screen rather than where
  // they sit in the window: the window itself changes width. Draw mode is
  // entered by clicking a control in this row, so anything that moves as it
  // starts moves out from under the cursor that started it.
  private func probeLayout() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
      guard let view = self.paletteView, let window = self.paletteWindow else { return }

      func snapshot(_ tag: String) -> [String] {
        view.display()
        let origin = window.frame.minX
        let rects = view.hitRects
        var overlaps = 0
        var outside = 0
        for (index, one) in rects.enumerated() {
          if !view.bounds.contains(one) { outside += 1 }
          for other in rects[(index + 1)...] where one.intersects(other) { overlaps += 1 }
        }
        // Named rather than counted from the end, because the number of
        // controls between them is exactly what changes between the layouts.
        let anchors = self.anchoredControls.map { name -> String in
          let x = view.namedRects[name].map { Int(origin + $0.minX) } ?? -1
          return "\(tag)-at-\(name) \(x)"
        }
        var hintOverlaps = 0
        let hints = view.hintRects
        for (index, one) in hints.enumerated() {
          for other in hints[(index + 1)...] where one.intersects(other) {
            hintOverlaps += 1
          }
        }
        return ["\(tag)-window \(Int(window.frame.width))",
                "\(tag)-hint-overlaps \(hintOverlaps)",
                "\(tag)-controls \(rects.count)",
                "\(tag)-outside \(outside)",
                "\(tag)-overlaps \(overlaps)",
                "\(tag)-untipped \(rects.count - view.tipTexts.count)"] + anchors
      }

      // The menu bar is the way out of an overlay whose window is unreachable,
      // so whether the item actually got a place on it is a fact worth having
      // rather than assuming: macOS drops status items that do not fit.
      var lines: [String] = []
      if let button = self.statusItem?.button, let bar = button.window {
        lines.append("status-placed 1")
        lines.append("status-width \(Int(bar.frame.width))")
        lines.append("status-x \(Int(bar.frame.minX))")
        lines.append("status-onscreen "
                     + "\(NSScreen.screens.contains { $0.frame.intersects(bar.frame) } ? 1 : 0)")
        lines.append("status-menu \(self.statusItem?.menu?.items.count ?? 0)")
        // A display with a notch has two usable strips and a hole between
        // them, and an item macOS placed in the hole is an item nobody sees.
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(bar.frame) }) {
          lines.append("screen-width \(Int(screen.frame.width))")
          let left = screen.auxiliaryTopLeftArea
          let right = screen.auxiliaryTopRightArea
          if let left = left, let right = right {
            lines.append("notch \(Int(left.maxX)) \(Int(right.minX))")
            let visible = bar.frame.maxX <= left.maxX || bar.frame.minX >= right.minX
            lines.append("status-behind-notch \(visible ? 0 : 1)")
          } else {
            lines.append("notch none")
            lines.append("status-behind-notch 0")
          }
        }
      } else {
        lines.append("status-placed 0")
      }
      lines += snapshot("idle")
      self.setDrawing(true)
      lines += snapshot("drawing")
      lines.append("tips " + view.tipTexts.joined(separator: ", "))
      if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
          try? png.write(to: URL(fileURLWithPath: self.session + "/palette.png"))
        }
      }
      self.setDrawing(false)
      view.display()
      if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
          try? png.write(to: URL(fileURLWithPath: self.session + "/palette-idle.png"))
        }
      }
      try? (lines.joined(separator: "\n") + "\n")
        .write(toFile: self.session + "/layout.probe", atomically: true,
               encoding: .utf8)
    }
  }

  // Leaving draw mode gives the keyboard back by hiding the application, and
  // the question the probe asks is what that hiding takes with it: the marks
  // the user drew, and the frame that says a screenshot was taken.
  private func probeLeave() {
    setDrawing(true)
    drawSelfTestStroke()
    drawing = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
      self.setDrawing(false)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        var lines = [
          "shapes \(self.shapes.count)",
          "screens \(self.markWindows.count)",
          "marks-visible \(self.markWindows.filter { $0.isVisible }.count)",
        ]
        self.confirmShot()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
          lines.append("flash-visible "
                       + "\(self.markWindows.filter { $0.isVisible }.count)")
          lines.append("palette-visible "
                       + "\((self.paletteWindow?.isVisible ?? false) ? 1 : 0)")
          self.paletteView?.display()
          let tips = self.paletteView?.tipTexts ?? []
          lines.append("tips " + tips.joined(separator: ", "))
        }
        // How long the confirmation stays up, in hundredths, measured rather
        // than read off the timer: the user has to catch it out of the corner
        // of an eye while talking, not look for it.
        var ticks = 0
        Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { timer in
          ticks += 1
          guard !self.shutterFlash || ticks >= 200 else { return }
          timer.invalidate()
          lines.append("flash-hundredths \(ticks)")
          try? (lines.joined(separator: "\n") + "\n")
            .write(toFile: self.session + "/leave.probe", atomically: true,
                   encoding: .utf8)
        }
      }
    }
  }

  // The width keys are the one control with a range rather than a state, so the
  // probe reports where a handful of presses actually lands inside it.
  private func probeWidth() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
      self.setDrawing(true)
      self.select(.pen)
      let start = self.width
      for _ in 0..<3 { self.widen(+1) }
      let wider = self.width
      for _ in 0..<40 { self.widen(+1) }
      let top = self.width
      for _ in 0..<80 { self.widen(-1) }
      let bottom = self.width
      self.setDrawing(false)
      let lines = ["start \(Int(start))", "after-three \(Int(wider))",
                   "top \(Int(top))", "bottom \(Int(bottom))"]
      try? (lines.joined(separator: "\n") + "\n")
        .write(toFile: self.session + "/width.probe", atomically: true,
               encoding: .utf8)
    }
  }

  // A wide arrow is the shape most easily got wrong, because everything about
  // it is drawn relative to a width that is usually small. The probe renders
  // one through the same code the screen uses and measures the ink, since the
  // fault the user reported is in the pixels and not in the numbers.
  private func probeArrow() {
    var lines: [String] = []

    func measure(_ tag: String, to end: NSPoint, width: CGFloat) {
      let size = NSSize(width: 500, height: 240)
      guard let rep = NSBitmapImageRep(
              bitmapDataPlanes: nil, pixelsWide: Int(size.width),
              pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4,
              hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
              bytesPerRow: 0, bitsPerPixel: 0) else { return }
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
      NSColor.clear.setFill()
      NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
      let start = NSPoint(x: 100, y: 120)
      stroke(Shape(tool: .arrow, colorIndex: 0, width: width, screen: 0,
                   points: [start, end]))
      NSGraphicsContext.restoreGraphicsState()

      var beyond = 0, behind = 0, maxHalf = 0, shaftHalf = 0
      for px in 0..<Int(size.width) {
        for py in 0..<Int(size.height) {
          guard let colour = rep.colorAt(x: px, y: py),
                colour.alphaComponent > 0.5 else { continue }
          // The bitmap is top down and the arrow is drawn along y = 120.
          let y = Int(size.height) - 1 - py
          let half = abs(y - 120)
          if CGFloat(px) > end.x + 1 { beyond += 1 }
          if CGFloat(px) < start.x - 1 { behind += 1 }
          maxHalf = max(maxHalf, half)
          if px == 110 { shaftHalf = max(shaftHalf, half) }
        }
      }
      lines.append("\(tag)-beyond-tip \(beyond)")
      lines.append("\(tag)-behind-start \(behind)")
      lines.append("\(tag)-max-half \(maxHalf)")
      lines.append("\(tag)-shaft-half \(shaftHalf)")
      // A number says which assertion broke and a picture says why.
      if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: session + "/arrow-" + tag + ".png"))
      }
    }

    measure("wide", to: NSPoint(x: 380, y: 120), width: 40)
    measure("short", to: NSPoint(x: 160, y: 120), width: 40)
    try? (lines.joined(separator: "\n") + "\n")
      .write(toFile: session + "/arrow.probe", atomically: true, encoding: .utf8)
  }

  // MARK: the pixel test

  // Posting synthetic mouse events needs Accessibility, which cannot be granted
  // without a person, so the test drives the same three calls the mouse does.
  private func drawSelfTestStroke() {
    guard let screen = NSScreen.main else { return }
    let size = screen.frame.size
    tool = .pen
    colorIndex = 0
    width = 40
    drawing = true
    beginStroke(at: NSPoint(x: size.width * 0.25, y: size.height * 0.5), screen: 0)
    extendStroke(to: NSPoint(x: size.width * 0.50, y: size.height * 0.5))
    extendStroke(to: NSPoint(x: size.width * 0.75, y: size.height * 0.5))
    endStroke(at: NSPoint(x: size.width * 0.75, y: size.height * 0.5))
    drawing = false
    for view in markViews { view.display() }
  }
}

// Screen Recording is the permission that breaks this tool silently: without it
// screencapture still writes a file and the file is only the wallpaper. doctor
// asks here rather than guessing from the pixels of a shot.
// The CLI prints the key list at the start of every session, and a second copy
// of it in the shell script is a copy that goes stale the first time anybody
// rebinds one. It asks the overlay instead.
if CommandLine.arguments.contains("--print-keys") {
  for action in Action.allCases {
    print(action.rawValue + " " + Settings.shared.shortcut(action).plain)
  }
  exit(0)
}
if CommandLine.arguments.contains("--check-capture") {
  exit(CGPreflightScreenCaptureAccess() ? 0 : 1)
}
if CommandLine.arguments.contains("--request-capture") {
  CGRequestScreenCaptureAccess()
  exit(0)
}

let application = NSApplication.shared
let controller = Overlay()
application.delegate = controller
application.setActivationPolicy(.accessory)
application.run()
