# What a person says to reach a command is their own turn of phrase, so the
# phrases are a list they edit. The list is edited in one place, saved in
# another and matched in a third, and a phrase that reaches the file but not the
# grammar is a setting that lies to the person who set it.
. "$REPO/test/lib.sh"

OVERLAY="$(probe_overlay)" \
  || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"

needs_screen

session="$RF_HOME/sessions/voice"
mkdir -p "$session"
touch "$session/start.ref"

RF_SESSION="$session" RF_OVERLAY_SELFTEST=voice-settings "$OVERLAY" \
  > "$RF_CASE_TMP/overlay.log" 2>&1 &
overlay_pid=$!
# shellcheck disable=SC2064
trap "kill -TERM $overlay_pid 2>/dev/null || true" EXIT

report="$session/voice.probe"
waited=0
while [ ! -f "$report" ]; do
  kill -0 "$overlay_pid" 2>/dev/null || fail "the overlay died in its settings window:
$(cat "$RF_CASE_TMP/overlay.log")"
  sleep 0.2
  waited=$((waited + 1))
  [ "$waited" -lt 100 ] || fail "the settings window never reported:
$(cat "$RF_CASE_TMP/overlay.log")"
done

kill -TERM "$overlay_pid" 2>/dev/null || true
trap - EXIT

contents="$(cat "$report")"
echo "$contents"
field() { printf '%s\n' "$contents" | sed -n "s/^$1 //p"; }

assert_contains "$(field tabs)" "Voice" "the settings window has a voice tab"

# The window picks a command when it opens, and the editor has to be showing
# that command's phrases. Empty reads as a command with no phrases, and what a
# person does about that is type one in and lose the rest.
[ "$(field editor-lines)" -ge 2 ] \
  || fail "the phrase editor shows $(field editor-lines) lines for the command the
  window selected when it opened, and that command has several phrases"
assert_eq "$(field enabled)" "1" "turning voice control on did not take"
assert_eq "$(field trigger)" "computer" "the trigger word did not take"

# An empty trigger would make every phrase in the table a command, so "the
# rectangle is wrong" would change the tool twice. The one in force stands.
assert_eq "$(field trigger-after-empty)" "computer" \
  "an empty trigger word was accepted, which arms every phrase on ordinary speech"

# A phrase typed into the window reaches the grammar that matches speech.
assert_eq "$(field added)" "tool-arrow" "a phrase added in settings does not work"
assert_eq "$(field added-second)" "tool-arrow" \
  "only the first of several phrases for one command works"

# Editing the list replaces it. A list that silently keeps the author's phrases
# alongside the user's is one they cannot take a phrase out of.
assert_eq "$(field replaced)" "none" \
  "a phrase the user removed still reaches the command"
assert_eq "$(field old-trigger)" "none" \
  "the old trigger word still fires after it was changed"

# The escape works against a changed trigger too, and is not wired to the
# default one.
assert_eq "$(field escaped)" "none" \
  "the escape phrase does not hold against a changed trigger word"

# The CLI reads this file to decide what to print at the start of a session, and
# the next session reads it to know what can be said.
assert_eq "$(field saved-phrase)" "1" "the phrase was not written to settings.json"
assert_eq "$(field saved-enabled)" "1" "voice being on was not written to settings.json"

# The CLI has to agree with the file the overlay wrote.
settings="$RF_HOME/settings.json"
assert_file "$settings"
assert_eq "$(jq -r '.voice.enabled' "$settings")" "true" "the CLI reads voice.enabled"
assert_eq "$(jq -r '.voice.trigger' "$settings")" "computer" "the CLI reads voice.trigger"
assert_eq "$(jq -r '.voice.phrases["tool-arrow"] | length' "$settings")" "2" \
  "the CLI reads the phrase list"

# The shortcuts are in the same file, and a voice setting that flattened them
# would cost the user their stop key mid session.
assert_eq "$(jq -r '.shortcuts.stop.key' "$settings")" "S" \
  "writing a voice setting lost the shortcuts"
