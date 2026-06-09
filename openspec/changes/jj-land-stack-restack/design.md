## Context

`/jj-land` lands a stack bottom-up: wait for CI → merge (`--squash` default) → retarget the next PR's base to trunk → repeat → cleanup. It assumes (a) the only pre-merge wait is CI, and (b) retargeting the base is enough to keep an upper PR mergeable. Both broke on the first real shared-file stack (PRs #16–#19): the merge raced GitHub's mergeability recompute, and squash-rewriting a lower PR left the upper siblings conflicting against trunk because their branches still carried the pre-squash history of the shared file.

## Goals / Non-Goals

**Goals:**
- A multi-PR stack whose PRs share files lands cleanly in one `/jj-land`, with no remote stragglers and no manual restack.
- Never fire a merge against a PR GitHub has not confirmed mergeable.
- Preserve the existing safety posture: bottom-up order, clean abort, merged-only cleanup, non-interactive, force-free, never `--admin`.

**Non-Goals:**
- Changing the base-retarget logic itself (still correct), the CI-gate (when CI exists), or the colocated branch-cleanup from `jj-land-colocated-cleanup` (orthogonal; both compose).
- Cross-orchestrator concerns; conflict *resolution* policy (a genuinely conflicting upper PR after a correct restack is still a reported blocker).

## Decisions

1. **Pre-merge mergeability wait (always, not just under CI).** Before merging PR *n*, poll `gh pr view <n> --json mergeStateStatus,mergeable` until `mergeable=MERGEABLE` and `mergeStateStatus ∈ {CLEAN, UNSTABLE}` (UNSTABLE = mergeable but non-required checks pending), bounded by `--poll-interval`/`--timeout`. `UNKNOWN`/`BLOCKED`/`DIRTY` keep polling; `DIRTY` past timeout aborts as `blocked`. This subsumes the CI wait (a still-running required check shows as non-CLEAN) and fixes the no-CI race.
2. **`--merge` is the default merge method for a *multi-PR* stack.** Merge commits preserve the lower PRs' commit SHAs, so once PR *n* merges, PR *n+1*'s branch (which contains those same SHAs) shows only its *own* diff against trunk — no shared-file re-conflict. A single-PR land keeps `--squash` (no stack to cascade). `--method` still overrides explicitly.
3. **Restack after each merge when a rewriting method (`--squash`/`--rebase`) is chosen for a stack.** A rewriting merge changes the lower change's trunk SHA, so the remaining stack must be rebased onto the new trunk and re-pushed before the next PR is considered: `jj git fetch` → `jj rebase -s <next> -d <trunk>` (jj rebases by change-diff, so a shared-file change re-applies cleanly) → `jj git push -b <each remaining bookmark>`. Only un-merged tail bookmarks (orchestrator-owned) are rewritten; this is the sole history rewrite and is not a force-merge.
4. **Compose, don't duplicate.** The mergeability wait extends §3; the merge-method default and restack extend §4; the remote-branch cleanup (jj-land-colocated-cleanup) is unchanged in §5.

## Risks / Trade-offs

- **`--merge` default changes trunk history shape** (merge commits vs squashed) for stacks. Accepted: it is the correct-by-construction choice for shared-file stacks; operators wanting squashed trunk pass `--method squash` and get the restack path instead.
- **Restack re-pushes tail bookmarks** (a force-update of un-merged branches). Safe: only the orchestrator's own un-merged tail, never a merged or foreign branch; jj's rebase is conflict-surfacing, not lossy.
- **Polling adds latency** before each merge. Bounded by `--timeout`; far cheaper than a half-landed stack needing manual recovery.
- **Sequencing:** depends on `jj-land` being canonical before this delta syncs (apply after `jj-land`, alongside `jj-land-colocated-cleanup`).
