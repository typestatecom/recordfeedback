# Prior art

What else does this job, checked on 2026-08-24 by reading vendor pages
and search results. Nothing here was installed or tested, so treat the
feature claims as the vendors' own. Recorded so the question does not
have to be asked again from nothing.

The short version: four commercial macOS apps ship into this lane,
Anthropic ships two pieces of it first party, and no open source project
was found doing the same thing. Absence from a search is weak evidence,
so that last point is the one most likely to go stale.

## Same job

**Assist**, <https://assistapp.dev>, $15 once, proprietary, macOS 14+,
Apple silicon for voice. Closest on capture. Hold Option to draw on the
screen and speak into the same capture. Local WhisperKit, raw audio never
saved, transcript only. Also watches running Claude Code and Codex tasks
from the notch and answers their permission prompts. The unit is one
capture and the intent spoken over it, not a session with a timeline.

**Annotate**, <https://www.aat.ee/projects/annotate>, free,
proprietary, Apple silicon. Closest in intent. Records the screen while
you draw with pen, rectangle and text and speak, aligns the speech to
what was on screen when it was said, and hands the agent frames plus
transcript over MCP rather than a video file. Works with Cursor, Claude
Code and Codex. Local only, no account.

**Casso**, <https://usecasso.app>, $29 once, proprietary, Mac and
Windows. Annotation without voice. Numbered boxes over the UI, optional
notes, and it writes a full screenshot, per box crops, a composite and a
markdown prompt to `/tmp/casso/sessions/`, then optionally auto pastes
into the terminal. The output shape is close to ours.

**Clipy**, <https://clipy.online/for/claude-code>. Records screen plus
narration and produces a markdown document it calls an AREC twin: summary,
key frames with click coordinates, full timestamped transcript. A skill
installed by curl recognises a `clipy.online/video/<id>` link pasted into
Claude Code. Cloud based, which is the main split from the rest.

## First party

**Claude Code voice dictation**, shipped 2026-03-03. `/voice`, hold
space, speech transcribes into the prompt box, tuned for code vocabulary
with the project name and git branch as recognition hints. Voice only, no
screen and no drawing.

**Record a Skill** in Claude Cowork, shipped 2026-07-21. Records screen
plus voice narration of a task and distils it into a reusable skill file.
A different purpose, teaching a repeatable workflow rather than giving
feedback on the thing in front of you, and it lives in the desktop app
rather than the terminal.

## Adjacent

- **screenpipe**, <https://github.com/screenpipe/screenpipe>, open
  source. Records the screen continuously and serves it to agents as
  context. Always on rather than session scoped.
- Local dictation with no screen: OpenSuperWhisper, OpenWhispr,
  superwhisper, Wispr Flow, Aqua Voice.
- Capture and annotation with no agent: CleanShot X, and **Capso**,
  <https://github.com/lzhgus/Capso>, open source Swift with a reusable
  `AnnotationKit`.
- Web QA feedback, the older form of the idea: Jam.dev, Marker.io,
  BugHerd. All three added MCP servers so agents can read the reports.
  Screenshots and console logs, browser only, no voice.

## What is left to this tool

1. It runs inside the agent's turn. Every product above is an external
   app driven by hand, after which you paste, link or hand over MCP.
   Here the slash command starts the recording, blocks on it, stops it
   and reads the result in one turn. Nothing found has that shape.
2. One document, session shaped. Many screenshots interleaved into one
   transcript by timestamp. Assist and Casso are one capture at a time,
   Annotate and Clipy are video the agent samples.
3. No MCP server, no proprietary format, no account, no upload. The
   output is a markdown file with absolute paths that outlives the tool.
4. Both capture modes with the full palette on hotkeys, and region crops
   of the same marks. Casso has the palette without voice, Assist has the
   voice with a thinner palette.

The lane is crowded and moving, so 1 is the claim to recheck before it is
made in public.
