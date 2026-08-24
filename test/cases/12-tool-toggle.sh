# Picking a tool is the control the user finds first, so it has to be the way
# out as well. Pressing the tool that is already on leaves draw mode, and until
# it does the overlay keeps the screen and there is no obvious way back.
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

session="$RF_HOME/sessions/tools"
mkdir -p "$session"
touch "$session/start.ref"

RF_SESSION="$session" RF_OVERLAY_SELFTEST=tools "$OVERLAY" \
  > "$RF_CASE_TMP/overlay.log" 2>&1 &
overlay_pid=$!
# shellcheck disable=SC2064
trap "kill -TERM $overlay_pid 2>/dev/null || true" EXIT

report="$session/tools.probe"
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

assert_eq "$(field after-pick)" "1 pen" \
  "picking the pen turns drawing on and selects it. The probe said:
$contents"

assert_eq "$(field after-pick-again)" "0" \
  "picking the pen a second time leaves draw mode.
  Without this the only way out is a key the palette never names, and the
  overlay holds every click on the screen. The probe said:
$contents"

assert_eq "$(field after-switch)" "1 arrow" \
  "picking a different tool switches to it and stays in draw mode. The probe said:
$contents"

assert_eq "$(field after-second-switch)" "1 rectangle" \
  "switching again stays in draw mode rather than toggling off. The probe said:
$contents"

assert_eq "$(field after-second-switch-again)" "0" \
  "the toggle works for every tool, not only the first one. The probe said:
$contents"

echo "a tool that is already on is the way back out of draw mode"
