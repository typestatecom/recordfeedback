#!/usr/bin/env bash
# Rebuilds the README shots. Takes over the screen for about fifteen seconds:
# a backdrop covers every display so that nothing of the real desktop is in the
# picture, the overlay draws over it, and the shots are cropped from that.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUT="$HERE"

for tool in swiftc screencapture uv; do
  command -v "$tool" > /dev/null 2>&1 || {
    echo "docs/screenshots/make.sh: $tool is not installed." >&2
    echo "  fix: install the Xcode command line tools with: xcode-select --install" >&2
    exit 1
  }
done

work="$(mktemp -d -t rf-shots)"
backdrop_pid=""
overlay_pid=""
cleanup() {
  [ -n "$overlay_pid" ] && kill -TERM "$overlay_pid" 2>/dev/null || true
  [ -n "$backdrop_pid" ] && kill -TERM "$backdrop_pid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

echo "building the backdrop"
swiftc -O -framework Cocoa -o "$work/backdrop" "$HERE/backdrop.swift"

echo "building the overlay with its probes"
"$REPO/overlay/build.sh" --probes > "$work/build.log" 2>&1 \
  || { echo "the overlay would not build:"; sed 's/^/  /' "$work/build.log"; exit 1; }

echo "taking the screen for a few seconds"
"$work/backdrop" & backdrop_pid=$!
sleep 2

session="$work/session"
mkdir -p "$session"
RF_SESSION="$session" RF_OVERLAY_SELFTEST=poster "$REPO/bin/rf-overlay-probe" \
  > "$work/overlay.log" 2>&1 & overlay_pid=$!
sleep 4

screencapture -x "$work/full.png"

kill -TERM "$overlay_pid" 2>/dev/null || true; overlay_pid=""
kill -TERM "$backdrop_pid" 2>/dev/null || true; backdrop_pid=""
sleep 1

[ -s "$work/full.png" ] || {
  echo "screencapture wrote nothing." >&2
  echo "  fix: give this terminal Screen Recording in System Settings, Privacy and Security." >&2
  exit 1
}

# The menu bar is cropped off. It carries the session timer, which is worth
# showing, but it also carries whatever else this machine happens to run, and
# none of that belongs in a public README. The timer gets its own shot instead.
uv run --quiet --with pillow python - "$work/full.png" "$OUT" <<'PY'
import sys
from PIL import Image

source, out = sys.argv[1], sys.argv[2]
image = Image.open(source).convert("RGB")
w, h = image.size
scale = w / 1512 if w > 1512 else 1        # retina captures are twice the points

def save(name, box, target_width):
    crop = image.crop(box)
    ratio = target_width / crop.width
    crop.resize((target_width, max(1, round(crop.height * ratio))),
                Image.LANCZOS).save(f"{out}/{name}", optimize=True)
    print(f"wrote {out}/{name}")

menu_bar = round(37 * scale)
save("annotating.png", (0, menu_bar, w, h), 1400)
# The palette sits centred near the bottom edge, which is where the overlay
# puts it until somebody drags it.
save("palette.png",
     (round(w * 0.03), h - round(105 * scale), round(w * 0.97), h - round(30 * scale)),
     1200)
PY
