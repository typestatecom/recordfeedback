# Decisions

Engineering calls worth keeping. One entry each, newest last.

## 2026-08-24 One CLI file, no shared shell library

`bin/recordfeedback` holds everything: config, session layout, every
subcommand. A second sourced file would have to be found from both the
repository and the install symlink, which is one more thing that can be
missing at run time. The cost is a long file.

## 2026-08-24 Test cases are plain bash, one file each, no framework

`test/run.sh` runs `test/cases/*.sh` and prints one line per case. A case
exits 0 to pass, 77 to skip, anything else to fail, and its captured
output is printed only when it fails. Each case gets its own `RF_HOME`
under `test/tmp/home/<case>` so no case can see another one's sessions.
The cost is that there is no assertion library beyond `test/lib.sh`.

## 2026-08-24 doctor separates fail from warn

A missing `ffmpeg` stops the tool, an unbuilt overlay does not. `doctor`
prints `fail` for the first and `warn` for the second, and exits non-zero
only on `fail`. This keeps `doctor` honest during the build, when the
overlay does not exist yet, without weakening the checks that matter.

## 2026-08-24 doctor tests the microphone by recording

Permission cannot be read out of a database that is readable only by
system processes, so `doctor` captures half a second and checks the file
grew past the 44 byte WAV header. `RF_FFMPEG_INPUT` replaces the input in
tests, so no test ever opens the real microphone.

## 2026-08-24 macOS has no timeout(1), so the CLI carries its own

`run_with_timeout` backgrounds the command and polls at 100 ms. Every
external call in this tool can block on a permission prompt that never
returns, and a blocked `doctor` teaches the user nothing.

## 2026-08-24 The recorder is stopped by writing q, not by a signal

Measured on this machine with ffmpeg 7.1.1: an `-f avfoundation` recorder
ignores both SIGINT and SIGTERM and is still running ten seconds later,
and a SIGKILL leaves a zero byte file, because ffmpeg holds the audio in
its output buffer until it flushes. `-flush_packets 1` does not change
that, and neither does writing raw PCM instead of a WAV. The signal
sequence the spec first described would have destroyed every recording it
was meant to end.

ffmpeg's own keyboard command `q` exits cleanly in about 0.35 seconds and
writes a correct header. So the recorder gets a FIFO at
`$SESSION/ffmpeg.ctl` as stdin, opened read-write with `0<>` so the FIFO
never reaches end of file when the launching shell exits, and `stop`
writes `q` to it. This replaces `-nostdin`, and it solves the same
problem: ffmpeg still never touches the terminal.

TERM and KILL remain as a fallback for a wedged recorder, and `stop` says
out loud that the audio is probably lost when it gets that far, because
nothing can be recovered from a zero byte file.

## 2026-08-24 The synthetic test source is -re lavfi sine

`RF_FFMPEG_INPUT="-re -f lavfi -i sine=..."` records in real time and
answers `q` on the same control FIFO as the real input, so the tests
exercise the production shutdown path rather than a special case. Without
`-re` the source generates hours of audio in a second and proves nothing.

## 2026-08-24 The quantised turbo model is accurate enough, and fast

`ggml-large-v3-turbo-q5_0.bin` transcribed the fixture word for word and
segmented three spoken sentences into six segments with clean millisecond
offsets, in about two seconds for twelve seconds of audio. The full
large-v3-turbo was the fallback if quality was poor. It is not needed.

## 2026-08-24 transcribe is its own subcommand

`stop` calls it, and so can a person whose `stop` died after the WAV was
written. It takes a session directory, which is also what lets the test
drive it against a `say` fixture without recording anything.

## 2026-08-24 Session screenshots leave the screenshot folder

A screenshot taken during a session belongs to that session, so `collect`
moves it into the archive instead of copying it, and the desktop is left
as it was. `RF_KEEP_SHOTS=1` restores the old behaviour for anyone who
wants both. This inverts `RF_MOVE_SHOTS` from the spec, which defaulted
to copying and left every session's shots piled on the desktop.

The overlay captures straight into `$SESSION/inbox` and never goes near
the screenshot folder at all, so those shots are collected whatever their
timestamp and there is nothing to clean up. That also means a session
driven from the overlay needs no access to `~/Desktop`, which matters
because macOS denies it by default.

## 2026-08-24 macOS screenshots go to `~/Screenshots`, not the Desktop

macOS denies this terminal `~/Desktop` and `~/Documents`, so `collect`
found nothing however correct it was, and the only fixes were a Full Disk
Access grant the user has to click through, or moving the screenshots out
of the protected folders. `defaults write com.apple.screencapture
location ~/Screenshots` costs one command, is undone by one command, and
needs no permission at all, because `~/Screenshots` and `~/Pictures` are
not folders macOS protects.

What it costs: it changes where every screenshot on the machine lands,
not only the ones taken during a session, so the README has to say it and
has to say how to put it back. `doctor` keeps listing the folder rather
than trusting the setting, because a person who points it back at the
Desktop gets silence otherwise.

## 2026-08-24 A paragraph never spans a screenshot

The spec asks for two things that fight each other: segments merged into
paragraphs of roughly 40 words, and a picture placed after the segment
that was being spoken when it was taken. Merging first buries the picture
at the end of a paragraph, after sentences said ten seconds later, and
the placement is the only thing this document exists for. So the merge
closes a paragraph as soon as a screenshot offset falls inside it.

What it costs: a paragraph next to a screenshot is shorter than 40 words,
sometimes a single sentence. That reads fine and the alternative does not.

## 2026-08-24 Silence is measured from the audio, not read from the transcript

Whisper invents speech out of digital silence. Thirty seconds of
`anullsrc` transcribes as "Thank you.", which would have gone into
`feedback.md` as something the user said. So `stop` measures
`mean_volume` with ffmpeg's `volumedetect` and writes `silent` into
`meta.json`, and anything at or below -60 dBFS sets the transcript aside
and says the recording was silent.

What it costs: one extra ffmpeg pass over the WAV at stop time, and a
threshold. -60 dBFS is far below a person talking in a quiet room, which
sits above -40, and far above a muted microphone, which lands near -91.

## 2026-08-24 The overlay takes the screenshots and shows a palette

Three things asked for at once, and they turn out to be one decision. A
visible recording indicator cannot exist while `screencapture` composites
the screen, because the indicator lands in every shot. It can exist the
moment the overlay owns the capture key: it hides its own furniture,
captures, and puts it back. So `⌥⌘X` takes the whole screen and `⌥⌘R`
takes a region, both straight into `$SESSION/inbox`, and the palette can
stay on screen showing a red dot, the elapsed time, the tools and the
colours.

What it costs: the tool now asks people to learn a key instead of using
`⇧⌘4`. `⇧⌘4` still works and `collect` still sweeps the screenshot
folder, so nothing breaks for anyone who forgets, they just get the
palette in the picture.

`⌥⌘D` from the spec was macOS's own show and hide the Dock, which Carbon
refuses to register, so draw mode moved to `⌥⌘A`.

## 2026-08-24 The pixel test drives the drawing code, not synthetic events

The spec asked for the composite proof to be driven by synthetic mouse
events. Posting those needs Accessibility permission, which cannot be
granted without a person clicking a switch, so a test that needs it is a
test that never runs. `RF_OVERLAY_SELFTEST=1` instead calls the same
`beginStroke`, `extendStroke` and `endStroke` the mouse handler calls,
and the case then asserts on real pixels out of a real `screencapture`.

What it costs: the delivery of the mouse event itself is not covered, so
a broken `mouseDown` would not be caught here. Everything the proof was
about, that an overlay window at `.statusBar` level lands in the
composite, is covered. Measured on this machine the stroke adds 127124
red pixels, and with the stroke removed it adds 1220, so the case
separates the two answers by two orders of magnitude.

## 2026-08-24 doctor asks macOS about Screen Recording instead of guessing

Without Screen Recording permission `screencapture` still exits zero and
still writes a PNG. The PNG is the wallpaper with no windows in it. That
is the one failure that looks like success all the way to the point where
a person reads `feedback.md` and finds pictures of nothing. The overlay
binary answers `--check-capture` with `CGPreflightScreenCaptureAccess`,
and `doctor` reports it as its own line.

What it costs: `doctor` now depends on the overlay being built for that
one check. It says so rather than staying quiet when it is not.

## 2026-08-24 One list of screenshot extensions

`status` counted only the screenshot folder while `collect` counted the
folder and the overlay's inbox, so a person who pressed `⌥⌘X` three times
was told zero shots had been taken. Both now read `IMAGE_NAMES`, and the
status line stopped naming one folder while counting two places.

What it costs: a global array in a shell script. The alternative was the
extension list written out a third time, which is how the two counts
drifted apart in the first place.

## 2026-08-24 The palette sits above the mark windows, at its own level

`isFloatingPanel = true` puts the panel back at the floating level, so
setting `.statusBar` before it left the palette below the full screen
mark windows for the whole session. While idle that is invisible, because
the mark windows are click through and every press falls to the palette
underneath. Entering draw mode turns click through off, and from that
moment the mark window took every click aimed at a tool, at the camera
and at Stop. Draw mode became a room with the door only a key opens, and
a person who is talking rather than reading the hotkey list is stuck in
it. The palette now takes its level after `isFloatingPanel`, one step
above `.statusBar`, and carries `canHide = false` so that the hide that
gives the keyboard back on leaving draw mode does not take the clock and
the Stop button away with it.

What it costs: a test hook in the overlay. Accessibility cannot be
granted without a person, so no test can post a real click, and
`11-palette-reachable` asks `NSWindow.windowNumber(at:)` the question a
click asks instead. That covers which window is in front and not the
delivery of the event to the button.
