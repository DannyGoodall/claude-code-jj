## Why

Running many Claude Code agents on many changes at once needs an isolation substrate that does not let concurrent agents clobber each other's files, does not lose work to a crash, and does not stall integration on the first conflict. GitButler's shared working tree races concurrent writers; git worktrees carry restack-while-checked-out hazards. **Jujutsu (jj) workspaces** give physical per-agent isolation, automatic working-copy snapshots, lock-free operations, and first-class conflicts — exactly the properties autonomous concurrency needs. This change builds the plugin that turns those properties into an orchestrator/worker workflow for Claude Code.

## What Changes

- A workflow-agnostic **orchestration mechanism** (`jj-delegate` skill): resolve a workload → provision a jj workspace → dispatch a worker subagent (background by default) → integrate the result, with integration that never halts.
- A constrained **worker agent** (`jj-workspace-worker`): works in exactly one jj workspace, jj-only (never raw mutating git, never bookmarks/push), non-interactive, with a structured JSON report.
- Two **safety hooks**: a PostToolUse **snapshot hook** (`jj util snapshot` after every edit, closing jj's crash-before-snapshot gap) and a PreToolUse **guard hook** (blocks raw mutating git, interactive jj, and `rm` on the `.jj`/`.git` stores).
- An **OpenSpec binding** (`jj-openspec` skill, separate plugin) that backgrounds an OpenSpec verb (`apply`/`propose`/`new`/`ff`) on a jj workspace, mapping verb → shape → reconcile tail.
- Depends on the read-only `jj-vcs@toolbox` plugin (unmodified) for the worker's jj command vocabulary.

## Capabilities

### New Capabilities
- `jj-delegate`: the orchestrator/worker lifecycle on jj workspaces — provision, dispatch, integrate, teardown; roles, base-revision (seed-intent) selection, concurrent fan-out, failure handling.
- `jj-workspace-worker`: the constrained worker subagent's contract — workspace containment, jj-only VCS, commit shaping, command hygiene, JSON report.
- `jj-safety-hooks`: the snapshot hook (crash-gap closure) and the guard hook (blocks the operations that corrupt jj state or hang an agent).
- `jj-openspec-binding`: the OpenSpec verb → shape mapping and reconcile tails layered over `jj-delegate`.

### Modified Capabilities
(none — first build.)

## Impact

- New marketplace `claude-code-jj` with two plugins: `jj-concurrent` (core) and `jj-concurrent-openspec` (binding).
- Soft dependency on `jj-vcs@toolbox` and on a jj repository (ideally colocated with git for PRs).
- No changes to any target project's code — the plugin orchestrates agents, it does not ship application behaviour.
