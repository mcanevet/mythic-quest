#!/usr/bin/env python3
"""trace-watch scan: retrospective per-specialist checklist extraction.

Runs the trace-watch retrospective checklist mechanically against the
opencode session DB for a sandbox directory. Outputs, per session:
  CLAIM   -- bd claim/close commands with their real outcomes
  DENY    -- genuine permission refusals (corpus echoes filtered)
  IMPROV  -- improvisation/fallback language in reasoning parts
  ERR     -- error-shaped tool outputs

Corpus-echo filter: file-content echoes (skill/README reads) contain
words like "denied" without being real refusals. We mark outputs that
are wrapped in file-content markers (<path>, <skill_content>, line
numbers) as echoes and skip them.

Usage:
  scan.py <sandbox-dir-substring> [--sessions] [--json] [--perf] [--deep]
                                     [--latency]
"""
import json
import re
import sqlite3
import sys
from collections import defaultdict

DB = "~/.local/share/opencode/opencode.db"
import os
DB = os.path.expanduser(DB)


def perf_report(sub):
    """Performance & waste lens: per-session time/token/error summary."""
    sessions = load_sessions(sub)
    print(f"# trace-watch perf scan: '{sub}' — {len(sessions)} sessions")
    print("# (orchestrator wall time includes idle waits; trust tool-time + calls)")
    sig_counts = defaultdict(int)
    dup_reads = defaultdict(int)
    big_outs = []
    for sid, agent, title, ts in load_sessions(sub):
        created, updated = None, None
        tool_time = 0.0
        fails = 0
        reads = []
        turns = 0
        tokens_in = tokens_out = 0
        db = sqlite3.connect(DB)
        for (tc, tu, raw) in db.execute(
            "SELECT time_created, time_updated, data FROM part "
            "WHERE session_id=? ORDER BY time_created, id", (sid,)
        ):
            created = created or tc
            updated = tu or updated
            try:
                d = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if d.get("type") == "tool":
                turns += 1
                dur = max(0, ((tu or tc) - tc)) / 1000
                tool_time += dur
                st = d.get("state") or {}
                out = str(st.get("output") or "")
                err = str(st.get("error") or "")
                if st.get("status") == "error" or ERRSIG.search(out + err):
                    fails += 1
                    # normalize signature: first error-ish line, digits stripped
                    line = (err.split("\n") or out.split("\n"))[0] if (err or out) else "?"
                    m = ERRSIG.search(out + err)
                    if m:
                        line = m.group(0)
                    sig = re.sub(r"\d+", "N", line)[:90]
                    sig_counts[(d.get("tool", "?"), sig)] += 1
                if d.get("tool") == "read":
                    fp = (st.get("input") or {}).get("filePath")
                    if fp:
                        reads.append(fp)
                blob = out + err
                if len(blob) > 4000:
                    big_outs.append((len(blob) // 1000, d.get("tool"), sid[-6:]))
            elif d.get("type") == "reasoning":
                turns += 0  # reasoning isn't a tool turn; counted via part count below
        for fp, cnt in {fp: reads.count(fp) for fp in reads}.items():
            if cnt > 1:
                dup_reads[(agent, fp.split("/")[-1])] += cnt - 1
        wall = ((updated or created) - created) / 60000 if created else 0
        print(
            f"{agent:8} {wall:6.0f}m wall  {tool_time:6.0f}s tool  "
            f"{turns:3d} calls  {fails:2d} fails  | {title[:52]}"
        )
    print("\n## Top failure signatures (repeat >= 2 = corpus gap)")
    for (tool, sig), n in sorted(sig_counts.items(), key=lambda x: -x[1])[:12]:
        if n >= 2:
            print(f"  {n:3d}x [{tool}] {sig}")
    print("\n## Duplicate reads within sessions")
    for (agent, fn), n in sorted(dup_reads.items(), key=lambda x: -x[1])[:12]:
        if n >= 1:
            print(f"  {n:2d}x extra {fn} ({agent})")
    print("\n## Largest outputs swallowed (kB)")
    for kb, tool, sid in sorted(big_outs, reverse=True)[:8]:
        print(f"  {kb:5d}kB [{tool}] ({sid})")



ECHO = re.compile(
    r"<skill_content|<path>|<type>file</type>|^\s*\d+: |SKILL\.md|AGENTS\.md|"
    r"rules\.yaml|reference/",
    re.M,
)
REAL_DENY = re.compile(
    r"(permission denied|denied by (permission|policy|permissions)"
    r"|not permitted|Blocked by permission|Error updating|already claimed"
    r"|Operation not permitted)",
    re.I,
)
IMPROV = re.compile(
    r"\b(fallback|workaround|cannot write|can'?t write|improvis"
    r"|instead of writing|writes? (?:were |are )?denied)",
    re.I,
)
ERRSIG = re.compile(
    r"(SCRIPT ERROR|Parse Error|Failed loading resource|MCP error"
    r"|__process failed|Invalid access)",
)
# Deliberation-spiral markers in reasoning text: hedging/self-questioning
# that correlates with hypothesis-loop sessions.
SPIRAL = re.compile(
    r"^(wait|but wait|hmm|maybe|perhaps|possibly|odd|weird|strange"
    r"|interesting|suspicious|confusing|still stuck|let me try again"
    r"|something is deeply wrong|time to compress|rather than)"
    r"\b|\?$",
    re.I,
)


def deep_report(sub):
    """Reasoning-lens report: spirals, probe loops, cross-session signature
    duplication, engine relaunches. Complements --perf (which reads tool
    outputs) by reading reasoning traces and cross-session patterns."""
    sessions = load_sessions(sub)
    print(f"# trace-watch deep scan: '{sub}' — {len(sessions)} sessions")
    print("# (higher spiral ratio = more hedging/self-questioning per action;")
    print("#  >= 0.5 flagged = hypothesis-loop session, review by hand)")
    sigs_by_session = defaultdict(set)  # session -> normalized error sigs
    sig_sessions = defaultdict(set)    # sig -> sessions containing it
    probe_scripts = defaultdict(int)   # (agent, script-head) -> count
    relaunches = 0
    rows = []
    for sid, agent, title, ts in sessions:
        created, updated = None, None
        tools = 0
        spiral_hits = 0
        reasoning_parts = 0
        reasoning_s = 0.0
        run_script_streak = 0
        max_streak = 0
        db = sqlite3.connect(DB)
        for (tc, tu, raw) in db.execute(
            "SELECT time_created, time_updated, data FROM part "
            "WHERE session_id=? ORDER BY time_created, id", (sid,)
        ):
            created = created or tc
            updated = tu or updated
            try:
                d = json.loads(raw)
            except json.JSONDecodeError:
                continue
            t = d.get("type")
            if t == "tool":
                tools += 1
                st = d.get("state") or {}
                tool = d.get("tool", "?")
                out = str(st.get("output") or "")
                err = str(st.get("error") or "")
                m = ERRSIG.search(out + err)
                if m:
                    sig = re.sub(r"\d+", "N", m.group(0))[:80]
                    sigs_by_session[sid].add((tool, sig))
                    sig_sessions[(tool, sig)].add(agent)
                if tool == "godot_run_project":
                    relaunches += 1
                if tool == "godot_run_script":
                    run_script_streak += 1
                    max_streak = max(max_streak, run_script_streak)
                    head = re.sub(
                        r"\d+", "N", str((st.get("input") or {}).get("script", ""))[:120]
                    )
                    probe_scripts[(agent, head)] += 1
                else:
                    run_script_streak = 0
            elif t == "reasoning":
                reasoning_parts += 1
                tm = d.get("time") or {}
                reasoning_s += (tm.get("end", 0) - tm.get("start", 0)) / 1000
                txt = d.get("text") or ""
                for line in txt.split("\n"):
                    if SPIRAL.match(line.strip()):
                        spiral_hits += 1
        ratio = (spiral_hits / tools) if tools else 0
        rows.append(
            (agent, title, sid[-6:], spiral_hits, reasoning_parts, reasoning_s,
             tools, ratio, max_streak)
        )
    for agent, title, sid6, sp, rp, rs, tools, ratio, streak in rows:
        flag = "⚠️ " if ratio >= 0.5 else "  "
        print(
            f"{flag}{agent:8} spiral={sp:3d}/{tools:3d} tools ({ratio:.2f})  "
            f"reason={rp:3d} parts ({rs:6.0f}s)  probe-max-streak={streak:2d} "
            f"| {title[:44]} ({sid6})"
        )
    print(f"\n## Engine relaunches (godot_run_project): {relaunches} run-total")
    print("   (each relaunch re-pays project import + state setup; >1 per")
    print("    specialist = cold-start tax)")
    dup = [
        (n, agent, head)
        for (agent, head), n in probe_scripts.items()
        if n >= 3
    ]
    if dup:
        print("\n## Repeated probe scripts (>= 3x same head, same agent)")
        for n, agent, head in sorted(dup, reverse=True)[:8]:
            print(f"  {n:3d}x ({agent}) {head[:100]}")
    shared = [
        (tool, sig, sorted(agents))
        for (tool, sig), agents in sig_sessions.items()
        if len(agents) > 1
    ]
    if shared:
        print("\n## Error signatures shared across >= 2 agents")
        print("   (same failure hit by siblings = missing durable artifact")
        print("    or upstream defect — one bead should cover all sessions)")
        for tool, sig, agents in sorted(shared, key=lambda x: -len(x[2]))[:10]:
            print(f"  [{tool}] {sig} — agents: {', '.join(agents)}")


def latency_report(sub):
    """Latency & turn-economy lens: wall vs tool vs reasoning time,
    gap anatomy, duplicate calls, orchestrator bd-admin ratio,
    stop-project failure rate, cross-session file-read overlap,
    skill payload census, token decomposition, wave parallelism."""
    sessions = load_sessions(sub)
    print(f"# trace-watch latency scan: '{sub}' — {len(sessions)} sessions")
    print("# wall = session span; tool = sum(tool durations); reason = sum")
    print("# (reasoning span durations); gaps = inter-tool wait, the model/")
    print("# API latency surface. Turn count is the cost lever (see bead 4qr).")
    reads_by_file = defaultdict(set)  # basename -> {agents}
    skill_census = defaultdict(lambda: [0, 0])  # name -> [loads, chars]
    stop_fail = [0, 0]  # total stop_project fails/total
    edit_sets = defaultdict(set)  # agent -> set of files edited
    span = {}  # agent -> (start, end) merged for parallelism check
    for sid, agent, title, ts in sessions:
        created = updated = None
        tool_time = reasoning_s = 0.0
        turns = 0
        last_t = None
        gaps = []
        dups = defaultdict(int)
        bd_admin = dispatches = 0
        tokin = tok_cr = 0
        top_step = 0
        db = sqlite3.connect(DB)
        for (tc, tu, raw) in db.execute(
            "SELECT time_created, time_updated, data FROM part "
            "WHERE session_id=? ORDER BY time_created, id", (sid,)
        ):
            created = created or tc
            updated = tu or updated
            try:
                d = json.loads(raw)
            except json.JSONDecodeError:
                continue
            t = d.get("type")
            if t == "tool":
                turns += 1
                st = d.get("state") or {}
                tool = d.get("tool", "?")
                inp = st.get("input") or {}
                out = str(st.get("output") or "")
                err = str(st.get("error") or "")
                tool_time += max(0, (tu or tc) - tc) / 1000
                if last_t is not None:
                    gaps.append((tc - last_t) / 1000)
                last_t = tc
                key = (tool, json.dumps(inp, sort_keys=True))
                dups[key] += 1
                if tool == "read":
                    fp = inp.get("filePath")
                    if fp:
                        reads_by_file[fp.split("/")[-1]].add(agent)
                elif tool == "skill":
                    nm = inp.get("name", "?")
                    skill_census[nm][0] += 1
                    skill_census[nm][1] += len(out)
                elif tool == "task":
                    dispatches += 1
                elif tool == "bash":
                    cmd = str(inp.get("command", ""))
                    if re.match(r"\s*(bd |.*; bd )", cmd) or " bd " in f" {cmd} ":
                        bd_admin += 1
                elif tool == "godot_stop_project":
                    stop_fail[1] += 1
                    if re.search(r"error|not permitted", (out + err), re.I):
                        stop_fail[0] += 1
                if tool in ("edit", "write"):
                    fp = inp.get("filePath") or ""
                    if fp:
                        edit_sets[agent].add(fp.split("/")[-1])
            elif t == "reasoning":
                tm = d.get("time") or {}
                reasoning_s += (tm.get("end", 0) - tm.get("start", 0)) / 1000
            elif t == "step-finish":
                tk = d.get("tokens") or {}
                tokin += tk.get("input", 0)
                top_step = max(top_step, tk.get("input", 0))
                tok_cr += (tk.get("cache") or {}).get("read", 0)
        if created:
            if agent not in span:
                span[agent] = [created, updated or created]
            else:
                span[agent][0] = min(span[agent][0], created)
                span[agent][1] = max(span[agent][1], updated or created)
        wall = ((updated or created) - created) / 60000 if created else 0
        gap_sum = sum(gaps)
        big = sum(g for g in gaps if g > 60)
        dup_n = sum(n - 1 for n in dups.values() if n >= 3)
        bd_note = ""
        if dispatches or bd_admin:
            bd_note = f"  bd-admin={bd_admin} dispatch={dispatches}"
        tok_note = (
            f"  in={tokin/1000:6.0f}k peak={top_step//1000:3d}k cr={tok_cr/1000:4.0f}k"
            if tokin else ""
        )
        print(
            f"  {agent:8} {wall:5.1f}m wall  {tool_time:5.0f}s tool  "
            f"{reasoning_s:5.0f}s reason  {turns:3d} turns  "
            f"gaps={gap_sum/60:5.1f}m (>{60}s: {big/60:4.1f}m)  "
            f"dupcalls>=3x={dup_n}{bd_note}{tok_note}"
        )
    if stop_fail[1]:
        print(
            f"\n## godot_stop_project failures: {stop_fail[0]}/{stop_fail[1]}"
            " (every failure risks pkill-denial retries + engine relaunch;"
            " see bead 60b upstream fix)"
        )
    print("\n## Skill payload census (per-load size drives per-session")
    print("   input-token tax; >10kB/load = split candidate, bead zpb)")
    for nm, (loads, chars) in sorted(skill_census.items(), key=lambda x: -x[1][1]):
        per = chars // loads if loads else 0
        flag = "⚠️ " if per > 10000 else "  "
        print(f"  {flag}{nm:16} {loads:2d} loads, {per:5d} B/load")
    print("\n## Cross-session file reads (>=3 agents = dispatch lacks")
    print("   project map; bead d9w)")
    for fn, agents in sorted(reads_by_file.items(), key=lambda x: -len(x[1])):
        if len(agents) >= 3:
            print(f"  {fn:30} read by {len(agents)} agents")
    print("\n## Wave parallelism (edit-set disjointness between agents;")
    print("   disjoint pair = could have run concurrently; bead hbm)")
    agents = sorted(edit_sets)
    for i in range(len(agents)):
        for j in range(i + 1, len(agents)):
            inter = edit_sets[agents[i]] & edit_sets[agents[j]]
            if not inter:
                print(f"  {agents[i]:8} ⊥ {agents[j]:8} — disjoint edits,"
                      " concurrency was safe")
    clash = [
        (a, b, sorted(edit_sets[a] & edit_sets[b])[:4])
        for i, a in enumerate(agents)
        for b in agents[i + 1:]
        if edit_sets[a] & edit_sets[b]
    ]
    if clash:
        print("  overlapping editors (serialization justified):")
        for a, b, files in clash:
            print(f"  {a:8} ∩ {b:8} — {', '.join(files)}")


def load_sessions(sub):
    db = sqlite3.connect(DB)
    return db.execute(
        "SELECT id, agent, title, time_created FROM session "
        "WHERE directory LIKE ? ORDER BY time_created",
        (f"%{sub}%",),
    ).fetchall()


def parts(sid):
    db = sqlite3.connect(DB)
    for (raw,) in db.execute(
        "SELECT data FROM part WHERE session_id=? ORDER BY time_created, id",
        (sid,),
    ):
        try:
            yield json.loads(raw)
        except json.JSONDecodeError:
            continue


def scan_session(sid, agent, title):
    findings = []
    for d in parts(sid):
        t = d.get("type")
        if t == "tool":
            st = d.get("state") or {}
            out = st.get("output") or ""
            err = st.get("error") or ""
            tool = d.get("tool", "?")
            inp = json.dumps(st.get("input", {}))[:100]
            # claims/close audit: every bd state-changing command
            if tool == "bash" and re.search(r"bd (update|close|create|comment)", inp):
                first = (out or err).split("\n")[0][:120]
                flag = "!" if re.search(r"rror|efused|lready", first) else " "
                findings.append(f"  {flag} CLAIM {inp[:90]} => {first}")
            blob = out + "\n" + err
            if ECHO.search(blob[:500]):
                continue  # file-content echo, skip whole output
            for m in REAL_DENY.finditer(blob):
                ctx = blob[max(0, m.start() - 90):m.end() + 90].replace("\n", " ¶ ")
                findings.append(f"  DENY [{tool}] {ctx[:230]}")
            for m in ERRSIG.finditer(blob):
                ctx = blob[max(0, m.start() - 60):m.end() + 120].replace("\n", " ¶ ")
                findings.append(f"  ERR  [{tool}] {ctx[:200]}")
        elif t == "reasoning":
            txt = d.get("text", "")
            for m in IMPROV.finditer(txt):
                ctx = txt[max(0, m.start() - 110):m.end() + 130].replace("\n", " ¶ ")
                findings.append(f"  IMPROV (reasoning) {ctx[:240]}")
    return findings


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    sub = sys.argv[1]
    if "--perf" in sys.argv:
        perf_report(sub)
        return
    if "--deep" in sys.argv:
        deep_report(sub)
        return
    if "--latency" in sys.argv:
        latency_report(sub)
        return
    sessions = load_sessions(sub)
    print(f"# trace-watch scan: '{sub}' — {len(sessions)} sessions")
    for sid, agent, title, ts in sessions:
        findings = scan_session(sid, agent, title)
        if findings:
            print(f"\n## {agent}: {title[:60]} ({sid[-6:]})")
            seen = set()
            for f in findings:
                k = f[:80]
                if k in seen:
                    continue
                seen.add(k)
                print(f)


if __name__ == "__main__":
    main()
