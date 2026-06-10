## Context

`/jj-land` merges a stack of GitHub PRs bottom-up, then runs a §5 cleanup pass. It was written assuming `gh pr merge --delete-branch` both merges and removes the head branch, and that a non-zero exit means the merge failed. In a **colocated jj↔git repo** neither assumption holds: jj keeps git HEAD detached, so `gh`'s post-merge *local*-branch step fails (`could not determine current branch`), which (a) makes the command exit non-zero despite a successful remote merge and (b) aborts before the server-side `--delete-branch`. Observed for real landing PRs #11–#13: all three merged, all three left remote-branch stragglers, and the exit codes were non-zero.

## Goals / Non-Goals

**Goals:**
- Land cleanly in a colocated jj repo: a successful merge is recognised as such, and no remote branch is left behind.
- Make remote-branch removal an explicit, observable cleanup step rather than a side effect of `gh pr merge`.
- Keep the existing safety posture: non-interactive, force-free, orchestrator-only, merged-only cleanup, never `--admin`.

**Non-Goals:**
- Changing the bottom-up order, base-retargeting, or CI-wait/abort logic (those work).
- Fixing `gh` itself or changing jj's detached-HEAD model.
- Touching `/jj-pr` / `/jj-stacked-pr` (they push + open PRs; they do not merge, so the `--delete-branch`-on-merge issue does not arise there).

## Decisions

1. **Merge result is read from PR state, not exit code.** After `gh pr merge`, confirm with `gh pr view <pr> --json state` → `MERGED`. Treat the colocated local-branch error as expected noise when state is `MERGED`; only a non-`MERGED` state is a real failure that aborts the remaining stack (§3.3 abort semantics unchanged).
2. **Drop `--delete-branch` from the merge call.** Branch removal moves entirely into §5 cleanup, so the merge step cannot be aborted by a branch-cleanup failure. Default method stays `--squash`.
3. **Explicit remote-head-branch deletion in §5, merged-only.** For each change whose PR is `MERGED`, delete the remote head branch via the GitHub API (`gh api -X DELETE repos/<owner>/<repo>/git/refs/heads/<branch>`), tolerating "already gone" (a 422/404 is success — idempotent). Resolve `<owner>/<repo>` from `gh repo view --json nameWithOwner` or the `origin` remote.
4. **§5 cleanup is a three-part merged-only pass:** (a) delete the local jj bookmark, (b) delete the remote head branch, (c) forget the linked workspace via jj-delegate Teardown when one exists. Un-merged changes are never touched.
5. **Document the gotcha** in the skill so the behaviour is expected, not surprising, for any future `gh pr merge` use under colocated jj.

## Risks / Trade-offs

- **Two-step (merge, then delete remote branch) is briefly non-atomic** — a crash between them leaves one straggler, but the cleanup is idempotent and re-runnable, and `/jj-land`'s resume-from-first-open re-run will re-sweep merged PRs' branches. Acceptable.
- **API-based ref delete needs repo scope on the `gh` token** — already required for merging; no new permission.
- **Sequencing dependency:** the `jj-land` capability must be canonical before this delta syncs (apply `jj-land` first). Called out in the proposal Impact.
