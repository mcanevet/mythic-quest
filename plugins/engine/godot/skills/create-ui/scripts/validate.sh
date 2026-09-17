#!/usr/bin/env bash
# Thin wrapper — delegates to the canonical shared validate.sh in
# create-entity. Kept so SKILL.md references to "scripts/validate.sh
# (in this skill)" keep working.
exec bash "$(dirname "$0")/../../create-entity/scripts/validate.sh" "$@"
