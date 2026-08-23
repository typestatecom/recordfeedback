#!/usr/bin/env bash
# Runs every case in test/cases. One line per case. No framework.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO
export RFB="$REPO/bin/recordfeedback"
export TMPROOT="$REPO/test/tmp"

# A case exits 0 for pass and 77 for skip. Anything else is a failure and the
# captured output is printed, because a case that fails silently is worthless.
SKIP_EXIT=77

mkdir -p "$TMPROOT"

pattern="${1:-}"
pass=0
fail=0
skip=0
failed_names=()

for case_file in "$REPO"/test/cases/*.sh; do
  name="$(basename "$case_file" .sh)"
  if [ -n "$pattern" ] && [[ "$name" != *"$pattern"* ]]; then
    continue
  fi

  case_home="$TMPROOT/home/$name"
  rm -rf "$case_home"
  mkdir -p "$case_home/models"
  # Every case gets its own RF_HOME so cases never see each other's sessions.
  export RF_HOME="$case_home"
  export RF_CASE_TMP="$TMPROOT/scratch/$name"
  rm -rf "$RF_CASE_TMP"
  mkdir -p "$RF_CASE_TMP"

  log="$TMPROOT/$name.log"
  started=$(date +%s)
  set +e
  bash "$case_file" >"$log" 2>&1
  status=$?
  set -e
  elapsed=$(( $(date +%s) - started ))

  if [ "$status" -eq 0 ]; then
    printf 'ok    %-34s %3ds\n' "$name" "$elapsed"
    pass=$((pass + 1))
  elif [ "$status" -eq "$SKIP_EXIT" ]; then
    printf 'skip  %-34s %3ds  %s\n' "$name" "$elapsed" "$(tail -n 1 "$log")"
    skip=$((skip + 1))
  else
    printf 'FAIL  %-34s %3ds\n' "$name" "$elapsed"
    sed 's/^/        | /' "$log"
    fail=$((fail + 1))
    failed_names+=("$name")
  fi
done

echo
echo "$pass passed, $fail failed, $skip skipped"
if [ "$fail" -gt 0 ]; then
  echo "failed: ${failed_names[*]}"
  exit 1
fi
