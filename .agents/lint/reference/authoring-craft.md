# Skill & Agent Authoring Craft

Enforced rules live in the lint registry (`rules.yaml`); this document owns
**authoring method**, not enforcement. Grounded in the
[Agent Skills](https://agentskills.io) spec (guides: `best-practices`,
`optimizing-descriptions`, `evaluating-skills`, `using-scripts`).

## Agent vs skill placement

Two questions decide placement:

1. **Would this survive an engine switch?** Decision logic, role
   responsibilities, workflow patterns, quality standards → agent.
2. **Does it name APIs, file formats, MCP tools, or process mechanics?**
   → skill, referenced by path, never inlined.

An agent file should read as a job description plus judgment criteria,
delegating all mechanics to skills the agent invokes. An agent that can't
be described without naming the engine is a skill wearing an agent costume —
factor it out. When an agent needs engine mechanics, it says "consult
`skills/<name>/SKILL.md`" — that indirection IS the portability mechanism.

## Skill descriptions carry the trigger burden

Progressive disclosure loads only `name` + `description` at session start —
the description alone decides activation.

- **Imperative trigger phrasing:** "Use when …" / "Use after …"; name the
  concrete inputs, scenarios, and user intents that should activate it.
- **Intent-first, not implementation-first:** "Connect game events to their
  handlers" *before* mentioning a specific tool.
- **Cover plus enforcement:** 40-80% coverage of a task beats over-claiming;
  every false trigger costs context and trust.

## Size & progressive disclosure

Full `SKILL.md` body loads only on activation (~5000-token budget), then
`reference/`/`scripts/` on demand.

- Keep `SKILL.md` well under the lint cap; push detail into `reference/`.
- **Tell the agent WHEN to load each reference file** — never leave a
  reference unreachable from the workflow.
- One level deep from the skill root; avoid nested reference chains.
  Cross-skill references to a canonical schema are the one deliberate
  exception.
- **Provide defaults, not menus. Favor procedures over declarations.**
- **Match specificity to fragility:** hard rules where failure is
  catastrophic, lighter guidance where craftsmanship applies.
- Templates/checklists belong in the skill (or `reference/`), not agent files.

## Scripts (agentic interface)

Everything in `scripts/` is executed by an agent with no human to clarify:

- Self-contained, or dependencies documented in a header comment.
- Non-interactive: `--help`/usage line, helpful errors, distinct exit codes.
- Structured output on stdout, diagnostics on stderr; bounded and deterministic.
- Idempotent.
- Pin one-off external invocations (e.g. `npx -y <pkg>@<version>`).

Logic you execute → `scripts/`; content you copy → `reference/`. Prose
describing a concrete mechanical transform ("lowercase it, strip special
chars") is the signal it should be a script, not instructions left to
execution-by-judgment.

## Agent-computer interface (ACI)

Design the interface as carefully as the prompts:

- **Poka-yoke — make errors structurally hard.** Unambiguous, fully-specified
  inputs over forms the model must resolve; explicit absolute/fully-qualified
  references over ambiguous ones.
- **Stay close to natural model output.** Formats the model writes fluently
  (whole files, JSON objects) beat formats with formatting overhead.
- **Document for a junior engineer:** example usage, edge cases, explicit
  boundaries in descriptions and parameter docs.
- **Draw clear boundaries between similar tools** so the agent can't pick the
  wrong one (run vs attach, validate vs run_script, save vs save-as).
- **Test how the agent uses it, then tighten.** Run representative inputs,
  observe mistakes, convert each into a gotcha, validator check, or parameter
  constraint.

## Eval-first authoring

- Define 2-3 representative invocations + expected outputs before finalizing
  a skill; keep checkable cases in `evals/evals.json` inside the skill directory.
- When a playtest/validation run exposes a failure mode, turn it into an
  explicit rule, gotcha line, or validator check — a skill that never fails in
  practice isn't being exercised.
- When revising, re-run expected cases (validators + evals), not just prose
  review. If an observed failure motivated the change, it must appear as an
  explicit rule/gotcha/validator check — not just prose.

## Bounded execution & structured failure

Every unit of delegated work needs a bounded horizon:

- Delegations bound their retries (default cap: 3) and return
  `⛔ BLOCKED: <cause>` + attempts + evidence. Never a loop, never a silent
  detour.
- Missing mandated deliverables: spawn ONE completion run; if that also
  fails, escalate BLOCKED. Don't re-run open-ended.
- Orchestrators never do the work themselves; anti-recursion guards are part
  of the agent's instructions.
- Encode failure-history lessons as protocol steps citing the evidence in
  benchmark reports (citation rules from the lint registry apply).

## Porting to a new engine

1. Agents stay unchanged — verify no engine references leaked in.
2. Update harness config (opencode.json/jsonc) to the new engine's MCP/LSP.
3. Swap skill implementations (same skill names, new internals).
4. Adjust permission patterns in frontmatter comments (config, not logic).
