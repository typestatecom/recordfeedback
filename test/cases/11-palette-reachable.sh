# In draw mode the mark windows cover every screen and take every click, so the
# palette is the only thing left to press. If a mark window sits in front of it
# the Stop button is unreachable at exactly the moment the user wants out, and
# leaving draw mode must not take the palette off the screen either.
. "$REPO/test/lib.sh"

OVERLAY="$REPO/bin/rf-overlay"

if [ ! -x "$OVERLAY" ]; then
  "$REPO/overlay/build.sh" > "$RF_CASE_TMP/build.log" 2>&1 \
    || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"
fi

probe="$RF_CASE_TMP/probe.png"
screencapture -x "$probe" > /dev/null 2>&1 \
  || skip "screencapture cannot run without a screen"
[ -s "$probe" ] || skip "screencapture produced nothing, so there are no windows to order"

session="$RF_HOME/sessions/palette"
mkdir -p "$session"
touch "$session/start.ref"

RF_SESSION="$session" RF_OVERLAY_SELFTEST=palette "$OVERLAY" \
  > "$RF_CASE_TMP/overlay.log" 2>&1 &
overlay_pid=$!
# shellcheck disable=SC2064
trap "kill -TERM $overlay_pid 2>/dev/null || true" EXIT

report="$session/palette.probe"
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

palette_window="$(field palette)"
hit="$(field hit)"
visible="$(field visible-after-drawing)"
[ -n "$palette_window" ] || fail "the probe named no palette window:
$contents"

assert_eq "$hit" "$palette_window" \
  "the window a click at the centre of the palette lands on while drawing.
  A mark window in front of the palette swallows the Stop button.
  The probe said:
$contents"

assert_eq "$visible" "1" \
  "the palette is still on screen after leaving draw mode.
  The probe said:
$contents"

echo "the palette takes its own clicks while drawing and survives leaving draw mode"
