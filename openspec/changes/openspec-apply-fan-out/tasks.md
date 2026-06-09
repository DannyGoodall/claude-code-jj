## 1. Separability detection (jj-openspec-fanout)

- [x] 1.1 In the `jj-openspec` skill, add a step that partitions the target change's `tasks.md` into task groups by its `##` heading / numbering structure
- [x] 1.2 Derive each group's file area from the paths its tasks reference (explicit file/dir mentions plus the spec deltas the group implements); record undeterminable areas as such
- [x] 1.3 Implement the separability test: two groups are separable only when their file areas are disjoint AND no stated cross-group ordering dependency exists; undeterminable area ⇒ non-separable
- [x] 1.4 Compute the separable-group set and the minimum-benefit gate (≥2 separable groups of non-trivial size); below the gate, mark the change for single-worker

## 2. Per-group dispatch policy (jj-openspec-binding apply shape)

- [x] 2.1 Extend the `apply` → implementing shape to choose a distribution: single-worker (default/fallback) or per-group fan-out when the separable-group set qualifies
- [x] 2.2 For fan-out, build one group-scoped workload string per separable group: `/opsx:apply <change>` instructed to implement ONLY group N's tasks and mark ONLY group N's checkboxes
- [x] 2.3 Hand each group-scoped workload to `jj-delegate` as a concurrent sibling, each based on the change's proposal revision; rely on `jj-delegate` for all provisioning/dispatch choreography
- [x] 2.4 Preserve the existing single-worker hand-off unchanged for the fallback path

## 3. Reconcile-into-one-change integration (jj-openspec-fanout)

- [x] 3.1 Integrate each group worker's commits into ONE change branch for the change as they report (stack/merge siblings), not separate branches
- [x] 3.2 On overlapping content, rely on never-halting jj integration: resolve the first-class conflict by editing markers (never interactive `jj resolve`) before proceeding
- [x] 3.3 Ensure `tasks.md` checkbox hunks from different groups reconcile cleanly (disjoint lines); resolve any true overlap deliberately
- [x] 3.4 Run the apply shape's verify → push/PR tail exactly once over the reconciled change branch

## 4. Fallback, docs, and validation

- [x] 4.1 Wire the single-worker fallback for every non-fan-out case (one group, overlapping areas, ordering dependency, undeterminable area, ungrouped `tasks.md`)
- [x] 4.2 Update the `jj-openspec` skill docs to describe the fan-out path, the separability rule, and the fallback guarantee (identical end result)
- [x] 4.3 Add a worked example in the binding docs showing a change with two disjoint groups fanned out and reconciled into one branch
- [x] 4.4 Run `openspec validate openspec-apply-fan-out` and confirm the spec deltas are well-formed
