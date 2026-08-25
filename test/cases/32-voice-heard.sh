# The whole voice path through the recogniser that ships in macOS: spoken audio
# into the recorder, a command out of Apple's recogniser, the overlay acting on
# it, and the log the transcript is later scrubbed against.
#
# Every other voice case stands in for the recogniser, because recognition needs
# a permission a test cannot grant. This one does not stand in for anything, so
# it skips until the permission exists. It never asks for it: requesting puts a
# system dialog on the screen of whoever is running the suite, and a test suite
# does not get to do that.
. "$REPO/test/lib.sh"

OVERLAY="$(probe_overlay)" \
  || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"

speech="$("$OVERLAY" --check-speech 2>/dev/null || true)"
state="$(printf '%s\n' "$speech" | sed -n 's/^permission //p')"
[ "$state" = granted ] \
  || skip "Speech Recognition is '$state'. Turn it on for this terminal in System Settings, Privacy and Security, Speech Recognition, and this case runs."
[ "$(printf '%s\n' "$speech" | sed -n 's/^on-device //p')" = 1 ] \
  || skip "this machine has no offline recogniser, and recordfeedback will not use the network one"

export RF_LANG=en
export RF_VOICE_LISTEN=1
export RF_OVERLAY_BIN="$OVERLAY"

# Voice control on, before the session starts, through the file both the CLI and
# the overlay read.
mkdir -p "$RF_HOME"
cat > "$RF_HOME/settings.json" <<'JSON'
{"voice":{"enabled":true,"trigger":"let's","escape":"not a command"}}
JSON

# Real speech, built by the macOS synthesiser, so this needs no person and no
# microphone. The command sits between two sentences of ordinary feedback,
# because a recogniser that fires on the feedback either side is the failure
# that matters.
aiff="$RF_CASE_TMP/said.aiff"
spoken="$RF_CASE_TMP/spoken.wav"
wav="$RF_CASE_TMP/said.wav"
say -v Samantha -r 165 -o "$aiff" \
  "The heading is too tight. Let's take a screenshot of this area. The submit button is the wrong colour."
ffmpeg -v error -y -i "$aiff" -ac 1 -ar 16000 -c:a pcm_s16le "$spoken"

# The speech runs about six seconds and the recogniser works a second or so
# behind it, so the fixture carries room tone after it. Without that the
# recorder reaches the end of its input and exits while the case is still
# waiting, and stop would be asking a dead recorder to flush itself.
ffmpeg -v error -y -i "$spoken" \
  -f lavfi -i "anoisesrc=r=16000:c=white:a=0.0005" \
  -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1" \
  -t 40 -ac 1 -ar 16000 -c:a pcm_s16le "$wav"

export RF_FFMPEG_INPUT="-re -i $wav"
out="$("$RFB" start 2>&1)" || fail "start failed: $out"
echo "$out"
session="$(sed -n 's/^  session: //p' <<< "$out")"
[ -n "$session" ] || fail "start printed no session path"

# The command is spoken about three seconds in, and the recogniser is a second
# or so behind the audio it is fed.
commands="$session/commands.json"
waited=0
while [ ! -f "$commands" ] && [ "$waited" -lt 100 ]; do
  sleep 0.2
  waited=$((waited + 1))
done
# One more pass, so a second command heard just after the first is in the file
# before it is counted. Counting too early would pass a bug that fires twice.
sleep 2

"$RFB" stop > "$RF_CASE_TMP/stop.out" 2>&1 || true
echo "--- overlay log ---"; cat "$session/overlay.log" 2>/dev/null

[ -f "$commands" ] \
  || fail "nothing was heard in six seconds of speech carrying one command.
The overlay log is above."
echo "--- commands.json ---"; cat "$commands"

heard="$(jq -r '[.[].command] | join(",")' "$commands")"
case "$heard" in
  *region*) ;;
  *) fail "the spoken command was not heard as a region capture. Got: $heard" ;;
esac

# The feedback either side of it must not have reached anything. A session is
# mostly sentences like these, and a tool that acts on them is worse than one
# that misses a command.
count="$(jq 'length' "$commands")"
[ "$count" -eq 1 ] \
  || fail "one command was spoken and $count were acted on:
$(cat "$commands")"

# It was acted on, not only heard.
shots="$(jq -r '[.[] | select(.command == "region")] | length' "$commands")"
assert_eq "$shots" "1" "the region command was logged once"

# And it is out of the transcript, which is the whole point of logging it.
assert_file "$session/feedback.md"
doc="$(cat "$session/feedback.md")"
echo "--- feedback.md ---"; echo "$doc"
transcript_part="$(python3 -c "
doc = open('$session/feedback.md').read()
print(doc.split('## Spoken commands')[0])" | tr '[:upper:]' '[:lower:]')"
assert_not_contains "$transcript_part" "screenshot of this area" "the transcript"
assert_contains "$transcript_part" "heading" "the feedback before the command survived"
assert_contains "$transcript_part" "button" "the feedback after the command survived"
