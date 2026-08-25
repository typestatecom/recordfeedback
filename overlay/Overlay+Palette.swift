// The palette: its layout, its controls and where it sits.
import Cocoa
import Carbon.HIToolbox

extension Overlay {
  // MARK: the palette

  func drawPalette(in view: PaletteView) {
    view.clearHits()
    view.clearTips()
    view.clearNames()
    view.clearHints()
    let bounds = view.bounds
    let alarm = inputLevel.alarming
    let shell = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                             xRadius: 13, yRadius: 13)
    // The alarm colours the whole row rather than lighting one small control,
    // because the user is looking at their own work and not at this window.
    if alarm {
      NSColor(srgbRed: 0.30, green: 0.05, blue: 0.05, alpha: 0.97).setFill()
    } else {
      NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 0.94).setFill()
    }
    shell.fill()
    if alarm {
      NSColor(srgbRed: 1, green: 0.35, blue: 0.30, alpha: 0.95).setStroke()
      shell.lineWidth = 2
    } else {
      NSColor(white: 1, alpha: 0.14).setStroke()
      shell.lineWidth = 1
    }
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

    // The clock proves the recorder is running. It does not prove it is hearing
    // anything, and the difference between those two is a whole lost session.
    drawInputMeter(in: NSRect(x: x, y: mid - 11, width: 26, height: 22), view: view)
    x += 34

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

      // The other way back out of a mistake. It was a key and nothing else, and
      // a key that appears nowhere on the screen is one the person who bound it
      // still goes hunting for.
      let clearKey = Settings.shared.shortcut(.clear)
      let wipe = NSRect(x: x, y: mid - 15, width: 56, height: 30)
      control(wipe, in: view, on: false, key: clearKey.display,
              tip: "clear the marks (" + clearKey.plain + ")") {
        [weak self] in self?.clear()
      }
      label("Clear", at: NSPoint(x: wipe.midX - 18, y: mid - 7), size: 13,
            weight: .semibold, color: NSColor(white: 1, alpha: 0.95))
      view.name("clear", wipe)
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

    // A spoken command produces no click and no keypress. Several of these do
    // something the user cannot see from where they are looking, and a command
    // that was misheard is one they need to catch at the moment it happens.
    if let heard = voiceHeardTitle, Date().timeIntervalSince(voiceHeardAt) < 2.5 {
      let text = "heard: " + heard
      label(text, at: NSPoint(x: 14, y: bounds.maxY - 14), size: 10, weight: .semibold,
            color: NSColor(srgbRed: 0.45, green: 0.85, blue: 1, alpha: 0.95))
      view.name("voice-heard", NSRect(x: 14, y: bounds.maxY - 14, width: 100, height: 11))
    } else if let failure = voiceFailure {
      // Truncated to the first sentence. The whole of it is in the log and in
      // the tooltip, and the row is not where a paragraph goes.
      let first = failure.split(separator: ".").first.map(String.init) ?? failure
      label("voice control off: " + first, at: NSPoint(x: 14, y: bounds.maxY - 14),
            size: 9, weight: .regular,
            color: NSColor(srgbRed: 1, green: 0.75, blue: 0.35, alpha: 0.95))
      view.name("voice-failed", NSRect(x: 14, y: bounds.maxY - 14, width: 100, height: 11))
    }

    if alarm {
      // Above the row rather than inside it, so the words appear without
      // shifting a single control out from under the user's cursor.
      let text = silenceAlarmText
      let font = NSFont.systemFont(ofSize: 11, weight: .bold)
      let size = (text as NSString).size(withAttributes: [.font: font])
      let at = NSPoint(x: min(bounds.midX - size.width / 2, bounds.maxX - size.width - 14),
                       y: bounds.maxY - 15)
      label(text, at: at, size: 11, weight: .bold,
            color: NSColor(srgbRed: 1, green: 0.55, blue: 0.5, alpha: 1))
      view.name("silence", NSRect(origin: at, size: size))
    } else if editing != nil {
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
  func drawAnchoredEnd(in view: PaletteView, bounds: NSRect, mid: CGFloat) {
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

    // In both rows and never moving, because whether anything is listening is a
    // thing the user checks mid sentence. It is drawn in both states rather
    // than only when listening: a control that appears only when it is on is
    // one nobody can find to turn on.
    let listening = voiceListening
    let ear = NSRect(x: right - 32, y: mid - 15, width: 32, height: 30)
    let listenKey = Settings.shared.shortcut(.listen)
    control(ear, in: view, on: listening, key: listenKey.display,
            tip: listening
              ? "listening for spoken commands (" + listenKey.plain + ")"
              : "not listening, spoken commands are off (" + listenKey.plain + ")") {
      [weak self] in self?.toggleListening()
    }
    drawMicIcon(in: ear, listening: listening,
                failed: voiceFailure != nil)
    view.name("listen", ear)
    right = ear.minX - 7

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
  func control(_ rect: NSRect, in view: PaletteView, on: Bool,
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

  func hint(_ text: String, under rect: NSRect, view: PaletteView) {
    guard !text.isEmpty else { return }
    let font = NSFont.systemFont(ofSize: 8, weight: .medium)
    let size = (text as NSString).size(withAttributes: [.font: font])
    let at = NSPoint(x: rect.midX - size.width / 2, y: 4)
    label(text, at: at, size: 8, weight: .medium,
          color: NSColor(white: 1, alpha: 0.45))
    view.addHint(NSRect(origin: at, size: size))
  }

  func drawGearIcon(in rect: NSRect, color: NSColor) {
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
  func drawRegionIcon(in rect: NSRect, color: NSColor) {
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
  func drawCameraIcon(in rect: NSRect, color: NSColor) {
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
  func drawToolIcon(_ candidate: Tool, in box: NSRect, color: NSColor) {
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

  func separator(at x: CGFloat, middle: CGFloat) {
    NSColor(white: 1, alpha: 0.15).setFill()
    NSBezierPath(rect: NSRect(x: x, y: middle - 12, width: 1, height: 24)).fill()
  }

  func label(_ text: String, at point: NSPoint, size: CGFloat,
                     weight: NSFont.Weight, color: NSColor) {
    (text as NSString).draw(at: point, withAttributes: [
      .font: NSFont.systemFont(ofSize: size, weight: weight),
      .foregroundColor: color,
    ])
  }
}

extension Overlay {
  // The meter is bars and not a number, because a person mid sentence reads a
  // shape and not a measurement. It carries a scale even in silence, so an
  // empty meter reads as an empty meter and never as a meter that is not there.
  func drawInputMeter(in rect: NSRect, view: PaletteView) {
    let bars = 5
    let gap: CGFloat = 2
    let barWidth = (rect.width - gap * CGFloat(bars - 1)) / CGFloat(bars)
    let level = inputLevel.meter
    let alarm = inputLevel.alarming
    let lit = Int((level * Double(bars)).rounded(.up))

    for index in 0..<bars {
      // Rising, so the meter reads as a level and not as a row of lights.
      let height = rect.height * (0.34 + 0.66 * CGFloat(index) / CGFloat(bars - 1))
      let bar = NSRect(x: rect.minX + CGFloat(index) * (barWidth + gap),
                       y: rect.minY, width: barWidth, height: height)
      let shape = NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5)
      if alarm {
        // Empty bars in the alarm colour, so the meter says the same thing the
        // row does rather than sitting there dark and ambiguous.
        NSColor(srgbRed: 1, green: 0.35, blue: 0.30, alpha: pulseOn ? 0.85 : 0.3).setFill()
      } else if !inputLevel.reported {
        NSColor(white: 1, alpha: 0.18).setFill()
      } else if index < lit {
        // The top of the scale is where clipping lives, so it is the one part
        // of the meter that is not the same colour as the rest.
        NSColor(srgbRed: index >= bars - 1 ? 1 : 0.36,
                green: index >= bars - 1 ? 0.72 : 0.86,
                blue: index >= bars - 1 ? 0.25 : 0.44, alpha: 0.95).setFill()
      } else {
        NSColor(white: 1, alpha: 0.16).setFill()
      }
      shape.fill()
    }

    view.name("meter", rect)
    view.addTip(rect, alarm
                  ? "the recorder is capturing silence, at " + inputLevel.reading
                  : "microphone level, " + inputLevel.reading)
  }
}

extension Overlay {
  // Whether anything is actually listening, and not merely whether it was asked
  // for. A microphone lit while the recogniser failed to start would be the
  // same lie the clock told before it had a meter beside it.
  var voiceListening: Bool {
    Settings.shared.voiceEnabled && voice != nil && voiceFailure == nil
  }

  // A microphone, struck through when nothing is listening. The strike is what
  // carries the state at a glance: a dimmed icon and a lit one are the same
  // shape, and this row is read mid sentence.
  func drawMicIcon(in rect: NSRect, listening: Bool, failed: Bool) {
    let colour: NSColor = failed
      ? NSColor(srgbRed: 1, green: 0.75, blue: 0.35, alpha: 0.95)
      : NSColor(white: 1, alpha: listening ? 1.0 : 0.5)
    colour.setFill()
    colour.setStroke()

    let body = NSRect(x: rect.midX - 3.5, y: rect.midY - 2, width: 7, height: 11)
    NSBezierPath(roundedRect: body, xRadius: 3.5, yRadius: 3.5).fill()

    let cradle = NSBezierPath()
    cradle.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY + 1),
                     radius: 6.5, startAngle: 200, endAngle: 340, clockwise: true)
    cradle.lineWidth = 1.5
    cradle.stroke()

    let stem = NSBezierPath()
    stem.move(to: NSPoint(x: rect.midX, y: rect.midY - 5.5))
    stem.line(to: NSPoint(x: rect.midX, y: rect.midY - 9))
    stem.lineWidth = 1.5
    stem.stroke()

    guard !listening else { return }
    let slash = NSBezierPath()
    slash.move(to: NSPoint(x: rect.midX - 8, y: rect.midY - 9))
    slash.line(to: NSPoint(x: rect.midX + 8, y: rect.midY + 9))
    slash.lineWidth = 1.8
    slash.stroke()
  }
}
