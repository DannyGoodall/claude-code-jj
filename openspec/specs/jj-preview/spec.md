# jj-preview Specification

## Purpose
TBD - created by archiving change jj-preview-skill. Update Purpose after archive.
## Requirements
### Requirement: Orchestrator-only preview skill

The `/jj-preview <rev>` skill SHALL be invoked only by the orchestrator and SHALL NOT be invoked inside a worker. It SHALL require a jj repository (ideally colocated with git) and SHALL accept exactly one revision argument: a commit id, a change id, or a bookmark name resolvable by jj.

#### Scenario: Invoked with a resolvable revision

- **WHEN** the orchestrator invokes `/jj-preview <rev>` with a revision that jj can resolve
- **THEN** the skill proceeds to provision a throwaway preview workspace at that revision

#### Scenario: Invoked with an unresolvable revision

- **WHEN** the operator passes a revision that jj cannot resolve to a single commit
- **THEN** the skill reports the resolution failure naming the revision and provisions nothing

#### Scenario: Invoked inside a worker

- **WHEN** a worker agent attempts to invoke `/jj-preview`
- **THEN** the skill is out of contract for that context and SHALL NOT be used; only the orchestrator owns workspace provisioning and teardown

### Requirement: Throwaway workspace at the target revision, history untouched

The skill SHALL provision a throwaway jj workspace at the target revision using `jj workspace add -r <rev> ../wt-preview-<slug>`. It SHALL be read-only with respect to history: it SHALL NOT rebase `@`, SHALL NOT move any bookmark, SHALL NOT push, and SHALL NOT archive. The working copy `@` and all bookmarks/refs SHALL be left exactly as they were before invocation.

#### Scenario: Preview leaves the working copy undisturbed

- **WHEN** the skill provisions a preview workspace at `<rev>`
- **THEN** the orchestrator's working copy `@` points at the same commit it did before, and no bookmark, ref, or commit in history has been moved, pushed, or archived

#### Scenario: Preview workspace materialises the target revision

- **WHEN** the skill runs `jj workspace add -r <rev> ../wt-preview-<slug>`
- **THEN** the new workspace's working copy reflects the contents of `<rev>` without rebasing or otherwise mutating `@`

### Requirement: Per-workspace environment provisioning for the preview

The skill SHALL provision the preview workspace's environment by copying the gitignored files the app needs to run (for example `.env` and local config) into the preview directory. It SHALL compose with the existing per-workspace-environment worktree-include convention where that convention is available, reusing it rather than inventing a separate copy mechanism.

#### Scenario: Gitignored files are present for a real run

- **WHEN** the skill provisions a preview workspace for a project that keeps `.env` / local config out of version control
- **THEN** those gitignored files are copied into the preview workspace so the app can actually run

#### Scenario: Worktree-include convention is reused when present

- **WHEN** the project declares a worktree-include convention for per-workspace environment files
- **THEN** the skill composes with that convention to populate the preview workspace rather than defining a new include mechanism

### Requirement: Distinct port assignment

The skill SHALL assign a distinct port to the preview, reusing the orchestrator's existing "assign a port per worker that runs the app" convention, so that the preview does not collide with any live worker or any other concurrent preview.

#### Scenario: Concurrent previews do not collide

- **WHEN** more than one preview (or a preview alongside a running worker app) is active at once
- **THEN** each is assigned a distinct port via the existing port-assignment convention and none collides with another

### Requirement: Run the dev/app command and report URL + PID

The skill SHALL run the project's dev/app command inside the preview workspace on the assigned port and SHALL report back to the operator the URL at which the preview is reachable and the PID of the running process.

#### Scenario: Preview is reported as a reachable URL and PID

- **WHEN** the dev/app command starts successfully in the preview workspace
- **THEN** the skill reports the preview URL (host + assigned port) and the process PID to the operator

#### Scenario: Dev/app command fails to start

- **WHEN** the project's dev/app command fails to start in the preview workspace
- **THEN** the skill reports the failure to the operator rather than reporting a URL, and leaves the workspace available for inspection or teardown

### Requirement: Clean teardown

The skill SHALL provide clean teardown of a preview: stopping the running preview process, running `jj workspace forget` for the preview workspace, and removing the throwaway directory. Teardown SHALL never delete or mutate the repository `.jj` (or `.git`) state.

#### Scenario: Operator tears down a preview

- **WHEN** the operator requests teardown of an active preview
- **THEN** the skill stops the preview process, runs `jj workspace forget` for that workspace, and removes the throwaway `../wt-preview-<slug>` directory, leaving the repository `.jj`/`.git` untouched

