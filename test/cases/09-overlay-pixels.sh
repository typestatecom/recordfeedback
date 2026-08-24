# The design rests on one fact: screencapture composites the screen, so an
# overlay window is in the picture and the marks land in the file. If that is
# false the overlay is worthless and the tool has to take the shot a different
# way, so it is proven here and not reasoned about.
. "$REPO/test/lib.sh"

OVERLAY="$(probe_overlay)" \
  || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"

command -v screencapture > /dev/null 2>&1 || skip "no screencapture on this machine"
command -v uv > /dev/null 2>&1 || skip "no uv, so pillow cannot count the pixels"

# A headless runner has no window server, so the whole case is meaningless
# rather than failing.
probe="$RF_CASE_TMP/probe.png"
screencapture -x "$probe" > /dev/null 2>&1 || skip "screencapture cannot run without a screen"
[ -s "$probe" ] || skip "screencapture produced nothing, so there is no screen to test"

count_red() {
  uv run --quiet --with pillow python -c '
import sys
from PIL import Image, ImageChops
image = Image.open(sys.argv[1]).convert("RGB")
r, g, b = image.split()
mask = ImageChops.logical_and(
    ImageChops.logical_and(r.point(lambda v: v > 200, mode="1"),
                           g.point(lambda v: v < 60, mode="1")),
    b.point(lambda v: v < 60, mode="1"))
print(mask.convert("L").histogram()[255])
' "$1"
}

# The screen may already hold something red, so the question is never how much
# red is there but how much the overlay added.
before="$(count_red "$probe")"

session="$RF_HOME/sessions/pixels"
mkdir -p "$session"
touch "$session/start.ref"

RF_SESSION="$session" RF_OVERLAY_SELFTEST=1 "$OVERLAY" \
  > "$RF_CASE_TMP/overlay.log" 2>&1 &
overlay_pid=$!
# shellcheck disable=SC2064
trap "kill -TERM $overlay_pid 2>/dev/null || true" EXIT

waited=0
while [ ! -f "$session/overlay.ready" ]; do
  kill -0 "$overlay_pid" 2>/dev/null || fail "the overlay exited before it was ready:
$(cat "$RF_CASE_TMP/overlay.log")"
  sleep 0.2
  waited=$((waited + 1))
  [ "$waited" -lt 50 ] || fail "the overlay never became ready:
$(cat "$RF_CASE_TMP/overlay.log")"
done
# The window server draws a frame or two after the windows are ordered in.
sleep 1

after_shot="$RF_CASE_TMP/after.png"
screencapture -x "$after_shot" || fail "screencapture failed with the overlay up"
after="$(count_red "$after_shot")"

kill -TERM "$overlay_pid" 2>/dev/null || true

added=$((after - before))
# The stroke is 40 points thick across half the screen, so it is tens of
# thousands of pixels on any real display. A threshold this low still cannot be
# reached by noise, and does not depend on the display's scale.
if [ "$added" -lt 5000 ]; then
  fail "screencapture did not composite the overlay: $before red pixels before, $after after.
  If macOS is refusing Screen Recording to this terminal the shot is only the
  wallpaper. Check System Settings, Privacy and Security, Screen Recording.
  The shot is at $after_shot"
fi

echo "the overlay added $added red pixels to the screenshot"
