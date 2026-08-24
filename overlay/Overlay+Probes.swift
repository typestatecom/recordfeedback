// Every selftest probe. Nothing here runs in a session: each is reached only
// by RF_OVERLAY_SELFTEST, which the test suite sets and nothing else does.
import Cocoa
import Carbon.HIToolbox

#if RF_PROBES
extension Overlay {
  // MARK: the palette probe

  // Posting a synthetic click needs Accessibility, so the test asks the window
  // server the question a click asks: which window is in front at this point.
  func probePalette() {
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
  func probeTools() {
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
  func probeCapture() {
    setDrawing(true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      self.capture(region: false)
      // Read now rather than at the report. What this case is about is that the
      // capture was asked for from inside draw mode, and draw mode three
      // seconds later is a different question with somebody else's keystrokes
      // in it.
      let drawingAtCapture = self.drawing
      // A person typing at another window while this runs is the ordinary case,
      // not a rare one, and their keys arrive here because draw mode took the
      // foreground. Injecting the exit is the only way to test that without
      // waiting for somebody to press esc at the right second.
      if ProcessInfo.processInfo.environment["RF_OVERLAY_STRAY_EXIT"] == "1" {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.setDrawing(false) }
      }
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
        let lines = ["drawing \(drawingAtCapture ? 1 : 0)",
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

  // Two presses inside the second that screencapture takes are what a person
  // does when the first one is silent, which is exactly what -x makes it.
  func probeDoubleCapture() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
      self.capture(region: false)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        self.capture(region: false)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: self.inbox))
          ?? []
        let lines = ["files " + names.filter { !$0.hasPrefix(".") }.sorted()
                       .joined(separator: " "),
                     "shots \(self.shots)"]
        try? (lines.joined(separator: "\n") + "\n")
          .write(toFile: self.session + "/double.probe", atomically: true,
                 encoding: .utf8)
      }
    }
  }

  // The row carries two layouts now, and the thing that has to hold across
  // both of them is where the controls sit on the screen rather than where
  // they sit in the window: the window itself changes width. Draw mode is
  // entered by clicking a control in this row, so anything that moves as it
  // starts moves out from under the cursor that started it.
  func probeLayout() {
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
  func probeLeave() {
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
  func probeWidth() {
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

  func probeSettings() {
    openSettings()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      guard let window = self.settingsWindow?.window else {
        try? "opened 0\n".write(toFile: self.session + "/settings.probe",
                                atomically: true, encoding: .utf8)
        return
      }
      let buttons = window.contentView?.subviews.compactMap { $0 as? NSButton } ?? []
      var lines = ["opened \(window.isVisible ? 1 : 0)",
                   "buttons \(buttons.count)",
                   "titles " + buttons.map { $0.title }.joined(separator: ","),
                   "level \(window.level.rawValue)",
                   "palette-level \(self.paletteWindow?.level.rawValue ?? 0)",
                   "over-palette "
                     + "\((self.paletteWindow.map { window.frame.intersects($0.frame) } ?? false) ? 1 : 0)"]
      if let view = window.contentView,
         let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
          try? png.write(to: URL(fileURLWithPath: self.session + "/settings.png"))
        }
      }
      lines.append("rows-outside "
                   + "\((window.contentView?.subviews.filter { !window.contentView!.bounds.contains($0.frame) }.count) ?? -1)")
      try? (lines.joined(separator: "\n") + "\n")
        .write(toFile: self.session + "/settings.probe", atomically: true,
               encoding: .utf8)
    }
  }

  func probeRebind() {
    var lines: [String] = []
    lines.append("before " + Settings.shared.shortcut(.draw).plain)

    // The one the settings window refuses: a combination another action holds.
    let taken = Settings.shared.shortcut(.clear)
    lines.append("conflict "
                 + (Settings.shared.conflict(taken, ignoring: .draw)?.rawValue ?? "none"))
    // And the one it allows: an action asked to keep what it already has.
    lines.append("self-conflict "
                 + (Settings.shared.conflict(Settings.shared.shortcut(.draw),
                                             ignoring: .draw)?.rawValue ?? "none"))

    let wanted = Shortcut(keyCode: kVK_ANSI_J, option: false, shift: true,
                          command: true, control: false)
    Settings.shared.set(.draw, to: wanted)
    reinstallHotkeys()
    lines.append("after " + Settings.shared.shortcut(.draw).plain)
    lines.append("shown " + Settings.shared.shortcut(.draw).display)
    lines.append("saved "
                 + (FileManager.default.fileExists(atPath: Settings.shared.path) ? "1" : "0"))

    // The row reads the binding rather than keeping its own copy of it.
    paletteView?.display()
    lines.append("tips " + (paletteView?.tipTexts.joined(separator: ", ") ?? ""))

    // Reloading from disk has to give back what was written, or the binding
    // lasts only as long as this process does.
    Settings.shared.load()
    lines.append("reloaded " + Settings.shared.shortcut(.draw).plain)
    lines.append("untouched " + Settings.shared.shortcut(.stop).plain)

    Settings.shared.reset()
    lines.append("reset " + Settings.shared.shortcut(.draw).plain)

    try? (lines.joined(separator: "\n") + "\n")
      .write(toFile: session + "/rebind.probe", atomically: true, encoding: .utf8)
  }

  // A wide arrow is the shape most easily got wrong, because everything about
  // it is drawn relative to a width that is usually small. The probe renders
  // one through the same code the screen uses and measures the ink, since the
  // fault the user reported is in the pixels and not in the numbers.
  func probeArrow() {
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
  // The documentation shots. Draws one of each mark over the backdrop and stays
  // in draw mode with the palette up, so that what the README shows is the real
  // overlay rather than a picture of one.
  func probePoster() {
    guard let screen = NSScreen.main else { return }
    let size = screen.frame.size
    setDrawing(true)

    func stroke(_ points: [NSPoint], _ newTool: Tool, _ colour: Int, _ pen: CGFloat) {
      tool = newTool
      colorIndex = colour
      width = pen
      guard let first = points.first else { return }
      beginStroke(at: first, screen: 0)
      for point in points.dropFirst() { extendStroke(to: point) }
      endStroke(at: points.last!)
    }

    // An arrow at the row a person would be talking about, a box round the
    // heading, and a highlighter under the button they mean.
    stroke([NSPoint(x: size.width * 0.90, y: size.height * 0.42),
            NSPoint(x: size.width * 0.795, y: size.height * 0.545)], .arrow, 0, 8)
    stroke([NSPoint(x: size.width * 0.17, y: size.height * 0.70),
            NSPoint(x: size.width * 0.38, y: size.height * 0.77)], .rect, 2, 6)
    stroke([NSPoint(x: size.width * 0.755, y: size.height * 0.218),
            NSPoint(x: size.width * 0.826, y: size.height * 0.218)], .highlighter, 3, 30)

    tool = .arrow
    redrawMarks()
    for view in markViews { view.display() }
  }

  func drawSelfTestStroke() {
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
#endif
