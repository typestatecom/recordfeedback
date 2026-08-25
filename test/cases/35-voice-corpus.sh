# Voice control, measured against a person's own voice rather than a
# synthesiser's.
#
# `say` produces the same clean studio American every time, and voice control
# passed every case built on it while being close to unusable for the person it
# was built for. So the fixtures are real recordings: test/voice/clips holds
# them, test/voice/manifest.tsv says what each one was meant to reach, and
# test/voice/extract.sh cuts more out of any session that went badly.
#
# This is a ratchet and not a pass or fail. Recognition is not going to be
# perfect, so the case holds the number that has been reached and refuses to let
# it fall. Raise the baseline when the rate goes up, never lower it to go green.
. "$REPO/test/lib.sh"

OVERLAY="$(probe_overlay)" \
  || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"

speech="$("$OVERLAY" --check-speech 2>/dev/null || true)"
state="$(printf '%s\n' "$speech" | sed -n 's/^permission //p')"
[ "$state" = granted ] \
  || skip "Speech Recognition is '$state'. Turn it on for this terminal in System Settings, Privacy and Security, Speech Recognition."

manifest="$REPO/test/voice/manifest.tsv"
[ -f "$manifest" ] \
  || skip "no recordings yet. Make some with test/voice/record.sh, or cut them out of a session with test/voice/extract.sh"

baseline_file="$REPO/test/voice/baseline"
baseline="$(cat "$baseline_file" 2>/dev/null || echo 0)"

clips="$RF_CASE_TMP/clips.txt"
: > "$clips"
total=0
while IFS=$'\t' read -r name expected said; do
  case "$name" in '#'*|'') continue ;; esac
  [ -f "$REPO/test/voice/clips/$name" ] || fail "the manifest names $name and it is not in test/voice/clips"
  echo "$REPO/test/voice/clips/$name" >> "$clips"
  total=$((total + 1))
done < "$manifest"
[ "$total" -gt 0 ] || skip "the manifest has no recordings in it"

session="$RF_HOME/sessions/corpus"
mkdir -p "$session"
touch "$session/start.ref"
mkdir -p "$RF_HOME"
cat > "$RF_HOME/settings.json" <<'JSON'
{"voice":{"enabled":true,"trigger":"let's","escape":"not a command"}}
JSON

RF_SESSION="$session" RF_VOICE_CLIPS="$clips" RF_VOICE_LISTEN=1 RF_LANG=en \
  RF_OVERLAY_SELFTEST=voice-replay "$OVERLAY" > "$RF_CASE_TMP/overlay.log" 2>&1 &
overlay_pid=$!
# shellcheck disable=SC2064
trap "kill -TERM $overlay_pid 2>/dev/null || true" EXIT

report="$session/replay.probe"
waited=0
while [ ! -f "$report" ]; do
  sleep 0.5
  waited=$((waited + 1))
  [ "$waited" -lt $((total * 20 + 60)) ] || fail "the replay never finished:
$(cat "$RF_CASE_TMP/overlay.log")"
done
kill -TERM "$overlay_pid" 2>/dev/null || true
trap - EXIT

grep -q '^error' "$report" && fail "the replay could not run: $(cat "$report")"

# One line per recording, so a miss can be read rather than counted.
hits=0
misses=""
while IFS=$'\t' read -r name expected said; do
  case "$name" in '#'*|'') continue ;; esac
  line="$(grep -a "^clip $name " "$report" || true)"
  got="$(printf '%s\n' "$line" | awk '{print $3}')"
  heard="$(printf '%s\n' "$line" | sed -n 's/^[^|]*| //p')"
  case ",$got," in
    *",$expected,"*) hits=$((hits + 1)); printf 'ok   %-26s %s\n' "$name" "$heard" ;;
    *) misses="$misses$name wanted $expected, got ${got:-nothing}, heard: $heard
"; printf 'MISS %-26s wanted %-12s got %-12s %s\n' "$name" "$expected" "${got:-nothing}" "$heard" ;;
  esac
done < "$manifest"

echo
echo "recognised $hits of $total, baseline $baseline"
[ -n "$misses" ] && { echo "missed:"; printf '%s' "$misses"; }

[ "$hits" -ge "$baseline" ] || fail "voice control recognised $hits of $total real
  recordings and the baseline is $baseline. Something made it worse. The misses
  are listed above, and each one is a recording of a person saying a command
  that this tool did not act on."

# A baseline that drifts below what the tool can do stops catching anything, so
# it is raised here rather than left for somebody to remember.
if [ "$hits" -gt "$baseline" ]; then
  echo "$hits" > "$baseline_file"
  echo "raised the baseline to $hits. Commit test/voice/baseline."
fi
