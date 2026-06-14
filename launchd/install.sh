#!/bin/zsh

set -euo pipefail

SOURCE_ROOT="/Users/buyecho/Documents/关注杭州配售型保障性住房的最新消息"
RUNTIME_ROOT="$HOME/.local/share/hangzhou_housing_monitor"
LABEL="com.local.hangzhou.housing.monitor"
MANUAL_LABEL="$LABEL.manual"
PLIST_SOURCE="$SOURCE_ROOT/launchd/$LABEL.plist"
PLIST_TARGET="$HOME/Library/LaunchAgents/$LABEL.plist"
MANUAL_PLIST_SOURCE="$SOURCE_ROOT/launchd/$MANUAL_LABEL.plist"
MANUAL_PLIST_TARGET="$HOME/Library/LaunchAgents/$MANUAL_LABEL.plist"
LEGACY_CONFIG="$HOME/.codex/automations/automation/automation.toml"
LEGACY_MEMORY="$HOME/.codex/automations/automation/memory.md"
SECRET_DIR="$RUNTIME_ROOT/.secrets"
SECRET_FILE="$SECRET_DIR/qq_smtp_auth_code"
SOURCE_SECRET="$SOURCE_ROOT/.secrets/qq_smtp_auth_code"

mkdir -p \
  "$RUNTIME_ROOT/launchd" \
  "$RUNTIME_ROOT/logs" \
  "$RUNTIME_ROOT/state" \
  "$RUNTIME_ROOT/.mail-outbox" \
  "$SECRET_DIR" \
  "$HOME/Library/LaunchAgents"
chmod 700 "$SECRET_DIR"

cp "$SOURCE_ROOT/send_qq_email.py" "$RUNTIME_ROOT/send_qq_email.py"
cp "$SOURCE_ROOT/launchd/run_monitor.sh" "$RUNTIME_ROOT/launchd/run_monitor.sh"
cp "$SOURCE_ROOT/launchd/health_check.sh" "$RUNTIME_ROOT/launchd/health_check.sh"
cp "$SOURCE_ROOT/launchd/monitor_prompt.md" "$RUNTIME_ROOT/launchd/monitor_prompt.md"
cp "$SOURCE_ROOT/launchd/manual_prompt.md" "$RUNTIME_ROOT/launchd/manual_prompt.md"
cp "$SOURCE_ROOT/launchd/run_codex_with_timeout.py" "$RUNTIME_ROOT/launchd/run_codex_with_timeout.py"
cp "$SOURCE_ROOT/launchd/reconcile_manual_run.py" "$RUNTIME_ROOT/launchd/reconcile_manual_run.py"
chmod +x \
  "$RUNTIME_ROOT/launchd/run_monitor.sh" \
  "$RUNTIME_ROOT/launchd/health_check.sh" \
  "$RUNTIME_ROOT/launchd/run_codex_with_timeout.py" \
  "$RUNTIME_ROOT/launchd/reconcile_manual_run.py" \
  "$RUNTIME_ROOT/send_qq_email.py"

if [[ -d "$SOURCE_ROOT/.mail-outbox" ]]; then
  cp -n "$SOURCE_ROOT/.mail-outbox/"* "$RUNTIME_ROOT/.mail-outbox/" 2>/dev/null || true
fi

if [[ ! -s "$RUNTIME_ROOT/state/monitor-memory.md" && -r "$LEGACY_MEMORY" ]]; then
  cp "$LEGACY_MEMORY" "$RUNTIME_ROOT/state/monitor-memory.md"
fi

if [[ ! -s "$SECRET_FILE" && -s "$SOURCE_SECRET" ]]; then
  cp "$SOURCE_SECRET" "$SECRET_FILE"
fi

if [[ ! -s "$SECRET_FILE" && -r "$LEGACY_CONFIG" ]]; then
  /usr/bin/python3 - "$LEGACY_CONFIG" "$SECRET_FILE" <<'PY'
import re
import sys
from pathlib import Path

source, target = map(Path, sys.argv[1:])
match = re.search(
    r"授权码[：:]\s*([A-Za-z0-9]+)",
    source.read_text(encoding="utf-8"),
)
if not match:
    raise SystemExit("Could not migrate QQ SMTP authorization code")
target.write_text(match.group(1) + "\n", encoding="utf-8")
PY
fi

if [[ ! -s "$SECRET_FILE" ]]; then
  print -u2 -r -- "QQ SMTP authorization code is missing"
  exit 1
fi
chmod 600 "$SECRET_FILE"

plutil -lint "$PLIST_SOURCE"
plutil -lint "$MANUAL_PLIST_SOURCE"
cp "$PLIST_SOURCE" "$PLIST_TARGET"
cp "$MANUAL_PLIST_SOURCE" "$MANUAL_PLIST_TARGET"
chmod 600 "$PLIST_TARGET"
chmod 600 "$MANUAL_PLIST_TARGET"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$MANUAL_LABEL" 2>/dev/null || true
rmdir "$RUNTIME_ROOT/state/run.lock" 2>/dev/null || true
/usr/bin/python3 "$RUNTIME_ROOT/launchd/reconcile_manual_run.py"
launchctl bootstrap "gui/$(id -u)" "$PLIST_TARGET"
launchctl bootstrap "gui/$(id -u)" "$MANUAL_PLIST_TARGET"
launchctl enable "gui/$(id -u)/$LABEL"
launchctl enable "gui/$(id -u)/$MANUAL_LABEL"

launchctl print "gui/$(id -u)/$LABEL"
launchctl print "gui/$(id -u)/$MANUAL_LABEL"
