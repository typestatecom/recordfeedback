// Shared by every file in the overlay.
import Cocoa

func warn(_ message: String) {
  FileHandle.standardError.write(("rf-overlay: " + message + "\n").data(using: .utf8)!)
}
