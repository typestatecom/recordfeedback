# The window that binds the keys is the only part of this tool a user has to
# find on their own, and it was written without ever being opened. A window
# that crashes, comes up empty, or draws its rows outside itself is a tool
# whose shortcuts cannot be changed at all.
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

session="$RF_HOME/sessions/settings"
mkdir -p "$session"
touch "$session/start.ref"

RF_SESSION="$session" RF_OVERLAY_SELFTEST=settings "$OVERLAY" \
  > "$RF_CASE_TMP/overlay.log" 2>&1 &
overlay_pid=$!
# shellcheck disable=SC2064
trap "kill -TERM $overlay_pid 2>/dev/null || true" EXIT

report="$session/settings.probe"
waited=0
while [ ! -f "$report" ]; do
  kill -0 "$overlay_pid" 2>/dev/null || fail "the overlay died opening its own
  settings window:
$(cat "$RF_CASE_TMP/overlay.log")"
  sleep 0.2
  waited=$((waited + 1))
  [ "$waited" -lt 100 ] || fail "the settings window never reported:
$(cat "$RF_CASE_TMP/overlay.log")"
done

kill -TERM "$overlay_pid" 2>/dev/null || true
trap - EXIT

contents="$(cat "$report")"
field() { printf '%s\n' "$contents" | sed -n "s/^$1 //p"; }

assert_eq "$(field opened)" "1" \
  "the settings window opens. The probe said:
$contents"

# Seven actions and a restore button.
[ "$(field buttons)" -eq 8 ] \
  || fail "the settings window has $(field buttons) buttons and there are seven
  shortcuts plus the way back to the defaults. An action with no button is an
  action nobody can rebind. The probe said:
$contents"

assert_contains "$(field titles)" "Restore defaults" \
  "there is a way back to the defaults, since a user who binds a key they
  cannot press has no other way out. The probe said:
$contents"

# The current binding is what each button shows, so the window says what is set
# rather than only taking what is typed.
assert_contains "$(field titles)" "$("$OVERLAY" --print-keys | sed -n 's/^draw //p' \
  | sed 's/opt-shift-/\xe2\x8c\xa5\xe2\x87\xa7/')" \
  "each button shows the shortcut that is currently bound. The probe said:
$contents"

assert_eq "$(field rows-outside)" "0" \
  "every row is inside the window. A row drawn past the bottom is a shortcut
  that exists and cannot be reached. The probe said:
$contents"

# The palette is deliberately above everything else on the screen, and the
# settings window is opened from the palette, so without this it comes up
# underneath the row that opened it.
[ "$(field level)" -gt "$(field palette-level)" ] \
  || fail "the settings window is at level $(field level) and the palette is at
  $(field palette-level), so the row sits on top of the window it opened. The
  palette is at the bottom centre and the window opens in the middle of the
  screen, so what it covers is the last shortcut and the way back to the
  defaults. The probe said:
$contents"

echo "the settings window opens with a control for every shortcut"
