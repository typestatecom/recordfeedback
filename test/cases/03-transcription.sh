# Speech in, words out. The fixture is built by the macOS speech synthesiser,
# so this needs no person and no microphone, and it is the only honest end to
# end check of the speech half.
. "$REPO/test/lib.sh"

export RF_MODEL="$HOME/.recordfeedback/models/ggml-large-v3-turbo-q5_0.bin"
[ -f "$RF_MODEL" ] || skip "the whisper model is not on this machine"

sentence="The button on the cockpit page is misaligned"
aiff="$RF_CASE_TMP/fixture.aiff"
wav="$RF_CASE_TMP/fixture.wav"

say -v Samantha -o "$aiff" "$sentence"
assert_file "$aiff"
ffmpeg -v error -y -i "$aiff" -ac 1 -ar 16000 -c:a pcm_s16le "$wav"
assert_file "$wav"

# Transcribe through the CLI, so the test covers the code that ships and not a
# hand written whisper-cli line.
session="$RF_CASE_TMP/session"
mkdir -p "$session/shots"
cp "$wav" "$session/audio.wav"
touch "$session/start.ref"

RF_LANG=en "$RFB" transcribe "$session"

assert_file "$session/transcript.json"
assert_file "$session/transcript.txt"

text="$(jq -r '[.transcription[].text] | join(" ")' "$session/transcript.json" | tr '[:upper:]' '[:lower:]')"
echo "heard: $text"

case "$text" in
  *cockpit*) ;;
  *) fail "the transcript does not contain 'cockpit'. Heard: $text" ;;
esac
case "$text" in
  *misaligned*) ;;
  *) fail "the transcript does not contain 'misaligned'. Heard: $text" ;;
esac

# offsets.from is what the whole screenshot join depends on, so prove it is
# there and is a number of milliseconds and not a formatted string.
first_offset="$(jq -r '.transcription[0].offsets.from' "$session/transcript.json")"
case "$first_offset" in
  ''|*[!0-9]*) fail "offsets.from is not a plain integer: '$first_offset'" ;;
esac

plain="$(tr '[:upper:]' '[:lower:]' < "$session/transcript.txt")"
assert_contains "$plain" "cockpit" "transcript.txt"

# A real session is several sentences long, and the merge depends on each
# segment carrying its own offset. Prove whisper segments the speech and that
# the offsets rise with the audio.
long_aiff="$RF_CASE_TMP/long.aiff"
long_session="$RF_CASE_TMP/long"
mkdir -p "$long_session"
say -v Samantha -o "$long_aiff" \
  "So the thing I do not like about the cockpit page is the spacing at the top, it feels loose. Look at this, the button is doing the wrong thing here. And the same problem is on the flow page."
ffmpeg -v error -y -i "$long_aiff" -ac 1 -ar 16000 -c:a pcm_s16le "$long_session/audio.wav"

RF_LANG=en "$RFB" transcribe "$long_session"

count="$(jq '.transcription | length' "$long_session/transcript.json")"
[ "$count" -ge 3 ] || fail "expected several segments from three sentences, got $count"

jq -r '.transcription[] | "\(.offsets.from) \(.offsets.to)"' "$long_session/transcript.json" \
  | python3 -c "
import sys
prev = -1
for n, line in enumerate(sys.stdin):
    a, b = (int(x) for x in line.split())
    if a < prev:
        raise SystemExit('segment %d starts at %dms, before the previous segment ended at %dms' % (n, a, prev))
    if b < a:
        raise SystemExit('segment %d ends at %dms before it starts at %dms' % (n, b, a))
    prev = a
print('offsets rise across every segment')
"

long_text="$(jq -r '[.transcription[].text] | join(" ")' "$long_session/transcript.json" | tr '[:upper:]' '[:lower:]')"
echo "heard: $long_text"
for word in cockpit spacing button flow; do
  case "$long_text" in
    *"$word"*) ;;
    *) fail "the long transcript is missing '$word'. Heard: $long_text" ;;
  esac
done
