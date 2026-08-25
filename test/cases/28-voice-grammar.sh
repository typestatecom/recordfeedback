# What the user says, and what this tool decides they meant. A session is
# mostly a person describing a bug, so the expensive mistake is not a command
# that was missed but a sentence about a rectangle that changed the tool.
. "$REPO/test/lib.sh"

OVERLAY="$(probe_overlay)" \
  || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"

session="$RF_HOME/sessions/grammar"
mkdir -p "$session"
touch "$session/start.ref"

heard="$RF_CASE_TMP/heard.txt"
cat > "$heard" <<'SAID'
let's draw
Let's draw.
let us draw
lets draw
let's pick arrow
let's pick rectangle
let's pick highlight
let's pick red
let's pick blue
let's make it bigger
let's make it smaller
let's take a screenshot
let's take a screenshot of this area
let's take a screenshot of an area
let's clear
let's undo
let's hide the marks
let's stop the session
the rectangle in the corner is the wrong colour
I think the arrow should be red here
let's see what happens when I click that
not a command let's draw
not a command, let's take a screenshot of this area
let's draw and let's pick blue
SAID

RF_SESSION="$session" RF_VOICE_HEARD="$heard" RF_OVERLAY_SELFTEST=grammar "$OVERLAY" \
  > "$RF_CASE_TMP/overlay.log" 2>&1 &
overlay_pid=$!
# shellcheck disable=SC2064
trap "kill -TERM $overlay_pid 2>/dev/null || true" EXIT

report="$session/grammar.probe"
waited=0
while [ ! -f "$report" ]; do
  sleep 0.2
  waited=$((waited + 1))
  [ "$waited" -lt 100 ] || fail "the overlay never wrote $report:
$(cat "$RF_CASE_TMP/overlay.log")"
done
trap - EXIT
cat "$report"

# Every command found for one heard sentence, in order, or "none".
got() {
  awk -F'|' -v want="$1" '$2 == want { print $3 }' "$report" | tr '\n' ',' | sed 's/,$//'
}

expect() {
  local sentence="$1" wanted="$2"
  local actual
  actual="$(got "$sentence")"
  [ "$actual" = "$wanted" ] \
    || fail "\"$sentence\" was read as '$actual', expected '$wanted'"
}

# The trigger, in the forms a recogniser writes the same spoken word in.
expect "let's draw" "draw"
expect "Let's draw." "draw"
expect "let us draw" "draw"
expect "lets draw" "draw"

expect "let's pick arrow" "tool-arrow"
expect "let's pick rectangle" "tool-rectangle"
expect "let's pick highlight" "tool-highlighter"
expect "let's pick red" "colour-red"
expect "let's pick blue" "colour-blue"
expect "let's make it bigger" "bigger"
expect "let's make it smaller" "smaller"
expect "let's clear" "clear"
expect "let's undo" "undo"
expect "let's hide the marks" "hide"
expect "let's stop the session" "stop"

# The longer phrase wins. Both of these start with the words of the shorter one,
# and a region shot asked for as a full screen shot is the wrong picture.
expect "let's take a screenshot" "screenshot"
expect "let's take a screenshot of this area" "region"
expect "let's take a screenshot of an area" "region"

# The sentences a session is actually made of. These are the ones that must not
# reach anything: a person describing a rectangle is not asking for one.
expect "the rectangle in the corner is the wrong colour" "none"
expect "I think the arrow should be red here" "none"

# A trigger with nothing this tool knows behind it is the user talking.
expect "let's see what happens when I click that" "none"

# The way to say one of these sentences and mean it literally. Without it there
# is no way to tell this tool what to write down.
expect "not a command let's draw" "none"
expect "not a command, let's take a screenshot of this area" "none"

# A person says two things in one breath and a recogniser hands over the whole
# sentence at once.
expect "let's draw and let's pick blue" "draw,colour-blue"
