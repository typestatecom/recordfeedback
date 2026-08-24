#!/usr/bin/env bash
# Rebuilds the README shots. Takes over the screen for about half a minute.
#
# The page in the shot is loaded in a Chrome started on a throwaway profile, so
# it is signed out and carries no bookmarks, no extensions and nobody's account.
# A shot of a signed in browser would publish whoever took it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUT="$HERE"
SITE="${RF_SHOT_SITE:-https://github.com}"
CHROME="${RF_CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

for tool in swiftc screencapture uv; do
  command -v "$tool" > /dev/null 2>&1 || {
    echo "docs/screenshots/make.sh: $tool is not installed." >&2
    echo "  command: $tool" >&2
    echo "  fix: install the Xcode command line tools with: xcode-select --install" >&2
    exit 1
  }
done
[ -x "$CHROME" ] || {
  echo "docs/screenshots/make.sh: no Chrome at $CHROME." >&2
  echo "  fix: install Google Chrome, or set RF_CHROME to the binary inside another one." >&2
  exit 1
}

work="$(mktemp -d -t rf-shots)"
chrome_pid=""
overlay_pid=""
cleanup() {
  [ -n "$overlay_pid" ] && kill -TERM "$overlay_pid" 2>/dev/null || true
  [ -n "$chrome_pid" ] && kill -TERM "$chrome_pid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

echo "building the overlay with its probes"
"$REPO/overlay/build.sh" --probes > "$work/build.log" 2>&1 \
  || { echo "the overlay would not build:"; sed 's/^/  /' "$work/build.log"; exit 1; }

# One overlay run per shot, because the palette wears a different row in each.
shoot() {
  local name="$1" quiet="$2"
  local session="$work/$name"
  mkdir -p "$session"
  RF_SESSION="$session" RF_OVERLAY_SELFTEST=poster RF_POSTER_QUIET="$quiet" \
    "$REPO/bin/rf-overlay-probe" > "$work/$name.log" 2>&1 & overlay_pid=$!

  local waited=0
  while [ ! -f "$session/poster.probe" ]; do
    sleep 0.2
    waited=$((waited + 1))
    [ "$waited" -lt 100 ] || { echo "the overlay never reported for $name" >&2; exit 1; }
  done
  # Long enough that any notification the machine threw up has gone again. One
  # of those in a published shot is somebody's private business.
  sleep 6
  screencapture -x "$work/$name.png"
  kill -TERM "$overlay_pid" 2>/dev/null || true; overlay_pid=""
  sleep 1
  [ -s "$work/$name.png" ] || {
    echo "screencapture wrote nothing." >&2
    echo "  command: screencapture -x $work/$name.png" >&2
    echo "  fix: give this terminal Screen Recording in System Settings, Privacy and Security." >&2
    exit 1
  }
  cp "$session/poster.probe" "$work/$name.probe"
}

echo "opening $SITE on a throwaway profile"
"$CHROME" --user-data-dir="$work/chrome" --no-first-run --no-default-browser-check \
  --disable-session-crashed-bubble --hide-crash-restore-bubble --disable-notifications \
  --window-position=0,0 --window-size=1512,940 "$SITE" > "$work/chrome.log" 2>&1 &
chrome_pid=$!
sleep 10

echo "drawing on it"
shoot annotating 0
echo "and again with nothing drawn"
shoot quiet 1

kill -TERM "$chrome_pid" 2>/dev/null || true; chrome_pid=""

uv run --quiet --with pillow python - "$work" "$OUT" <<'PY'
import sys
from PIL import Image

work, out = sys.argv[1], sys.argv[2]


def probe(name):
    values = {}
    for line in open(f"{work}/{name}.probe"):
        parts = line.split()
        values[parts[0]] = [int(n) for n in parts[1:]]
    return values


def save(image, name, box, target_width):
    crop = image.crop(box)
    ratio = target_width / crop.width
    crop.resize((target_width, max(1, round(crop.height * ratio))),
                Image.LANCZOS).save(f"{out}/{name}", optimize=True)
    print(f"wrote {out}/{name}")


def palette_box(image, name, pad):
    """The palette's own frame, turned from screen points into image pixels.

    Cropping by eye is what put the bar off centre the first time. The overlay
    knows exactly where it put the window, so it is asked instead of guessed.
    Screen points count up from the bottom left and image pixels count down
    from the top left, which is the whole of the arithmetic below.
    """
    values = probe(name)
    x, y, w, h = values["palette"]
    screen_width, screen_height = values["screen"]
    scale = image.width / screen_width
    top = (screen_height - y - h) * scale
    return (round(x * scale) - pad, round(top) - pad,
            round((x + w) * scale) + pad, round(top + h * scale) + pad)


shot = Image.open(f"{work}/annotating.png").convert("RGB")
menu_bar = round(37 * (shot.width / probe("annotating")["screen"][0]))
save(shot, "annotating.png", (0, menu_bar, shot.width, shot.height), 1400)

# Equal padding on every side, measured from the window the overlay reports, so
# the bar sits in the middle of its own picture.
for source, name in (("annotating", "palette.png"), ("quiet", "palette-quiet.png")):
    image = Image.open(f"{work}/{source}.png").convert("RGB")
    pad = round(20 * (image.width / probe(source)["screen"][0]))
    save(image, name, palette_box(image, source, pad), 1200)
PY
