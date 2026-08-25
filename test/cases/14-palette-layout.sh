# The row carries two layouts: the clock, the way into draw mode, the capture
# buttons and Stop while the user is talking, and the whole tray of tools,
# colours and widths while the pen is down. Draw mode is entered by clicking a
# control in this row, so every control that exists in both layouts has to sit
# at the same place on the screen in both, or it moves out from under the
# cursor that started it. None of that is visible from the source, so it is
# read out of a real palette instead.
. "$REPO/test/lib.sh"

OVERLAY="$(probe_overlay)" \
  || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"

needs_screen

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

contents="$(cat "$report")"
field() { printf '%s\n' "$contents" | sed -n "s/^$1 //p"; }

for state in idle drawing; do
  assert_eq "$(field "$state-overlaps")" "0" \
    "no two controls overlap in the $state row. The probe said:
$contents"

  assert_eq "$(field "$state-outside")" "0" \
    "every control is inside the window in the $state row. A control past the
  end of the window is drawn but can never be clicked. The probe said:
$contents"

  assert_eq "$(field "$state-hint-overlaps")" "0" \
    "no two key hints in the $state row run into each other. The hints are
  drawn under the controls rather than inside them, so a hint wider than the
  control it belongs to collides with its neighbour and neither can be read.
  The probe said:
$contents"

  assert_eq "$(field "$state-untipped")" "0" \
    "every control in the $state row names itself when the pointer rests on it.
  The keys are the whole point of this tool and a control that never says
  which key reaches it is a control the user has to be told about. The probe
  said:
$contents"
done

# Stop, the two capture buttons and the shot count exist in both rows.
for control in stop camera region shots settings; do
  assert_eq "$(field "idle-at-$control")" "$(field "drawing-at-$control")" \
    "the $control control sits at the same place on the screen whether the pen
  is down or not. Draw mode is entered by clicking in this row, so a control
  that moves as it starts moves out from under the cursor that started it, and
  Stop moving is a click that draws a mark instead of ending the session. The
  probe said:
$contents"
done

[ "$(field idle-controls)" -lt "$(field drawing-controls)" ] \
  || fail "the idle row carries $(field idle-controls) controls and the drawing
  row $(field drawing-controls). The tools, the colours and the width belong to
  draw mode, and holding them on the screen for a whole session puts them over
  the work the user is talking about. The probe said:
$contents"

[ "$(field idle-window)" -lt "$(field drawing-window)" ] \
  || fail "the window is $(field idle-window) wide idle and
  $(field drawing-window) drawing, so it is not giving the screen back while
  the user is talking. The probe said:
$contents"

assert_contains "$(field tips)" "$("$OVERLAY" --print-keys | sed -n 's/^screenshot //p')" \
  "the capture button names the key the overlay actually registered, not a
  copy of it written into the row. The probe said:
$contents"

assert_eq "$(field status-placed)" "1" \
  "the overlay puts an item in the menu bar. It is the one place a full screen
  application cannot cover and an unplugged display cannot take away, so it is
  the way back to a session whose palette has become unreachable. The probe
  said:
$contents"

[ "$(field status-menu)" -ge 8 ] \
  || fail "the menu bar item carries $(field status-menu) menu entries, and it
  has to carry the tools, the settings, Stop and the way out of a stuck
  overlay. The probe said:
$contents"

# A menu bar item that macOS placed in the notch is drawn, clickable and
# invisible, which is worse than one that was refused. Whichever happened, the
# tool has to say so rather than leave the user looking for it.
if [ "$(field status-behind-notch)" = "1" ]; then
  # The overlay measures its own item half a second after its windows are up,
  # which is after this probe has already reported, so the warning is waited for
  # rather than assumed to have been written. The CLI waits for the same reason
  # and says so where it does it.
  waited=0
  while [ "$waited" -lt 40 ]; do
    grep -q "behind this display's notch" "$RF_CASE_TMP/overlay.log" 2>/dev/null && break
    sleep 0.1
    waited=$((waited + 1))
  done
  assert_contains "$(cat "$RF_CASE_TMP/overlay.log")" "behind this display's notch" \
    "the overlay says so when its indicator lands behind the notch. The menu
  bar on this machine is full: $(field notch) is the hole and the item is at
  $(field status-x)"
fi

kill -TERM "$overlay_pid" 2>/dev/null || true
trap - EXIT

echo "both rows fit, and the controls they share do not move between them"
