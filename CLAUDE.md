# recordfeedback

A macOS tool that records what you say and what you draw on the screen during
a working session, and hands a coding agent one document that joins the two.
Read SPEC.md first. It is the contract and it holds every fact about this
machine that was already checked, so that none of it is guessed again.

## Commands

- Tests: `test/run.sh`
- Build the overlay: `overlay/build.sh`
- Install the CLI and agent integrations: `./install.sh`
- Check the machine: `bin/recordfeedback doctor`

## How to work here

- Every step in the build order in SPEC.md ends with its tests green and
  one commit. Nothing is declared done because it looks right.
- Every bug gets a failing test first. Write the test, run it, see it
  fail against the unfixed code, then fix it, then see it pass. A test
  written after the fix proves nothing. If a defect cannot be reproduced
  in a test, say so out loud instead of skipping it quietly.
- Prove behaviour against the real thing. This tool is a shell around
  ffmpeg, whisper-cli, screencapture and AppKit, so a test that mocks
  those tests nothing. Use `RF_FFMPEG_INPUT` and the `say` fixture to
  run the real binaries without a person and without a microphone.
- Decide engineering yourself and record the calls worth keeping in
  `docs/decisions.md`, one short entry each, dated, saying what was
  chosen and what it costs. Ask on product decisions.
- Anything the user must do by hand, macOS permission prompts above all,
  is printed by the tool at the moment it is needed, not left in a
  README.

## Hard rules

- No em-dashes anywhere: code, comments, documents, commit messages,
  chat.
- One commit per task, `git add` the paths you changed and not `-A`, and
  the tree works at every commit.
- A comment says why, never what, and never the story. No date, no
  account of what the code used to do, no name of who found a bug. State
  the reason the code is the way it is and the failure the other way
  causes, and stop. History belongs in git and reasoning belongs in
  `docs/decisions.md`.
- Plain professional English in every document and every message. No
  marketing phrasing.
- Names are explicit and short, and neither at the other's cost. The
  idiom of the language wins: `opts`, `ctx`, `dir`, `pid`, `url` are
  words. An abbreviation coined in this repository is not.
- Shell is bash with `set -euo pipefail`, and every path that can hold a
  space is quoted. macOS names screenshots with spaces in them.
- A failure prints what failed, the command that failed and what to do
  about it. This tool runs while the user is talking to their computer
  and cannot watch a terminal.
