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

(cd "$SANDBOX" && bd init --quiet --stealth) >/dev/null 2>&1 ||
  fail "bd init failed in sandbox (bd ${BD_VERSION})"
[ -d "$SANDBOX/.beads" ] || fail "sandbox .beads/ missing after bd init"

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
cat >> "$SANDBOX/$EXPECTED_FILE" <<'CONTRACT'

## Game-Build Session Contract (orchestrator)

You run as the **build** agent (see .opencode/agents/build.md): the
orchestrator. You own the workflow; **poppy** (subagent) owns implementation.
Follow this loop:

1. **Bootstrap (once, if needed)** — dispatch to poppy:
   - If no `VISION.md`: brief poppy to run the genesis skill
     (`.agents/skills/genesis/SKILL.md`) — produces VISION.md + BACKLOG.md.
   - If no molecule epic exists (check: `bd list --type epic`
     is empty): brief poppy to pour the molecule — create the epic, parent
     one bead per BACKLOG.md task (labels/priorities per the backlog), and
     wire the release chain: playtest bead + release bead as children,
     release `bd dep add`-blocked on playtest, playtest blocked on all dev
     beads.
   - One bead per BACKLOG.md task; no extra beads at bootstrap.

2. **Dev loop (repeat until nothing is ready)**:
   - Inspect the frontier: `bd ready --json`
   - Pick the highest-priority ready bead; dispatch it to poppy via the Task
     tool with the bead ID and any context (which skill applies:
     `.agents/plugins/engine/<engine>/skills/...`).
   - After poppy returns: verify the close reason (`bd show
     <id>`) — honest verdicts only; "stubs ready" is not a PASS. If poppy
     reported discoveries, they are already filed via `discovered-from`.
   - **You never implement yourself** — no file writes, no non-bd commands.
     Everything goes through poppy.

3. **Stop condition**: `bd ready` returns nothing and the epic has no open
   children — the board is drained. Report a summary: game title, beads
   closed (PASS/FAIL counts), discoveries filed, final playtest verdict.
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

# 5c. Engine MCP servers -> harness config -------------------------------------
# The engine plugin declares MCP servers (plugins/engine/<engine>/mcp.json,
# format: {"<server-name>": {command,args,env}}). We render them into the
# harness's config file so the game-build session can use them. Configured
# servers are FAIL-soft: if a render fails we warn but continue (the session
# can still build via file-based flows).
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
