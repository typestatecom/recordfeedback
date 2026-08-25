# No audio and no speech is not a failure. A session where nobody said
# anything still has to produce a document, and it has to say why it is empty
# rather than leave a reader guessing.
. "$REPO/test/lib.sh"

export RF_MODEL="$HOME/.recordfeedback/models/ggml-large-v3-turbo-q5_0.bin"
[ -f "$RF_MODEL" ] || skip "the whisper model is not on this machine"

folder="$RF_CASE_TMP/screenshots"
mkdir -p "$folder"
export RF_SHOT_DIR="$folder"
export RF_LANG=en

# Digital silence, which is what a session with a muted microphone actually
# produces. -re makes it arrive in real time like a microphone does, so the
# recorder is still alive when stop asks it to quit.
export RF_FFMPEG_INPUT="-re $RF_ROOM_TONE -t 30"

"$RFB" start --no-overlay > "$RF_CASE_TMP/start.out"
session="$(sed -n 's/^  session: //p' "$RF_CASE_TMP/start.out")"
[ -n "$session" ] || fail "start printed no session path"

out="$("$RFB" stop)"
echo "--- stop ---"; echo "$out"

# The last line, alone, is the path of the document, so a caller can read it
# without parsing prose.
last_line="$(echo "$out" | tail -1)"
assert_eq "$last_line" "$session/feedback.md" "the last line of stop"
assert_file "$session/feedback.md"

doc="$(cat "$session/feedback.md")"
echo "--- feedback.md ---"; echo "$doc"
assert_contains "$doc" "# Feedback session" "the document"
assert_contains "$doc" "0 screenshots" "the summary line"

# A reader who knows nothing about the tool has to understand what happened.
lower="$(echo "$doc" | tr '[:upper:]' '[:lower:]')"
case "$lower" in
  *silent*|*"nothing was said"*|*"no speech"*) ;;
  *) fail "the document does not say the recording was silent. Got:
$doc" ;;
esac

# stop is idempotent, and it is called twice whenever a person uses the hotkey
# and then the slash command.
out2="$("$RFB" stop "$session")"
echo "--- second stop ---"; echo "$out2"
assert_eq "$(echo "$out2" | tail -1)" "$session/feedback.md" "the last line of the second stop"

# The session is over, so nothing may still claim to be running.
[ -e "$RF_HOME/current" ] && fail "current still exists after stop"
assert_eq "$(jq -r .status "$session/meta.json")" "done" "the session status"

status_out="$("$RFB" status)"
assert_contains "$status_out" "No session is running" "status after stop"

# last finds the session that has a feedback.md.
assert_eq "$("$RFB" last)" "$session/feedback.md" "last"
