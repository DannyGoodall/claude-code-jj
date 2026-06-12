#!/usr/bin/env bash
# Noise-filtering wrapper for openspec/opsx CLI invocations (jj-openspec §3.5).
# The allow-list table in SKILL.md is the source of truth for the dropped
# phrases; keep the two greps below in sync with it.

# run an openspec/opsx command, drop only known-harmless stderr, keep exit code
opsx_filtered() {
  command -v openspec >/dev/null 2>&1 || {
    echo "BLOCKER: openspec CLI not found on PATH" >&2; return 127; }
  local err; err="$( { "$@" 2>&1 1>&3 3>&-; } 3>&1 )"; local code=$?
  printf '%s\n' "$err" \
    | grep -v -e "Rules for 'tasks' must be an array" \
              -e "Unknown artifact ID in rules" >&2
  return $code
}
# usage: opsx_filtered openspec validate <change> --no-pager
