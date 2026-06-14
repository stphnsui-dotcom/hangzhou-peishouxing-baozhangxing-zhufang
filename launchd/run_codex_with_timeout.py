#!/usr/bin/env python3
"""Run Codex with a hard timeout and terminate its process group on expiry."""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--prompt", type=Path, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    if not args.command:
        parser.error("missing command")
    return args


def main() -> int:
    args = parse_args()
    with args.prompt.open("rb") as prompt:
        process = subprocess.Popen(
            args.command,
            stdin=prompt,
            start_new_session=True,
        )
        try:
            return process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            print(f"CODEX_TIMEOUT seconds={args.timeout}", flush=True)
            return 124


if __name__ == "__main__":
    raise SystemExit(main())
