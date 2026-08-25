// The entry point. Swift allows top level statements in main.swift and
// nowhere else, so the process starts here and the controller lives in
// Overlay.swift.
import Cocoa
import Carbon.HIToolbox
import Speech

// Screen Recording is the permission that breaks this tool silently: without it
// screencapture still writes a file and the file is only the wallpaper. doctor
// asks here rather than guessing from the pixels of a shot.
// The CLI prints the key list at the start of every session, and a second copy
// of it in the shell script is a copy that goes stale the first time anybody
// rebinds one. It asks the overlay instead.
if CommandLine.arguments.contains("--print-keys") {
  for action in Action.allCases {
    print(action.rawValue + " " + Settings.shared.shortcut(action).plain)
  }
  exit(0)
}
if CommandLine.arguments.contains("--check-capture") {
  exit(CGPreflightScreenCaptureAccess() ? 0 : 1)
}
if CommandLine.arguments.contains("--request-capture") {
  CGRequestScreenCaptureAccess()
  exit(0)
}
// Asked without requesting, so doctor can report the permission without putting
// a dialog on the screen of somebody who only wanted a status line.
if CommandLine.arguments.contains("--check-speech") {
  let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
  let state: String
  switch SFSpeechRecognizer.authorizationStatus() {
  case .authorized: state = "granted"
  case .denied: state = "refused"
  case .restricted: state = "restricted"
  case .notDetermined: state = "not asked yet"
  @unknown default: state = "unknown"
  }
  print("permission " + state)
  print("available \(recognizer?.isAvailable == true ? 1 : 0)")
  print("on-device \(recognizer?.supportsOnDeviceRecognition == true ? 1 : 0)")
  print("enabled \(Settings.shared.voiceEnabled ? 1 : 0)")
  exit(0)
}

let application = NSApplication.shared
let controller = Overlay()
application.delegate = controller
application.setActivationPolicy(.accessory)
application.run()
