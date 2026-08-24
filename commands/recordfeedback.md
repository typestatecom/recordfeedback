---
description: Record spoken feedback with screen annotations, then act on it
argument-hint: [stop|status|abort|doctor]
allowed-tools: Bash, Read
---

The user is about to talk instead of type. `$ARGUMENTS` decides what to do.

## No arguments: run a session

1. Run `recordfeedback start`.
2. Tell the user recording is live, in three lines or fewer, and list the
   keys: `⌥⌘A` draw, `⌥⌘X` screenshot, `⌥⌘R` screenshot a region,
   `⌥⌘Z` undo, `⌥⌘C` clear, `⌥⌘S` stop. Say nothing else. They are
   already talking and a wall of text is in their way.
3. Run `recordfeedback wait --timeout 570` with a Bash timeout of 570000
   milliseconds. Exit code 0 means the user pressed stop, 2 means the
   timeout passed and nothing is wrong, 3 means the recorder died. On 2,
   run it again, as many times as it takes. Do not raise the timeout: the
   Bash tool ceiling is 600 seconds. Print nothing between attempts.
4. Run `recordfeedback stop`. Its last line, alone, is the absolute path
   of `feedback.md`.
5. Read that file. Read every screenshot it names with the Read tool,
   by the absolute path in the document. The pictures are half the
   feedback and a path in a document is not a picture until it is read.
6. Restate the feedback as a short list of concrete items, so the user
   can see what was understood before any code changes.
7. Start the work.

## `stop`

The user ended the session by interrupting the turn, or with the hotkey.
Run `recordfeedback stop` and then steps 5 to 7 above. Do not start a new
session.

## `status`, `abort`, `doctor`

Run `recordfeedback` with that argument and print the output as it came.
Add nothing.

## When something fails

The CLI prints what failed, the command behind it and the fix. Pass that
through as it is written. Do not paraphrase a permission instruction: the
user has to click the exact switch it names.
