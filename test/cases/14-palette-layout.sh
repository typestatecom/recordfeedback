# The palette is one row of controls at a fixed width, and every control added
# to it pushes the ones after it along. Nothing about that is visible from the
# source, so the row is measured: no control may sit on top of another and none
# may fall off the end. A camera button under the Stop button is a screenshot
# key that stops the session.
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

session="$RF_HOME/sessions/layout"
mkdir -p "$session"
touch "$session/start.ref"

RF_SESSION="$session" RF_OVERLAY_SELFTEST=layout "$OVERLAY" \
  > "$RF_CASE_TMP/overlay.log" 2>&1 &
overlay_pid=$!
# shellcheck disable=SC2064
trap "kill -TERM $overlay_pid 2>/dev/null || true" EXIT

report="$session/layout.probe"
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

# Five tools, six colours, thinner, thicker, camera, Stop and Done.
[ "$(field controls)" -ge 16 ] \
  || fail "the palette registered only $(field controls) clickable controls, so
  the probe did not see the row it was meant to measure. The probe said:
$contents"

assert_eq "$(field overlaps)" "0 " \
  "no two controls in the palette overlap. The pairs are given as minX:maxX of
  each. The probe said:
$contents"

assert_eq "$(field outside)" "0" \
  "every control is inside the palette window. A control past the end of the
  window is drawn but can never be clicked. The probe said:
$contents"

assert_eq "$(field camera-idle)" "$(field camera-drawing)" \
  "the controls to the right of the tools sit in the same place whether draw
  mode is on or off. Draw mode is entered by clicking a tool, so anything that
  moves when it starts moves out from under the cursor that started it. The
  probe said:
$contents"

[ "$(field controls)" -eq "$(($(field controls-idle) + 1))" ] \
  || fail "draw mode should add exactly one control, the way out of it, and it
  added $(($(field controls) - $(field controls-idle))). The probe said:
$contents"

echo "the palette row fits, with $(field controls) controls and no overlap"
