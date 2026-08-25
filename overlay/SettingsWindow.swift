import Cocoa
import Carbon.HIToolbox

// A session takes seven key combinations away from every other application on
// the machine for as long as it runs, so which seven has to be the user's
// choice and not the author's. Recording a key rather than typing its name is
// the only way to bind one without a table of key codes in a README.
//
// Voice control has the same problem in a different shape: what a person says
// to reach a command is their own turn of phrase, so the phrases are a list
// they edit and not one the author fixed.
final class SettingsWindow: NSWindowController {
  private weak var overlay: Overlay?
  private var rows: [Action: NSButton] = [:]
  private var notes: [Action: NSTextField] = [:]
  private var recording: Action?
  private var monitor: Any?

  private var voiceSwitch: NSButton?
  private var triggerField: NSTextField?
  private var escapeField: NSTextField?
  private var phraseView: NSTextView?
  private var commandTable: NSTableView?
  private var phraseHeading: NSTextField?
  // Group headings and commands in one list, because the table draws them in
  // one column and a heading is a row that cannot be selected.
  private var listing: [VoiceCommand?] = []
  private var selected: VoiceCommand?

  // What the window is made of, asked of the window rather than counted off the
  // content view. Tabs put every control inside a page, and a probe that reads
  // the top level finds an empty window and calls it a pass.
  private(set) var tabTitles: [String] = []
  private weak var tabView: NSTabView?

  func showVoiceTab() {
    guard let tabs = tabView, tabs.tabViewItems.count > 1 else { return }
    tabs.selectTabViewItem(at: 1)
  }

  var shortcutButtons: [NSButton] { Action.allCases.compactMap { rows[$0] } }

  // What the phrase editor is showing. An editor that comes up empty over a
  // selected command reads as a command with no phrases, and the first thing a
  // person does about that is type one in and lose the rest.
  var editorText: String { phraseView?.string ?? "" }

  init(overlay: Overlay) {
    self.overlay = overlay
    let size = NSSize(width: 640, height: 540)
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable], backing: .buffered,
                          defer: false)
    window.title = "recordfeedback settings"
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
    let tabs = NSTabView(frame: content.bounds.insetBy(dx: 12, dy: 12))
    tabs.autoresizingMask = [.width, .height]

    let keys = NSTabViewItem(identifier: "shortcuts")
    keys.label = "Shortcuts"
    keys.view = NSView(frame: tabs.contentRect)
    buildShortcuts(in: keys.view!)
    tabs.addTabViewItem(keys)

    let voice = NSTabViewItem(identifier: "voice")
    voice.label = "Voice"
    voice.view = NSView(frame: tabs.contentRect)
    buildVoice(in: voice.view!)
    tabs.addTabViewItem(voice)

    tabTitles = [keys.label, voice.label]
    tabView = tabs
    content.addSubview(tabs)
  }

  // MARK: shortcuts

  private func buildShortcuts(in page: NSView) {
    var y = page.bounds.height - 44

    let heading = NSTextField(labelWithString:
      "These keys belong to recordfeedback for as long as a session is"
      + " running, and to nothing else.")
    heading.frame = NSRect(x: 20, y: y + 8, width: 560, height: 32)
    heading.font = NSFont.systemFont(ofSize: 11)
    heading.textColor = .secondaryLabelColor
    heading.lineBreakMode = .byWordWrapping
    heading.maximumNumberOfLines = 2
    page.addSubview(heading)

    for action in Action.allCases {
      y -= 40
      let label = NSTextField(labelWithString: action.title)
      label.frame = NSRect(x: 20, y: y + 6, width: 220, height: 18)
      label.font = NSFont.systemFont(ofSize: 13)
      page.addSubview(label)

      let button = NSButton(title: "", target: self, action: #selector(startRecording(_:)))
      button.frame = NSRect(x: 244, y: y, width: 104, height: 28)
      button.bezelStyle = .rounded
      button.tag = Action.allCases.firstIndex(of: action) ?? 0
      page.addSubview(button)
      rows[action] = button

      let note = NSTextField(labelWithString: "")
      note.frame = NSRect(x: 356, y: y + 6, width: 220, height: 18)
      note.font = NSFont.systemFont(ofSize: 10)
      note.textColor = .systemRed
      page.addSubview(note)
      notes[action] = note
    }

    let reset = NSButton(title: "Restore defaults", target: self,
                         action: #selector(restoreDefaults))
    reset.frame = NSRect(x: 20, y: 16, width: 150, height: 30)
    reset.bezelStyle = .rounded
    page.addSubview(reset)

    let where_ = NSTextField(labelWithString: Settings.shared.path)
    where_.frame = NSRect(x: 180, y: 22, width: 400, height: 16)
    where_.font = NSFont.systemFont(ofSize: 9)
    where_.textColor = .tertiaryLabelColor
    where_.lineBreakMode = .byTruncatingHead
    page.addSubview(where_)
  }

  // MARK: voice

  private func buildVoice(in page: NSView) {
    let width = page.bounds.width
    var y = page.bounds.height - 38

    let toggle = NSButton(checkboxWithTitle: "Listen for spoken commands while recording",
                          target: self, action: #selector(toggleVoice))
    toggle.frame = NSRect(x: 20, y: y, width: 420, height: 22)
    page.addSubview(toggle)
    voiceSwitch = toggle
    y -= 34

    let why = NSTextField(labelWithString:
      "Recognition runs on this Mac and no audio leaves it. macOS asks for"
      + " Speech Recognition the first time a session starts listening."
      + " Spoken commands are kept out of the transcript and listed on their own.")
    why.frame = NSRect(x: 20, y: y - 14, width: width - 40, height: 44)
    why.font = NSFont.systemFont(ofSize: 11)
    why.textColor = .secondaryLabelColor
    why.lineBreakMode = .byWordWrapping
    why.maximumNumberOfLines = 3
    page.addSubview(why)
    y -= 48

    let triggerLabel = NSTextField(labelWithString: "Say this first:")
    triggerLabel.frame = NSRect(x: 20, y: y + 4, width: 100, height: 18)
    triggerLabel.font = NSFont.systemFont(ofSize: 12)
    page.addSubview(triggerLabel)

    let trigger = NSTextField(string: Settings.shared.voiceTrigger)
    trigger.frame = NSRect(x: 124, y: y, width: 120, height: 24)
    trigger.target = self
    trigger.action = #selector(voiceWordsChanged)
    page.addSubview(trigger)
    triggerField = trigger

    let escapeLabel = NSTextField(labelWithString: "Mean the words:")
    escapeLabel.frame = NSRect(x: 264, y: y + 4, width: 110, height: 18)
    escapeLabel.font = NSFont.systemFont(ofSize: 12)
    page.addSubview(escapeLabel)

    let escape = NSTextField(string: Settings.shared.voiceEscape)
    escape.frame = NSRect(x: 378, y: y, width: 200, height: 24)
    escape.target = self
    escape.action = #selector(voiceWordsChanged)
    page.addSubview(escape)
    escapeField = escape
    y -= 30

    let hint = NSTextField(labelWithString:
      "Without a first word, \"the rectangle is wrong\" would change the tool.")
    hint.frame = NSRect(x: 20, y: y - 4, width: width - 40, height: 16)
    hint.font = NSFont.systemFont(ofSize: 10)
    hint.textColor = .tertiaryLabelColor
    page.addSubview(hint)
    y -= 16

    rebuildListing()

    let tableHeight = y - 62
    let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 240, height: tableHeight))
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
    column.width = 224
    table.addTableColumn(column)
    table.headerView = nil
    table.rowHeight = 22
    table.delegate = self
    table.dataSource = self
    table.selectionHighlightStyle = .regular
    let scroller = NSScrollView(frame: NSRect(x: 20, y: 56, width: 240, height: tableHeight))
    scroller.hasVerticalScroller = true
    scroller.borderType = .bezelBorder
    scroller.documentView = table
    page.addSubview(scroller)
    commandTable = table

    let heading = NSTextField(labelWithString: "")
    heading.frame = NSRect(x: 276, y: 56 + tableHeight - 20, width: width - 296, height: 18)
    heading.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    page.addSubview(heading)
    phraseHeading = heading

    let note = NSTextField(labelWithString: "One phrase per line. Any of them reaches it.")
    note.frame = NSRect(x: 276, y: 56 + tableHeight - 38, width: width - 296, height: 16)
    note.font = NSFont.systemFont(ofSize: 10)
    note.textColor = .tertiaryLabelColor
    page.addSubview(note)

    let editorHeight = tableHeight - 44
    let editorWidth = width - 296
    let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: editorWidth, height: editorHeight))
    editor.isRichText = false
    editor.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    editor.isAutomaticQuoteSubstitutionEnabled = false
    // A text view built by hand rather than out of a nib has none of this set,
    // and without it the view lays out against a container of no size and shows
    // nothing however much text it holds.
    editor.minSize = NSSize(width: 0, height: 0)
    editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.autoresizingMask = [.width]
    editor.textContainer?.containerSize = NSSize(width: editorWidth,
                                                 height: CGFloat.greatestFiniteMagnitude)
    editor.textContainer?.widthTracksTextView = true
    editor.delegate = self
    let editorScroller = NSScrollView(
      frame: NSRect(x: 276, y: 56, width: width - 296, height: editorHeight))
    editorScroller.hasVerticalScroller = true
    editorScroller.borderType = .bezelBorder
    editorScroller.documentView = editor
    page.addSubview(editorScroller)
    phraseView = editor

    let restore = NSButton(title: "Restore default phrases", target: self,
                           action: #selector(restorePhrases))
    restore.frame = NSRect(x: 20, y: 16, width: 190, height: 30)
    restore.bezelStyle = .rounded
    page.addSubview(restore)
  }

  private func rebuildListing() {
    listing = []
    var lastGroup = ""
    for command in VoiceCommand.allCases {
      if command.group != lastGroup {
        lastGroup = command.group
        listing.append(nil)
      }
      listing.append(command)
    }
  }

  private func groupTitle(at row: Int) -> String {
    for index in stride(from: row, through: 0, by: -1) {
      if let command = listing[index] { return command.group }
    }
    return ""
  }

  private func showPhrases(for command: VoiceCommand) {
    selected = command
    phraseHeading?.stringValue = command.title
    let phrases = Settings.shared.phrasesOrDefaults()[command] ?? []
    phraseView?.string = phrases.joined(separator: "\n")
  }

  private func savePhrases() {
    guard let command = selected, let text = phraseView?.string else { return }
    Settings.shared.setVoicePhrases(command, to: text.components(separatedBy: "\n"))
  }

  @objc private func toggleVoice() {
    Settings.shared.setVoiceEnabled(voiceSwitch?.state == .on)
    // Turning it on mid session starts listening now, rather than at the next
    // session, because the user turned it on to use it in this one.
    overlay?.voiceSettingChanged()
  }

  @objc private func voiceWordsChanged() {
    Settings.shared.setVoiceWords(trigger: triggerField?.stringValue ?? "",
                                  escape: escapeField?.stringValue ?? "")
    // Read back, because an empty trigger is refused and the field has to show
    // what is in force rather than what was typed.
    triggerField?.stringValue = Settings.shared.voiceTrigger
    escapeField?.stringValue = Settings.shared.voiceEscape
    overlay?.voiceSettingChanged()
  }

  @objc private func restorePhrases() {
    Settings.shared.resetVoicePhrases()
    if let command = selected { showPhrases(for: command) }
    overlay?.voiceSettingChanged()
  }

  private func refresh() {
    for (action, button) in rows {
      button.title = recording == action ? "Press keys" : Settings.shared.shortcut(action).display
    }
    voiceSwitch?.state = Settings.shared.voiceEnabled ? .on : .off
    triggerField?.stringValue = Settings.shared.voiceTrigger
    escapeField?.stringValue = Settings.shared.voiceEscape
    if selected == nil, let first = listing.compactMap({ $0 }).first {
      showPhrases(for: first)
      if let row = listing.firstIndex(of: first) {
        commandTable?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      }
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

extension SettingsWindow: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int { listing.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                 row: Int) -> NSView? {
    let field = NSTextField(labelWithString: "")
    field.frame = NSRect(x: 4, y: 2, width: 216, height: 18)
    if let command = listing[row] {
      field.stringValue = "   " + command.title
      field.font = NSFont.systemFont(ofSize: 12)
    } else {
      field.stringValue = groupTitle(at: row + 1).uppercased()
      field.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
      field.textColor = .tertiaryLabelColor
    }
    let holder = NSView(frame: NSRect(x: 0, y: 0, width: 224, height: 22))
    holder.addSubview(field)
    return holder
  }

  // A heading is not a thing that can be edited, so it is not a thing that can
  // be selected either.
  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    listing[row] != nil
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    // Saved before moving on, or every edit is lost the moment the user picks
    // the next command to edit.
    savePhrases()
    guard let table = commandTable, table.selectedRow >= 0,
          let command = listing[table.selectedRow] else { return }
    showPhrases(for: command)
  }
}

extension SettingsWindow: NSTextViewDelegate {
  func textDidChange(_ notification: Notification) {
    // Saved as it is typed. A phrase list that only takes effect on some later
    // event is one a user tests, finds dead, and gives up on.
    savePhrases()
    overlay?.voiceSettingChanged()
  }
}
