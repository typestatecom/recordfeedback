#!/usr/bin/env bash
# Builds the annotation overlay. One file, one swiftc call, no Xcode project.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$REPO/bin"

if ! command -v swiftc > /dev/null 2>&1; then
  echo "overlay/build.sh: swiftc is not installed." >&2
  echo "  command: swiftc" >&2
  echo "  fix: install the Xcode command line tools with: xcode-select --install" >&2
  exit 1
fi

swiftc -O -framework Cocoa -framework Carbon \
  -o "$REPO/bin/rf-overlay" "$REPO/overlay/Overlay.swift"

echo "built $REPO/bin/rf-overlay"
