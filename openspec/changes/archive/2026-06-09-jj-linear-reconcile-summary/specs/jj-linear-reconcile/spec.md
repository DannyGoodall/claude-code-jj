## ADDED Requirements

### Requirement: Separately enabled for Linear-tracked repos only

The `jj-linear-reconcile` capability SHALL ship inside the `jj-concurrent-linear` plugin, which requires the `jj-concurrent` plugin and a configured Linear MCP server. Where that plugin is not enabled, no umbrella summary comment SHALL be posted and no human-gate sub-issue SHALL be created, and the orchestrator SHALL reconcile workers exactly as the bare `jj-concurrent` mechanism does.

#### Scenario: Binding absent leaves reconcile unchanged

- **WHEN** the `jj-concurrent` plugin is enabled but `jj-concurrent-linear` is not
- **THEN** no summary comment is posted to any umbrella issue
- **AND** no `ready-for-human` sub-issue is created
- **AND** the orchestrator reconciles workers exactly as it would without the binding

#### Scenario: Linear MCP unavailable is non-fatal

- **WHEN** the binding is enabled but the Linear MCP server is not reachable at reconcile
- **THEN** the binding SHALL skip the summary comment and any human-gate sub-issue creation
- **AND** SHALL surface a non-fatal note in the orchestrator's reconcile report
- **AND** the worker's integration (rebase/merge/teardown) SHALL proceed unaffected

### Requirement: Structured reconcile summary posted to the umbrella issue

At the orchestrator's reconcile step for a worker, the binding SHALL post a single structured summary comment to that fan-out's **umbrella** Linear issue (resolved from the agent-plan manifest by the reporting worker's workspace path). The comment SHALL be composed only from documented sources — the worker's structured JSON report and the binding's verify/PR reconcile outcome — and SHALL contain four defined sections:

- **What changed** — sourced from the worker report's `changes` list (and, when present, the PR diff/title from the reconcile tail).
- **Root cause(s)** — sourced from the worker report's `notes` and, when the worker reported blocked or conflicted, the `blocked_on` / `conflicts_seen` text.
- **Test results** — sourced from the worker report's `tests_run` together with the verify outcome produced by the `jj-openspec-binding` reconcile tail (pass/fail).
- **PR link** — sourced from the reconcile tail's push/PR step when a PR was opened; otherwise stated as "no PR" with the integrated change-id(s).

The summary SHALL NOT invent content beyond these sources; any section without source data SHALL be rendered as an explicit "none reported" rather than fabricated.

#### Scenario: Clean finish yields a four-section summary

- **WHEN** a worker reports a clean finish and the reconcile tail produces a verify outcome and a PR link
- **THEN** the binding posts one comment to the umbrella issue with What-changed, Root-cause, Test-results, and PR-link sections
- **AND** each section's content is drawn only from the worker report and the verify/PR outcome

#### Scenario: Missing source data renders as none-reported

- **WHEN** the worker report omits a source for a section (e.g. `tests_run` is null)
- **THEN** that section of the summary is rendered as an explicit "none reported"
- **AND** no content is fabricated to fill it

#### Scenario: Umbrella resolved by workspace path

- **WHEN** a worker provisioned in workspace `W` reports back
- **THEN** the binding resolves the umbrella issue for `W` from the manifest
- **AND** posts the summary to that umbrella and to no unrelated issue

### Requirement: Idempotent summary on reconcile retry

Reconcile MAY be retried. The binding SHALL avoid posting a duplicate, byte-identical summary comment for the same worker on a retry — for example by guarding on the last summary comment already present for that worker — so a retried reconcile does not litter the umbrella with repeated summaries.

#### Scenario: Retried reconcile does not duplicate the summary

- **WHEN** the same worker's reconcile is processed a second time with the same report and outcome
- **THEN** the binding does not post a second byte-identical summary comment
- **AND** no error is raised

### Requirement: Auto human-gate sub-issue when a manual pass is needed

When a reconciled change needs a human pass that automated verify cannot cover — specifically a manual UI/visual check signalled by the worker report or the verify outcome — the binding SHALL auto-create a Linear **sub-issue under the umbrella**, labelled `ready-for-human`, describing exactly what to check. The human-gate sub-issue body SHALL state: what to verify (the specific UI/visual behaviour), why automated verify cannot cover it, and where to look (the PR link and/or the affected route or screenshot target). The binding SHALL NOT mark the change complete on the strength of automated verify alone while a human-gate sub-issue is outstanding.

#### Scenario: Visual check flagged creates a ready-for-human sub-issue

- **WHEN** the worker report or verify outcome flags an outstanding manual UI/visual check that automated verify cannot cover
- **THEN** the binding creates a sub-issue under the umbrella labelled `ready-for-human`
- **AND** its body states what to verify, why automated verify cannot cover it, and where to look (PR link / route / screenshot target)

#### Scenario: Human-gate sub-issue is linked to the umbrella

- **WHEN** a human-gate sub-issue is created
- **THEN** it is created as a sub-issue of the fan-out's umbrella issue resolved from the manifest by the worker's workspace path
- **AND** the reconcile summary comment references that it was raised

### Requirement: Human-gate trigger is precise and does not fire on a fully-automated clean finish

The binding SHALL define the human-gate trigger explicitly: a `ready-for-human` sub-issue is created **only** when the worker report or verify outcome carries a manual/visual-verification signal (e.g. a `notes` or verify field indicating a UI/visual check is outstanding). A fully-automated clean finish — automated verify passed and no manual/visual signal present — SHALL NOT create a human-gate sub-issue. A reported blocker or conflict SHALL NOT, by itself, create a `ready-for-human` sub-issue (that path is a blocker, not a human visual gate).

#### Scenario: Fully-automated clean finish creates no human-gate sub-issue

- **WHEN** automated verify passed and neither the report nor the verify outcome carries a manual/visual signal
- **THEN** no `ready-for-human` sub-issue is created
- **AND** only the summary comment is posted to the umbrella

#### Scenario: Blocker alone does not create a human-gate sub-issue

- **WHEN** a worker reports a non-null `blocked_on` and no manual/visual-verification signal
- **THEN** the binding does not create a `ready-for-human` sub-issue
- **AND** the blocker is surfaced via the summary's Root-cause section instead

### Requirement: Reconcile inputs are read-only and the worker stays Linear-agnostic

The binding SHALL derive the summary and the human-gate decision solely from the worker's existing structured JSON report (`workspace`, `changes`, `submitted`, `tests_run`, `blocked_on`, `conflicts_seen`, `notes`), the verify outcome from the `jj-openspec-binding` reconcile tail, and the orchestrator's plan manifest — without modifying the report format and without giving the worker any Linear identifier or capability. A worker that stalls and never returns a report (recovered by resume-in-place) SHALL produce no umbrella summary and no human-gate sub-issue until a successor returns a report.

#### Scenario: Summary derives only from existing inputs

- **WHEN** the binding composes a summary
- **THEN** it reads only the documented report fields, the verify outcome, and the manifest
- **AND** requires no new field added to the worker's report contract

#### Scenario: Stalled worker produces no umbrella post

- **WHEN** a worker dies without emitting a report
- **THEN** no summary comment and no human-gate sub-issue are produced for it
- **AND** only a successor worker's report drives the next umbrella update
