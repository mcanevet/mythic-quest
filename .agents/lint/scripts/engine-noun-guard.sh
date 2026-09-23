#!/usr/bin/env bash
# Mechanical tripwire for the engine-agnostic-agents lint rule
# (.agents/lint/rules.yaml — the semantic source of truth; this script is
# only a fast, deterministic pre-check so obvious violations fail without
# dispatching judge subagents). Fails on engine-specific nouns appearing
# in the INSTRUCTION BODY of agent profiles. Frontmatter is skipped —
# permissions are configuration and may legitimately name engine plugins.
set -uo pipefail
cd "$(dirname "$0")/../../.."

status=0
# Engine-specific nouns: file formats, tool names, process commands.
# Engine-neutral terms ("engine", "runtime", "the engine plugin") are fine.
# EXEMPT: shell-command invocations (godot --...) directed at humans,
# not role-agent instructions. Those are human-workflow docs, not agent
# persona text.
pattern='(\.gd\b|\.tscn\b|\.tres\b|\.gdscript\b|run_script|start_test|stop_project|run_project|get_debug_output|simulate_input|take_screenshot|SceneTree|get_tree\(\)|godot [^-])'

for f in agents/*.md; do
  [ -f "$f" ] || continue
  # Find frontmatter end line, then grep only the body, keeping real line numbers.
  fm_end=$(awk 'NR==1 && $0=="---" {infm=1; next} infm && $0=="---" {print NR; exit}' "$f")
  if [ -n "${fm_end:-}" ]; then
    hits=$(tail -n +"$((fm_end + 1))" "$f" | grep -Ein "$pattern")
  else
    hits=$(grep -Ein "$pattern" "$f")
  fi
  if [ -n "$hits" ]; then
    while IFS= read -r line; do
      echo "$f: $line" >&2
      status=1
    done <<< "$hits"
  fi
done

exit $status
