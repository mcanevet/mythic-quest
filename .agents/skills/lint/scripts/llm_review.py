#!/usr/bin/env python3
"""Embedded semantic linter (llm-review tier of .agents/lint/rules.yaml).

Runs LLM-judged governance rules on agent/skill files using the harness
model. One model call per (rule, file), structured output enforced via a
forced tool call, validated, cached by content hash.

Design borrowed from moeru-ai/alint deep dive (bead mythic-quest-e7w):
- Forced tool_call for structured output (provider-agnostic)
- Line-numbered source in prompt; schema says to use the left-column number
- Retry with validation feedback, classification of retriable vs fatal
- Cache fingerprint: {ruleHash, modelId, targetHash} (content-addressed)
- Exit codes: 0 pass, 1 violations, 2 infra error

Usage:
  llm_review.py [--rule NAME] [--target PATH] [--no-cache] [--json]

Model access: reads LLM_REVIEW_MODEL_ID (for cache fingerprinting) and
LLM_REVIEW_COMMAND (a shell command that receives the JSON request on
stdin and must return an OpenAI-compatible chat completion JSON on
stdout). This keeps the script harness-agnostic: any harness can provide
the command that performs one model call.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[4]
RULES_YAML = ROOT / ".agents" / "lint" / "rules.yaml"
CACHE_DIR = ROOT / ".agents" / "lint" / ".llmreviewcache"

DEFAULT_COMMAND = os.environ.get("LLM_REVIEW_COMMAND", "")
MODEL_ID = os.environ.get("LLM_REVIEW_MODEL_ID", "unconfigured")

MAX_ATTEMPTS = 3
RETRIABLE_HTTP = {408, 429, 500, 502, 503, 504}

# Target selection: agent/skill/prose files governed by the swarm.
TARGET_PATTERNS = [
    re.compile(r"^\.agents/.*\.(md|ya?ml|toml)$"),
    re.compile(r"^agents/.*\.(md|ya?ml|toml)$"),
    re.compile(r"^skills/.*\.(md|ya?ml|toml)$"),
    re.compile(r"^AGENTS\.md$"),
]


class InfraError(Exception):
    pass


def sha256(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def load_rules(name_filter: str | None) -> dict:
    data = yaml.safe_load(RULES_YAML.read_text())
    rules = {}
    for name, rule in data.get("rules", {}).items():
        if rule.get("tier") != "llm-review":
            continue
        if name_filter and name != name_filter:
            continue
        prompt = rule.get("prompt")
        if not prompt or not prompt.strip():
            continue
        rules[name] = rule
    return rules


def discover_targets(explicit: str | None) -> list[Path]:
    if explicit:
        p = ROOT / explicit
        if not p.is_file():
            raise InfraError(f"target not found: {explicit}")
        return [p]
    targets = []
    for path in ROOT.rglob("*"):
        if any(part.startswith(".") and part not in (".agents", ".claude", ".codex")
               for part in path.relative_to(ROOT).parts[:-1]):
            continue
        rel = path.relative_to(ROOT).as_posix()
        if path.is_file() and any(p.match(rel) for p in TARGET_PATTERNS):
            targets.append(path)
    return sorted(targets)


def line_numbered(source: str) -> str:
    return "\n".join(f"{i + 1} | {line}" for i, line in enumerate(source.splitlines()))


def build_request(instruction: str, rule_name: str, target_path: Path, source: str) -> dict:
    schema = {
        "type": "object",
        "properties": {
            "findings": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "line": {"type": "integer"},
                        "message": {"type": "string"},
                        "confidence": {"type": "string", "enum": ["high", "medium", "low"]},
                    },
                    "required": ["line", "message", "confidence"],
                    "additionalProperties": False,
                },
            },
        },
        "required": ["findings"],
        "additionalProperties": False,
    }
    system = f"{instruction.strip()}\n\nYou are reviewing one file for a governance rule named '{rule_name}'."
    user = (
        f"Reviewed target file path: {target_path.relative_to(ROOT).as_posix()}\n"
        f"Reviewed target source with line numbers "
        f"(use the left-column number as the finding line):\n\n{line_numbered(source)}\n\n"
        "Call the report_findings tool exactly once with your findings. "
        "Use an empty findings array if there are no violations."
    )
    return {
        "model": MODEL_ID,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "tools": [{
            "type": "function",
            "function": {
                "name": "report_findings",
                "description": "Report findings for the governance rule",
                "parameters": schema,
            },
        }],
        "tool_choice": {"type": "function", "function": {"name": "report_findings"}},
        "temperature": 0,
    }


def call_model(request: dict) -> dict:
    if not DEFAULT_COMMAND:
        raise InfraError(
            "LLM_REVIEW_COMMAND not set; provide a shell command that reads an "
            "OpenAI-compatible chat request on stdin and writes the completion "
            "JSON on stdout"
        )
    proc = subprocess.run(
        ["/bin/sh", "-c", DEFAULT_COMMAND],
        input=json.dumps(request),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise InfraError(f"model command failed (rc={proc.returncode}): {proc.stderr[-500:]}")
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as e:
        raise InfraError(f"model command returned non-JSON output: {e}") from e


class RetriableError(Exception):
    pass


class FatalError(Exception):
    pass


def extract_tool_call(completion: dict) -> dict:
    choices = completion.get("choices") or []
    if len(choices) != 1:
        raise RetriableError(f"expected exactly 1 choice, got {len(choices)}")
    choice = choices[0]
    finish = choice.get("finish_reason")
    if finish == "content_filter":
        raise FatalError("content_filter")
    message = choice.get("message") or {}
    tool_calls = message.get("tool_calls") or []
    if len(tool_calls) != 1:
        raise RetriableError(f"expected exactly 1 tool call, got {len(tool_calls)}")
    tc = tool_calls[0]
    if (tc.get("function") or {}).get("name") != "report_findings":
        raise RetriableError(f"unexpected tool name: {tc.get('function', {}).get('name')}")
    args = tc["function"].get("arguments")
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except json.JSONDecodeError as e:
            raise RetriableError(f"tool arguments are not valid JSON: {e}") from e
    return args


def validate_findings(args: dict, max_line: int) -> list[dict]:
    if not isinstance(args, dict) or set(args) != {"findings"}:
        raise RetriableError(f"payload must have exactly a 'findings' key, got: {sorted(args) if isinstance(args, dict) else type(args)}")
    findings = args["findings"]
    if not isinstance(findings, list):
        raise RetriableError("'findings' must be an array")
    out = []
    for f in findings:
        if not isinstance(f, dict) or set(f) != {"line", "message", "confidence"}:
            raise RetriableError(f"finding keys must be exactly line/message/confidence, got: {sorted(f) if isinstance(f, dict) else type(f)}")
        line, msg, conf = f["line"], f["message"], f["confidence"]
        if not isinstance(line, int) or isinstance(line, bool) or not (1 <= line <= max_line):
            raise RetriableError(f"line {line!r} out of range 1..{max_line}")
        if not isinstance(msg, str) or not msg.strip():
            raise RetriableError("message must be a non-empty string")
        if conf not in ("high", "medium", "low"):
            raise RetriableError(f"confidence {conf!r} not in high/medium/low")
        out.append({"line": line, "message": msg, "confidence": conf})
    return out


def judge(rule_name: str, rule: dict, target: Path) -> tuple[list[dict], bool]:
    """Returns (findings, from_cache)."""
    source = target.read_text()
    max_line = max(len(source.splitlines()), 1)
    instruction = " ".join(rule["prompt"].split())

    use_cache = CACHE_DIR.exists() or True
    fingerprint = {
        "rule": sha256(instruction),
        "model": MODEL_ID,
        "target": sha256(source),
    }
    cache_key = sha256(json.dumps(fingerprint, sort_keys=True))
    cache_file = CACHE_DIR / f"{cache_key}.json"

    if use_cache and cache_file.is_file():
        try:
            cached = json.loads(cache_file.read_text())
            if cached.get("fingerprint") == fingerprint:
                return cached["findings"], True
        except (json.JSONDecodeError, KeyError):
            pass  # corrupted entry: ignore, rerun

    request = build_request(instruction, rule_name, target, source)
    messages = request["messages"]

    last_error = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        completion = call_model(request)
        try:
            args = extract_tool_call(completion)
            findings = validate_findings(args, max_line)
            CACHE_DIR.mkdir(parents=True, exist_ok=True)
            payload = {"fingerprint": fingerprint, "findings": findings}
            fd, tmp = tempfile.mkstemp(dir=CACHE_DIR, suffix=".tmp")
            try:
                with os.fdopen(fd, "w") as fh:
                    json.dump(payload, fh)
                os.replace(tmp, cache_file)
            finally:
                if os.path.exists(tmp):
                    os.unlink(tmp)
            return findings, False
        except RetriableError as e:
            last_error = e
            if attempt < MAX_ATTEMPTS:
                messages.append({"role": "user", "content": (
                    f"Your previous tool call could not be validated. "
                    f"Validation error: {e}. Call report_findings again with "
                    f"arguments that exactly match the tool schema."
                )})
        except FatalError as e:
            raise InfraError(f"fatal model error on {target}: {e}") from e
    raise InfraError(
        f"rule {rule_name} on {target}: exhausted {MAX_ATTEMPTS} attempts; "
        f"last validation error: {last_error}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rule", help="only run the named llm-review rule")
    parser.add_argument("--target", help="only lint this repo-relative path")
    parser.add_argument("--no-cache", action="store_true")
    parser.add_argument("--json", action="store_true", dest="as_json")
    args = parser.parse_args()

    try:
        rules = load_rules(args.rule)
        if not rules:
            print("llm-review: no matching rules", file=sys.stderr)
            return 0
        targets = discover_targets(args.target)
        if not targets:
            print("llm-review: no targets", file=sys.stderr)
            return 0

        diagnostics = []
        cached_count = 0
        for rule_name, rule in sorted(rules.items()):
            for target in targets:
                findings, from_cache = judge(rule_name, rule, target)
                if from_cache:
                    cached_count += 1
                for f in findings:
                    diagnostics.append({
                        "rule": rule_name,
                        "file": target.relative_to(ROOT).as_posix(),
                        "line": f["line"],
                        "message": f["message"],
                        "confidence": f["confidence"],
                        "severity": "warn",
                        "cached": from_cache,
                    })
    except InfraError as e:
        print(f"llm-review INFRA FAIL: {e}", file=sys.stderr)
        return 2

    diagnostics.sort(key=lambda d: (d["rule"], d["file"], d["line"]))
    if args.as_json:
        print(json.dumps({"diagnostics": diagnostics, "cached": cached_count}, indent=2))
    else:
        for d in diagnostics:
            print(f"WARN {d['rule']} {d['file']}:{d['line']} [{d['confidence']}] {d['message']}")
        print(f"llm-review: {len(diagnostics)} finding(s), {cached_count} cached judgment(s)")

    return 1 if diagnostics else 0


if __name__ == "__main__":
    sys.exit(main())
