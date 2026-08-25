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
let's take screenshot of this area
let's take a screenshot of area
lets pick the arrow
not command let's draw
let's pick
let's take a screenshot of
let's take a screenshot and then I will explain
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

# A recogniser drops articles. This machine's own recogniser heard "let's take
# screenshot of this area" for a fixture that said "take a screenshot of this
# area", and an exact match on the words let the command through untouched.
# Articles carry nothing here, so they are not what a command turns on.
expect "let's take screenshot of this area" "region"
expect "let's take a screenshot of area" "region"
expect "lets pick the arrow" "tool-arrow"

# The escape has to survive the same treatment, or the one way to say these
# sentences literally stops working the moment a recogniser drops a word.
expect "not command let's draw" "none"

# A recogniser builds its sentence a word at a time and hands over each version
# of it, so a command that is the beginning of a longer one is only half heard
# until the rest arrives. Acting on the short one takes the wrong picture, so
# the match says whether it could still grow and the caller waits.
grew() { awk -F'|' -v want="$1" '$2 == want { print $5 }' "$report" | tail -n 1; }
assert_eq "$(grew "let's take a screenshot")" "grows" \
  "\"let's take a screenshot\" is the whole of \"let's take a screenshot of this
  area\" until the rest of it arrives, and it has to say so"
assert_eq "$(grew "let's take a screenshot of this area")" "final" \
  "the whole phrase cannot grow any further and waiting on it would lose it"

# A command nothing extends is acted on the moment it is heard, or every one of
# them waits for a recogniser to decide the sentence is over.
assert_eq "$(grew "let's draw")" "final" \
  "\"let's draw\" is nothing's beginning and must not be held back"

# Half a word into a command is not a command. A recogniser hands over its
# sentence as it builds it, and this is what most of those handovers look like.
expect "let's pick" "none"

# One word further in is still the longer phrase arriving and not the sentence
# moving on. This is the handover that fired the wrong command: the short match
# no longer sat at the end of the sentence, so it stopped being held back.
assert_eq "$(grew "let's take a screenshot of")" "grows" \
  "\"of\" is the next word of \"of this area\" and not the start of a new thought"

# And once the words stop agreeing with the longer phrase, the user said the
# short one and went on. Holding it back any longer loses it.
expect "let's take a screenshot and then I will explain" "screenshot"
assert_eq "$(grew "let's take a screenshot and then I will explain")" "final" \
  "the sentence moved on, so the screenshot has to be taken"
