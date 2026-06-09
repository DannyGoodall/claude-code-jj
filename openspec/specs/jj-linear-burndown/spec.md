# jj-linear-burndown Specification

## Purpose
TBD - created by archiving change jj-linear-burndown. Update Purpose after archive.
## Requirements
### Requirement: Orchestrator-only, separately enabled, Linear-backed

The burndown driver SHALL ship as a skill (`jj-burndown`, trigger `/jj-burndown <board>`) inside the separately-enableable `jj-concurrent-linear` plugin, requiring the `jj-concurrent` plugin (for the `jj-delegate` mechanism) and a configured Linear MCP server. It SHALL run only in the repository's primary (default) jj workspace as an orchestrator-side driver; it SHALL own no jj/workspace choreography and SHALL delegate all provisioning, dispatch, integration, and teardown to `jj-delegate`. Where the plugin is not enabled, the skill's trigger SHALL be absent and no Linear calls SHALL be made.

#### Scenario: Absent where the plugin is not enabled

- **WHEN** the `jj-concurrent` plugin is enabled but `jj-concurrent-linear` is not
- **THEN** the `/jj-burndown` trigger is not present
- **AND** no board query or Linear update is attempted

#### Scenario: Linear MCP unavailable

- **WHEN** `/jj-burndown <board>` is invoked but the Linear MCP server is not reachable
- **THEN** the skill SHALL abort the run before dispatching any worker and report that Linear is unavailable
- **AND** SHALL NOT leave any partially-dispatched worker unaccounted for

#### Scenario: Driver delegates all jj choreography

- **WHEN** the skill dispatches an issue
- **THEN** the workspace add, background dispatch, integration, and teardown are performed by `jj-delegate`
- **AND** the burndown skill itself issues no `jj workspace`, bookmark, push, or rebase command

### Requirement: Board/label query selects the work queue

The skill SHALL resolve the `<board>` argument to a Linear board by name or id, then query that board for issues in the `ready-for-agent` state (per the project's triage-labels convention) to form the candidate queue. The selection SHALL be deterministic and re-queryable: the same board state yields the same candidate set. Issues that are not `ready-for-agent` SHALL be excluded. The candidate set SHALL be ordered for dispatch by a defined, stable key (board position, then priority, then issue identifier as a tie-breaker), so dispatch order is reproducible.

#### Scenario: Only ready-for-agent issues enter the queue

- **WHEN** the board holds a mix of `ready-for-agent`, backlog, in-progress, and done issues
- **THEN** only the `ready-for-agent` issues are placed in the candidate queue
- **AND** issues in any other state are excluded

#### Scenario: Board argument resolved by name or id

- **WHEN** `/jj-burndown <board>` is invoked with either a board name or a board id
- **THEN** the skill resolves it to a single Linear board
- **AND** if the argument is ambiguous or matches no board, the skill reports the resolution failure and dispatches nothing

#### Scenario: Deterministic dispatch ordering

- **WHEN** the candidate set is built from a given board state
- **THEN** the issues are ordered by the defined stable key
- **AND** re-querying the same unchanged board state produces the same ordered set

### Requirement: Bounded sliding-window concurrent drain

The skill SHALL drain the queue under a concurrency cap that bounds the number of `jj-delegate` workers in flight at once. The cap SHALL default to a moderate value (3) and SHALL be configurable. The skill SHALL maintain a sliding window: it dispatches up to the cap, and each time a worker lands and is reconciled it pulls and dispatches the next ready issue, so the in-flight count never exceeds the cap. The skill SHALL NOT fan out the entire board at once.

#### Scenario: In-flight count never exceeds the cap

- **WHEN** the queue holds more issues than the configured cap
- **THEN** at most `cap` workers are in flight at any moment
- **AND** the remaining issues wait in the queue until a slot frees

#### Scenario: Window advances on each landing

- **WHEN** an in-flight worker lands and is reconciled
- **THEN** the skill pulls the next ready issue and dispatches it (if any remain)
- **AND** the freed slot is reused rather than left idle while the queue is non-empty

#### Scenario: Configurable cap honored

- **WHEN** the cap is configured to a value other than the default
- **THEN** the skill drains under that configured value
- **AND** the default of 3 applies only when no override is given

### Requirement: Per-issue dispatch via jj-delegate

Each pulled issue SHALL become exactly one `jj-delegate` worker in its own jj workspace (concurrent siblings, per the `jj-delegate` spec's orchestrator/worker split and concurrent-sibling provisioning). The issue's body/specification SHALL be passed as that worker's workload. Workers SHALL be dispatched in the background by default, consistent with `jj-delegate`. One issue SHALL map to exactly one worker; the skill SHALL NOT bundle multiple issues into a single worker.

#### Scenario: One issue, one worker, one workspace

- **WHEN** an issue is pulled from the queue
- **THEN** the skill dispatches a single `jj-delegate` worker in its own workspace for that issue
- **AND** the issue's body becomes the worker's workload

#### Scenario: Background concurrent siblings

- **WHEN** multiple issues are dispatched within the cap
- **THEN** each runs as a background concurrent sibling worker per the `jj-delegate` spec
- **AND** the skill returns to reconcile landings rather than blocking on any single worker

### Requirement: Per-issue Linear update as its worker lands

When a worker reports, the skill SHALL update that worker's issue based on the worker's structured JSON report: a clean finish (`blocked_on` null and no unresolved conflicts) SHALL move the issue from its in-progress state to its done state; a non-null `blocked_on` or `conflicts_seen` SHALL post a comment carrying the blocker/conflict text and leave the issue in a needs-attention state (not done). Where the C2 status-sync binding (`jj-linear-sync`) is enabled, the skill SHALL reuse it for the per-issue transition and SHALL NOT redefine the report-to-Linear mapping. Where that binding is absent, the skill SHALL apply a minimal inline status update following the same clean/blocked rule and SHALL note that it is running in degraded mode.

#### Scenario: Clean landing moves the issue to done

- **WHEN** an issue's worker reports `blocked_on: null` and `conflicts_seen: null`
- **THEN** the issue transitions from in-progress to done

#### Scenario: Blocked landing comments and holds

- **WHEN** an issue's worker reports a non-null `blocked_on` or `conflicts_seen`
- **THEN** the skill posts a comment with that text to the issue
- **AND** does not transition the issue to done

#### Scenario: Reuse the status-sync binding when present

- **WHEN** the `jj-linear-sync` (C2) binding is enabled
- **THEN** the burndown defers the per-issue transition to that binding's report-to-Linear mapping
- **AND** does not define its own competing mapping

#### Scenario: Degraded inline update when the binding is absent

- **WHEN** the `jj-linear-sync` binding is not enabled
- **THEN** the burndown applies a minimal inline status update under the same clean/blocked rule
- **AND** notes in its readout that it is running in degraded mode

### Requirement: Live burndown summary cadence

The skill SHALL emit a running summary at a defined cadence — at minimum each time the sliding window advances (a worker lands and/or a new worker is dispatched). Each summary SHALL show queue depth remaining, in-flight worker count, cumulative done count, and cumulative blocked count. When the run terminates the skill SHALL emit a final summary reflecting the end state of the drain.

#### Scenario: Running summary on each window advance

- **WHEN** a worker lands or the window advances
- **THEN** the skill emits a summary with queue-remaining, in-flight, done, and blocked counts

#### Scenario: Final summary at termination

- **WHEN** the run terminates
- **THEN** the skill emits a final summary reflecting total done, total blocked, and an empty queue

### Requirement: Re-query and drain termination

The skill SHALL re-query the board as the queue drains so that issues newly labelled `ready-for-agent` during the run are picked up within the same run, rather than fixing the queue at start. Re-query SHALL not re-dispatch an issue that already has an in-flight or completed worker in this run (dispatch is idempotent per issue within a run). The run SHALL terminate when a re-query returns no `ready-for-agent` issues and no workers are in flight.

#### Scenario: Newly labelled issue is picked up mid-run

- **WHEN** an issue is moved to `ready-for-agent` after the run has started but before termination
- **THEN** a subsequent re-query includes it and the skill dispatches it when a slot frees

#### Scenario: No duplicate dispatch on re-query

- **WHEN** a re-query returns an issue that already has an in-flight or completed worker this run
- **THEN** the skill does not dispatch a second worker for that issue

#### Scenario: Termination when board is drained

- **WHEN** a re-query returns no `ready-for-agent` issues and no workers are in flight
- **THEN** the run terminates and emits the final summary

