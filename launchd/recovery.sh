#!/bin/zsh
set -euo pipefail

echo "=== 杭州保障房 LaunchAgent 恢复 ==="

SOURCE="/Users/buyecho/Documents/关注杭州配售型保障性住房的最新消息"
RUNTIME="$HOME/.local/share/hangzhou_housing_monitor"
LABEL="com.local.hangzhou.housing.monitor"
MANUAL_LABEL="$LABEL.manual"
PLIST_MAIN="$HOME/Library/LaunchAgents/$LABEL.plist"
PLIST_MANUAL="$HOME/Library/LaunchAgents/$MANUAL_LABEL.plist"

# Step 1: Copy missing Python scripts to runtime
echo "[1/4] 部署缺失的 Python 脚本..."
cp "$SOURCE/launchd/run_codex_with_timeout.py" "$RUNTIME/launchd/run_codex_with_timeout.py"
cp "$SOURCE/launchd/reconcile_manual_run.py" "$RUNTIME/launchd/reconcile_manual_run.py"
chmod +x "$RUNTIME/launchd/run_codex_with_timeout.py" "$RUNTIME/launchd/reconcile_manual_run.py"

# Step 2: Copy updated run_monitor.sh to runtime
echo "[2/4] 部署更新后的 run_monitor.sh..."
cp "$SOURCE/launchd/run_monitor.sh" "$RUNTIME/launchd/run_monitor.sh"
chmod +x "$RUNTIME/launchd/run_monitor.sh"

# Step 3: Update plists to point to workspace run_monitor.sh
echo "[3/4] 更新 plist 指向工作区脚本..."
cp "$SOURCE/launchd/run_monitor.sh" "$RUNTIME/launchd/run_monitor.sh"
chmod +x "$RUNTIME/launchd/run_monitor.sh"

# Step 4: Clean stale lock
rmdir "$RUNTIME/state/run.lock" 2>/dev/null || true

# Step 5: Bootstrap both agents
echo "[4/4] 重新加载 LaunchAgent..."
launchctl bootstrap "gui/$(id -u)" "$PLIST_MAIN"
launchctl bootstrap "gui/$(id -u)" "$PLIST_MANUAL"
launchctl enable "gui/$(id -u)/$LABEL"
launchctl enable "gui/$(id -u)/$MANUAL_LABEL"

# Verify
echo ""
echo "=== 验证 ==="
launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | rg 'state =|runs =' || echo "WARN: Main agent 未加载"
launchctl print "gui/$(id -u)/$MANUAL_LABEL" 2>/dev/null | rg 'state =|runs =' || echo "WARN: Manual agent 未加载"
ls -la "$RUNTIME/launchd/"*.py 2>/dev/null || echo "WARN: Python 脚本仍缺失"
echo ""
echo "=== 恢复完成 ==="
