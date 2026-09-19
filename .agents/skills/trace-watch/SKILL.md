---
name: trace-watch
description: Live-monitor a running game-build session (walkthrough/benchmark) via the opencode session DB. Use while observing an active sandbox run to detect stalls, spawns, and hidden failures in real time.
---

# Trace-Watch: live monitoring of game-build sessions

Watch an active game-build sandbox run and catch failures as they happen —
not in the postmortem. The core discipline: **read tool outputs, not
intents**. Agent prose saying "proceeding" is rationalization, not evidence
that a command succeeded.

## Setup

Sessions live in `~/.local/share/opencode/opencode.db` (tables `session`,
`part`). Filter by sandbox directory:

```sql
SELECT s.id, s.time_created,
       (SELECT COUNT(*) FROM part p WHERE p.session_id = s.id)
FROM session s
WHERE s.directory LIKE '%<sandbox-name>%'
ORDER BY s.time_created ASC;
```

Each `part` row's `data` JSON has `type` (`text` | `tool`), and for tools a
`state` object with `input`, `output`, `error`.

## Poll loop

1. Poll every 5–10 minutes (adjust to run tempo). New session IDs =
   subagent dispatches.
2. Tail the two most recent sessions: recent parts, newest last.
3. Record subagent spawns, dispatch batch composition, gate transitions,
   stalls (>60s with no tool activity in the most active session).

## Monitoring rules (from real misses)

Derived from walkthrough9, where every `bd update --claim` was refused
(actor mismatch) for the WHOLE run while the live monitor watched tool
inputs and agent prose:

- **Read `state.output` for every state-changing command** (`bd
  create/update/close`, `--claim` calls, `git`, file writes). A refused
  command followed by the agent continuing ("treating the claim as held —
  proceeding") is a **defect signature**, not coping. Do not log it as
  healthy adaptation.
- **Verify state materialized.** If the workflow says claims put beads
  `in_progress`, spot-check `bd list` in the sandbox shows ◐ during
  dispatch windows. Zero ◐ across an entire run = systemic claim failure —
  investigate immediately, don't theorize.
- **Triage every error-shaped output**: `Error updating`, `refused`,
  `denied`, `failed`, permission-blocks. Even when the run ultimately
  succeeds, silent workarounds (working a bead without claiming it,
  hand-editing what a tool should have written) compound into unmeasured
  drift. File a pipeline-dev bead with the session/part evidence.
- **Query, don't theorize.** When state looks counterintuitive ("no beads
  in progress"), one targeted query — dump outputs for all `--claim` calls
  — beats a narrative built from prose.

## Useful queries

Tail a session (newest last):

```bash
sqlite3 -json ~/.local/share/opencode/opencode.db \
  "SELECT p.data FROM part p WHERE p.session_id='<id>' ORDER BY p.time_created, p.id" \
  | python3 -c "
import json,sys
for r in json.load(sys.stdin):
    d=json.loads(r['data'])
    if d.get('type')=='text': print('TEXT:', d.get('text','')[:250].replace(chr(10),' ¶ '))
    elif d.get('type')=='tool':
        st=d.get('state',{})
        print('TOOL:', d.get('tool'), '|', json.dumps(st.get('input',{}))[:130])
        out=str(st.get('output') or st.get('error') or '')
        if 'rror' in out or 'efused' in out or 'enied' in out: print('  ⚠ OUTPUT:', out[:300])
"
```

Audit all claim/command outcomes across a run (outputs, not inputs):

```bash
sqlite3 -json ~/.local/share/opencode/opencode.db \
  "SELECT p.data FROM part p WHERE p.data LIKE '%--claim%' OR p.data LIKE '%bd close%'" \
  | python3 -c "
import json,sys
for r in json.load(sys.stdin):
    d=json.loads(r['data'])
    if d.get('type')!='tool': continue
    st=d.get('state',{}); out=str(st.get('output') or '')
    cmd=json.dumps(st.get('input',{}))[:120]
    flag=('⚠' if ('rror' in out or 'efused' in out) else ' ')
    print(flag, cmd, '=>', out[:200])
"
```

Ledger cross-check (run inside the sandbox dir):

```bash
bd list            # any ◐ during active dispatches? should be
bd ready --json    # what the orchestrator sees as claimable
bd list --closed --json | jq length   # progress rate
```

## Retrospective review: per-specialist checklist

Post-run analysis (benchmark postmortems, walkthrough comparisons) must not
just answer the framing question (cost, pacing, routing). For EVERY specialist
session in the run, run this checklist — improvements hide inside PASSes that
recover gracefully and leave no alarm in a metrics scan:

1. **Claim**: right bead, right `--actor`, claim actually succeeded (output
   checked).
2. **Skill**: assigned skill read BEFORE acting (first reads of the session).
3. **Denials**: grep tool outputs for `denied`/`permission`/`not permitted` —
   filter corpus echoes (skill/README file content) from real refusals.
4. **Improvisation**: reasoning/text mentions `fallback`/`workaround`/
   `instead`/`cannot write` — each is a permission-stencil or tool gap.
5. **Silent corruption**: successful tool calls whose readback is wrong
   (zeroed/mangled data) — the tool reported success; only a read-back or a
   later worker reveals it.
6. **Close honesty**: close reason's claims traceable to in-session evidence.

Any hit on 3–5 is a pipeline-dev bead with the session/part IDs, even if the
run shipped fine — especially then.

**Mechanical first pass**: run the scanner before reading prose — it extracts
CLAIM/DENY/IMPROV/ERR signals per session with the corpus-echo filter applied:

```bash
python3 .agents/skills/trace-watch/scripts/scan.py <sandbox-name>
```

Read its output, then apply points 2, 5, and 6 (skill-before-action ordering,
readback verification, close honesty) by reading the flagged sessions —
those need judgment the scanner can't do. The cost/token lens composes with
this: run the metrics analysis AND the checklist; neither substitutes for
the other.

**Watch log**: post one `bd comment` per watch on the pipeline bead that
commissioned the review (or a dedicated watch-log bead), citing session/part
IDs — so successive watches accumulate instead of living in conversation.

**Known blind spots** (compensate by hand):
- Workers that die mid-flight look like clean finishes — cross-check session
  list against bead close actors (a bead closed by an actor who isn't the
  assignee is a repair dispatch, like phil's wt11 material work).
- Reasoning-model internal text may not all land in `reasoning` parts.
- One long-running tool call defeats the stall detector; check part timestamps.
- Corpus echoes can slip past the filter — a "denied" hit quoting file-content
  markers (`<path>`, line-number prefixes) is text about permissions, not a
  permission event.

## Escalation

- Stalled >10 min: check `pmset -g assertions` (host sleep masks as stall).
- Systemic refusal pattern (same error ≥3×): interrupting the run is
  usually cheaper than letting it compensate for a broken primitive.
- Any confirmed pipeline defect: `bd create` in THIS repo's ledger
  (pipeline-dev), citing session/part IDs — never in the sandbox ledger.
