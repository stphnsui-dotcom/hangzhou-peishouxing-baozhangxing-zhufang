#!/bin/zsh

set -u

ROOT="$HOME/.local/share/hangzhou_housing_monitor"
LABEL="com.local.hangzhou.housing.monitor"
MANUAL_LABEL="$LABEL.manual"
STATUS_FILE="$ROOT/state/latest-status.json"
LATEST_LOG="$ROOT/logs/latest.log"

print -r -- "CHECKED_AT=$(date '+%Y-%m-%dT%H:%M:%S%z')"

if launchctl print "gui/$(id -u)/$LABEL" >/tmp/hangzhou-housing-launchctl.txt 2>&1; then
  print -r -- "LAUNCH_AGENT=loaded"
  rg 'state =|last exit code =|runs =' /tmp/hangzhou-housing-launchctl.txt || true
else
  print -r -- "LAUNCH_AGENT=not_loaded"
  cat /tmp/hangzhou-housing-launchctl.txt
fi

if launchctl print "gui/$(id -u)/$MANUAL_LABEL" >/tmp/hangzhou-housing-manual-launchctl.txt 2>&1; then
  print -r -- "MANUAL_AGENT=loaded"
  rg 'state =|last exit code =|runs =' /tmp/hangzhou-housing-manual-launchctl.txt || true
else
  print -r -- "MANUAL_AGENT=not_loaded"
  cat /tmp/hangzhou-housing-manual-launchctl.txt
fi

if [[ -f "$STATUS_FILE" ]]; then
  print -r -- "LATEST_STATUS_FILE=$STATUS_FILE"
  cat "$STATUS_FILE"
else
  print -r -- "LATEST_STATUS_FILE=missing"
fi

pending_count=$(
  /usr/bin/python3 - "$ROOT/.mail-outbox" <<'PY'
import json
import sys
from pathlib import Path

count = 0
for path in Path(sys.argv[1]).glob("*.json"):
    data = json.loads(path.read_text(encoding="utf-8"))
    count += data.get("status") != "sent"
print(count)
PY
)
print -r -- "OUTBOX_PENDING=$pending_count"

if [[ -f "$LATEST_LOG" ]]; then
  print -r -- "LATEST_LOG_TAIL=$LATEST_LOG"
  tail -n 40 "$LATEST_LOG"
else
  print -r -- "LATEST_LOG=missing"
fi
