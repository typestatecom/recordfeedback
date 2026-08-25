// Shared by every file in the overlay.
import Cocoa

func warn(_ message: String) {
  FileHandle.standardError.write(("rf-overlay: " + message + "\n").data(using: .utf8)!)
}

// Whether this process may take the keyboard and come to the front.
//
// A session must: draw mode is useless if the keys go to the application
// underneath. A test must not: the suite runs on the machine somebody is
// working on, and every case that entered draw mode pulled the keyboard out of
// whatever they were typing in.
func mayTakeFocus() -> Bool {
  #if RF_PROBES
  return ProcessInfo.processInfo.environment["RF_OVERLAY_SELFTEST"] == nil
  #else
  return true
  #endif
}
