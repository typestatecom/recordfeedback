// The palette: the only part of the overlay the user points at.
import Cocoa

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

  // Where those labels sit, so a case can ask of one control whether it names
  // itself instead of counting tips against controls and trusting the two lists
  // to line up.
  var tipRects: [NSRect] { tips.map { $0.0 } }

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

  // Separate from mouseDown so that a probe can press a control without the
  // Accessibility permission a synthetic click needs, and press exactly what a
  // click would press rather than a copy of the same search.
  @discardableResult
  func press(at point: NSPoint) -> Bool {
    for (rect, action) in hits where rect.contains(point) {
      action()
      return true
    }
    return false
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if press(at: point) { return }
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
