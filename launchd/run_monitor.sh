#!/bin/zsh

set -u

ROOT="$HOME/.local/share/hangzhou_housing_monitor"
CODEX_BIN="/Applications/Codex.app/Contents/Resources/codex"
STATE_DIR="$ROOT/state"
LOG_DIR="$ROOT/logs"
LOCK_DIR="$STATE_DIR/run.lock"
MODE="${1:-scheduled}"
if [[ "$MODE" == "--force-email" ]]; then
  MODE="force-email"
  PROMPT_FILE="$ROOT/launchd/manual_prompt.md"
else
  MODE="scheduled"
  PROMPT_FILE="$ROOT/launchd/monitor_prompt.md"
fi
RUN_ID="$(date '+%Y%m%d-%H%M%S')"
RUN_LOG="$LOG_DIR/run-$RUN_ID.log"
LATEST_LOG="$LOG_DIR/latest.log"
SUMMARY_FILE="$STATE_DIR/latest-summary.txt"
STATUS_FILE="$STATE_DIR/latest-status.json"
RUN_PROMPT="$STATE_DIR/prompt-$RUN_ID.md"

mkdir -p "$STATE_DIR" "$LOG_DIR"

timestamp() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

write_status() {
  local result="$1"
  local exit_code="$2"
  /usr/bin/python3 - "$STATUS_FILE" "$result" "$exit_code" "$RUN_ID" "$RUN_LOG" "$MODE" <<'PY'
import json
import sys
from datetime import datetime
from pathlib import Path

path, result, exit_code, run_id, log_path, mode = sys.argv[1:]
payload = {
    "run_id": run_id,
    "finished_at": datetime.now().astimezone().isoformat(timespec="seconds"),
    "result": result,
    "exit_code": int(exit_code),
    "mode": mode,
    "log_path": log_path,
}
Path(path).write_text(
    json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR") ))
  if (( lock_age < 10800 )); then
    print -r -- "$(timestamp) SKIP_ALREADY_RUNNING lock_age_seconds=$lock_age" >> "$LATEST_LOG"
    exit 0
  fi
  rmdir "$LOCK_DIR" 2>/dev/null || {
    print -r -- "$(timestamp) ERROR_STALE_LOCK_UNREMOVABLE $LOCK_DIR" >> "$LATEST_LOG"
    exit 1
  }
  mkdir "$LOCK_DIR" || exit 1
fi
trap 'rm -f "$RUN_PROMPT" 2>/dev/null || true; rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM

exec > >(tee -a "$RUN_LOG" "$LATEST_LOG") 2>&1

print -r -- "$(timestamp) RUN_START id=$RUN_ID mode=$MODE"

if [[ ! -x "$CODEX_BIN" ]]; then
  print -r -- "$(timestamp) ERROR_CODEX_NOT_FOUND path=$CODEX_BIN"
  write_status "failed" 127
  exit 127
fi

if [[ ! -r "$PROMPT_FILE" ]]; then
  print -r -- "$(timestamp) ERROR_PROMPT_NOT_FOUND path=$PROMPT_FILE"
  write_status "failed" 66
  exit 66
fi

cd "$ROOT" || exit 1

cp "$PROMPT_FILE" "$RUN_PROMPT"
cat >> "$RUN_PROMPT" <<EOF

# 本次运行参数

- 运行模式：$MODE
- 唯一运行标识：$RUN_ID
- 邮件标题必须包含该运行标识对应的本地执行时间，确保用户每次手动点击都能收到本次独立结果。
EOF

print -r -- "$(timestamp) OUTBOX_DRAIN_START"
/usr/bin/python3 "$ROOT/send_qq_email.py" --drain
drain_exit=$?
print -r -- "$(timestamp) OUTBOX_DRAIN_END exit_code=$drain_exit"

TIMEOUT_WRAPPER="$ROOT/launchd/run_codex_with_timeout.py"
WORKSPACE_WRAPPER="/Users/buyecho/Documents/关注杭州配售型保障性住房的最新消息/launchd/run_codex_with_timeout.py"
[[ -f "$TIMEOUT_WRAPPER" ]] || TIMEOUT_WRAPPER="$WORKSPACE_WRAPPER"
if [[ -f "$TIMEOUT_WRAPPER" ]]; then
  /usr/bin/python3 "$TIMEOUT_WRAPPER" \
    --timeout 900 \
    --prompt "$RUN_PROMPT" \
    -- \
    "$CODEX_BIN" exec \
    --cd "$ROOT" \
    --skip-git-repo-check \
    --ephemeral \
    --model "gpt-5.5" \
    --sandbox danger-full-access \
    --config 'approval_policy="never"' \
    --output-last-message "$SUMMARY_FILE" \
    -
else
  print -r -- "$(timestamp) WARN_TIMEOUT_WRAPPER_MISSING path=$TIMEOUT_WRAPPER"
  "$CODEX_BIN" exec \
    --cd "$ROOT" \
    --skip-git-repo-check \
    --ephemeral \
    --model "gpt-5.5" \
    --sandbox danger-full-access \
    --config 'approval_policy="never"' \
    --output-last-message "$SUMMARY_FILE" \
    - < "$RUN_PROMPT"
fi
exit_code=$?

if (( exit_code != 0 )) && [[ "$MODE" == "force-email" ]]; then
  RECONCILE_SCRIPT="$ROOT/launchd/reconcile_manual_run.py"
  WORKSPACE_RECONCILE="/Users/buyecho/Documents/关注杭州配售型保障性住房的最新消息/launchd/reconcile_manual_run.py"
  [[ -f "$RECONCILE_SCRIPT" ]] || RECONCILE_SCRIPT="$WORKSPACE_RECONCILE"
  if [[ -f "$RECONCILE_SCRIPT" ]]; then
    /usr/bin/python3 "$RECONCILE_SCRIPT"
  else
    print -r -- "$(timestamp) WARN_RECONCILE_SCRIPT_MISSING path=$RECONCILE_SCRIPT"
  fi
  recovered=$(
    /usr/bin/python3 - "$STATUS_FILE" "$RUN_ID" <<'PY'
import json
import sys
from pathlib import Path

path, run_id = sys.argv[1:]
if not Path(path).exists():
    print("no")
else:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    print("yes" if data.get("mode") == "force-email" and data.get("run_id") == run_id else "no")
PY
  )
  if [[ "$recovered" == "yes" ]]; then
    print -r -- "$(timestamp) RUN_RECOVERED_FROM_SENT_MANIFEST id=$RUN_ID original_exit_code=$exit_code"
    exit_code=0
  fi
fi

if (( exit_code == 0 )); then
  result="success"
else
  result="failed"
fi

write_status "$result" "$exit_code"
print -r -- "$(timestamp) RUN_END id=$RUN_ID result=$result exit_code=$exit_code"
exit "$exit_code"
