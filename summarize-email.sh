#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# obsidian-email-summarizer
# Fetches emails via mail-app-cli, summarizes with Claude, writes to Obsidian.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure go binaries and common paths are available (needed for cron/launchd)
export PATH="$HOME/go/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# --- Phase 0: Configuration ---

if [[ -f "$SCRIPT_DIR/.env" ]]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.env"
fi

MAIL_ACCOUNTS="${MAIL_ACCOUNTS:?Error: MAIL_ACCOUNTS is required in .env}"
MAIL_MAILBOX="${MAIL_MAILBOX:-INBOX}"
MAIL_SINCE_DAYS="${MAIL_SINCE_DAYS:-1}"
VAULT_PATH="${VAULT_PATH:?Error: VAULT_PATH is required in .env}"
SOURCES_DIR="${SOURCES_DIR:-sources}"
CLAUDE_MODEL="${CLAUDE_MODEL:-haiku}"
claude_args=(--model "$CLAUDE_MODEL" --no-session-persistence)
if [[ -n "${CLAUDE_MAX_BUDGET:-}" ]]; then
  claude_args+=(--max-budget-usd "$CLAUDE_MAX_BUDGET")
fi

TODAY="$(date +%Y-%m-%d)"
SINCE_DATE="$(date -v-"${MAIL_SINCE_DAYS}"d +%Y-%m-%d)"
OUTPUT_DIR="$VAULT_PATH/$SOURCES_DIR"
OUTPUT_FILE="$OUTPUT_DIR/email-summary-$TODAY.md"

# --- Phase 1: Preflight checks ---

for cmd in mail-app-cli claude jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: '$cmd' not found in PATH. Run install.sh or install it manually." >&2
    exit 1
  fi
done

if [[ ! -d "$VAULT_PATH" ]]; then
  echo "Error: Vault path does not exist: $VAULT_PATH" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# --- Phase 2: Fetch emails ---

echo "Fetching emails since $SINCE_DATE..."

all_headers="[]"
IFS=',' read -ra accounts <<< "$MAIL_ACCOUNTS"

for account in "${accounts[@]}"; do
  account="$(echo "$account" | xargs)"  # trim whitespace

  # Detect inbox name: Exchange/Outlook uses "Inbox", Gmail uses "INBOX"
  mailbox="$MAIL_MAILBOX"
  if [[ "$mailbox" == "INBOX" ]]; then
    mailbox="$(mail-app-cli mailboxes list -a "$account" 2>/dev/null \
      | jq -r '[.[].Name] | if index("INBOX") then "INBOX" elif index("Inbox") then "Inbox" else "INBOX" end')"
  fi

  echo "  Fetching from: $account / $mailbox"

  result="$(mail-app-cli messages list \
    -a "$account" \
    -m "$mailbox" \
    --since "$SINCE_DATE" \
    --limit 50 2>/dev/null || echo "[]")"

  msg_count="$(echo "$result" | jq 'length')"
  if [[ "$msg_count" -eq 0 ]]; then
    continue
  fi
  echo "    Found $msg_count message(s)."

  all_headers="$(echo "$all_headers" "$result" | jq -s '.[0] + .[1]')"
done

total_count="$(echo "$all_headers" | jq 'length')"

if [[ "$total_count" -eq 0 ]]; then
  echo "No emails found since $SINCE_DATE. Nothing to summarize."
  exit 0
fi

echo "Found $total_count email(s) total."

# --- Phase 3: Fetch content (parallel) ---

echo "Fetching content for $total_count email(s)..."

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

while IFS= read -r line; do
  msg_id="$(echo "$line" | jq -r '.ID')"
  account="$(echo "$line" | jq -r '.Account')"
  mailbox="$(echo "$line" | jq -r '.Mailbox')"

  ( mail-app-cli messages show "$msg_id" \
      -a "$account" -m "$mailbox" > "$tmpdir/$msg_id.json" 2>/dev/null || echo "{}" > "$tmpdir/$msg_id.json"
  ) &
done < <(echo "$all_headers" | jq -c '.[]')
wait

all_emails="$(jq -s '.' "$tmpdir"/*.json)"

# --- Phase 4: Format and summarize ---

# Truncate each email body to 2000 chars to balance summary quality vs cost
formatted="$(echo "$all_emails" | jq -r '
  .[] |
  (.Content // "(no body)") as $body |
  ($body | if length > 2000 then .[:2000] + "..." else . end) as $trimmed |
  "---\nFrom: \(.Sender // "unknown")\nSubject: \(.Subject // "no subject")\nDate: \(.DateReceived // .DateSent // "unknown")\nAccount: \(.Account // "unknown")\n\n\($trimmed)\n"
')"

echo "Summarizing with Claude ($CLAUDE_MODEL)..."

prompt="$(cat "$SCRIPT_DIR/prompts/summarize.txt")"

summary="$(printf '%s\n\n%s' "$prompt" "$formatted" | claude -p "${claude_args[@]}" 2>/dev/null)"

# --- Phase 5: Write output ---

{
  echo "# Email Summary - $TODAY"
  echo ""
  echo "> $total_count email(s) processed from: ${MAIL_ACCOUNTS}."
  echo ""
  echo "$summary"
} > "$OUTPUT_FILE"

# --- Phase 6: Report ---

echo ""
echo "Done! Summary written to:"
echo "  $OUTPUT_FILE"
echo ""
echo "Link from your daily note with:"
echo "  [[email-summary-$TODAY|Email Summary]]"
