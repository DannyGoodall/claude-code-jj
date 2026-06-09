## MODIFIED Requirements

### Requirement: OpenSpec verb maps to a shape

The `jj-openspec` skill SHALL accept an OpenSpec verb and map it to a **shape** that determines the worker's workload and the reconcile tail: `apply` → implementing (integrate → verify → push/PR); `propose`/`new`/`ff` → authoring (validate + surface artifacts for review; bookmark only, no verify, no merge); `explore` → interactive (run inline, not a default background candidate). The `apply` verb MAY be supplied a **set of changes** (an explicit list or a selector) rather than a single change; when so supplied with two or more distinct apply-ready changes, the binding SHALL map the set to the `jj-openspec-pipeline` capability — one apply-shape concurrent-sibling worker per change, each on its own change's proposal revision — then run each change's verify tail and a pipeline-level reconcile. With a single change (or a set that reduces to one), `apply` SHALL behave exactly as the single-change implementing shape.

#### Scenario: apply runs the implementing shape

- **WHEN** `/jj-openspec apply <change>` is invoked
- **THEN** a worker runs `/opsx:apply <change>` in a workspace and the reconcile tail verifies, integrates, and pushes/opens a PR

#### Scenario: propose runs the authoring shape

- **WHEN** `/jj-openspec propose <idea>` is invoked
- **THEN** a worker runs `/opsx:propose` to draft the change artifacts and the reconcile tail validates and surfaces them without merging

#### Scenario: apply over a change set runs the pipeline

- **WHEN** `/jj-openspec apply` is invoked with a set of two or more distinct apply-ready changes
- **THEN** the binding maps the set to the `jj-openspec-pipeline` capability, dispatching one apply-shape concurrent-sibling worker per change on each change's proposal revision
- **AND** each change runs its own verify tail and the pipeline produces one reconcile summary

#### Scenario: apply over a one-change set falls back

- **WHEN** `/jj-openspec apply` is invoked with a set that reduces to a single apply-ready change
- **THEN** apply behaves exactly as the single-change implementing shape with no pipeline overhead

### Requirement: Binding layers over the generic mechanism

The `jj-openspec` skill SHALL resolve OpenSpec-specific parameters (change name, bookmark naming, base revision) and then hand off to the `jj-delegate` mechanism with the OpenSpec verb invocation as the workload. For a change set, it SHALL resolve EACH change's parameters (its own proposal revision and bookmark naming) and hand off one workload per change as concurrent siblings. It SHALL own no jj/workspace choreography (that is `jj-delegate`'s) and no OpenSpec artifact rules (those are the opsx skills').

#### Scenario: Apply worker is based on the proposal revision

- **WHEN** applying a change whose artifacts live on a known revision
- **THEN** the apply worker's workspace is based on that revision so the artifacts are present, with no seed commit

#### Scenario: Each pipeline worker is based on its own change's proposal revision

- **WHEN** applying a set of changes whose artifacts live on distinct revisions
- **THEN** each change's apply worker is based on that change's own proposal revision so its artifacts are present, with no seed commit
