# obsidian-email-summarizer

A daily email digest for Obsidian, powered by macOS Mail.app and any LLM CLI.

Fetches emails from all your Mail.app accounts via AppleScript, summarizes them with your choice of LLM, and writes a markdown summary to your Obsidian vault.

```
Mail.app (AppleScript) → LLM (filter + summarize) → sources/email-summary-2026-03-24.md
```

## Requirements

- macOS with Mail.app configured (any accounts: Gmail, iCloud, Outlook, etc.)
- An LLM CLI tool (see [Supported LLM tools](#supported-llm-tools) below)
- Full Disk Access for Terminal (System Settings > Privacy & Security)

## Quick Start

```bash
git clone https://github.com/youruser/obsidian-email-summarizer.git
cd obsidian-email-summarizer

# Check dependencies and list your Mail.app accounts
./install.sh

# Edit configuration
$EDITOR .env

# Run it
./summarize-email.sh
```

Then link from your Obsidian daily note:

```
[[email-summary-2026-03-24|Email Summary]]
```

## Configuration

Edit `.env` (created by `install.sh` from `.env.example`):

| Variable | Default | Description |
|---|---|---|
| `MAIL_ACCOUNTS` | *(required)* | Comma-separated Mail.app account names |
| `MAIL_SINCE_DAYS` | `1` | How many days back to look |
| `VAULT_PATH` | *(required)* | Absolute path to your Obsidian vault |
| `SOURCES_DIR` | `sources` | Output subdirectory within the vault |
| `LLM_CMD` | Claude Sonnet | LLM command (see below) |

To find your account names, run `./install.sh` — it lists all Mail.app accounts.

## Supported LLM tools

Set `LLM_CMD` in `.env`. The command must read a prompt from **stdin** and write the summary to **stdout**.

**Claude Code** (default):
```bash
LLM_CMD="claude -p --model claude-sonnet-4-6 --effort high --no-session-persistence"
```

**Claude Code (faster, cheaper)**:
```bash
LLM_CMD="claude -p --model claude-haiku-4-5-20251001 --effort medium --no-session-persistence"
```

**OpenAI Codex CLI**:
```bash
LLM_CMD="codex e -m gpt-5.4-mini --skip-git-repo-check --ephemeral -o /dev/stdout"
```

Any CLI that reads from stdin and writes to stdout will work.

## Output

Each run produces a file like `sources/email-summary-2026-03-24.md`:

```markdown
# Email Summary - 2026-03-24

> 35 email(s) processed from: Work,Personal.

## Work

**Project deadline moved** — manager@company.com
Sprint deadline pushed to Friday. Updated tickets are in Jira.

**Quarterly review scheduled** — hr@company.com
Performance review scheduled for April 2 at 2pm. Pre-fill self-assessment form beforehand.

## Personal

**Flight confirmation** — noreply@airline.com
Round trip to Denver confirmed for April 10-13. Confirmation code: ABC123.

## Action Items

- [ ] Complete self-assessment form before April 2
- [ ] Review updated sprint tickets in Jira
```

## How It Works

1. **Fetch**: A single AppleScript call retrieves recent emails from all configured accounts using Mail.app's `whose date received` filter (fast, server-side filtering)
2. **Sanitize**: Control characters are stripped from email content
3. **Summarize**: All emails are sent to the LLM in a single pass — it filters out spam/newsletters and summarizes the rest with action items
4. **Write**: The summary is saved as a dated markdown file in your vault's `sources/` directory

Edit `prompts/summarize.txt` to tune what gets filtered and how summaries are formatted.

The script is idempotent — running it twice in one day overwrites the same file. It auto-detects inbox naming differences between Gmail (`INBOX`) and Exchange/Outlook (`Inbox`).

## Automation

### launchd (recommended)

Create `~/Library/LaunchAgents/com.user.email-summarizer.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.email-summarizer</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/obsidian-email-summarizer/summarize-email.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>7</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/email-summarizer.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/email-summarizer.log</string>
</dict>
</plist>
```

Load it:

```bash
launchctl load ~/Library/LaunchAgents/com.user.email-summarizer.plist
```

### cron

```bash
crontab -e
# Add:
0 7 * * * /path/to/summarize-email.sh >> /tmp/email-summarizer.log 2>&1
```

Note: launchd handles macOS sleep/wake better than cron.

## Troubleshooting

**"Could not access Mail.app"**
Grant Full Disk Access to Terminal in System Settings > Privacy & Security > Full Disk Access.

**No emails found**
Check your account names match exactly (run `./install.sh` to list them) and that `MAIL_SINCE_DAYS` covers a recent enough window.

**Empty summary**
Ensure your LLM CLI is authenticated (e.g., run `claude` interactively first, or check your API key for codex).

## License

MIT
