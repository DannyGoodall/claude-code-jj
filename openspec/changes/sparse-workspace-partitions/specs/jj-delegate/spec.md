## MODIFIED Requirements

### Requirement: Workspace provisioning with explicit base revision (seed intent)

Provisioning a worker workspace SHALL use `jj workspace add -r <base-rev> <path>` with the base revision given explicitly. Because `jj workspace add` defaults to the parent of the current change, omitting `-r` would exclude in-flight inputs present in `@`; the orchestrator SHALL therefore base a worker on the revision that already contains the inputs the workload needs (e.g. `@` when clean, or a curated change revision), with no separate "seed commit".

Provisioning MAY additionally scope the worker's working copy to a declared **sparse partition** by passing `--sparse-patterns <glob...>` (equivalently applying `jj sparse set` to the new workspace). When a sparse partition is given, only the matching paths SHALL materialise on disk in that workspace; files outside the partition SHALL NOT be present, so the worker physically cannot read or edit them. Sparse provisioning SHALL be optional and per-worker: when no sparse partition is given, the workspace materialises the full working tree exactly as before. The base-revision seed-intent rule above SHALL be unaffected by the sparse choice — the partition governs *which files materialise*, never *which revision the workspace starts from*.

#### Scenario: Worker workspace carries the inputs it needs

- **WHEN** the orchestrator provisions a worker on a revision containing required inputs
- **THEN** those inputs are present in the worker's workspace without any prior commit ceremony

#### Scenario: Full-tree provisioning is unchanged when no partition is given

- **WHEN** the orchestrator provisions a worker without a sparse partition
- **THEN** the worker's workspace materialises the full working tree of the base revision, exactly as before

#### Scenario: Sparse partition materialises only the worker's lane

- **WHEN** the orchestrator provisions a worker with `--sparse-patterns` scoped to that worker's file partition
- **THEN** only the partition's paths materialise in the worker's workspace
- **AND** files outside the partition are absent from disk, so the worker cannot read or edit them

## ADDED Requirements

### Requirement: Sparse partition as a hard ownership boundary

When the orchestrator fans out concurrent workers over disjoint file partitions, it MAY provision each worker with a sparse partition to make disjoint-file ownership a **physical guarantee** rather than a soft convention. A worker's sparse partition SHALL be chosen so that disjoint partitions across concurrent siblings do not overlap; the absence of out-of-lane files SHALL be the enforcement mechanism, so a worker cannot produce a cross-lane edit even by mistake.

The orchestrator SHALL include in a worker's partition not only the paths the worker is expected to **edit** but also the paths the workload must **read** to function (e.g. the invoked skill's own inputs and any in-lane context it depends on), so a sparse worker is never starved of context it legitimately needs. A worker SHALL treat the deliberate absence of out-of-partition files as expected, not as a missing-file error.

#### Scenario: Concurrent siblings cannot edit each other's lane

- **WHEN** two concurrent workers are provisioned with non-overlapping sparse partitions
- **THEN** neither worker's workspace contains the other's files
- **AND** a worker cannot produce a change touching a file outside its own partition

#### Scenario: Partition includes the paths the workload must read

- **WHEN** the orchestrator scopes a worker's sparse partition
- **THEN** the partition covers the paths the workload reads to function as well as the paths it edits
- **AND** the worker proceeds without treating absent out-of-lane files as an error

### Requirement: Sparse partitions chosen only when full-tree tooling is not required

A sparse working copy omits files, so any build, type-check, or test tooling that needs the full repository tree (cross-repo import resolution, whole-repo type-checking, a full-suite run) SHALL NOT be expected to work inside a sparsely-provisioned workspace. The orchestrator SHALL choose a sparse partition only when the worker's in-workspace verification does not require the full tree; when verification does require the full tree, the orchestrator SHALL either provision that worker full-tree (declining the sparse option) or run that verification outside the sparse workspace. The trade-off SHALL be documented in the provisioning guidance so the choice is deliberate.

#### Scenario: Full-tree verification declines the sparse option

- **WHEN** a worker's workload requires whole-repo build or test tooling to verify
- **THEN** the orchestrator provisions that worker full-tree rather than with a sparse partition, or runs that verification outside the sparse workspace
- **AND** does not expect a whole-repo build/test to succeed inside a sparse working copy

#### Scenario: Sparse option taken for self-contained lanes

- **WHEN** a worker's workload edits and verifies entirely within its own partition
- **THEN** the orchestrator MAY provision that worker with a sparse partition for hard ownership
- **AND** the partition's trade-offs are recorded in the provisioning guidance
