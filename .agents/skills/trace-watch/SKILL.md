---
name: trace-watch
description: Monitor and analyze game-build session traces (walkthroughs, benchmarks) via the opencode session DB — live watch of an active run AND post-run retrospective review. Detects failures, friction, and waste (time, tokens, retries) and turns them into pipeline improvements.
---

# Trace-Watch: observe game-build sessions, find what to fix

Trace-watch watches a sandbox run — live during execution, or retrospectively
after it ends — and turns the traces into improvements. The core discipline:
**read tool outputs, not intents**. Agent prose saying "proceeding" is
rationalization, not evidence that a command succeeded.

## Doctrine: WHAT / WHY / HOW

Every trace-watch finding, from any mode, answers the same three questions
in order. Nothing is done until all three have an answer:

1. **WHAT went wrong or is wasting resources** — the symptom, observable
   in the trace (error output, denial, delay, duplicated work, mangled
   data, or merely excessive cost).
2. **WHY it happens** — the root cause, traced backwards: corpus gap,
   permission-stencil gap, tool/upstream defect, workflow-design flaw,
   or legitimate irreducible work. Symptoms cluster; a cluster usually
   shares one cause (40 denials = one missing grant, 19 compile errors
   = one gotcha).
3. **HOW to improve** — the remedy and its owner: a corpus/skill edit in
   this repo, an upstream contribution, a beads change, or a workflow
   change; with the measured cost so the fix's value is justified.

"What goes wrong" is deliberately broad — anything in a trace that
shouldn't be there, shouldn't have taken that long, or shouldn't have been
needed at all. Known symptom families (extend, don't restrict):

- **Correctness**: errors, failed calls, silent corruption (success with
  wrong data), missing verification, dishonest closes, mid-flight death.
- **Friction**: permission denials, unknown flags, rejected formats,
  escape-hunting, improvisation where a sanctioned path existed.
- **Waste**: retries, duplicate reads, oversized outputs, re-derived
  context, cold starts, deliberation spirals.
- **Structural**: wrong routing, dead workers, repair re-dispatches,
  cold re-verifies, gate-ordering fights, missing dispatch context.
- **Behavioral**: rule-induced paralysis, hallucinated identifiers,
  stale assumptions carried across turns, drift from the skill's script.
- **Latent**: things that PASS now but encode a landmine — fragile
  patterns, guessed constants, assumptions that only hold by luck.

A symptom outside these families is still in scope if it costs time,
tokens, or trust; add it to the list when first observed.

*A finding without its cause is a rumor; a cause without a remedy is a
complaint.* File beads for the complete triple only.

## Data source

Sessions live in `~/.local/share/opencode/opencode.db` (tables `session`,
`part`). Filter by sandbox directory:

```sql
SELECT s.id, s.agent, s.title, s.time_created,
       (SELECT COUNT(*) FROM part p WHERE p.session_id = s.id)
FROM session s
WHERE s.directory LIKE '%<sandbox-name>%'
ORDER BY s.time_created ASC;
```

Each `part` row's `data` JSON has `type` (`text` | `tool` | `reasoning`),
and for tools a `state` object with `input`, `output`, `error`, `status`,
plus `time_created`/`time_updated` columns for durations.

## Mode 1: live watch

Use while a run is executing, to catch failures as they happen instead of
in the postmortem.

1. Poll every 5–10 minutes (adjust to run tempo). New session IDs =
   subagent dispatches.
2. Tail the two most recent sessions: recent parts, newest last.
3. Record subagent spawns, dispatch batch composition, gate transitions,
   stalls (>60s with no tool activity in the most active session).

**Rules (learned from real misses):**

- **Read `state.output` for every state-changing command** (`bd
  create/update/close`, `--claim` calls, `git`, file writes). A refused
  command followed by the agent continuing ("treating the claim as held —
  proceeding") is a **defect signature**, not coping. Don't log it as
  healthy adaptation.
- **Verify state materialized.** If the workflow says claims put beads
  `in_progress`, spot-check that `bd list` in the sandbox shows ◐ during
  dispatch windows. Zero ◐ across an entire run = systemic claim failure —
  investigate, don't theorize.
- **Triage every error-shaped output**: `Error updating`, `refused`,
  `denied`, `failed`, permission blocks. Silent workarounds compound into
  unmeasured drift even when the run succeeds.
- **Query, don't theorize.** When state looks counterintuitive, one
  targeted query — dump outputs for all `--claim` calls — beats a
  narrative built from prose.

**Escalation:**

- Stalled >10 min: check `pmset -g assertions` (host sleep masks as
  stall).
- Systemic refusal pattern (same error ≥3×): interrupting the run is
  usually cheaper than letting it compensate for a broken primitive.
- Confirmed pipeline defect: file it (see "Filing findings") — don't wait
  for the run to end if it's steering the run into drift.

## Mode 2: retrospective review

Post-run analysis (benchmark postmortems, walkthrough comparisons).
Improvements hide inside PASSes that recover gracefully and leave no
alarm in a metrics scan — so reviews do more than answer the framing
question (cost, pacing, routing).

**Order of operations — mechanical first, judgment second:**

```bash
python3 .agents/skills/trace-watch/scripts/scan.py <sandbox-name>           # signals
python3 .agents/skills/trace-watch/scripts/scan.py <sandbox-name> --perf    # waste
python3 .agents/skills/trace-watch/scripts/scan.py <sandbox-name> --deep    # reasoning-lens
python3 .agents/skills/trace-watch/scripts/scan.py <sandbox-name> --latency # turn economy
```

Read the scanner outputs first. Then apply the judgment lenses below by
reading the flagged sessions — they need interpretation the scanner
can't do.

### Scanner modes

- **default** — claim audit, real denials (echo-filtered), improvisation
  language, error-shaped outputs. Correctness signals.
- **--perf** — per-session wall/tool-time/calls/fails, top failure
  signatures (same error ≥2× = corpus gap), duplicate reads, giant outputs.
- **--deep** — reasoning-lens: deliberation-spiral ratio per session
  (hedging-marker density in reasoning parts ÷ tool calls; ≥0.5 = review
  the session by hand), probe-script repetition (same normalized
  `run_script` head ≥3× = should have been a TestPlayer scenario), error
  signatures shared across ≥2 agents (= one missing artifact or upstream
  defect covering several sessions), engine relaunch count.
- **--latency** — turn economy: wall vs tool-time vs reasoning-duration vs
  inter-tool gap decomposition (wt12 lesson: wall time is ~model latency ×
  turns — tools are nearly free; attacks on turn count are where the money
  is); duplicate identical calls; orchestrator bd-admin:dispatch ratio
  (caveat: genesis-style ledger AUTHORING — `bd create` of the subtask
  backlog — is legitimate work, only routing/polling chatter is waste);
  `godot_stop_project` failure rate; per-skill payload census (>10kB/load
  = split candidate); cross-session file-read overlap (≥3 agents read the
  same file = dispatch prompts lack a project map); per-session token
  decomposition (input, cache-read, peak AND median step context —
  peak≫median means monotonic context growth across the session, the
  pollution signature of bead tek; peak≈median×2-3 is normal accumulation);
  wave-parallelism matrix (edit-set
  disjointness between agents — disjoint pairs could have run concurrently,
  overlapping pairs justify serialization; bead hbm); orchestration lenses
  A/E (blocking-await share, bd-native substitution patterns) and B
  (dispatcher idle-on-child gaps) — full definitions and thresholds in
  [reference/orchestration-lenses.md](reference/orchestration-lenses.md).

### Deterministic vs semantic

All four scanner modes are **deterministic** — regex classifiers, gap
arithmetic, call counting. They reliably produce *candidates*; they cannot
judge meaning. Semantic analysis (did the agent actually conclude the
right thing? was the improvisation justified? is this a test-config
defect?) is the human/subagent judgment pass over flagged sessions —
everything in the checklists below. Every scanner hit is a question, not
a finding; the WHAT/WHY/HOW triple requires reading the trace.

### Per-specialist checklist (correctness lens)

For EVERY specialist session in the run:

1. **Claim**: right bead, right `--actor`, claim actually succeeded
   (output checked).
2. **Skill**: assigned skill read BEFORE acting (first reads of the
   session).
3. **Denials**: grep tool outputs for `denied`/`permission`/`not
   permitted` — the scanner applies the corpus-echo filter; verify hits
   aren't text *about* permissions.
4. **Improvisation**: reasoning/text mentions `fallback`/`workaround`/
   `instead`/`cannot write` — each marks a permission-stencil or tool
   gap.
5. **Silent corruption**: successful tool calls whose readback is wrong
   (zeroed/mangled data).
6. **Close honesty**: close reason's claims traceable to in-session
   evidence.

Any hit on 3–5 is a finding even if the run shipped fine — especially
then.

### Waste lens (efficiency)

A run can pass every checklist point and still be 2× slower and 3× more
expensive than it needs to be. Quantify per session —
`wall / tool-time / calls / fails / duplicate-reads` — then attribute
each finding to one category (attribution keeps fixes accountable).
**Headline metrics for benchmark reports: per-session TURN COUNT and
INPUT TOKENS** (from `--latency`) — wall time is almost entirely
model-API latency between actions (rachel gauntlet: 29m wall, 144s
tools), so turns are the cost lever, not tool speed. Evaluate corpus
changes by delta in turns/spirals vs the prior run, not anecdotes.

1. **Tool errors & retries** — failed calls; repeated identical
   signatures (same error ≥2× in a session = corpus gap, not bad luck:
   unknown flag, `:=` inference, hallucinated identifier, denied path).
2. **Time loss** — decompose wall time into tool-time vs inter-call gap
   (model latency × turns). Tool time is rarely the problem (a 42-min
   gate session held 70s of tool time); attack turn count and the
   cold-start tax (re-booting engines, re-registering autoloads,
   re-reading layout a sibling already mapped).
3. **Token waste** — repeated reads of the same file (within a session
   = context failure; across siblings = missing durable artifact),
   oversized outputs swallowed whole, reasoning re-deriving known state.
4. **Turn waste** — deliberation spirals (long reasoning runs, no tool
   calls between), close dances, flag guessing.
5. **Structural waste** — repair re-dispatches redoing a dead worker's
   context; gate re-verify as a full cold re-gauntlet instead of a delta;
   orchestrator poll loops.

Tag findings reducible vs irreducible (a legitimate re-verify after a
real bug fix is irreducible) — report both anyway so the reducible share
is measurable run over run.

## Upstream attribution

Before filing a finding as pipeline-dev, ask which layer owns the fix.
Many trace discoveries are defects or missing primitives in upstream
dependencies — fixing them there benefits every run and consumer:

- **godot-mcp-runtime** (or the engine plugin's MCP server): tool bugs
  (silent data mangling with `success:true`), missing pre-flight
  validation (reject a script at submit instead of error-43 at exec),
  better error messages, verb coverage gaps.
- **bd (beads)**: CLI flag-surface inconsistencies workers guess at,
  claim idempotency, gate-resolution ergonomics.
- **opencode / harness**: permission-model gaps (write vs edit stencil
  asymmetry), trace-schema limits (reasoning capture, per-tool token
  accounting), dispatch mechanics.

A finding is usually BOTH: file the pipeline-dev bead for our
compensation (corpus gotchas, skill rules) now, and record the upstream
proposal in the description — session/part IDs, minimal repro, drafted
issue text if possible — so proposing it later is copy-paste. Never let
"that's an upstream bug" swallow the finding: our runs pay the cost
today.

## Filing findings

- Findings go to THIS repo's ledger (`bd create` at the repo root),
  never the sandbox ledger — improvements to agents/skills/formulas/
  permissions are pipeline-dev work even when observed mid-game.
- Cite session/part IDs and measured numbers: "5× compile error 43, ~7
  turns, est. 5 min + tokens" beats "compile errors happened".
- **Watch log**: post one `bd comment` per watch on the pipeline bead
  that commissioned the review (or a dedicated watch-log bead), citing
  session/part IDs — so successive watches accumulate in the ledger
  instead of living in conversation.

## Known blind spots (compensate by hand)

- Workers that die mid-flight look like clean finishes — cross-check the
  session list against bead close actors (a bead closed by an actor who
  isn't the assignee is a repair dispatch).
- Reasoning-model internal text may not all land in `reasoning` parts.
- One long-running tool call defeats the stall detector; check part
  timestamps (`time_updated - time_created`).
- Orchestrator wall time includes idle waits — judge it by tool-time +
  call count, not wall.
- Corpus echoes can slip past the filters — a "denied" hit quoting
  file-content markers (`<path>`, line-number prefixes) is text about
  permissions, not a permission event.

## Appendix: ad-hoc queries

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
