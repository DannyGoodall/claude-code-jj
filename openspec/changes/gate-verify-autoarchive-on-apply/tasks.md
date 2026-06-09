## 1. Verify gate in the implementing reconcile tail (jj-openspec-binding)

- [ ] 1.1 In the `jj-openspec` skill, after the orchestrator integrates all worker commits into the one reconciled change branch, add a step that runs `/opsx:verify <change>` once over that reconciled branch in the primary workspace
- [ ] 1.2 Branch the reconcile tail on the verify result: an unambiguous green proceeds; any failure or inconclusive result stops the tail before trunk-advance/PR
- [ ] 1.3 Make trunk-advance, `jj git push`, and PR creation CONDITIONAL on the green branch only — remove the unconditional "verify then push/PR" path
- [ ] 1.4 On non-green, hold the integrated change un-pushed (no trunk mutation, no ref mutation) and surface the verify failure as orchestrator data (which scenarios/tasks failed)

## 2. Auto-archive on green (jj-openspec-binding)

- [ ] 2.1 On the green branch, before push/PR, run `/opsx:archive <change>` in the primary workspace so delta specs sync into `openspec/specs/` and the change moves to `openspec/changes/archive/`
- [ ] 2.2 Capture the archive's canonical-spec sync + change-directory move on the SAME reconciled change branch that advances to trunk / the PR
- [ ] 2.3 Resolve any archive delta-sync conflict against canonical specs by editing conflict markers (never interactive `jj resolve`), per the existing integration contract
- [ ] 2.4 Ensure the verify gate and the auto-archive step each run exactly once over the reconciled branch, independent of single-worker vs fan-out distribution

## 3. Role-split and shape boundaries

- [ ] 3.1 Keep verify, archive, conditional trunk-advance, and push/PR entirely in the orchestrator (primary workspace); confirm the `jj-workspace-worker` contract is unchanged (workers never verify/archive/push)
- [ ] 3.2 Confirm the authoring shapes (`propose`/`new`/`ff`) and `explore` are untouched: no verify gate, no auto-archive, still validate-and-surface / run inline

## 4. Docs and validation

- [ ] 4.1 Update the `jj-openspec` skill docs to describe the verify GATE (green ⇒ archive then push/PR; non-green ⇒ stop and report) and the auto-archive-on-green step
- [ ] 4.2 Add a worked example in the binding docs showing a green apply that archives + opens a PR, and a failing apply that holds the change un-pushed with a reported reason
- [ ] 4.3 Run `openspec validate gate-verify-autoarchive-on-apply` and confirm the spec deltas are well-formed
