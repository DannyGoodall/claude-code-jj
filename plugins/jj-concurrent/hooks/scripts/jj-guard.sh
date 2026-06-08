#!/usr/bin/env bash
# jj-guard.sh — PreToolUse hook (Bash).
#
# Blocks the small set of commands that corrupt jj state, hang agent sessions,
# or destroy the repository, for BOTH orchestrator and worker roles. It is
# deliberately CHEAP and HANG-PROOF: it pattern-matches the command string and
# NEVER invokes jj (jj can hang, and a guard that hangs on every Bash call is
# worse than no guard). Role-specific rules (bookmarks/push are orchestrator-
# only) are enforced by the worker-agent contract in v0.1.0, not here.
#
# Exit 0 = allow. Exit 2 = block (stderr is shown to the model, which course-
# corrects). Fails OPEN on any internal error.

set -uo pipefail

input="$(cat 2>/dev/null || true)"
[ -z "$input" ] && exit 0

# Extract the command; fail open if jq is unavailable or parsing fails.
if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
else
  exit 0
fi
[ -z "$cmd" ] && exit 0

# Only enforce inside a jj repository. The guard's whole purpose is protecting
# jj state, so outside a jj repo it must FAIL OPEN — raw git is legitimate
# there and blocking it would break ordinary git workflows in any other repo
# where this plugin happens to be enabled (it is user-scoped). Detection is a
# cheap upward walk for a .jj entry — no jj invocation, so it cannot hang.
# (Limitation, as with the gt-guard precedent: evaluated from the session's
# cwd, so a `cd <jj-repo> && …` compound is judged from the previous cwd.)
dir="$PWD"; in_jj=""
while [ "$dir" != "/" ]; do
  if [ -e "$dir/.jj" ]; then in_jj="1"; break; fi
  dir="$(dirname "$dir")"
done
[ -n "$in_jj" ] || exit 0

block() { echo "BLOCKED by jj-guard: $1" >&2; exit 2; }

# 1) Destructive ops on the jj/git stores. The geirsson incident: an agent
#    "debugged" a jj hang with `rm -rf .jj` — only git's backing saved it.
#    Recovery is orchestrator-only (jj op restore / jj op log).
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_./-])rm([[:space:]]+-[[:alnum:]]+)*[[:space:]]+[^|;&]*\.(jj|git)([/[:space:]"'\'']|$)'; then
  block "refusing 'rm' targeting .jj/.git. Never delete the VCS store to fix a hang — recovery is orchestrator-only (jj op restore)."
fi

# 2) State-mutating raw git in a (colocated) jj repo corrupts jj state.
#    Read-only git (log/status/show/diff/rev-parse) stays allowed; gh is fine.
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_./-])git[[:space:]]+(commit|add|checkout|switch|reset|rebase|merge|cherry-pick|stash|restore|am|apply|clean|mv|rm)([[:space:]]|$)'; then
  block "raw mutating git corrupts jj state in a colocated repo. Use jj for version control (and gh for PRs). Read-only git (log/status/show/diff) is allowed."
fi
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_./-])git[[:space:]]+branch[[:space:]]+-[dDmM]'; then
  block "raw git branch mutation corrupts jj state. Use jj bookmark (orchestrator only)."
fi

# 3) Interactive jj that hangs agent sessions (no TTY for the editor/TUI).
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_./-])jj[[:space:]]+(resolve|arrange|diffedit)([[:space:]]|$)'; then
  block "interactive jj command hangs automation. Edit conflict markers directly, or use jj restore / jj rebase / jj parallelize."
fi
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_./-])jj[[:space:]]+config[[:space:]]+edit([[:space:]]|$)'; then
  block "jj config edit opens an editor. Use jj config set <key> <value>."
fi
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_./-])jj[[:space:]]+sparse[[:space:]]+edit([[:space:]]|$)'; then
  block "jj sparse edit opens an editor. Use jj sparse set --add/--remove <path>."
fi
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_./-])jj[[:space:]][^|;&]*(--interactive|[[:space:]]-i)([[:space:]]|$)'; then
  block "interactive jj (-i/--interactive) hangs automation. Provide filesets and -m instead."
fi

exit 0
