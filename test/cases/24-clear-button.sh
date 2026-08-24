# Clearing is bound to a key and nothing on the screen says so, which is how the
# person who wrote the tool ended up hunting for it in their own palette. Every
# other way out of a mistake is a control, and this one has to be too.
. "$REPO/test/lib.sh"

OVERLAY="$(probe_overlay)" \
  || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"

session="$RF_HOME/sessions/clear"
mkdir -p "$session"
touch "$session/start.ref"

RF_SESSION="$session" RF_OVERLAY_SELFTEST=clearbutton "$OVERLAY" \
  > "$RF_CASE_TMP/overlay.log" 2>&1 &
overlay_pid=$!
# shellcheck disable=SC2064
trap "kill -TERM $overlay_pid 2>/dev/null || true" EXIT

report="$session/clear.probe"
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

assert_eq "$(field named)" "1" \
  "draw mode carries a control named clear. Without it the only way to take a
  drawing back is a key combination that appears nowhere on the screen. The
  probe said:
$contents"

assert_eq "$(field shapes-before)" "1" \
  "the probe drew something to clear. The probe said:
$contents"

assert_eq "$(field shapes-after)" "0" \
  "pressing clear takes the marks off the screen, rather than only looking as
  though it would. The probe said:
$contents"

echo "clear is a button and it clears"
