#!/usr/bin/env bash
# jj-guard.sh — PreToolUse hook (Bash).
#
# Blocks the small set of commands that corrupt jj state, hang agent sessions,
# or destroy the repository, for BOTH orchestrator and worker roles. It is
# deliberately CHEAP and HANG-PROOF: it pattern-matches the command string and
# NEVER invokes jj (jj can hang, and a guard that hangs on every Bash call is
# worse than no guard). It ALSO enforces the orchestrator/worker role floor:
# it detects its workspace role from the located .jj/repo (a directory = the
# default workspace = orchestrator; a regular file = a linked workspace =
# worker) using only filesystem type tests, and when running as a WORKER it
# blocks the orchestrator-only operations `jj bookmark …` and `jj git push`.
# Orchestrator and undetermined roles fail open (these stay allowed).
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
#
# cwd resolution: the hook sees the SESSION's $PWD, which lags a `cd` inside
# the command being guarded. So a `cd <other-repo> && git …` would otherwise
# be judged from the session repo. We parse a single leading `cd <dir>` (incl.
# a `(cd <dir>` subshell, quoted/relative/absolute/~ targets) and detect from
# THAT effective directory. This covers the common case; arbitrary mid-command
# directory changes are still judged from the leading cwd (documented limit).
effdir="$PWD"
lead="${cmd#"${cmd%%[![:space:]]*}"}"       # ltrim
lead="${lead#(}"                             # drop a leading subshell paren
lead="${lead#"${lead%%[![:space:]]*}"}"      # ltrim again
case "$lead" in
  "cd "*|"cd"$'\t'*)
    tgt="${lead#cd}"
    tgt="${tgt#"${tgt%%[![:space:]]*}"}"     # ltrim
    tgt="${tgt%%[&;|)]*}"                      # stop at && ; | or closing )
    tgt="${tgt%"${tgt##*[![:space:]]}"}"      # rtrim
    tgt="${tgt%\"}"; tgt="${tgt#\"}"          # strip surrounding quotes
    tgt="${tgt%\'}"; tgt="${tgt#\'}"
    case "$tgt" in
      "")   ;;                                  # bare `cd` → keep $PWD
      /*)   effdir="$tgt" ;;
      "~"|"~/"*) effdir="${HOME}${tgt#\~}" ;;
      *)    effdir="$PWD/$tgt" ;;
    esac
    ;;
esac

dir="$effdir"; in_jj=""; jjdir=""
while [ -n "$dir" ] && [ "$dir" != "/" ]; do
  if [ -e "$dir/.jj" ]; then in_jj="1"; jjdir="$dir/.jj"; break; fi
  dir="$(dirname "$dir")"
done
[ -n "$in_jj" ] || exit 0

block() { echo "BLOCKED by jj-guard: $1" >&2; exit 2; }

# Role detection (cheap, jj-free). The located .jj/repo encodes role with zero
# coordination: in the DEFAULT workspace .jj/repo is the store DIRECTORY itself
# (orchestrator); in a LINKED workspace created by `jj workspace add` it is a
# regular FILE pointing back at the default store (worker). Anything else (e.g.
# a symlink or exotic layout) is UNKNOWN. Only filesystem type tests — never a
# jj invocation — so role detection cannot hang.
role="unknown"
if [ -d "$jjdir/repo" ]; then
  role="orchestrator"
elif [ -f "$jjdir/repo" ]; then
  role="worker"
fi

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

# 4) Worker role floor: in a LINKED workspace, bookmarks/refs and push are
#    ORCHESTRATOR-ONLY (the jj-delegate role split). The orchestrator (default
#    workspace) and any UNKNOWN role fall through and ALLOW these — fail open,
#    never wrongly block the default workspace. Commit-shaping (jj new/describe/
#    squash/split/rebase) is never matched here and stays free for workers.
if [ "$role" = "worker" ]; then
  if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_./-])jj[[:space:]]+bookmark([[:space:]]|$)'; then
    block "jj bookmark is orchestrator-only. Workers must not touch bookmarks/refs — report your change and let the orchestrator integrate and push."
  fi
  if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_./-])jj[[:space:]]+git[[:space:]]+push([[:space:]]|$)'; then
    block "jj git push is orchestrator-only. Workers never push — report your change and let the orchestrator integrate and push."
  fi
fi

exit 0
