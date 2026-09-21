# Walkthrough 15 — RallyWall (lumo-max) — SHIPPED

**Date:** 2026-09-20 · **Sandbox:** `test/walkthrough15`
**Pipeline commit:** `b5fde8d` (all ten wt14-postmortem beads: wave loop `af73510`, atomic claim+reparent `eb1d61e`, project-map enrichment `5ae6af0`, canonical gauntlet `b48551b`, engine-reuse mandate `f25f31d`, grooming example `892bbbb`, type annotations `46080b8`, run_script pre-flight `389f438`, sandbox-noise doc `79c6a96`, gate independence `fc2693d`)
**godot-mcp-runtime:** `v3.8.0` (`be7e20f`, tagged — batch cold-import pre-pass fix #60)

## Outcome

**SHIPPED.** All 23 beads closed, board drained. Functional gauntlet PASS (0 violations), consumer critique ACCEPT (one doc bug found, fixed, re-verified). Game playable to win screen (score 15).

## Headline

**Massive cost collapse from wt14 — but the parallel-wave goal failed.** Wall dropped 4h47m → **88m** (-69%), input tokens 15.34M → **4.17M** (-73%), sessions 23 → **11**, tool calls 1,300 → **389**. The ten doc fixes and runtime pin did their work. However, all 10 dispatches were **fully-blocking serial awaits** (78.6m await = 90% of build's 87.5m span; peak concurrency = 1) — the wave-loop mandate in build.md was reasoned about ("poppy cap is 2 beads") but never executed as parallel Task calls. The wt15 success criteria met: boots 14≪57, `--set-labels` effectively zero (3 batched commands by ian, sanctioned). Missed: wall ≤45m (88m), orchestrator <15m (4740s tool/87.5m span), concurrency >2 (1).

## Metrics

| Metric | wt14 | wt15 | Δ |
|---|---|---|---|
| Outcome | SHIPPED | **SHIPPED** | = |
| End-to-end wall | 4h47m (287m) | **88m** | **-69%** |
| Input tokens (non-cache) | 15.34M | **4.17M** | **-73%** |
| Cache-read tokens | 18.53M | **5.07M** | -73% |
| Output tokens | 138K | **37K** | -73% |
| Sessions | 23 | **11** | -52% |
| Tool calls | 1,300 | **389** | -70% |
| Engine boots | 57 | **14** | -75% |
| Blocking awaits | 22/22 dispatches | **10/10 dispatches, 78.6m (90% of span)** | unchanged pathology |
| Peak concurrency | 2 | **1** | -1 |
| Compile-error retries (error 43) | ~16 turns | **3** | -81% |
| `--set-labels` calls | 25 | **3** (batched, sanctioned) | -88% |
| Duplicate genesis stubs | 2 | **0** | fixed |
| Real-game bugs | 4 | **1** (Space-gate README mismatch) | cleaner build |

**Cost split (input tokens):** build 693k (17%), poppy 6 sessions 2.27M (55%), rachel 491k, pootie 481k, ian 227k.

## What Worked (carry forward)

1. **Type-annotation + pre-flight discipline**: error-43 compile retries fell 16 → 3. Rachel's gauntlet was clean (10m, zero game bugs, honest about self-authored probe errors).
2. **Engine-reuse mandate**: 14 boots for 11 sessions — poppy's 6 sessions amortized boot cost.
3. **Canonical gauntlet scenario**: rachel used `functional_gauntlet.json`, 0-violation pass on first run.
4. **Atomic claim+reparent**: zero "already claimed" fights (wt14: every role session fought one; wt12: ian lost 5 turns).
5. **No duplicate genesis**: exactly one molecule, one genesis session (wt14 had 2 stray stubs).
6. **Honest orphan tracking**: poppy self-filed paddle2.tscn cleanup beads; gate independence held (pootie filed rr2.1, poppy fixed it — right routing).
7. **`bd batch` adoption**: routing waves committed in single transactions (7-op, 2-op batches).

## What Failed (fix for wt16)

### 1. Serial dispatch persists — THE finding of wt15
Build's own reasoning shows it: *"poppy cap is 2 beads. Scaffold first (sbr.15), then entities"* and *"ball physics + paddle-ball collision both to poppy — but same files-ish; cap 2 beads anyway."* It treats waves as single-worker 2-bead batches and never routes to specialists (phil/stephen/gustavo never ran; all P1 polish was deferred as out-of-scope rather than parallelized). The wave-parallelism matrix shows **5 disjoint agent pairs** that could have run concurrently. **Fix:** the mandate exists but is prose the model reasons around. Escalate to structure: a numbered dispatch algorithm (exact turn-by-turn procedure: one turn = `bd ready` → one turn = N parallel `task` calls) or a dispatch checklist step that must be cited. Candidate: fold into wt16's worktree/Dana experiment (bead bkk) since per-worker clones force the disjointness computation.

### 2. Molecule anatomy surprise
Build: *"does game-run have a dev-loop step? Pour only created 5 things, no dev-loop"* (22:28) and *"the molecule only has consumer gate?"* (23:25). The game-run formula created 5 beads (game-run, groom, raw backlog, consumer gate, + gates) with no dev-loop/qa-gate steps — build improvised rachel's gauntlet as a non-gate dispatch and burned ~10 bd-admin turns on close dances (6+ attempts to close `mol-sbr` against deferred children). **Fix:** verify the `game-run.formula.toml` output matches build.md's assumed anatomy (dev-loop step, gate steps); document the expected bead inventory post-pour in build.md.

### 3. `bd children` not in build's allowlist
The pre-close check mandated by worker-common was **permission-denied for build** (`bd children walkthrough15-mol-sbr --json 2>/dev/null` → deny). Build substituted `bd blocked` and improvised. **Fix:** add `bd children*`, `bd gate*`, `bd blocked*`, `bd dep*`, `bd swarm*` to the build profile allowlist (sandbox-init rendering).

### 4. `bd gate resolve` flag guessing
Pootie: first attempt denied (permissions), second attempt `--verdict` → `unknown flag`, third succeeded (right flags after 2 wasted turns). **Fix:** exact command in rachel.md/pootie.md profiles (`bd gate resolve <id> --accept/--reject --note "..."` — verify against `bd help gate`).

### 5. P1/P2 deferral instead of parallel polish
All 6 P1 + 3 P2 beads deferred as "out of MVP scope" — legitimate scoping, but they were also the natural parallel-dispatch fodder for specialists. Decision point for wt16: is the RallyWall spec P0-only by design? If the spec demands polish, serial poppy would have paid 30m+; parallel specialists would pay ~10m wall.

### 6. Probe `var :=` residuals (3 error-43s)
Type discipline held in authored game code but leaked in throwaway probes (rachel: `x0`, `was_over`; pootie: one). **Fix:** move the type-annotation rule into the run_script pre-flight item 3 as a pre-submit regex self-check ("grep your script for `:=` near `get_node`/`get_`/`dict.get` before submitting").

### 7. Permission-stencil residuals (12 bash denials)
mkdir×2 (filed `jo8u`, fixed `e29b11a`), rm×3 (filed `0ri1`, fixed `f0c2d9f`), `python3 -c` math×1, printf-piped `bd batch`×1, `bd children` (above). Every one improvised around successfully, but each cost a turn. The `printf ... | bd batch` mismatch is notable: build correctly reasoned "heredoc starts with bd batch" and self-recovered in one hop — the doc example earned its keep. **Fix:** add `python3 -c *` (compute-only, no FS) to worker allowlist or teach mental-arithmetic-first.

### 8. stop_project 14/14 "failures" — still miscategorized
Every stop_project returned the macOS `_process failed ... Operation not permitted` sandbox-extension noise; opencode's classifier still counts them as tool errors. Zero behavioral impact (workers know the doc, engines recycled cleanly), but it pollutes failure metrics and risks future false-alarm spirals. **Fix:** remains upstream (opencode result classification); bead 2r3 doc mitigation held.

### 9. Pootie's 11m Space-gate probe spiral (0.37 ratio)
Pootie burned ~8 turns diagnosing "ball not moving" before discovering the start overlay required Space — the game's README said "starts immediately" (the actual rr2.1 bug!). A consumer critique that reads the start-overlay code path first, or tries "press any key" before deep-diagnosing immobility, would save ~5 turns. **Fix:** critique-mode doc: "if the world seems frozen on first boot, suspect a start gate/input wait before diagnosing physics."

## Comparison to wt14

- **Cost:** every dimension down 70%+ — the ten doc/skill fixes + v3.8.0 runtime worked exactly as designed.
- **Quality:** gauntlet and consumer both clean on first pass (wt14 needed re-fix cycles); only 1 real game finding (doc bug).
- **Concurrency:** regressed to strictly serial — wt14 at least overlapped twice. The wave-loop prose alone does not change model behavior; wt16 must make parallel dispatch structural, not aspirational.

## Next Steps

1. **Wave-loop escalation** — structural dispatch algorithm or checklist citation in build.md (fold into bkk's worktree design).
2. **Formula anatomy verification** — game-run molecule bead inventory vs build.md expectations.
3. **Build-profile permission grants** — `bd children*/gate*/blocked*/dep*/swarm*`.
4. **Gate-resolve exact-flag docs** in gate-owner profiles.
5. **Critique start-gate heuristic** in pootie/full-modes docs.
6. Run **wt16** with worktree isolation + Dana merge-gate (bead bkk) — parallel dispatch becomes mandatory when workers own separate clones.

---

**Trace:** `~/.local/share/opencode/opencode.db` (11 sessions, 389 tool calls, 88m span).
**Reports:** `test/walkthrough15/reports/` (functional-rallywall.md, critique-rallywall.md).
**Post-run fixes shipped:** mkdir/rm docs (`e29b11a`, `f0c2d9f`), batch wire-format template (`5ee475c`).
