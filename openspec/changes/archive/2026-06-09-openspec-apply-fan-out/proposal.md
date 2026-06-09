## Why

`/jj-openspec apply` today runs a single worker for an entire change, even when that change's `tasks.md` is structured as several task groups that touch disjoint file areas — so independent work is serialized behind one agent and one workspace. jj is the only substrate that can safely fan a single logical change across several concurrent writers (physical per-workspace isolation, lock-free ops, first-class conflicts on integration), so the apply binding should exploit that to run separable task groups in parallel and then reconcile them into one change branch. Worktrees (restack-while-checked-out hazards) and GitButler (shared working tree races) cannot do this safely.

## What Changes

- Add a **fan-out mode** to the apply shape of `/jj-openspec apply`: when a change's `tasks.md` decomposes into task groups that touch **disjoint file areas**, the orchestrator splits the apply across SEVERAL concurrent workers — one jj workspace per separable group — instead of one worker for the whole change.
- Add **separability detection**: the binding analyses `tasks.md` task groups and their declared/derived file areas to decide which groups are separable (disjoint) and which must stay together (overlapping or ordering-dependent).
- Add **per-group dispatch**: each worker is scoped to exactly its group's tasks (it implements only those tasks, marks only those checkboxes) on its own workspace, dispatched as a concurrent sibling via `jj-delegate`.
- Add **reconcile-into-one-change integration**: the orchestrator integrates every group worker's commits back into a SINGLE change branch (stack/merge the sibling changes), relying on jj integration that never halts; overlapping integrations surface as first-class conflicts the orchestrator resolves deliberately.
- Add **single-worker fallback**: when groups are not separable (overlapping areas, too few groups, ordering dependencies, or detection is unsure), apply runs exactly as today — one worker for the whole change. Fan-out is an optimization, never a correctness requirement.
- The existing single-worker `apply` behaviour is preserved as the default/fallback path — **no breaking change** to the current `/jj-openspec apply <change>` contract.

## Capabilities

### New Capabilities
- `jj-openspec-fanout`: per-task-group concurrent fan-out of a single OpenSpec apply — separability detection over `tasks.md`, one-workspace-per-group provisioning, group-scoped concurrent worker dispatch, reconcile-into-one-change integration, and the single-worker fallback rule.

### Modified Capabilities
- `jj-openspec-binding`: the `apply` → implementing shape gains an optional fan-out path. Its requirements change so that the apply shape MAY split into per-group concurrent workers when separable, while still defaulting to (and falling back to) the single-worker apply, and its reconcile tail integrates either one worker or several group workers into one change branch before verify/push.

## Impact

- Affects the `jj-concurrent-openspec` plugin (`jj-openspec` skill) only; layers over the unchanged `jj-delegate` concurrent-sibling mechanism and the constrained `jj-workspace-worker`.
- Depends on `jj-delegate`'s existing concurrent fan-out, base-revision provisioning, and never-halting integration — adds no new jj/workspace primitives, only an OpenSpec-aware decomposition and reconcile policy on top.
- No changes to any target project's application code; the opsx skills (`/opsx:apply`) are invoked per group exactly as before, scoped to a task subset.
- Requires a change whose `tasks.md` is group-structured to benefit; ungrouped or interdependent changes transparently use the existing single-worker path.
