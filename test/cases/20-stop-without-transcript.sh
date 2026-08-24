# Stopping a session flushes the recorder, transcribes the words and merges the
# document. The middle one is the only step that needs a model on disk and a
# working whisper, and it is the step most likely to fail. When it does, the
# audio, the screenshots and their timings are all still there, and throwing
# the whole document away rather than writing the half that survived loses
# everything the user did with their hands.
. "$REPO/test/lib.sh"

export RF_FFMPEG_INPUT="-re -f lavfi -i sine=frequency=440:sample_rate=16000"
# There is no model at this path, which is exactly the failure being tested.
export RF_MODEL="$RF_CASE_TMP/no-such-model.bin"

"$RFB" start --no-overlay > "$RF_CASE_TMP/start.out" 2>&1 \
  || fail "start failed:
$(cat "$RF_CASE_TMP/start.out")"
session="$(sed -n 's/^  session: //p' "$RF_CASE_TMP/start.out")"
[ -n "$session" ] || fail "start printed no session path"
trap '"$RFB" abort > /dev/null 2>&1 || true' EXIT

mkdir -p "$session/inbox"
cp "$REPO/test/cases/20-stop-without-transcript.sh" /dev/null 2>/dev/null || true
screencapture -x "$session/inbox/shot-001.png" > /dev/null 2>&1 || true
[ -f "$session/inbox/shot-001.png" ] || printf 'x' > "$session/inbox/shot-001.png"

sleep 2

out="$("$RFB" stop 2> "$RF_CASE_TMP/stop.err")" || status=$?
trap - EXIT

assert_file "$session/feedback.md"

document="$(cat "$session/feedback.md")"
assert_contains "$document" "Screenshot" \
  "the document still names the screenshot that was taken. The picture and the
  second it was taken at both survived the step that failed, and they are half
  of what this tool exists to hand over"

[ -s "$session/audio.wav" ] \
  || fail "the recorder was not flushed, so the words are gone as well as the
  transcript. ffmpeg keeps the recording buffered until it is asked to quit."

errors="$(cat "$RF_CASE_TMP/stop.err")"
assert_contains "$errors" "$session/audio.wav" \
  "stop says where the audio it could not transcribe was kept, because the
  words are recoverable and the user has no way to know that. It said:
$errors"

assert_contains "$errors" "recordfeedback transcribe" \
  "stop says how to fill the document in once the model is there. It said:
$errors"

# The last line of stop is the path, alone, and a caller reads it without
# parsing prose. That contract has to hold on the bad day too.
last="$(printf '%s\n' "$out" | tail -n 1)"
assert_eq "$last" "$session/feedback.md" \
  "the last line stop prints is still the path to the document. Everything
  that calls this tool reads that line, so a failure that changes it is a
  failure that strands the caller as well as the session"

echo "a session that cannot be transcribed still hands over its pictures"
