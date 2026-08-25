# The overlay takes its own screenshots into the session inbox, so a count that
# only looks at the screenshot folder tells a person who just pressed the
# capture key that nothing was captured.
. "$REPO/test/lib.sh"

export RF_FFMPEG_INPUT="-re $RF_ROOM_TONE -t 600"
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
# The shortcuts are settings now, so a list typed into the CLI is a list that
# goes stale the first time anybody rebinds one. The overlay is asked.
if [ -x "$REPO/bin/rf-overlay" ]; then
  keys="$("$REPO/bin/rf-overlay" --print-keys)"
  [ -n "$keys" ] || fail "rf-overlay --print-keys printed nothing, so the CLI has
  no way to name a key without keeping its own copy of the list"

  for action in draw screenshot region undo clear hide stop; do
    printf '%s\n' "$keys" | grep -q "^$action " \
      || fail "--print-keys does not name '$action'. It said:
$keys"
  done

  out="$("$RFB" start)"
  session="$(printf '%s' "$out" | sed -n 's/^  session: //p')"
  while read -r action combination; do
    [ -n "$combination" ] || continue
    assert_contains "$out" "$combination" \
      "the keys start prints are the keys the overlay registered. The overlay
  reports '$action $combination'. Two copies of this list is one that goes
  stale the first time a key is rebound"
  done <<< "$keys"
  "$RFB" abort > /dev/null
fi
