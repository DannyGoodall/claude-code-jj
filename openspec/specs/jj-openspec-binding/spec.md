# jj-openspec-binding Specification

## Purpose
TBD - created by archiving change jj-concurrent-plugin. Update Purpose after archive.
## Requirements
### Requirement: OpenSpec verb maps to a shape

The `jj-openspec` skill SHALL accept an OpenSpec verb and map it to a **shape** that determines the worker's workload and the reconcile tail: `apply` → implementing (integrate → verify → push/PR); `propose`/`new`/`ff` → authoring (validate + surface artifacts for review; bookmark only, no verify, no merge); `explore` → interactive (run inline, not a default background candidate).

#### Scenario: apply runs the implementing shape

- **WHEN** `/jj-openspec apply <change>` is invoked
- **THEN** a worker runs `/opsx:apply <change>` in a workspace and the reconcile tail verifies, integrates, and pushes/opens a PR

#### Scenario: propose runs the authoring shape

- **WHEN** `/jj-openspec propose <idea>` is invoked
- **THEN** a worker runs `/opsx:propose` to draft the change artifacts and the reconcile tail validates and surfaces them without merging

### Requirement: Binding layers over the generic mechanism

The `jj-openspec` skill SHALL resolve OpenSpec-specific parameters (change name, bookmark naming, base revision) and then hand off to the `jj-delegate` mechanism with the OpenSpec verb invocation as the workload. It SHALL own no jj/workspace choreography (that is `jj-delegate`'s) and no OpenSpec artifact rules (those are the opsx skills').

#### Scenario: Apply worker is based on the proposal revision

- **WHEN** applying a change whose artifacts live on a known revision
- **THEN** the apply worker's workspace is based on that revision so the artifacts are present, with no seed commit

### Requirement: Separately enabled for OpenSpec repos only

The binding SHALL ship as a distinct plugin (`jj-concurrent-openspec`) requiring the `jj-concurrent` plugin and the opsx skills, so non-OpenSpec repositories never surface its triggers.

#### Scenario: Binding absent in a non-OpenSpec repo

- **WHEN** the core plugin is enabled but the binding plugin is not
- **THEN** `/jj-openspec` is unavailable and only the generic `/jj-delegate` mechanism is present

