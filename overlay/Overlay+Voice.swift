// What a spoken command reaches, and the record of it having been said.
import Cocoa

extension Overlay {
  func startVoice() {
    guard Settings.shared.voiceEnabled else { return }
    #if RF_PROBES
    // Asking for Speech Recognition puts a system dialog on the screen of
    // whoever is running the tests, and it stays there until somebody answers
    // it. A case that is about the settings and not about listening must not be
    // able to do that.
    let environment = ProcessInfo.processInfo.environment
    if environment["RF_OVERLAY_SELFTEST"] != nil, environment["RF_VOICE_LISTEN"] != "1" {
      warn("voice control is configured but the probe build is not listening.")
      return
    }
    #endif
    let listener = VoiceListener(session: session, grammar: Settings.shared.grammar(),
                                 startedAt: startedAt)
    listener.delegate = self
    voice = listener
    listener.start()
  }

  // Started and stopped mid session, from a key and from the row, because the
  // window that also holds this switch is three clicks away and the user's
  // hands are off the keyboard. It writes the same setting the window shows: a
  // second, session only notion of listening would leave that window reading on
  // while nothing was listening.
  func toggleListening() {
    let wanted = !Settings.shared.voiceEnabled
    Settings.shared.setVoiceEnabled(wanted)
    voiceSettingChanged()
    // Said out loud either way. Starting is invisible until a command lands,
    // and stopping is invisible until one fails to.
    voiceHeardTitle = wanted ? "listening" : "listening off"
    voiceHeardAt = Date()
    settingsWindow?.refreshFromSettings()
    paletteView?.needsDisplay = true
    rebuildMenu()
    refreshStatusItem()
  }

  // Turning voice control on or off, or changing what can be said, takes effect
  // in the session that is running. A setting that only applies to the next
  // session is one a user changes, tests, finds dead, and gives up on.
  func voiceSettingChanged() {
    let wanted = Settings.shared.voiceEnabled
    if !wanted {
      voice?.stop()
      voice = nil
      voiceFailure = nil
      paletteView?.needsDisplay = true
      return
    }
    // Already listening, so only the grammar changed and the listener is
    // rebuilt around the new one.
    voice?.stop()
    voice = nil
    voiceFailure = nil
    startVoice()
  }

  // The commands are written down whether or not the transcript ends up being
  // scrubbed of them, because a session where the tool did something the user
  // did not ask for is one they need to be able to read back.
  func logCommand(_ match: VoiceMatch, at offset: TimeInterval) {
    var entry: [String: Any] = [
      "at": max(0, (offset * 10).rounded() / 10),
      "command": match.command.rawValue,
      "title": match.command.title,
      "phrase": match.phrase,
      "heard": match.heard,
    ]
    if voiceFailure != nil { entry["note"] = "acted on while voice control was failing" }
    var all = loadCommands()
    all.append(entry)
    guard let data = try? JSONSerialization.data(
            withJSONObject: all, options: [.prettyPrinted]) else { return }
    try? data.write(to: URL(fileURLWithPath: session + "/commands.json"), options: .atomic)
  }

  func loadCommands() -> [[String: Any]] {
    guard let data = FileManager.default.contents(atPath: session + "/commands.json"),
          let all = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    else { return [] }
    return all
  }

  // A spoken command produces no click and no keypress, so without this the
  // only sign it landed is the thing it did, and half of these do something the
  // user cannot see from where they are looking.
  func acknowledge(_ match: VoiceMatch) {
    voiceHeardTitle = match.command.title
    voiceHeardAt = Date()
    paletteView?.needsDisplay = true
    refreshStatusItem()
  }

  func perform(_ command: VoiceCommand) {
    switch command {
    case .draw: setDrawing(true)
    case .done: leaveDrawing()
    case .clear: clear()
    case .undo: undo()
    case .toolPen: select(.pen)
    case .toolArrow: select(.arrow)
    case .toolRect: select(.rect)
    case .toolHighlighter: select(.highlighter)
    case .toolText: select(.text)
    case .colorRed: pick(0)
    case .colorOrange: pick(1)
    case .colorYellow: pick(2)
    case .colorGreen: pick(3)
    case .colorBlue: pick(4)
    case .colorWhite: pick(5)
    case .bigger: widen(+1)
    case .smaller: widen(-1)
    case .screenshot: capture(region: false)
    case .region: capture(region: true)
    case .hide: if !marksHidden { toggleHidden() }
    case .show: if marksHidden { toggleHidden() }
    case .stop: stopSession()
    }
  }
}

extension Overlay: VoiceListenerDelegate {
  func voiceHeard(_ matches: [VoiceMatch], at offset: TimeInterval) {
    #if RF_PROBES
    for match in matches { replayFired.append(match.command.rawValue + "|" + match.phrase) }
    #endif
    for match in matches {
      // Written down before it is acted on. Stop ends the process, and a
      // command that ended the session without leaving a record of itself is
      // the one entry a person would go looking for.
      logCommand(match, at: offset)
      acknowledge(match)
      perform(match.command)
    }
  }

  func voiceFailed(_ reason: String) {
    voiceFailure = reason
    warn("voice control is not listening: " + reason)
    paletteView?.needsDisplay = true
  }
}
