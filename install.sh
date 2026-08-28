#!/usr/bin/env bash
# Puts the CLI on PATH and the agent commands where their hosts look for them.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${RF_BIN_DIR:-$HOME/.local/bin}"
COMMANDS_DIR="${RF_COMMANDS_DIR:-$HOME/.claude/commands}"
SKILLS_DIR="${RF_SKILLS_DIR:-$HOME/.agents/skills}"

mkdir -p "$BIN_DIR" "$COMMANDS_DIR" "$SKILLS_DIR"

ln -sfn "$REPO/bin/recordfeedback" "$BIN_DIR/recordfeedback"
ln -sfn "$REPO/bin/recordfeedback" "$BIN_DIR/rfb"
ln -sfn "$REPO/commands/recordfeedback.md" "$COMMANDS_DIR/recordfeedback.md"
ln -sfn "$REPO/skills/recordfeedback" "$SKILLS_DIR/recordfeedback"

echo "Installed:"
echo "  $BIN_DIR/recordfeedback"
echo "  $BIN_DIR/rfb"
echo "  $COMMANDS_DIR/recordfeedback.md"
echo "  $SKILLS_DIR/recordfeedback"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo
    echo "$BIN_DIR is not on your PATH, so the agent integrations cannot find the CLI."
    echo "Add this to ~/.zshrc and open a new terminal:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac

# Without the overlay there is no palette and no stop key, and a person who
# installed the tool has no way to know that from the outside.
echo
# mktemp rather than a fixed name in /tmp: the log is world readable there and
# two accounts installing on one machine would write to each other's file.
build_log="$(mktemp -t rf-overlay-build)"
trap 'rm -f "$build_log"' EXIT
if "$REPO/overlay/build.sh" > "$build_log" 2>&1; then
  echo "  $REPO/bin/rf-overlay"
else
  echo "The overlay did not build, so there are no annotations, no palette and"
  echo "no stop key. Everything else works."
  echo "  command: $REPO/overlay/build.sh"
  sed 's/^/    /' "$build_log"
fi

echo
echo "Check the machine with: recordfeedback doctor"
