#!/usr/bin/env bash
# Cuts the commands out of a real session and keeps them as fixtures.
#
# The best test material for this is a person's own voice saying the thing they
# actually said, in the room they actually said it in. A session that went badly
# is the most valuable of all, because every command it missed is a case that
# fails until it stops missing it.
#
#   test/voice/extract.sh ~/.recordfeedback/sessions/20260825-134912 [label]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SESSION="${1:-}"
LABEL="${2:-session}"
MODEL="${RF_MODEL:-$HOME/.recordfeedback/models/ggml-large-v3-turbo-q5_0.bin}"

[ -n "$SESSION" ] || {
  echo "test/voice/extract.sh: no session given." >&2
  echo "  command: test/voice/extract.sh SESSION_DIR [label]" >&2
  echo "  fix: pass a session directory, for instance the one recordfeedback last names." >&2
  exit 1
}
[ -f "$SESSION/audio.wav" ] || {
  echo "test/voice/extract.sh: no audio at $SESSION/audio.wav." >&2
  exit 1
}
[ -f "$MODEL" ] || {
  echo "test/voice/extract.sh: no whisper model at $MODEL." >&2
  echo "  fix: set RF_MODEL, or download the model the README names." >&2
  exit 1
}

work="$(mktemp -d -t rf-voice)"
trap 'rm -rf "$work"' EXIT

echo "reading the words and where they were said"
whisper-cli -m "$MODEL" -f "$SESSION/audio.wav" -l en -ojf -sow \
  -of "$work/words" -np -t 8 > "$work/whisper.log" 2>&1 \
  || { echo "whisper could not read $SESSION/audio.wav:"; tail -5 "$work/whisper.log"; exit 1; }

python3 "$HERE/spans.py" "$work/words.json" "$work/spans.tsv"
count="$(wc -l < "$work/spans.tsv" | tr -d ' ')"
echo "found $count candidate commands"
[ "$count" -gt 0 ] || exit 0

# What each span means is decided by the grammar that ships, and not by a second
# copy of it here that could disagree with it.
overlay="$REPO/bin/rf-overlay-probe"
[ -x "$overlay" ] || "$REPO/overlay/build.sh" --probes > /dev/null
cut -f3 "$work/spans.tsv" > "$work/heard.txt"
probe_session="$work/grammar"
mkdir -p "$probe_session"
touch "$probe_session/start.ref"
RF_SESSION="$probe_session" RF_VOICE_HEARD="$work/heard.txt" \
  RF_OVERLAY_SELFTEST=grammar "$overlay" > "$work/grammar.log" 2>&1 || true
[ -f "$probe_session/grammar.probe" ] || {
  echo "the grammar probe said nothing:"; cat "$work/grammar.log"; exit 1
}

mkdir -p "$HERE/clips"
manifest="$HERE/manifest.tsv"
[ -f "$manifest" ] || printf '# clip\texpected\tsaid\n' > "$manifest"

kept=0
skipped=0
while IFS=$'\t' read -r from to said; do
  # The command this tool would take those words to mean. A span the grammar
  # reads as nothing is a person talking, and it is not a fixture.
  command="$(awk -F'|' -v want="$said" '$2 == want { print $3; exit }' \
    "$probe_session/grammar.probe")"
  if [ -z "$command" ] || [ "$command" = "none" ]; then
    skipped=$((skipped + 1))
    continue
  fi
  index=1
  while [ -f "$HERE/clips/$command-$LABEL-$index.wav" ]; do index=$((index + 1)); done
  name="$command-$LABEL-$index.wav"
  # A little air either side, because a clip that starts on the first consonant
  # loses it and the recogniser then hears a different word.
  start="$(python3 -c "print(max(0, $from - 0.2))")"
  length="$(python3 -c "print(round($to - $from + 0.5, 3))")"
  ffmpeg -v error -y -ss "$start" -t "$length" -i "$SESSION/audio.wav" \
    -ac 1 -ar 16000 -c:a pcm_s16le "$HERE/clips/$name"
  printf '%s\t%s\t%s\n' "$name" "$command" "$said" >> "$manifest"
  kept=$((kept + 1))
done < "$work/spans.tsv"

echo "kept $kept clips, skipped $skipped spans the grammar reads as ordinary speech"
echo "manifest: $manifest"
echo "run them with: test/run.sh 35-voice-corpus"
