"""Inject a managed work-log checkpoint after Codex context compaction."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any


MANAGED_MARKERS = {
    "<!-- work-log:v1 -->",
    "<!-- work-log:v2 -->",
}

CONTEXT_PREFIX = (
    "A work-log recovery checkpoint was loaded after context compaction. "
    "Latest user instructions and freshly verified workspace state remain "
    "authoritative."
)


def read_event() -> dict[str, Any] | None:
    try:
        event = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, UnicodeError):
        return None

    return event if isinstance(event, dict) else None


def resolve_project_root(cwd: Path) -> Path:
    try:
        result = subprocess.run(
            ["git", "-C", str(cwd), "rev-parse", "--show-toplevel"],
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="strict",
        )
    except (OSError, UnicodeError):
        return cwd

    if result.returncode == 0:
        candidate = Path(result.stdout.strip())
        if candidate.is_dir():
            return candidate

    return cwd


def read_managed_log(project_root: Path) -> str | None:
    log_path = project_root / "log.md"
    try:
        content = log_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        return None

    lines = content.splitlines()
    first_line = lines[0] if lines else ""
    return content if first_line in MANAGED_MARKERS else None


def build_output(checkpoint: str) -> dict[str, Any]:
    return {
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": f"{CONTEXT_PREFIX}\n\n{checkpoint}",
        }
    }


def run() -> int:
    event = read_event()
    if (
        event is None
        or event.get("hook_event_name") != "SessionStart"
        or event.get("source") != "compact"
    ):
        return 0

    cwd_value = event.get("cwd")
    if not isinstance(cwd_value, str) or not cwd_value.strip():
        return 0

    cwd = Path(cwd_value)
    if not cwd.is_dir():
        return 0

    checkpoint = read_managed_log(resolve_project_root(cwd))
    if checkpoint is None:
        return 0

    json.dump(build_output(checkpoint), sys.stdout, ensure_ascii=False, separators=(",", ":"))
    return 0


def main() -> int:
    try:
        return run()
    except Exception as exc:  # pragma: no cover - last-resort hook containment
        print(f"work-log-hook: unexpected error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
