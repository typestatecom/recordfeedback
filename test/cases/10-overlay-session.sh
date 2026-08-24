# The overlay takes its own screenshots into the session inbox, so a count that
# only looks at the screenshot folder tells a person who just pressed the
# capture key that nothing was captured.
. "$REPO/test/lib.sh"

export RF_FFMPEG_INPUT="-re -f lavfi -i anullsrc=r=16000:cl=mono -t 600"
export RF_SHOT_DIR="$RF_CASE_TMP/shots"
mkdir -p "$RF_SHOT_DIR"

"$RFB" start --no-overlay > "$RF_CASE_TMP/start.out"
session="$(sed -n 's/^  session: //p' "$RF_CASE_TMP/start.out")"
[ -n "$session" ] || fail "start printed no session path"
trap '"$RFB" abort > /dev/null 2>&1 || true' EXIT

out="$("$RFB" status)"
assert_contains "$out" "0 so far" "status before any screenshot"

mkdir -p "$session/inbox"
touch "$session/inbox/shot-001.png"
out="$("$RFB" status)"
assert_contains "$out" "1 so far" "status after the overlay captured one shot"

# A shot from the screenshot folder still counts, and the two add up.
touch "$RF_SHOT_DIR/Screenshot 2026-08-24 at 10.00.00.png"
out="$("$RFB" status)"
assert_contains "$out" "2 so far" "status with one overlay shot and one folder shot"

"$RFB" abort > /dev/null
trap - EXIT

# --- the keys start prints are the keys the overlay registers.
if [ -x "$REPO/bin/rf-overlay" ]; then
  out="$("$RFB" start)"
  session="$(printf '%s' "$out" | sed -n 's/^  session: //p')"
  for key in opt-cmd-A opt-cmd-X opt-cmd-R opt-cmd-Z opt-cmd-C opt-cmd-H opt-cmd-S; do
    assert_contains "$out" "$key" "the hotkey list start prints"
  done
  # Option-Command-D is the system's own Dock shortcut and Carbon will not hand
  # it over, so offering it sends the user to a key that does nothing.
  assert_not_contains "$out" "opt-cmd-D" "the hotkey list start prints"
  "$RFB" abort > /dev/null
fi
