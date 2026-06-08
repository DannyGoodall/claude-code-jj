#!/usr/bin/env bash
# jj-snapshot.sh — PostToolUse hook (Edit|MultiEdit|Write|NotebookEdit).
#
# jj snapshots the working copy only when a jj command runs. An agent that
# edits files and then crashes BEFORE any jj command would lose that last
# edit. This hook forces a snapshot after every edit, so every change is
# captured into the workspace's working-copy commit and is recoverable via
# `jj evolog` / `jj op restore`.
#
# Design constraints:
#   - Fail-open ALWAYS (never block or error an agent edit).
#   - Never run outside a jj repo.
#   - Time-bounded: jj occasionally hangs; a stuck snapshot must not wedge the
#     agent, so we cap it and move on. A missed snapshot just means the NEXT
#     jj command captures the change — no data loss, only a smaller window.

command -v jj >/dev/null 2>&1 || exit 0

# Cheap jj-repo detection by walking up for a .jj entry — no jj invocation,
# so this is hang-proof even if the jj process layer is misbehaving.
dir="$PWD"
found=""
while [ "$dir" != "/" ]; do
  if [ -e "$dir/.jj" ]; then found="$dir"; break; fi
  dir="$(dirname "$dir")"
done
[ -n "$found" ] || exit 0

# Snapshot the working copy for the current workspace, time-bounded and quiet.
if command -v timeout >/dev/null 2>&1; then
  timeout 30 jj util snapshot --quiet >/dev/null 2>&1 || true
else
  jj util snapshot --quiet >/dev/null 2>&1 || true
fi

exit 0
