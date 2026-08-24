# Leaving draw mode gives the keyboard back to the application underneath by
# hiding this one, and hiding it takes the mark windows off the screen with it.
# Every mark the user drew disappears, and so does the frame that confirms a
# screenshot, which is the only confirmation the tool gives.
. "$REPO/test/lib.sh"

OVERLAY="$REPO/bin/rf-overlay"

if [ ! -x "$OVERLAY" ]; then
  "$REPO/overlay/build.sh" > "$RF_CASE_TMP/build.log" 2>&1 \
    || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"
fi

probe="$RF_CASE_TMP/probe.png"
screencapture -x "$probe" > /dev/null 2>&1 \
  || skip "screencapture cannot run without a screen"
[ -s "$probe" ] || skip "screencapture produced nothing, so there is no window server"

session="$RF_HOME/sessions/leave"
mkdir -p "$session"
touch "$session/start.ref"

RF_SESSION="$session" RF_OVERLAY_SELFTEST=leave "$OVERLAY" \
  > "$RF_CASE_TMP/overlay.log" 2>&1 &
overlay_pid=$!
# shellcheck disable=SC2064
trap "kill -TERM $overlay_pid 2>/dev/null || true" EXIT

report="$session/leave.probe"
waited=0
while [ ! -f "$report" ]; do
  kill -0 "$overlay_pid" 2>/dev/null || fail "the overlay exited before it reported:
$(cat "$RF_CASE_TMP/overlay.log")"
  sleep 0.2
  waited=$((waited + 1))
  [ "$waited" -lt 100 ] || fail "the overlay never wrote $report:
$(cat "$RF_CASE_TMP/overlay.log")"
done

kill -TERM "$overlay_pid" 2>/dev/null || true
trap - EXIT

contents="$(cat "$report")"
field() { printf '%s\n' "$contents" | sed -n "s/^$1 //p"; }

[ "$(field shapes)" -ge 1 ] \
  || fail "the probe drew nothing, so it cannot say what leaving draw mode did
  to the marks. The probe said:
$contents"

assert_eq "$(field marks-visible)" "$(field screens)" \
  "the marks stay on the screen after draw mode ends. Putting the pen down is
  not the same as rubbing the drawing out, and a user who points at something
  and then stops drawing to talk about it is left pointing at nothing. The
  probe said:
$contents"

assert_eq "$(field palette-visible)" "1" \
  "the palette stays up after draw mode ends. The probe said:
$contents"

assert_eq "$(field flash-visible)" "$(field screens)" \
  "the frame that confirms a screenshot is on a window the user can see, with
  draw mode off. The capture keys work whether or not the pen is down, and a
  silent capture with no confirmation is indistinguishable from a key that did
  nothing. The probe said:
$contents"

assert_contains "$(field tips)" "screenshot" \
  "the camera control names itself when the pointer rests on it, the way every
  tool does. A lens with no label is the one control in the row nobody can
  identify. The probe said:
$contents"

[ "$(field flash-hundredths)" -ge 30 ] \
  || fail "the shot confirmation was up for $(field flash-hundredths) hundredths
  of a second. The user is talking to their computer and not watching it, so a
  confirmation that brief is missed, and a missed confirmation is a key pressed
  again: this bug was found in a session that has four near identical shots
  taken in three seconds. The probe said:
$contents"

echo "the marks and the shot confirmation survive the end of draw mode"
