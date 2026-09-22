# Walkthrough 16 — RallyWall (lumo-max, medium) — SHIPPED

**Date:** 2026-09-21 · **Sandbox:** `test/walkthrough16`
**Pipeline commit:** `1a6f71f` (run HEAD — pre-hardening; `b4cef8b` merge-slot/worktree, `a30f8a9`/`904d69e` lint+trace-fix commits landed AFTER the run and are unvalidated by it)
**godot-mcp-runtime:** `v3.8.0` via npx (one server process **per agent session** — key to the top finding)

## Outcome

**SHIPPED.** All gates passed, molecule closed, release done. RallyWall playable to win screen (score 15): functional gauntlet 0 violations, vision PASS (13✅/1❌ particle polish → spawned concern bead, fixed, re-verified), consumer ACCEPT. One future-scope bead left open (audio, P2) — legitimate deferral.

## Metrics

| Metric | wt15 | wt16 | Δ |
|---|---|---|---|
| Outcome | SHIPPED | **SHIPPED** | = |
| End-to-end wall | 88m | **135m** (21:44:56→23:59:59) | +52% |
| Input tokens (non-cache) | 4.17M | **8.60M** | **+106%** |
| Cache-read tokens | 5.07M | **8.60M** | +70% |
| Output tokens | 37K | **69K** | +87% |
| Sessions | 11 | **11** | = |
| Tool calls | 389 | **661** | +70% |
| Tool errors | ~35 | **69** (build 5, ian 23, poppy 20, rachel 12, pootie 5, phil 4) | ~2x |
| Engine boots (run_project) | 14 | **30** | +114% |
| Peak concurrency | 1 | **2** (rachel + ian, 22:52) | +1 |
| Molecule beads closed | 23 | 20 (+1 open audio) | = |
| Real game bugs | 1 | **0** | cleaner |
| Trunk mutations committed | n/a (no worktree mandate) | **0 — all game code uncommitted on trunk** | wt16 finding |

**Cost split (input tokens):** build 1.01M (12%), poppy 5 sessions 4.17M (48%), rachel 779k, ian (genesis+vision) 1.59M, phil 503k, pootie 613k.

## What Worked

1. **First-ever parallel gate dispatch.** Build dispatched rachel (qa-gate) and ian (vision-gate) simultaneously at 22:52 — the wt15 postmortem's #1 failure (peak concurrency 1) was addressed; the wave/parallel intent finally executed.
2. **Zero game bugs.** Gauntlet 0 violations, gates found only a P3 polish gap (particles), consumer found nothing beyond nits. Cleanest game-quality run yet — error-43 compile retries down to 7 (was 3→ back up slightly, see failure 4), pre-flight/checklist discipline holding in authored code.
3. **Specialist routing worked.** phil ran (neon materials, 15m/503k) and poppy absorbed the cao.2.1 particle concern re-fix — correct gate-independence routing (gate finds, spawn child, specialist fixes, re-verify).
4. **Genesis discipline held.** One molecule, one genesis, raw beads properly categorized; gates spawned concern children correctly (`cao.2.1`).
5. **Milestone-template absence survived.** Despite loda's finding being unfixed at run time, build improvised milestones without the 10-turn tax wt15 predicted — but via expensive improvisation (part of build's 1.01M).

## What Failed

### 1. Parallel dispatch collided on the shared Godot runtime — THE finding of wt16
Rachel + ian ran concurrently (22:52–23:16), each session spawning its **own** godot-mcp-runtime process, both targeting `rallywall/`. The two `BridgeManager`s treated the same on-disk artifacts (`.mcp/godot-runtime/bridge/mcp_bridge.gd` + `McpBridge` autoload in project.godot) as per-process-owned. Cross-kill evidence from the trace: ian `stop_project` 22:56:43 → rachel bridge death 22:56:46; ian re-inject 22:57:02 → rachel death 22:57:22; rachel debug shows port 49402, ian's 49421. Result: rachel's QA gate ballooned to **23m** (7 gauntlet run_script failures, "Bridge session ended"/"another command in flight"/"No active runtime session"), ian burned **20 tool errors** (8 "another command in flight", 2 "No active runtime session"). Combined: ~25-30m wall and ~700k tokens of pure churn (restarts, re-diagnosis, get_debug_output polls — ian made 21 debug-output calls alone).
**Root cause confirmed + reproduced upstream:** `tests/integration/concurrent-servers-one-project.test.ts` in godot-mcp-runtime (3 passing tests: port rewrite, cleanup cross-delete, repairOrphaned cross-delete). Comment posted on upstream issue #61.
**Fix:** upstream ownership fencing (multi-client single-project) — parked as 8vpa/f7xv scope extension. Downstream mitigation until then: **serialize runtime-touching roles** or give each a separate worktree.

### 2. Wall regression (+52%) with concurrency UP — why
Extra 47m decomposes as: (a) bridge-churn collision ~25m (failure 1); (b) a fully-sequential tail — poppy's chain shows a **40.8m hole** (22:35 states/HUD end → 23:16 particles start) while gates ran, then the vision concern fix, then consumer — gate→fix→consumer never overlapped (poppy's idle gaps between its own sessions: 0.8-1.9m, so the backbone itself is tight; the serialization is structural, not worker slowness); (c) build idle awaiting **serial** worker chains 124m cumulative. Only the two gates ran in parallel — and they collided. Paradox: dispatches were MORE parallel than wt15 but wall ROSE, because the only parallel pair collided and the newly-well-parallelized pair didn't overlap the critical path (poppy chain remained the bottleneck).
**Fix:** overlap verification gates WITH the next dev wave (gates read-only vs disjoint files), not just with each other — requires the runtime fix first, else the collision recurs.

### 3. Token regression (+106%) — the parallel experiment doubled QA/vision cost
rachel 779k + ian vision 1.36M ≈ 2.1M for the gate phase; wt15's serial equivalents were ~1.2M. The delta is churn: restart cycles, debug polling, retry prompts re-carrying context. Bridge churn is a **token amplifier**, not just a time amplifier. Also build rose 693k→1.01M (improvised milestones, longer orchestration over the collision).
**Fix:** same as 1. No separate remediation.

### 4. Error-43 compile retries crept back: 7 (rachel 0, poppy 5, ian 2)
wt15 held it to 3 via pre-flight type discipline; wt16's were concentrated in **probe scripts and nested-dict literals** — a new failure shape: rachel's big scenario dicts hit "Expected closing ')'" parse errors that mimic bracket-mismatch but were transport/serialization-sensitive (her report: "known transport-mangling gotcha for long nested dicts", workaround = JSON-string encode). hm5a's check-brackets.sh (shipped post-run in 904d69e) would NOT have caught these — they weren't literal bracket imbalance.
**Fix:** worker-common guidance — encode scenario payloads >~20 lines as JSON string + `JSON.parse_string` (rachel discovered this herself mid-run; it needs to be day-one guidance). Filed.

### 5. Permission-stencil denials persist: 15 across the run
build 5, ian 3, poppy 4 (bash×2, write×2), rachel 2, pootie 1. Shapes: write-to-scenarios-dir denied (rachel's gauntlet file couldn't persist — noted in her report), edit/write denials in worker profiles, bash stencil misses. 8gzm (defer/test/printf grants, in 904d69e) addresses the bd verb subset; the write-pattern gaps remain.
**Fix:** audit write patterns in agent profiles — rachel needs `tests/scenarios/*.json` write scope for the canonical gauntlet.

### 6. All game code uncommitted on trunk (worktree mandate ignored)
Run pinned pre-`b4cef8b`: zero `git worktree` calls, zero worker commits — the entire game exists as uncommitted mutations on trunk. Confirmed as omission (build.md at run time lacked the mandate), not failure. The hardening commit makes this structural for wt17+, but this run provides **no validation** of merge-slot/worktree enforcement (0b03 closed as implemented-not-validated).
**Fix:** wt17 must be a fresh sandbox-init validation run (also for b4cef8b/904d69e/a30f8a9).

### 7. Ian's vision-gate burned 1.36M tokens — the most expensive single session
26 run_script + 21 get_debug_output + 20 errors. Beyond the collision, ian's review methodology itself is heavy: he re-ran mechanics verification that rachel's gauntlet had already covered (speed ×1.05 series measured identically in both reports). Duplicate verification across gates.
**Fix:** gate specialization — vision gate reviews VISION elements + aesthetics (screenshots, feel), NOT mechanical correctness (that's qa-gate's contract). File profile fix.

### 8. Stop_project macOS sandbox noise (13) — still miscategorized
Same as wt15 finding 8; `sandbox_extension_issue_file_to_process` "Operation not permitted" stderr noise counted as errors. Upstream (opencode) unresolved; harmless but pollutes metrics.

## Optimizations Filed (this postmortem)

- **Bridge churn root cause** → upstream issue #61 comment + repro tests (done). Downstream: serialize runtime roles until fixed, or per-role worktrees.
- **bead (new) JSON-encode guidance** for long nested-dict scripts in run_script payloads (rachel's discovered workaround, day-one).
- **bead (new) rachel write-scope** for `tests/scenarios/*.json` (canonical gauntlet persistence).
- **bead (new) gate deduplication** — vision-gate profile: aesthetics only, no mechanics re-verification.
- **bead (new) wt17 validation run** — fresh sandbox-init; validates b4cef8b worktree/merge-slot enforcement + 904d69e trace fixes + this run's beads end-to-end (supersedes 0b03's implemented-not-validated close).
- Existing parked: 8vpa/f7xv (upstream multi-project + now same-project fencing), bs69 (reasoning-effort), awxd.

## Comparison to wt15

- **Quality:** improved (0 game bugs, cleaner gates, correct concern routing).
- **Cost/time:** regressed — entirely attributable to the parallel-gate collision and serial poppy backbone; the fixes exist (upstream fencing + wave overlap with dev).
- **Concurrency:** structurally attempted for the first time (gates in parallel); next step is gates ∥ dev waves and specialist waves (phil ∥ poppy on disjoint files).
- **Verdict:** the parallel experiment was the right thing to run — it surfaced the single deepest infrastructure defect in the stack (shared-runtime ownership), with a clean upstream repro attached.

## Next Steps

1. Upstream: await maintainer response on #61 fencing proposal; implement if unowned.
2. Ship profile fixes (gate dedup, rachel write-scope, JSON-encode guidance).
3. **wt17**: fresh sandbox-init run validating worktree/merge-slot enforcement + all post-wt16 fixes, with runtime-touching roles serialized (or per-worktree) until upstream fencing lands.

---

**Trace:** `~/.local/share/opencode/opencode.db` (11 sessions, 661 tool calls, 135m span, 8.6M input tokens).
**Reports:** `test/walkthrough16/reports/` (functional, vision genesis, vision review, consumer critique).
