# The recorder listens to the input macOS is set to listen to, and never to
# whichever one happens to be first in a list.
#
# This is the failure that started all of this. An avfoundation index is not
# stable: it shifts when a device is plugged in, and on this machine a pair of
# AirPods connecting moved the built in microphone from index 0 to index 1 and
# put a virtual mixer routed to nothing in its place. A session recorded through
# that mixer is a file of zeros, and index 0 was the default.
. "$REPO/test/lib.sh"

command -v system_profiler > /dev/null 2>&1 \
  || skip "system_profiler is not on this machine, so there is no default input to compare against"

# The input macOS itself is set to use.
wanted="$(system_profiler SPAudioDataType 2>/dev/null \
  | awk '/^        [A-Za-z].*:$/{ name = $0 } /Default Input Device: Yes/{ print name; exit }' \
  | sed 's/^ *//; s/:$//')"
[ -n "$wanted" ] || skip "this machine reports no default input device"
echo "macOS default input: $wanted"

listing="$("$RFB" devices 2>&1)"
echo "$listing"
case "$listing" in
  *"$wanted"*) ;;
  *) skip "the default input '$wanted' is not an avfoundation input, so there is nothing to match" ;;
esac

# What the tool would record from, asked of the tool and not worked out here a
# second time.
index="$("$RFB" input-index)"
echo "recordfeedback would record from index: $index"
case "$index" in
  ''|*[!0-9]*) fail "input-index printed '$index', which is not an index" ;;
esac

# The marker devices puts beside the chosen line is part of the listing and not
# part of the name.
chosen="$(printf '%s\n' "$listing" | sed -n "s/^\[$index\] //p" \
  | sed 's/  *<- .*$//')"
[ -n "$chosen" ] || fail "index $index is not in the list of inputs:
$listing"
assert_eq "$chosen" "$wanted" \
  "the tool would record from '$chosen' while macOS is set to record from
  '$wanted'. An index is not a device, and this is exactly how a session gets
  recorded through a virtual mixer that is routed to nothing."

# An index the user asked for is theirs and is not second guessed.
assert_eq "$(RF_DEVICE=2 "$RFB" input-index)" "2" \
  "RF_DEVICE was overridden by the default input"
assert_eq "$("$RFB" input-index --device 3)" "3" \
  "--device was overridden by the default input"
