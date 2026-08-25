#!/usr/bin/env bash
# Records you saying the commands, and keeps the recordings as fixtures.
#
#   test/voice/record.sh                     every command, once each
#   test/voice/record.sh draw region         only those
#   test/voice/record.sh --label fast draw   tagged, so the same command can be
#                                            recorded in as many ways as you like
#
# Say each one the way you would actually say it. The point of this is the
# accent, the pace and the room you are really in, and a recording made in a
# careful voice you would never use proves nothing.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SECONDS_PER_CLIP="${RF_CLIP_SECONDS:-3}"
LABEL="me"

while [ $# -gt 0 ]; do
  case "$1" in
    --label) LABEL="${2:-me}"; shift 2 ;;
    --seconds) SECONDS_PER_CLIP="${2:-3}"; shift 2 ;;
    -*) echo "test/voice/record.sh: unknown option '$1'" >&2
        echo "  command: test/voice/record.sh [--label NAME] [--seconds N] [command...]" >&2
        exit 1 ;;
    *) break ;;
  esac
done

# The commands and the words to say for them come from the tool itself, so a
# phrase added in the settings window is one this can record.
overlay="$REPO/bin/rf-overlay-probe"
[ -x "$overlay" ] || "$REPO/overlay/build.sh" --probes > /dev/null

# The input the tool would record from, so the fixtures come through the same
# microphone a session does.
device="$("$REPO/bin/recordfeedback" input-index)"
trigger="$(jq -r '.voice.trigger // "let'"'"'s"' "${RF_HOME:-$HOME/.recordfeedback}/settings.json" 2>/dev/null || echo "let's")"

if [ $# -gt 0 ]; then
  commands=("$@")
else
  commands=(draw done clear undo tool-pen tool-arrow tool-rectangle tool-highlighter
            colour-red colour-blue bigger smaller screenshot region)
fi

mkdir -p "$HERE/clips"
manifest="$HERE/manifest.tsv"
[ -f "$manifest" ] || printf '# clip\texpected\tsaid\n' > "$manifest"

phrase_for() {
  # The first phrase the settings hold for a command, which is the one to read
  # aloud. Any of its phrases would do, and this one is the plainest.
  python3 - "$1" "${RF_HOME:-$HOME/.recordfeedback}/settings.json" <<'PY'
import json, sys
command, path = sys.argv[1], sys.argv[2]
try:
    phrases = json.load(open(path))["voice"]["phrases"][command]
    print(phrases[0] if phrases else command.replace("-", " "))
except Exception:
    print(command.replace("-", " "))
PY
}

echo "Recording through avfoundation input $device. Say each line as you would"
echo "really say it. Each recording is $SECONDS_PER_CLIP seconds and starts when you press return."
echo

for command in "${commands[@]}"; do
  words="$(phrase_for "$command")"
  index=1
  while [ -f "$HERE/clips/$command-$LABEL-$index.wav" ]; do index=$((index + 1)); done
  name="$command-$LABEL-$index.wav"

  printf '  say: "%s %s"   [return to record, s to skip] ' "$trigger" "$words"
  read -r answer
  case "$answer" in
    s|skip) echo "    skipped"; continue ;;
  esac

  printf '    recording'
  ffmpeg -nostdin -v error -y -f avfoundation -i ":$device" \
    -t "$SECONDS_PER_CLIP" -ac 1 -ar 16000 -c:a pcm_s16le "$HERE/clips/$name" \
    < /dev/null > /dev/null 2>&1 || {
      echo " ... ffmpeg could not record."
      echo "    command: ffmpeg -f avfoundation -i :$device -t $SECONDS_PER_CLIP $HERE/clips/$name" >&2
      echo "    fix: check recordfeedback doctor, which says whether the microphone works." >&2
      exit 1
    }

  # A recording of a room with nobody talking in it is not a fixture, and
  # keeping one would only ever fail for the wrong reason.
  level="$(ffmpeg -hide_banner -nostdin -i "$HERE/clips/$name" -af volumedetect -f null - 2>&1 \
    | sed -n 's/.*max_volume: \(-*[0-9.]*\) dB.*/\1/p')"
  if [ -z "$level" ] || [ "$(python3 -c "print(1 if float('${level:--99}') < -45 else 0)")" = 1 ]; then
    echo " ... nothing was said, dropping it (peak ${level:-unknown} dBFS)"
    rm -f "$HERE/clips/$name"
    continue
  fi

  printf '%s\t%s\t%s %s\n' "$name" "$command" "$trigger" "$words" >> "$manifest"
  echo " ... kept $name (peak $level dBFS)"
done

echo
echo "manifest: $manifest"
echo "measure them with: test/run.sh 35-voice-corpus"
