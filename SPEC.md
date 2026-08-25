# recordfeedback

A macOS tool that turns a spoken, annotated working session into one
structured feedback document that Claude Code acts on.

You type `/recordfeedback` in any Claude Code session. Recording starts.
You keep using your computer and you talk. You draw arrows, boxes and
highlights straight on the screen, and you take screenshots with the
normal macOS keys, so the annotations are inside the images. You press a
stop key. Claude Code wakes up holding the transcript, the screenshots in
the order you took them, and the sentence you were saying when each one
was taken, and it starts working.

## Why it exists

Typing feedback is slower than saying it, and a screenshot without the
sentence that goes with it is a puzzle. The value of this tool is the
join: a picture placed at the second it was taken inside a transcript.

## What is already installed and verified on this machine

Do not re-derive these. They were checked on 2026-08-24.

| Thing | State |
| --- | --- |
| macOS | 14.4.1, arm64, Apple M1 Max |
| `ffmpeg` | `/opt/homebrew/bin/ffmpeg` |
| `fswatch` | `/opt/homebrew/bin/fswatch` |
| `whisper-cli` | `/opt/homebrew/bin/whisper-cli` (brew `whisper-cpp`), Metal backend |
| Whisper model | `~/.recordfeedback/models/ggml-large-v3-turbo-q5_0.bin`, 547 MB |
| `swiftc` | `/usr/bin/swiftc`, Swift 5.10, target `arm64-apple-macosx14.0` |
| SDK | `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` |
| `uv`, `jq`, `python3` | all present under `/opt/homebrew/bin` |
| avfoundation audio inputs | Several, index `0` the built-in microphone. `recordfeedback devices` lists them, and `--device N` picks one. The indexes are per machine, so nothing may assume them. |
| Screenshot folder | `~/Screenshots`, set with `defaults write com.apple.screencapture location`. It was `~/Desktop`, which is a folder macOS protects. |
| Protected folder access | **Not granted, and no longer needed.** `ls ~/Desktop` and `ls ~/Documents` both fail with `Operation not permitted`, so screenshots were moved out of the protected folders instead of asking for the permission. `~/Screenshots` and `~/Pictures` read fine. `doctor` still checks the folder by listing it, because `-d` succeeds on a folder macOS will not let it read, and a person who points the setting back at the Desktop needs to be told why nothing is collected. |
| `~/.claude/commands/` | does not exist yet. `install.sh` creates it. No global slash command competes with this one. |

`whisper-cli` writes ggml and Metal loader lines to stderr before any
result. The first run of a process loads the embedded Metal library and
that took 14 seconds. Treat stderr as noise, parse the JSON file only,
and never parse stdout.

## Layout

```
~/Projects/recordfeedback/
  SPEC.md                  this file, the contract
  CLAUDE.md                how to work in this repository
  README.md                install and daily use, written last
  bin/recordfeedback       the CLI, bash
  bin/rf-overlay           built Swift binary, git-ignored
  overlay/*.swift          the annotation overlay, one file per type
  overlay/Overlay.swift      the controller: its state and its lifecycle
  overlay/Overlay+*.swift    the controller by section
  overlay/main.swift         the entry point, which Swift allows nowhere else
  overlay/build.sh         swiftc invocation, --probes for the test build
  overlay/Info.plist       linked into the binary, so macOS can be asked for Speech Recognition
  commands/recordfeedback.md   the Claude Code slash command
  install.sh               symlinks the CLI and the slash command
  test/run.sh              the whole test suite, no framework
  test/cases/*.sh          one file per case
  docs/decisions.md        engineering calls worth keeping
```

State and output live outside the repository:

```
~/.recordfeedback/
  models/ggml-large-v3-turbo-q5_0.bin
  current                  symlink to the active session directory, absent when idle
  sessions/<YYYYmmdd-HHMMSS>/
    meta.json              device, start time, cwd, git branch, note
    start.ref stop.ref     empty files, the time window for screenshots
    audio.wav              16 kHz mono PCM
    levels/0.pcm           one second of the recording each, six of them, rotated
    commands.json          the spoken commands, when voice control is on
    ffmpeg.pid ffmpeg.log
    overlay.pid
    stop                   created by the stop hotkey, watched by `wait`
    shots/01-0043.png      copied screenshots, index and elapsed time in the name
    shots.json             one record per screenshot
    transcript.json        raw whisper-cli output
    transcript.txt         plain text, no timestamps
    feedback.md            the document Claude Code reads
```

A session directory is never deleted by the tool. Disk is cheap and a
session you want back a week later is worth more than the megabytes.

## The CLI

`bin/recordfeedback <command>`. Also installed as `rfb`.

### `start [--note TEXT] [--device N] [--no-overlay]`

1. Refuse if `~/.recordfeedback/current` points at a session whose
   ffmpeg is alive. Print the session path and how long it has run.
   A stale `current` whose pid is dead is cleaned up and start proceeds.
2. Create the session directory, `touch start.ref`, write `meta.json`.
3. Start the recorder detached, with a control FIFO as its stdin:

   ```
   mkfifo "$SESSION/ffmpeg.ctl"
   nohup ffmpeg -hide_banner -loglevel warning \
     -progress "$SESSION/ffmpeg.progress" \
     -f avfoundation -i ":$DEVICE" \
     -ac 1 -ar 16000 -c:a pcm_s16le "$SESSION/audio.wav" \
     0<>"$SESSION/ffmpeg.ctl" >"$SESSION/ffmpeg.log" 2>&1 &
   ```

   The FIFO is how the recording is stopped, and it replaces `-nostdin`.
   ffmpeg still never touches the terminal, because its stdin is the
   FIFO. `0<>` opens the FIFO read-write so ffmpeg holds a writer on it
   itself, which means the FIFO never reaches end of file when this
   shell exits and `q` still arrives at stop time.
4. Prove the recorder is real by reading `out_time_us` from
   `ffmpeg.progress` until it is greater than zero, for up to 5 seconds.
   Do not check the size of `audio.wav`. ffmpeg holds the audio in its
   output buffer and the file is still zero bytes several seconds in, so
   file size proves nothing. The progress stream is the first honest
   sign that audio is arriving. If the pid dies or no audio arrives,
   print the last 20 lines of `ffmpeg.log` and the microphone hint
   below, remove the session, and exit non-zero.
5. Prove the input carries sound and not only samples. A recorder that
   runs while every sample it captures is zero looks exactly like a
   working session, and the whole session is lost with nothing on the
   screen having said so. Wait for two finished level segments, up to
   four seconds, and refuse the session if the loudest of them is at or
   below `DEAD_DBFS`. Refuse here and never mid session: refusing now
   costs the seconds spent proving it, and refusing later would throw
   away what the user has already said.
6. Start `bin/rf-overlay` detached unless `--no-overlay`, store its pid.
   Pass `RF_DEAD_DBFS`, so the number that refuses a session here and the
   number the palette raises its alarm on cannot drift apart.
7. Print the hotkeys and the session path, and what can be said when
   voice control is on.

`--voice` and `--no-voice` write `voice.enabled` in the settings file
rather than holding a flag for one session, so the flag and the settings
window cannot disagree about whether the session that is running is
listening.

### The input level

The recorder has a second output, so that whether it is hearing anything
can be answered while it runs:

```
-ac 1 -ar 16000 -c:a pcm_s16le \
-f segment -segment_time 1 -segment_wrap 6 -segment_format s16le \
"$SESSION/levels/%d.pcm"
```

It has to be a second output. `audio.wav` is unreadable while the
session runs: the wav muxer holds every sample until ffmpeg exits and
the file is still zero bytes minutes in, with or without
`-flush_packets`. ffmpeg's `astats` filter cannot supply it either,
because `ametadata=print:file=` writes through avio and only flushes on
close, and `pipe:1` and `/dev/stderr` behave the same. The segment muxer
closes each file when its second ends, and a closed file is a flushed
one. `-segment_wrap` bounds the cost at six files, about 190 kB,
whatever the length of the session.

The level is the loudest complete segment written in the last eight
seconds, in dBFS, and the loudest rather than the latest because a
person draws breath mid sentence. A segment older than eight seconds is
ignored, since under `segment_wrap` files are overwritten in place and a
recorder that died leaves loud ones behind. `DEAD_DBFS` is -85: a live
microphone in a quiet room measured between -74 and -81 dBFS on this
machine over repeated samples, and a stream of zeros reads `-inf` here
and -91 through ffmpeg's volumedetect, which clamps. The threshold sits
between the two with a handful of dB either side, and the level is taken
as the loudest of several seconds rather than the latest, so a pause
between two sentences cannot reach it.

`status` reports the level of a live session. `doctor` reports the level
of half a second of real capture and fails on a device delivering
silence, because counting the bytes that came back passes on a denied
permission, a muted input and a virtual mixer routed to nothing alike.

The microphone hint, printed verbatim on a recorder that produced no
audio: the terminal application needs Microphone permission in System
Settings, Privacy and Security, Microphone. macOS asks once, and if the
prompt was refused the switch has to be turned on by hand.

### `wait [--timeout SECONDS]`

Blocks until `$SESSION/stop` appears, or the recorder dies, or the
timeout passes. Exit code says which: `0` stop requested, `2` timeout,
`3` recorder died. Poll every 500 ms. This is what lets one slash
command cover the whole session, because Claude Code can call it again
after a timeout and lose nothing.

### `stop`

Idempotent. Works whether the recorder is still running or the stop
hotkey already halted it.

1. `touch stop.ref`.
2. Write `q` to `$SESSION/ffmpeg.ctl` and wait up to 10 seconds. This is
   ffmpeg's own quit command and it is the only shutdown that produces a
   playable file. Measured on this machine: an `-f avfoundation` recorder
   ignores SIGINT and SIGTERM and is still running ten seconds later, and
   a SIGKILL leaves a zero byte file, because ffmpeg keeps the audio
   buffered until it exits cleanly. Neither `-flush_packets 1` nor
   writing raw PCM changes that. `kill -TERM` and then `kill -KILL`
   remain only as a fallback for a wedged recorder, and stop says out
   loud that the audio is probably lost when it gets that far, because
   nothing can be recovered from a zero byte file.
3. `kill -TERM` the overlay.
4. Collect screenshots. Files in the screenshot folder, depth 1, with an
   image extension, not starting with a dot, newer than `start.ref` and
   not newer than `stop.ref`. Sort by modification time. Copy each to
   `shots/NN-MMSS.ext` where `NN` is the index from 01 and `MMSS` is the
   elapsed time from the session start. Write `shots.json`. Move, never
   copy, unless `RF_KEEP_SHOTS=1`, so a session's screenshots live in its
   archive and not on the desktop. Shots the overlay captured straight
   into `$SESSION/inbox` are collected whatever their timestamp, because
   they never went near the screenshot folder.
5. Transcribe:

   ```
   whisper-cli -m "$MODEL" -f audio.wav -l "$RF_LANG" \
     -oj -of "$SESSION/transcript" -np -t 8
   ```

   `-oj` writes `transcript.json`. Add `-otxt` for `transcript.txt`.
   `RF_LANG` defaults to `auto`.
6. Build `feedback.md`.
7. Remove `current`. Print a summary and the absolute path of
   `feedback.md` as the last line, alone, so the caller can read it
   without parsing prose.

Step 5 is the only one that needs a model on disk and a working whisper,
so it is the step most likely to fail, and it runs in a subshell because
its own failure path exits. The audio, the screenshots and their timings
all survive it. The document is written either way, with the half that
lived, and stop says where the recording was kept and how to fill the
words in later. The last line is still the path to the document, because
everything that calls this tool reads that line and a failure that
changes it strands the caller as well as the session.

### `status`, `abort`, `last`, `devices`, `doctor`

A session records from the input macOS itself is set to use, resolved by
matching the system default input's name against the avfoundation list,
and index 0 only when nothing can be matched. An index given with
`--device` or `RF_DEVICE` is used as it was given. The indexes shift
when a device is plugged in: on this machine a pair of AirPods
connecting moved the built in microphone from index 0 to index 1 and put
a virtual mixer routed to nothing in its place, which is a recording of
zeros that looks exactly like a working session. `input-index` reports
what would be opened without starting anything.

`status` prints the active session, elapsed time, audio file size and
screenshot count so far. `abort` stops everything and marks the session
`aborted` without transcribing. `last` prints the path of the newest
session that has a `feedback.md`. `devices` lists the avfoundation audio
inputs with their indexes. `doctor` checks every dependency in the table
above, the model file, the microphone permission and that the overlay
binary is built, and prints one line per check. It also reports an
overlay that is running with no session behind it, because from in front
of one there is nothing to tell it apart from a session that is simply
running, and that is where a person looks when they cannot make the
window go away.

## The transcript JSON

`whisper-cli -oj` writes:

```json
{ "transcription": [
    { "timestamps": { "from": "00:00:00,000", "to": "00:00:03,120" },
      "offsets":   { "from": 0, "to": 3120 },
      "text": " Look at this button." } ] }
```

`offsets.from` is milliseconds from the start of the audio, which is the
start of the session. That is the whole reason the join works. Read
`offsets`, never the formatted `timestamps` string.

## feedback.md

One chronological document. A reader who knows nothing about the tool
must understand it.

```markdown
# Feedback session 2026-08-24 14:32

Duration 4m18s. 3 screenshots. Language en. Started in
`~/Projects/typestate` on branch `main`.

## Transcript

[00:00] So the thing I do not like about the cockpit page is the
spacing at the top, it feels loose.

[00:41] Look at this, the button is doing the wrong thing here.

![Screenshot 1 at 00:43](/Users/…/shots/01-0043.png)

[00:52] And the same problem is on the flow page.

## Screenshots

1. `01-0043.png` at 00:43, taken while saying: "Look at this, the button
   is doing the wrong thing here."
```

Rules for the merge:

- A screenshot goes after the transcript segment that was being spoken
  when it was taken, which is the last segment whose `offsets.from` is
  at or before the screenshot offset.
- A screenshot taken before any speech goes at the top.
- Merge consecutive whisper segments into paragraphs of roughly 40
  words, and stamp the paragraph with the offset of its first segment.
  Whisper segments are a few seconds each and one line per segment is
  unreadable.
- Image paths are absolute. Claude Code reads an image by path and a
  relative path from an unknown working directory does not resolve.
- The "taken while saying" line quotes at most 25 words.
- No audio and no speech is not a failure. Write the screenshots with
  their times and say the recording was silent.

## The overlay

`overlay/*.swift`, one file per type, built by `overlay/build.sh` in a
single call over the whole folder so a file added and left out of the
build cannot fail later at the first call into it:

```
swiftc -O -framework Cocoa -framework Carbon -framework Speech \
  -framework AVFoundation \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
  -Xlinker overlay/Info.plist \
  -o bin/rf-overlay overlay/*.swift
```

The Info.plist is linked into the executable rather than put in a
bundle, because this is one file and not an application. macOS kills a
process that asks for Speech Recognition without one, so voice control
cannot start at all without that section being present.

`overlay/build.sh --probes` adds `-D RF_PROBES` and writes
`bin/rf-overlay-probe`. That build carries the `RF_OVERLAY_SELFTEST`
entry points and the shipped one does not, so the probes cannot be
reached in the binary a person installs. Cases that drive a probe get it
from `probe_overlay` in `test/lib.sh`, and the CLI takes `RF_OVERLAY_BIN`
for the one case that launches the overlay through it.

Behaviour:

- `NSApp.setActivationPolicy(.accessory)`. No dock icon, no menu bar
  item, nothing that appears in a screenshot on its own.
- One borderless transparent `NSWindow` per `NSScreen`, covering the
  full frame, `backgroundColor = .clear`, `isOpaque = false`,
  `level = .statusBar`, collection behaviour `[.canJoinAllSpaces,
  .stationary, .fullScreenAuxiliary]`. Rebuild the windows when
  `NSApplication.didChangeScreenParametersNotification` fires.
- Idle means `ignoresMouseEvents = true`. Every click goes to the app
  underneath and the overlay is invisible to the user in every way
  except the marks already drawn.
- Draw mode means `ignoresMouseEvents = false` and the app activates so
  it gets key events.

Global hotkeys through Carbon `RegisterEventHotKey`. Carbon hotkeys need
no Accessibility permission, and a `CGEventTap` does. Use Carbon.

| Action | Default | What it does |
| --- | --- | --- |
| `draw` | `⌥⇧D` | toggle draw mode |
| `screenshot` | `⌥⇧X` | screenshot the whole screen, instantly |
| `region` | `⌥⇧R` | screenshot a region, crosshair and drag |
| `clear` | `⌥⇧C` | clear all marks |
| `undo` | `⌥⇧Z` | undo the last mark |
| `stop` | `⌥⇧S` | stop the recording session |
| `hide` | `⌥⇧H` | hide or show the marks without clearing them |
| `listen` | `⌥⇧V` | start or stop listening for spoken commands |

The left hand column is the name in the settings file and the name
`--print-keys` reports. The middle one is only the default.

### The shortcuts

A session takes seven key combinations away from every other application
on the machine for as long as it runs, so which seven is the user's
choice and not the author's. They live in `~/.recordfeedback/settings.json`
and the overlay's settings window records them by pressing them, because
binding a key any other way needs a table of key codes in a README.

The defaults are option and shift: `⌥⇧D` draw, `⌥⇧X` screenshot, `⌥⇧R`
region, `⌥⇧Z` undo, `⌥⇧C` clear, `⌥⇧H` hide the marks, `⌥⇧V` listen,
`⌥⇧S` stop.
Command pairs are what other applications use, and `⌥⌘D` in particular is
macOS's own show and hide the Dock, which Carbon will not hand over. The
cost of option and shift is the characters it types on a layout that has
them, which is a trade the user makes knowingly and can undo by rebinding.

The window is above the palette, which is above everything else on the
screen and is where the window is opened from: underneath it, the row
covers the last shortcut and the way back to the defaults.
`21-settings-window` opens it and reads the controls out of it, because a
window written without being opened is a window that fails the first time
somebody reaches for it.

A binding with no modifier is refused, because a bare letter registered
globally is that letter taken away from the editor the user is talking
about. So is a key outside the letters and digits, so that the file can
never name a key the overlay would fail to register. A file that cannot
be parsed leaves every default in place: the user is mid session and a
broken file must not cost them the stop key.

Nothing else keeps a copy of that list. `rf-overlay --print-keys` reports
what is bound, and the CLI's start banner asks for it, because two copies
of a list is one that goes stale the first time anybody rebinds a key.
`18-shortcut-settings` asserts that, and `10-overlay-session` asserts that
the keys the CLI prints are the keys the overlay reports.

The overlay takes the screenshots itself, with `screencapture -x` for the
screenshot key and `screencapture -i` for the region key, straight into
`$SESSION/inbox`.
`⇧⌘4` still works and `collect` still sweeps the screenshot folder, but
neither is the path the tool asks for. The overlay's own capture is what
makes the palette below possible: it hides its own furniture for the
instant of the capture and puts it back after, so the marks land in the
file and the tool's own controls do not. A shot in the inbox also needs
no access to a folder macOS protects.

The stop key writes `$SESSION/stop`, where the session path comes from the
`RF_SESSION` environment variable the CLI sets when it launches the
overlay. The overlay never reads `~/.recordfeedback/current`, because
the session it belongs to is the one that started it.

Stopping is answered before anything is done, because nothing that stop
does can be seen: flushing the recorder, transcribing and merging all
take time and none of them show. The row and the menu bar say the click
landed at once, or the button reads as broken and gets pressed again.

The stop file is a request, and it is only answered by whoever is
watching for it. Nobody is, if the CLI died or was never waiting, and
then the window stays on the screen with its stop button doing nothing
while the recorder runs on. So the request has a deadline, thirty seconds
by default and `RF_RESCUE_SECONDS` in a test, after which the overlay
finishes the session itself by running the CLI at `RF_CLI`, says in its
log why, and quits. It runs the CLI rather than reimplementing any of it,
because a second copy of the shutdown is a second thing to get wrong
about somebody's recording. `19-orphan-rescue` presses stop with nothing
at all listening and waits for `feedback.md`.

Inside draw mode, plain keys with no modifier:

| Key | Action |
| --- | --- |
| `p` | pen, freehand |
| `a` | arrow, straight, head at the end of the drag |
| `r` | rectangle outline |
| `h` | highlighter, thick and translucent |
| `t` | text, click to place a caret and type |
| `1`…`6` | red, orange, yellow, green, blue, white |
| `[` `]` | thinner, thicker |
| `u` `c` | undo, clear |
| `esc` | leave draw mode, or commit the text being typed |
| the active tool's own key | leave draw mode |

Leaving draw mode hides the application, which is what hands the keyboard
back to whatever the user is talking about. Both the mark windows and the
palette are exempt from that hiding with `canHide = false`. Putting the
pen down is not rubbing the drawing out: a user who circles something and
then stops drawing to talk about it would otherwise be left pointing at
nothing, and the shutter frame, which is drawn on the mark windows, would
never be seen at all outside draw mode.

Text is a shape like any other: a point, a colour, a size and a string.
Click places the caret, typing edits it, `esc` or `return` commits it and
clicking elsewhere commits it and starts another. An empty string commits
nothing. While text is being typed the plain letter keys are text and not
tool shortcuts, which is the one place in the overlay where a key means
two things, so the palette says which mode is on.

### The palette

A person who is talking to their computer cannot tell whether a silent
tool is recording, and a tool that lost the microphone without saying so
wastes the whole session. So the overlay shows one small window, and not
a heads-up display that fades:

- Bottom centre by default, draggable anywhere, and it remembers where it
  was put for the next session.
- A red dot and the elapsed time, which is the proof that recording is
  live. The dot pulses once a second.
- An input meter beside the clock, five rising bars, lit from the level
  of the recording itself. The clock proves the recorder is running and
  says nothing about whether it can hear anything, and the difference
  between those two is a whole lost session. After four seconds of
  silence the row turns red, the meter pulses empty and it says NO
  SOUND in words, and the menu bar item says it too. Four seconds,
  because one lost second is a hiccup and a room with nobody talking in
  it still sits far above the threshold, so a pause in the conversation
  never reaches it. The session keeps recording throughout.
- A row of tools: pen, arrow, rectangle, highlighter, text. Each button
  draws the mark its tool makes rather than the letter that reaches it,
  because five letters in a row read as one word and not as five
  controls. The letter is in the button's tooltip with the tool's name.
  The active one is lit. Clicking one selects it and enters draw mode,
  and clicking the one that is already lit leaves draw mode.
- A Done button, shown only while drawing, which leaves draw mode. The
  way out has to be visible at the moment the overlay is holding every
  click on the screen, not only written in a key list that scrolled away.
- Six colour swatches and a width control, both reflecting the current
  state, because the keyboard shortcuts change state that is otherwise
  invisible. The width is shown as a dot at the size it will draw at,
  because a number says nothing about the mark it is about to make.
- A camera button for the full screen shot, a second one for a region,
  the number of shots taken so far, and a stop button.
- Two rows, not one. The tools, the colours and the width belong to draw
  mode, and a session is mostly spent talking, so idle the row carries
  only the clock, one Draw button, the two capture buttons, the count and
  Stop. It is 404 wide idle and 852 drawing, and it grows leftwards: the
  right hand end is the anchor, so every control that exists in both rows
  sits at the same place on the screen in both. Draw mode is entered by
  clicking in this row, and a control that moves as it starts moves out
  from under the cursor that started it. Stop moving is a click that
  draws a mark instead of ending the session.
- Every control names its key underneath itself, at 8 points, as well as
  in its tooltip. The keys are the whole point of this tool and its user
  is talking, not hunting for a tooltip.
- Every control is a rectangle registered while the row is drawn, and so
  is every key hint, so `14-palette-layout` can assert of both rows that
  no two controls overlap, no two hints collide, nothing falls off the
  end, every control has a tooltip, and the shared controls have not
  moved between the two.
- The row sits at 70% opacity while idle and full strength while the pen
  is down or the pointer is on it. It is over the user's work for the
  whole session.
- The palette window alone has `ignoresMouseEvents = false` while idle.
  The full screen mark windows stay click through, so the palette can be
  clicked while everything under it is untouched.
- The position remembered between sessions is the right hand end, not the
  left, because that is the end that stays put when the row changes
  width.
- A gear opens the settings window. It is in the row and not only in the
  menu bar item, because on a full menu bar macOS places that item in the
  notch, where it is drawn, clickable and invisible.

### The menu bar item

A red dot and the elapsed time, with a menu carrying every action, the
settings and Stop. The menu bar is the one place a full screen
application cannot cover, an unplugged display cannot take away and a
palette dragged out of reach cannot hide, so it is the way back to a
session that has become unreachable any other way. Its last entry force
quits the overlay alone, and says what that leaves behind: the recording
keeps running and `recordfeedback stop` still finishes the session.

macOS lays status items out from the right, and on a display with a notch
it will place one in the hole rather than refuse it. The overlay measures
its own item against `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`
after the windows are up, and says so when it landed there, because an
item that is drawn and invisible is worse than one that was refused. The
CLI prints whatever the overlay warned about as part of the start banner,
since nobody opens `overlay.log`.

The palette is furniture, so it is hidden for the instant of a capture,
with the crosshair, and put back after. That is only possible because the
overlay owns the capture keys.

`screencapture -x` takes the shutter sound out, so that the shot does not
land in the recording of the person talking. That leaves a successful
screenshot looking exactly like a key that did nothing, so once the file
is on disk the overlay flashes a white frame around every screen for
350ms, and lights the camera button in the palette while it does. The
frame is at the four edges of the screen and the eye of someone mid
sentence is at neither edge, so the confirmation is repeated on the
control that was clicked. It is drawn after the capture, so it can never
appear in the shot it is confirming, and it is drawn even when the marks
are hidden. A full screen capture that writes no file prints the Screen
Recording fix; a region capture that writes none does not, because escape
cancels one.

The drawing model is a list of shapes. A shape is a tool, a colour, a
width, a list of points and, for text, a string. Freehand appends points on drag. Arrow and
rectangle keep two points and update the second one while dragging. The
arrow is sized from a width that is usually small, so its head is clamped
to the length of the drag and its shaft is butt capped and stopped inside
the head: at the wide end a round cap puts half a width of ink past the
point the user dragged to, and an unclamped head on a short drag runs
back out through the tail. `17-wide-arrow` renders arrows through the
drawing code and counts the ink outside the two points.
Redraw everything in `draw(_:)`. Undo removes the last shape. This is
small enough that nothing more clever is needed, and a shape list is
what makes undo one line.

The highlighter draws with alpha 0.35, a round cap and a width of 24 by
default.

Safety: the overlay quits by itself after 4 hours, and `pkill rf-overlay`
always frees the screen. Both go in the README, because a stuck overlay
that swallows clicks is the one failure that a person cannot debug with
the mouse.

### The constraint that decides whether this works

`screencapture`, which is what `⇧⌘4` runs, composites the screen. An
overlay window is part of that composite, so the marks land in the file.
This must be proven by a test and not by reasoning, because if it is
false the whole overlay is worthless and the design has to change to
having the tool take the screenshot itself.

The proof: start the overlay, draw a shape in a known colour through
synthetic events, run `screencapture -x` to a file, and count pixels of
that colour with `uv run --with pillow python -c ...`. `uv` is
installed. Pillow is not installed globally and does not need to be.

One known limit to write in the README: `⇧⌘4` then space captures a
single window rather than a region, and a window capture excludes the
overlay. Region and full screen capture include it.

### Voice control

In active development and not yet reliable. Measured on this machine
across a two minute session in the author's own voice, seven commands
landed out of considerably more attempts, and "let's draw" did not land
once in about ten tries. Everything else in the tool works without it and
the keys and the palette do all of the same jobs, so it stays off by
default and the README says plainly that it is not to be depended on.

Off until it is asked for, with `--voice` or the settings window. It
needs a macOS permission of its own and a tool that starts listening for
orders because it was installed is not one a person can predict.

The audio comes from the recorder's own level segments, fed to
`SFSpeechAudioBufferRecognitionRequest`, and never from a second capture
of the microphone. Two consumers of one device is a thing that can half
fail, and a recogniser hearing a stream the recording never got would
act on words that are not in the transcript. It also means the overlay
needs no Microphone permission of its own, that the recogniser and
whisper are timestamped against the same clock, and that the whole path
is drivable by a test through `RF_FFMPEG_INPUT` and `say`.

`requiresOnDeviceRecognition` is set, and a machine with no offline
recogniser for the locale is refused with an explanation rather than
falling back to the network one. This tool records everything a person
says while they work. macOS shows its own prompt saying speech data will
be sent to Apple; that is the generic system wording and not what this
tool asks for.

Every command is prefixed by a trigger word, `let's` by default and
configurable, because a session is mostly sentences like "the rectangle
in the corner is the wrong colour" and matching bare phrases against
that changes the tool twice in one sentence. Saying the escape phrase,
`not a command` by default, in front of one makes it words: it swallows
the trigger and the phrase behind it and both land in the transcript.
Without that there is no way to tell this tool what to write down. An
empty trigger is refused, since it would arm every phrase in the table
on ordinary speech.

Phrases are a list the user edits, several per command, and they are
matched longest first so that "let's take a screenshot of this area"
reaches the region capture and not the full screen one whose phrase is
its first three words. The commands are `draw`, `done`, `clear`, `undo`,
the five tools, the six colours, `bigger`, `smaller`, `screenshot`,
`region`, `hide`, `show` and `stop`.

A recogniser hands back the whole sentence again on every revision, so a
command already acted on is remembered by where it sat in the utterance,
and the same command does not fire twice within one and a half seconds.
A spoken command produces no click and no keypress, so the row says what
it heard for two and a half seconds afterwards, and says so in the
palette when voice control was asked for and could not start.

Each command is appended to `commands.json` in the session, with the
offset it was spoken at, the command, and the words that reached it,
written before it is acted on because `stop` ends the process. `stop`
takes them back out of the transcript and lists them under `## Spoken
commands` instead. They are instructions that were already carried out,
and a reader who takes them for feedback acts on them a second time. The
two recognisers do not agree word for word, so the phrase is found by
overlap within a few seconds of where it was logged, and a command that
cannot be found is reported as not having been removed rather than
having the transcript cut at a guess. Only the characters the matched
words occupied are cut, because rebuilding the segment from its words
costs every other sentence in it its capitals and its punctuation, and
whether the command shares a segment with feedback is whisper's choice
and not this tool's.

The settings window carries this on a tab of its own: the switch, the
trigger word, the escape phrase, and every command's phrases one per
line.

Listening is started and stopped mid session by the `listen` key and by
a microphone button in the anchored end of the palette, struck through
when nothing is listening. A window three clicks away is not reachable
by someone whose hands are off the keyboard, which is the whole point of
this feature. It throws the same switch the settings window shows rather
than a second session only one: two notions of listening would leave
that window reading on while nothing listened. The button is drawn in
both states, because a control that appears only when it is on is one
nobody can find to turn on, and it is lit only when a listener is
actually running, so a recogniser that failed to start does not show as
listening.

## The slash command

`commands/recordfeedback.md`, symlinked to
`~/.claude/commands/recordfeedback.md` by `install.sh`.

```markdown
---
description: Record spoken feedback with screen annotations, then act on it
argument-hint: [stop|status|abort|doctor]
allowed-tools: Bash, Read
---
```

The body tells Claude what to do with `$ARGUMENTS`:

- Empty. Run `recordfeedback start`. Print the hotkeys to the user in
  three lines or fewer. Then call `recordfeedback wait --timeout 570`
  in a loop until it exits 0 or 3, so a session of any length is
  covered. Then run `recordfeedback stop`, read the `feedback.md` path
  from its last line, read that file, read every screenshot it names
  with the Read tool, restate the feedback as a short list, and start
  the work.
- `stop`. Only the stop and process half, for a session the user ended
  by interrupting the turn.
- `status`, `abort`, `doctor`. Run the CLI and print the output.

The Bash timeout for `wait` is 570 seconds and the tool ceiling is 600.
Do not raise it.

While `wait` blocks, the user cannot type in Claude Code. That is
intended, they are talking, not typing. Control-C interrupts the turn
and leaves the recorder running, and `/recordfeedback stop` picks it up.
Say this in the README.

## Configuration

Environment variables, all with working defaults:

| Variable | Default | Meaning |
| --- | --- | --- |
| `RF_HOME` | `~/.recordfeedback` | state and sessions |
| `RF_MODEL` | the turbo model in `RF_HOME/models` | whisper model file |
| `RF_LANG` | `auto` | language passed to `-l` |
| `RF_DEVICE` | the input macOS is set to use, by name | avfoundation audio input index |
| `RF_SHOT_DIR` | `defaults read com.apple.screencapture location`, else `~/Desktop` | where to look for screenshots |
| `RF_KEEP_SHOTS` | unset | leave the originals in the screenshot folder instead of moving them |
| `RF_FFMPEG_INPUT` | unset | replaces the whole avfoundation input, for tests |
| `RF_DEAD_DBFS` | `-85` | level at or below which the input counts as silence, passed to the overlay by `start` |
| `RF_DEAD_SECONDS` | `4` | silence before the palette raises its alarm |
| `RF_VOICE_LISTEN` | unset | in the probe build only, `1` lets a case start the recogniser. Without it a probe never spawns whisper for audio it has no use for |
| `RF_NO_SCREEN` | unset | `1` skips the cases that put windows on the screen, so the suite can be run on a machine somebody is working at |
| `RF_WHISPER` | `whisper-cli` on the usual paths | the binary voice control listens with |

The settings file `~/.recordfeedback/settings.json` carries the
shortcuts and, under `voice`, `enabled`, `trigger`, `escape` and
`phrases`. It is written out in full, defaults included, because it is
where a person goes to see what they can say and a key that is not there
is a sentence they never find out about.

`RF_FFMPEG_INPUT` is what makes the pipeline testable without a
microphone and without a person. A test sets it to a synthetic source
and everything downstream runs unchanged.

A session where nobody spoke is not the same fixture as a broken
microphone, and `test/lib.sh` keeps them apart. `RF_ROOM_TONE` is white
noise at about -71 dBFS, which is what this machine's microphone reads
in a quiet room: quiet enough that `stop` calls the session silent, and
alive enough that `start` does not read it as a dead input. `anullsrc`
is the dead input. Spelling one with the other is how a lost session
gets written off as a quiet one.

## Testing

`test/run.sh` runs every case and prints one line each. No framework.
Exit non-zero if any case fails. Every case cleans up its own session
directories, under `RF_HOME=$repo/test/tmp/home`.

The suite runs on the machine somebody is working at, so it may not take
that machine away from them. Two rules follow. The probe build never
calls `NSApp.activate` or makes a window key: a case drives the code
directly and has no use for real focus, while every case that entered
draw mode used to pull the keyboard out of whatever the person was
typing in. And `RF_NO_SCREEN=1` skips the cases that put windows on the
screen, through `needs_screen` in `test/lib.sh`, so the rest can be run
mid task without anything appearing over the work.

The cases that must exist:

1. `doctor` reports every dependency present.
2. A session started with `RF_FFMPEG_INPUT` set to a synthetic source
   records in real time. Sample `out_time_us` from `ffmpeg.progress`
   twice and assert the recorded audio advances one second per second of
   wall clock to within 2 percent, and that the finished WAV covers the
   session window to within one second. The rate is the property that
   matters. Both the real input and the synthetic one carry a fixed
   startup offset of about half a second, measured at -0.574 seconds for
   the microphone and +0.595 for the synthetic source, which says
   nothing about drift, so an absolute half second tolerance on the
   window would fail on a recorder that is working perfectly.
3. Speech in, words out. Build the fixture with the macOS speech
   synthesiser, which needs no person and no microphone:

   ```
   say -v Samantha -o fixture.aiff "The button on the cockpit page is misaligned"
   ffmpeg -i fixture.aiff -ac 1 -ar 16000 fixture.wav
   ```

   Run the transcription step on it and assert the text contains
   "cockpit" and "misaligned", case-insensitively. This is the only
   honest end to end check of the speech half.
4. Screenshot collection picks up a file written by `screencapture -x`
   during the session, ignores one written before `start.ref` and one
   written after `stop.ref`, and names the copies with the right elapsed
   times.
5. The merge places a screenshot after the segment that was being spoken
   at its offset. Drive this from a hand written `transcript.json` and
   `shots.json` so it does not need audio at all.
6. `stop` on a session with no audio and no screenshots still writes a
   `feedback.md` and says the session was empty.
7. `start` refuses while a session is live, and names the live one.
8. The overlay pixel test above. It needs a real screen, so it must skip
   itself with a clear message when `screencapture` cannot run, and it
   must not be the reason `test/run.sh` fails in a headless run.
9. `start` refuses an input that is delivering silence, says so in a way
   that names the way out, and leaves no session behind, while a real
   signal through the same path still starts. `anullsrc` is what a
   denied microphone, a muted device and an unrouted virtual mixer all
   look like on the wire.
10. The palette raises its alarm on a dead input, says NO SOUND in
    words, reaches the menu bar, and clears when the input comes back.
    An alarm that latches is one the user learns to ignore.
11. The grammar reads what a person says. The sentences that must reach
    nothing matter more than the ones that must reach something: "the
    rectangle in the corner is the wrong colour" and "I think the arrow
    should be red here" are what a session is made of, and a trigger
    with nothing known behind it is the user talking. "let's take a
    screenshot of this area" reaches the region capture and not the full
    screen one. The escape phrase holds. Two commands in one breath both
    land.
12. A spoken command comes out of the transcript and is listed on its
    own, proven against a real whisper transcript of real spoken audio,
    with the feedback either side of it surviving intact.
13. A phrase typed into the settings window reaches the grammar that
    matches speech, is written to the settings file, replaces rather
    than joins the defaults, and does not flatten the shortcuts that
    live in the same file. An empty trigger word is refused.

14. Listening starts and stops from the key mid session, the row carries
    the control in both states and names which it is, and the state the
    key left is the state the settings file holds.
15. The whole voice path through the recogniser macOS ships, from spoken
    audio to the command log, with the feedback either side of the
    command reaching nothing. It skips until Speech Recognition is
    granted, since it stands in for nothing and cannot ask.

A case must never put a macOS permission dialog on the screen of whoever
is running the suite. The probe build refuses to start the recogniser
unless `RF_VOICE_LISTEN=1`, so a case about the voice settings cannot
ask for Speech Recognition.

## Build order

Each step ends with its tests green and a commit. Do not start the next
one before the previous one is proven by something that runs.

1. `doctor` and the session directory layout. Case 1.
2. Recording: `start`, `status`, `abort`, `stop` down to a finished WAV,
   with `RF_FFMPEG_INPUT`. Cases 2 and 7.
3. Transcription and `transcript.json`. Case 3.
4. Screenshot collection and `shots.json`. Case 4.
5. `feedback.md` merge. Cases 5 and 6.
6. `wait` and the stop file.
7. The overlay: window, draw mode, pen, then arrow, rectangle,
   highlighter, colours, undo, clear, the HUD. Case 8 as early as the
   first pen stroke exists, because it decides the design.
8. The slash command and `install.sh`.
9. `README.md` and `docs/decisions.md`.
10. A real session, by hand, start to finish, with the user.

After step 6 the tool is already useful without the overlay. Say so, so
that the overlay being hard does not block the rest.

## Out of scope

No cloud speech service. No video capture. No editing the transcript
before Claude sees it. No menu bar application. No Xcode project. No
Homebrew formula. These are all reasonable later and none of them is
needed to answer the question this tool exists for.
