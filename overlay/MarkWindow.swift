// The windows the marks are drawn in, one per screen.
import Cocoa

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
