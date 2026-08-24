// The model: what can be drawn, and in what.
import Cocoa

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
