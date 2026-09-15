# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd prime` for full workflow context.

> Architecture and sync anti-patterns: see the generated blocks below and
> [SYNC_CONCEPTS.md](https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md).

## Scope Boundary: Pipeline-Dev vs Game-Build (MANDATORY)

This repo serves TWO audiences with STRICTLY DISJOINT ledgers. Violating this
boundary has caused repeated real mistakes — read this section before
creating or moving ANY file.

- **Pipeline-dev** (this repo's own sessions): infrastructure work —
  skills, agent profiles, sandbox-init, lint, governance. Its beads live
  in THIS repo's `.beads/` and track infra tasks only.
- **Game-build** (sandbox sessions under `test/<name>/`): actual game
  content — VISION.md, game beads, the poured molecule, game code. Its
  beads live in the sandbox's `.beads/`.

### Placement rules

1. **This repo's `.beads/` is pipeline-dev territory.** NEVER put
   game-build artifacts (formulas, molecules, game tasks) there. A game
   formula in the pipeline ledger conflates the two worlds — this exact
   mistake has been made and reverted twice.
2. **Game-build infrastructure ships as repo CONTENT** in game-build
   surface dirs at the repo root, existing only to be deployed into
   sandboxes at init:
   - `skills/` — engine-agnostic game skills (genesis, ...)
   - `plugins/engine/<engine>/` — engine plugins (skills, mcp.json)
   - `agents/` — game-build agent profiles (build, poppy, rachel, ian,
     pootie)
   - `workflows/` — game-build formulas (game-run.formula.toml)
   None of these are for pipeline-dev sessions to execute, pour, or claim.
3. **Pipeline internals stay nested** under `.agents/` (lint,
   sandbox-init) — invisible to game-build sessions (mounted behind
   `.agents/.agents/` in the sandbox).
4. **Deployment is one-way, at init time**: `sandbox-init` copies agents
   + formulas into the sandbox and renders the AGENTS.md contract. After
   init, the game session is self-contained; it never writes back here.
5. **Litmus test before creating a file**: "Will a game-build session
   consume this, or a pipeline-dev session?" Game consumer → root surface
   dir (`skills/`, `agents/`, `plugins/`, `workflows/`). Pipeline consumer
   → `.agents/`. Neither → `.beads/formulas/` is always wrong.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work atomically
bd close <id>         # Complete work
bd dolt push          # Push beads data to remote
```

## Non-Interactive Shell Commands

Some shells alias `cp`, `mv`, `rm` (and others) into interactive mode,
which hangs agents. The safest strategy: invoke them as
`command cp source dest`, `command rm -f file`, etc. — `command` bypasses
aliases unconditionally and avoids guessing which flags each platform needs.
For tools without aliases but confirmation prompts (`scp`, `ssh`, `apt-get`,
`brew`), pass their non-interactive flags
(`-o BatchMode=yes`, `-y`, `HOMEBREW_NO_AUTO_UPDATE=1`).

<!-- BEGIN BEADS INTEGRATION v:1 profile:full hash:9c890b20 -->
## Issue Tracking with bd (beads)

**IMPORTANT**: This project uses **bd (beads)** for ALL issue tracking. Do NOT use markdown TODOs, task lists, or other tracking methods.

### Why bd?

- Dependency-aware: Track blockers and relationships between issues
- Git-friendly: Dolt-powered version control with native sync
- Agent-optimized: JSON output, ready work detection, discovered-from links
- Prevents duplicate tracking systems and confusion

### Quick Start

**Check for ready work:**

```bash
bd ready --json
```

**Create new issues:**

```bash
bd create "Issue title" --description="Detailed context" -t bug|feature|task -p 0-4 --json
bd create "Issue title" --description="What this issue is about" -p 1 --deps discovered-from:bd-123 --json
```

**Claim and update:**

```bash
bd update <id> --claim --json
bd update bd-42 --priority 1 --json
```

**Complete work:**

```bash
bd close bd-42 --reason "Completed" --json
```

### Issue Types

- `bug` - Something broken
- `feature` - New functionality
- `task` - Work item (tests, docs, refactoring)
- `epic` - Large feature with subtasks
- `chore` - Maintenance (dependencies, tooling)

### Priorities

- `0` - Critical (security, data loss, broken builds)
- `1` - High (major features, important bugs)
- `2` - Medium (default, nice-to-have)
- `3` - Low (polish, optimization)
- `4` - Backlog (future ideas)

### Workflow for AI Agents

1. **Check ready work**: `bd ready` shows unblocked issues
2. **Claim your task atomically**: `bd update <id> --claim`
3. **Work on it**: Implement, test, document
4. **Discover new work?** Create linked issue:
   - `bd create "Found bug" --description="Details about what was found" -p 1 --deps discovered-from:<parent-id>`
5. **Complete**: `bd close <id> --reason "Done"`

### Quality
- Use `--acceptance` and `--design` fields when creating issues
- Use `--validate` to check description completeness

### Lifecycle
- `bd defer <id>` / `bd supersede <id>` for issue management
- `bd stale` / `bd orphans` / `bd lint` for hygiene
- `bd human <id>` to flag for human decisions
- `bd formula list` / `bd mol pour <name>` for structured workflows

### Sync

bd stores issue history in Dolt:

- Each write auto-commits to Dolt history
- Do not treat `.beads/issues.jsonl` as the sync protocol

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.

### Important Rules

- ✅ Use bd for ALL task tracking
- ✅ Always use `--json` flag for programmatic use
- ✅ Link discovered work with `discovered-from` dependencies
- ✅ Check `bd ready` before asking "what should I work on?"
- ❌ Do NOT create markdown TODO lists
- ❌ Do NOT use external issue trackers
- ❌ Do NOT duplicate tracking systems

For more details, see README.md and https://github.com/gastownhall/beads/blob/main/docs/getting-started/quickstart.md.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.

<!-- END BEADS INTEGRATION -->


## Governance Rules

All governance rules live in `.agents/lint/rules.yaml` (single source of truth) and are enforced by the `lint` skill. Do not restate them here.
