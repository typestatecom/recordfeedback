---
description: Record spoken feedback with screen annotations, then act on it
argument-hint: [stop|status|abort|doctor|voice on|voice off]
allowed-tools: Bash, Read
---

The user is about to talk instead of type. `$ARGUMENTS` decides what to do.

## No arguments: run a session

1. Run `recordfeedback start`.
2. Tell the user recording is live, in three lines or fewer, and list the
   keys exactly as `start` printed them. Do not write them from memory:
   they are settings, the user can rebind any of them, and `start` asks
   the overlay what is actually bound. If `start` printed anything else,
   a warning about the menu bar for instance, pass that through too. Say
   nothing else. They are already talking and a wall of text is in their
   way.
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
6. If the document has a `## Spoken commands` section, those are orders
   the user gave the recorder and they were already carried out. They
   are not feedback and nothing in them is a thing to do. Do not restate
   them as work.
7. Restate the feedback as a short list of concrete items, so the user
   can see what was understood before any code changes.
7. Start the work.

## `stop`

The user ended the session by interrupting the turn, or with the hotkey.
Run `recordfeedback stop` and then steps 5 to 7 above. Do not start a new
session.

## `voice on`, `voice off`

Voice control lets the user drive the overlay by saying "let's draw",
"let's pick red", "let's take a screenshot of this area". Run
`recordfeedback start --voice` for the next session, or for `voice off`,
`--no-voice`. If they ask for it mid session, tell them the Voice tab in
the settings window, reached by the gear in the palette, turns it on for
the session that is already running.

The first session that listens raises a macOS Speech Recognition prompt
and nothing is listening until it is answered. Say that, since they are
talking and not watching the screen.

## `status`, `abort`, `doctor`

Run `recordfeedback` with that argument and print the output as it came.
Add nothing.

## When something fails

The CLI prints what failed, the command behind it and the fix. Pass that
through as it is written. Do not paraphrase a permission instruction: the
user has to click the exact switch it names.
