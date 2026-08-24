# A session takes seven key combinations away from every other application on
# the machine for as long as it runs, so which seven is the user's choice. The
# choice lives in one file, and everything that names a key reads it: the
# overlay's own registrations, the row on the screen and the list the CLI
# prints when a session starts.
. "$REPO/test/lib.sh"

OVERLAY="$REPO/bin/rf-overlay"

if [ ! -x "$OVERLAY" ]; then
  "$REPO/overlay/build.sh" > "$RF_CASE_TMP/build.log" 2>&1 \
    || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"
fi

settings="$RF_HOME/settings.json"

# --- with no file at all, the defaults answer.
defaults="$("$OVERLAY" --print-keys)"
assert_eq "$(printf '%s\n' "$defaults" | sed -n 's/^draw //p')" "opt-shift-D" \
  "with no settings file the overlay falls back to its own defaults, so a fresh
  machine has working keys before anything has been saved. It said:
$defaults"

# --- a bound key is reported, and reaches the row on the screen.
mkdir -p "$RF_HOME"
cat > "$settings" <<'JSON'
{
  "shortcuts": {
    "draw":       { "key": "J", "modifiers": ["command", "shift"] },
    "screenshot": { "key": "K", "modifiers": ["control", "option"] },
    "stop":       { "key": "Q", "modifiers": ["command", "option"] }
  }
}
JSON

out="$("$OVERLAY" --print-keys)"
assert_eq "$(printf '%s\n' "$out" | sed -n 's/^draw //p')" "shift-cmd-J" \
  "a shortcut written into $settings is the shortcut the overlay uses. It said:
$out"
assert_eq "$(printf '%s\n' "$out" | sed -n 's/^screenshot //p')" "ctrl-opt-K" \
  "the modifiers are read in the order macOS writes them. It said:
$out"
assert_eq "$(printf '%s\n' "$out" | sed -n 's/^region //p')" "opt-shift-R" \
  "an action the file does not mention keeps its default, so a partial file is
  not a broken one. It said:
$out"

# --- the list the CLI prints is the list the overlay registered.
if [ -x "$RFB" ]; then
  banner="$("$RFB" start 2>/dev/null)" || banner=""
  if [ -n "$banner" ]; then
    assert_contains "$banner" "shift-cmd-J" \
      "start prints the keys that are actually bound, not a copy written into
  the shell script"
    "$RFB" abort > /dev/null 2>&1 || true
  fi
fi

# --- a binding with no modifier is refused.
cat > "$settings" <<'JSON'
{ "shortcuts": { "draw": { "key": "J", "modifiers": [] } } }
JSON
out="$("$OVERLAY" --print-keys)"
assert_eq "$(printf '%s\n' "$out" | sed -n 's/^draw //p')" "opt-shift-D" \
  "a shortcut with no modifier is refused and the default kept. A bare letter
  registered globally is that letter taken away from every application on the
  machine, including the editor the user is talking about. It said:
$out"

# --- a key the overlay cannot name is refused rather than half applied.
cat > "$settings" <<'JSON'
{ "shortcuts": { "draw": { "key": "F13", "modifiers": ["option"] } } }
JSON
out="$("$OVERLAY" --print-keys)"
assert_eq "$(printf '%s\n' "$out" | sed -n 's/^draw //p')" "opt-shift-D" \
  "a key outside the set the settings window can record is refused, so the
  file can never name a key the overlay would fail to register. It said:
$out"

# --- a file that is not JSON at all leaves a working set of keys.
printf 'this is not json\n' > "$settings"
out="$("$OVERLAY" --print-keys)"
assert_eq "$(printf '%s\n' "$out" | sed -n 's/^stop //p')" "opt-shift-S" \
  "a settings file that cannot be parsed leaves every default in place. The
  user is mid session and a broken file must not cost them the stop key. It
  said:
$out"

echo "the shortcuts come from one file, and a broken one costs nothing"
