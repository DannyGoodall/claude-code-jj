## ADDED Requirements

### Requirement: Separable task groups are detected from tasks.md

The fan-out path SHALL analyse the change's `tasks.md` and partition it into task groups, then classify which groups are **separable** — implementable concurrently because they touch **disjoint file areas** with no cross-group ordering dependency. A group's file area SHALL be determined from the tasks' declared/derived target paths (e.g. file mentions, directory scopes); when a group's area cannot be determined, that group SHALL be treated as non-separable. Two groups SHALL be deemed separable only when their file areas do not intersect and neither group's tasks depend on the other's completion.

#### Scenario: Disjoint groups are classified separable

- **WHEN** `tasks.md` has two task groups, one editing only `src/api/**` and one editing only `docs/**`
- **THEN** the detector reports both groups as separable
- **AND** their file areas are recorded as disjoint

#### Scenario: Overlapping groups are classified non-separable

- **WHEN** two task groups both edit files under `src/api/**`
- **THEN** the detector reports them as non-separable (their areas intersect)

#### Scenario: Undeterminable area forces non-separable

- **WHEN** a task group's target file area cannot be derived from its tasks
- **THEN** that group is classified non-separable and is not fanned out

### Requirement: One workspace per separable group, dispatched concurrently

For each separable group, the orchestrator SHALL provision its own jj workspace via the `jj-delegate` mechanism (explicit base revision on the change's proposal revision, concurrent siblings) and dispatch one `jj-workspace-worker` per group. Each worker's workload SHALL be `/opsx:apply <change>` **scoped to only that group's tasks**: the worker implements only its group's tasks and marks only its group's checkboxes in `tasks.md`, leaving other groups' tasks untouched.

#### Scenario: Each group gets an isolated concurrent worker

- **WHEN** three groups are separable
- **THEN** three workspaces are provisioned as concurrent siblings, each on the change's proposal revision
- **AND** three workers run `/opsx:apply` concurrently, each scoped to one group's tasks

#### Scenario: A group worker touches only its own tasks

- **WHEN** a worker is dispatched for group A
- **THEN** it implements only group A's tasks and marks only group A's checkboxes
- **AND** it does not edit files outside group A's recorded file area

### Requirement: Group workers reconcile into one change branch

After each group worker reports, the orchestrator SHALL integrate that worker's commits into a **single change branch** for the change (stacking or merging the sibling changes), not into separate branches. Integration SHALL rely on the never-halting jj integration: a reconcile that touches overlapping content produces a first-class conflict object the orchestrator resolves deliberately by editing conflict markers, never the interactive `jj resolve`. The reconciled branch SHALL contain every group's completed tasks before the apply shape's verify/push tail runs.

#### Scenario: Separable groups reconcile cleanly

- **WHEN** all group workers complete on disjoint file areas
- **THEN** each worker's commits are integrated onto the one change branch in turn
- **AND** the integration succeeds without conflict because the areas are disjoint

#### Scenario: An unexpected overlap surfaces a first-class conflict

- **WHEN** two group workers' commits unexpectedly touch the same lines during reconcile
- **THEN** the integration succeeds (exit 0) and the change is marked as a first-class conflict
- **AND** the orchestrator resolves it by editing markers before verify runs

#### Scenario: Verify runs once over the reconciled change

- **WHEN** all groups are reconciled onto the one change branch
- **THEN** the apply shape's verify tail runs once over the combined result before push/PR

### Requirement: Single-worker fallback when groups are not separable

Fan-out SHALL be strictly an optimization. When `tasks.md` yields fewer than two separable groups — including when groups overlap, have ordering dependencies, file areas are undeterminable, or `tasks.md` is not group-structured — the apply SHALL fall back to exactly the existing single-worker behaviour: one worker, one workspace, the whole change. Choosing fan-out SHALL NOT change the final reconciled result relative to the single-worker path; it only changes how the work is distributed.

#### Scenario: Too few separable groups falls back

- **WHEN** a change has only one task group, or all groups overlap
- **THEN** apply runs a single worker for the whole change exactly as without fan-out

#### Scenario: Ordering dependency forces fallback

- **WHEN** group B's tasks depend on group A's completion
- **THEN** the groups are not fanned out concurrently and apply falls back to the single-worker path

#### Scenario: Fan-out result equals single-worker result

- **WHEN** the same change is applied via fan-out and via the single-worker path
- **THEN** the reconciled change branch contains the same completed tasks in both cases
