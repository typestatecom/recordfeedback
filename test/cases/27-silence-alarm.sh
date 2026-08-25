# A microphone can die in the middle of a session, and from in front of the
# screen a session recording silence looks exactly like one recording speech.
# The palette carries a meter for the whole session and raises an alarm when the
# input goes dead, because the user is talking and not reading a terminal.
. "$REPO/test/lib.sh"

OVERLAY="$(probe_overlay)" \
  || skip "the overlay does not build here: $(tail -n 1 "$RF_CASE_TMP/build.log")"

needs_screen

session="$RF_HOME/sessions/alarm"
mkdir -p "$session/levels"
touch "$session/start.ref"

# A stand in for the recorder's second output: one second of 16 kHz mono s16le
# per file, rewritten in rotation the way the segment muxer does. Zeros are what
# a denied microphone, a muted device and an unrouted virtual mixer all write.
# It has to keep writing rather than drop three files and stop, because a
# segment that stopped being written is a recorder that died, which is a
# different thing from one that is running and capturing silence.
writer_pid=""
start_writer() {
  stop_writer
  local source="$1"
  ( while :; do
      for n in 0 1 2; do
        dd if="$source" of="$session/levels/$n.pcm" bs=32768 count=1 2>/dev/null
        sleep 0.3
      done
    done ) &
  writer_pid=$!
}
stop_writer() {
  [ -n "$writer_pid" ] && kill -TERM "$writer_pid" 2>/dev/null
  writer_pid=""
}

start_writer /dev/zero

RF_SESSION="$session" RF_OVERLAY_SELFTEST=level "$OVERLAY" \
  > "$RF_CASE_TMP/overlay.log" 2>&1 &
overlay_pid=$!
# shellcheck disable=SC2064
trap "kill -TERM $overlay_pid 2>/dev/null || true; stop_writer" EXIT

report="$session/level.probe"
await_report() {
  local waited=0
  rm -f "$report"
  while [ ! -f "$report" ]; do
    kill -0 "$overlay_pid" 2>/dev/null || fail "the overlay exited before it reported:
$(cat "$RF_CASE_TMP/overlay.log")"
    sleep 0.2
    waited=$((waited + 1))
    [ "$waited" -lt 150 ] || fail "the overlay never wrote $report:
$(cat "$RF_CASE_TMP/overlay.log")"
  done
}

# The probe rewrites the report every time it polls, so the first one is read
# after the alarm has had its grace period to elapse.
await_report
sleep 6
await_report
dead="$(cat "$report")"
echo "$dead"

value() { grep -a "^$1 " "$report" | tail -n 1 | cut -d' ' -f2-; }

assert_eq "$(value input-reported)" "1" "the overlay never measured the input"
assert_eq "$(value input-dead)" "1" "silence did not read as a dead input"
assert_eq "$(value alarm)" "1" "the palette raised no alarm on a dead input"

# The alarm has to say what is wrong in words. A red row that names nothing is
# a row the user stares at while the session keeps recording nothing.
words="$(value alarm-text)"
assert_contains "$words" "SOUND" "the alarm must say what is wrong"

# The menu bar is the one place a full screen application cannot cover, so the
# alarm has to reach it too.
assert_eq "$(value menu-alarm)" "1" "the menu bar item did not show the alarm"

# A microphone that comes back clears the alarm. An alarm that latches is one
# the user learns to ignore.
start_writer /dev/urandom
sleep 3
await_report
alive="$(cat "$report")"
echo "$alive"
assert_eq "$(value input-dead)" "0" "a live input still read as dead"
assert_eq "$(value alarm)" "0" "the alarm did not clear when the input came back"

kill -TERM "$overlay_pid" 2>/dev/null || true
stop_writer
trap - EXIT
