# A screenshot taken from inside draw mode is the whole point of the overlay:
# the marks are on the screen and the shot is what carries them to the reader.
# Draw mode is also the one state where this application is frontmost and its
# windows cover every screen, so it is the state where a capture can be lost.
. "$REPO/test/lib.sh"

OVERLAY="$(probe_overlay)" \
  || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"

command -v screencapture > /dev/null 2>&1 || skip "no screencapture on this machine"

needs_screen

session="$RF_HOME/sessions/capture"
mkdir -p "$session"
touch "$session/start.ref"

RF_SESSION="$session" RF_OVERLAY_SELFTEST=capture "$OVERLAY" \
  > "$RF_CASE_TMP/overlay.log" 2>&1 &
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
  "the probe was still in draw mode when it asked for the capture. The probe said:
$contents"

assert_eq "$(field files)" "shot-001.png" \
  "a capture asked for from inside draw mode writes one file into the session inbox.
  If this is empty the shot was never taken and the session ends with no
  screenshots at all. The overlay said:
$(cat "$RF_CASE_TMP/overlay.log")
  The probe said:
$contents"

[ -s "$session/inbox/shot-001.png" ] \
  || fail "$session/inbox/shot-001.png is empty, so screencapture wrote nothing"

assert_eq "$(field confirmed)" "1" \
  "a shot that lands is confirmed on screen. screencapture is run with -x so
  that the shutter does not land in the recording, which leaves a successful
  screenshot looking exactly like a key that did nothing. The probe said:
$contents"

assert_eq "$(field still-flashing)" "0" \
  "the confirmation clears itself, rather than staying on the screen and in
  every later shot. The probe said:
$contents"

echo "a screenshot taken from inside draw mode lands in the session inbox"
