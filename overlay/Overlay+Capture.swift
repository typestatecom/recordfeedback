// Taking a screenshot, and ending the session.
import Cocoa
import Carbon.HIToolbox

extension Overlay {
  // MARK: screenshots

  func countShots() -> Int {
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: inbox)) ?? []
    return contents.filter { !$0.hasPrefix(".") }.count
  }

  // The overlay owns the capture keys so that it can take its own furniture out
  // of the picture. A shot in the session inbox also needs no access to the
  // folder macOS protects.
  func capture(region: Bool) {
    let wasVisible = paletteWindow?.isVisible ?? false
    paletteWindow?.orderOut(nil)

    // The name is taken now rather than inside the wait below. screencapture
    // does not write the file until a second or more later, so two presses
    // inside that window both counted the same empty folder, took the same
    // name, and the second shot replaced the first without saying so. Counting
    // the folder as well as the reservation is what lets a rescued overlay
    // carry on from the files a previous one left.
    reservedShots = max(reservedShots, countShots()) + 1
    let name = String(format: "shot-%03d.png", reservedShots)

    // The window server needs a moment to drop the panel out of the composite,
    // and without the wait the palette lands in the file it was hidden for.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      let path = self.inbox + "/" + name
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
      task.arguments = region ? ["-i", path] : ["-x", path]

      DispatchQueue.global().async {
        do {
          try task.run()
          task.waitUntilExit()
        } catch {
          warn("screencapture would not run: \(error.localizedDescription)")
          warn("  command: /usr/sbin/screencapture \(task.arguments!.joined(separator: " "))")
          warn("  fix: give this terminal Screen Recording in System Settings, Privacy and Security.")
        }
        let wrote = FileManager.default.fileExists(atPath: path)
        DispatchQueue.main.async {
          if wasVisible { self.paletteWindow?.orderFrontRegardless() }
          self.shots = self.countShots()
          if wrote {
            self.confirmShot()
          } else if !region {
            // A region capture writes nothing when the user presses escape,
            // which is not a failure. A full screen one always should.
            warn("screencapture wrote no file, so that screenshot was lost.")
            warn("  command: /usr/sbin/screencapture -x \(path)")
            warn("  fix: give this terminal Screen Recording in System Settings, Privacy and Security.")
          }
          self.paletteView?.needsDisplay = true
        }
      }
    }
  }

  // The shot is taken with -x so the shutter sound stays out of the recording,
  // and a silent capture is indistinguishable from a key that did nothing. The
  // frame is the confirmation, drawn after the file is on disk so that it can
  // never appear in the shot it is confirming.
  //
  // Long enough to be caught by someone who is talking rather than watching. A
  // confirmation that is missed is a key pressed again, and pressing it again
  // is another file: the session that found this holds four near identical
  // shots taken across three seconds.
  func confirmShot() {
    shutterFlash = true
    redrawMarks()
    paletteView?.needsDisplay = true
    Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
      self?.shutterFlash = false
      self?.redrawMarks()
      self?.paletteView?.needsDisplay = true
    }
  }

  // MARK: stop

  func stopSession() {
    guard !stopping else { return }
    // Answering the click is the first thing that happens, before anything
    // that can take time. Stopping a session means flushing the recorder,
    // transcribing and merging, and none of that has any effect the user can
    // see: the row and the menu bar have to say the click landed by
    // themselves, or the button reads as broken and gets pressed again.
    stopping = true
    stopRequestedAt = Date()
    paletteView?.needsDisplay = true
    refreshStatusItem()
    rebuildMenu()

    // The session path comes from the environment the CLI set, so this always
    // stops the session this overlay belongs to and never a later one.
    FileManager.default.createFile(atPath: session + "/stop", contents: nil)

    // The stop file is a request, and it is only answered by whoever is
    // watching for it. Nobody is, if the CLI died or was never waiting, and
    // then this window stays on the screen with its stop button doing nothing
    // anybody can see, while the recorder runs on. So the request has a
    // deadline, after which the overlay finishes the session itself.
    let deadline = Double(ProcessInfo.processInfo.environment["RF_RESCUE_SECONDS"]
                            ?? "") ?? 30
    Timer.scheduledTimer(withTimeInterval: deadline, repeats: false) { [weak self] _ in
      self?.finishSessionAlone()
    }
  }

  // Everything that makes a session worth having is written by the CLI: the
  // recorder is flushed with its own q command, the words are transcribed and
  // the document is merged. So this runs the CLI rather than reimplementing
  // any of it in Swift, where a second copy would be a second thing to get
  // wrong about somebody's recording.
  func finishSessionAlone() {
    let cli = ProcessInfo.processInfo.environment["RF_CLI"] ?? ""
    warn("stop was pressed \(Int(Date().timeIntervalSince(stopRequestedAt)))s ago"
         + " and nothing was listening for it.")
    guard !cli.isEmpty, FileManager.default.isExecutableFile(atPath: cli) else {
      warn("  RF_CLI is not set, so this overlay cannot finish the session"
           + " itself and is leaving it alone rather than losing it.")
      warn("  the recording is still running and nothing has been lost.")
      warn("  fix: recordfeedback stop \(session)")
      NSApp.terminate(nil)
      return
    }
    warn("  finishing it here instead, with: \(cli) stop \(session)")
    warn("  nothing is lost: the recorder is flushed the same way, and the"
         + " document is written to \(session)/feedback.md.")

    // Detached, because this process is about to end and the work outlives it.
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = ["-c", "nohup " + shellQuoted(cli) + " stop " + shellQuoted(session)
                      + " >> " + shellQuoted(session + "/rescue.log") + " 2>&1 &"]
    do {
      try task.run()
      task.waitUntilExit()
    } catch {
      warn("  that would not run: \(error.localizedDescription)")
      warn("  fix: recordfeedback stop \(session)")
    }
    NSApp.terminate(nil)
  }

  // macOS names screenshots with spaces in them, and a session directory sits
  // under a home directory that can have one too.
  func shellQuoted(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}
