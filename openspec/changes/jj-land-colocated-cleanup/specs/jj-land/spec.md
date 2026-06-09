## ADDED Requirements

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
