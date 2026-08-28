# The join is the whole point of the tool: a picture placed at the second it
# was taken inside a transcript. Driven from a hand written transcript.json
# and shots.json, so it needs no audio at all.
. "$REPO/test/lib.sh"

session="$RF_CASE_TMP/session"
mkdir -p "$session/shots"

cat > "$session/meta.json" <<'JSON'
{"started":"2026-08-24T12:32:00Z","started_local":"2026-08-24T14:32:00+0200",
 "cwd":"/Users/someone/Projects/typestate","branch":"main","note":"",
 "device":"0","lang":"auto","status":"recording"}
JSON

# Three sentences, each its own whisper segment, spread over a minute.
cat > "$session/transcript.json" <<'JSON'
{"result":{"language":"en"},
 "transcription":[
  {"offsets":{"from":0,"to":39000},"timestamps":{"from":"00:00:00,000","to":"00:00:39,000"},
   "text":" So the thing I do not like about the cockpit page is the spacing at the top, it feels loose."},
  {"offsets":{"from":41000,"to":50000},"timestamps":{"from":"00:00:41,000","to":"00:00:50,000"},
   "text":" Look at this, the button is doing the wrong thing here."},
  {"offsets":{"from":52000,"to":60000},"timestamps":{"from":"00:00:52,000","to":"00:01:00,000"},
   "text":" And the same problem is on the flow page."}]}
JSON

# One shot at 00:43, which is inside the second sentence.
: > "$session/shots/01-0043.png"
cat > "$session/shots.json" <<JSON
[{"index":1,"file":"01-0043.png","path":"$session/shots/01-0043.png",
  "offset_ms":43000,"elapsed":"00:43","taken_at":"2026-08-24T12:32:43Z","source":"folder"}]
JSON

touch -t 202608241432.00 "$session/start.ref"
touch -t 202608241433.10 "$session/stop.ref"

"$RFB" feedback "$session"
assert_file "$session/feedback.md"
doc="$(cat "$session/feedback.md")"
echo "--- feedback.md ---"; echo "$doc"

assert_contains "$doc" "# Feedback session" "the document"
assert_contains "$doc" "Duration 1m10s" "the summary line"
assert_contains "$doc" "1 screenshot." "the summary line"
assert_contains "$doc" "Language en" "the summary line"
assert_contains "$doc" "branch \`main\`" "the summary line"
assert_contains "$doc" "## Transcript" "the document"
assert_contains "$doc" "## Screenshots" "the document"

# A coding agent reads an image by path from an unknown working directory.
assert_contains "$doc" "($session/shots/01-0043.png)" "the image link"
assert_not_contains "$doc" "](shots/" "the image link"

# The image belongs after the sentence that was being spoken at 00:43, and
# before the one that had not been said yet. Line order is the assertion.
button_line="$(grep -n 'button is doing the wrong thing' "$session/feedback.md" | head -1 | cut -d: -f1)"
image_line="$(grep -n '^!\[' "$session/feedback.md" | head -1 | cut -d: -f1)"
flow_line="$(grep -n 'same problem is on the flow page' "$session/feedback.md" | head -1 | cut -d: -f1)"
[ -n "$button_line" ] || fail "the second sentence is missing from the transcript"
[ -n "$image_line" ] || fail "the screenshot was never placed in the transcript"
[ -n "$flow_line" ] || fail "the third sentence is missing from the transcript"
[ "$image_line" -gt "$button_line" ] || fail "the image at line $image_line is before the sentence being spoken at line $button_line"
[ "$image_line" -lt "$flow_line" ] || fail "the image at line $image_line is after the sentence spoken later at line $flow_line"

# The screenshot list says what was being said when the shot was taken.
assert_contains "$doc" "01-0043.png" "the screenshot list"
assert_contains "$doc" "taken while saying" "the screenshot list"
tail_section="$(sed -n '/## Screenshots/,$p' "$session/feedback.md")"
assert_contains "$tail_section" "button is doing the wrong thing" "the quote in the screenshot list"

# Whisper segments are a few seconds each. One line per segment is unreadable,
# so segments merge into paragraphs stamped with the offset of the first one.
assert_contains "$doc" "[00:00]" "the first paragraph stamp"

# --- a shot taken before anyone spoke goes at the top --------------------
early="$RF_CASE_TMP/early"
mkdir -p "$early/shots"
cp "$session/meta.json" "$early/meta.json"
# Speech starts at 00:08, so a shot at 00:00 is genuinely before all of it.
# The rule is the last segment at or before the shot, and here there is none.
cat > "$early/transcript.json" <<'JSON'
{"result":{"language":"en"},
 "transcription":[
  {"offsets":{"from":8000,"to":20000},"timestamps":{"from":"00:00:08,000","to":"00:00:20,000"},
   "text":" So the thing I do not like is the spacing at the top, it feels loose."}]}
JSON
: > "$early/shots/01-0000.png"
cat > "$early/shots.json" <<JSON
[{"index":1,"file":"01-0000.png","path":"$early/shots/01-0000.png",
  "offset_ms":0,"elapsed":"00:00","taken_at":"2026-08-24T12:32:00Z","source":"overlay"}]
JSON
touch -t 202608241432.00 "$early/start.ref"
touch -t 202608241433.10 "$early/stop.ref"
"$RFB" feedback "$early"
early_image="$(grep -n '^!\[' "$early/feedback.md" | head -1 | cut -d: -f1)"
early_first="$(grep -n "spacing at the top" "$early/feedback.md" | head -1 | cut -d: -f1)"
[ "$early_image" -lt "$early_first" ] || fail "a shot taken before any speech was not placed at the top"

# --- a long transcript merges into paragraphs, not one line per segment ---
many="$RF_CASE_TMP/many"
mkdir -p "$many/shots"
cp "$session/meta.json" "$many/meta.json"
echo '[]' > "$many/shots.json"
python3 - "$many/transcript.json" <<'PY'
import json, sys
segs = []
for i in range(30):
    segs.append({"offsets": {"from": i * 3000, "to": i * 3000 + 2500},
                 "timestamps": {"from": "", "to": ""},
                 "text": " word%d and some more words here to fill the line out" % i})
json.dump({"result": {"language": "en"}, "transcription": segs}, open(sys.argv[1], "w"))
PY
touch -t 202608241432.00 "$many/start.ref"
touch -t 202608241433.30 "$many/stop.ref"
"$RFB" feedback "$many"
stamps="$(grep -c '^\[[0-9][0-9]:[0-9][0-9]\]' "$many/feedback.md")"
echo "30 segments became $stamps paragraphs"
[ "$stamps" -lt 30 ] || fail "every segment became its own paragraph, nothing was merged"
[ "$stamps" -gt 1 ] || fail "the whole transcript collapsed into one paragraph"
