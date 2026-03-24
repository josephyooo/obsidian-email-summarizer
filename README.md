# obsidian-email-summarizer

A daily email digest for Obsidian, powered by macOS Mail.app and Claude.

Fetches emails from all your Mail.app accounts via [`mail-app-cli`](https://github.com/intelligrit/mail-app-cli), screens them for relevance, summarizes with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) in headless mode, and writes a markdown summary to your Obsidian vault.

```
mail-app-cli → claude -p (screen) → claude -p (summarize) → sources/email-summary-2026-03-24.md
```

## Requirements

- macOS with Mail.app configured (any accounts: Gmail, iCloud, Outlook, etc.)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- [Go](https://go.dev/) (for building mail-app-cli)
- [jq](https://jqlang.github.io/jq/) (likely already installed on macOS)
- Full Disk Access for Terminal (System Settings > Privacy & Security)

## Quick Start

```bash
git clone https://github.com/youruser/obsidian-email-summarizer.git
cd obsidian-email-summarizer

# Install dependencies (Go, mail-app-cli)
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
| `MAIL_MAILBOX` | `INBOX` | Mailbox to fetch from (auto-detects `Inbox` for Exchange) |
| `MAIL_SINCE_DAYS` | `1` | How many days back to look |
| `VAULT_PATH` | *(required)* | Absolute path to your Obsidian vault |
| `SOURCES_DIR` | `sources` | Output subdirectory within the vault |
| `CLAUDE_MODEL` | `haiku` | Claude model (`haiku`, `sonnet`, `opus`) |
| `CLAUDE_MAX_BUDGET` | `0.50` | Max spend per run in USD (omit to disable) |

To find your account names:

```bash
mail-app-cli accounts list
```

## Output

Each run produces a file like `sources/email-summary-2026-03-24.md`:

```markdown
# Email Summary - 2026-03-24

> 12 of 35 email(s) summarized from: Work,Personal.

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

The script uses a **two-pass approach** to keep costs low and summaries focused:

1. **Fetch headers**: `mail-app-cli` lists recent emails from all accounts (fast, no content)
2. **Screen** (pass 1): Subject lines and senders are sent to `claude -p`, which returns IDs of emails worth reading — filtering out marketing, newsletters, OTPs, and spam
3. **Fetch content**: Only selected emails have their full body fetched via `mail-app-cli messages show`
4. **Summarize** (pass 2): Full email content is sent to `claude -p` with the summarization prompt
5. **Write**: The summary is saved as a dated markdown file in your vault's `sources/` directory

The screening prompts live in `prompts/screen.txt` and `prompts/summarize.txt` — edit them to tune what gets included and how summaries are formatted.

The script is idempotent — running it twice in one day overwrites the same file. It also auto-detects inbox naming differences between Gmail (`INBOX`) and Exchange/Outlook (`Inbox`).

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
        <string>/Users/you/Projects/obsidian-email-summarizer/summarize-email.sh</string>
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

**"mail-app-cli not found"**
Run `./install.sh` or ensure `~/go/bin` is in your PATH.

**"Could not access Mail.app"**
Grant Full Disk Access to Terminal in System Settings > Privacy & Security > Full Disk Access.

**No emails found**
Check your account names match exactly (`mail-app-cli accounts list`) and that `MAIL_SINCE_DAYS` covers a recent enough window.

**Claude errors**
Ensure the Claude CLI is authenticated (`claude` in interactive mode first).

## License

MIT
