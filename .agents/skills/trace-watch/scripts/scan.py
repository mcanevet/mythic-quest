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
  scan.py <sandbox-dir-substring> [--sessions] [--json] [--perf]
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
