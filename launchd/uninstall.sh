#!/bin/zsh

set -euo pipefail

LABEL="com.local.hangzhou.housing.monitor"
MANUAL_LABEL="$LABEL.manual"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
MANUAL_PLIST="$HOME/Library/LaunchAgents/$MANUAL_LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$MANUAL_LABEL" 2>/dev/null || true
rm -f "$PLIST"
rm -f "$MANUAL_PLIST"

print -r -- "Runtime data retained at $HOME/.local/share/hangzhou_housing_monitor"
