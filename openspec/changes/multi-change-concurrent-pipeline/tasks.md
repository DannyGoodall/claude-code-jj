## 1. Change-set supply and resolution (jj-openspec-pipeline)

- [ ] 1.1 In the `jj-openspec` skill, add a step that accepts the apply target as either an explicit list of change names or a selector (glob/query over `openspec/changes/` plus OpenSpec status)
- [ ] 1.2 Resolve a selector to a de-duplicated list of existing change names
- [ ] 1.3 Filter the resolved list to apply-ready changes (their `applyRequires` artifacts complete); exclude non-existent/unready members with an explicit note
- [ ] 1.4 Confirm the concrete resolved change set (and its fan-out width) before any worker is dispatched

## 2. Per-change dispatch policy (jj-openspec-binding apply shape)

- [ ] 2.1 Extend the `apply` → implementing shape to detect a change SET vs a single change and choose pipeline vs single-change distribution
- [ ] 2.2 For the pipeline, build one apply-shape workload per change: `/opsx:apply <change>` for that single change only
- [ ] 2.3 Resolve EACH change's parameters (its own proposal revision, bookmark naming) and hand each workload to `jj-delegate` as a concurrent sibling based on that change's proposal revision
- [ ] 2.4 Preserve the existing single-change hand-off unchanged for the fallback path

## 3. Integration ordering and stacking (jj-openspec-pipeline)

- [ ] 3.1 Default to independent landings: integrate each completed change onto trunk with no inter-change ordering
- [ ] 3.2 When inter-change dependencies are declared within the set, compute a topological order and integrate the changes as a stitched stack in that order
- [ ] 3.3 Abort stacking with an explicit error on a declared-dependency cycle (never choose an arbitrary order)
- [ ] 3.4 On overlapping integration, rely on never-halting jj integration: resolve the first-class conflict by editing markers (never interactive `jj resolve`) before the affected change's verify tail runs

## 4. Per-change verify tails and pipeline reconcile (jj-openspec-pipeline)

- [ ] 4.1 Run each change's existing apply-shape verify tail over ITS OWN reconciled result; never run one change's verify over another's
- [ ] 4.2 Add a thin pipeline reconcile layer that orders the landings/stack after each member's verify
- [ ] 4.3 Emit a single pipeline-level summary listing each change as landed / stacked / conflicted / failed
- [ ] 4.4 Ensure a failed/blocked member does not block independent members; leave its workspace intact for inspection and report it in the summary

## 5. Fallback, docs, and validation

- [ ] 5.1 Wire the single-change fallback for every sub-threshold case (single change, empty set after exclusions, only duplicates/overlaps)
- [ ] 5.2 Update the `jj-openspec` skill docs to describe the pipeline entry, change-set supply, ordering/stacking policy, per-change verify + pipeline reconcile, and the fallback guarantee
- [ ] 5.3 Add a worked example showing a set of independent changes landed concurrently, plus one showing a declared-dependency stitched stack
- [ ] 5.4 Note the orthogonality with `openspec-apply-fan-out` (across-changes vs within-a-change) in the binding docs
- [ ] 5.5 Run `openspec validate multi-change-concurrent-pipeline` and confirm the spec deltas are well-formed
