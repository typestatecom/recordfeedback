// Draw mode: entering and leaving it, the shapes it makes, the keys it takes
// over, and how the marks reach the screen.
import Cocoa
import Carbon.HIToolbox

extension Overlay {
  // MARK: modes

  func setDrawing(_ on: Bool) {
    if !on { commitText() }
    drawing = on
    for window in markWindows { window.ignoresMouseEvents = !on }
    if on {
      if mayTakeFocus() {
        NSApp.activate(ignoringOtherApps: true)
        markWindows.first?.makeKeyAndOrderFront(nil)
      }
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
  func leaveDrawing() { setDrawing(false) }

  func toggleHidden() {
    marksHidden.toggle()
    redrawMarks()
    paletteView?.needsDisplay = true
  }

  // The tool is the control a person reaches for first, so it is also the one
  // they press to put the pen down. Without this the only way out is a key the
  // palette does not name, while the overlay is holding every click on screen.
  func select(_ newTool: Tool) {
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

  func undo() {
    if editing != nil { commitText(); return }
    guard !shapes.isEmpty else { return }
    shapes.removeLast()
    redrawMarks()
  }

  func clear() {
    editing = nil
    shapes.removeAll()
    redrawMarks()
  }

  func commitText() {
    guard let index = editing else { return }
    editing = nil
    if index < shapes.count && shapes[index].text.isEmpty {
      shapes.remove(at: index)
    }
    redrawMarks()
    paletteView?.needsDisplay = true
  }

  func redrawMarks() {
    for view in markViews { view.needsDisplay = true }
  }

  // MARK: keys inside draw mode

  func handleKey(_ event: NSEvent) -> Bool {
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
  func widen(_ steps: Int) {
    width += 2 * CGFloat(steps)
    paletteView?.needsDisplay = true
  }

  func pick(_ index: Int) {
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

  func stroke(_ shape: Shape) {
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

  func rectBetween(_ a: NSPoint, _ b: NSPoint) -> NSRect {
    NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
           width: abs(a.x - b.x), height: abs(a.y - b.y))
  }

  func drawArrow(from start: NSPoint, to end: NSPoint,
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
}
