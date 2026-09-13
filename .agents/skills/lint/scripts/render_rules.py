#!/usr/bin/env python3
"""Render the generated AGENTS.md governance section from lint/rules.yaml.

Single source of truth is lint/rules.yaml; the AGENTS.md block is a render
target. Never hand-edit the generated block.

Usage:
  render_rules.py           rewrite AGENTS.md block from rules.yaml
  render_rules.py --check   exit 1 if AGENTS.md block is stale, 0 if fresh
"""

from pathlib import Path
import sys

import yaml

ROOT = Path(__file__).resolve().parents[4]
RULES = ROOT / ".agents" / "lint" / "rules.yaml"
AGENTS_MD = ROOT / "AGENTS.md"

BEGIN = "<!-- BEGIN LINT RULES (generated from lint/rules.yaml) -->"
END = "<!-- END LINT RULES -->"


def render_block(rules: dict) -> str:
    lines = [
        BEGIN,
        "",
        "## Harness Governance Rules",
        "",
        "Generated from `.agents/lint/rules.yaml` (single source of truth).",
        "Do not hand-edit; run `.agents/skills/lint/scripts/render_rules.py`.",
        "",
    ]
    for name, rule in rules["rules"].items():
        lines.append(f"- **{rule['title']}** ({name}, tier: {rule['tier']})")
        rationale = " ".join(rule["rationale"].split())
        lines.append(f"  {rationale}")
    lines += ["", END]
    return "\n".join(lines)


def main(check_only: bool) -> int:
    rules = yaml.safe_load(RULES.read_text())
    block = render_block(rules)
    if not AGENTS_MD.exists():
        if check_only:
            return 1
        AGENTS_MD.write_text(block + "\n")
        print(f"Rendered {len(rules['rules'])} rules into {AGENTS_MD} (new file)")
        return 0
    content = AGENTS_MD.read_text()
    if BEGIN in content and END in content:
        before, rest = content.split(BEGIN, 1)
        _, after = rest.split(END, 1)
        current = BEGIN + rest.split(END, 1)[0] + END
        if check_only:
            return 0 if current.strip() == block.strip() else 1
        new_content = before + block + after.rstrip("\n") + "\n"
        if new_content != content:
            AGENTS_MD.write_text(new_content)
            print(f"Rendered {len(rules['rules'])} rules into {AGENTS_MD}")
        else:
            print(f"{AGENTS_MD} already up to date ({len(rules['rules'])} rules)")
        return 0
    if check_only:
        return 1
    AGENTS_MD.write_text(content.rstrip("\n") + "\n\n" + block + "\n")
    print(f"Rendered {len(rules['rules'])} rules into {AGENTS_MD}")
    return 0


if __name__ == "__main__":
    sys.exit(main(check_only="--check" in sys.argv))
