## ADDED Requirements

### Requirement: Stack-aware land in one orchestrator skill

The plugin SHALL provide an orchestrator skill `/jj-land` that, given a jj stack whose changes already have open GitHub PRs, lands the entire stack bottom-up in one invocation: for each change from trunk upward it waits for required CI, merges the PR, retargets the next PR's base, and after the loop performs a post-merge cleanup pass. The skill SHALL run only in the orchestrator role (which owns bookmarks, refs, push, and fetch) and SHALL NOT be invoked inside a worker. The skill SHALL be non-interactive (`jj … --no-pager`, `gh` with explicit flags, no editor spawn) and SHALL perform no force operations.

#### Scenario: A clean stack lands end-to-end

- **WHEN** `/jj-land` is invoked on a stack of three changes whose PRs all have green required checks
- **THEN** the three PRs are merged bottom-up, the upper PRs are retargeted as the lower ones merge, and the cleanup pass runs
- **AND** the skill returns a per-PR outcome list plus a cleanup summary

#### Scenario: Worker may not invoke land

- **WHEN** the skill is reached
- **THEN** it runs only in the orchestrator role
- **AND** it is never invoked inside a worker, because workers are forbidden from bookmark, push, ref, and fetch operations

### Requirement: Bottom-up merge order derived from the jj stack

The skill SHALL derive the merge order from the jj stack itself — the linear order of changes from trunk upward, computed via a jj revset over the stack — and SHALL map each change to its bookmark and thus its PR. It SHALL merge strictly in that bottom-up order and SHALL refuse to merge any PR before every PR beneath it in the stack has merged, even if an upper PR's checks pass first. Order SHALL be read from jj, not from each PR's GitHub `base` field.

#### Scenario: Order comes from jj, not PR metadata

- **WHEN** `/jj-land` computes its merge order
- **THEN** it derives the order from a jj revset over the stack (trunk upward), not from the PRs' `base` fields
- **AND** it merges in that order even if some PR bases were set by hand

#### Scenario: Upper PR is held until its downstack lands

- **WHEN** an upper PR's required checks pass before a lower PR's
- **THEN** the skill still merges the lower PR first
- **AND** it does not merge the upper PR until every PR beneath it has merged

### Requirement: Per-step CI wait with clean abort

Before merging each PR the skill SHALL poll that PR's GitHub checks (e.g. `gh pr checks` / `gh pr view --json statusCheckRollup,mergeStateStatus`) on an interval until the required checks reach success, then merge. On a failing required check or an elapsed per-PR wait-timeout, the skill SHALL abort the remaining stack cleanly — leaving every PR merged so far merged and every un-reached PR open — and SHALL report which step stopped the run and why. The skill SHALL NOT loop indefinitely and SHALL NOT bypass a red check by forcing or admin-merging.

#### Scenario: Required checks must pass before merge

- **WHEN** the skill reaches a PR whose required checks are still running
- **THEN** it polls until those checks succeed before merging that PR

#### Scenario: A red check aborts the rest of the stack

- **WHEN** a PR's required check fails
- **THEN** the skill stops without merging that PR or any PR above it
- **AND** PRs merged earlier in the run remain merged
- **AND** the report names the PR whose check went red

#### Scenario: Wait-timeout stops the run

- **WHEN** a PR's required checks do not reach success within the per-PR timeout
- **THEN** the skill aborts the remaining stack rather than waiting forever
- **AND** it reports the timed-out PR

### Requirement: Base retargeting as lower PRs merge

After a lower PR merges, the skill SHALL retarget the next-up PR's base to trunk via `gh pr edit <pr> --base <trunk>`, so each PR is merged against a base that still exists rather than against a branch that the lower merge has removed. Retargeting SHALL happen before the next PR's CI wait so that its checks run against the correct base. The skill SHALL report the base value it set for each retargeted PR.

#### Scenario: Next PR is retargeted to trunk after the lower one merges

- **WHEN** PR n merges and PR n+1 previously targeted PR n's head branch
- **THEN** the skill sets PR n+1's base to trunk via `gh pr edit --base` before waiting on its checks

#### Scenario: Retarget is reported, not silent

- **WHEN** the skill retargets a PR's base
- **THEN** the per-PR outcome includes the base value it set

### Requirement: Post-merge cleanup with fetch, bookmark deletion, and workspace forget

After the merge loop completes or aborts, the skill SHALL run a single cleanup pass that acts only on the PRs that actually merged: it SHALL (1) run `jj git fetch` to sync the local trunk with the merged commits; (2) delete the local bookmarks for the merged changes (`jj bookmark delete <name>`), leaving bookmarks for un-merged PRs intact; and (3) for each merged change that still has a linked jj workspace, forget that workspace by deferring to the `jj-delegate` Teardown mechanism (`jj workspace forget` + directory removal) rather than re-implementing workspace lifecycle. Cleanup SHALL NOT touch un-merged PRs, their bookmarks, or their workspaces.

#### Scenario: Trunk is synced and merged bookmarks deleted

- **WHEN** the merge loop finishes with PRs merged
- **THEN** the skill runs `jj git fetch` to bring the merged commits onto local trunk
- **AND** it deletes the local bookmarks for the merged changes only

#### Scenario: Stale workspaces are forgotten via jj-delegate teardown

- **WHEN** a merged change still has a linked jj workspace
- **THEN** the skill forgets that workspace using the jj-delegate Teardown mechanism rather than its own workspace-lifecycle logic

#### Scenario: Cleanup leaves an aborted tail intact

- **WHEN** the run aborted partway and some PRs did not merge
- **THEN** the cleanup pass deletes bookmarks and forgets workspaces only for the merged PRs
- **AND** the un-merged PRs, their bookmarks, and their workspaces are left untouched for a re-run

### Requirement: Composition with jj-github-pr without depending on it

The skill SHALL land PRs regardless of how they were opened — whether by the `jj-github-pr` capability's `/jj-pr` skill or by hand — and SHALL NOT require any in-flight change (including `jj-github-pr`) to be canonical. Its only precondition on each stacked change is that the change has an open GitHub PR for its bookmark's head branch.

#### Scenario: Lands PRs opened by /jj-pr

- **WHEN** the stack's PRs were opened by `/jj-pr`
- **THEN** `/jj-land` lands them with no additional configuration

#### Scenario: Lands hand-opened PRs

- **WHEN** the stack's PRs were opened by hand rather than by `/jj-pr`
- **THEN** `/jj-land` still lands them, requiring only that each stacked change has an open PR

### Requirement: Non-interactive, dependency-checked, force-free operation

The skill SHALL verify that `gh` is available and authenticated (e.g. `gh auth status`) before attempting any merge, and SHALL report a clear blocker when it is not rather than half-landing the stack. All commands SHALL be non-interactive (`jj … --no-pager`; `gh` with explicit flags; no editor spawn). The skill SHALL NOT pass `--admin`, SHALL NOT force-merge, and SHALL NOT override branch protection; a protection-blocked merge SHALL be reported as a blocker. Re-running `/jj-land` after a partial land SHALL skip already-merged PRs and resume from the first still-open PR.

#### Scenario: Missing or unauthenticated gh is reported before any merge

- **WHEN** `gh` is absent or not authenticated
- **THEN** the skill reports a clear blocker and merges nothing
- **AND** it does not hang on an interactive prompt

#### Scenario: Branch protection is reported, not overridden

- **WHEN** branch protection blocks a PR merge
- **THEN** the skill reports the blocker and stops
- **AND** it does not pass `--admin` or force the merge

#### Scenario: Re-run resumes from the first open PR

- **WHEN** `/jj-land` is re-run after a partial land
- **THEN** it skips the already-merged PRs and resumes from the first still-open PR, re-deriving order from the now-shorter jj stack
