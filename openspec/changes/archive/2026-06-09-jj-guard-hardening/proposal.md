## Why

The initial guard hook enforced its rules on every Bash command regardless of repository. Because the plugin is user-scoped, this over-blocked raw git in **non-jj** repositories (e.g. an ordinary git or GitButler project), breaking normal git workflows there. It also judged repository membership from the session's working directory, so a `cd <other-repo> && git …` command was judged from the wrong directory. The guard's purpose is protecting *jj* state, so it must apply only inside a jj repo and must understand a leading directory change.

## What Changes

- The guard hook SHALL **only enforce inside a jj repository**, failing open everywhere else — detected by a cheap upward walk for a `.jj` entry (no jj invocation, so it cannot hang).
- The guard SHALL resolve the effective directory by parsing a **single leading `cd <dir>`** (including a `(cd <dir>` subshell and quoted/relative/absolute/`~` targets), so `cd <non-jj-repo> && git …` is judged from the target directory, not the session cwd.

## Capabilities

### New Capabilities
(none.)

### Modified Capabilities
- `jj-safety-hooks`: the guard requirement gains jj-repo gating (fail open outside a jj repo) and cwd-aware repo detection.

## Impact

- `plugins/jj-concurrent/hooks/scripts/jj-guard.sh` only. No behaviour change inside a jj repo (raw mutating git, interactive jj, and `rm` on the store remain blocked); the change is that the guard now stays silent outside jj repos and reads the right directory.
- Known residual limits (documented, accepted): the guard matches git/jj *mentions* in a command string, and `git -C <dir> <verb>` slips past — the worker contract remains the primary enforcement line.
