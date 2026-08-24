// The annotation overlay. The CLI launches one of these per session with
// RF_SESSION set, and it belongs to that session for its whole life. It never
// reads ~/.recordfeedback/current, because a session that ended is not this
// process's business.
import Cocoa
import Carbon.HIToolbox


// Swift scopes `private` to one file, and this class is spread across the
// Overlay+ files, so its members are internal. The binary is a single module
// with nothing else in it, so internal is as narrow as private was.
final class Overlay: NSObject, NSApplicationDelegate {
  let session = ProcessInfo.processInfo.environment["RF_SESSION"] ?? ""
  var markWindows: [MarkWindow] = []
  var markViews: [MarkView] = []
  var paletteWindow: PaletteWindow?
  var paletteView: PaletteView?

  var shapes: [Shape] = []
  var drawing = false
  var marksHidden = false
  var tool: Tool = .pen
  var colorIndex = 0
  var widths: [Tool: CGFloat] = {
    var w: [Tool: CGFloat] = [:]
    for t in Tool.allCases { w[t] = t.defaultWidth }
    return w
  }()
  var editing: Int?
  var startedAt = Date()
  var pulseOn = true
  var shots = 0
  // The highest shot number handed out, which is ahead of what is on disk for
  // as long as screencapture takes to write.
  var reservedShots = 0
  var shutterFlash = false
  var keyMonitor: Any?
  var statusItem: NSStatusItem?
  var settingsWindow: SettingsWindow?
  // Set the instant Stop is pressed, so the row and the menu bar can say the
  // click landed before anything downstream has had time to answer it.
  var stopping = false
  var stopRequestedAt = Date()

  var width: CGFloat {
    get { widths[tool] ?? tool.defaultWidth }
    set { widths[tool] = max(1, min(64, newValue)) }
  }

  var inbox: String { session + "/inbox" }

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
    #if RF_PROBES
    // The probes are compiled in only for the test suite. A shipped binary
    // carries no scaffolding and cannot be talked into a probe by an
    // environment variable.

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
    if ProcessInfo.processInfo.environment["RF_OVERLAY_SELFTEST"] == "capture-twice" {
      probeDoubleCapture()
    }
    if ProcessInfo.processInfo.environment["RF_OVERLAY_SELFTEST"] == "clearbutton" {
      probeClearButton()
    }
    if ProcessInfo.processInfo.environment["RF_OVERLAY_SELFTEST"] == "poster" {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.probePoster() }
    }
    if ProcessInfo.processInfo.environment["RF_OVERLAY_SELFTEST"] == "layout" {
      probeLayout()
    }
    // Opens the settings window, because a window written blind is a window
    // that crashes the first time somebody reaches for it.
    if ProcessInfo.processInfo.environment["RF_OVERLAY_SELFTEST"] == "settings" {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.probeSettings() }
    }
    // Rebinds a key the way the settings window does, because saving a
    // shortcut and having it take effect is the whole point of that window and
    // none of it is reached by opening one.
    if ProcessInfo.processInfo.environment["RF_OVERLAY_SELFTEST"] == "rebind" {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.probeRebind() }
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
    #endif
    buildStatusItem()

    // Written last, so a test that waits for it knows the windows are up.
    FileManager.default.createFile(atPath: session + "/overlay.ready", contents: nil)
  }

  func sessionStart() -> Date {
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

  func buildWindows() {
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

  let paletteHeight: CGFloat = 52
  var paletteWidth: CGFloat { drawing ? 956 : 446 }

  func buildPalette() {
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
  func paletteOrigin(for size: NSSize) -> NSPoint {
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
  func resizePalette() {
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

  func installHotkeys() {
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
}
