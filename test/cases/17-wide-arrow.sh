# Everything about the arrow is drawn relative to its width, and the width is
# usually small. At the wide end the shaft's round cap bulges out past the point
# of the arrow, and on a short drag the head is longer than the arrow it belongs
# to and runs backwards out of its own tail.
. "$REPO/test/lib.sh"

OVERLAY="$REPO/bin/rf-overlay"

if [ ! -x "$OVERLAY" ]; then
  "$REPO/overlay/build.sh" > "$RF_CASE_TMP/build.log" 2>&1 \
    || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"
fi

session="$RF_HOME/sessions/arrow"
mkdir -p "$session"
touch "$session/start.ref"

RF_SESSION="$session" RF_OVERLAY_SELFTEST=arrow "$OVERLAY" \
  > "$RF_CASE_TMP/overlay.log" 2>&1 &
overlay_pid=$!
# shellcheck disable=SC2064
trap "kill -TERM $overlay_pid 2>/dev/null || true" EXIT

report="$session/arrow.probe"
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

assert_eq "$(field wide-beyond-tip)" "0" \
  "a wide arrow puts no ink past the point it was dragged to. The shaft is
  stroked with a round cap, and half a width of that cap sits beyond the tip,
  which at a wide setting is a blob on the end of the arrow. The probe said:
$contents"

assert_eq "$(field short-behind-start)" "0" \
  "a short wide arrow stays between the two points it was dragged between. The
  head is sized from the width alone, so on a short drag it is longer than the
  arrow and runs out through the tail. The probe said:
$contents"

# The head is sized from the width and has to be cut down to fit a short drag.
# Cut too far and the arrow loses the head instead of the overhang.
[ "$(field short-max-half)" -gt "$(field short-shaft-half)" ] \
  || fail "the head of a short wide arrow reaches $(field short-max-half) from
  the line and its shaft reaches $(field short-shaft-half), so there is no head
  left to see. The probe said:
$contents"

echo "a wide arrow keeps its ink between its own two ends"
