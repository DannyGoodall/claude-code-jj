## MODIFIED Requirements

### Requirement: OpenSpec verb maps to a shape

The `jj-openspec` skill SHALL accept an OpenSpec verb and map it to a **shape** that determines the worker's workload and the reconcile tail: `apply` → implementing (integrate → verify → push/PR); `propose`/`new`/`ff` → authoring (validate + surface artifacts for review; bookmark only, no verify, no merge); `explore` → interactive (run inline, not a default background candidate); `relay` → **composite**: the authoring shape, then a mandatory human go/no-go gate, then — only on go — the implementing shape seeded from the approved proposal revision. The `relay` verb SHALL NOT introduce a new shape of its own; it SHALL compose the existing authoring and implementing shapes unchanged, owning only their ordering and the gate between them.

#### Scenario: apply runs the implementing shape

- **WHEN** `/jj-openspec apply <change>` is invoked
- **THEN** a worker runs `/opsx:apply <change>` in a workspace and the reconcile tail verifies, integrates, and pushes/opens a PR

#### Scenario: propose runs the authoring shape

- **WHEN** `/jj-openspec propose <idea>` is invoked
- **THEN** a worker runs `/opsx:propose` to draft the change artifacts and the reconcile tail validates and surfaces them without merging

#### Scenario: relay runs authoring then implementing with a gate between

- **WHEN** `/jj-openspec relay <idea>` is invoked
- **THEN** the binding first runs the authoring shape to draft the change artifacts
- **AND** then halts at a human go/no-go gate before running anything further
- **AND** on go it runs the implementing shape against the drafted change, with no change to either shape's own behaviour

## ADDED Requirements

### Requirement: Relay flow composes authoring and implementing with a human gate

The `relay` verb SHALL drive a two-leg flow with an explicit human decision point between the legs. The **first leg** SHALL dispatch the authoring shape exactly as `/jj-openspec propose` does — drafting the change artifacts on the worker's own revision and surfacing them for review, with no verify and no merge. After the authoring leg reports, the binding SHALL **halt and surface the drafted artifacts for an explicit human go/no-go** and SHALL NOT auto-advance to the implementing leg. On a **go**, the binding SHALL dispatch the **second leg** (the implementing shape) against the drafted change. On a **no-go**, the binding SHALL end the relay with the proposal revision left intact for the human to revise or discard, and SHALL dispatch no implementing leg.

The relay SHALL own only the composition (which leg runs when) and the gate (the pause between legs). It SHALL introduce no new jj or workspace choreography (that remains `jj-delegate`'s) and no new OpenSpec artifact rules (those remain the opsx skills').

#### Scenario: Gate halts before implementing and requires explicit go

- **WHEN** the authoring leg of a relay has reported its drafted artifacts
- **THEN** the binding halts and surfaces those artifacts for a human go/no-go decision
- **AND** does not dispatch the implementing leg until an explicit go is given

#### Scenario: Go advances to the implementing leg

- **WHEN** the human gives a go at the relay gate
- **THEN** the binding dispatches the implementing shape against the drafted change

#### Scenario: No-go ends the relay with the proposal intact

- **WHEN** the human gives a no-go at the relay gate
- **THEN** the binding dispatches no implementing leg
- **AND** the proposal revision is left intact for the human to revise or discard

### Requirement: Relay implementing leg is seeded from the approved proposal revision

The implementing leg dispatched on a relay **go** SHALL be based on the revision that carries the approved proposal artifacts, following the binding's existing apply-worker-base rule: the worker's workspace SHALL start from that proposal revision (seed-intent) so the drafted artifacts are present, with **no seed commit**. The relay SHALL reuse this existing provisioning rule rather than introducing a separate seeding mechanism, and SHALL resolve the proposal revision from the authoring leg's reported result rather than requiring the human to re-supply it.

#### Scenario: Implementing leg starts from the proposal revision

- **WHEN** the relay advances to the implementing leg on a go
- **THEN** the implementing worker's workspace is based on the revision carrying the approved proposal artifacts
- **AND** those artifacts are present in the worker's workspace with no separate seed commit

#### Scenario: Relay carries the proposal revision through the gate

- **WHEN** the authoring leg reports the revision it drafted the artifacts on
- **THEN** the binding uses that reported revision as the implementing leg's base
- **AND** does not require the human to re-supply the change name or revision at the gate

### Requirement: Non-relay verbs are unaffected by the relay flow

Adding the `relay` verb SHALL NOT change the behaviour of any existing verb. `/jj-openspec propose`, `new`, `ff`, `apply`, and `explore` SHALL each continue to run their single mapped shape exactly as before, with no gate and no composition. The `relay` verb SHALL be an additional trigger, not a modification of the existing single-shape triggers.

#### Scenario: Single-shape verbs run with no gate

- **WHEN** any of `propose`, `new`, `ff`, `apply`, or `explore` is invoked
- **THEN** the binding runs that verb's single mapped shape exactly as before
- **AND** introduces no go/no-go gate and no second leg
