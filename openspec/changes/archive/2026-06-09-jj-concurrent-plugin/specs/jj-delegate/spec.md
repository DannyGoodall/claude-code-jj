## ADDED Requirements

### Requirement: Orchestrator/worker role split

The plugin SHALL define two roles. The **orchestrator** runs in the repository's primary (default) jj workspace and owns workspace lifecycle (`jj workspace add`/`forget`), all bookmark and ref operations, `jj git push`, integration, and the agent-plan manifest. A **worker** runs in exactly one linked jj workspace and owns only its own commits; it SHALL NOT operate on bookmarks, push, or run raw mutating git.

#### Scenario: Worker confined to its workspace

- **WHEN** a worker is dispatched into a provisioned workspace
- **THEN** it edits and shapes commits only within that workspace
- **AND** all bookmark/push/integration operations are performed by the orchestrator

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

After integration the orchestrator SHALL tear a workspace down (`jj workspace forget` + remove the directory; never the repo `.jj`). A worker that reports a blocker SHALL have its workspace left intact for inspection. A worker that dies without reporting SHALL be recovered by **resume-in-place**: its edits are already snapshotted, so a fresh worker continues in the same workspace.

#### Scenario: Resume-in-place after a worker dies

- **WHEN** a worker stalls or is killed without a report
- **THEN** its work remains snapshotted in its workspace
- **AND** a fresh worker dispatched into the same workspace continues from that state
