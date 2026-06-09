## ADDED Requirements

### Requirement: A change set is supplied explicitly or by selector

The pipeline SHALL accept the set of changes to apply as either an **explicit list of change names** or a **selector** (a glob/query over `openspec/changes/` and OpenSpec status). A selector SHALL be resolved to a concrete, de-duplicated list of existing change names before any dispatch. The resolved set SHALL contain only distinct changes that exist and are apply-ready (their `applyRequires` artifacts are complete); any member that does not exist or is not apply-ready SHALL be excluded with an explicit note, never silently dispatched.

#### Scenario: Explicit list is taken as the change set

- **WHEN** the pipeline is invoked with an explicit list `change-a change-b change-c`
- **THEN** the change set is exactly those three changes after confirming each exists and is apply-ready

#### Scenario: Selector resolves to a concrete set

- **WHEN** the pipeline is invoked with a selector (e.g. a glob over `openspec/changes/`)
- **THEN** the selector is resolved to a de-duplicated list of existing, apply-ready change names
- **AND** that resolved list is confirmed before any worker is dispatched

#### Scenario: Non-existent or unready member is excluded

- **WHEN** a supplied or selected change does not exist or is not apply-ready
- **THEN** that change is excluded from the dispatched set with an explicit note
- **AND** it is never dispatched to a worker

### Requirement: One apply-shape sibling worker per change

For each change in the resolved set, the orchestrator SHALL provision its own jj workspace via the `jj-delegate` mechanism (explicit base revision on THAT change's own proposal revision, dispatched as a concurrent sibling) and dispatch one `jj-workspace-worker` whose workload is `/opsx:apply <change>` for that single change. Each worker SHALL implement only its own change's tasks and touch only its own change's file area; no worker is scoped across changes.

#### Scenario: Each change gets an isolated concurrent worker

- **WHEN** the resolved set has three independent changes
- **THEN** three workspaces are provisioned as concurrent siblings, each based on its own change's proposal revision
- **AND** three workers run `/opsx:apply` concurrently, one per change

#### Scenario: A worker is confined to one change

- **WHEN** a worker is dispatched for change A
- **THEN** it runs `/opsx:apply A` and shapes commits only for change A
- **AND** it does not implement or mark tasks for any other change in the set

### Requirement: Integration ordering and stacking are decided per dependency

The pipeline SHALL decide integration mode between **independent landings** (each change integrated onto trunk with no inter-change ordering) and a **stitched stack** (changes layered onto one another in a chosen order). The default SHALL be independent landings. A **stitched stack** SHALL be produced only when inter-change dependencies are declared (a change depends on another in the set); in that case the stacking order SHALL be a topological order of the declared dependencies, and a dependency cycle SHALL abort stacking with an explicit error rather than produce an arbitrary order. Integration of each change SHALL rely on the never-halting jj integration: an overlapping integration produces a first-class conflict object the orchestrator resolves deliberately by editing markers, never the interactive `jj resolve`.

#### Scenario: Independent changes land independently

- **WHEN** the set has no declared inter-change dependencies
- **THEN** each completed change is integrated onto trunk independently
- **AND** no stacking order is imposed between them

#### Scenario: Declared dependencies produce a stitched stack

- **WHEN** change B declares a dependency on change A within the set
- **THEN** the changes are integrated as a stitched stack with A below B in topological order

#### Scenario: Dependency cycle aborts stacking

- **WHEN** the declared inter-change dependencies form a cycle
- **THEN** stacking is aborted with an explicit error
- **AND** no arbitrary order is chosen

#### Scenario: Overlapping integration surfaces a first-class conflict

- **WHEN** two changes unexpectedly touch the same lines during integration
- **THEN** the integration succeeds (exit 0) and the affected change is marked as a first-class conflict
- **AND** the orchestrator resolves it by editing markers before that change's verify tail runs

### Requirement: Per-change verify tails and a pipeline-level reconcile

Each change SHALL run the existing apply-shape verify tail over ITS OWN reconciled result; the pipeline SHALL NOT collapse two changes' verify results into one. The pipeline SHALL add a thin reconciliation layer that orders the landings/stack, runs after each member's own verify, and produces a single pipeline-level summary of every change's outcome (landed / stacked / conflicted / failed). A failing or blocked member SHALL NOT block the integration of the other independent members; its failure SHALL be reported in the summary and its workspace left intact for inspection.

#### Scenario: Each change verifies on its own result

- **WHEN** three changes complete
- **THEN** each change's apply-shape verify tail runs once over that change's own reconciled result
- **AND** no change's verify is run over another change's result

#### Scenario: Pipeline summarizes every member's outcome

- **WHEN** the pipeline finishes
- **THEN** it produces one summary listing each change as landed, stacked, conflicted, or failed

#### Scenario: One member's failure does not block independent members

- **WHEN** one independent change's worker reports a blocker
- **THEN** the other independent changes are still integrated and verified
- **AND** the failed change is reported in the summary with its workspace left intact

### Requirement: Single-change fallback for non-conforming sets

The pipeline SHALL be strictly an optimization across changes. When the resolved set contains fewer than two distinct apply-ready changes — including a single change, an empty set after exclusions, or only overlapping/duplicate members — the binding SHALL fall back to the existing single-change `/jj-openspec apply <change>` behaviour with no behaviour change. Choosing the pipeline SHALL NOT change any individual change's reconciled result relative to applying that change alone; it only changes that several changes are applied concurrently.

#### Scenario: Single change falls back

- **WHEN** the resolved set contains exactly one change
- **THEN** apply runs the existing single-change path for that change with no pipeline overhead

#### Scenario: Empty resolved set is a no-op with a note

- **WHEN** every supplied/selected change is excluded as non-existent or unready
- **THEN** the pipeline dispatches nothing and reports the empty set explicitly

#### Scenario: Pipeline result equals per-change apply result

- **WHEN** the same change is applied via the pipeline and on its own
- **THEN** that change's reconciled result is the same in both cases
