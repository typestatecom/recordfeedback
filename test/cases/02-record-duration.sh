# A session records in real time: the recorded audio advances one second per
# second of wall clock, and the finished WAV covers the session window.
. "$REPO/test/lib.sh"

export RF_FFMPEG_INPUT="-re -f lavfi -i sine=frequency=440:sample_rate=16000"

out="$("$RFB" start --note "duration check")"
echo "$out"
assert_contains "$out" "Recording" "start output"

session="$(readlink "$RF_HOME/current")"
[ -d "$session" ] || fail "current does not point at a session directory"
assert_file "$session/start.ref"
assert_file "$session/meta.json"
assert_file "$session/ffmpeg.pid"

note="$(jq -r .note "$session/meta.json")"
assert_eq "$note" "duration check" "meta.json note"

sample() { grep -a '^out_time_us=' "$session/ffmpeg.progress" | tail -n 1 | cut -d= -f2; }
r1="$(sample)"; t1="$(python3 -c 'import time;print(time.time())')"
sleep 6
r2="$(sample)"; t2="$(python3 -c 'import time;print(time.time())')"

st="$("$RFB" status)"
echo "$st"
assert_contains "$st" "$session" "status output"

"$RFB" abort >/dev/null

[ -L "$RF_HOME/current" ] && fail "abort left the current symlink behind"
assert_file "$session/audio.wav"

window="$(python3 -c "
import os
a=os.stat('$session/start.ref').st_mtime
b=os.stat('$session/stop.ref').st_mtime
print(round(b-a,3))")"
duration="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$session/audio.wav")"

python3 - <<PY
w = float("$window"); d = float("$duration")
rate = (int("$r2") - int("$r1")) / 1e6 / (float("$t2") - float("$t1"))
print("window=%.3f duration=%.3f offset=%+.3f rate=%.4f" % (w, d, d - w, rate))

# The property that matters is that a second of talking becomes a second of
# audio. Both the real input and the synthetic one carry a fixed startup
# offset of about half a second, which says nothing about drift.
if abs(rate - 1.0) > 0.02:
    raise SystemExit("the recorder is not running in real time: %.4f seconds of audio per second" % rate)
if abs(d - w) > 1.0:
    raise SystemExit("audio duration %.3f does not cover the session window %.3f" % (d, w))
PY

rate="$(ffprobe -v error -show_entries stream=sample_rate,channels -of csv=p=0 "$session/audio.wav")"
assert_eq "$rate" "16000,1" "audio format"

status="$(jq -r .status "$session/meta.json")"
assert_eq "$status" "aborted" "meta.json status after abort"
