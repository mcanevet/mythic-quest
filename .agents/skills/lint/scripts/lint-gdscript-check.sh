#!/usr/bin/env bash
# lint-gdscript-check: deterministic GDScript parse checks for the lint wisp.
# Runs headless Godot --check-only on:
#   1. All skills/*/scripts/*.gd files
#   2. Embedded ```gdscript blocks in SKILL.md + reference/*.md
# Exemptions for embedded blocks: no extends, placeholder <...> on non-comment lines,
# explicit marker <!-- lint:gdscript-unparseable -->.
# Output: warnings to stderr; exit 0 always (non-blocking pre-pass).

set -uo pipefail
GODOT_BIN="${GODOT_BIN:-$(command -v godot || true)}"
if [ -z "$GODOT_BIN" ] && [ -x "/Applications/Godot.app/Contents/MacOS/godot" ]; then
  GODOT_BIN="/Applications/Godot.app/Contents/MacOS/godot"
fi
if [ -z "$GODOT_BIN" ]; then
  echo "ℹ️  godot binary not found — skipped GDScript parse check" >&2
  exit 0
fi

warn() { printf '⚠️  %s\n' "$1" >&2; }

# Check standalone .gd files --------------------------------------------------
check_gdscript_parse() {
  local gd_tmp err
  gd_tmp=$(mktemp -d)
  trap 'rm -rf "$gd_tmp"' RETURN
  printf 'config_version=5\n[application]\nconfig/name="lint-gd-check"\n' > "$gd_tmp/project.godot"
  
  for gd in skills/*/scripts/*.gd .agents/skills/*/scripts/*.gd; do
    [ -e "$gd" ] || continue
    cp "$gd" "$gd_tmp/check_target.gd"
    err="$("$GODOT_BIN" --headless --path "$gd_tmp" --check-only --script res://check_target.gd 2>&1)" || true
    if printf '%s' "$err" | grep -q "SCRIPT ERROR\|Parse Error"; then
      warn "GDScript parse error in $gd:"
      printf '%s\n' "$err" | grep -v '^Godot Engine' | sort -u | head -5 | sed 's/^/    /'
    fi
  done
}

# Check embedded ```gdscript blocks -------------------------------------------
check_embedded_gdscript_parse() {
  local md_files gd_tmp n_checked snip err
  md_files=$( { ls skills/*/SKILL.md skills/*/reference/*.md .agents/skills/*/SKILL.md .agents/skills/*/reference/*.md 2>/dev/null; } | sort -u )
  [ -z "$md_files" ] && return
  
  gd_tmp=$(mktemp -d)
  trap 'rm -rf "$gd_tmp"' RETURN
  printf 'config_version=5\n[application]\nconfig/name="lint-md-gd-check"\n' > "$gd_tmp/project.godot"
  n_checked=0
  
  for md in $md_files; do
    python3 - "$md" "$gd_tmp" <<'PYEOF' || true
import re, sys, os
md, out_dir = sys.argv[1], sys.argv[2]
src = open(md, encoding="utf-8").read()
n = 0
for m in re.finditer(r"```gdscript\n(.*?)```", src, re.S):
    body = m.group(1)
    if not re.search(r"^\s*extends\s+\w+", body, re.M):
        continue
    code_lines = [l for l in body.split("\n") if not l.strip().startswith("#")]
    code_text = "\n".join(code_lines)
    if "<" in code_text and ">" in code_text:
        continue
    if "lint:gdscript-unparseable" in body:
        continue
    with open(os.path.join(out_dir, f"{abs(hash(md))%99999}_{n}.gd"), "w") as fh:
        fh.write(body)
    n += 1
PYEOF
  done
  
  for snip in "$gd_tmp"/*.gd; do
    [ -e "$snip" ] || continue
    n_checked=$((n_checked + 1))
    err="$("$GODOT_BIN" --headless --path "$gd_tmp" --check-only --script "res://$(basename "$snip")" 2>&1)" || true
    if printf '%s' "$err" | grep -q "SCRIPT ERROR\|Parse Error"; then
      warn "Embedded GDScript parse error (snippet $(basename "$snip")):"
      printf '%s\n' "$err" | grep -v '^Godot Engine' | sort -u | head -5 | sed 's/^/    /'
    fi
  done
}

check_gdscript_parse
check_embedded_gdscript_parse
exit 0
