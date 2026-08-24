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

## 2026-08-24 A tool that is already on is the way out of draw mode

Watching a first session: the user clicked P, drew, and then said they
could not stop drawing. They tried `⌥⌘D`, which is the Dock. `esc` does
leave draw mode and always did, but nothing on screen said so, and the
hotkey list had scrolled away in the terminal behind the overlay. The
control they had in front of them was the tool button they had just
pressed, and pressing it again did nothing.

Selecting the tool that is already selected now leaves draw mode, and a
Done button appears in the palette for the length of draw mode. `esc`
stays. Three ways out, one of which is under the cursor already.

What it costs: two quick presses of the same tool key drop out of draw
mode instead of being ignored. That is the same gesture as a toggle
everywhere else, and the alternative was a mode with no visible exit
while the overlay holds every click on the screen.

## 2026-08-24 The tool buttons draw their marks, not their letters

The same session: `P A R H T` in a row was read as a word rather than as
five buttons, and every tool had to be pressed to find out what it was.
`T` was the one that stayed unclear even after trying it, because a
letter among letters does not say text.

Each button now draws what its tool draws: a nib, an arrow, a rectangle
outline, a fat translucent bar. Text keeps a serif `T`, which is already
the icon for text everywhere else and stops reading as a shortcut letter
once the other four are shapes. The letter and the tool's name moved into
a tooltip, so the keyboard is still discoverable from the palette.

What it costs: the keys are no longer visible at a glance, only on hover,
and the tooltips are reinstalled only when the row changes because the
palette redraws twice a second to pulse the dot and reinstalling on every
frame restarts the hover timer.

## 2026-08-24 A screenshot that lands flashes a frame

`screencapture -x` is right: the shutter sound would land in the audio of
the person talking. It also means a successful screenshot and a key that
did nothing look and sound identical, and the session that prompted this
ended with the user saying they could not take a screenshot.

Once the file is on disk the overlay flashes a white frame around every
screen for 180ms. It is drawn after the capture completes, so it cannot
appear in the shot it confirms, and ahead of the hidden marks check, so
`⌥⌘H` does not silence it. A full screen capture that writes no file now
prints the Screen Recording fix. A region capture that writes none does
not, because escape cancels one and that is not a failure.

What it costs: a 180ms frame lands in a second shot taken inside that
window. The confirmation is worth more than that.

## 2026-08-24 The palette row is measured, not eyeballed

Adding the Done button pushed the row past the window and put the camera
button and the width control underneath Stop, where a click meant to take
a screenshot ends the session. It had already been over: at 600 wide the
camera and the shot count were under Stop before anything was added, and
the colour swatches, 18 wide with their targets grown to 24 on a step of
23, each overlapped their neighbour by a point.

None of that is visible from the source, so it is asserted instead. The
palette view keeps the rectangles the drawing code registered, and
`14-palette-layout` reads them out of a real palette in draw mode: no two
overlap, none falls outside the window, and the controls to the right of
the tools do not move when draw mode starts. The window went to 720 and
the colour step to 26.

What it costs: another test hook, and a window 120 points wider on the
screen for the whole session.

## 2026-08-24 The marks are the user's work, not the tool's furniture

Leaving draw mode hides the application to give the keyboard back to
whatever is underneath. The palette was already exempt from that with
`canHide = false`, and the mark windows were not, so every mark the user
had drawn came off the screen the moment they put the pen down. A user
who circles something and then stops drawing to talk about it is left
pointing at nothing.

The same hiding took the shutter frame with it, so a screenshot taken
outside draw mode had no confirmation at all. Both windows are now
exempt. Hiding the application still deactivates it, which is the part
that hands the keyboard back, so nothing was lost.

What it costs: nothing on screen, and one more window the window server
keeps composited while the session runs, which it was already doing for
the whole of draw mode.

## 2026-08-24 The shot confirmation is longer and repeated on the row

The frame that says a screenshot was taken was up for 180ms, at the four
edges of the screen, and it is drawn only after the file lands on disk so
it can never appear in the shot it confirms. That leaves half a second in
which a pressed key has done nothing visible. A session recorded against
this tool holds four near identical shots taken across three seconds,
with the user asking out loud whether the key had registered.

The frame now holds for 350ms, and the camera button in the palette
lights while it does. The row is where the eye that just clicked already
is, and the palette is the one window that is never hidden.

What it costs: the window in which the confirmation lands in a second
shot doubles. A confirmation nobody catches is worth less.

## 2026-08-24 The arrow is drawn to fit between its own two ends

Every part of the arrow is sized from a width that is usually small, and
at the wide end two things broke. The shaft was stroked to the tip with a
round cap, so half a width of ink sat beyond the point the user dragged
to: a blob hanging off the end. And the head was four widths long
whatever the drag, so a short wide arrow had a head longer than itself,
with the barbs running back out through the tail.

The head is now clamped to the length of the drag, and the shaft is butt
capped and stopped inside the head. `17-wide-arrow` renders arrows
through the same code the screen uses and counts the ink outside the two
points, because the fault is in the pixels and not in the numbers. The
probes now also write what they rendered, so a broken assertion can be
looked at.

What it costs: a short drag at a wide setting is nearly all head, since
staying inside the two ends wins over keeping the shaft. The tail is flat
rather than rounded.

## 2026-08-24 The palette carries two rows, anchored at its right hand end

The row held the whole tray of tools, colours and widths for the entire
session, and a session is mostly spent talking. The width was fixed at
720 for exactly one reason: draw mode is entered by clicking a control in
this row, so anything that moved as it started moved out from under the
cursor that started it, and Stop moving is a click that draws a mark
instead of ending the session.

That reason is served by anchoring rather than by a fixed width. The
window now grows leftwards from its right hand end, 404 idle and 852
drawing, and the controls that exist in both rows are laid out from the
right edge inwards, so they sit at the same place on the screen in both.
`14-palette-layout` asserts that of a real palette by name rather than by
counting along the row, since what changes between the two layouts is how
many controls sit between them.

Idle the row carries the clock, one Draw button, the two capture buttons,
the count and Stop. Every control has button chrome and names its key
underneath itself, because the user of this tool is mid sentence and
cannot go hunting for a tooltip. The hints are text under a control
rather than inside it, so a hint wider than its control collides with its
neighbour's and neither can be read: the probe registers the hint
rectangles too, and `opt-cmd-X` and `opt-cmd-R` were the first pair to
collide. They are drawn with the key symbols.

What it costs: the row is 52 tall rather than 46, to carry the hints. The
saved position moved to a new key, so the palette starts once in its
default place for anyone who had moved it. A region capture now has a
button, which is one more control in both rows.

## 2026-08-24 The shortcuts are settings, and one place knows what they are

Draw mode was on `⌥⌘A` because macOS owns `⌥⌘D` and Carbon will not hand
it over. Wanting D back is a reasonable thing to want, and so is wanting
a different key entirely: a session takes seven combinations away from
every other application on the machine for as long as it runs, and which
seven is not the author's business.

They live in `~/.recordfeedback/settings.json` and the overlay records
them by pressing them. The defaults moved to option and shift, which no
window manager on this machine claims and macOS has no letter shortcut
on. The cost is the characters option and shift types on a layout that
has them, `Ç` among them, which the tool's own user accepted knowingly
and can undo by rebinding.

The file is defended rather than trusted. A binding with no modifier is
refused, because a bare letter registered globally is that letter taken
away from the editor the user is talking about. A key outside letters and
digits is refused, so the file can never name one the overlay would fail
to register. A file that will not parse leaves every default standing:
the user is mid session and a broken file must not cost them the stop
key.

Nothing keeps a second copy of the list. `rf-overlay --print-keys` is the
one answer, the CLI's banner asks for it, and the slash command was
changed to repeat what the banner printed rather than to name keys from
memory.

What it costs: the CLI runs the overlay binary once per start to print
its own banner, and every key anybody has already learned has moved.

## 2026-08-24 The menu bar item, and what a notch does to it

The palette can be dragged onto a display that is later unplugged, buried
under a full screen application, or left behind by an overlay whose CLI
died, which is how a user ended up with a window they could not stop. The
menu bar is the one place none of that reaches, so the overlay puts a red
dot and the clock there with a menu carrying every action, the settings,
Stop, and a force quit that says what it leaves behind.

On the machine this was built for it is invisible. macOS lays status
items out from the right and, when both strips beside the notch are full,
places one in the hole rather than refusing it: 1512 points wide, strips
of 663 and 664, and the item at 683 to 752. Drawn, clickable, and
invisible, which is worse than absent.

That is a full menu bar and not something the code can fix, so the code
says so instead. The overlay measures its own item against
`auxiliaryTopLeftArea` and `auxiliaryTopRightArea` once the windows are
up, and the CLI prints whatever the overlay warned about as part of the
start banner, because nobody opens `overlay.log`. The settings also got a
gear in the palette row, so the one control the menu bar item was the
only route to is reachable when the item cannot be seen.

What it costs: a second route to the settings, and a start that waits up
to three seconds for the overlay to have something to say before it
prints its banner.

## 2026-08-24 A stop nobody answers finishes itself

The overlay's stop button writes a file and waits for the CLI to come and
finish the session. Nothing answers that file if the CLI died or was
never watching, and then the window stays on the screen, the button does
nothing anybody can see, and the recorder runs on. That happened to this
tool's own user for forty minutes, and from in front of the window there
was no way to tell it from a session that was simply running.

Three changes. The click is answered before anything is done, because
nothing a stop does can be seen: the row says Ending and the menu bar
says stopping, at once. The request has a deadline, after which the
overlay runs the CLI itself and quits, rather than reimplementing the
shutdown in Swift where a second copy would be a second thing to get
wrong about somebody's recording. And `doctor` reports an overlay with no
session behind it, since that is where a person looks when they cannot
make a window go away.

What it costs: the CLI's path is passed to the overlay in the
environment, and a stop that a slow caller answers after thirty seconds
is answered twice. The second one was already harmless: `stop.ref` fixes
the end of the window on the first stop and is not widened by a later
one.

## 2026-08-24 A stop that cannot transcribe still hands over the pictures

Finding the rescue above meant running a stop with no whisper model on
the path, which exposed something worse: `cmd_transcribe` ends the script
when the model is missing, so `cmd_stop` died before writing anything.
The audio, the screenshots and their timings were all on disk and nothing
joined them, and the caller never got the path it reads off the last
line.

Transcription now runs in a subshell, and the document is written either
way with the half that survived. Stop says where the recording was kept
and how to fill the words in later. The last line is still the path,
because everything that calls this tool reads that line and a failure
that changes it strands the caller as well as the session.

What it costs: a stop can now succeed while producing a document with no
words in it, so the message that says why has to be read.

## 2026-08-24 The settings window is opened by a test, not only by a user

The window that binds the keys is the only part of this tool a user has
to find on their own, and it was written without ever being opened. That
is exactly the kind of code that fails the first time somebody reaches
for it, and two things did.

Its rows were laid out from `window.frame.height`, which counts the title
bar, so the heading was drawn above the top edge. And it opened
underneath the palette, which sits above everything else on the screen
and is where the window is opened from, so the row covered the last
shortcut and the way back to the defaults.

`21-settings-window` opens it, reads the buttons out of it, and checks
that every row is inside the window and that the window is above the
palette. The probe also writes what it rendered, though `cacheDisplay`
draws these controls without their text, so the honest witness for the
look is a real screenshot and the probe is the witness for the layout.

What it costs: a test hook that opens a window, and a window at a level
above the palette, which means it also floats over other applications
while a session is running.

## 2026-08-24 The drift check judges three windows, not one

`02-record-duration` measured the recorder over a single six second window and
failed the whole suite at 0.9215 seconds of audio per second, then passed on
its own. That is the fixture and not the tool: `-re` paces itself off the CPU
clock, so one scheduling stall while the suite is running overlays and
screencaptures reads as several percent of drift. A real microphone is clocked
by the audio device and cannot lag that way.

It now takes three windows and judges the middle one. Drift that is real is in
every window and moves the middle; a stall is in one and does not. The failure
prints all three, so a genuine drift can be told apart from a noisy machine
without rerunning anything.

What it costs: the case takes fourteen seconds instead of eight.

## 2026-08-24 Shot names are reserved at the key press, not counted off the folder

`capture` takes its number from a counter that only moves forward, seeded
from the folder with `max(reserved, countShots())` so an overlay rescued
mid-session continues the numbering rather than restarting it. Counting
the folder at write time was correct only while no second press arrived
inside the second screencapture takes, and the second press is exactly
what a silent capture invites. The cost is one more piece of state that
has to be seeded correctly on rescue.

## 2026-08-24 Probes sample the state the assertion is about, at the moment it is about

`probeCapture` records draw mode when the capture is asked for rather
than when the report is written three seconds later. Draw mode takes the
foreground, so every key pressed at any other window in those three
seconds arrives in the overlay, and `esc` or the letter of the chosen
tool leaves draw mode. Reading late made the case fail about one run in
ten, only ever while somebody was at the keyboard, and the failure named
a screenshot that had in fact been taken. The cost is that the probe no
longer says anything about draw mode after the capture, which no case
asks about.
