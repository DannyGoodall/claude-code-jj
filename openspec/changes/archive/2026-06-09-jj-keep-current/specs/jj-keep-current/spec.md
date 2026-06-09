## ADDED Requirements

### Requirement: Orchestrator-only currency check

The `/jj-keep-current` skill SHALL run only in the orchestrator role (the primary jj workspace) because every operation it performs — `jj git fetch`, `jj rebase`, `jj git push`, and reading PR/CI status — is reserved to the orchestrator. A worker SHALL NOT invoke it.

#### Scenario: Worker does not run keep-current

- **WHEN** a workspace worker considers landing its own stack
- **THEN** it does not run `/jj-keep-current` itself
- **AND** fetch, rebase, push, and CI reads are performed by the orchestrator

### Requirement: CI gate blocks land unless required checks are green

The skill SHALL query the pull request's CI status via the `gh` CLI and gate landing on it. When required checks are configured, the gate SHALL evaluate the required checks (`gh pr checks <ref> --required`); when none are marked required, it SHALL fall back to all checks. Any failed or errored check SHALL produce a not-landable verdict with reason `ci-failing`. Any pending or queued check SHALL produce a hold verdict with reason `ci-pending`. All checks succeeding SHALL produce a green gate. The gate SHALL be green only when at least one check exists and all evaluated checks succeed.

#### Scenario: All required checks green

- **WHEN** the PR's required checks all report success
- **THEN** the CI gate is green
- **AND** the verdict is eligible to be landable (subject to currency)

#### Scenario: A required check is failing

- **WHEN** any evaluated check reports failure or error
- **THEN** the verdict is not-landable with reason `ci-failing`
- **AND** no land may proceed

#### Scenario: Checks still running

- **WHEN** any evaluated check is pending or queued
- **THEN** the verdict is a hold with reason `ci-pending`

### Requirement: Missing CI is surfaced, never treated as green

When the pull request has zero CI checks, the gate SHALL return a verdict with reason `ci-missing` rather than reporting green. The skill SHALL NOT treat the absence of checks as a passing gate.

#### Scenario: No checks configured

- **WHEN** the PR reports no CI checks at all
- **THEN** the verdict reason is `ci-missing`
- **AND** the gate is not reported as green

### Requirement: Trunk-movement detection with no-op fast path

The skill SHALL detect whether trunk has moved by running `jj git fetch` for the trunk bookmark and comparing the stack's base revision against the freshly-fetched trunk tip. The trunk bookmark SHALL be a resolved input (configuration or argument), not hardcoded. When the stack base already equals the fetched trunk tip, the skill SHALL skip the rebase and push steps entirely.

#### Scenario: Trunk has not moved

- **WHEN** the fetched trunk tip equals the stack's current base
- **THEN** the skill skips rebase and push
- **AND** proceeds directly to the CI gate

#### Scenario: Trunk has moved

- **WHEN** the fetched trunk tip differs from the stack's base
- **THEN** the skill proceeds to rebase the stack onto the new trunk tip

### Requirement: Never-halt auto-rebase onto the new trunk

When trunk has moved, the skill SHALL rebase the stack onto the fetched trunk tip with `jj rebase`. The rebase SHALL always succeed (exit 0) — inheriting the `jj-delegate` "Integration never halts" invariant — recording any conflict as a first-class conflicted change rather than halting. The skill SHALL NOT invoke interactive `jj resolve` and SHALL NOT silently resolve conflicts.

#### Scenario: Clean rebase onto moved trunk

- **WHEN** the stack rebases onto the new trunk tip without conflict
- **THEN** the rebase exits 0 and the stack is clean on the new base
- **AND** the skill proceeds to push the updated stack

#### Scenario: Conflicting rebase produces a first-class object

- **WHEN** the rebase produces one or more conflicted changes
- **THEN** the rebase still exits 0 and the conflicts are recorded as first-class conflicted changes
- **AND** no interactive resolution is invoked

### Requirement: A conflicted rebase blocks land and is reported

When the rebase produces any conflicted change, the skill SHALL produce a not-landable verdict with reason `rebase-conflicted`, SHALL report the conflicted change-ids and the conflicting file paths, and SHALL NOT push the conflicted stack.

#### Scenario: Conflicted stack is reported, not pushed

- **WHEN** the rebase leaves one or more conflicted changes
- **THEN** the verdict is not-landable with reason `rebase-conflicted`
- **AND** the conflicted change-ids and file paths are reported
- **AND** the stack is not pushed

### Requirement: Push the rebased stack after a clean rebase

After a conflict-free rebase onto a moved trunk, the skill SHALL push the moved bookmark(s) via `jj git push` so the pull request rebuilds against the new trunk.

#### Scenario: Updated stack is pushed

- **WHEN** the rebase onto the moved trunk is conflict-free
- **THEN** the moved bookmark(s) are pushed to the remote
- **AND** the PR head reflects the new base

### Requirement: Bounded CI re-check loop after push

After pushing a rebased stack, the skill SHALL re-run the CI gate against the new head. While the gate is `ci-pending`, the skill SHALL poll at a configurable interval up to a configurable maximum number of attempts, then return the last gate result. The re-check loop SHALL be bounded and SHALL NOT wait indefinitely.

#### Scenario: Re-check waits for a freshly-triggered run

- **WHEN** the push triggers a new CI run that is initially pending
- **THEN** the skill polls the gate at the configured interval up to the configured maximum attempts
- **AND** returns the gate result once non-pending or once the attempt budget is exhausted

#### Scenario: Re-check loop is bounded

- **WHEN** checks remain pending past the maximum attempts
- **THEN** the skill returns a `ci-pending` hold verdict rather than waiting indefinitely

### Requirement: Single landable / not-landable verdict with a typed reason

The skill SHALL emit exactly one verdict for the stack: **landable** when the stack is current with trunk and the CI gate is green, otherwise **not-landable** (or a hold) carrying a typed reason from the set `trunk-moved`, `rebase-conflicted`, `ci-failing`, `ci-pending`, `ci-missing`. The verdict SHALL be the skill's primary output for callers (a human or a land flow) to consume.

#### Scenario: Current and green is landable

- **WHEN** the stack base equals the fetched trunk tip (or was cleanly rebased and pushed) and the CI gate is green
- **THEN** the verdict is landable

#### Scenario: Not current or not green is not landable

- **WHEN** the stack is conflicted, red, pending, or has missing CI
- **THEN** the verdict is not-landable (or a hold) carrying the corresponding typed reason

### Requirement: Composition with /jj-land without depending on it

The `/jj-keep-current` capability SHALL be usable and testable independently of the in-flight `/jj-land` (D4). It SHALL expose its verdict so that a land flow can consult it and refuse to land on anything but a landable verdict, but it SHALL NOT require `/jj-land` to exist and SHALL NOT depend on any in-flight change being canonical.

#### Scenario: Used standalone

- **WHEN** `/jj-keep-current` is invoked without any land skill present
- **THEN** it completes and returns its verdict
- **AND** it does not error on the absence of `/jj-land`

#### Scenario: Consulted by a land flow

- **WHEN** a land flow consults `/jj-keep-current` before landing
- **THEN** it lands only on a landable verdict
- **AND** declines on any not-landable or hold verdict
