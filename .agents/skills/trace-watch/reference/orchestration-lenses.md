# Latency mode lens reference

Detailed definitions for `scan.py --latency` orchestration lenses. The
SKILL.md carries only the mode summary; this file holds the contracts.

## Lens A — orchestrator blocking-await share

Each `task` dispatch with zero caller activity during it, plus cumulative
await ÷ wall. Threshold: >60% blocking-await share means the dispatcher
is the bottleneck (wt12 measured 96%, wt13 76% — the dispatcher was the
single biggest cost center). Remedy: fire-and-monitor dispatch — batch
independent dispatches into one turn, use wave-N await time to prepare
wave N+1.

## Lens B — dispatcher idle-on-child gaps

Caller silent >30s while a worker session is active, outside awaited
dispatches. Catches dispatcher gaps that aren't attributable to a single
await (context bloat, lost position). Small counts on top of a high
Lens A are secondary; Lens A is the primary lever.

## Lens E — bd-native substitution patterns

Bash sequences reimplementing bd primitives:
- Per-bead `bd update` routing/labeling bursts (≥4 calls for one wave)
  → one `bd batch` transaction (upstream designed batch for exactly
  this loop shape).
- Sleep-based or repeated identical `bd show`/`bd list` polling →
  `bd ready --mol` / `bd swarm status` (computed frontier) or
  `bd gate check` (the sanctioned gate-evaluation poll).

Static-side counterpart: lint rule `dispatch-as-bd-native` judges
profiles/formulas that prescribe these loops.

## Remedy wiring

Fixes land in `agents/build.md` (frontier dispatch model, batched
grooming waves) and `workflows/game-run.formula.toml`. Validate by
re-running `--latency` on the next walkthrough: Lens A should drop
below ~30% and Lens E burst counts to ~zero.
