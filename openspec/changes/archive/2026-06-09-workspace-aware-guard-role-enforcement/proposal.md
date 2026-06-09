## Why

The orchestrator/worker role split (`jj-delegate`) is the safety model for colocated jj concurrency: only the orchestrator may touch bookmarks, refs, and `jj git push`; a worker owns only its own commits. Today that rule lives **only in the worker-agent contract prose** — nothing enforces it. A confused or hallucinating worker can run `jj bookmark set` or `jj git push` and corrupt the shared ref state the orchestrator owns, with no guard to stop it. The guard hook already runs on every Bash call and already cheaply detects jj-repo membership; it is the natural place to also enforce the role floor.

## What Changes

- Extend the `jj-guard.sh` PreToolUse hook to **detect its role** at the `.jj` directory the existing upward walk already finds: `.jj/repo` being a regular file means a linked workspace (**worker**); `.jj/repo` being a directory means the default workspace (**orchestrator**).
- When the role is **worker**, the guard SHALL **block** `jj bookmark …` and `jj git push` with explanatory messages directing the agent to leave ref/push operations to the orchestrator.
- When the role is **orchestrator** (or role is undetermined), these commands SHALL remain **allowed** — the orchestrator legitimately owns them, and undetermined detection must fail open to preserve the existing universal-floor behaviour.
- Detection MUST stay **cheap and hang-proof**: it uses only filesystem `test -f`/`test -d` on the already-located `.jj/repo`, never invokes jj, and fails open on any ambiguity.

No behaviour changes for the orchestrator and no change to the existing universal floor (raw mutating git, interactive jj, `rm` on the store) for either role.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `jj-safety-hooks`: Add a requirement that the guard hook detects its workspace role (default = orchestrator, linked = worker) via a cheap, hang-proof filesystem check and, when running as a worker, blocks `jj bookmark …` and `jj git push`. The existing universal-floor requirement is unchanged.

## Impact

- **Spec**: `openspec/specs/jj-safety-hooks` gains one new requirement (delta: ADDED).
- **Code (later, not this change)**: `plugins/jj-concurrent/hooks/scripts/jj-guard.sh` — role-detection block + two worker-only rules. The header comment that currently says role rules are "enforced by the worker-agent contract in v0.1.0, not here" becomes stale and will be updated at implementation time.
- **Roles referenced**: relies on the `jj-delegate` orchestrator/worker split for the semantics of which operations are orchestrator-only.
- **No runtime dependencies added**; detection is pure POSIX filesystem tests. No new jj invocation, so the guard's hang-proof guarantee is preserved.
