# jj-land Specification

## Purpose
TBD - created by archiving change jj-land. Update Purpose after archive.
## Requirements
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

### Requirement: Merge success is determined by PR state, not command exit code
The skill SHALL confirm a PR has merged by reading `gh pr view <pr> --json state` and checking for `MERGED`, and SHALL NOT treat a non-zero `gh pr merge` exit code as a merge failure when the PR state is `MERGED`. Under a colocated jj↔git repo git HEAD is detached, so `gh`'s post-merge local-branch step fails and returns non-zero even though the remote merge succeeded; that error MUST NOT abort the remaining stack.

#### Scenario: Colocated merge succeeds despite a non-zero gh exit
- **WHEN** `/jj-land` merges a PR in a colocated jj repo and `gh pr merge` exits non-zero with "could not determine current branch: failed to run git: not on any branch"
- **THEN** the skill reads `gh pr view <pr> --json state`, observes `MERGED`, and continues landing the stack rather than aborting

#### Scenario: A genuinely unmerged PR still aborts
- **WHEN** after `gh pr merge` the PR state is not `MERGED`
- **THEN** the skill treats it as a real failure and aborts the remaining stack per the existing abort semantics

### Requirement: Merge step omits server-side branch deletion
The merge step SHALL invoke `gh pr merge` WITHOUT `--delete-branch`, so a branch-cleanup failure can never abort the merge; branch removal MUST happen in the cleanup pass instead. The default merge method remains `--squash`, and the skill MUST NOT pass `--admin` or force a merge.

#### Scenario: Merge does not depend on --delete-branch
- **WHEN** `/jj-land` merges a PR
- **THEN** it runs `gh pr merge <pr> --squash` (no `--delete-branch`), and the head branch is removed later by the cleanup pass

### Requirement: Cleanup deletes the remote head branch for every merged PR
For each change whose PR is `MERGED`, the cleanup pass SHALL delete that PR's remote head branch (for example `gh api -X DELETE repos/<owner>/<repo>/git/refs/heads/<branch>`, with `<owner>/<repo>` resolved from `gh repo view` or the `origin` remote), so no remote stragglers remain on `origin`. An already-absent branch (404/422) MUST be treated as success so the step is idempotent and re-runnable.

#### Scenario: No remote stragglers after a land
- **WHEN** `/jj-land` finishes landing a stack in a colocated repo
- **THEN** every merged PR's remote head branch has been deleted, leaving only the trunk branch for those changes

#### Scenario: Remote-branch delete is idempotent
- **WHEN** the cleanup attempts to delete a remote head branch that is already gone
- **THEN** the resulting 404/422 is treated as success and the cleanup continues without error

### Requirement: Three-part merged-only cleanup
The cleanup pass SHALL, for each merged change, delete its local jj bookmark, delete its remote head branch, and forget its linked jj workspace via the jj-delegate Teardown mechanism when one exists. The pass MUST act on merged changes only and MUST leave un-merged changes' bookmarks, remote branches, and workspaces untouched.

#### Scenario: Aborted land leaves the tail intact
- **WHEN** a land aborts partway and only the lower PRs merged
- **THEN** cleanup removes only the merged changes' bookmarks, remote branches, and workspaces, and leaves the un-merged tail fully intact for a re-run

### Requirement: Wait for mergeability before each merge
Before merging a PR, the skill SHALL poll `gh pr view <pr> --json mergeStateStatus,mergeable` until the PR is genuinely mergeable (`mergeable` is `MERGEABLE` and `mergeStateStatus` is `CLEAN` or `UNSTABLE`), bounded by the configured poll interval and timeout. It SHALL NOT fire a merge against a PR whose `mergeStateStatus` is `UNKNOWN` (GitHub still recomputing). This wait applies even when there are no required CI checks, so the skill never races GitHub's asynchronous mergeability recompute after a base retarget.

#### Scenario: No-CI PR is merged only once GitHub confirms mergeable
- **WHEN** a PR has no required checks and its base was just retargeted to trunk, so `mergeStateStatus` is briefly `UNKNOWN`
- **THEN** the skill polls until `mergeable=MERGEABLE` and `mergeStateStatus=CLEAN` before merging, rather than merging immediately and no-opping

#### Scenario: Persistently un-mergeable PR aborts on timeout
- **WHEN** a PR stays `DIRTY`/`UNKNOWN` past the configured timeout
- **THEN** the skill aborts the remaining stack as `blocked`, leaving merged PRs merged and the tail open (existing clean-abort semantics)

### Requirement: Default to --merge for a multi-PR stack
For a stack of more than one PR, the default merge method SHALL be `--merge` (preserving each PR's commit identity), so that once a lower PR merges, an upper PR's already-merged lower commits are recognised and the upper PR shows only its own diff — never a shared-file re-conflict. A single-PR land MAY keep `--squash`. An explicit `--method` argument always overrides the default.

#### Scenario: Shared-file stack lands without cascade conflicts
- **WHEN** a stack's PRs touch a shared file and the default method is used
- **THEN** each PR is merged with `--merge`, and merging a lower PR does NOT make the upper PRs conflict against trunk

### Requirement: Restack the remaining stack after a rewriting merge
When a rewriting merge method (`--squash` or `--rebase`) is explicitly chosen for a multi-PR stack, after each merge the skill SHALL bring the remaining stack up to date before considering the next PR: `jj git fetch` to sync trunk, `jj rebase` the still-un-merged stack onto the updated trunk, and `jj git push` the rewritten tail bookmarks. Only un-merged, orchestrator-owned tail bookmarks are rewritten; merged changes and foreign branches are never touched, and no merge is forced.

#### Scenario: Squash-merge of a shared-file stack restacks the tail
- **WHEN** `--method squash` is chosen and the bottom PR (sharing a file with an upper PR) is merged
- **THEN** the skill fetches, rebases the remaining stack onto the new trunk, and re-pushes the tail bookmarks, so the next PR is clean against trunk before it is merged

#### Scenario: Restack rewrites only the un-merged tail
- **WHEN** the post-merge restack runs
- **THEN** it rebases and re-pushes only the still-open tail bookmarks, never a merged change's bookmark or a branch outside this stack

