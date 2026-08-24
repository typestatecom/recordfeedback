import Cocoa
import Carbon.HIToolbox

// A session takes seven key combinations away from every other application on
// the machine for as long as it runs, so which seven has to be the user's
// choice and not the author's. Recording a key rather than typing its name is
// the only way to bind one without a table of key codes in a README.
final class SettingsWindow: NSWindowController {
  private weak var overlay: Overlay?
  private var rows: [Action: NSButton] = [:]
  private var notes: [Action: NSTextField] = [:]
  private var recording: Action?
  private var monitor: Any?

  init(overlay: Overlay) {
    self.overlay = overlay
    let size = NSSize(width: 460, height: CGFloat(Action.allCases.count) * 40 + 132)
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable], backing: .buffered,
                          defer: false)
    window.title = "recordfeedback shortcuts"
    window.isReleasedWhenClosed = false
    // Above the palette, which is above everything else on the screen and is
    // where this window is opened from. Without this it comes up underneath
    // the row that opened it, and the row covers the last shortcut and the way
    // back to the defaults.
    window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
    super.init(window: window)
    build(in: window)
  }

  required init?(coder: NSCoder) { fatalError("not loaded from a nib") }

  func show() {
    refresh()
    window?.center()
    window?.makeKeyAndOrderFront(nil)
  }

  private func build(in window: NSWindow) {
    guard let content = window.contentView else { return }
    // The content view, not the window: the window is a title bar taller and
    // laying out from its height puts the first row above the top edge.
    var y = content.bounds.height - 56

    let heading = NSTextField(labelWithString:
      "These keys belong to recordfeedback for as long as a session is"
      + " running, and to nothing else.")
    heading.frame = NSRect(x: 20, y: y + 14, width: 420, height: 32)
    heading.font = NSFont.systemFont(ofSize: 11)
    heading.textColor = .secondaryLabelColor
    heading.lineBreakMode = .byWordWrapping
    heading.maximumNumberOfLines = 2
    content.addSubview(heading)

    for action in Action.allCases {
      y -= 40
      let label = NSTextField(labelWithString: action.title)
      label.frame = NSRect(x: 20, y: y + 6, width: 200, height: 18)
      label.font = NSFont.systemFont(ofSize: 13)
      content.addSubview(label)

      let button = NSButton(title: "", target: self, action: #selector(startRecording(_:)))
      button.frame = NSRect(x: 224, y: y, width: 104, height: 28)
      button.bezelStyle = .rounded
      button.tag = Action.allCases.firstIndex(of: action) ?? 0
      content.addSubview(button)
      rows[action] = button

      let note = NSTextField(labelWithString: "")
      note.frame = NSRect(x: 334, y: y + 6, width: 108, height: 18)
      note.font = NSFont.systemFont(ofSize: 10)
      note.textColor = .systemRed
      content.addSubview(note)
      notes[action] = note
    }

    let reset = NSButton(title: "Restore defaults", target: self,
                         action: #selector(restoreDefaults))
    reset.frame = NSRect(x: 20, y: 20, width: 150, height: 30)
    reset.bezelStyle = .rounded
    content.addSubview(reset)

    let where_ = NSTextField(labelWithString: Settings.shared.path)
    where_.frame = NSRect(x: 180, y: 26, width: 262, height: 16)
    where_.font = NSFont.systemFont(ofSize: 9)
    where_.textColor = .tertiaryLabelColor
    where_.lineBreakMode = .byTruncatingHead
    content.addSubview(where_)
  }

  private func refresh() {
    for (action, button) in rows {
      button.title = recording == action ? "Press keys" : Settings.shared.shortcut(action).display
    }
  }

  @objc private func startRecording(_ sender: NSButton) {
    guard sender.tag < Action.allCases.count else { return }
    let action = Action.allCases[sender.tag]
    stopRecording()
    recording = action
    notes[action]?.stringValue = ""
    refresh()

    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.captured(event)
      return nil
    }
  }

  private func captured(_ event: NSEvent) {
    guard let action = recording else { return }
    let flags = event.modifierFlags
    if Int(event.keyCode) == kVK_Escape && !flags.contains(.option) {
      stopRecording()
      refresh()
      return
    }
    let candidate = Shortcut(keyCode: Int(event.keyCode),
                             option: flags.contains(.option),
                             shift: flags.contains(.shift),
                             command: flags.contains(.command),
                             control: flags.contains(.control))

    // A key with no name here cannot be registered, and a key with no modifier
    // would be taken away from every application on the machine.
    if Keys.name(for: candidate.keyCode) == "?" {
      notes[action]?.stringValue = "letters and digits"
    } else if candidate.isEmpty {
      notes[action]?.stringValue = "needs a modifier"
    } else if let clash = Settings.shared.conflict(candidate, ignoring: action) {
      notes[action]?.stringValue = "held by " + clash.rawValue
    } else {
      Settings.shared.set(action, to: candidate)
      notes[action]?.stringValue = ""
      overlay?.reinstallHotkeys()
      stopRecording()
    }
    refresh()
  }

  private func stopRecording() {
    if let monitor = monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    recording = nil
  }

  @objc private func restoreDefaults() {
    Settings.shared.reset()
    for note in notes.values { note.stringValue = "" }
    overlay?.reinstallHotkeys()
    refresh()
  }
}
