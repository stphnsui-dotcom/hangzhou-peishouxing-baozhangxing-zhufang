#!/usr/bin/env python3
"""Recover state when a manual run sent mail but Codex did not exit cleanly."""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path


ROOT = Path.home() / ".local/share/hangzhou_housing_monitor"
OUTBOX = ROOT / ".mail-outbox"
STATE = ROOT / "state"


def parse_time(value: str | None) -> datetime:
    if not value:
        return datetime.min.astimezone()
    return datetime.fromisoformat(value)


def main() -> int:
    manifests = []
    for path in OUTBOX.glob("*.json"):
        data = json.loads(path.read_text(encoding="utf-8"))
        if "监控·立即检索" in data.get("subject", "") and data.get("status") == "sent":
            manifests.append((parse_time(data.get("sent_at")), path, data))
    if not manifests:
        return 0

    sent_at, path, data = max(manifests, key=lambda item: item[0])
    status_path = STATE / "latest-status.json"
    existing = {}
    if status_path.exists():
        existing = json.loads(status_path.read_text(encoding="utf-8"))
    if parse_time(existing.get("finished_at")) >= sent_at:
        return 0

    run_id = Path(data.get("source_html_path", "")).stem.split("-force-email")[0]
    summary = (
        f"手动立即检索邮件已发送。\n\n"
        f"标题：{data['subject']}\n"
        f"Manifest：{data['id']}，status=sent，sent_at={data['sent_at']}。\n"
        "本状态由恢复程序根据 SMTP 成功记录补写。"
    )
    status = {
        "run_id": run_id,
        "finished_at": data["sent_at"],
        "result": "success_recovered",
        "exit_code": 0,
        "mode": "force-email",
        "manifest_id": data["id"],
        "manifest_path": str(path),
        "recovered": True,
    }
    STATE.mkdir(parents=True, exist_ok=True)
    status_path.write_text(
        json.dumps(status, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (STATE / "latest-summary.txt").write_text(summary + "\n", encoding="utf-8")

    memory_path = STATE / "monitor-memory.md"
    memory = memory_path.read_text(encoding="utf-8") if memory_path.exists() else ""
    marker = f"Manifest id: {data['id']}"
    if marker not in memory:
        recovered_note = (
            f"\n{sent_at.astimezone().strftime('%Y-%m-%d %H:%M:%S %Z')}\n\n"
            "- Manual force-email run completed SMTP delivery before the Codex process stalled.\n"
            f"- Subject: {data['subject']}\n"
            f"- {marker}; status=sent; sent_at={data['sent_at']}.\n"
            "- Runtime state was reconciled from the durable outbox manifest.\n"
        )
        memory_path.write_text(memory + recovered_note, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
