// The annotation overlay. The CLI launches one of these per session with
// RF_SESSION set, and it belongs to that session for its whole life. It never
// reads ~/.recordfeedback/current, because a session that ended is not this
// process's business.
import Cocoa
import Carbon.HIToolbox

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

  func register(_ keyCode: Int, named name: String, handler: @escaping () -> Void) {
    let id = nextID
    nextID += 1
    var ref: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(signature: OSType(0x52464244), id: id)
    let status = RegisterEventHotKey(UInt32(keyCode), UInt32(optionKey | cmdKey),
                                     hotKeyID, GetApplicationEventTarget(), 0, &ref)
    if status != noErr || ref == nil {
      warn("could not register \(name), another application already owns it.")
      warn("  fix: quit whatever owns \(name), or use the palette button instead.")
      return
    }
    handlers[id] = handler
    refs.append(ref!)
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

  override func draw(_ dirtyRect: NSRect) {
    owner?.drawPalette(in: self)
    syncTips()
  }

  func clearHits() { hits.removeAll() }

  func addHit(_ rect: NSRect, _ action: @escaping () -> Void) {
    hits.append((rect, action))
  }

  // The rectangles the drawing code actually registered, which is the only
  // honest source for a test asking whether two controls sit on top of one
  // another. A layout read off the source is a layout nobody laid out.
  var hitRects: [NSRect] { hits.map { $0.0 } }

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

  private func buildPalette() {
    // Wide enough for draw mode, which is the widest the row gets because it is
    // the only state carrying the Done button. The width does not change with
    // the state: a control that moves out from under the cursor as draw mode
    // starts is a control that gets mis-clicked.
    let size = NSSize(width: 720, height: 46)
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

  private func paletteOrigin(for size: NSSize) -> NSPoint {
    let defaults = UserDefaults.standard
    if let saved = defaults.string(forKey: "palette.origin") {
      let point = NSPointFromString(saved)
      for screen in NSScreen.screens where screen.frame.contains(point) {
        // The origin is the bottom left corner, so a position saved by an older
        // and narrower palette can put the right hand end, where Stop lives,
        // past the edge of the screen.
        let limit = screen.frame
        return NSPoint(x: min(point.x, limit.maxX - size.width),
                       y: min(point.y, limit.maxY - size.height))
      }
    }
    guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
    return NSPoint(x: screen.frame.midX - size.width / 2,
                   y: screen.frame.minY + 40)
  }

  func rememberPalettePosition(_ origin: NSPoint) {
    UserDefaults.standard.set(NSStringFromPoint(origin), forKey: "palette.origin")
  }

  private func installHotkeys() {
    Hotkeys.shared.install()
    // Option-Command-D is the system's own show and hide the Dock and Carbon
    // will not hand it over, so draw mode is A for annotate.
    Hotkeys.shared.register(kVK_ANSI_A, named: "opt-cmd-A") { [weak self] in
      self?.setDrawing(!(self?.drawing ?? false))
    }
    Hotkeys.shared.register(kVK_ANSI_X, named: "opt-cmd-X") { [weak self] in
      self?.capture(region: false)
    }
    Hotkeys.shared.register(kVK_ANSI_R, named: "opt-cmd-R") { [weak self] in
      self?.capture(region: true)
    }
    Hotkeys.shared.register(kVK_ANSI_C, named: "opt-cmd-C") { [weak self] in
      self?.clear()
    }
    Hotkeys.shared.register(kVK_ANSI_Z, named: "opt-cmd-Z") { [weak self] in
      self?.undo()
    }
    Hotkeys.shared.register(kVK_ANSI_H, named: "opt-cmd-H") { [weak self] in
      self?.toggleHidden()
    }
    Hotkeys.shared.register(kVK_ANSI_S, named: "opt-cmd-S") { [weak self] in
      self?.stopSession()
    }
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
    paletteView?.needsDisplay = true
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
    case kVK_ANSI_LeftBracket: width -= 2; paletteView?.needsDisplay = true
    case kVK_ANSI_RightBracket: width += 2; paletteView?.needsDisplay = true
    default: return false
    }
    return true
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
    let shaft = NSBezierPath()
    shaft.move(to: start)
    shaft.line(to: end)
    shaft.lineWidth = width
    shaft.lineCapStyle = .round
    shaft.stroke()

    let angle = atan2(end.y - start.y, end.x - start.x)
    let length = max(14, width * 4)
    let spread = CGFloat.pi / 7
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
    let bounds = view.bounds
    let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                  xRadius: 10, yRadius: 10)
    NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 0.92).setFill()
    background.fill()
    NSColor(white: 1, alpha: 0.18).setStroke()
    background.lineWidth = 1
    background.stroke()

    let middle = bounds.midY
    var x: CGFloat = 12

    // The red dot and the clock are the proof that recording is live, which a
    // silent tool cannot give a person who is talking instead of watching.
    let dot = NSRect(x: x, y: middle - 5, width: 10, height: 10)
    NSColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: pulseOn ? 1.0 : 0.35).setFill()
    NSBezierPath(ovalIn: dot).fill()
    x += 20

    let elapsed = Int(Date().timeIntervalSince(startedAt))
    label(String(format: "%02d:%02d", elapsed / 60, elapsed % 60),
          at: NSPoint(x: x, y: middle - 8), size: 14, weight: .medium,
          color: NSColor(white: 1, alpha: 0.95))
    x += 52

    separator(at: x, middle: middle); x += 11

    view.clearTips()
    for candidate in Tool.allCases {
      let rect = NSRect(x: x, y: middle - 14, width: 28, height: 28)
      let active = candidate == tool && drawing
      if active {
        NSColor(srgbRed: 0.20, green: 0.50, blue: 1.0, alpha: 0.9).setFill()
      } else {
        NSColor(white: 1, alpha: 0.10).setFill()
      }
      NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
      drawToolIcon(candidate, in: rect,
                   color: NSColor(white: 1, alpha: active ? 1.0 : 0.7))
      view.addHit(rect) { [weak self] in self?.select(candidate) }
      // A drawn shape says what a tool does but not what key reaches it, and
      // the letters this replaced were the only place the keys were written.
      view.addTip(rect, candidate.name + " (" + candidate.letter.lowercased() + ")")
      x += 32
    }

    x += 3

    // Leaving draw mode is the thing a person needs most and guesses least, so
    // it is a button and not only a key. Its space is held whether it is shown
    // or not: draw mode is entered by clicking a tool, and everything to the
    // right of this would otherwise jump out from under the cursor as it starts.
    if drawing {
      let done = NSRect(x: x, y: middle - 13, width: 52, height: 26)
      NSColor(white: 1, alpha: 0.18).setFill()
      NSBezierPath(roundedRect: done, xRadius: 6, yRadius: 6).fill()
      label("Done", at: NSPoint(x: done.minX + 8, y: middle - 8), size: 13,
            weight: .semibold, color: NSColor(white: 1, alpha: 0.95))
      view.addHit(done) { [weak self] in self?.leaveDrawing() }
      view.addTip(done, "stop drawing (esc)")
    }
    x += 56

    separator(at: x, middle: middle); x += 11

    for (index, color) in palette.enumerated() {
      let rect = NSRect(x: x, y: middle - 9, width: 18, height: 18)
      color.setFill()
      NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
      if index == colorIndex {
        NSColor.white.setStroke()
        let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3),
                                xRadius: 6, yRadius: 6)
        ring.lineWidth = 1.5
        ring.stroke()
      }
      view.addHit(rect.insetBy(dx: -3, dy: -3)) { [weak self] in self?.pick(index) }
      // The swatch is 18 wide and its target is grown to 24, so the step has to
      // clear 24 or the seam between two colours belongs to both of them.
      x += 26
    }

    x += 3
    separator(at: x, middle: middle); x += 11

    let thinner = NSRect(x: x, y: middle - 11, width: 22, height: 22)
    button("-", in: thinner, view: view) { [weak self] in
      self?.width -= 2
      self?.paletteView?.needsDisplay = true
    }
    x += 25
    label(String(format: "%.0f", width), at: NSPoint(x: x + 4, y: middle - 7),
          size: 12, weight: .medium, color: NSColor(white: 1, alpha: 0.85))
    x += 26
    let thicker = NSRect(x: x, y: middle - 11, width: 22, height: 22)
    button("+", in: thicker, view: view) { [weak self] in
      self?.width += 2
      self?.paletteView?.needsDisplay = true
    }
    x += 25

    x += 3
    separator(at: x, middle: middle); x += 11

    let camera = NSRect(x: x, y: middle - 13, width: 30, height: 26)
    NSColor(white: 1, alpha: 0.10).setFill()
    NSBezierPath(roundedRect: camera, xRadius: 6, yRadius: 6).fill()
    NSColor(white: 1, alpha: 0.75).setStroke()
    let lens = NSBezierPath(ovalIn: NSRect(x: camera.midX - 6, y: camera.midY - 6,
                                           width: 12, height: 12))
    lens.lineWidth = 1.5
    lens.stroke()
    view.addHit(camera) { [weak self] in self?.capture(region: false) }
    x += 34

    label("\(shots)", at: NSPoint(x: x, y: middle - 7), size: 12,
          weight: .medium, color: NSColor(white: 1, alpha: 0.85))
    x += 22

    let stop = NSRect(x: bounds.maxX - 62, y: middle - 13, width: 50, height: 26)
    NSColor(srgbRed: 0.85, green: 0.20, blue: 0.17, alpha: 0.95).setFill()
    NSBezierPath(roundedRect: stop, xRadius: 6, yRadius: 6).fill()
    label("Stop", at: NSPoint(x: stop.midX - 15, y: middle - 8), size: 13,
          weight: .semibold, color: .white)
    view.addHit(stop) { [weak self] in self?.stopSession() }

    if editing != nil {
      label("typing", at: NSPoint(x: 12, y: 2), size: 9, weight: .regular,
            color: NSColor(srgbRed: 1, green: 0.9, blue: 0.3, alpha: 0.9))
    } else if marksHidden {
      label("marks hidden", at: NSPoint(x: 12, y: 2), size: 9, weight: .regular,
            color: NSColor(white: 1, alpha: 0.6))
    }
  }

  private func button(_ text: String, in rect: NSRect, view: PaletteView,
                      action: @escaping () -> Void) {
    NSColor(white: 1, alpha: 0.10).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
    label(text, at: NSPoint(x: rect.midX - 4, y: rect.midY - 8), size: 14,
          weight: .semibold, color: NSColor(white: 1, alpha: 0.8))
    view.addHit(rect, action)
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
  private func confirmShot() {
    shutterFlash = true
    redrawMarks()
    Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in
      self?.shutterFlash = false
      self?.redrawMarks()
    }
  }

  // MARK: stop

  private func stopSession() {
    // The session path comes from the environment the CLI set, so this always
    // stops the session this overlay belongs to and never a later one.
    FileManager.default.createFile(atPath: session + "/stop", contents: nil)
    paletteView?.needsDisplay = true
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

  // Draw mode is the widest the palette ever gets, because it is the only
  // state that shows the way out of it, so it is the state the row has to fit.
  private func probeLayout() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
      guard let view = self.paletteView else { return }
      view.display()
      // Stop is anchored to the right hand end and the camera is the control
      // before it, so its position is where every width added to the left of it
      // shows up.
      let idleCamera = view.hitRects.dropLast().last.map { Int($0.minX) } ?? -1
      let idleCount = view.hitRects.count

      self.setDrawing(true)
      view.display()
      let rects = view.hitRects
      var overlaps: [String] = []
      var outside = 0
      for (index, one) in rects.enumerated() {
        if !view.bounds.contains(one) { outside += 1 }
        for other in rects[(index + 1)...] where one.intersects(other) {
          overlaps.append("\(Int(one.minX)):\(Int(one.maxX))"
                          + "/\(Int(other.minX)):\(Int(other.maxX))")
        }
      }
      let drawingCamera = rects.dropLast().last.map { Int($0.minX) } ?? -1

      let lines = ["width \(Int(view.bounds.width))",
                   "controls \(rects.count)",
                   "controls-idle \(idleCount)",
                   "outside \(outside)",
                   "camera-idle \(idleCamera)",
                   "camera-drawing \(drawingCamera)",
                   "overlaps \(overlaps.count) \(overlaps.joined(separator: " "))"]
      self.setDrawing(false)
      try? (lines.joined(separator: "\n") + "\n")
        .write(toFile: self.session + "/layout.probe", atomically: true,
               encoding: .utf8)
    }
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
