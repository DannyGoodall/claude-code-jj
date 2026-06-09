## Why

`/jj-openspec apply` today targets exactly ONE change at a time, so a backlog of several independent, ready-to-implement OpenSpec changes is landed serially even though they touch disjoint file areas and have no ordering relationship. jj is the only substrate that can safely run several writers against one repository at once (physical per-workspace isolation, lock-free ops, first-class conflicts on integration), so the apply binding should be able to take a SET of changes and land them as concurrent siblings — the across-changes axis of concurrency — and then integrate them either as independent landings or stitched into one stack.

## What Changes

- Add a **multi-change pipeline** entry to the apply binding: `/jj-openspec apply` (or a `pipeline` form) accepts a **set of change names** instead of one, and dispatches one apply-shape worker per change as a concurrent sibling — one jj workspace per change, each based on that change's own proposal revision.
- Define **how the change set is supplied**: an explicit list of change names, OR a selector (glob/query over `openspec/changes/` and OpenSpec status) that resolves to a concrete, deduplicated change set the orchestrator confirms before dispatch.
- Define **integration ordering / stacking**: each change is integrated by its own apply tail; the pipeline decides between **independent landings** (each change onto trunk, no inter-change order) and a **stitched stack** (changes layered in a chosen order onto one another), with stacking order derived from declared inter-change dependencies (default: independent when no dependency is stated).
- Define **per-change verify/reconcile tails plus a pipeline-level reconcile**: every change runs the existing apply-shape verify tail over its own reconciled result; the pipeline adds a thin reconciliation layer that orders the landings/stack and surfaces a single summary, never collapsing two changes' verify results into one.
- Add a **pre-dispatch disjointness/safety gate and fallback**: the pipeline confirms the change set members are distinct and ready; on a non-conforming set (overlapping change targeting the same change, unready change, single change) it falls back to the existing single-change apply with no behaviour change.
- The existing single-change `/jj-openspec apply <change>` contract is **preserved unchanged** as the default and the fallback path — multi-change is purely additive.

## Capabilities

### New Capabilities
- `jj-openspec-pipeline`: across-changes concurrent apply of a SET of independent OpenSpec changes — change-set supply (explicit list or selector), one apply-shape sibling worker per change on each change's proposal revision via `jj-delegate`, integration ordering/stacking policy (independent landings vs stitched stack from inter-change dependencies), per-change verify tails plus a pipeline-level reconcile/summary, and the single-change fallback.

### Modified Capabilities
- `jj-openspec-binding`: the binding gains a multi-change/pipeline entry. Its `apply` → implementing shape requirements change so the binding MAY accept a change SET and map it to N apply-shape concurrent-sibling workers (one per change) before per-change verify and pipeline reconcile, while still defaulting to (and falling back to) the single-change apply.

## Impact

- Affects the `jj-concurrent-openspec` plugin (`jj-openspec` skill) only; layers over the unchanged `jj-delegate` concurrent-sibling mechanism and the constrained `jj-workspace-worker`.
- Depends on `jj-delegate`'s existing concurrent fan-out, explicit base-revision provisioning, and never-halting integration — adds no new jj/workspace primitives, only an OpenSpec-aware change-set decomposition, ordering/stacking, and reconcile policy on top.
- Orthogonal to and composable with `openspec-apply-fan-out` (the within-a-change per-task-group axis): pipeline operates across changes, fan-out operates within one change; a pipeline member MAY itself fan out internally with no coupling between the two policies.
- No changes to any target project's application code; the opsx skills (`/opsx:apply`) are invoked per change exactly as today.
