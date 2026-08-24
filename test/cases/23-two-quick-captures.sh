# A capture is silent by design, so the second press is what a person does when
# they are not sure the first one worked. Both files have to survive: a
# screenshot that is quietly overwritten is feedback the reader never sees, and
# nothing in the session says it went missing.
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

session="$RF_HOME/sessions/double"
mkdir -p "$session"
touch "$session/start.ref"

RF_SESSION="$session" RF_OVERLAY_SELFTEST=capture-twice "$OVERLAY" \
  > "$RF_CASE_TMP/overlay.log" 2>&1 &
overlay_pid=$!
# shellcheck disable=SC2064
trap "kill -TERM $overlay_pid 2>/dev/null || true" EXIT

report="$session/double.probe"
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

assert_eq "$(field files)" "shot-001.png shot-002.png" \
  "two captures write two files. The name used to be counted off the folder
  inside the delay before screencapture runs, so a second press that landed
  while the first file was still being written counted the same empty folder
  and took the same name. The probe said:
$contents"

assert_eq "$(field shots)" "2" \
  "the count the palette shows agrees with what is on disk, so a person is
  never told they took fewer shots than they did. The probe said:
$contents"

[ -s "$session/inbox/shot-001.png" ] || fail "shot-001.png is empty"
[ -s "$session/inbox/shot-002.png" ] || fail "shot-002.png is empty"

echo "a second press inside the first capture keeps both files"
