## ADDED Requirements

### Requirement: Automated amend-after-review loop in one orchestrator skill

The plugin SHALL provide an orchestrator skill `/jj-pr-fixup` that, given a GitHub PR (number or URL), reads that PR's review comments via the `gh` CLI, dispatches a worker to address them in a workspace based on the PR head, lands the worker's fixes into their owning downstack commits, and re-pushes to update the same PR. The skill SHALL run only in the orchestrator role (which owns workspace lifecycle, refs, and push) and SHALL NOT be invoked inside a worker. Every command SHALL run non-interactively (`jj … --no-pager`; no editor or `-i` flow).

#### Scenario: Full loop on a PR with review comments

- **WHEN** `/jj-pr-fixup <pr>` is invoked for a PR that has unresolved review comments
- **THEN** the skill reads the review comments via `gh`, dispatches a worker based on the PR head, absorbs the worker's fixes into their owning commits, and updates the same PR
- **AND** it returns the updated PR URL together with where the fixes landed

#### Scenario: No actionable comments is reported, not improvised

- **WHEN** `/jj-pr-fixup <pr>` is invoked for a PR whose review comments are all resolved or outdated
- **THEN** the skill reports that there are no actionable comments and makes no commits, no absorb, and no push
- **AND** it does not dispatch a worker against an empty brief

### Requirement: Review comments mapped to a worker brief

The skill SHALL fetch the PR's review comments — file/line-anchored review threads and the review summary — via `gh`, exclude resolved and outdated threads, and compose the remaining items into a single worker brief. The brief SHALL preserve each comment's file path, line/anchor, and body so the worker can locate and address each item, and SHALL name the workspace path and the base revision. The skill SHALL NOT delegate this filtering to the worker.

#### Scenario: Unresolved comments become the brief

- **WHEN** the PR has three unresolved line-anchored review comments and one resolved thread
- **THEN** the composed worker brief contains the three unresolved comments with their file/line/body preserved
- **AND** the resolved thread is excluded

#### Scenario: gh cannot read review comments

- **WHEN** `gh` is absent, unauthenticated, or lacks permission to read the PR's review comments
- **THEN** the skill reports a clear blocker for the comment-fetch step
- **AND** it does not proceed with an empty brief as if there were no comments

### Requirement: Worker based on the PR head revision

Provisioning the fixup worker SHALL resolve the PR head branch to a local jj revision (fetching it when needed) and provision with `jj workspace add -r <pr-head-rev> <path>`, so the worker's fixes apply on top of exactly the commits under review, per the `jj-delegate` explicit-base-revision rule. The skill SHALL report a clear blocker when the PR head cannot be resolved to a local revision, before provisioning any workspace.

#### Scenario: Worker provisioned on the PR head

- **WHEN** `/jj-pr-fixup <pr>` resolves the PR head to a local revision
- **THEN** the worker workspace is created with `jj workspace add -r <pr-head-rev> <path>`
- **AND** the worker's fixes apply on top of the commits under review

#### Scenario: PR head not resolvable locally

- **WHEN** the PR head branch cannot be resolved or fetched to a local jj revision
- **THEN** the skill reports a clear blocker and provisions no workspace

### Requirement: Fixes absorbed into their owning commits

After the worker reports, the skill SHALL land the worker's working-copy fixes into their owning downstack commits via the `/jj-absorb` step (jj's `jj absorb`), so each fix lands in the commit a reviewer commented on rather than as a new tip commit. Any hunk with no unambiguous downstack home SHALL be surfaced for deliberate placement per `/jj-absorb`'s remainder handling, and SHALL NOT be force-fitted or silently pushed as a tip commit.

#### Scenario: Each fix lands in the commit it belongs to

- **WHEN** the worker's fixes correspond to lines last touched by distinct downstack commits
- **THEN** the skill absorbs each hunk into the commit that last touched those lines
- **AND** it reports which fix landed in which commit

#### Scenario: Ambiguous fix is surfaced, not force-fitted

- **WHEN** a worker fix has no unambiguous downstack home
- **THEN** the skill surfaces that hunk for deliberate placement (per `/jj-absorb` remainder handling)
- **AND** it does not push it as a new tip commit

### Requirement: PR updated in place after the fixup

Once fixes are absorbed the skill SHALL re-push and update the existing PR via the `/jj-pr` push-and-PR step, so the PR is updated in place with the amended commits rather than duplicated. The skill SHALL NOT open a second PR for the same head branch and SHALL NOT force-push beyond what the `/jj-pr` step performs.

#### Scenario: Existing PR is updated, not duplicated

- **WHEN** fixes have been absorbed for a PR that is already open
- **THEN** the skill invokes the `/jj-pr` push-and-PR step to update that same PR in place
- **AND** no second PR is created for the same head branch

#### Scenario: Push step failure is reported distinctly

- **WHEN** absorb succeeds but the `/jj-pr` push-and-update step fails
- **THEN** the skill reports "fixes absorbed, PR not updated" distinctly from overall success
- **AND** it does not silently report the loop as complete

### Requirement: Composition over reimplementation and orchestrator-role contract

The skill SHALL delegate the hunk-landing step to the `/jj-absorb` skill (capability `jj-absorb-fixup`) and the push-and-update step to the `/jj-pr` skill (capability `jj-github-pr`), defining itself only the comment→brief mapping, the PR-head basing, and the orchestration that strings the pieces together. Because those skills are in-flight, the skill SHALL preflight-check that they (and an authenticated `gh`) are available and report a clear blocker when absent rather than open-coding their behaviour. The dispatched worker SHALL only address comments inside its workspace and SHALL NOT operate on bookmarks, push, or run raw mutating git, per the `jj-delegate` role split.

#### Scenario: Missing composed skill is reported, not open-coded

- **WHEN** the `/jj-absorb` or `/jj-pr` skill is not available in the session
- **THEN** the skill reports a clear blocker for that step
- **AND** it does not substitute an open-coded absorb or push

#### Scenario: Worker stays within its role

- **WHEN** the fixup worker addresses the review comments in its workspace
- **THEN** it shapes only its own commits within that workspace
- **AND** all absorb, ref, push, and PR-update operations are performed by the orchestrator
