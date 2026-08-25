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
