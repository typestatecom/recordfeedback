# An input that delivers digital silence is a dead microphone, and a session
# recorded through one is lost before it starts. start proves sound arrives,
# not merely that the recorder runs, and refuses the session while refusing
# still costs the user nothing.
. "$REPO/test/lib.sh"

# anullsrc is what a muted device, an unrouted virtual mixer and a denied
# microphone all look like on the wire: every sample zero.
export RF_FFMPEG_INPUT="-re -f lavfi -i anullsrc=r=16000:cl=mono"

set +e
out="$("$RFB" start 2>&1)"
status=$?
set -e
echo "$out"

[ "$status" -ne 0 ] || fail "start accepted an input that was delivering silence"
assert_contains "$out" "silence" "the refusal must say the input is silent"

# The fix has to be on the screen at the moment it is needed, not in a README.
assert_contains "$out" "recordfeedback devices" "the refusal must say how to pick another input"

# A refused start leaves nothing behind, exactly as the no-audio path does.
[ -L "$RF_HOME/current" ] && fail "the refused start left the current symlink behind"

sessions="$(find "$RF_HOME/sessions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "$sessions" "0" "the refused start left a session directory behind"

# A real signal through the same path still starts, so the check rejects
# silence and not the fixture.
export RF_FFMPEG_INPUT="-re -f lavfi -i sine=frequency=440:sample_rate=16000"
out="$("$RFB" start 2>&1)" || fail "start refused a live input: $out"
session="$(readlink "$RF_HOME/current")"

# The level stream is what the palette reads to show the meter, so it has to
# exist and carry numbers while the session is live.
assert_file "$session/levels/0.pcm"
levels="$(find "$session/levels" -name "*.pcm" -size +4000c | wc -l | tr -d " ")"
[ "$levels" -gt 0 ] || fail "the live session finished no level segments"

st="$("$RFB" status)"
echo "$st"
assert_contains "$st" "input:" "status must report the input level of a live session"

"$RFB" abort >/dev/null
