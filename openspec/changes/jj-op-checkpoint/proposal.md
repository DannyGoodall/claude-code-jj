## Why

jj's operation log (`jj op log` / `jj op restore`) is a whole-repo undo history — already named in the `jj-delegate` skill as the orchestrator's recovery surface — but today it is reached only ad hoc, after something has already gone wrong, by hand-reading raw op ids. Before a deliberately risky orchestration step (a fan-out integration that rebases several workers' changes, a big history rewrite), the orchestrator has no labelled "save point" to roll back to, so recovery means scanning the op log under pressure and guessing which op predates the damage.

## What Changes

- A new orchestrator skill **`/jj-checkpoint <label>`** that, before a risky step, records a **named checkpoint** capturing the repo's current operation id (resolved via `jj op log`) under a human-supplied label, persisted in the agent-plan manifest the orchestrator already owns.
- A companion orchestrator skill **`/jj-rewind [label]`** that restores the repo to a checkpoint's captured op via `jj op restore <op-id>`, after printing a **confirmation summary** of what the restore will change (the ops that will be undone, and the workspaces/bookmarks affected). With no label it targets the most recent checkpoint; with a label it targets that named checkpoint.
- Both skills are **orchestrator-only** and operate on the operation log of the whole repo. They use `jj op log` and `jj op restore` exclusively and **never delete `.jj`** (or any repo metadata).
- **Reconcile-lifecycle wiring**: the `jj-delegate` reconcile/integration prose gains an optional checkpoint-before / rewind-on-regret beat — checkpoint immediately before §5 fan-out integration or a big rebase, rewind if that step goes wrong — replacing the current "scan the op log by hand" recovery note with a labelled workflow.

## Capabilities

### New Capabilities
- `jj-op-checkpoint`: the `/jj-checkpoint` and `/jj-rewind` orchestrator skills — record a labelled checkpoint capturing the current op id before a risky step, list/resolve checkpoints, and restore the repo to a checkpoint via `jj op restore` with a pre-restore confirmation summary; the orchestrator-owned, op-log-based safety net for fan-out integration and large rebases.

### Modified Capabilities
<!-- None. jj-delegate already names jj op log/op restore as its recovery surface; this change supplies the concrete labelled skill its reconcile lifecycle points at, without changing jj-delegate's existing requirements. The reference is one-directional (this capability points at the lifecycle), so no delta spec is required. -->

## Impact

- New skills `plugins/jj-concurrent/skills/jj-checkpoint/SKILL.md` and `plugins/jj-concurrent/skills/jj-rewind/SKILL.md` in the core `jj-concurrent` plugin; bumps that plugin's version and extends its description to mention the checkpoint/rewind safety net.
- Checkpoint records are persisted alongside the existing orchestrator agent-plan manifest (label → op id → timestamp → note); no new external store.
- Reconcile-lifecycle prose in the `jj-delegate` skill references `/jj-checkpoint` and `/jj-rewind` as the before/after-a-risky-step beats (documentation/wiring only — no behaviour change to jj-delegate's spec).
- Hard dependency only on jj's operation log (present in every jj repo); no `gh`, no remote, no application-code change in any target project. Operates entirely on local repo history.
