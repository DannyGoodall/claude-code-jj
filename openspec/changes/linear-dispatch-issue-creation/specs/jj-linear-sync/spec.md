## ADDED Requirements

### Requirement: Umbrella and sub-issue creation at dispatch

When the orchestrator starts a `/jj-openspec apply` or any `jj-delegate` fan-out, the binding SHALL — before workers are dispatched — create exactly one Linear **umbrella issue** representing the change/fan-out, and one **sub-issue per worker** (one per task-group), each parented to the umbrella. Creation SHALL happen on the orchestrator side only; no worker is involved in creating issues. The orchestrator SHALL NOT dispatch a worker before that worker's sub-issue exists (or creation has been explicitly skipped per the unavailability rule).

#### Scenario: Fan-out of N workers creates an umbrella and N sub-issues

- **WHEN** the orchestrator begins a fan-out provisioning N workers (N task-groups)
- **THEN** the binding creates one umbrella issue for the fan-out
- **AND** creates exactly N sub-issues, each parented to that umbrella, one per worker
- **AND** no worker is dispatched before its sub-issue exists

#### Scenario: Single apply creates one umbrella and one sub-issue

- **WHEN** a `/jj-openspec apply <change>` provisions a single worker
- **THEN** the binding creates one umbrella issue for the change and one sub-issue for that worker

### Requirement: Agent-bound label on created issues

Each issue created at dispatch — the umbrella and every sub-issue — SHALL receive a configurable label marking it as agent-bound work, defaulting to `ready-for-agent`. The label value SHALL be configurable per team/repo; where the configured label does not exist in the Linear workspace, the binding SHALL skip labelling with a non-fatal note rather than fail creation.

#### Scenario: Default label applied to created issues

- **WHEN** the binding creates the umbrella and sub-issues with no label override configured
- **THEN** each created issue carries the `ready-for-agent` label

#### Scenario: Configured label overrides the default

- **WHEN** a team configures a different agent-bound label
- **THEN** the binding applies that configured label to each created issue instead of the default

#### Scenario: Missing label does not fail creation

- **WHEN** the configured label does not exist in the Linear workspace
- **THEN** the binding creates the issues without that label and emits a non-fatal note
- **AND** dispatch proceeds

### Requirement: Created IDs threaded into the manifest keyed by workspace path

Immediately after creating issues for a worker, the binding SHALL record in the orchestrator's agent-plan manifest the **umbrella issue ID** for the fan-out and the **sub-issue ID** for that worker, keyed by the worker's workspace path — the `{ workspacePath → { umbrellaId, subIssueId } }` custody that the reconcile-side mapping reads. The recorded sub-issue ID for a workspace path SHALL be the issue created for the worker provisioned at that path, so that a later report from that workspace resolves to exactly the issue created for it.

#### Scenario: Each worker's created sub-issue is keyed by its workspace path

- **WHEN** the binding creates sub-issue `S` for the worker to be provisioned at workspace path `W`
- **THEN** the manifest records `{ W → { umbrellaId, subIssueId: S } }`
- **AND** a later report from workspace `W` resolves to sub-issue `S` and to no other

#### Scenario: Umbrella ID shared across sibling workers

- **WHEN** several workers are created under one fan-out
- **THEN** every sibling worker's manifest entry records the same umbrella ID
- **AND** each records its own distinct sub-issue ID

### Requirement: Worker stays Linear-agnostic at creation

The act of creating issues SHALL NOT introduce any Linear identifier into the worker's world. A worker's dispatch brief SHALL NOT require a Linear identifier to function, and the worker's JSON report SHALL NOT carry one. ID custody belongs entirely to the orchestrator's manifest, exactly as on the reconcile side. Any human-readable cross-reference placed in a brief (e.g. an issue URL for context) SHALL be advisory only and SHALL NOT be something the worker must echo back or act upon.

#### Scenario: Brief carries no required Linear identifier

- **WHEN** the orchestrator dispatches a worker after creating its sub-issue
- **THEN** the worker's brief contains no Linear identifier the worker must use or return
- **AND** the worker completes its workload with no knowledge of any Linear issue

### Requirement: Idempotent creation across re-dispatch and resume-in-place

Issue creation SHALL be idempotent with respect to a given fan-out plan and workspace path. If the manifest already records an umbrella for the fan-out and a sub-issue for a workspace path, the binding SHALL reuse those recorded IDs rather than create new ones. A retried plan, a re-dispatch, or a resume-in-place of an existing workspace (a successor worker provisioned at the same path) SHALL NOT create a duplicate umbrella or a duplicate sub-issue.

#### Scenario: Resume-in-place reuses the existing sub-issue

- **WHEN** a worker at workspace path `W` stalls and a successor is provisioned at the same path `W`
- **THEN** the binding reuses the sub-issue already recorded for `W`
- **AND** creates no new sub-issue and no new umbrella

#### Scenario: Retried plan does not duplicate the umbrella

- **WHEN** a fan-out plan whose umbrella is already recorded is re-run
- **THEN** the binding reuses the recorded umbrella and the recorded per-workspace sub-issues
- **AND** creates no duplicate issues

### Requirement: Skip-and-note when Linear is unavailable or the binding is absent

When the binding is not enabled, or the Linear MCP server is not reachable at dispatch, the binding SHALL skip issue creation entirely, emit a non-fatal note in the dispatch report, and allow the fan-out to proceed unaffected — workspace provisioning and worker dispatch SHALL NOT be blocked by Linear unavailability. Where creation is skipped, no `{ umbrellaId, subIssueId }` entry is recorded, so the reconcile-side mapping SHALL find no sub-issue for those workers and SHALL itself skip-and-note (no umbrella or sibling fallback).

#### Scenario: Linear MCP unreachable at dispatch

- **WHEN** the binding is enabled but the Linear MCP server is not reachable when the fan-out starts
- **THEN** the binding skips issue creation and emits a non-fatal note
- **AND** workspaces are provisioned and workers are dispatched exactly as without the binding

#### Scenario: Binding absent leaves dispatch unchanged

- **WHEN** the `jj-concurrent` plugin is enabled but `jj-concurrent-linear` is not
- **THEN** no Linear issues are created at dispatch
- **AND** the orchestrator fans out exactly as the bare mechanism would
