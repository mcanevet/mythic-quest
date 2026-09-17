# Session Database Debugging Guide

Diagnose game-build session failures and monitor live sessions by querying
opencode's SQLite session database and correlating with project filesystem state.
Harness-level (not game-level): this is about the agent swarm's behavior, not
the game's.

## When to use

- A game-build session stalled, died, or produced unexpected results
- A subagent returned an empty `<task_result>` or `⛔ BLOCKED`
- A subagent reports "No MCP runtime tools appear..."
- Multi-hour `time_updated` gaps and you need to distinguish host sleep from a real stall
- Post-hoc analysis of a completed run (retry patterns, skill choice correlation)

## Quick Start

The opencode session DB lives at `~/.local/share/opencode/opencode.db` and
runs in **WAL mode — query it directly while sessions are active**; readers
don't block writers, no snapshot copy needed.

### 1. Find the active session and its subagent tree

```bash
sqlite3 ~/.local/share/opencode/opencode.db \
  "SELECT id, slug, title, time_created, agent FROM session WHERE project_id = '$(sqlite3 ~/.local/share/opencode/opencode.db "SELECT id FROM project WHERE path = \"$(pwd)")' AND parent_id IS NULL ORDER BY time_created DESC LIMIT 1;"
```

Then list children (subagents) under that root:

```bash
ROOT_ID="ses_xxx"
sqlite3 ~/.local/share/opencode/opencode.db \
  "SELECT id, slug, agent, time_created, time_updated FROM session WHERE parent_id = '$ROOT_ID' ORDER BY time_created;"
```

### 2. Inspect reasoning traces

Check reasoning **first** — it reveals the agent's decision process, not just
outcomes:

```bash
sqlite3 ~/.local/share/opencode/opencode.db \
  "SELECT json_extract(data, '$.text') FROM part WHERE session_id = '$ROOT_ID' AND json_extract(data, '$.type') = 'reasoning' ORDER BY time_created DESC LIMIT 5;"
```

### 3. Correlate with filesystem state

```bash
bd_ledger.sh ready 2>/dev/null | head -30 # stuck beads? (or: bd list --status in_progress)
ls -la plans/ scripts/                     # expected files exist?
ls -la .opencode/skills/                   # symlinks resolve?
find .opencode/skills -name "*.sh" -not -executable   # missing exec bits?
```

### 4. Watch for stalls in real time

Run [`scripts/watch_session.sh`](scripts/watch_session.sh) — see the script
header for usage. Key metric: `time_updated` deltas. A session with no update
in >60s **and zero tool-call activity** likely stalled — but confirm via
reasoning traces first (see Gotchas below).

For **root-session** stalls use [`scripts/watch_root.sh`](scripts/watch_root.sh)
instead — it watches the root's own part activity AND its child-tree freshness.
Motivation (observed 09-04, ling run): a root can emit one truncated mega-step
(`finish: length` at high context) and sit brain-dead for hours with the opencode
process alive while **no subagents run** — `watch_session.sh` on any child shows
nothing because there are no children to watch. `watch_root.sh` fires only when
root parts are stale *and* no child session updated recently, and prints host
diagnostics (process uptime, `kern.waketime`) to disambiguate brain-death from
host sleep (AGENTS.md stopping-condition caveat: verify activity, not timestamps,
before intervening).

## Failure Mode Index

Consult [reference/failure-modes.md](reference/failure-modes.md) for the full
symptom → cause → fix table (MCP suicide via `pkill`, permission denials,
slug-not-found, silent subagent deaths, and more).

## Full Trace Extraction

For offline/pattern analysis, dump the complete session tree (see
[reference/trace-analysis.md](reference/trace-analysis.md)):

```bash
sqlite3 -json ~/.local/share/opencode/opencode.db \
  "WITH RECURSIVE session_tree(id, slug, agent, depth) AS (
     SELECT id, slug, agent, 0 FROM session WHERE id = '$ROOT_ID'
     UNION ALL
     SELECT s.id, s.slug, s.agent, st.depth+1 FROM session s JOIN session_tree st ON s.parent_id = st.id
   )
   SELECT st.slug, st.agent, json_extract(p.data, '$.type') as part_type,
          json_extract(p.data, '$.content') as content, p.time_created
   FROM session_tree st JOIN part p ON p.session_id = st.id
   ORDER BY p.time_created;" > /tmp/session_trace.json
```

## Gotchas

- **Host sleep ≠ stall.** Wall-clock gaps in `time_updated` can be laptop
  sleep. Diagnose by **tool-call activity**, not timestamps: a live-but-spinning
  subagent shows repeated model+tool calls with no progress; a sleeping host
  shows a break with none at all.
- **DB timestamps are ms since epoch** — divide by 1000 for unixepoch.
- **Field names drift across opencode versions** — `reasoning` parts have the payload at `$.text`, `tool` parts at `$.state.*`. Before extraction: check one sample row with `SELECT data FROM part WHERE session_id='$ROOT_ID' LIMIT 1` and inspect the JSON shape.
- **Use `-json` + `jq` (or python)** — raw SQLite output is hard to parse.
- **Keep session IDs handy** — the root ID links to all subagents.
- **MCP servers have no auto-reconnect.** Once the godot-mcp-runtime process
  dies (e.g. stray `pkill -f godot`), all engine tools are gone for the entire
  opencode session. The TUI sidebar still shows "Connected" (a startup
  snapshot, never refreshed). Only a full opencode restart restores tools.
- **Probe engine-tool questions via a real poppy delegation, never `opencode run` as the build agent.** The build/orchestrator agent denies `godot-mcp-runtime_*` by design, so a bare `opencode run` probe ALWAYS answers "tools absent" — a false positive that cost a full diagnostic cycle (09-01). Correct probe: `opencode run "Delegate to poppy: call godot-mcp-runtime_get_project_info and report verbatim"`.
- **Distinguish toolset-snapshot race from server death.** Successful MCP connections log NOTHING; absence of MCP log lines is not evidence of failure. Check the DB instead: zero failed `godot-mcp-runtime_*` calls + an "MCP unavailable" agent claim = likely snapshot race (session born before async handshake finished), not a dead server. Restart fixes both, but the diagnosis wording differs (see failure-modes.md).
- **Watch for format drift** — MCP tool parameters may change across versions;
  verify field names before assuming agent typos.

---

*Harness-introspection skill. Not for game-building tasks.*
