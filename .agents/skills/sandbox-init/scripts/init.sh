#!/usr/bin/env bash
# init.sh — reset a sandbox to a pristine, launch-ready state.
#
# Layout (production-faithful consumer layout, mirrors the old MythicQuest
# `prepare_test_dir.sh` with .opencode renamed to .agents):
#
#   test/<name>/              <- fresh consumer git repo (git init)
#   └── .agents/              <- git SUBMODULE -> this pipeline-dev repo @ committed HEAD
#       ├── agents/           <- game-build agents (top-level, once created)
#       ├── skills/           <- game-build skills (top-level, once created)
#       └── .agents/          <- pipeline-dev internals (lint, sandbox-init)
#
# The whole pipeline-dev repo is mounted at .agents (as the old repo mounted at
# .opencode): game-build agents/skills live at the REPO TOP LEVEL so the
# consumer sees .agents/agents + .agents/skills. Harness-internal
# pipeline-dev skills live nested under .agents/.agents/ and stay behind.
# All supported harnesses (opencode, codex, claude, ...) read .agents/
# natively — no per-harness bridge needed. The harness argument selects
# the `bd setup <recipe>` that generates the right instructions file
# (AGENTS.md, CLAUDE.md, ...).
#
# The submodule pins the harness at the CURRENT COMMITTED HEAD: the consumer
# repo's history records WHICH harness commit a sandbox was built against.
# Git refuses a submodule URL equal to the superproject, so the submodule
# points at a sibling BARE MIRROR (../mythic-quest-mirror.git) that this
# script creates and refreshes from harness HEAD first.
#
# Guarantees (idempotent — safe to run repeatedly):
#   1. Refuses to wipe a sandbox held by a live session of the target
#      harness (zombie contamination guard — a stale session keeps writing
#      into the rebuilt sandbox).
#   2. Sandbox wiped completely (disposable by contract) then rebuilt.
#   3. .agents submodule pinned to the CURRENT COMMITTED harness HEAD.
#      Uncommitted harness changes are EXCLUDED (commit first — that is the
#      reproducibility point).
#   4. Fresh consumer git repo; its first commit pins the harness SHA.
#   5. bd ledger initialized (bd init --quiet --stealth) and the harness's
#      integration file(s) generated via `bd setup <harness>`.
#   6. Fail-loud verification; exit 1 with a reason if anything is off.
#   7. Commits nothing to the pipeline-dev repo itself.
#
# Usage: init.sh <harness> <engine> [sandbox-name]
#   harness: opencode | codex | claude | ... (any `bd setup` recipe; required)
#   engine: godot | ... (must exist under plugins/engine/; required)
#   sandbox-name defaults to "benchmark"; lives under test/ (gitignored).
# Exit codes: 0 = ready, 1 = verification failed
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
HARNESS="${1:-}"
ENGINE="${2:-}"
SANDBOX_NAME="${3:-benchmark}"

fail() { printf 'init.sh: %s\n' "$1" >&2; exit 1; }

[ -n "$HARNESS" ] ||
  fail "harness required: init.sh <opencode|codex|claude> <engine> [sandbox-name]"
[ -n "$ENGINE" ] ||
  fail "engine required: init.sh <harness> <godot|...> [sandbox-name]"

# Engine plugin: skills live at plugins/engine/<engine>/skills/. The sandbox
# stages a flat, loader-scannable skills/ dir merging the repo's engine-
# agnostic core skills with the chosen engine plugin's skills.
PLUGIN_DIR="$REPO_ROOT/plugins/engine/$ENGINE"
[ -d "$PLUGIN_DIR/skills" ] ||
  fail "unknown engine plugin: $PLUGIN_DIR/skills missing (available: $(ls "$REPO_ROOT/plugins/engine" 2>/dev/null | tr '\n' ' '))"

# Integration file each harness's loader expects after bd setup.
expected_file() {
  case "$HARNESS" in
    claude) printf 'CLAUDE.md' ;;
    *)      printf 'AGENTS.md' ;;
  esac
}

# Validate sandbox name: simple alphanumeric/hyphen/underscore, no slashes/dots
if echo "$SANDBOX_NAME" | grep -qE '[./]'; then
  fail "sandbox name must be a simple name (alphanumeric/hyphen/underscore, no dots or slashes), got: $SANDBOX_NAME"
fi

SANDBOX="$REPO_ROOT/test/$SANDBOX_NAME"
cd "$REPO_ROOT"
command rm -f .beads.gate.lock 2>/dev/null || true

# 1. Refuse to wipe a sandbox with a live session in it ----------------------
if [ -d "$SANDBOX" ]; then
  LIVE_SESSIONS=$(pgrep -x "$HARNESS" 2>/dev/null | while read -r pid; do
    CWD=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
    if [ "$CWD" = "$SANDBOX" ] || [ "${CWD#"$SANDBOX"/}" != "$CWD" ]; then
      echo "$pid"
    fi
  done || true)
  [ -z "$LIVE_SESSIONS" ] ||
    fail "live $HARNESS session(s) [$LIVE_SESSIONS] hold the sandbox — stop them before wiping ($SANDBOX is disposable but they will corrupt the rebuilt state)"
fi

# 2. Mirror maintenance — submodule remote is a bare clone of this repo ------
MIRROR="$REPO_ROOT/../mythic-quest-mirror.git"
if [ -d "$MIRROR" ]; then
  # '+' forces: the mirror is disposable and must track HEAD even across
  # history rewrites; a plain fetch wedges future runs on stale refs.
  git --git-dir="$MIRROR" fetch -q "$REPO_ROOT" "+refs/heads/*:refs/heads/*" ||
    fail "mirror fetch failed — check $MIRROR"
else
  # --no-local: the worktree has ignored dirs that break local clones
  git clone --bare --no-local -q "$REPO_ROOT" "$MIRROR" ||
    fail "could not create bare mirror at $MIRROR"
fi

HEAD_SHA=$(git rev-parse HEAD) ||
  fail "harness HEAD unreadable — unbalanced repo state?"
[ -n "$(git ls-files .agents)" ] ||
  fail "harness has no committed .agents tree — commit first (the submodule pins COMMITTED state)"

# 3. Wipe and rebuild the sandbox ---------------------------------------------
command rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"

# 4. Consumer repo + .agents submodule at harness HEAD -----------------------
git -C "$SANDBOX" init -q
git -C "$SANDBOX" -c protocol.file.allow=always \
  submodule add -q --name agents "$MIRROR" .agents ||
  fail "submodule add failed (mirror: $MIRROR)"
git -C "$SANDBOX/.agents" checkout -q "$HEAD_SHA" ||
  fail "submodule checkout of $HEAD_SHA failed"
git -C "$SANDBOX" add .agents
git -C "$SANDBOX" -c user.name=harness -c user.email=harness@local \
  commit -qm "chore: pin harness @ ${HEAD_SHA:0:8} (.agents submodule)"

# 4b. Stage game-build skills: flat skills/ dir merging engine-agnostic core
# skills (repo skills/) with the chosen engine plugin's skills. Symlinks keep
# a single source of truth — no copies to drift.
stage_skill() { # <target-name> <source-rel-path-from-skills-dir>
  [ -d "$SANDBOX/$2" ] || fail "cannot stage skill '$1': $2 missing"
  ln -s "../$2" "$SANDBOX/skills/$1"
}
mkdir -p "$SANDBOX/skills"
for skill_dir in "$REPO_ROOT/skills"/*/; do
  name="$(basename "$skill_dir")"
  stage_skill "$name" ".agents/skills/$name"
done
for skill_dir in "$PLUGIN_DIR/skills"/*/; do
  name="$(basename "$skill_dir")"
  stage_skill "$name" ".agents/plugins/engine/$ENGINE/skills/$name"
done

# 5. Seed the sandbox ledger and harness instructions -------------------------
(cd "$SANDBOX" && bd init --quiet --stealth) >/dev/null 2>&1 ||
  fail "bd init failed in sandbox (is bd on PATH?)"
[ -d "$SANDBOX/.beads" ] || fail "sandbox .beads/ missing after bd init"

(cd "$SANDBOX" && bd setup "$HARNESS") >/dev/null 2>&1 ||
  fail "bd setup $HARNESS failed in sandbox (is bd on PATH? valid recipe?)"
EXPECTED_FILE=$(expected_file)
[ -f "$SANDBOX/$EXPECTED_FILE" ] ||
  fail "sandbox $EXPECTED_FILE missing after bd setup $HARNESS"

# Some recipes (e.g. codex) also install files INTO .agents/ (a skill into
# .agents/skills/) — but .agents is the harness submodule, so those files
# dirty its worktree. Checkout-local excludes hide them from both repos'
# status without committing generated content into either (same trick the
# old MythicQuest prep used for node_modules).
SUB_GD=$(git -C "$SANDBOX/.agents" rev-parse --absolute-git-dir)
if git -C "$SANDBOX/.agents" status --porcelain | grep -q '^??'; then
  mkdir -p "$SUB_GD/info"
  git -C "$SANDBOX/.agents" status --porcelain | sed -n 's/^?? \(.*\)$/\1/p' \
    >> "$SUB_GD/info/exclude"
fi

git -C "$SANDBOX" add -A 2>/dev/null || true
git -C "$SANDBOX" -c user.name=harness -c user.email=harness@local \
  commit -qm "chore: bd ledger + managed instructions ($HARNESS)" >/dev/null 2>&1 ||
  fail "seed commit failed"

# 5. Verify engine plugin requirements (manifest-driven) ----------------------
MANIFEST="$PLUGIN_DIR/engine.yaml"
[ -f "$MANIFEST" ] || fail "engine manifest missing: $MANIFEST"

# Parse engine version requirement (simple YAML grep — not a full parser)
# Extracts the version under requirements.binary.version
ENGINE_VERSION_REQ=$(grep -A3 "^  binary:" "$MANIFEST" | grep "version:" | head -1 | sed 's/.*version:[[:space:]]*//' | tr -d '"' | tr -d "'")
[ -n "$ENGINE_VERSION_REQ" ] || fail "engine version requirement missing from manifest"

# Health check command (if defined)
HEALTH_CHECK=$(grep -A5 "^health_check:" "$MANIFEST" | grep "^  - command:" | head -1 | sed 's/.*- command:[[:space:]]*//')
if [ -n "$HEALTH_CHECK" ]; then
  # Run health check (may need path substitution for MCP runtime)
  eval "$HEALTH_CHECK" >/dev/null 2>&1 ||
    fail "engine health check failed: $HEALTH_CHECK"
fi

# 6. Fail-loud verification ---------------------------------------------------
# Top-level agents/ and skills/ are the game-build surface (may not exist
# yet — the harness pins whatever IS committed). The internals must be there.
AGENTS_TREE="$SANDBOX/.agents"
[ "$(git -C "$AGENTS_TREE" rev-parse HEAD)" = "$HEAD_SHA" ] ||
  fail "submodule HEAD drifted from harness HEAD"
[ -f "$AGENTS_TREE/.agents/lint/rules.yaml" ] ||
  fail "governance rules missing in submodule: .agents/lint/rules.yaml"
[ -d "$SANDBOX/skills" ] || fail "skills/ staging missing"
git -C "$SANDBOX" status --porcelain | grep -q . &&
  fail "unexpected dirty files in sandbox"

printf 'READY: %s | harness @ %s (%s, %s) | git initialized | ledger seeded | skills staged\n' \
  "$SANDBOX" "${HEAD_SHA:0:8}" "$HARNESS" "$ENGINE"
printf 'next: cd %s && %s (game-build session)\n' "$SANDBOX" "$HARNESS"
