#!/usr/bin/env bash
# Puts the CLI on PATH and the slash command where Claude Code looks for it.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${RF_BIN_DIR:-$HOME/.local/bin}"
COMMANDS_DIR="${RF_COMMANDS_DIR:-$HOME/.claude/commands}"

mkdir -p "$BIN_DIR" "$COMMANDS_DIR"

ln -sfn "$REPO/bin/recordfeedback" "$BIN_DIR/recordfeedback"
ln -sfn "$REPO/bin/recordfeedback" "$BIN_DIR/rfb"
ln -sfn "$REPO/commands/recordfeedback.md" "$COMMANDS_DIR/recordfeedback.md"

echo "Installed:"
echo "  $BIN_DIR/recordfeedback"
echo "  $BIN_DIR/rfb"
echo "  $COMMANDS_DIR/recordfeedback.md"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo
    echo "$BIN_DIR is not on your PATH, so the slash command cannot find the CLI."
    echo "Add this to ~/.zshrc and open a new terminal:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac

if [ ! -x "$REPO/bin/rf-overlay" ]; then
  echo
  echo "The overlay is not built, so there are no annotations and no palette."
  echo "Build it with: $REPO/overlay/build.sh"
fi

echo
echo "Check the machine with: recordfeedback doctor"
