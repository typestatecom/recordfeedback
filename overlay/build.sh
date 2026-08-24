#!/usr/bin/env bash
# Builds the annotation overlay. Every .swift in this folder, one swiftc call,
# no Xcode project.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$REPO/bin"

if ! command -v swiftc > /dev/null 2>&1; then
  echo "overlay/build.sh: swiftc is not installed." >&2
  echo "  command: swiftc" >&2
  echo "  fix: install the Xcode command line tools with: xcode-select --install" >&2
  exit 1
fi

# The whole folder rather than a list: a file added to the overlay and left out
# of the build fails at the first call into it, which is a long way from the
# person who added it.
sources=("$REPO"/overlay/*.swift)

swiftc -O -framework Cocoa -framework Carbon \
  -o "$REPO/bin/rf-overlay" "${sources[@]}"

echo "built $REPO/bin/rf-overlay"
