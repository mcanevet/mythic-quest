#!/usr/bin/env bash
# init.sh — reset a sandbox to a pristine, launch-ready state.
#
# Layout (production-faithful consumer layout):
#
#   test/<name>/              <- fresh consumer git repo (git init)
#   └── .agents/              <- git SUBMODULE -> this pipeline-dev repo @ committed HEAD
#       ├── skills/           <- engine-agnostic game-build skills
#       ├── plugins/engine/<engine>/skills/  <- engine plugin skills
#       └── .agents/          <- pipeline-dev internals (lint, sandbox-init)
#
# The whole pipeline-dev repo is mounted at .agents: game-build skills and
# agents live at the REPO TOP LEVEL (skills/, plugins/, agents/) so the
# consumer session reads them at .agents/skills/..., .agents/plugins/...,
# and .agents/agents/... (harness agent files). Pipeline-dev skills live
# nested under .agents/.agents/ and stay behind.
# All supported harnesses (opencode, codex, claude, ...) read .agents/
# natively. The harness argument selects the `bd setup <recipe>` that
# generates the right instructions file (AGENTS.md, CLAUDE.md, ...).
#
# The submodule pins the CURRENT COMMITTED HEAD: the consumer repo's
# history records WHICH commit a sandbox was built against. Git refuses a
# submodule URL equal to the superproject, so the submodule points at a
# sibling BARE MIRROR (../mythic-quest-mirror.git) that this script creates
# and refreshes from HEAD first.
#
# Guarantees (idempotent — safe to run repeatedly):
#   1. Refuses to wipe a sandbox held by a live session of the target
#      harness (zombie contamination guard).
#   2. Sandbox wiped completely (disposable by contract) then rebuilt.
#   3. .agents submodule pinned to the CURRENT COMMITTED HEAD.
#      Uncommitted changes are EXCLUDED (commit first — that is the
#      reproducibility point).
#   4. Fresh consumer git repo; its first commit pins the SHA.
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
warn() { printf 'init.sh: WARN: %s\n' "$1" >&2; }

[ -n "$HARNESS" ] ||
  fail "harness required: init.sh <opencode|codex|claude> <engine> [sandbox-name]"
[ -n "$ENGINE" ] ||
  fail "engine required: init.sh <harness> <godot|...> [sandbox-name]"

PLUGIN_DIR="$REPO_ROOT/plugins/engine/$ENGINE"
REL_PLUGIN_SKILLS=".agents/plugins/engine/$ENGINE/skills"
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
  git --git-dir="$MIRROR" fetch -q "$REPO_ROOT" "+refs/heads/*:refs/heads/*" ||
    fail "mirror fetch failed — check $MIRROR"
else
  git clone --bare --no-local -q "$REPO_ROOT" "$MIRROR" ||
    fail "could not create bare mirror at $MIRROR"
fi

HEAD_SHA=$(git rev-parse HEAD) ||
  fail "HEAD unreadable — unbalanced repo state?"
[ -n "$(git ls-files .agents)" ] ||
  fail "no committed .agents tree — commit first (the submodule pins COMMITTED state)"

# 3. Wipe and rebuild the sandbox ---------------------------------------------
command rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"

# 4. Consumer repo + .agents submodule at HEAD --------------------------------
git -C "$SANDBOX" init -q
git -C "$SANDBOX" -c protocol.file.allow=always \
  submodule add -q --name agents "$MIRROR" .agents ||
  fail "submodule add failed (mirror: $MIRROR)"
git -C "$SANDBOX/.agents" checkout -q "$HEAD_SHA" ||
  fail "submodule checkout of $HEAD_SHA failed"
git -C "$SANDBOX" add .agents
git -C "$SANDBOX" -c user.name=harness -c user.email=harness@local \
  commit -qm "chore: pin pipeline-dev @ ${HEAD_SHA:0:8} (.agents submodule)"

# 5. Seed the sandbox ledger and harness instructions -------------------------
# bd version for game-build sessions: 1.3.0-rc.2 is REQUIRED (new bd features
# used by game-build skills). This is an independent sandbox DB — unrelated to
# the pipeline-dev repo's ledger — but init and session must resolve the SAME
# version, else the session hits schema skew. All bd invocations below run via
# mise against this pin, never the invoking shell's PATH bd.
BD_VERSION="1.3.0-rc.2"
BD_TOOL="github:gastownhall/beads"

cat > "$SANDBOX/mise.toml" <<MISE
# Game-build session toolchain.
# bd is pinned to the version that initialized this ledger; resolved via mise
# regardless of the user's PATH. Requires bd ${BD_VERSION} features.
[tools]
"${BD_TOOL}" = "${BD_VERSION}"
MISE
mise install -C "$SANDBOX" >/dev/null 2>&1 ||
  fail "mise install failed for bd ${BD_VERSION} in sandbox"

(cd "$SANDBOX" && bd init --quiet --stealth --remote "") >/dev/null 2>&1 ||
  fail "bd init failed in sandbox (bd ${BD_VERSION})"
[ -d "$SANDBOX/.beads" ] || fail "sandbox .beads/ missing after bd init"

# Ledger isolation guard: the sandbox sits INSIDE the pipeline-dev repo, whose
# git origin carries refs/dolt/data. Without an explicit opt-out, bd init
# auto-wires that origin as sync.remote + a Dolt remote, silently cloning the
# pipeline ledger into the sandbox (and risking writes flowing back). The empty
# --remote above is the opt-out; these assertions make a regression fail loud.
if grep -qE '^sync\.remote: "?..*' "$SANDBOX/.beads/config.yaml" 2>/dev/null; then
  fail "ledger isolation violated: sync.remote set in sandbox config.yaml (bd init ignored empty --remote?)"
fi
if [ -n "$(cd "$SANDBOX" && mise exec -C . -- bd dolt remote list 2>/dev/null | grep -v '^No remotes')" ]; then
  fail "ledger isolation violated: Dolt remote(s) configured in sandbox ledger"
fi

# Deploy the game-run formula into the sandbox's OWN ledger. The formula is
# game-build infrastructure shipped as repo content (workflows/), NOT part of
# the pipeline-dev ledger's .beads/ namespace — sandboxes pour it from their
# own .beads/formulas/ so the two ledgers stay disjoint. Skeleton: genesis ->
# raw-backlog -> grooming -> dev (poppy) -> qa (rachel) -> vision (ian) ->
# consumer (pootie) -> release, with waits_for fan-ins and human gates.
FORMULA_SRC="$REPO_ROOT/workflows/game-run.formula.toml"
[ -f "$FORMULA_SRC" ] ||
  fail "game-run formula missing from pipeline repo (workflows/)"
mkdir -p "$SANDBOX/.beads/formulas"
command cp "$FORMULA_SRC" "$SANDBOX/.beads/formulas/" ||
  fail "failed to copy game-run formula into sandbox"

# milestone-template: poured per-milestone by the orchestrator. Copy + cook
# it too, or `bd mol pour milestone-template` fails 'not found' and the
# orchestrator hand-builds the milestone anatomy (observed wt16: ~10
# recovery turns + miswired epic-blocked-by-molecule deps).
MILESTONE_SRC="$REPO_ROOT/workflows/milestone-template.formula.toml"
if [ -f "$MILESTONE_SRC" ]; then
  command cp "$MILESTONE_SRC" "$SANDBOX/.beads/formulas/" ||
    warn "failed to copy milestone-template formula into sandbox"
else
  warn "milestone-template formula missing from pipeline repo (workflows/)"
fi

# Persist the cooked proto so `bd mol pour game-run` finds it by NAME.
# (walkthrough8, 2026-09-17: the orchestrator's `bd mol pour game-run` failed
# with 'not found as formula or proto ID' — a copied formula alone does not
# register a pourable proto; the pour-by-name path needs the cooked proto
# persisted in the ledger. Template-labeled beads are hidden from bd list /
# bd ready, so they don't pollute the session's queues.)
(
  cd "$SANDBOX" &&
  mise exec -C . -- bd cook game-run --persist >/dev/null 2>&1 &&
  mise exec -C . -- bd mol pour game-run --var game_title=__INIT_VERIFY__ --dry-run >/dev/null 2>&1
) || fail "game-run proto registration failed (cook --persist / pour --dry-run)"

# Cook milestone-template's proto too — same pour-by-name requirement.
(
  cd "$SANDBOX" &&
  mise exec -C . -- bd cook milestone-template --persist >/dev/null 2>&1 &&
  mise exec -C . -- bd mol pour milestone-template --var theme=__INIT_VERIFY__ --var index=0 --dry-run >/dev/null 2>&1
) || warn "milestone-template proto registration failed (cook --persist / pour --dry-run)"

(cd "$SANDBOX" && bd setup "$HARNESS") >/dev/null 2>&1 ||
  fail "bd setup $HARNESS failed in sandbox (valid recipe?)"
EXPECTED_FILE=$(expected_file)
[ -f "$SANDBOX/$EXPECTED_FILE" ] ||
  fail "sandbox $EXPECTED_FILE missing after bd setup $HARNESS"

# 5b. Append the game-build loop contract (the orchestrator's ruleset).
# This block IS the control plane: it owns the molecule lifecycle,
# bead wiring, and the dev loop. Skills (genesis, create-*) are content
# and implementation only. Rendered below the bd-managed instructions
# so the session treats it as standing orders.
# NOTE: This CONTRACT heredoc is the progressive-disclosure rendering of
# agents/build.md into sandbox AGENTS.md — agents/build.md is the SOURCE OF
# TRUTH. Generated content: when editing the contract, change agents/build.md
# first, then mirror the change here (this script cannot read it at render
# time because the sandbox layout differs). Drift check: the lint rule
# single-source-of-truth covers both files; keep the bodies byte-identical
# where structure permits.
cat >> "$SANDBOX/$EXPECTED_FILE" <<'CONTRACT'

## Game-Build Session Contract (orchestrator)

You run as the **build** agent (see .opencode/agents/build.md): the
orchestrator. You own the workflow; role agents (**poppy**, **rachel**, **ian**,
**pootie**) own implementation, QA, vision, and consumer critique. Follow this
multi-loop workflow:

1. **Bootstrap (once, if needed)** — pour the molecule:
   - If no `VISION.md` exists: dispatch genesis skill
     (`skills/genesis/SKILL.md`) — produces VISION.md and spawns raw task
     children under the `raw-backlog` step.
   - If no molecule epic exists (`bd list --type epic` is empty): pour the
     pre-registered game-run proto (sandbox-init persisted it — no cook
     step needed):
     ```bash
     bd mol pour game-run --var game_title="<from VISION.md>"
     ```
     The formula creates the skeleton: genesis → raw-backlog →
     backlog-grooming → dev-loop → qa-gate → vision-gate → consumer-gate →
     release.

2. **Backlog grooming** — route raw children:
   - For each raw child of the `raw-backlog` step:
     - Decide assignee: poppy (implementation), phil (materials),
       stephen (animation), gustavo (audio), rachel (QA), ian (vision),
       pootie (consumer)
     - Add skill label: `skill:<skill-name>` (create-entity, create-ui,
       apply-material, apply-animation, apply-audio, etc.)
     - Update description with "Use skill: <skill-name>"
   - Example:
     ```bash
     bd update <id> --assignee poppy
     bd update <id> --set-labels "skill:create-entity"
     bd update <id> --description "Use skill: create-entity"
     ```

3. **Dev loop (repeat until dev-loop is complete)**:
   - Claim beads assigned to you (build): `bd ready --json`
   - Dispatch to role agents via Task tool with bead ID and context
   - After each agent returns: verify the close reason (`bd show <id>`)
   - Gate supervision between dispatches:
     - `bd gate check` — auto-resolve timer/gh gates
     - `bd reclaim` — reclaim stale claims (dead workers)
     - `bd mol current` — check molecule progress

4. **Gate resolution** — human gates close manually:
   - **qa-gate**: rachel verifies all children PASS → `bd gate resolve rachel-qa-signoff`
   - **vision-gate**: ian validates against VISION.md → `bd gate resolve ian-vision-review`
   - **consumer-gate**: pootie accepts the experience → `bd gate resolve pootie-consumer-acceptance`
   - Bugs discovered during gates are spawned as **unassigned** children of
     the gate (`--parent <gate-id>`) so the `waits_for` catches them; you
     then groom them (assignee + skill) like any raw bead, and dev-loop
     fixes them.

5. **Release** — close the molecule:
   - When consumer-gate closes, claim and close the release bead
   - Close the molecule epic
   - Report summary: game title, beads closed (PASS/FAIL), discoveries,
     final verdicts

**You never implement yourself** — no file writes, no non-bd commands.
Everything goes through role agents.
CONTRACT

git -C "$SANDBOX" add -A 2>/dev/null || true

# Some recipes (e.g. codex) install files INTO .agents/ — but .agents is the
# submodule, so those files dirty its worktree. Checkout-local excludes hide
# them from both repos' status (same trick the old repo used for node_modules).
SUB_GD=$(git -C "$SANDBOX/.agents" rev-parse --absolute-git-dir)
if git -C "$SANDBOX/.agents" status --porcelain | grep -q '^??'; then
  mkdir -p "$SUB_GD/info"
  git -C "$SANDBOX/.agents" status --porcelain | sed -n 's/^?? \(.*\)$/\1/p' \
    >> "$SUB_GD/info/exclude"
fi

# 5a. Render game-build agent profiles into the sandbox ------------------------
# agents/*.md at repo root define the build (orchestrator) + poppy
# (implementer) split (mythic-quest-iko). Copied (not symlinked) into the
# harness's agent dir so each sandbox owns its copy; deny-baseline-first
# permissions are structural, per-agent.
if [ -d "$REPO_ROOT/agents" ]; then
  AGENT_DIR="$SANDBOX/.opencode/agents"
  mkdir -p "$AGENT_DIR"
  command cp "$REPO_ROOT"/agents/*.md "$AGENT_DIR/" ||
    fail "failed to copy agent profiles"
  [ -f "$AGENT_DIR/build.md" ] && [ -f "$AGENT_DIR/poppy.md" ] ||
    fail "agent profiles incomplete (need build.md + poppy.md)"
fi

git -C "$SANDBOX" add -A 2>/dev/null || true
git -C "$SANDBOX" -c user.name=harness -c user.email=harness@local \
  commit -qm "chore: bd ledger + managed instructions ($HARNESS)" >/dev/null 2>&1 ||
  fail "seed commit failed"

# 5b. Merge slot ------------------------------------------------------------------
# The rig's single merge slot (<prefix>-merge-slot) guards the merge-review
# phase of the build orchestrator (atomic exclusion for trunk checkout/
# merge; created here so the orchestrator never races a nonexistent slot).
if ! (cd "$SANDBOX" && bd merge-slot create) >/dev/null 2>&1; then
  warn "merge-slot create failed (orchestrator can create it later via 'bd merge-slot create')"
fi

# 5c. Engine MCP servers -> harness config -------------------------------------
# The engine plugin declares MCP servers (plugins/engine/<engine>/mcp.json,
# format: {"<server-name>": {command,args,env}}). We render them into the
# harness's config file so the game-build session can use them. Configured
# servers are FAIL-soft: if a render fails we warn but continue (the session
# can still build via file-based flows).

# 5d. Sandbox path fence (fail-fast, not hang) — harness-specific ----------
# opencode defaults external_directory to "ask"; subagents cannot surface
# an ask prompt, so ANY tool touching a path outside the sandbox root
# (cd .., cat ../x, cp /System/..., glob <repo-root>) hangs the worker
# forever (four wt17 incidents). Deny-by-default makes those calls fail
# fast with a visible permission error instead. Narrow read-only
# carve-outs for system font dirs (asset vendoring, wt17 phil).
if [ "$HARNESS" = "opencode" ]; then
  [ -s "$SANDBOX/opencode.json" ] || echo '{}' > "$SANDBOX/opencode.json"
  jq '.permission = ((.permission // {}) * {
        external_directory: {
          "*": "deny",
          "/System/Library/Fonts/*": "allow",
          "/Library/Fonts/*": "allow"
        }
      })' "$SANDBOX/opencode.json" > "$SANDBOX/opencode.json.tmp" &&
    mv "$SANDBOX/opencode.json.tmp" "$SANDBOX/opencode.json" ||
    fail "failed to write sandbox path fence into opencode.json"
fi
# Other harnesses (codex, claude): equivalent fencing TBD —
# .claude/settings.json permissions and codex sandbox configs differ;
# add per-harness blocks here as they are exercised.

MCP_JSON="$PLUGIN_DIR/mcp.json"
if [ -f "$MCP_JSON" ] && command -v jq >/dev/null 2>&1; then
  # Use jq to iterate safely (handles server names with spaces)
  while IFS= read -r SERVER; do
    [ -z "$SERVER" ] && continue
    CMD=$(jq -r ".[\"$SERVER\"].command // empty" "$MCP_JSON")
    ARGS=$(jq -r ".[\"$SERVER\"].args // [] | @json" "$MCP_JSON")
    ENV_JSON=$(jq -r ".[\"$SERVER\"].env // {} | @json" "$MCP_JSON")
    case "$HARNESS" in
      opencode)
        # opencode: opencode.json — command is [cmd, *args], enabled required
        [ -s "$SANDBOX/opencode.json" ] || echo '{}' > "$SANDBOX/opencode.json"
        jq --arg cmd "$CMD" --argjson args "$ARGS" --argjson env "$ENV_JSON" \
          '.mcp[$SERVER] = {type: "local", enabled: true, command: ([$cmd] + $args), environment: $env, timeout: 30000}' \
          --arg SERVER "$SERVER" "$SANDBOX/opencode.json" > "$SANDBOX/opencode.json.tmp" &&
          mv "$SANDBOX/opencode.json.tmp" "$SANDBOX/opencode.json" ||
          warn "opencode MCP render failed for $SERVER"
        # Engine plugin skills (.agents/plugins/engine/<engine>/skills) are not
        # scanned by the harness skill tool by default; register the folder via
        # skills.paths so `skill <name>` resolves without symlinks/copies.
        # (walkthrough9: gustavo's `skill apply-audio` failed with "not found"
        # and cost a turn before falling back to reading the file.)
        [ -d "$PLUGIN_DIR/skills" ] &&
          jq '.skills.paths = ((.skills.paths // []) + [$pluginSkills])' \
            --arg pluginSkills "$REL_PLUGIN_SKILLS" "$SANDBOX/opencode.json" \
            > "$SANDBOX/opencode.json.tmp" &&
          mv "$SANDBOX/opencode.json.tmp" "$SANDBOX/opencode.json" ||
          warn "opencode skills.path registration failed for $SERVER"
        ;;
      claude)
        # Claude Code: .mcp.json at project root, top-level server entries
        [ -s "$SANDBOX/.mcp.json" ] || echo '{}' > "$SANDBOX/.mcp.json"
        jq --arg cmd "$CMD" --argjson args "$ARGS" --argjson env "$ENV_JSON" \
          '.[$SERVER] = {type: "stdio", command: $cmd, args: $args, env: $env}' \
          --arg SERVER "$SERVER" "$SANDBOX/.mcp.json" > "$SANDBOX/.mcp.json.tmp" &&
          mv "$SANDBOX/.mcp.json.tmp" "$SANDBOX/.mcp.json" ||
          warn "claude MCP render failed for $SERVER"
        ;;
      *)
        warn "MCP render for harness '$HARNESS' not implemented — configure manually"
        ;;
    esac
  done < <(jq -r 'keys[]' "$MCP_JSON")
  git -C "$SANDBOX" add -A 2>/dev/null || true
  git -C "$SANDBOX" -c user.name=harness -c user.email=harness@local \
    commit -qm "chore: engine MCP servers ($ENGINE)" >/dev/null 2>&1 || true
fi

# 6. Fail-loud verification ---------------------------------------------------
git -C "$SANDBOX" status --porcelain | grep -q . &&
  fail "unexpected dirty files in sandbox"

printf 'READY: %s | repo @ %s (%s, %s) | git initialized | ledger seeded\n' \
  "$SANDBOX" "${HEAD_SHA:0:8}" "$HARNESS" "$ENGINE"
printf 'next: cd %s && %s (game-build session)\n' "$SANDBOX" "$HARNESS"
