#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path


sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")


EXPECTED_MANIFEST: dict[str, object] = {
    "description": "Load a managed project work-log after Codex context compaction.",
    "hooks": {
        "SessionStart": [
            {
                "matcher": "^compact$",
                "hooks": [
                    {
                        "type": "command",
                        "command": 'python3 "${PLUGIN_ROOT}/hooks/session_start.py"',
                        "commandWindows": 'python "%PLUGIN_ROOT%\\hooks\\session_start.py"',
                        "statusMessage": "Loading work-log recovery checkpoint",
                        "timeout": 10,
                        "additionalContextLimit": 2500,
                    }
                ],
            }
        ]
    },
}


def first_mismatch(
    actual: object,
    expected: object,
    path: str = "$",
) -> str | None:
    if actual.__class__ is not expected.__class__:
        return (
            f"{path}: expected type {expected.__class__.__name__}, "
            f"got {actual.__class__.__name__}"
        )

    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            return f"{path}: expected object"

        for key in expected:
            if key not in actual:
                return f"{path}.{key}: missing"

        for key in actual:
            if key not in expected:
                return f"{path}.{key}: unexpected"

        for key, expected_value in expected.items():
            mismatch = first_mismatch(
                actual[key],
                expected_value,
                f"{path}.{key}",
            )
            if mismatch is not None:
                return mismatch

        return None

    if isinstance(expected, list):
        if not isinstance(actual, list):
            return f"{path}: expected array"

        if len(actual) != len(expected):
            return (
                f"{path}: expected {len(expected)} items, "
                f"got {len(actual)}"
            )

        for index, expected_value in enumerate(expected):
            mismatch = first_mismatch(
                actual[index],
                expected_value,
                f"{path}[{index}]",
            )
            if mismatch is not None:
                return mismatch

        return None

    if actual != expected:
        return f"{path}: expected {expected!r}, got {actual!r}"

    return None


def validate_manifest(path: Path) -> str | None:
    try:
        actual = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return f"$: unable to read valid UTF-8 JSON ({exc})"

    return first_mismatch(actual, EXPECTED_MANIFEST)


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "usage: validate_hooks_manifest.py PATH",
            file=sys.stderr,
        )
        return 2

    manifest_path = Path(sys.argv[1])
    mismatch = validate_manifest(manifest_path)
    if mismatch is not None:
        print(f"{manifest_path}: {mismatch}", file=sys.stderr)
        return 1

    print(f"PASS: manifest-contract {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
