# start refuses while a session is live, and names the live one.
. "$REPO/test/lib.sh"

export RF_FFMPEG_INPUT="-re -f lavfi -i sine=frequency=440:sample_rate=16000"

"$RFB" start >/dev/null
session="$(readlink "$RF_HOME/current")"

set +e
out="$("$RFB" start 2>&1)"
status=$?
set -e
echo "$out"

[ "$status" -ne 0 ] || fail "a second start succeeded while a session was live"
assert_contains "$out" "$session" "the refusal must name the live session"
assert_contains "$out" "already" "the refusal must say a session is already running"

# The refusal must not have touched the live session.
pid="$(cat "$session/ffmpeg.pid")"
kill -0 "$pid" 2>/dev/null || fail "the refused start killed the live recorder"

"$RFB" abort >/dev/null

# A stale current whose recorder is dead is cleaned up and start proceeds.
ln -sfn "$session" "$RF_HOME/current"
out="$("$RFB" start 2>&1)" || fail "start refused despite a stale current symlink: $out"
second="$(readlink "$RF_HOME/current")"
[ "$second" != "$session" ] || fail "start reused the stale session directory"
"$RFB" abort >/dev/null
