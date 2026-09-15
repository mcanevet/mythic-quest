#!/bin/bash
# Stop the spawned Godot engine process WITHOUT killing the MCP server.
#
# Why this script exists: agents have historically used pkill directly, and the
# argv semantics of `pkill -f godot --path` (unquoted) make pkill's effective
# pattern just "godot" — which matches `npx godot-mcp-runtime` (the MCP server
# itself), permanently disconnecting all engine MCP tools (no auto-reconnect).
# This script encapsulates the one safe kill pattern; agents never invoke pkill.
#
# Usage: stop_engine.sh          — kill engine, wait for port release
# Exit codes: 0 = stopped (or nothing running), non-zero = unexpected failure

set -u

# Matches only the spawned engine process: `godot --path <dir> ...`
# Does NOT match `npx godot-mcp-runtime` (no `--path` in its command line).
pkill -f 'godot --path' 2>/dev/null
RC=$?

if [ $RC -eq 0 ]; then
  echo "engine process(es) signalled"
elif [ $RC -eq 1 ]; then
  echo "no matching engine process found"
else
  echo "pkill failed with exit $RC" >&2
  exit $RC
fi

# Wait for socket teardown (macOS TIME_WAIT recycling) before restart attempts.
sleep 3
echo "engine stopped"
