# doctor reports every dependency present on this machine.
. "$REPO/test/lib.sh"

# The real model lives outside the test home. Point at it so doctor checks the
# same file the tool would really use.
export RF_MODEL="$HOME/.recordfeedback/models/ggml-large-v3-turbo-q5_0.bin"
# Never open the real microphone from a test.
export RF_FFMPEG_INPUT="-f lavfi -i sine=frequency=440:duration=1"

out="$("$RFB" doctor 2>&1)" || true
echo "$out"

for dep in ffmpeg ffprobe fswatch whisper-cli swiftc jq python3 screencapture; do
  line="$(echo "$out" | grep -E "^[a-z]+ +$dep( |$)" || true)"
  [ -n "$line" ] || fail "doctor printed no line for $dep. Got:
$out"
  case "$line" in
    ok*) ;;
    *) fail "doctor did not report $dep present: $line" ;;
  esac
done

assert_contains "$out" "whisper model" "doctor output"
assert_contains "$out" "screenshot folder" "doctor output"
assert_contains "$out" "microphone" "doctor output"

# The model line must be ok, the model is on this machine.
model_line="$(echo "$out" | grep "whisper model")"
case "$model_line" in
  ok*) ;;
  *) fail "doctor did not find the whisper model: $model_line" ;;
esac

# A microphone check that counts bytes passes on a dead device: a denied
# permission, a muted input and a virtual mixer routed to nothing all hand over
# a full sized file of zeros. Reporting that as working is the check that let a
# whole session be recorded into nothing.
out="$(RF_FFMPEG_INPUT="-f lavfi -i anullsrc=r=16000:cl=mono" "$RFB" doctor 2>&1 || true)"
echo "$out"
mic_line="$(printf '%s\n' "$out" | grep -i 'microphone' || true)"
[ -n "$mic_line" ] || fail "doctor printed no microphone line at all. Got:
$out"
case "$mic_line" in
  fail*) ;;
  *) fail "doctor passed a microphone that captured nothing but zeros:
$mic_line" ;;
esac
assert_contains "$mic_line" "zero" "the failing microphone line must say what is wrong"

# Voice control listens with whisper, the same engine that writes the
# transcript, so what it needs is what the transcript needs and doctor can say
# so without a permission being involved at all.
overlay="$REPO/bin/rf-overlay"
if [ -x "$overlay" ]; then
  out="$("$overlay" --check-voice 2>/dev/null || true)"
  assert_contains "$out" "engine whisper" "--check-voice names the engine"
  ready="$(printf '%s\n' "$out" | sed -n 's/^ready //p')"
  case "$ready" in
    0|1) ;;
    *) fail "--check-voice did not say whether it can listen. Got:
$out" ;;
  esac
  # A machine that cannot listen has to say why, or the switch in the settings
  # window turns on something that then does nothing.
  if [ "$ready" = 0 ]; then
    assert_contains "$out" "why " "--check-voice must say why it cannot listen"
  fi
fi
