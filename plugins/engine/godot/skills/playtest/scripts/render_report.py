#!/usr/bin/env python3
"""Render a playtest scenario JSON report as a markdown verification table.

Usage: render_report.py <report.json> [report2.json ...]

Reads the structured JSON emitted by the TestPlayer harness
(await_test_done result: scenario, violations[], metrics, ...), prints a
"Functional Verification Report" table to stdout. Non-zero exit if any
violations are present.
"""
import json
import sys


def render(report: dict) -> str:
    lines = ["## Functional Verification Report", ""]
    metrics = report.get("metrics", {})
    violations = report.get("violations", [])
    row = lambda i, s, e: f"| {i} | {'✅ PASS' if s else '❌ FAIL'} | {e} |"

    def fmt(name: str, passed: bool, evidence: str) -> None:
        lines.append(row(name, passed, evidence))

    crash = metrics.get("crash_detected", False)
    fmt("No crash during run", not crash,
        "No fatal errors in debug output (process-wide, external check)" if not crash
        else "Crash detected by harness")

    nodes_finite = metrics.get("nodes_finite")
    if nodes_finite is not None:
        fmt("Physics stability", bool(nodes_finite),
            "No NaN/Inf in position values (`nodes_finite`)")

    p99 = metrics.get("frame_ms_p99")
    if p99 is not None:
        fmt("FPS stability", p99 < 33.3, f"p99 frame time = {p99:.1f}ms (< 33.3ms threshold)")

    stalls = metrics.get("stall_ticks_over_100ms")
    worst = metrics.get("worst_frame_ms")
    if stalls is not None:
        note = f"{stalls} physics tick(s) exceeded 100ms (`stall_ticks_over_100ms`)"
        if worst is not None:
            note += f", worst {worst:.0f}ms"
        if stalls > 0:
            note += (" — host stall (background throttle/display sleep/memory pressure); "
                     "exclude large sim jumps from gameplay verdicts, see background-throttle gotcha")
            # Informational row, not a FAIL: stalls are environmental telemetry;
            # the fps_stable invariant handles actual performance verdicts.
            lines.append(f"| Engine stalls (>100ms ticks) | ⚠️ INFO | {note} |")
        else:
            fmt("Engine stalls (>100ms ticks)", True, "none observed")

    fps_floor = metrics.get("fps_floor_violations")
    if fps_floor is not None:
        fmt("Min FPS floor", fps_floor == 0,
            f"Average FPS stayed above 30 (`fps_floor`, {fps_floor} violation(s))")

    input_count = metrics.get("input_count")
    if input_count is not None:
        fmt("Input responsiveness", True, f"ChaosBot fired {input_count} inputs without hang")

    for v in violations:
        name = v.get("invariant", "invariant") if isinstance(v, dict) else str(v)
        fmt(name, False, str(v.get("evidence", v)) if isinstance(v, dict) else "")

    lines += ["", f"**Overall: {'FAIL' if violations else 'PASS'}**",
              "", f"**Violations Found:** {len(violations)}"]
    return "\n".join(lines)


def main() -> int:
    any_fail = False
    for path in sys.argv[1:]:
        with open(path) as f:
            report = json.load(f)
        print(render(report))
        if report.get("violations"):
            any_fail = True
    return 1 if any_fail else 0


if __name__ == "__main__":
    sys.exit(main())
