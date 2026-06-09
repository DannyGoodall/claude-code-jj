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

Provisioning MAY additionally scope the worker's working copy to a declared **sparse partition** — creating the workspace already-narrowed (e.g. `jj workspace add --sparse-patterns empty`, then `jj sparse set --clear --add <glob...>` to declare the lane's paths). When a sparse partition is given, only the matching paths SHALL materialise on disk in that workspace; files outside the partition SHALL NOT be present, so the worker physically cannot read or edit them. Sparse provisioning SHALL be optional and per-worker: when no sparse partition is given, the workspace materialises the full working tree exactly as before. The base-revision seed-intent rule above SHALL be unaffected by the sparse choice — the partition governs *which files materialise*, never *which revision the workspace starts from*.

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

### Requirement: Seed gitignored workload files from the worktree-include declaration

The orchestrator SHALL, after provisioning a worker workspace with `jj workspace add`, seed the gitignored files the workload needs by reading the repository's declarative worktree-include list — the same convention Claude Code uses to copy selected gitignored files into a newly commissioned git worktree — and copying exactly the paths it declares into the new workspace. The orchestrator SHALL NOT copy gitignored files ad hoc on a per-file basis when such a declaration exists.

Resolution SHALL be deterministic and follow this order, using the first source
present:
1. a repository-root worktree-include file (gitignore-style, newline-separated
   path globs), then
2. the worktree copy-list key in `.claude/settings.json`.

Each declared entry SHALL be interpreted as a path glob resolved relative to the
repository root, and matched files SHALL be copied into the new workspace
preserving their path relative to the repository root.

The orchestrator SHALL apply the following safety bounds:
- only copy paths that resolve inside the repository root (never escape it);
- never copy version-control internals (`.jj/`, `.git/`);
- report any declared path that matches nothing, rather than silently skipping
  it, so a missing required input is visible at provisioning time.

#### Scenario: Declared gitignored files are seeded into the new workspace

- **WHEN** the orchestrator provisions a worker workspace and a worktree-include
  declaration lists gitignored paths the workload needs (e.g. `.env.local`)
- **THEN** the orchestrator reads that declaration once and copies exactly the
  declared paths into the new workspace, preserving their relative layout
- **AND** it does not issue ad-hoc per-file copies outside the declaration

#### Scenario: Resolution order is deterministic

- **WHEN** both a repository-root worktree-include file and a worktree copy-list
  key in `.claude/settings.json` are present
- **THEN** the orchestrator uses the repository-root include file as the
  authoritative source and does not also apply the settings copy-list

#### Scenario: A declared but missing path is reported, not silently dropped

- **WHEN** the worktree-include declaration lists a path that matches no file in
  the repository
- **THEN** the orchestrator reports the missing declared path at provisioning
  time rather than silently continuing

### Requirement: Fallback to explicit copy when no include declaration exists

The orchestrator SHALL, when the repository has no worktree-include declaration (neither a repository-root include file nor a worktree copy-list in `.claude/settings.json`), fall back to the prior behaviour of copying the specific gitignored files the workload needs explicitly (e.g. `cp .env.local <workspace-path>/`). The absence of a declaration SHALL NOT block provisioning and SHALL NOT regress existing flows.

#### Scenario: No declaration present

- **WHEN** the orchestrator provisions a worker workspace in a repository with no
  worktree-include declaration
- **THEN** provisioning proceeds and the orchestrator copies the needed gitignored
  files explicitly, as before, without error

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

