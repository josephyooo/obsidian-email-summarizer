#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== obsidian-email-summarizer setup ==="
echo ""

# --- Check dependencies ---

if command -v python3 &>/dev/null; then
  echo "[ok] python3 is installed: $(python3 --version 2>&1)"
else
  echo "[!!] python3 not found." >&2
  exit 1
fi

# Check for an LLM CLI (at least one should be available)
found_llm=false
for cmd in claude codex pi; do
  if command -v "$cmd" &>/dev/null; then
    echo "[ok] $cmd is installed."
    found_llm=true
  fi
done
if [[ "$found_llm" == "false" ]]; then
  echo "[!!] No LLM CLI found. Install one of: claude, codex, or pi." >&2
  exit 1
fi

# --- Set up .env ---

if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
  echo ""
  echo "[ok] Created .env from template. Edit it now:"
  echo "  $SCRIPT_DIR/.env"
else
  echo "[ok] .env already exists."
fi

# --- Verify Mail.app access ---

echo ""
echo "Testing Mail.app access via AppleScript..."
if osascript -e 'tell application "Mail" to get name of accounts' &>/dev/null; then
  echo "[ok] Mail.app is accessible. Available accounts:"
  osascript -e 'tell application "Mail"
    set output to ""
    repeat with a in accounts
      set output to output & "  - " & name of a & " (" & email addresses of a & ")" & "\n"
    end repeat
    return output
  end tell' 2>/dev/null
else
  echo "[!!] Could not access Mail.app."
  echo "     Grant Full Disk Access to Terminal in:"
  echo "     System Settings > Privacy & Security > Full Disk Access"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit .env with your account names and vault path"
echo "  2. Run: ./summarize-email.sh"
