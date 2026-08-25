# Voice control has to be startable and stoppable in the middle of a session
# without opening a window. The user's hands are off the keyboard and their eyes
# are on their own work, so it is a key and a control in the row, the same as
# every other thing this tool does.
. "$REPO/test/lib.sh"

OVERLAY="$(probe_overlay)" \
  || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"

# The key is bindable like every other one, and it is named in the list the CLI
# prints, since two copies of that list is one that goes stale.
keys="$("$OVERLAY" --print-keys)"
echo "$keys"
assert_contains "$keys" "listen " "there is a key for starting and stopping listening"

needs_screen

session="$RF_HOME/sessions/toggle"
mkdir -p "$session/levels"
touch "$session/start.ref"

# Off to begin with, which is the shipped default.
mkdir -p "$RF_HOME"
cat > "$RF_HOME/settings.json" <<'JSON'
{"voice":{"enabled":false,"trigger":"let's","escape":"not a command"}}
JSON

RF_SESSION="$session" RF_OVERLAY_SELFTEST=voice-toggle "$OVERLAY" \
  > "$RF_CASE_TMP/overlay.log" 2>&1 &
overlay_pid=$!
# shellcheck disable=SC2064
trap "kill -TERM $overlay_pid 2>/dev/null || true" EXIT

report="$session/toggle.probe"
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
echo "$contents"
field() { printf '%s\n' "$contents" | sed -n "s/^$1 //p"; }

# The row says whether anything is listening, in both states. A control that
# only appears in one of them is one the user cannot find in the other.
assert_eq "$(field control-off)" "1" \
  "the palette has no listening control while voice control is off"
assert_eq "$(field control-on)" "1" \
  "the palette has no listening control while voice control is on"

# The key turns it on and off, and the answer is the same fact the settings
# window shows, not a second one that can disagree with it.
assert_eq "$(field enabled-start)" "0" "voice control was not off to begin with"
assert_eq "$(field enabled-after-on)" "1" "the key did not turn listening on"
assert_eq "$(field enabled-after-off)" "0" "the key did not turn listening off again"

# Turning it off has to stop the listener and not merely write a setting.
assert_eq "$(field listener-after-off)" "0" \
  "the listener was still running after listening was turned off"

# It survives to the next session, because the settings window shows a switch
# and a switch that reads on while nothing is listening is a window that lies.
assert_eq "$(field saved)" "0" "the state the key left was not written to the file"

# Saying so is the only way a user knows. The row names the state in words.
assert_contains "$(field label-off)" "off" \
  "the palette does not say that listening is off"
