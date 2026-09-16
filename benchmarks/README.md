# Benchmark Suite

Fixed, reusable prompts for end-to-end benchmarking of the mythic-quest
harness. Each prompt is versioned in-repo so harness changes can be A/B
compared against recorded baseline runs.

## Prompts

| File | Purpose | Profile |
|---|---|---|
| `prompts/rallywall.md` | **Primary / fast baseline** — minimal entity count, full pipeline coverage | Fastest feedback, lowest token burn |
| `prompts/brickfall.md` | Coverage variant — instancing (node grids), lives, destruction | Stress path for create-entity instancing |

Run the primary prompt (`rallywall.md`) for regression benchmarking after
any harness change. Reach for `brickfall.md` when testing code paths
involving repeated-node instancing (brick grids, item spawners) that the
primary prompt doesn't reach.

## Running a benchmark

1. Reset the sandbox (deterministic — use the sandbox-init skill):
   ```bash
   # via the sandbox-init skill (.agents/skills/sandbox-init/)
   # creates test/<name>/ with agents+formulas deployed at init
   ```
   The deployed copies come from the repo's committed HEAD — commit your
   harness changes BEFORE init or the benchmark measures stale code.
2. Start opencode from the sandbox dir, note the wall-clock start time.
   **Run under `caffeinate -dimsu` (or equivalent power-assertion).**
   Host sleep is indistinguishable from stalls in the session DB after
   the fact — a MythicQuest run lost 5.8 of 9.2 wall-clock hours to
   sleep and the active-time figure had to be reconstructed from
   tool-activity bursts. Record `pmset -g assertions` output (or system
   sleep log) alongside the metrics so sleep-time can be subtracted
   deterministically instead of inferred.
3. Paste the prompt verbatim. Do not edit it, clarify it, or answer
   agent questions beyond the minimum required — consistency is the
   experiment control.
4. While it runs, monitor via the opencode session DB
   (`~/.local/share/opencode/opencode.db`, tables `session`/`message`/`part`)
   to record subagent spawns, stalls, retries.
5. On completion, record the metrics below.

## Metrics to record (efficiency + outcome axes)

| Metric | Source |
|---|---|
| godot-mcp-runtime version | pinned in `plugins/engine/godot/mcp.json` — record in every results file; version changes invalidate comparisons |
|---|---|
| Total wall-clock time | session timestamps (root session `time_created` → `time_updated`) |
| Token usage (if exposed) | session DB / provider dashboard |
| Subagent count + per-agent durations | session DB, `parent_id` tree |
| Retry counts (BLOCKED reports, close-refusal workarounds) | session DB tool parts + ledger |
| `run_project` success/fail + durations | session DB tool parts |
| Stalls (>60s no tool activity) | live monitor or DB gap analysis |
| QA pass rate + FAIL items | rachel's verdicts + reports/** |
| Vision-qa rating + consumer verdict | ian / pootie results |
| Invariant violations | TestPlayer reports (zero-violation counts) |
| Language drift | reasoning-part scan in session DB |
| Improvised-workaround incidents | BLOCKED reports, denied-permission retries, skill-dir writes |
| fast-verify coverage (post-4rl) | count of tasks verified per-task vs skipped |

Results go in `results/YYYY-MM-DD-<game>-<model>-<outcome>.md`.

## Baselines

| Date | Prompt | Model | Result | Notes |
|---|---|---|---|---|
| 2026-09-15 | walkthrough6 (ad-hoc, "Lamplight of the Storm") | lumo-max | PASS (4 QA bugs found+fixed) | CONTROL: old harness. 5h47m, 13.73M input tok, 23 sessions, 1,106 tools, 0 compactions. Full analysis: [results/2026-09-15-walkthrough6-lumomax-control.md](results/2026-09-15-walkthrough6-lumomax-control.md) |
| 2026-09-16 | walkthrough7 (game-run formula, v3.7.0) | lumo-max | PASS (QA clean, 3 consumer bugs fixed) | 2h27m, 7.08M input tok, 18 sessions, 747 tools. vs control: −58% time, −48% input. Full analysis: [results/2026-09-16-walkthrough7-rallywall-lumomax.md](results/2026-09-16-walkthrough7-rallywall-lumomax.md) |
