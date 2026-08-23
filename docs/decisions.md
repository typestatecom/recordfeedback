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
