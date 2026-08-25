// The menu bar item, which is the only part of a running session that is
// visible when the palette is hidden.
import Cocoa
import Carbon.HIToolbox

extension Overlay {
  // MARK: the menu bar

  // The palette can be dragged off a screen that was unplugged, covered by a
  // full screen application, or left behind by an overlay whose CLI died. The
  // menu bar is the one place on macOS that none of that can reach, so it
  // carries the proof that recording is live and, more importantly, a way out.
  func buildStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.imagePosition = .noImage
    statusItem = item
    rebuildMenu()
    refreshStatusItem()
    // The bar lays its items out from the right, and on a display with a notch
    // it will place one in the hole rather than refuse it. The item is then
    // drawn, clickable and invisible, which is worse than absent, so the one
    // thing the tool can do is say which of those happened.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.checkStatusItemVisible() }
  }

  func checkStatusItemVisible() {
    guard let bar = statusItem?.button?.window else {
      warn("the menu bar had no room for the recording indicator.")
      warn("  fix: remove an icon from the menu bar, then start again.")
      warn("  the palette on the screen and recordfeedback stop both still work.")
      return
    }
    guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(bar.frame) }),
          let left = screen.auxiliaryTopLeftArea,
          let right = screen.auxiliaryTopRightArea else { return }
    guard bar.frame.maxX > left.maxX && bar.frame.minX < right.minX else { return }
    warn("the recording indicator landed behind this display's notch, so it is"
         + " there but cannot be seen.")
    warn("  the menu bar is full: the strips beside the notch are"
         + " \(Int(left.width)) and \(Int(right.width)) points wide and both are taken.")
    warn("  fix: remove an icon from the menu bar, or hold command and drag one"
         + " off it, then start the session again.")
    warn("  the palette on the screen and recordfeedback stop both still work.")
  }

  func refreshStatusItem() {
    guard let button = statusItem?.button else { return }
    let elapsed = Int(Date().timeIntervalSince(startedAt))
    let clock = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    let text = NSMutableAttributedString()
    let dot = NSAttributedString(
      string: stopping ? "\u{25A0} " : "\u{25CF} ",
      attributes: [.foregroundColor: stopping
                     ? NSColor.secondaryLabelColor
                     : NSColor(srgbRed: 0.90, green: 0.20, blue: 0.17,
                               alpha: pulseOn ? 1.0 : 0.35),
                   .font: NSFont.systemFont(ofSize: 11)])
    text.append(dot)
    text.append(NSAttributedString(
      string: stopping ? "stopping" : clock,
      attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]))
    // The menu bar is the one place a full screen application cannot cover and
    // a palette dragged out of reach cannot hide, so an alarm that does not
    // reach it is one the user can be sitting in front of and never see.
    if !stopping && inputLevel.alarming {
      text.append(NSAttributedString(
        string: "  NO SOUND",
        attributes: [.foregroundColor: NSColor(srgbRed: 0.95, green: 0.26, blue: 0.21,
                                               alpha: pulseOn ? 1.0 : 0.45),
                     .font: NSFont.systemFont(ofSize: 11, weight: .bold)]))
    }
    button.attributedTitle = text
    if stopping {
      button.toolTip = "recordfeedback is finishing the session"
    } else if inputLevel.alarming {
      button.toolTip = "recordfeedback is recording silence, at "
        + inputLevel.reading + ". Nothing said now is being kept."
    } else {
      button.toolTip = "recordfeedback is recording. \(shots) screenshot"
        + (shots == 1 ? "" : "s") + " so far."
    }
  }

  func rebuildMenu() {
    guard let item = statusItem else { return }
    let menu = NSMenu()
    menu.autoenablesItems = false

    let header = NSMenuItem(title: "Recording this session", action: nil, keyEquivalent: "")
    header.isEnabled = false
    menu.addItem(header)
    menu.addItem(.separator())

    for action in [Action.draw, .screenshot, .region, .undo, .clear, .hide] {
      menu.addItem(menuItem(action))
    }

    menu.addItem(.separator())
    let settings = NSMenuItem(title: "Shortcuts and settings...",
                              action: #selector(openSettings), keyEquivalent: "")
    settings.target = self
    menu.addItem(settings)

    menu.addItem(.separator())
    menu.addItem(menuItem(.stop))

    // The way out of an overlay whose session nobody is listening to any more.
    // It says what it leaves behind, because quitting the window is not the
    // same as ending the recording and the user has to know which one they got.
    let quit = NSMenuItem(title: "Force quit the overlay",
                          action: #selector(forceQuit), keyEquivalent: "")
    quit.target = self
    quit.toolTip = "Closes this window only. The recording keeps running, and"
      + " recordfeedback stop still finishes the session with nothing lost."
    menu.addItem(quit)

    item.menu = menu
  }

  // The shortcut is written into the title rather than bound as a key
  // equivalent, because the same combination is already a global hotkey and
  // binding it twice fires it twice while the overlay is frontmost.
  func menuItem(_ action: Action) -> NSMenuItem {
    let key = Settings.shared.shortcut(action)
    let item = NSMenuItem(title: action.title + "  (" + key.display + ")",
                          action: #selector(menuAction(_:)), keyEquivalent: "")
    item.target = self
    item.representedObject = action.rawValue
    if action == .draw { item.state = drawing ? .on : .off }
    if action == .hide { item.state = marksHidden ? .on : .off }
    return item
  }

  @objc private func menuAction(_ sender: NSMenuItem) {
    guard let raw = sender.representedObject as? String,
          let action = Action(rawValue: raw) else { return }
    perform(action)
    rebuildMenu()
  }

  @objc private func forceQuit() {
    warn("force quit from the menu bar. The recording is still running.")
    warn("  finish the session with: recordfeedback stop")
    NSApp.terminate(nil)
  }

  @objc func openSettings() {
    if settingsWindow == nil {
      settingsWindow = SettingsWindow(overlay: self)
    }
    if mayTakeFocus() { NSApp.activate(ignoringOtherApps: true) }
    settingsWindow?.show()
  }
}
