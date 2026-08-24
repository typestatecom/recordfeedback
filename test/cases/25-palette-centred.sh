# The row grows leftwards from its right hand end, so that Stop and the capture
# buttons stay under the cursor when draw mode widens it. That anchoring is
# right, but the first position was centred for the narrow row, which left the
# wide one hanging off to the left on every fresh install. Nobody had dragged
# it anywhere: that was simply where it opened.
. "$REPO/test/lib.sh"

OVERLAY="$(probe_overlay)" \
  || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"

session="$RF_HOME/sessions/centred"
mkdir -p "$session"
touch "$session/start.ref"

RF_SESSION="$session" RF_OVERLAY_SELFTEST=poster RF_FRESH_PALETTE=1 "$OVERLAY" \
  > "$RF_CASE_TMP/overlay.log" 2>&1 &
overlay_pid=$!
# shellcheck disable=SC2064
trap "kill -TERM $overlay_pid 2>/dev/null || true" EXIT

report="$session/poster.probe"
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
read -r _ px _ pw _ <<< "$(grep '^palette ' "$report")"
read -r _ sw _ <<< "$(grep '^screen ' "$report")"

centre=$(( px + pw / 2 ))
want=$(( sw / 2 ))
drift=$(( centre - want ))
[ "$drift" -lt 0 ] && drift=$(( -drift ))

# Two points of slack for the odd pixel, and no more. The failure this catches
# was over two hundred.
[ "$drift" -le 2 ] || fail "the row is $drift points off the middle of the screen
  in draw mode, with nobody having moved it. Its centre is $centre and the
  screen's is $want. The probe said:
$contents"

echo "the wide row opens in the middle of the screen"
