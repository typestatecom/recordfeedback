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
| avfoundation audio inputs | `[0] MacBook Pro Microphone`, `[1] CASTER Stream Mix 1`, `[2] Microsoft Teams Audio`, `[3] CASTER` |
| Screenshot folder | `~/Desktop` (`defaults read com.apple.screencapture location` is unset) |
| Desktop access | **Not granted.** `ls ~/Desktop` fails with `Operation not permitted`. The terminal application needs Files and Folders, Desktop Folder, or Full Disk Access, or no screenshot can ever be collected. `doctor` checks this by listing the folder, because `-d` succeeds on a folder macOS will not let it read. |
| `~/.claude/commands/` | exists, empty. No global slash command competes with this one. |

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
  overlay/Overlay.swift    the annotation overlay, one file
  overlay/build.sh         swiftc invocation
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
5. Start `bin/rf-overlay` detached unless `--no-overlay`, store its pid.
6. Print the hotkeys and the session path.

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

### `status`, `abort`, `last`, `devices`, `doctor`

`status` prints the active session, elapsed time, audio file size and
screenshot count so far. `abort` stops everything and marks the session
`aborted` without transcribing. `last` prints the path of the newest
session that has a `feedback.md`. `devices` lists the avfoundation audio
inputs with their indexes. `doctor` checks every dependency in the table
above, the model file, the microphone permission and that the overlay
binary is built, and prints one line per check.

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

`overlay/Overlay.swift`, one file, built by `overlay/build.sh`:

```
swiftc -O -framework Cocoa -framework Carbon -o bin/rf-overlay overlay/Overlay.swift
```

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

| Key | Action |
| --- | --- |
| `⌥⌘D` | toggle draw mode |
| `⌥⌘C` | clear all marks |
| `⌥⌘Z` | undo the last mark |
| `⌥⌘S` | stop the recording session |
| `⌥⌘H` | hide or show the marks without clearing them |

`⌥⌘S` writes `$SESSION/stop`, where the session path comes from the
`RF_SESSION` environment variable the CLI sets when it launches the
overlay. The overlay never reads `~/.recordfeedback/current`, because
the session it belongs to is the one that started it.

Inside draw mode, plain keys with no modifier:

| Key | Action |
| --- | --- |
| `p` | pen, freehand |
| `a` | arrow, straight, head at the end of the drag |
| `r` | rectangle outline |
| `h` | highlighter, thick and translucent |
| `1`…`6` | red, orange, yellow, green, blue, white |
| `[` `]` | thinner, thicker |
| `u` `c` | undo, clear |
| `esc` | leave draw mode |

A heads-up display, top centre, shows the tool, the colour and the
width when draw mode is entered and after any change, and fades out
after 1.5 seconds. It must fade fully, because anything still on screen
lands in the next screenshot.

The drawing model is a list of shapes. A shape is a tool, a colour, a
width and a list of points. Freehand appends points on drag. Arrow and
rectangle keep two points and update the second one while dragging.
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
| `RF_DEVICE` | `0` | avfoundation audio input index |
| `RF_SHOT_DIR` | `defaults read com.apple.screencapture location`, else `~/Desktop` | where to look for screenshots |
| `RF_KEEP_SHOTS` | unset | leave the originals in the screenshot folder instead of moving them |
| `RF_FFMPEG_INPUT` | unset | replaces the whole avfoundation input, for tests |

`RF_FFMPEG_INPUT` is what makes the pipeline testable without a
microphone and without a person. A test sets it to a synthetic source
and everything downstream runs unchanged.

## Testing

`test/run.sh` runs every case and prints one line each. No framework.
Exit non-zero if any case fails. Every case cleans up its own session
directories, under `RF_HOME=$repo/test/tmp/home`.

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
