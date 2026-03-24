#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== obsidian-email-summarizer setup ==="
echo ""

# --- Check/install Go ---

if command -v go &>/dev/null; then
  echo "[ok] Go is installed: $(go version)"
else
  echo "[..] Go not found. Installing via Homebrew..."
  if ! command -v brew &>/dev/null; then
    echo "Error: Homebrew not found. Install Go manually: https://go.dev/dl/" >&2
    exit 1
  fi
  brew install go
  echo "[ok] Go installed."
fi

# --- Install mail-app-cli ---

if command -v mail-app-cli &>/dev/null; then
  echo "[ok] mail-app-cli is installed."
else
  echo "[..] Installing mail-app-cli..."
  go install github.com/intelligrit/mail-app-cli@latest

  # Check if ~/go/bin is in PATH
  if ! command -v mail-app-cli &>/dev/null; then
    echo ""
    echo "mail-app-cli was installed to ~/go/bin/ but it's not in your PATH."
    echo "Add this to your ~/.zshrc:"
    echo ""
    echo '  export PATH="$HOME/go/bin:$PATH"'
    echo ""
    echo "Then restart your terminal or run: source ~/.zshrc"
    exit 1
  fi
  echo "[ok] mail-app-cli installed."
fi

# --- Check other dependencies ---

if command -v claude &>/dev/null; then
  echo "[ok] Claude CLI is installed."
else
  echo "[!!] Claude CLI not found. Install it: https://docs.anthropic.com/en/docs/claude-code" >&2
  exit 1
fi

if command -v jq &>/dev/null; then
  echo "[ok] jq is installed."
else
  echo "[!!] jq not found. Install it: brew install jq" >&2
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
echo "Testing mail-app-cli access to Mail.app..."
if mail-app-cli accounts list &>/dev/null; then
  echo "[ok] Mail.app is accessible. Available accounts:"
  mail-app-cli accounts list 2>/dev/null | jq -r '.[].name // .[].email // .'
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
