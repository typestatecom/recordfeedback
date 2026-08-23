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
  [ "$1" = "$2" ] || fail "${3:-values differ}: expected '$2', got '$1'"
}
