# Assertions shared by the cases. Sourced, never run.
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

skip() {
  echo "$*"
  exit 77
}

assert_contains() {
  local haystack="$1" needle="$2" what="${3:-output}"
  case "$haystack" in
    *"$needle"*) ;;
    *) fail "$what does not contain '$needle'. Got:
$haystack" ;;
  esac
}

assert_not_contains() {
  local haystack="$1" needle="$2" what="${3:-output}"
  case "$haystack" in
    *"$needle"*) fail "$what should not contain '$needle'. Got:
$haystack" ;;
  esac
}

assert_file() {
  [ -f "$1" ] || fail "expected file $1 to exist"
}

assert_eq() {
  # The comparison goes first. The message is usually several lines of context
  # ending in a dump of what the probe said, and appending the comparison after
  # that reads as though it belongs to the last line of the dump, which sent a
  # reader chasing an assertion that had passed.
  [ "$1" = "$2" ] || fail "expected '$2', got '$1'
${3:-values differ}"
}

# The probes are compiled out of the binary the tool ships, so a case that
# drives one builds its own. Same sources, one flag apart, rebuilt whenever a
# source is newer than it so a case never proves yesterday's code.
probe_overlay() {
  local binary="$REPO/bin/rf-overlay-probe"
  if [ ! -x "$binary" ] \
     || [ -n "$(find "$REPO/overlay" -name '*.swift' -newer "$binary" 2>/dev/null)" ]; then
    "$REPO/overlay/build.sh" --probes > "$RF_CASE_TMP/build.log" 2>&1 || return 1
  fi
  printf '%s\n' "$binary"
}

# Room tone: a session where nobody spoke. Measured at about -71 dBFS, which is
# what this machine's microphone reads in a quiet room, so it is quiet enough
# that stop calls the session silent and alive enough that start does not read
# it as a dead input. anullsrc is not this. Every sample of anullsrc is zero,
# which is a microphone that is not working, and a fixture that spells one of
# those with the other is how a lost session gets written off as a quiet one.
RF_ROOM_TONE='-f lavfi -i anoisesrc=r=16000:c=white:a=0.0005'
