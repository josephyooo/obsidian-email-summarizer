#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# obsidian-email-summarizer
# Fetches emails via AppleScript, summarizes with an LLM, writes to Obsidian.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# --- Phase 0: Configuration ---

# Source .env but don't override already-set env vars
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  while IFS='=' read -r key val; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    val="${val%\"}" && val="${val#\"}"  # strip quotes
    [[ -z "${!key:-}" ]] && export "$key=$val"
  done < "$SCRIPT_DIR/.env"
fi

MAIL_ACCOUNTS="${MAIL_ACCOUNTS:?Error: MAIL_ACCOUNTS is required in .env}"
MAIL_SINCE_DAYS="${MAIL_SINCE_DAYS:-1}"
VAULT_PATH="${VAULT_PATH:?Error: VAULT_PATH is required in .env}"
SOURCES_DIR="${SOURCES_DIR:-sources}"
LLM_CMD="${LLM_CMD:-claude -p --model claude-haiku-4-5-20251001 --effort medium --no-session-persistence < {input} > {output}}"

TODAY="$(date +%Y-%m-%d)"
OUTPUT_DIR="$VAULT_PATH/$SOURCES_DIR"
OUTPUT_FILE="$OUTPUT_DIR/email-summary-$TODAY.md"

# --- Phase 1: Preflight checks ---

llm_bin="$(echo "$LLM_CMD" | awk '{print $1}')"
for cmd in "$llm_bin" python3; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: '$cmd' not found in PATH." >&2
    exit 1
  fi
done

if [[ ! -d "$VAULT_PATH" ]]; then
  echo "Error: Vault path does not exist: $VAULT_PATH" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# --- Phase 2: Fetch emails via AppleScript ---

echo "Fetching emails from last $MAIL_SINCE_DAYS day(s)..."

# Build AppleScript account list
IFS=',' read -ra accounts <<< "$MAIL_ACCOUNTS"
as_accounts=""
for a in "${accounts[@]}"; do
  a="$(echo "$a" | xargs)"
  as_accounts="${as_accounts}\"${a}\", "
done
as_accounts="{${as_accounts%, }}"

# Single AppleScript call: fetch headers + content for all accounts
# Uses 'whose date received' for fast server-side filtering
osascript -e "
tell application \"Mail\"
  set cutoff to (current date) - ${MAIL_SINCE_DAYS} * days
  set output to \"\"
  set accts to ${as_accounts}
  repeat with acctName in accts
    set acct to account acctName
    -- auto-detect inbox name (Gmail=INBOX, Exchange=Inbox)
    set mbox to missing value
    repeat with mb in mailboxes of acct
      if name of mb is \"INBOX\" or name of mb is \"Inbox\" then
        set mbox to mb
        exit repeat
      end if
    end repeat
    if mbox is missing value then
      -- skip account if no inbox found
    else
      set msgs to (messages of mbox whose date received > cutoff)
      repeat with m in msgs
        set subj to subject of m
        set sndr to sender of m
        set dt to date received of m as string
        set cont to content of m
        if length of cont > 2000 then
          set cont to text 1 thru 2000 of cont
        end if
        set output to output & \"ACCOUNT:\" & acctName & \"\\nFROM:\" & sndr & \"\\nSUBJECT:\" & subj & \"\\nDATE:\" & dt & \"\\nCONTENT:\" & cont & \"\\n---END---\\n\"
      end repeat
    end if
  end repeat
  return output
end tell" 2>/dev/null > "$tmpdir/raw_emails.txt"

# Sanitize control characters from email content
LC_ALL=C tr -cd '[:print:][:space:]' < "$tmpdir/raw_emails.txt" > "$tmpdir/clean_emails.txt"

email_count="$(grep -c '^---END---$' "$tmpdir/clean_emails.txt" || echo 0)"

if [[ "$email_count" -eq 0 ]]; then
  echo "No emails found. Nothing to summarize."
  exit 0
fi

echo "Found $email_count email(s)."

# --- Phase 3: Summarize ---

echo "Summarizing with: $(echo "$LLM_CMD" | awk '{print $1}')"

cat "$SCRIPT_DIR/prompts/summarize.txt" "$tmpdir/clean_emails.txt" > "$tmpdir/prompt.txt"

llm_cmd="${LLM_CMD//\{input\}/$tmpdir/prompt.txt}"
llm_cmd="${llm_cmd//\{output\}/$tmpdir/response.txt}"
eval "$llm_cmd"
summary="$(cat "$tmpdir/response.txt")"

# --- Phase 4: Write output ---

{
  echo "# Email Summary - $TODAY"
  echo ""
  echo "> $email_count email(s) processed from: ${MAIL_ACCOUNTS}."
  echo ""
  echo "$summary"
} > "$OUTPUT_FILE"

# --- Phase 5: Report ---

echo ""
echo "Done! Summary written to:"
echo "  $OUTPUT_FILE"
echo ""
echo "Link from your daily note with:"
echo "  [[email-summary-$TODAY|Email Summary]]"
