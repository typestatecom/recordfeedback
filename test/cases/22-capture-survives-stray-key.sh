# The overlay makes itself frontmost to draw, so every key the person presses
# while it is up lands in its own key monitor, and esc or the letter of the
# tool already chosen leaves draw mode. That happens after the capture was
# asked for and has nothing to do with whether the capture worked, so a probe
# that reads draw mode long after the fact reports somebody else's keystroke as
# a lost screenshot. This case injects that stray exit rather than waiting for
# a person to type during a test run.
. "$REPO/test/lib.sh"

OVERLAY="$REPO/bin/rf-overlay"

command -v screencapture > /dev/null 2>&1 || skip "no screencapture on this machine"

if [ ! -x "$OVERLAY" ]; then
  "$REPO/overlay/build.sh" > "$RF_CASE_TMP/build.log" 2>&1 \
    || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"
fi

probe="$RF_CASE_TMP/probe.png"
screencapture -x "$probe" > /dev/null 2>&1 \
  || skip "screencapture cannot run without a screen"
[ -s "$probe" ] || skip "screencapture produced nothing, so there is no window server"

session="$RF_HOME/sessions/stray"
mkdir -p "$session"
touch "$session/start.ref"

RF_SESSION="$session" RF_OVERLAY_SELFTEST=capture RF_OVERLAY_STRAY_EXIT=1 \
  "$OVERLAY" > "$RF_CASE_TMP/overlay.log" 2>&1 &
overlay_pid=$!
# shellcheck disable=SC2064
trap "kill -TERM $overlay_pid 2>/dev/null || true" EXIT

report="$session/capture.probe"
waited=0
while [ ! -f "$report" ]; do
  kill -0 "$overlay_pid" 2>/dev/null || fail "the overlay exited before it reported:
$(cat "$RF_CASE_TMP/overlay.log")"
  sleep 0.2
  waited=$((waited + 1))
  [ "$waited" -lt 150 ] || fail "the overlay never wrote $report:
$(cat "$RF_CASE_TMP/overlay.log")"
done

kill -TERM "$overlay_pid" 2>/dev/null || true
trap - EXIT

contents="$(cat "$report")"
field() { printf '%s\n' "$contents" | sed -n "s/^$1 //p"; }

assert_eq "$(field drawing)" "1" \
  "draw mode is reported as it was when the capture was asked for, not as it
  is three seconds later. Reading it late turns any keystroke that lands in
  the overlay during the wait into a failure about a screenshot that was in
  fact taken. The probe said:
$contents"

assert_eq "$(field files)" "shot-001.png" \
  "leaving draw mode after the capture was asked for does not cancel it. The
  file is written by a process that is already running. The probe said:
$contents"

[ -s "$session/inbox/shot-001.png" ] \
  || fail "$session/inbox/shot-001.png is empty, so screencapture wrote nothing"

echo "a stray key after the capture is not a lost screenshot"
