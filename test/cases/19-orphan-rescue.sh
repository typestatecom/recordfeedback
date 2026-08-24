# The overlay writes its stop file and waits for the CLI to come and finish the
# session. When nothing is listening, which is what happens if the CLI died or
# was never watching, that wait never ends: the window stays on the screen, the
# stop button does nothing anybody can see, and the recording keeps running.
# That happened to this tool's own user for forty minutes.
. "$REPO/test/lib.sh"

# The CLI launches the overlay here, so it is the CLI that has to be pointed at
# the build with the probes in it.
RF_OVERLAY_BIN="$(probe_overlay)" \
  || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"
export RF_OVERLAY_BIN

probe="$RF_CASE_TMP/probe.png"
screencapture -x "$probe" > /dev/null 2>&1 \
  || skip "screencapture cannot run without a screen"
[ -s "$probe" ] || skip "screencapture produced nothing, so there is no window server"

export RF_FFMPEG_INPUT="-re -f lavfi -i sine=frequency=440:sample_rate=16000"
# The overlay presses its own stop once its windows are up, and nothing at all
# is listening for it: no wait loop, no stop, no CLI of any kind.
export RF_OVERLAY_SELFTEST=rescue
export RF_RESCUE_SECONDS=4

"$RFB" start > "$RF_CASE_TMP/start.out" 2> "$RF_CASE_TMP/start.err" \
  || fail "start failed:
$(cat "$RF_CASE_TMP/start.err")"
session="$(sed -n 's/^  session: //p' "$RF_CASE_TMP/start.out")"
[ -n "$session" ] || fail "start printed no session path"
trap '"$RFB" abort > /dev/null 2>&1 || true' EXIT

overlay_pid="$(cat "$session/overlay.pid" 2>/dev/null || true)"
[ -n "$overlay_pid" ] || skip "start did not launch an overlay here"

# --- the click has to land somewhere the user can see, at once.
waited=0
while [ ! -f "$session/stop" ]; do
  sleep 0.2
  waited=$((waited + 1))
  [ "$waited" -lt 50 ] || fail "the overlay never asked for the session to stop:
$(cat "$session/overlay.log" 2>/dev/null)"
done

# --- and nobody answers, so the overlay has to finish the job itself.
waited=0
while kill -0 "$overlay_pid" 2>/dev/null; do
  sleep 1
  waited=$((waited + 1))
  [ "$waited" -lt 90 ] || fail "the overlay is still on the screen $waited seconds
  after its stop button was pressed, with nothing listening for it. There is no
  way off the screen from here except the terminal. Its log said:
$(cat "$session/overlay.log" 2>/dev/null)"
done

# --- and nothing may be lost by that.
waited=0
while [ ! -f "$session/feedback.md" ]; do
  sleep 1
  waited=$((waited + 1))
  [ "$waited" -lt 120 ] || fail "the overlay quit without the session being
  finished, so the recording is stranded. The audio, the shots and the words
  are all still on disk but nothing joined them. Its log said:
$(cat "$session/overlay.log" 2>/dev/null)"
done

[ -s "$session/audio.wav" ] \
  || fail "the session finished with no audio in it. ffmpeg keeps the recording
  buffered until it is asked to quit, so anything that ends a session without
  asking loses every word that was said."

assert_contains "$(cat "$session/overlay.log" 2>/dev/null)" "nothing was listening" \
  "the overlay says why it finished the session itself, since the user is
  about to find a session that ended without them running anything"

echo "an overlay nobody is listening to stops itself and loses nothing"
