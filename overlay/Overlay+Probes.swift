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
        // Asked of each control rather than by counting tips against controls.
        // The row also carries readouts that name themselves without being
        // clickable, and a subtraction counts one of those as a control that
        // lost its tooltip.
        let untipped = rects.filter { rect in
          !view.tipRects.contains { $0.contains(NSPoint(x: rect.midX, y: rect.midY)) }
        }.count
        return ["\(tag)-window \(Int(window.frame.width))",
                "\(tag)-hint-overlaps \(hintOverlaps)",
                "\(tag)-controls \(rects.count)",
                "\(tag)-outside \(outside)",
                "\(tag)-overlaps \(overlaps)",
                "\(tag)-untipped \(untipped)"] + anchors
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

  // Starting and stopping listening from the key, which is what a person mid
  // sentence actually reaches for. Whether the row carries the control in both
  // states, and whether the switch and the file agree afterwards, is not
  // visible from the source.
  func probeVoiceToggle() {
    guard let view = self.paletteView else { return }
    var lines: [String] = []

    func nameShown(_ key: String) -> Bool {
      view.display()
      return view.namedRects[key] != nil
    }
    func tip(for key: String) -> String {
      view.display()
      guard let rect = view.namedRects[key] else { return "" }
      let point = NSPoint(x: rect.midX, y: rect.midY)
      return view.tipText(at: point)
    }

    lines.append("enabled-start \(Settings.shared.voiceEnabled ? 1 : 0)")
    lines.append("control-off \(nameShown("listen") ? 1 : 0)")
    lines.append("label-off \(tip(for: "listen"))")

    // Through the same call the key and the row button make.
    self.toggleListening()
    lines.append("enabled-after-on \(Settings.shared.voiceEnabled ? 1 : 0)")
    lines.append("control-on \(nameShown("listen") ? 1 : 0)")

    self.toggleListening()
    lines.append("enabled-after-off \(Settings.shared.voiceEnabled ? 1 : 0)")
    lines.append("listener-after-off \(self.voice == nil ? 0 : 1)")

    // The file the next session reads, and the file the settings window shows.
    let saved = (try? String(contentsOfFile: Settings.shared.path, encoding: .utf8)) ?? ""
    lines.append("saved \(saved.contains("\"enabled\" : true") ? 1 : 0)")

    try? (lines.joined(separator: "\n") + "\n")
      .write(toFile: self.session + "/toggle.probe", atomically: true, encoding: .utf8)
  }

  // A phrase added in the settings window has to be a phrase that works. The
  // list is edited in one place, saved in another and matched in a third, and a
  // phrase that reaches the file but not the grammar is a setting that lies.
  func probeVoiceSettings() {
    openSettings()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      var lines: [String] = []
      let window = self.settingsWindow
      lines.append("tabs " + (window?.tabTitles ?? []).joined(separator: ","))
      // A tab that is never selected is a tab that is never laid out, and a
      // page that crashes on first sight is exactly what this is here to catch.
      window?.showVoiceTab()
      // What the editor is showing for whichever command the window selected
      // for itself, before the probe touches anything.
      let shown = window?.editorText ?? ""
      lines.append("editor-lines \(shown.isEmpty ? 0 : shown.split(separator: "\n").count)")

      // Through the same calls the window's own controls make, so what is
      // proven is the path a person's typing takes and not a private one.
      Settings.shared.setVoiceEnabled(true)
      Settings.shared.setVoiceWords(trigger: "computer", escape: "ignore this")
      Settings.shared.setVoicePhrases(.toolArrow, to: ["point at that", "stick an arrow on it"])
      lines.append("enabled \(Settings.shared.voiceEnabled ? 1 : 0)")
      lines.append("trigger \(Settings.shared.voiceTrigger)")

      // An empty trigger would make every phrase in the table fire on ordinary
      // speech, so it is refused and the one in force stands.
      Settings.shared.setVoiceWords(trigger: "   ", escape: "ignore this")
      lines.append("trigger-after-empty \(Settings.shared.voiceTrigger)")

      let grammar = Settings.shared.grammar()
      func read(_ said: String) -> String {
        let found = grammar.matches(in: said)
        return found.isEmpty ? "none" : found.map { $0.command.rawValue }.joined(separator: ",")
      }
      lines.append("added \(read("computer point at that"))")
      lines.append("added-second \(read("computer stick an arrow on it"))")
      // The phrases that were replaced are gone, not merged with the new ones.
      lines.append("replaced \(read("computer pick arrow"))")
      // The old trigger is not a trigger any more.
      lines.append("old-trigger \(read("let's point at that"))")
      lines.append("escaped \(read("ignore this computer point at that"))")

      // Written to the file, because the CLI reads it to decide what to print
      // and the next session reads it to know what can be said.
      let saved = (try? String(contentsOfFile: Settings.shared.path, encoding: .utf8)) ?? ""
      lines.append("saved-phrase \(saved.contains("point at that") ? 1 : 0)")
      lines.append("saved-enabled \(saved.contains("\"enabled\" : true") ? 1 : 0)")

      try? (lines.joined(separator: "\n") + "\n")
        .write(toFile: self.session + "/voice.probe", atomically: true, encoding: .utf8)
    }
  }

  // The grammar, driven by sentences from a file. What the recogniser hears is
  // Apple's business and needs a permission a test cannot grant, but what this
  // tool does with a heard sentence is this tool's business and is decided
  // here, so it is answered without a microphone or a person.
  // One second of a voice at a conversational level, written where the recorder
  // would have written it.
  func writePosterLevel() {
    let directory = session + "/levels"
    try? FileManager.default.createDirectory(atPath: directory,
                                             withIntermediateDirectories: true)
    let frames = 16000
    var samples = [Int16](repeating: 0, count: frames)
    for index in 0..<frames {
      // A tone rather than noise, because what is being drawn is one number and
      // a tone reaches it with arithmetic anybody can check. The amplitude puts
      // the meter around two thirds up, which is where speech sits.
      let phase = Double(index) * 2 * Double.pi * 180 / 16000
      samples[index] = Int16(sin(phase) * 2300)
    }
    let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
    for name in ["0.pcm", "1.pcm"] {
      try? data.write(to: URL(fileURLWithPath: directory + "/" + name))
    }
  }

  func probeGrammar() {
    let source = ProcessInfo.processInfo.environment["RF_VOICE_HEARD"] ?? ""
    let heard = (try? String(contentsOfFile: source, encoding: .utf8)) ?? ""
    let grammar = Settings.shared.grammar()
    var lines: [String] = []
    for sentence in heard.split(separator: "\n").map(String.init) {
      let trimmed = sentence.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }
      let matches = grammar.matches(in: trimmed)
      if matches.isEmpty {
        lines.append("heard|\(trimmed)|none|")
      } else {
        for one in matches {
          lines.append("heard|\(trimmed)|\(one.command.rawValue)|\(one.phrase)"
                       + "|\(one.couldGrow ? "grows" : "final")")
        }
      }
    }
    try? (lines.joined(separator: "\n") + "\n")
      .write(toFile: self.session + "/grammar.probe", atomically: true, encoding: .utf8)
    NSApp.terminate(nil)
  }

  // What the overlay makes of the recorder's level stream, rewritten on every
  // poll so a case can watch the alarm arm itself and then clear. Whether the
  // alarm reaches the row and the menu bar is not visible from the source, and
  // an alarm nobody can see is the failure it exists to prevent.
  func probeLevel() {
    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      guard let self = self, let view = self.paletteView else { return }
      // Drawn and then read, so what is reported is what a person would be
      // looking at and not what the flags say should have been drawn.
      view.display()
      let alarmed = view.namedRects["silence"] != nil
      let title = self.statusItem?.button?.attributedTitle.string ?? ""
      let lines = [
        "input-reported \(self.inputLevel.reported ? 1 : 0)",
        "input-dead \(self.inputLevel.isDead ? 1 : 0)",
        "input-reading \(self.inputLevel.reading)",
        "alarm \(alarmed ? 1 : 0)",
        "alarm-text \(alarmed ? self.silenceAlarmText : "")",
        "meter \(view.namedRects["meter"] != nil ? 1 : 0)",
        "menu-alarm \(title.contains("NO SOUND") ? 1 : 0)",
      ]
      if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
          try? png.write(to: URL(fileURLWithPath: self.session
                                   + (alarmed ? "/palette-alarm.png" : "/palette-live.png")))
        }
      }
      try? (lines.joined(separator: "\n") + "\n")
        .write(toFile: self.session + "/level.probe", atomically: true, encoding: .utf8)
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
      // Asked of the window and not counted off its content view. Every control
      // lives inside a tab page now, and a probe that reads the top level finds
      // an empty window and calls it a pass.
      func descend(_ view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descend($0) }
      }
      let all = window.contentView.map { descend($0) } ?? []
      let buttons = all.compactMap { $0 as? NSButton }
      let shortcutButtons: [NSButton] = self.settingsWindow?.shortcutButtons ?? []
      let tabs: [String] = self.settingsWindow?.tabTitles ?? []
      let buttonTitles: String = buttons.map { $0.title }.joined(separator: ",")
      let shortcutTitles: String = shortcutButtons.map { $0.title }.joined(separator: ",")
      let editors: Int = all.compactMap { $0 as? NSTextView }.count
      let tables: Int = all.compactMap { $0 as? NSTableView }.count
      let overPalette: Bool =
        self.paletteWindow.map { window.frame.intersects($0.frame) } ?? false
      var lines: [String] = []
      lines.append("opened \(window.isVisible ? 1 : 0)")
      lines.append("tabs " + tabs.joined(separator: ","))
      lines.append("shortcut-buttons \(shortcutButtons.count)")
      lines.append("buttons \(buttons.count)")
      lines.append("titles " + buttonTitles)
      lines.append("shortcut-titles " + shortcutTitles)
      lines.append("text-views \(editors)")
      lines.append("tables \(tables)")
      lines.append("level \(window.level.rawValue)")
      lines.append("palette-level \(self.paletteWindow?.level.rawValue ?? 0)")
      lines.append("over-palette \(overPalette ? 1 : 0)")
      if let view = window.contentView,
         let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
          try? png.write(to: URL(fileURLWithPath: self.session + "/settings.png"))
        }
      }
      // Asked of each page, because a row laid out past the bottom of a tab is
      // a row nobody can reach and the content view knows nothing about it.
      var outside = 0
      for page in (window.contentView?.subviews.compactMap { $0 as? NSTabView } ?? []) {
        for item in page.tabViewItems {
          guard let view = item.view else { continue }
          outside += view.subviews.filter { !view.bounds.contains($0.frame) }.count
        }
      }
      lines.append("rows-outside \(outside)")
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
  // The documentation shots. Draws the marks over whatever is behind it and
  // reports where the palette ended up, so the crop can be exact rather than
  // guessed. RF_POSTER_QUIET leaves draw mode alone, which is how the palette
  // is caught in the narrow row it wears while a person is only talking.
  func probePoster() {
    guard let screen = NSScreen.main else { return }
    let size = screen.frame.size
    let quiet = ProcessInfo.processInfo.environment["RF_POSTER_QUIET"] == "1"

    // A level for the meter to show. There is no recorder behind a poster, so
    // without this the picture advertises the meter in the one state that means
    // it has heard nothing yet, which is both the least useful thing to show
    // and not what a session looks like.
    writePosterLevel()
    inputLevel.poll()

    if !quiet {
      setDrawing(true)

      func at(_ fx: CGFloat, _ fy: CGFloat) -> NSPoint {
        NSPoint(x: size.width * fx, y: size.height * fy)
      }

      // Two marks and no more. The point of the picture is the tool, and a
      // screen covered in ink says nothing about how it is used.
      tool = .rect
      colorIndex = 0
      width = 5
      beginStroke(at: at(0.278, 0.320), screen: 0)
      extendStroke(to: at(0.464, 0.390))
      endStroke(at: at(0.464, 0.390))

      tool = .text
      colorIndex = 0
      beginStroke(at: at(0.281, 0.286), screen: 0)
      if let index = editing { shapes[index].text = "this text is not centred" }
      commitText()

      tool = .arrow
      redrawMarks()
      for view in markViews { view.display() }
    }

    // Where the palette actually is, in screen points with the origin at the
    // bottom left, and how tall the screen is so the crop can turn that into
    // the top left the image file uses.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      guard let palette = self.paletteWindow else { return }
      let frame = palette.frame
      let lines = ["palette \(Int(frame.minX)) \(Int(frame.minY)) " +
                   "\(Int(frame.width)) \(Int(frame.height))",
                   "screen \(Int(size.width)) \(Int(size.height))"]
      try? (lines.joined(separator: "\n") + "\n")
        .write(toFile: self.session + "/poster.probe", atomically: true,
               encoding: .utf8)
    }
  }

  func probeClearButton() {
    setDrawing(true)
    tool = .pen
    beginStroke(at: NSPoint(x: 200, y: 200), screen: 0)
    extendStroke(to: NSPoint(x: 400, y: 300))
    endStroke(at: NSPoint(x: 400, y: 300))
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      guard let view = self.paletteView else { return }
      view.display()
      var lines = ["shapes-before \(self.shapes.count)"]
      if let rect = view.namedRects["clear"] {
        lines.append("named 1")
        view.press(at: NSPoint(x: rect.midX, y: rect.midY))
      } else {
        lines.append("named 0")
      }
      lines.append("shapes-after \(self.shapes.count)")
      self.setDrawing(false)
      try? (lines.joined(separator: "\n") + "\n")
        .write(toFile: self.session + "/clear.probe", atomically: true,
               encoding: .utf8)
    }
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
