## ADDED Requirements

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
