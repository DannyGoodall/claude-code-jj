# jj-linear-sync Specification

## Purpose
TBD - created by archiving change jj-concurrent-linear. Update Purpose after archive.
## Requirements
### Requirement: Separately enabled for Linear-tracked repos only

The Linear binding SHALL ship as a distinct plugin (`jj-concurrent-linear`) requiring the `jj-concurrent` plugin and a configured Linear MCP server, so that repositories without Linear (or without a desire to grant Linear access) never surface its triggers and never issue Linear calls. Where the binding is not enabled, the orchestrator SHALL behave exactly as the bare `jj-concurrent` mechanism does.

#### Scenario: Binding absent in a non-Linear repo

- **WHEN** the `jj-concurrent` plugin is enabled but `jj-concurrent-linear` is not
- **THEN** no Linear sub-issue updates are attempted for any worker
- **AND** the orchestrator reconciles workers exactly as it would without the binding

#### Scenario: Linear MCP unavailable

- **WHEN** the binding is enabled but the Linear MCP server is not reachable
- **THEN** the binding SHALL skip the Linear update and surface a non-fatal note in the orchestrator's reconcile report
- **AND** the worker's integration (rebase/merge/teardown) SHALL proceed unaffected

### Requirement: Umbrella and sub-issue ID threading from dispatch to reconcile

The binding SHALL define how Linear identifiers are threaded across the worker lifecycle. At dispatch — when the orchestrator provisions a workspace and a worker — the binding SHALL record, in the orchestrator's agent-plan manifest, the **umbrella issue ID** for the fan-out and the **sub-issue ID** for that specific worker, keyed by the worker's workspace path (the worker's stable identity). At reconcile — when that worker's JSON report lands — the binding SHALL look the sub-issue ID up by the reporting worker's workspace path so the correct sub-issue is updated. The worker itself SHALL NOT be given, and SHALL NOT need, any Linear identifier; ID custody belongs entirely to the orchestrator.

#### Scenario: Sub-issue resolved for the reporting worker

- **WHEN** a worker provisioned in workspace `W` with recorded sub-issue `S` reports back
- **THEN** the binding resolves `S` from the manifest by `W`
- **AND** applies the report-driven Linear update to `S` and to no other sub-issue

#### Scenario: Worker stays Linear-agnostic

- **WHEN** the orchestrator dispatches a worker
- **THEN** the worker's brief contains no Linear identifier
- **AND** the worker's JSON report contains no Linear identifier
- **AND** the orchestrator alone maps the report to a sub-issue via the manifest

#### Scenario: No recorded sub-issue for a worker

- **WHEN** a worker reports but the manifest has no sub-issue ID keyed to its workspace
- **THEN** the binding SHALL skip the Linear update for that worker and note the missing mapping
- **AND** SHALL NOT update the umbrella or any unrelated sub-issue as a fallback

### Requirement: Status transition on a clean finish

When a worker reports a clean finish (a structured report with `blocked_on` null and no unresolved conflicts), the binding SHALL transition that worker's Linear sub-issue from its in-progress state to its done state. The transition SHALL be idempotent — re-applying the same report (e.g. on a reconcile retry) SHALL NOT produce a duplicate transition or error.

#### Scenario: In-progress sub-issue moves to done

- **WHEN** a worker's report has `blocked_on: null` and `conflicts_seen: null`
- **THEN** its sub-issue transitions from in-progress to done

#### Scenario: Idempotent re-reconcile

- **WHEN** the same clean report is reconciled a second time
- **THEN** the sub-issue remains done with no duplicate transition and no error

### Requirement: Blocker comment when a worker reports blocked

When a worker's report carries a non-null `blocked_on`, the binding SHALL post a comment to that worker's Linear sub-issue carrying the blocker text, and SHALL NOT transition the sub-issue to done. The sub-issue SHALL be left in a state that signals attention is needed (remaining in-progress, or a blocked state if the team's workflow defines one).

#### Scenario: Blocker surfaces as a sub-issue comment

- **WHEN** a worker's report has a non-null `blocked_on` string
- **THEN** the binding posts a comment containing that blocker text to the worker's sub-issue
- **AND** does not transition the sub-issue to done

#### Scenario: Conflict reported is treated as needing attention

- **WHEN** a worker's report has a non-null `conflicts_seen`
- **THEN** the binding posts a comment describing the conflict to the worker's sub-issue
- **AND** does not transition the sub-issue to done

### Requirement: Report-field to Linear-update mapping is the single source of truth

The binding SHALL define an explicit mapping from worker-report fields to Linear updates, consumed off the worker's existing structured JSON report (`workspace`, `changes`, `submitted`, `tests_run`, `blocked_on`, `conflicts_seen`, `notes`) without modifying the report format. A worker that stalls and never returns a report (recovered by the orchestrator's resume-in-place) SHALL leave its sub-issue untouched until a successor produces a report, so a stall never silently marks a sub-issue done.

#### Scenario: Mapping reads only existing report fields

- **WHEN** the binding processes a worker report
- **THEN** it derives the Linear update solely from the documented report fields
- **AND** requires no new field to be added to the worker's report contract

#### Scenario: Stalled worker does not get marked done

- **WHEN** a worker dies without emitting a report
- **THEN** its sub-issue is left unchanged
- **AND** only a successor worker's report drives the next Linear update for that sub-issue

