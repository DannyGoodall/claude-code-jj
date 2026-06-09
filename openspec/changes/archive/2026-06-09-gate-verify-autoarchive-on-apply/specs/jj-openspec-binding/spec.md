## MODIFIED Requirements

### Requirement: OpenSpec verb maps to a shape

The `jj-openspec` skill SHALL accept an OpenSpec verb and map it to a **shape** that determines the worker's workload and the reconcile tail: `apply` → implementing (integrate → **verify (GATE)** → on green: archive then push/PR, on non-green: stop before trunk-advance/PR and report); `propose`/`new`/`ff` → authoring (validate + surface artifacts for review; bookmark only, no verify, no merge); `explore` → interactive (run inline, not a default background candidate). For the implementing (`apply`) shape, `/opsx:verify` SHALL gate trunk-advance and PR: trunk-advance and PR run ONLY when verify passes, and a passing verify SHALL trigger an automatic `/opsx:archive <change>` (sync delta specs into canonical `openspec/specs/` and move the change to `openspec/changes/archive/`) before push/PR. The gate and the auto-archive-on-green step SHALL run exactly once over the fully reconciled change branch.

#### Scenario: apply runs the implementing shape

- **WHEN** `/jj-openspec apply <change>` is invoked
- **THEN** a worker runs `/opsx:apply <change>` in a workspace and the reconcile tail integrates the worker's change, then runs `/opsx:verify <change>` as a gate over the reconciled change

#### Scenario: green verify advances trunk, archives, and opens a PR

- **WHEN** the implementing reconcile tail runs `/opsx:verify <change>` over the reconciled change and verify passes
- **THEN** the orchestrator runs `/opsx:archive <change>` (sync delta specs → canonical, move the change to `archive/`) and then advances trunk / opens a PR over the lifecycle-complete result
- **AND** the verify gate and the auto-archive step each run exactly once over the reconciled change branch

#### Scenario: non-green verify stops before trunk-advance and PR

- **WHEN** the implementing reconcile tail runs `/opsx:verify <change>` over the reconciled change and verify fails or is inconclusive
- **THEN** the orchestrator performs no trunk-advance, no push, and opens no PR, holds the integrated change un-pushed, and reports the verify failure as data
- **AND** no `/opsx:archive` is run

#### Scenario: propose runs the authoring shape

- **WHEN** `/jj-openspec propose <idea>` is invoked
- **THEN** a worker runs `/opsx:propose` to draft the change artifacts and the reconcile tail validates and surfaces them without merging, without running verify, and without archiving

### Requirement: Binding layers over the generic mechanism

The `jj-openspec` skill SHALL resolve OpenSpec-specific parameters (change name, bookmark naming, base revision) and then hand off to the `jj-delegate` mechanism with the OpenSpec verb invocation as the workload. It SHALL own no jj/workspace choreography (that is `jj-delegate`'s) and no OpenSpec artifact rules (those are the opsx skills'); the binding owns only the verb → shape → reconcile-policy mapping, including — for the `apply` shape — the verify GATE on trunk-advance/PR and the auto-archive-on-green step, both of which it directs the orchestrator to run in the primary workspace (workers never verify, archive, or push).

#### Scenario: Apply worker is based on the proposal revision

- **WHEN** applying a change whose artifacts live on a known revision
- **THEN** the apply worker's workspace is based on that revision so the artifacts are present, with no seed commit

#### Scenario: Verify gate and auto-archive run in the orchestrator, not the worker

- **WHEN** the implementing reconcile tail reaches the verify gate for a reconciled change
- **THEN** the orchestrator (primary workspace) runs `/opsx:verify`, decides trunk-advance/PR on its result, and on green runs `/opsx:archive` and the conditional push/PR
- **AND** the worker performs none of verify, archive, trunk-advance, or push
