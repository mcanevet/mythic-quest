# Permission-Evaluation Semantics (opencode)

Verified against anomalyco/opencode source, Sep 2026:
`packages/opencode/src/permission/index.ts`,
`packages/core/src/permission.ts`,
`packages/core/src/tool/{write,edit,bash,read}.ts`,
`packages/opencode/src/tool/{task,skill}.ts`,
`packages/opencode/src/mcp/catalog.ts`.

Mis-keyed permission rules are **silently inert** — opencode neither warns
nor errors. This document exists because we twice wrote `write:` keys in
frontmatter believing opencode distinguished write from edit. It does not.
Verify against source, not docs summaries, when a permission seems inert.

## Rule keys (the "action" side)

A rule only ever matches against these exact keys — any other key
(`write:`, `mcp:`, ...) is dead config:

- `edit` — governs ALL file modifications: the `edit`, `write`, AND
  `apply_patch` tools all assert `action: "edit"`. **There is no separate
  `write` permission key.** Scope by resource path (`"reports/**": allow`)
  on the `edit` key.
- `read` — read tool; also MCP resource reads, which match patterns of the
  form `mcp:<server>:<uri>` against the `read` key (not a tool-name match).
- `bash` — shell; pattern matched against the full parsed command string
  (e.g. `git status --porcelain`).
- `task` — subagent spawn; pattern matched against the **subagent type**
  (agent name), not a file path.
- `skill`, `question`, `webfetch`, `websearch`, `glob`, `grep`, `lsp`,
  `external_directory`, `doom_loop` — as documented.
- **MCP tools** — the permission key is the FULL TOOL NAME:
  `<sanitized-server>_<tool-name>` (e.g. `godot-mcp-runtime_add_node`;
  catalog.ts:119 — `toolName = sanitize(server) + "_" + sanitize(name)`).
  That is why `"godot-mcp-runtime_*": allow` works: it wildcards the whole
  key. A bare `"godot-mcp-runtime"` (server name, no `_`) matches nothing —
  always keep the underscore and trailing tool wildcard.

## Evaluation order

`findLast` over the flattened ruleset — **last matching rule wins**. Put
catch-alls (`"*": deny`) FIRST and narrower grants after. Unmatched →
`"ask"` (interactive approval); in headless/benchmark runs an "ask" cannot
be answered, so effectively treat unlisted actions as unavailable. Agent
frontmatter rules are merged with global/project config (agent rules last →
they win conflicts).

## Deny semantics

A matching `deny` is checked first and blocks outright (it never degrades
to "ask"). Additionally, `deny` with action `*` and resource `*` makes
opencode **hide the tool from the model entirely** — including MCP tools:
a broad `"*: deny` typo'd to match a server-prefixed tool name will hide
the engine toolset.

## Subagent inheritance gotcha

opencode auto-appends `task: "*": deny` and `todowrite: "*": deny` to
subagent sessions that don't declare those keys — subagents can't spawn
subagents or write todos unless explicitly granted.

## Frontmatter patterns for this repo's agents

- `edit: "**/*.gd": allow` — game logic scripts are engine-specific but
  portable within an engine
- Deny-by-default for skill internals (`skills/*/scripts/*.gd`) — protect
  implementations from runtime edits; scope denies narrowly so bootstrap
  steps that legitimately copy files aren't blocked
- Grant narrow write scopes only where a role genuinely produces artifacts
  (e.g. report directories)
- Every permission grant gets a reason comment: what task it unblocks, and
  what its scope limits
