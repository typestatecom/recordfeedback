# Screenshot collection takes what was captured inside the session window,
# ignores what was not, names the copies with the right elapsed times, and
# leaves the screenshot folder without the shots it took.
. "$REPO/test/lib.sh"

folder="$RF_CASE_TMP/screenshots"
session="$RF_CASE_TMP/session"
mkdir -p "$folder" "$session/shots" "$session/inbox"
export RF_SHOT_DIR="$folder"

png() { ffmpeg -v error -y -f lavfi -i "color=c=$2:s=32x32" -frames:v 1 "$1"; }

# A real screencapture is what the tool actually has to collect, so use one
# where the screen allows it and say so when it does not.
if screencapture -x "$folder/during-1.png" 2>/dev/null && [ -s "$folder/during-1.png" ]; then
  echo "during-1.png came from screencapture -x"
else
  png "$folder/during-1.png" red
  echo "screencapture is unavailable, during-1.png was generated instead"
fi
png "$folder/during-2.png" green
png "$folder/before.png" blue
png "$folder/after.png" white
png "$session/inbox/rf-1.png" orange

# Fix the whole timeline by hand so the expected names are exact.
base="202608241200"
touch -t "$base.00" "$session/start.ref"
touch -t "$base.43" "$folder/during-1.png"    # 00:43
touch -t "202608241201.10" "$session/inbox/rf-1.png"   # 01:10
touch -t "202608241201.32" "$folder/during-2.png"      # 01:32
touch -t "202608241159.00" "$folder/before.png"        # a minute before the session
touch -t "202608241203.00" "$folder/after.png"         # a minute after it ended
touch -t "202608241202.00" "$session/stop.ref"

"$RFB" collect "$session"

assert_file "$session/shots.json"
ls -l "$session/shots"

for name in 01-0043.png 02-0110.png 03-0132.png; do
  assert_file "$session/shots/$name"
done
count="$(ls "$session/shots" | wc -l | tr -d ' ')"
assert_eq "$count" "3" "number of collected screenshots"

# Nothing outside the window may be collected.
[ -f "$session/shots/00-0000.png" ] && fail "a screenshot from before the session was collected"
ls "$session/shots" | grep -q '04-' && fail "a screenshot from after the session was collected"

# The session archive keeps the shots, the screenshot folder does not.
[ -f "$folder/during-1.png" ] && fail "during-1.png was left in the screenshot folder"
[ -f "$folder/during-2.png" ] && fail "during-2.png was left in the screenshot folder"
assert_file "$folder/before.png"
assert_file "$folder/after.png"

echo "--- shots.json ---"; jq . "$session/shots.json"

assert_eq "$(jq '. | length' "$session/shots.json")" "3" "records in shots.json"
assert_eq "$(jq -r '.[0].offset_ms' "$session/shots.json")" "43000" "first offset"
assert_eq "$(jq -r '.[1].offset_ms' "$session/shots.json")" "70000" "second offset"
assert_eq "$(jq -r '.[2].offset_ms' "$session/shots.json")" "92000" "third offset"
assert_eq "$(jq -r '.[0].elapsed' "$session/shots.json")" "00:43" "first elapsed"
assert_eq "$(jq -r '.[1].elapsed' "$session/shots.json")" "01:10" "second elapsed"

# Claude Code reads an image by path from an unknown working directory, so
# every path in shots.json has to be absolute.
jq -r '.[].path' "$session/shots.json" | while read -r p; do
  case "$p" in
    /*) [ -f "$p" ] || fail "shots.json points at a missing file: $p" ;;
    *) fail "shots.json holds a relative path: $p" ;;
  esac
done

# The shot the overlay captured straight into the session is recorded as such,
# because it never went near the screenshot folder.
assert_eq "$(jq -r '.[1].source' "$session/shots.json")" "overlay" "the inbox shot's source"
assert_eq "$(jq -r '.[0].source' "$session/shots.json")" "folder" "the folder shot's source"

# RF_KEEP_SHOTS leaves the originals where they were.
session2="$RF_CASE_TMP/session2"
mkdir -p "$session2/shots" "$session2/inbox"
png "$folder/keep-me.png" red
touch -t "$base.00" "$session2/start.ref"
touch -t "$base.30" "$folder/keep-me.png"
touch -t "202608241202.00" "$session2/stop.ref"
RF_KEEP_SHOTS=1 "$RFB" collect "$session2"
assert_file "$folder/keep-me.png"
assert_file "$session2/shots/01-0030.png"
