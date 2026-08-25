# wait is what lets one slash command cover a session of any length: Claude
# Code blocks on it, and the exit code says why it came back.
. "$REPO/test/lib.sh"

export RF_FFMPEG_INPUT="-re $RF_ROOM_TONE -t 600"

start_session() {
  "$RFB" start --no-overlay > "$RF_CASE_TMP/start.out"
  sed -n 's/^  session: //p' "$RF_CASE_TMP/start.out"
}

session="$(start_session)"
[ -n "$session" ] || fail "start printed no session path"

# --- the timeout is not a failure, it is how a 600 second tool call covers a
# --- session that runs for an hour.
began=$(date +%s)
set +e
"$RFB" wait --timeout 1
status=$?
set -e
elapsed=$(( $(date +%s) - began ))
assert_eq "$status" "2" "the exit code for a timeout"
[ "$elapsed" -le 4 ] || fail "wait --timeout 1 took ${elapsed}s"

# --- the stop hotkey writes the stop file, and wait has to see it quickly.
( sleep 1; touch "$session/stop" ) &
writer=$!
began=$(date +%s)
set +e
"$RFB" wait --timeout 20
status=$?
set -e
elapsed=$(( $(date +%s) - began ))
wait "$writer" 2>/dev/null || true
assert_eq "$status" "0" "the exit code when the stop file appears"
[ "$elapsed" -le 5 ] || fail "wait took ${elapsed}s to notice the stop file"

"$RFB" abort > /dev/null

# --- a dead recorder must not leave the caller blocked for the full timeout.
session="$(start_session)"
pid="$(cat "$session/ffmpeg.pid")"
( sleep 1; kill -KILL "$pid" 2>/dev/null || true ) &
killer=$!
began=$(date +%s)
set +e
"$RFB" wait --timeout 20
status=$?
set -e
elapsed=$(( $(date +%s) - began ))
wait "$killer" 2>/dev/null || true
assert_eq "$status" "3" "the exit code when the recorder dies"
[ "$elapsed" -le 6 ] || fail "wait took ${elapsed}s to notice the recorder died"

"$RFB" abort > /dev/null

# --- with no session at all, wait says so instead of blocking forever.
set +e
out="$("$RFB" wait --timeout 5 2>&1)"
status=$?
set -e
[ "$status" -ne 0 ] || fail "wait with no session should not report a stop"
assert_contains "$out" "no session" "wait with no session"
