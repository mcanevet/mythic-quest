#!/usr/bin/env python3
"""Deterministic lint for the swarm. Exit nonzero on any violation.

Checks (see .agents/lint/rules.yaml for the rule registry):
- bd-only-tracking: no markdown TODO checkboxes
- single-source-of-truth: generated AGENTS.md block matches render output

--all additionally runs the llm-review tier (llm_review.py, harness model).
"""

from pathlib import Path
import argparse
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
SCRIPTS = ROOT / ".agents" / "skills" / "lint" / "scripts"

BEGIN = "<!-- BEGIN LINT RULES (generated from lint/rules.yaml) -->"
END = "<!-- END LINT RULES -->"
TODO_RE = re.compile(r"^\s*- \[[ xX]\]\s+\S", re.MULTILINE)


def check_bd_only_tracking(files: list[Path]) -> list[str]:
    violations = []
    for f in files:
        if f.suffix != ".md" or not f.is_file():
            continue
        if TODO_RE.search(f.read_text()):
            violations.append(f"bd-only-tracking: {f} contains a markdown TODO checklist")
    return violations


def check_single_source_of_truth() -> list[str]:
    agents_md = ROOT / "AGENTS.md"
    if not agents_md.exists():
        return []
    if BEGIN not in agents_md.read_text():
        return []  # nothing generated yet; renderer decides placement
    result = subprocess.run(
        [sys.executable, str(SCRIPTS / "render_rules.py"), "--check"],
        capture_output=True,
        text=True,
    )
    if result.returncode == 1:
        return ["single-source-of-truth: AGENTS.md generated block is stale; rerun render_rules.py"]
    return []


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true",
                        help="also run the llm-review tier (semantic, uses harness model)")
    args = parser.parse_args()

    files = [p for p in ROOT.rglob("*") if ".git/" not in p.parts and ".beads/" not in p.parts]
    violations = check_bd_only_tracking(files) + check_single_source_of_truth()
    if violations:
        for v in violations:
            print(f"LINT FAIL: {v}", file=sys.stderr)
        return 1

    if args.all:
        result = subprocess.run(
            [sys.executable, str(SCRIPTS / "llm_review.py")],
        )
        if result.returncode == 2:
            print("LINT FAIL: llm-review tier hit an infra error", file=sys.stderr)
            return 1
        if result.returncode == 1:
            return 1
    print("lint: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
