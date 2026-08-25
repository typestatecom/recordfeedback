# The width is the one control with a range rather than a state, and it is
# reached from two places, the bracket keys and the two buttons in the palette,
# which now share a step. This holds the range either of them can cover: a few
# presses have to make a visible difference, and both ends have to be reachable.
. "$REPO/test/lib.sh"

OVERLAY="$(probe_overlay)" \
  || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"

needs_screen

session="$RF_HOME/sessions/width"
mkdir -p "$session"
touch "$session/start.ref"

RF_SESSION="$session" RF_OVERLAY_SELFTEST=width "$OVERLAY" \
  > "$RF_CASE_TMP/overlay.log" 2>&1 &
overlay_pid=$!
# shellcheck disable=SC2064
trap "kill -TERM $overlay_pid 2>/dev/null || true" EXIT

report="$session/width.probe"
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

start="$(field start)"
after="$(field after-three)"

[ "$after" -ge "$((start * 2))" ] \
  || fail "three presses of the thicker key took the pen from $start to $after.
  A step the eye cannot see is a control the user presses twice and gives up
  on. The probe said:
$contents"

[ "$(field top)" -ge 60 ] \
  || fail "holding the thicker key stops at $(field top), which is not a wide
  enough mark to circle a window with. The probe said:
$contents"

[ "$(field bottom)" -ge 1 ] \
  || fail "the width fell to $(field bottom), and a mark narrower than one
  point draws nothing at all. The probe said:
$contents"

[ "$(field bottom)" -le 4 ] \
  || fail "holding the thinner key stops at $(field bottom), so the fine end of
  the range cannot be reached. The probe said:
$contents"

echo "three presses take the width from $start to $after, topping out at $(field top)"
