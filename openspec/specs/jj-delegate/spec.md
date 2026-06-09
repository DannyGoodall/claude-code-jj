# jj-delegate Specification

## Purpose
TBD - created by archiving change jj-concurrent-plugin. Update Purpose after archive.
## Requirements
### Requirement: Orchestrator/worker role split

The plugin SHALL define two roles. The **orchestrator** runs in the repository's primary (default) jj workspace and owns workspace lifecycle (`jj workspace add`/`forget`), all bookmark and ref operations, `jj git push`, integration, and its own per-session agent-plan manifest. A **worker** runs in exactly one linked jj workspace and owns only its own commits; it SHALL NOT operate on bookmarks, push, or run raw mutating git. Multiple orchestrator sessions MAY run concurrently against one repo, each owning a distinct session-namespaced manifest; one orchestrator session SHALL NOT write another session's manifest.

#### Scenario: Worker confined to its workspace

- **WHEN** a worker is dispatched into a provisioned workspace
- **THEN** it edits and shapes commits only within that workspace
- **AND** all bookmark/push/integration operations are performed by the orchestrator

#### Scenario: Two orchestrators do not clobber each other's manifest

- **WHEN** two orchestrator sessions run concurrently in the same repo and each records its slices
- **THEN** each writes only its own session-namespaced manifest
- **AND** neither session's slices are lost or overwritten by the other

### Requirement: Workspace provisioning with explicit base revision (seed intent)

Provisioning a worker workspace SHALL use `jj workspace add -r <base-rev> <path>` with the base revision given explicitly. Because `jj workspace add` defaults to the parent of the current change, omitting `-r` would exclude in-flight inputs present in `@`; the orchestrator SHALL therefore base a worker on the revision that already contains the inputs the workload needs (e.g. `@` when clean, or a curated change revision), with no separate "seed commit".

#### Scenario: Worker workspace carries the inputs it needs

- **WHEN** the orchestrator provisions a worker on a revision containing required inputs
- **THEN** those inputs are present in the worker's workspace without any prior commit ceremony

### Requirement: Background dispatch by default

The orchestrator SHALL dispatch workers in the background by default so the session returns immediately and further workers can be provisioned and dispatched concurrently. Foreground dispatch SHALL be available on explicit request.

#### Scenario: Concurrent independent workers

- **WHEN** two independent workloads are delegated
- **THEN** each runs in its own workspace concurrently
- **AND** the orchestrator reconciles each as it reports

### Requirement: Integration never halts

When the orchestrator integrates a worker's change (e.g. by rebasing it onto trunk or onto a sibling), the operation SHALL succeed even on conflict — jj records conflicts as first-class objects in the resulting commit rather than blocking. The orchestrator SHALL resolve any conflict deliberately (editing conflict markers, never the interactive `jj resolve`).

#### Scenario: Conflicting integration produces a resolvable object

- **WHEN** two workers' changes touch the same lines and are stacked
- **THEN** the rebase succeeds (exit 0) and the conflicted change is marked as a first-class conflict
- **AND** the orchestrator resolves it by editing markers, then the change is clean

### Requirement: Teardown and failure handling

After integration the orchestrator SHALL tear a workspace down (`jj workspace forget` + remove the directory; never the repo `.jj`). A worker that reports a blocker SHALL have its workspace left intact for inspection. A worker that dies without reporting SHALL be recovered by **resume-in-place**: its edits are already snapshotted, so a fresh worker continues in the same workspace. The orchestrator SHALL additionally sweep state left by dead orchestrators/agents: on startup it SHALL identify session-namespaced manifests that are provably stale (past a liveness TTL with no fresh heartbeat and no live owner) and SHALL remove or archive them, while leaving any live session's manifest and any worker's commits untouched.

#### Scenario: Resume-in-place after a worker dies

- **WHEN** a worker stalls or is killed without a report
- **THEN** its work remains snapshotted in its workspace
- **AND** a fresh worker dispatched into the same workspace continues from that state

#### Scenario: Stale manifest from a dead orchestrator is swept

- **WHEN** an orchestrator starts and finds a session-namespaced manifest whose heartbeat is past the liveness TTL with no live owner
- **THEN** it removes or archives that stale manifest
- **AND** it does not delete or alter any worker commits

#### Scenario: Live orchestrator's manifest is never reclaimed

- **WHEN** a manifest's owning session still appears live (fresh heartbeat within the TTL), even if idle
- **THEN** the sweep leaves that manifest untouched

### Requirement: Per-session manifest namespacing

The orchestrator SHALL own a manifest namespaced to its session — `.jj-agent-plan.<session-id>.json` — where `<session-id>` is a filesystem-safe token derived deterministically from the orchestrator's session identity, stable across resume. All of that session's slice, status, blocker, and checkpoint records SHALL live in that one file. When no session identity is resolvable, the orchestrator SHALL fall back to the unnamespaced default path `.jj-agent-plan.json`, preserving today's single-orchestrator behaviour. Each manifest SHALL carry a liveness marker (its owning session id and a heartbeat the orchestrator refreshes as it operates) so other tooling can judge staleness.

#### Scenario: Session-namespaced manifest path

- **WHEN** an orchestrator session with a resolvable session id records its plan
- **THEN** it reads and writes `.jj-agent-plan.<session-id>.json`
- **AND** it does not read or write any other session's manifest

#### Scenario: Back-compat default manifest path

- **WHEN** an orchestrator runs with no resolvable session id (the lone single-orchestrator case)
- **THEN** it uses the unnamespaced `.jj-agent-plan.json` path exactly as before
- **AND** existing repos carrying a plain `.jj-agent-plan.json` continue to work without migration

#### Scenario: Resume re-attaches to the same manifest

- **WHEN** an orchestrator session resumes
- **THEN** it derives the same session id and re-attaches to its existing `.jj-agent-plan.<session-id>.json`

### Requirement: Per-orchestrator workspace and bookmark naming

To prevent two concurrent orchestrators from contending for the same names, the orchestrator SHALL derive workspace directory names and bookmark names from a per-session prefix when running under a session id. Workspace dirs SHALL incorporate the session prefix (e.g. `../wt-<session-prefix>-<slug>`) and bookmarks SHALL incorporate it (e.g. `<session-prefix>-<slug>`). The prefix SHALL be stable across resume so prefixed names are reproduced. In the back-compat single-orchestrator case (no session id), names SHALL be unprefixed exactly as today.

#### Scenario: Two orchestrators never collide on workspace dir or bookmark

- **WHEN** two orchestrator sessions delegate workloads that would otherwise pick the same `../wt-<slug>` dir and `<slug>` bookmark
- **THEN** each session's workspace dir and bookmark carry its own session prefix
- **AND** neither `jj workspace add` nor any bookmark operation contends for a name owned by the other session

#### Scenario: Single-orchestrator names stay unprefixed

- **WHEN** a lone orchestrator with no session id provisions a workspace and bookmark
- **THEN** the workspace dir and bookmark names are unprefixed, identical to today's behaviour

