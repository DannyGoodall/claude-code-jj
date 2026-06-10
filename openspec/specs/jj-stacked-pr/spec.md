# jj-stacked-pr Specification

## Purpose
TBD - created by archiving change jj-stacked-pr. Update Purpose after archive.
## Requirements
### Requirement: Derive the PR base chain from the jj stack topology

The plugin SHALL provide an orchestrator skill `/jj-stacked-pr` that, given a stitched linear jj stack — either an explicit ordered list of stacked bookmarks or a single tip bookmark whose ancestry it walks — resolves the ordered, root-first list of bookmarks from the jj stack topology (the bookmarked changes on `trunk()..<tip>`, ordered by ancestry). For that list `[A, B, C]` over trunk `T`, the skill SHALL compute each bookmark's PR base as the bookmark immediately below it, with the stack root based on trunk: `A→T`, `B→A`, `C→B`. The base chain SHALL be derived from jj topology, not from branch-name heuristics. The skill SHALL run only in the orchestrator role (which owns refs, push, and integration) and SHALL NOT be invoked inside a worker.

#### Scenario: Base chain derived for a three-change stack

- **WHEN** `/jj-stacked-pr` is invoked for a stitched stack `base → A → B → C`
- **THEN** A's PR base is the trunk branch
- **AND** B's PR base is bookmark A
- **AND** C's PR base is bookmark B

#### Scenario: Tip bookmark ancestry is walked into an ordered list

- **WHEN** `/jj-stacked-pr` is invoked with only the tip bookmark of the stack
- **THEN** the skill resolves the ordered root-first list of stacked bookmarks from the jj ancestry
- **AND** computes each base from list position

### Requirement: Linear stack asserted before any PR is touched

The skill SHALL verify that the resolved ancestry is a single linear chain before opening or updating any PR. If the selection is non-linear (a fork where one change has two children), gapped, or includes a bookmark outside `trunk()..<tip>`, the skill SHALL report the offending topology and stop without creating, updating, or re-basing any PR, rather than guessing a base.

#### Scenario: Non-linear stack is reported, not guessed

- **WHEN** the resolved set of stacked bookmarks does not form a single linear chain
- **THEN** the skill reports the non-linear topology and stops
- **AND** it does not create, update, or re-base any GitHub PR

### Requirement: One PR per bookmark based on its parent, composed over the per-bookmark primitive

For each bookmark in the ordered list, processed bottom-up (root first), the skill SHALL perform the per-bookmark push-and-PR step with that bookmark's computed base — conceptually `/jj-pr <bookmark> --base <parent>` — so that pushing, one-time remote tracking, create-or-update PR detection, and PR-body generation are inherited from the per-bookmark primitive rather than reimplemented. Processing SHALL be bottom-up so each PR's base branch is pushed before the child PR references it. The result SHALL be one GitHub PR per bookmark, each targeting its parent bookmark (the root targeting trunk).

#### Scenario: Each PR targets its parent bookmark

- **WHEN** `/jj-stacked-pr` opens PRs for the stack `base → A → B → C`
- **THEN** A's PR targets trunk, B's PR targets A, and C's PR targets B
- **AND** each push-and-PR step is the per-bookmark primitive, not a reimplementation

#### Scenario: Bottom-up ordering so a base branch exists before its child PR

- **WHEN** the skill creates the PRs for a fresh stack
- **THEN** it pushes and PR-creates from the root upward
- **AND** a child PR is created only after its parent bookmark has been pushed, so GitHub does not reject the `--base`

### Requirement: Cross-reference stack-navigation comment maintained in place

The skill SHALL maintain, on every PR in the stack, a single cross-reference comment containing the full ordered stack — each bookmark, its PR link, and a marker indicating which PR is the current one. The comment SHALL be wrapped in a stable delimiter (e.g. a marker comment pair) so that re-running `/jj-stacked-pr` updates the existing comment in place on each PR rather than appending a duplicate. A PR with no existing stack comment SHALL receive a new one; a PR with one SHALL have it edited.

#### Scenario: Every PR gets the ordered stack with a "you are here" marker

- **WHEN** the stack's PRs are opened
- **THEN** each PR carries a comment listing every bookmark in order with its PR link
- **AND** the current PR is marked within that list

#### Scenario: Re-run updates the comment in place, not duplicated

- **WHEN** `/jj-stacked-pr` is re-run for the same stack
- **THEN** the existing marker-delimited stack comment on each PR is edited in place
- **AND** no second stack comment is appended

### Requirement: Re-point PR bases when the stack is rebased

When the stack is rebased — a lower change amended, the stack reordered, or a change dropped — re-running `/jj-stacked-pr` SHALL re-resolve the ordered bookmark list from the current jj stack, recompute every base, and for each surviving PR whose base changed SHALL update it via `gh pr edit --base <new-parent>`, leaving unchanged bases untouched. The cross-reference comment SHALL be regenerated from the new order on every PR. A bookmark that has left the stack SHALL be reported as an orphaned PR for the orchestrator to handle and SHALL NOT be auto-closed by the skill.

#### Scenario: Reordered stack re-points bases idempotently

- **WHEN** the stack is reordered and `/jj-stacked-pr` is re-run
- **THEN** each PR whose parent changed has its base updated to the new parent bookmark
- **AND** PRs whose base is unchanged are not edited
- **AND** the cross-reference comment is regenerated from the new order

#### Scenario: Dropped change leaves a reported orphan, not an auto-close

- **WHEN** a change is dropped from the stack and `/jj-stacked-pr` is re-run
- **THEN** the PR for the dropped bookmark is reported as orphaned
- **AND** the skill does not automatically close it

### Requirement: Non-interactive, dependency-checked, report-shaped operation

The skill SHALL run only non-interactive commands (`jj … --no-pager`; `gh` with explicit flags such as `--base`, `--head`, `--json`, `--body`/`--body-file`; no editor spawn). It SHALL rely on the per-bookmark primitive's `gh` availability/authentication preflight and SHALL degrade clearly — reporting "PRs opened, stack comment not posted" distinctly — when the comment surface is unavailable, rather than failing the whole stack or hanging on a prompt. The skill SHALL return the ordered list of bookmark → PR URL → base, plus any rebase re-point actions taken.

#### Scenario: Comment surface unavailable degrades, does not fail the stack

- **WHEN** the PRs are opened but the stack-comment step cannot post
- **THEN** the skill reports "PRs opened, stack comment not posted" distinctly
- **AND** it does not hang on an interactive prompt and does not abandon the opened PRs

#### Scenario: Report surfaces the whole stack

- **WHEN** `/jj-stacked-pr` completes
- **THEN** it returns each bookmark with its PR URL and base
- **AND** any base re-point actions taken on a rebase re-run

