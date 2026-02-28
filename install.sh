#!/bin/bash
# Claude Code Statusline Installer
# Usage: bash install.sh

set -e

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Claude Code Statusline Installer ==="
echo ""

# 1. Check jq
if ! command -v jq &>/dev/null; then
  echo "[!] jq is required but not found."
  echo ""
  echo "Install jq for your platform:"
  echo "  macOS:          brew install jq"
  echo "  Ubuntu/Debian:  sudo apt install jq"
  echo "  Windows:        winget install jqlang.jq"
  echo "                  (then copy jq.exe to ~/bin/)"
  echo ""
  exit 1
fi
echo "[ok] jq found: $(jq --version)"

# 2. Copy script
mkdir -p "$CLAUDE_DIR"
cp "$SCRIPT_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh"
chmod +x "$CLAUDE_DIR/statusline.sh"
echo "[ok] statusline.sh installed to $CLAUDE_DIR/statusline.sh"

# 3. Update settings.json
if [ ! -f "$SETTINGS_FILE" ]; then
  echo '{}' > "$SETTINGS_FILE"
fi

# Check if statusLine is already configured
if jq -e '.statusLine' "$SETTINGS_FILE" &>/dev/null; then
  echo "[skip] statusLine already configured in settings.json"
else
  tmp=$(mktemp)
  jq '. + {"statusLine": {"type": "command", "command": "bash ~/.claude/statusline.sh"}}' "$SETTINGS_FILE" > "$tmp"
  mv "$tmp" "$SETTINGS_FILE"
  echo "[ok] statusLine added to $SETTINGS_FILE"
fi

echo ""
echo "=== Done! ==="
echo "Restart Claude Code and send a message to see the statusline."
echo ""
echo "Display example:"
echo "  🤖 Opus 4.6 │ 📊 71.0k/200.0k ███░░░░░░░ 36% 🟢 Good │ ⬇15.0k ⬆5.0k │ 💡残129.0k │ ⏳~42min │ 🔄0回"
echo "  🔥 1.2k/min │ 🕐 Daily:20.0k  🗓 Weekly:150.0k  📊 Monthly:500.0k"
