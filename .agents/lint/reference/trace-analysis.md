# Trace Analysis

Deep-dive patterns for analyzing extracted session traces
(`/tmp/session_trace.json` from the SKILL.md extraction query).

## Pretty-printing a single message with all parts

```bash
sqlite3 -json ~/.local/share/opencode/opencode.db \
  "SELECT m.id, m.time_created, p.type, json_extract(p.data, '$.content') as content FROM message m JOIN part p ON p.message_id = m.id WHERE m.session_id = '$ROOT_ID' ORDER BY m.time_created, p.time_created;" | jq '.'
```

## Extracting tool calls with status and input

```bash
sqlite3 -json ~/.local/share/opencode/opencode.db \
  "SELECT json_extract(p.data,'\$.type') as type, json_extract(p.data,'\$.tool') as tool,
          json_extract(p.data,'\$.state.status') as status,
          substr(coalesce(json_extract(p.data,'\$.state.output'), json_extract(p.data,'\$.text'),
                 json_extract(p.data,'\$.reason')),1,300) as detail
   FROM part p WHERE p.session_id = '$SESSION_ID' ORDER BY p.time_created DESC LIMIT 10;"
```

Then format with a small python filter (handles the `coalesce` chaos):

```python
import json, sys
for r in json.load(sys.stdin):
    d = (r.get('detail') or '').replace(chr(10), ' ')
    if r['type'] == 'tool':
        print(f"{'ERRO' if r.get('status')=='error' else 'comp'} {(r.get('tool') or '')[:24]} | {d[:180]}")
    elif r['type'] in ('text', 'reasoning'):
        print(f"[{r['type']}] {d[:200]}")
```

## What to look for in reasoning traces

- **Stalls:** large `time_updated` gaps with NO tool-call activity = host sleep (ignore); repeated reasoning mentioning the same error = spin loop
- **Permission denials:** `"type":"tool"` parts with errors containing "permission denied" or "blocked"
- **Format errors:** tool calls with wrong field names (`file_path` vs `filePath`)
- **Skill invocation failures:** missing script files, wrong paths, template mismatches

## Cross-session pattern analysis

Feed the trace JSON into external tools (jq, python) for pattern detection:
retry loops (same tool error repeating), skill-choice correlation with
outcomes, and efficiency-vs-outcome correlation (retry counts × playtest pass
rates — see AGENTS.md "Evidence Loop").

## DB Schema Notes

- `session`: `id`, `parent_id` (NULL = root), `agent`, `project_id`, `slug`,
  `time_created`/`time_updated` (ms since epoch)
- `part`: `session_id`, `message_id`, `time_created`, `data` (JSON blob with
  `$.type` ∈ patch/reasoning/text/tool/step-start/step-finish)
- `project`: `id`, `path`
- WAL mode: direct reads safe during active sessions
