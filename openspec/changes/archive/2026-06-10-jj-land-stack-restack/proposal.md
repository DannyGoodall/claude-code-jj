## Why

Landing the v0.6.0 workspace batch (PRs #16–#19) was `/jj-land`'s first run on a real stack whose PRs **share a file** (`worktreeinclude` and `sparse` both edit `jj-delegate/SKILL.md §3`). Two gaps surfaced:

1. **No mergeability-recompute wait.** With no required CI, `/jj-land` proceeds straight to merge. But after it retargets PR *n+1*'s base to trunk (and PR *n* merges), GitHub recomputes *n+1*'s mergeability **asynchronously**. The merge fired against a `mergeStateStatus=UNKNOWN` PR and no-op'd, leaving the PR open. The skill only waits for *CI checks*, not for *mergeability*.

2. **Squash + shared-file stacked PRs cascade-conflict.** `/jj-land` defaults to `--squash`, which **rewrites** the merged PR into one new trunk commit. The PRs above still contain the original commits; when a lower PR shares a file with an upper one, the upper PR then shows `CONFLICTING/DIRTY` against trunk (git can't reconcile the squashed trunk with the branch's un-squashed history). Retargeting the base does **not** fix this — the branch content itself is stale. Recovery required a manual restack: `jj git fetch` → `jj rebase` the remaining stack onto the new trunk → `jj git push` the updated bookmarks → merge the rest with `--merge`.

Both are real `/jj-land` correctness gaps for any non-trivial shared-file stack.

## What Changes

- `/jj-land` **waits for mergeability, not just CI**: before each merge it polls `gh pr view --json mergeStateStatus,mergeable` until the PR is actually mergeable (`CLEAN`/`UNSTABLE` + `MERGEABLE`), bounded by the same `--timeout`. This covers the no-CI case where the only thing to wait for is GitHub's post-retarget recompute.
- `/jj-land` **keeps the stack landable after each merge** instead of only retargeting the base. Two supported strategies, with a safe default:
  - **`--merge` is the default for a multi-PR stack** (preserves commit identity, so an upper PR's already-merged lower commits are recognised and never re-conflict);
  - when `--squash`/`--rebase` is explicitly chosen for a stack, after each merge `/jj-land` **restacks**: `jj git fetch`, `jj rebase` the remaining stack onto the updated trunk, and `jj git push` the rewritten bookmarks, so the upper PRs become clean against trunk before they are merged.
- A **gotcha note** documents the squash-rewrite-vs-stacked-PR hazard and the restack remedy.

All steps stay non-interactive, force-free (bookmark re-push after a jj rebase is the only history rewrite, and only on un-merged tail bookmarks the orchestrator owns), orchestrator-only; never `--admin`.

## Capabilities

### Modified Capabilities
- `jj-land`: add a pre-merge mergeability wait; make `--merge` the default merge method for multi-PR stacks; and, when a rewriting method is chosen, restack-and-repush the remaining stack after each merge so upper PRs stay clean against trunk.

## Impact

- Spec/skill: `plugins/jj-concurrent/skills/jj-land/SKILL.md` (§3 wait, §4 merge method/default, a new restack step, gotchas).
- **Sequencing:** the `jj-land` capability is not yet canonical (the `jj-land` change is unarchived); like `jj-land-colocated-cleanup`, this delta should sync after `jj-land` archives. Apply order within the family: `jj-land` → `jj-land-colocated-cleanup` → `jj-land-stack-restack`.
- Discovered landing PRs #16–#19 (recovered by hand; this change encodes that recovery into the skill).
