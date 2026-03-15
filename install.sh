#!/bin/bash
# ClawDoc installer — sets up the companion app as a background service
set -e

REPO="https://github.com/rungmc357/clawdoc"
INSTALL_DIR="$HOME/.local/share/clawdoc"
CONFIG_DIR="$HOME/.config/clawdoc"
LOG_DIR="$HOME/.local/log"

echo "🔧 ClawDoc Installer"
echo "================================"

# --- Detect OS ---
OS="$(uname -s)"
if [[ "$OS" != "Darwin" && "$OS" != "Linux" ]]; then
  echo "❌ Unsupported OS: $OS"
  exit 1
fi

# --- Check Python 3 ---
if ! command -v python3 &>/dev/null; then
  echo "❌ Python 3 is required. Install it and try again."
  exit 1
fi

# --- Check/install git ---
if ! command -v git &>/dev/null; then
  echo "❌ git is required. Install it and try again."
  exit 1
fi

# --- Create dirs ---
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$CONFIG_DIR/backups" "$LOG_DIR"

# --- Clone/update repo ---
if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "📦 Updating ClawDoc..."
  git -C "$INSTALL_DIR" pull --quiet
else
  echo "📦 Installing ClawDoc..."
  git clone --quiet "$REPO" "$INSTALL_DIR"
fi

# --- Config setup ---
if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
  echo ""
  echo "⚙️  Setting up ClawDoc..."
  echo ""
  echo "I just need one thing: a Telegram bot token."
  echo ""
  echo "  1. Open Telegram and message @BotFather"
  echo "     → https://t.me/BotFather"
  echo "  2. Send /newbot and follow the prompts"
  echo "  3. Copy the token it gives you"
  echo ""
  read -p "Paste your bot token: " BOT_TOKEN </dev/tty

  # Generate claim code
  CLAIM_CODE=$(python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_uppercase + string.digits) for _ in range(6)))")

  # Auto-detect OpenClaw
  WATCHED_SERVICES="[]"
  if command -v openclaw &>/dev/null || [[ -f "$HOME/.openclaw/openclaw.json" ]]; then
    echo ""
    echo "🔍 OpenClaw detected! Adding to watchdog automatically."
    # Detect custom port from OpenClaw config
    OC_PORT=18789
    if [[ -f "$HOME/.openclaw/openclaw.json" ]]; then
      DETECTED_PORT=$(python3 -c "import json; c=json.load(open('$HOME/.openclaw/openclaw.json')); print(c.get('gateway',{}).get('port', c.get('port', 18789)))" 2>/dev/null)
      if [[ -n "$DETECTED_PORT" && "$DETECTED_PORT" != "None" ]]; then
        OC_PORT="$DETECTED_PORT"
      fi
    fi
    WATCHED_SERVICES="[{\"name\":\"OpenClaw\",\"url\":\"http://localhost:${OC_PORT}/health\",\"restart_cmd\":\"openclaw gateway restart\",\"interval_min\":15,\"log_file\":\"~/.openclaw/logs/gateway.log\",\"config_files\":[\"~/.openclaw/openclaw.json\"]}]"
  fi

  cat > "$CONFIG_DIR/config.json" <<EOF
{
  "bot_token": "$BOT_TOKEN",
  "allowed_chat_id": null,
  "claim_code": "$CLAIM_CODE",
  "ollama_model": "qwen3.5:4b",
  "ollama_url": "http://localhost:11434",
  "watchdog_interval_min": 15,
  "shell_security": "disabled",
  "shell_password_hash": "",
  "transcription": "auto",
  "log_file": "$LOG_DIR/clawdoc.log",
  "skills_file": "$CONFIG_DIR/skills.json",
  "backup_dir": "$CONFIG_DIR/backups",
  "watched_services": $WATCHED_SERVICES
}
EOF
  echo "✅ Config saved"
else
  echo "✅ Config already exists, skipping."
fi

# --- Note about Ollama ---
if ! command -v ollama &>/dev/null; then
  echo ""
  echo "ℹ️  Ollama not found. AI chat is optional — all buttons and"
  echo "   commands work without it. Install later: https://ollama.com"
fi

# --- Install as service ---
echo ""
echo "🚀 Installing as background service..."

if [[ "$OS" == "Darwin" ]]; then
  PLIST="$HOME/Library/LaunchAgents/io.clawdoc.agent.plist"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>io.clawdoc.agent</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(command -v python3)</string>
    <string>$INSTALL_DIR/clawdoc.py</string>
    <string>--config</string>
    <string>$CONFIG_DIR/config.json</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/clawdoc.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/clawdoc.err.log</string>
</dict>
</plist>
EOF
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
  echo "✅ Installed as launchd service (io.clawdoc.agent)"
else
  SYSTEMD_DIR="$HOME/.config/systemd/user"
  mkdir -p "$SYSTEMD_DIR"
  cat > "$SYSTEMD_DIR/clawdoc.service" <<EOF
[Unit]
Description=ClawDoc — OpenClaw Companion
After=network.target

[Service]
ExecStart=$(command -v python3) $INSTALL_DIR/clawdoc.py --config $CONFIG_DIR/config.json
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/clawdoc.log
StandardError=append:$LOG_DIR/clawdoc.err.log

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now clawdoc
  echo "✅ Installed as systemd user service (clawdoc)"
fi

echo ""
echo "================================"
echo "✅ ClawDoc is running!"
echo ""
echo "Now message your bot on Telegram with this claim code:"
echo ""
echo "  📋 $CLAIM_CODE"
echo ""
echo "This links your Telegram account to ClawDoc."
echo "Logs: $LOG_DIR/clawdoc.log"
echo ""
echo "To uninstall:"
if [[ "$OS" == "Darwin" ]]; then
  echo "  launchctl unload ~/Library/LaunchAgents/io.clawdoc.agent.plist"
else
  echo "  systemctl --user disable --now clawdoc"
fi
