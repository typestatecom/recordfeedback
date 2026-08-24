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
