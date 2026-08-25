# --voice is a setting and not a flag held for one session, so the settings
# window and the flag cannot disagree about whether the running session is
# listening. The listener lives in the overlay, so asking for one without the
# other has to be said out loud rather than quietly doing nothing.
. "$REPO/test/lib.sh"

export RF_FFMPEG_INPUT="-re $RF_ROOM_TONE -t 60"

# Voice control needs the overlay, because the overlay is what listens. Asking
# for both at once used to start a session that was not listening and said
# nothing about it.
out="$("$RFB" start --voice --no-overlay 2>&1)"
echo "$out"
assert_contains "$out" "no overlay" "start says the session has no overlay"
# Matched on the sentence and not on the word "voice", which also appears in
# the path of the session directory this case runs in.
assert_contains "$out" "voice control needs the overlay" \
  "start must say that voice control cannot listen without the overlay"
"$RFB" abort > /dev/null

settings="$RF_HOME/settings.json"
assert_file "$settings"
assert_eq "$(jq -r '.voice.enabled' "$settings")" "true" "--voice writes the setting"

# The file is where a person goes to see what they can say, so a key that is not
# there is a sentence they never find out about. The CLI writes the whole voice
# block and not only the switch it was asked to change.
assert_eq "$(jq -r '.voice.trigger' "$settings")" "let's" \
  "--voice left the trigger word null in the settings file"
assert_eq "$(jq -r '.voice.escape' "$settings")" "not a command" \
  "--voice left the escape phrase null in the settings file"

# The banner asks the file rather than printing a word from memory, so a
# changed trigger is the one a person is told to say.
python3 - "$settings" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data["voice"]["trigger"] = "computer"
json.dump(data, open(path, "w"))
PY

out="$("$RFB" start --no-overlay 2>&1)"
"$RFB" abort > /dev/null
assert_eq "$(jq -r '.voice.trigger' "$settings")" "computer" \
  "starting a session overwrote the trigger word the user set"

# The file --voice writes on a machine where the overlay has never saved one
# carries a voice block and no shortcuts. The overlay has to honour it. It used
# to drop the whole file on the floor when the shortcuts block was missing,
# which meant --voice on a fresh install turned nothing on and said nothing.
OVERLAY="$(probe_overlay)" \
  || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"
cat > "$settings" <<'JSON'
{"voice":{"enabled":true,"trigger":"computer","escape":"ignore this"}}
JSON
reads="$("$OVERLAY" --check-voice 2>/dev/null | sed -n 's/^enabled //p')"
assert_eq "$reads" "1" \
  "the overlay ignored a settings file that has voice settings and no shortcuts"

# And the shortcuts still fall back to their defaults rather than to nothing,
# because a file with no shortcuts block must not cost the user their stop key.
assert_contains "$("$OVERLAY" --print-keys)" "stop opt-shift-S" \
  "a settings file with no shortcuts block lost the default keys"

# --no-voice turns it off again, and leaves the rest of the block alone.
"$RFB" start --no-voice --no-overlay > /dev/null 2>&1
"$RFB" abort > /dev/null
assert_eq "$(jq -r '.voice.enabled' "$settings")" "false" "--no-voice writes the setting"
assert_eq "$(jq -r '.voice.trigger' "$settings")" "computer" \
  "--no-voice threw away the trigger word the user set"
