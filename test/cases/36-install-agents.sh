# The installer exposes the same workflow to Claude Code and Codex.
. "$REPO/test/lib.sh"

bin_dir="$RF_CASE_TMP/bin"
claude_dir="$RF_CASE_TMP/claude-commands"
skills_dir="$RF_CASE_TMP/agent-skills"

out="$(
  RF_BIN_DIR="$bin_dir" \
  RF_COMMANDS_DIR="$claude_dir" \
  RF_SKILLS_DIR="$skills_dir" \
  "$REPO/install.sh"
)"

assert_contains "$out" "$claude_dir/recordfeedback.md" "installer output"
assert_contains "$out" "$skills_dir/recordfeedback" "installer output"

[ -L "$bin_dir/recordfeedback" ] || fail "recordfeedback CLI is not a symlink"
[ -L "$bin_dir/rfb" ] || fail "rfb CLI is not a symlink"
[ -L "$claude_dir/recordfeedback.md" ] || fail "Claude command is not a symlink"
[ -L "$skills_dir/recordfeedback" ] || fail "Codex skill is not a symlink"

assert_eq "$(readlink "$skills_dir/recordfeedback")" \
  "$REPO/skills/recordfeedback" \
  "Codex skill points at the wrong directory"
assert_file "$skills_dir/recordfeedback/SKILL.md"
