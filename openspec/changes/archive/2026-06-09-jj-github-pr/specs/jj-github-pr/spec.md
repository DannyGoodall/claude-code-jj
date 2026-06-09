## ADDED Requirements

### Requirement: Push-then-PR in one orchestrator skill

The plugin SHALL provide an orchestrator skill `/jj-pr` that, given a bookmark, first pushes it with `jj git push -b <bookmark>` and then, as a distinct second step, creates or updates a GitHub pull request for that bookmark via the `gh` CLI. Because `jj git push` only moves the bookmark to the remote and never opens a PR, the PR step SHALL always be performed separately. The skill SHALL run only in the orchestrator role (which owns refs and push) and SHALL NOT be invoked inside a worker.

#### Scenario: Bookmark pushed and PR opened

- **WHEN** `/jj-pr <bookmark>` is invoked for a bookmark with no existing open PR
- **THEN** the bookmark is pushed with `jj git push -b <bookmark>`
- **AND** a GitHub PR is created via `gh` for that bookmark
- **AND** the skill returns the PR URL

#### Scenario: Push and PR are separable failures

- **WHEN** the push step succeeds but the `gh` PR step fails
- **THEN** the skill reports "pushed, PR not created" distinctly from "nothing done"
- **AND** it does not silently report overall success

### Requirement: Create or update idempotently

The skill SHALL detect whether an open PR already exists for the bookmark's head branch (via `gh`, keyed on the head branch) and SHALL create a new PR when none exists or update the existing PR's body/title when one does. Re-running `/jj-pr` for the same bookmark after follow-up commits SHALL update the existing PR rather than open a duplicate, so it is safe to call as the reconcile tail re-pushes amended work.

#### Scenario: Existing PR is updated, not duplicated

- **WHEN** `/jj-pr <bookmark>` is invoked and an open PR already exists for that head branch
- **THEN** the skill updates that PR's body/title via `gh`
- **AND** no second PR is created for the same head branch

#### Scenario: Re-run after a follow-up commit

- **WHEN** a worker amends its change, the orchestrator re-pushes, and `/jj-pr <bookmark>` is invoked again
- **THEN** the same PR is updated in place

### Requirement: Generated PR body from commits and OpenSpec proposal

The skill SHALL generate the PR body as what / why / benefit plus an optional `Fixes <issue>` line. When an OpenSpec `proposal.md` exists for the change, the body SHALL be sourced from it (mapping its **Why**, **What Changes**, and **Impact**/benefit content); otherwise the body SHALL fall back to the bookmark's commit message descriptions. The `Fixes <issue>` line SHALL be emitted only from an explicit issue argument or an issue reference already present in a commit message, and SHALL be omitted rather than guessed when no issue is known.

#### Scenario: Body sourced from the OpenSpec proposal

- **WHEN** the change has an `openspec/changes/<change>/proposal.md`
- **THEN** the PR body's what/why/benefit are derived from that proposal's sections

#### Scenario: Body falls back to commit messages

- **WHEN** no OpenSpec proposal is present for the change
- **THEN** the PR body is derived from the bookmark's commit message descriptions

#### Scenario: Fixes line is only emitted when an issue is known

- **WHEN** no issue is given as an argument and none appears in the commits
- **THEN** the PR body omits the `Fixes <issue>` line rather than inventing one

### Requirement: One-time remote tracking on a freshly colocated repo

On a freshly colocated repository a bookmark may not yet track the remote. The skill SHALL detect when the bookmark is untracked against `origin` and SHALL perform the one-time `jj bookmark track <name>@origin` before/with the push, and SHALL NOT run the track command when the bookmark already tracks `origin`.

#### Scenario: Untracked bookmark is tracked once

- **WHEN** `/jj-pr <bookmark>` runs against a bookmark not yet tracking `origin`
- **THEN** the skill runs `jj bookmark track <bookmark>@origin` so the push and subsequent pushes succeed

#### Scenario: Already-tracked bookmark is not re-tracked

- **WHEN** the bookmark already tracks `origin`
- **THEN** the skill does not run the track command again

### Requirement: Reconcile-tail push step for delegate and OpenSpec apply

The skill SHALL be usable as the reconcile-tail push step invoked by the `jj-delegate` mechanism and the `jj-openspec` apply shape after a worker's change is integrated, providing the single push-and-PR action those tails call rather than ad-hoc inline push/PR steps.

#### Scenario: Delegate reconcile tail calls the skill

- **WHEN** the `jj-delegate` orchestrator finishes integrating a worker's change and reaches its push step
- **THEN** it invokes `/jj-pr <bookmark>` to push and open/update the PR

#### Scenario: OpenSpec apply tail calls the skill

- **WHEN** the `jj-openspec` apply shape completes verification and integration
- **THEN** its reconcile tail invokes `/jj-pr <bookmark>` for the push-and-PR step

### Requirement: Non-interactive, dependency-checked operation

The skill SHALL run only non-interactive commands (`jj … --no-pager`; `gh` with explicit `--title`/`--body`/`--head`/`--base` flags; no editor spawn). It SHALL verify that `gh` is available and authenticated before attempting the PR step and SHALL report a clear blocker when it is not, distinguishing a successful push from a missing PR. The skill SHALL NOT force-push.

#### Scenario: Missing or unauthenticated gh is reported, not improvised

- **WHEN** `gh` is absent or not authenticated
- **THEN** the skill reports a clear blocker for the PR step
- **AND** it does not hang on an interactive prompt and does not force-push
