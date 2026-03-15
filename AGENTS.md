# AGENTS.md — Instructions for AI Assistants

This file tells AI coding agents (OpenClaw, Claude Code, Codex, etc.) how to set up and work with ClawDoc.

## What ClawDoc Is

ClawDoc is an OpenClaw companion app — a self-hosted Telegram bot that monitors, diagnoses, and fixes OpenClaw when it goes down. It runs independently as its own process so it survives when OpenClaw dies.

**Key properties:**
- Single Python file (`clawdoc.py`), stdlib only (no pip dependencies for core)
- Config: `~/.config/clawdoc/config.json`
- Runs as launchd service (Mac: `io.clawdoc.agent`) or systemd user service (Linux: `clawdoc`)
- Uses local Ollama for AI-powered diagnostics (default: `qwen3.5:4b`)
- Shell access disabled by default — requires machine access to enable

## Setting Up ClawDoc (Agent Instructions)

### Option 1: Interactive installer (preferred)

```bash
curl -fsSL https://raw.githubusercontent.com/rungmc357/clawdoc/main/install.sh | bash
```

The installer will:
- Install ClawDoc and detect the system
- Set up Ollama (detect existing models or pull the default)
- Auto-detect OpenClaw and add it to the watchdog
- Install as a background service (launchd/systemd)
- Ask the user for their Telegram bot token and chat ID (with instructions)
- Start the service and send a confirmation message

**Note for AI agents:** The installer needs the user to provide a Telegram bot token. You can't create one — tell the user to message @BotFather on Telegram (`/newbot`) and @userinfobot for their chat ID, then paste both when prompted.

### Option 2: Write config directly

If the user already has a bot token and chat ID:

```bash
mkdir -p ~/.config/clawdoc ~/.config/clawdoc/backups ~/.local/log

cat > ~/.config/clawdoc/config.json <<'EOF'
{
  "bot_token": "BOT_TOKEN_HERE",
  "allowed_chat_id": CHAT_ID_HERE,
  "ollama_model": "qwen3.5:4b",
  "ollama_url": "http://localhost:11434",
  "shell_security": "disabled",
  "shell_password_hash": "",
  "watchdog_interval_min": 15,
  "transcription": "auto",
  "log_file": "~/.local/log/clawdoc.log",
  "skills_file": "~/.config/clawdoc/skills.json",
  "backup_dir": "~/.config/clawdoc/backups",
  "watched_services": [
    {
      "name": "OpenClaw",
      "url": "http://localhost:18789/health",
      "restart_cmd": "openclaw gateway restart",
      "log_file": "~/.openclaw/logs/gateway.log",
      "config_files": ["~/.openclaw/openclaw.json"]
    }
  ]
}
EOF
```

Then clone and install as a service:

```bash
git clone https://github.com/rungmc357/clawdoc.git ~/.local/share/clawdoc

# Mac (launchd):
cat > ~/Library/LaunchAgents/io.clawdoc.agent.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>io.clawdoc.agent</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/python3</string>
    <string>/Users/YOUR_USER/.local/share/clawdoc/clawdoc.py</string>
    <string>--config</string>
    <string>~/.config/clawdoc/config.json</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>~/.local/log/clawdoc.log</string>
  <key>StandardErrorPath</key><string>~/.local/log/clawdoc.err.log</string>
</dict>
</plist>
EOF
launchctl load ~/Library/LaunchAgents/io.clawdoc.agent.plist

# Linux (systemd):
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/clawdoc.service <<'EOF'
[Unit]
Description=ClawDoc - OpenClaw Companion
After=network.target
[Service]
ExecStart=/usr/bin/python3 ~/.local/share/clawdoc/clawdoc.py --config ~/.config/clawdoc/config.json
Restart=always
RestartSec=10
[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now clawdoc
```

## Important: Add OpenClaw to Watchdog

Always configure OpenClaw as a watched service with `config_files` for automatic backup and rollback:

```json
{
  "name": "OpenClaw",
  "url": "http://localhost:18789/health",
  "restart_cmd": "openclaw gateway restart",
  "log_file": "~/.openclaw/logs/gateway.log",
  "config_files": ["~/.openclaw/openclaw.json"]
}
```

The `config_files` field enables automatic config snapshots on every ClawDoc startup. If an OpenClaw auto-update breaks the config, ClawDoc detects the invalid JSON, restores from the latest backup, restarts, and notifies the user.

## Checking ClawDoc Status

```bash
# Mac
launchctl list io.clawdoc.agent

# Linux
systemctl --user status clawdoc

# Logs
tail -50 ~/.local/log/clawdoc.log
tail -50 ~/.local/log/clawdoc.err.log
```

## Restarting ClawDoc

```bash
# Mac
launchctl kickstart -k gui/$(id -u)/io.clawdoc.agent

# Linux
systemctl --user restart clawdoc
```

## Shell Access Security

Shell access is disabled by default. To enable after installation:

```bash
# Enable with password protection
python3 ~/.local/share/clawdoc/clawdoc.py --enable-shell password

# Enable with tap-to-approve (no password)
python3 ~/.local/share/clawdoc/clawdoc.py --enable-shell open

# Change password
python3 ~/.local/share/clawdoc/clawdoc.py --set-password

# Disable
python3 ~/.local/share/clawdoc/clawdoc.py --enable-shell disabled
```

Users can also enable shell access from Telegram: type `/run`, then run the activation command shown on their terminal.

## Installing Ollama (if missing)

```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama pull qwen3.5:4b
```

Larger models for more capable machines:
- `qwen3.5:4b` — default, ~2.5GB, works on almost anything
- `qwen3.5:9b` — better reasoning, ~6GB
- `qwen3.5:27b` — very capable, needs 16GB+ RAM

## Development

The main bot logic lives in `clawdoc.py`. It's intentionally a single file with no required pip dependencies. Keep it that way — the zero-dependency constraint is a feature.

When making changes:
1. Test locally: `python3 clawdoc.py --config ~/.config/clawdoc/config.json`
2. Commit to `main`
3. Users update via `/update` command in Telegram or by re-running `install.sh`
