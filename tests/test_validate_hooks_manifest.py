from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = REPOSITORY_ROOT / "hooks" / "hooks.json"
VALIDATOR_PATH = REPOSITORY_ROOT / "tests" / "validate_hooks_manifest.py"
BASE_MANIFEST = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def run_validator(manifest_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(VALIDATOR_PATH), str(manifest_path)],
        check=False,
        capture_output=True,
        encoding="utf-8",
        errors="strict",
    )


def replace_path(document, path, value) -> None:
    cursor = document
    for part in path[:-1]:
        cursor = cursor[part]
    cursor[path[-1]] = value


class HooksManifestContractTests(unittest.TestCase):
    def test_repository_manifest_matches_exact_contract(self) -> None:
        result = run_validator(MANIFEST_PATH)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertIn("PASS: manifest-contract", result.stdout)

    def test_contract_mutations_fail_and_name_field(self) -> None:
        cases = (
            (
                "matcher",
                ("hooks", "SessionStart", 0, "matcher"),
                "^startup$",
                "$.hooks.SessionStart[0].matcher",
            ),
            (
                "command",
                ("hooks", "SessionStart", 0, "hooks", 0, "command"),
                "python3 wrong.py",
                "$.hooks.SessionStart[0].hooks[0].command",
            ),
            (
                "commandWindows",
                ("hooks", "SessionStart", 0, "hooks", 0, "commandWindows"),
                "python wrong.py",
                "$.hooks.SessionStart[0].hooks[0].commandWindows",
            ),
            (
                "timeout",
                ("hooks", "SessionStart", 0, "hooks", 0, "timeout"),
                11,
                "$.hooks.SessionStart[0].hooks[0].timeout",
            ),
            (
                "additionalContextLimit",
                (
                    "hooks",
                    "SessionStart",
                    0,
                    "hooks",
                    0,
                    "additionalContextLimit",
                ),
                2499,
                "$.hooks.SessionStart[0].hooks[0].additionalContextLimit",
            ),
        )

        for name, path, value, expected_error_path in cases:
            with self.subTest(field=name):
                mutated = copy.deepcopy(BASE_MANIFEST)
                replace_path(mutated, path, value)

                with tempfile.TemporaryDirectory() as temp_dir:
                    manifest_path = Path(temp_dir) / "hooks.json"
                    manifest_path.write_text(
                        json.dumps(mutated, indent=2),
                        encoding="utf-8",
                    )
                    result = run_validator(manifest_path)

                self.assertNotEqual(result.returncode, 0, name)
                self.assertEqual(result.stdout, "", name)
                self.assertIn(expected_error_path, result.stderr, name)


if __name__ == "__main__":
    unittest.main()
