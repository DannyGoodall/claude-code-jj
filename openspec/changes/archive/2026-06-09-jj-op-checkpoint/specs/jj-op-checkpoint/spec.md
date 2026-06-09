## ADDED Requirements

### Requirement: Record a labelled checkpoint before a risky step

The plugin SHALL provide an orchestrator skill `/jj-checkpoint <label>` that captures the repository's current operation id (resolved from `jj op log`) under the human-supplied `<label>` and persists it as a checkpoint record. A checkpoint record SHALL contain at minimum the label, the captured op id, a timestamp, and an optional note. Recording a checkpoint SHALL be read-only with respect to repository history — it SHALL NOT itself create, abandon, or restore any operation; it only remembers the current op id so a later `/jj-rewind` can return to it. The skill SHALL run only in the orchestrator role (which owns the agent-plan manifest) and SHALL NOT be invoked inside a worker.

#### Scenario: Checkpoint captures the current op id

- **WHEN** `/jj-checkpoint pre-fanout-integration` is invoked
- **THEN** the current operation id is resolved from `jj op log`
- **AND** a checkpoint record with label `pre-fanout-integration`, that op id, and a timestamp is persisted
- **AND** no operation log entry that rewrites history is created by the recording itself

#### Scenario: Recording a checkpoint does not mutate history

- **WHEN** a checkpoint is recorded
- **THEN** the repository's working copy, bookmarks, and commits are unchanged
- **AND** the only effect is the new checkpoint record

### Requirement: Distinct labels and re-use semantics

A checkpoint label SHALL be a stable handle for one captured op id. The skill SHALL require a non-empty label. When `/jj-checkpoint` is invoked with a label that already exists, the skill SHALL NOT silently discard the prior record; it SHALL either refuse with a clear message or update the existing label only on explicit confirmation, so an earlier save point is never lost by accident.

#### Scenario: Empty label is rejected

- **WHEN** `/jj-checkpoint` is invoked with no label or an empty label
- **THEN** the skill reports that a non-empty label is required
- **AND** no checkpoint record is created

#### Scenario: Reusing an existing label does not silently overwrite

- **WHEN** `/jj-checkpoint <label>` is invoked for a label that already has a checkpoint
- **THEN** the skill does not silently replace the prior op id
- **AND** it either refuses or updates only after explicit confirmation

### Requirement: Rewind restores the repo to a checkpoint's op

The plugin SHALL provide an orchestrator skill `/jj-rewind [label]` that restores the repository to a checkpoint's captured operation id via `jj op restore <op-id>`. When a `label` is given, the skill SHALL target that named checkpoint; when no label is given, it SHALL target the most recently recorded checkpoint. The skill SHALL resolve the label to its stored op id and SHALL restore to exactly that op. The skill SHALL run only in the orchestrator role and SHALL NOT be invoked inside a worker.

#### Scenario: Rewind to a named checkpoint

- **WHEN** `/jj-rewind pre-fanout-integration` is invoked and that checkpoint exists
- **THEN** the skill runs `jj op restore <captured-op-id>` for that checkpoint
- **AND** the repository state matches the operation that was current when the checkpoint was recorded

#### Scenario: Bare rewind targets the latest checkpoint

- **WHEN** `/jj-rewind` is invoked with no label
- **THEN** the skill targets the most recently recorded checkpoint
- **AND** restores the repository to that checkpoint's captured op id

#### Scenario: Unknown label is reported, not guessed

- **WHEN** `/jj-rewind <label>` is invoked for a label with no checkpoint record
- **THEN** the skill reports the unknown label and lists the available checkpoints
- **AND** it does not run `jj op restore` against a guessed op id

### Requirement: Confirmation summary before restoring

Before running `jj op restore`, `/jj-rewind` SHALL print a confirmation summary describing what the restore will change: the target checkpoint (label, op id, timestamp), the operations that will be undone (those recorded after the captured op, from `jj op log`), and the affected workspaces and bookmarks. The skill SHALL require explicit confirmation before performing the restore, since `jj op restore` is a whole-repo undo that affects every workspace.

#### Scenario: Summary precedes the restore

- **WHEN** `/jj-rewind <label>` is invoked
- **THEN** a summary of the target checkpoint and the operations that will be undone is printed before any `jj op restore` runs
- **AND** the restore proceeds only after explicit confirmation

#### Scenario: Live sibling workspaces are flagged

- **WHEN** the rewind would undo operations that other live workspaces depend on
- **THEN** the summary flags the affected workspaces so the orchestrator can weigh the cross-workspace impact before confirming

### Requirement: Op-log only, never deletes repo metadata

Both skills SHALL operate exclusively through jj's operation log — `jj op log` to read and resolve op ids and `jj op restore` to roll back — and SHALL run non-interactive jj only (`--no-pager`, no editor spawn, no `-i`/`--interactive`). Neither skill SHALL delete or remove `.jj` (or any repository metadata), SHALL run raw mutating git, or SHALL touch bookmarks or push directly; rollback is achieved by `jj op restore` alone, which is itself recorded as a new operation and is therefore reversible.

#### Scenario: Rollback uses jj op restore, not deletion

- **WHEN** a rewind is performed
- **THEN** the rollback is achieved with `jj op restore <op-id>` only
- **AND** no `.jj` directory or repository metadata is deleted and no raw mutating git is run

#### Scenario: A rewind is itself reversible

- **WHEN** `/jj-rewind` restores to an earlier op
- **THEN** that restore is recorded as a new operation in `jj op log`
- **AND** the state prior to the rewind can itself be recovered by restoring to that later op

### Requirement: Checkpoints fit the reconcile lifecycle

The skills SHALL be usable as the before/after-a-risky-step beats of the `jj-delegate` reconcile/integration lifecycle: `/jj-checkpoint <label>` invoked immediately before a fan-out integration or a large rebase, and `/jj-rewind [label]` invoked to undo that step if it goes wrong. Checkpoint records SHALL be persisted alongside the orchestrator's existing agent-plan manifest so they survive across orchestration steps within a session.

#### Scenario: Checkpoint before fan-out integration

- **WHEN** the orchestrator is about to integrate several workers' changes in one fan-out pass
- **THEN** it invokes `/jj-checkpoint <label>` first to record a save point
- **AND** if the integration goes wrong it invokes `/jj-rewind <label>` to return to that point

#### Scenario: Checkpoints persist across steps in a session

- **WHEN** a checkpoint is recorded and the orchestrator performs further steps
- **THEN** the checkpoint remains resolvable by its label for a later `/jj-rewind`
