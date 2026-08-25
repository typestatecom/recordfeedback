# A spoken command is an instruction to this tool, not feedback about the work.
# It was carried out while the session ran, so leaving it in the document asks
# Claude Code to carry it out a second time. It comes out of the transcript and
# is reported on its own.
#
# The speech is real, the transcript is real whisper, and the scrubber is the
# one that ships. What is stood in for is Apple's recogniser, which needs a
# permission no test can grant, so the command log it would have written is
# written here instead.
. "$REPO/test/lib.sh"

export RF_MODEL="$HOME/.recordfeedback/models/ggml-large-v3-turbo-q5_0.bin"
[ -f "$RF_MODEL" ] || skip "the whisper model is not on this machine"

export RF_LANG=en
folder="$RF_CASE_TMP/screenshots"
mkdir -p "$folder"
export RF_SHOT_DIR="$folder"

aiff="$RF_CASE_TMP/said.aiff"
wav="$RF_CASE_TMP/said.wav"
say -v Samantha -o "$aiff" \
  "The login button on this page is far too small. Let's take a screenshot of this area. The spacing under the heading is also wrong."
ffmpeg -v error -y -i "$aiff" -ac 1 -ar 16000 -c:a pcm_s16le "$wav"

session="$RF_CASE_TMP/session"
mkdir -p "$session"
cp "$wav" "$session/audio.wav"
touch "$session/start.ref"
sleep 1
touch "$session/stop.ref"
cat > "$session/meta.json" <<'JSON'
{"started":"2026-08-25T09:00:00Z","cwd":"/tmp","branch":"main","note":"","silent":"false","status":"recording"}
JSON

RF_LANG=en "$RFB" transcribe "$session"
assert_file "$session/transcript.json"

whole="$(jq -r '[.transcription[].text] | join(" ")' "$session/transcript.json")"
echo "heard: $whole"

# The scrubber searches near the moment the command was spoken, so the log has
# to carry the offset the recogniser would have logged. It is taken from the
# segment whisper actually put the sentence in, which is where the recogniser
# reading the same recording would have been.
at="$(jq -r '[.transcription[] | select(.text | ascii_downcase | test("screenshot")) | .offsets.from] | first // empty' \
  "$session/transcript.json")"
[ -n "$at" ] || fail "whisper never transcribed the spoken command. Heard: $whole"

python3 -c "
import json, sys
json.dump([{
    'at': int('$at') / 1000.0,
    'command': 'region',
    'title': 'screenshot a region',
    'phrase': \"let's take a screenshot of this area\",
    'heard': \"let's take a screenshot of this area\",
}], open('$session/commands.json', 'w'))
"

"$RFB" feedback "$session" > "$RF_CASE_TMP/feedback.out" 2>&1 \
  || fail "feedback failed: $(cat "$RF_CASE_TMP/feedback.out")"
assert_file "$session/feedback.md"
doc="$(cat "$session/feedback.md")"
echo "--- feedback.md ---"; echo "$doc"

# Everything before "## Spoken commands" is what a reader takes for feedback.
transcript_part="$(python3 -c "
doc = open('$session/feedback.md').read()
print(doc.split('## Spoken commands')[0])
" | tr '[:upper:]' '[:lower:]')"

# The instruction is gone from the part that reads as feedback.
assert_not_contains "$transcript_part" "screenshot of this area" "the transcript"

# The feedback either side of it survived. Taking a sentence out must not take
# the sentences around it with it.
assert_contains "$transcript_part" "login button" "the transcript"
assert_contains "$transcript_part" "spacing" "the transcript"

# And it survived as it was written. Cutting one sentence out of a paragraph by
# rebuilding the paragraph from its bare words costs every other sentence in it
# its capitals and its punctuation, which is the document a person reads.
kept="$(python3 -c "
doc = open('$session/feedback.md').read()
print(doc.split('## Spoken commands')[0])")"
echo "$kept" | grep -q "The login button" \
  || fail "the sentence before the command lost its capital letter:
$kept"
echo "$kept" | grep -q "too small\." \
  || fail "the sentence before the command lost its full stop:
$kept"

# The command is still on the record, because a session where the tool did
# something has to be readable back.
assert_contains "$doc" "## Spoken commands" "the document"
assert_contains "$doc" "screenshot a region" "the spoken commands section"
assert_contains "$doc" "were taken out of the transcript" "the spoken commands section"

# Whisper decides where its segments end, and whether the command got one of its
# own is not this tool's choice. When it shares a segment with feedback, the
# segment has to be cut and not rebuilt: rebuilding it from its bare words costs
# every other sentence in it its capitals and its punctuation. Driven from a
# written transcript, because the case cannot ask whisper to segment a certain
# way and a defect that only appears on one of its choices is one that ships.
shared="$RF_CASE_TMP/shared"
mkdir -p "$shared"
cp "$session/audio.wav" "$shared/audio.wav"
touch "$shared/start.ref"
sleep 1
touch "$shared/stop.ref"
cp "$session/meta.json" "$shared/meta.json"
cat > "$shared/transcript.json" <<'JSON'
{"transcription":[{"timestamps":{"from":"00:00:00,000","to":"00:00:12,000"},
  "offsets":{"from":0,"to":12000},
  "text":" The login button is far too small. Let's take a screenshot of this area. The spacing is wrong."}]}
JSON
cat > "$shared/commands.json" <<'JSON'
[{"at":5.0,"command":"region","title":"screenshot a region",
  "phrase":"let's take a screenshot of this area","heard":"x"}]
JSON

"$RFB" feedback "$shared" > /dev/null 2>&1 || fail "feedback failed on a shared segment"
kept="$(python3 -c "
doc = open('$shared/feedback.md').read()
print(doc.split('## Spoken commands')[0])")"
echo "--- shared segment ---"; echo "$kept"

lower_kept="$(echo "$kept" | tr '[:upper:]' '[:lower:]')"
assert_not_contains "$lower_kept" "screenshot of this area"   "the command was not cut out of the segment it shared with feedback"
echo "$kept" | grep -q "The login button is far too small\."   || fail "the sentence before the command lost its capital or its full stop:
$kept"
echo "$kept" | grep -q "The spacing is wrong\."   || fail "the sentence after the command lost its capital or its full stop:
$kept"

# A session where nothing was said to the tool carries no such section, because
# a heading explaining an empty list is noise in a document that is read fast.
rm -f "$session/commands.json" "$session/feedback.md"
"$RFB" feedback "$session" > /dev/null 2>&1
plain="$(cat "$session/feedback.md")"
assert_not_contains "$plain" "## Spoken commands" "a session with no spoken commands"
assert_contains "$(echo "$plain" | tr '[:upper:]' '[:lower:]')" "screenshot of this area" \
  "the transcript of a session with no command log"
