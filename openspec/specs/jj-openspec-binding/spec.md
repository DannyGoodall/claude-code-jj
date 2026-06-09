# jj-openspec-binding Specification

## Purpose
TBD - created by archiving change jj-concurrent-plugin. Update Purpose after archive.
## Requirements
### Requirement: OpenSpec verb maps to a shape

The `jj-openspec` skill SHALL accept an OpenSpec verb and map it to a **shape** that determines the worker's workload and the reconcile tail: `apply` → implementing (integrate → verify → push/PR); `propose`/`new`/`ff` → authoring (validate + surface artifacts for review; bookmark only, no verify, no merge); `explore` → interactive (run inline, not a default background candidate). The implementing (`apply`) shape SHALL support two distributions: a **single-worker** distribution (one worker for the whole change) and an optional **per-group fan-out** distribution (one concurrent worker per separable `tasks.md` group, reconciled into one change branch) as defined by the `jj-openspec-fanout` capability. The shape SHALL default to and fall back to single-worker; fan-out SHALL NOT alter the implementing shape's verify → push/PR tail, which runs once over the reconciled change.

#### Scenario: apply runs the implementing shape

- **WHEN** `/jj-openspec apply <change>` is invoked
- **THEN** a worker runs `/opsx:apply <change>` in a workspace and the reconcile tail verifies, integrates, and pushes/opens a PR

#### Scenario: propose runs the authoring shape

- **WHEN** `/jj-openspec propose <idea>` is invoked
- **THEN** a worker runs `/opsx:propose` to draft the change artifacts and the reconcile tail validates and surfaces them without merging

#### Scenario: apply fans out across separable groups

- **WHEN** `/jj-openspec apply <change>` is invoked for a change whose `tasks.md` has two or more separable task groups
- **THEN** the implementing shape dispatches one concurrent worker per separable group, reconciles them into one change branch, and runs verify → push/PR once over the combined result

#### Scenario: apply falls back to single-worker

- **WHEN** `/jj-openspec apply <change>` is invoked for a change with no separable groups
- **THEN** the implementing shape runs a single worker for the whole change as before

### Requirement: Binding layers over the generic mechanism

The `jj-openspec` skill SHALL resolve OpenSpec-specific parameters (change name, bookmark naming, base revision, and — for the `apply` shape — task-group decomposition and separability per the `jj-openspec-fanout` capability) and then hand off to the `jj-delegate` mechanism with the OpenSpec verb invocation as the workload, dispatching one workload for the single-worker distribution or several group-scoped workloads as concurrent siblings for the fan-out distribution. It SHALL own no jj/workspace choreography (that is `jj-delegate`'s) and no OpenSpec artifact rules (those are the opsx skills'); the binding owns only the verb → shape → distribution → reconcile-policy mapping.

#### Scenario: Apply worker is based on the proposal revision

- **WHEN** applying a change whose artifacts live on a known revision
- **THEN** the apply worker's workspace is based on that revision so the artifacts are present, with no seed commit

#### Scenario: Fan-out group workers are concurrent siblings on the proposal revision

- **WHEN** the apply shape fans out across separable groups
- **THEN** the binding hands `jj-delegate` one group-scoped workload per group as concurrent siblings, each based on the change's proposal revision
- **AND** the binding delegates all provisioning, dispatch, and integration choreography to `jj-delegate`

### Requirement: Separately enabled for OpenSpec repos only

The binding SHALL ship as a distinct plugin (`jj-concurrent-openspec`) requiring the `jj-concurrent` plugin and the opsx skills, so non-OpenSpec repositories never surface its triggers.

#### Scenario: Binding absent in a non-OpenSpec repo

- **WHEN** the core plugin is enabled but the binding plugin is not
- **THEN** `/jj-openspec` is unavailable and only the generic `/jj-delegate` mechanism is present

