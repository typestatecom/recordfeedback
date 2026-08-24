// A stand-in screen for the documentation shots. The overlay draws over
// whatever is on the display, and what is on this machine's display is the
// author's work, so the shots are taken over this instead: no real paths, no
// real code, nothing that has to be checked before it is published.
import Cocoa

final class Backdrop: NSObject, NSApplicationDelegate {
  var windows: [NSWindow] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    for screen in NSScreen.screens {
      let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                            backing: .buffered, defer: false, screen: screen)
      window.setFrame(screen.frame, display: true)
      window.level = .normal
      window.isOpaque = true
      window.contentView = Scene(frame: NSRect(origin: .zero, size: screen.frame.size))
      window.orderFrontRegardless()
      windows.append(window)
    }
    NSApp.activate(ignoringOtherApps: true)
  }
}

final class Scene: NSView {
  override func draw(_ rect: NSRect) {
    NSColor(srgbRed: 0.09, green: 0.10, blue: 0.13, alpha: 1).setFill()
    bounds.fill()

    let card = NSRect(x: bounds.width * 0.14, y: bounds.height * 0.16,
                      width: bounds.width * 0.72, height: bounds.height * 0.68)
    round(card, radius: 14, fill: NSColor(srgbRed: 0.13, green: 0.14, blue: 0.18, alpha: 1))

    let bar = NSRect(x: card.minX, y: card.maxY - 44, width: card.width, height: 44)
    round(bar, radius: 14, fill: NSColor(srgbRed: 0.17, green: 0.18, blue: 0.23, alpha: 1))
    NSRect(x: bar.minX, y: bar.minY, width: bar.width, height: 14)
      .fill(using: .sourceOver)
    for (n, colour) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
      colour.setFill()
      NSBezierPath(ovalIn: NSRect(x: bar.minX + 18 + CGFloat(n) * 20,
                                  y: bar.midY - 6, width: 12, height: 12)).fill()
    }
    text("Settings", at: NSPoint(x: bar.minX + 92, y: bar.midY - 9), size: 15,
         weight: .medium, colour: NSColor(white: 0.75, alpha: 1))

    // A heading and a row of fields, which is enough shape for an arrow to have
    // something to point at without any of it meaning anything.
    var y = bar.minY - 68
    text("Notifications", at: NSPoint(x: card.minX + 44, y: y), size: 26,
         weight: .semibold, colour: NSColor(white: 0.95, alpha: 1))
    y -= 52
    for label in ["Email digest", "Mentions", "Weekly summary", "Product updates"] {
      let row = NSRect(x: card.minX + 44, y: y - 14, width: card.width - 88, height: 52)
      round(row, radius: 9, fill: NSColor(srgbRed: 0.16, green: 0.17, blue: 0.22, alpha: 1))
      text(label, at: NSPoint(x: row.minX + 22, y: row.midY - 10), size: 16,
           weight: .regular, colour: NSColor(white: 0.82, alpha: 1))
      let toggle = NSRect(x: row.maxX - 76, y: row.midY - 13, width: 52, height: 26)
      round(toggle, radius: 13,
            fill: NSColor(srgbRed: 0.20, green: 0.52, blue: 0.95, alpha: 1))
      NSColor.white.setFill()
      NSBezierPath(ovalIn: NSRect(x: toggle.maxX - 24, y: toggle.midY - 10,
                                  width: 20, height: 20)).fill()
      y -= 68
    }

    let save = NSRect(x: card.maxX - 168, y: card.minY + 36, width: 124, height: 42)
    round(save, radius: 9, fill: NSColor(srgbRed: 0.20, green: 0.52, blue: 0.95, alpha: 1))
    text("Save", at: NSPoint(x: save.midX - 20, y: save.midY - 10), size: 16,
         weight: .semibold, colour: .white)
  }

  private func round(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
  }

  private func text(_ string: String, at point: NSPoint, size: CGFloat,
                    weight: NSFont.Weight, colour: NSColor) {
    (string as NSString).draw(at: point, withAttributes: [
      .font: NSFont.systemFont(ofSize: size, weight: weight),
      .foregroundColor: colour,
    ])
  }
}

let application = NSApplication.shared
let backdrop = Backdrop()
application.delegate = backdrop
application.setActivationPolicy(.accessory)
application.run()
