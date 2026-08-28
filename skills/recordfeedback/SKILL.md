---
name: recordfeedback
description: Record spoken feedback with screen annotations, turn it into a joined transcript and screenshot document, and act on it. Use when the user invokes $recordfeedback or asks to start, stop, inspect, or abort a recordfeedback session.
---

# Record feedback

The user is about to talk instead of type. Interpret any text after the skill
name as the mode. With no mode, run a complete recording session.

## Start a session

1. Run `recordfeedback start`.
2. Tell the user recording is live, in three lines or fewer, and list the keys
   exactly as `start` printed them. The user can rebind them, so do not write
   them from memory. Pass through any other warning from `start`. Say nothing
   else because the user is already talking.
3. Run `recordfeedback wait --timeout 570`. Exit code 0 means the user pressed
   stop, 2 means the timeout passed normally, and 3 means the recorder died.
   On exit code 2, run it again for as long as the session continues.
4. Run `recordfeedback stop`. Its last line is the absolute path of
   `feedback.md`.
5. Read the entire feedback file and inspect every screenshot it names by its
   absolute path. The images are part of the feedback, not optional context.
6. If the document has a `## Spoken commands` section, do not treat anything
   in it as feedback. Those commands were already carried out while recording.
7. Restate the feedback as a short list of concrete items so the user can
   verify what was understood.
8. Start the requested work.

## Stop a session

When the mode is `stop`, or the user ended the session by interrupting the
turn, run `recordfeedback stop`, then continue from step 5 above. Do not start
a new session.

## Control voice commands

For `voice on`, run `recordfeedback start --voice` for the next session. For
`voice off`, run `recordfeedback start --no-voice`. If the user asks during a
session, tell them the `listen` key printed by `start` and that the microphone
button beside the gear controls the same setting.

The first listening session raises a macOS Speech Recognition prompt. Tell the
user that nothing listens until they answer it.

## Inspect or end without processing

For the modes `status`, `abort`, or `doctor`, run `recordfeedback` with that
argument and return its output without adding commentary.

## Failures

Pass through CLI failures exactly as written. In particular, do not paraphrase
permission instructions because the user must select the exact switch named.
