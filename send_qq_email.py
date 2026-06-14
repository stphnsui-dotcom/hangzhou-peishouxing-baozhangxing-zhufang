#!/usr/bin/env python3
"""Queue and send HTML mail through QQ SMTP with idempotent retries."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import smtplib
import ssl
import sys
from datetime import datetime
from email.message import EmailMessage
from pathlib import Path
from typing import Any


SMTP_HOST = "smtp.qq.com"
SMTP_PORT = 465
DEFAULT_ADDRESS = "your-qq-number@qq.com"
AUTOMATION_CONFIG = Path.home() / ".codex/automations/automation/automation.toml"
AUTH_CODE_FILE = Path(__file__).resolve().parent / ".secrets/qq_smtp_auth_code"
OUTBOX_DIR = Path(__file__).resolve().parent / ".mail-outbox"


def now_text() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def read_auth_code() -> str:
    env_code = os.environ.get("QQ_SMTP_AUTH_CODE", "").strip()
    if env_code:
        return env_code

    if AUTH_CODE_FILE.exists():
        file_code = AUTH_CODE_FILE.read_text(encoding="utf-8").strip()
        if file_code:
            return file_code

    if AUTOMATION_CONFIG.exists():
        config = AUTOMATION_CONFIG.read_text(encoding="utf-8")
        match = re.search(r"授权码[：:]\s*([A-Za-z0-9]+)", config)
        if match:
            return match.group(1)

    raise RuntimeError(
        "QQ SMTP authorization code not found in QQ_SMTP_AUTH_CODE, "
        f"{AUTH_CODE_FILE}, or the legacy automation config"
    )


def message_id(subject: str, html: str, recipient: str) -> str:
    payload = "\0".join((subject, html, recipient)).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()[:20]


def manifest_path(mail_id: str) -> Path:
    return OUTBOX_DIR / f"{mail_id}.json"


def write_manifest(data: dict[str, Any]) -> Path:
    OUTBOX_DIR.mkdir(parents=True, exist_ok=True)
    path = manifest_path(data["id"])
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return path


def queue_mail(html_path: Path, subject: str, recipient: str) -> Path:
    html_path = html_path.resolve()
    html = html_path.read_text(encoding="utf-8")
    mail_id = message_id(subject, html, recipient)
    OUTBOX_DIR.mkdir(parents=True, exist_ok=True)
    path = manifest_path(mail_id)
    if path.exists():
        data = json.loads(path.read_text(encoding="utf-8"))
        if "source_html_path" not in data:
            snapshot_path = OUTBOX_DIR / f"{mail_id}.html"
            snapshot_path.write_text(html, encoding="utf-8")
            data["source_html_path"] = data["html_path"]
            data["html_path"] = str(snapshot_path)
            write_manifest(data)
        return path

    snapshot_path = OUTBOX_DIR / f"{mail_id}.html"
    snapshot_path.write_text(html, encoding="utf-8")
    return write_manifest(
        {
            "id": mail_id,
            "status": "pending",
            "subject": subject,
            "sender": DEFAULT_ADDRESS,
            "recipient": recipient,
            "html_path": str(snapshot_path),
            "source_html_path": str(html_path),
            "created_at": now_text(),
            "attempts": 0,
            "last_attempt_at": None,
            "last_error": None,
            "sent_at": None,
        }
    )


def build_message(data: dict[str, Any]) -> EmailMessage:
    html = Path(data["html_path"]).read_text(encoding="utf-8")
    message = EmailMessage()
    message["Subject"] = data["subject"]
    message["From"] = data["sender"]
    message["To"] = data["recipient"]
    message.set_content("请使用支持 HTML 的邮箱客户端查看杭州配售型保障房监控简报。")
    message.add_alternative(html, subtype="html")
    return message


def send_manifest(path: Path, dry_run: bool = False) -> bool:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data["status"] == "sent":
        print(f"SKIP_SENT {data['id']}")
        return True

    if dry_run:
        build_message(data)
        print(f"DRY_RUN_OK {data['id']} {data['subject']}")
        return True

    data["attempts"] += 1
    data["last_attempt_at"] = now_text()
    data["last_error"] = None

    try:
        message = build_message(data)
        context = ssl.create_default_context()
        with smtplib.SMTP_SSL(
            SMTP_HOST,
            SMTP_PORT,
            timeout=30,
            context=context,
        ) as server:
            server.login(data["sender"], read_auth_code())
            server.send_message(message)
    except Exception as exc:
        data["last_error"] = f"{type(exc).__name__}: {exc}"
        write_manifest(data)
        print(f"SEND_FAILED {data['id']} {data['last_error']}", file=sys.stderr)
        return False

    data["status"] = "sent"
    data["sent_at"] = now_text()
    write_manifest(data)
    print(f"SENT {data['id']} {data['subject']}")
    return True


def drain(dry_run: bool = False) -> int:
    OUTBOX_DIR.mkdir(parents=True, exist_ok=True)
    pending = []
    for path in sorted(OUTBOX_DIR.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("status") != "sent":
            pending.append(path)

    if not pending:
        print("OUTBOX_EMPTY")
        return 0

    failed = [path for path in pending if not send_manifest(path, dry_run=dry_run)]
    return 1 if failed else 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--html", type=Path)
    parser.add_argument("--subject")
    parser.add_argument("--to", default=DEFAULT_ADDRESS)
    parser.add_argument("--drain", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not args.drain and (not args.html or not args.subject):
        parser.error("use --drain or provide both --html and --subject")
    return args


def main() -> int:
    args = parse_args()
    if args.drain:
        return drain(dry_run=args.dry_run)

    path = queue_mail(args.html, args.subject, args.to)
    return 0 if send_manifest(path, dry_run=args.dry_run) else 1


if __name__ == "__main__":
    raise SystemExit(main())
