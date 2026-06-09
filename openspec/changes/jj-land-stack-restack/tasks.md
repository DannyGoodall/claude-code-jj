## 1. Pre-merge mergeability wait (§3 of jj-land/SKILL.md)

- [ ] 1.1 Before each merge, poll `gh pr view <pr> --json mergeStateStatus,mergeable` until `mergeable=MERGEABLE` and `mergeStateStatus ∈ {CLEAN, UNSTABLE}`, bounded by `--poll-interval`/`--timeout`
- [ ] 1.2 Treat `UNKNOWN` (GitHub recomputing) as "keep polling", never as ready-to-merge; fold the existing required-CI wait into this same loop
- [ ] 1.3 On timeout still un-mergeable (`DIRTY`/`UNKNOWN`), abort the remaining stack as `blocked` (existing clean-abort semantics)

## 2. Merge method for stacks (§4 of jj-land/SKILL.md)

- [ ] 2.1 Make `--merge` the default merge method when the stack has >1 PR (single-PR land may keep `--squash`); explicit `--method` still overrides
- [ ] 2.2 Document why: merge commits preserve lower commits' identity, so upper PRs recognise already-merged lower commits and don't re-conflict on shared files

## 3. Restack after a rewriting merge (§4 of jj-land/SKILL.md)

- [ ] 3.1 When `--squash`/`--rebase` is chosen for a multi-PR stack, after each merge run `jj git fetch`, `jj rebase` the remaining stack onto the updated trunk, and `jj git push` the rewritten tail bookmarks before the next PR
- [ ] 3.2 Constrain the restack to un-merged, orchestrator-owned tail bookmarks only — never a merged change's bookmark or a branch outside the stack; no forced merge
- [ ] 3.3 Re-derive the next PR + its mergeability (§1) after the restack, so it is clean against trunk before merging

## 4. Docs / gotcha

- [ ] 4.1 Add a gotcha note to jj-land/SKILL.md: squash-rewrite vs stacked PRs sharing a file → upper PRs go CONFLICTING; the `--merge` default / restack remedy
- [ ] 4.2 Update the §6 report shape if needed to surface restack actions (tail bookmarks re-pushed)

## 5. Validation

- [ ] 5.1 Run `openspec validate jj-land-stack-restack` and resolve any issues
- [ ] 5.2 Exercise live: land a ≥2-PR shared-file stack and confirm (a) merges wait for mergeability, (b) with the `--merge` default no upper PR conflicts, and (c) under `--method squash` the post-merge restack keeps the tail clean — all with zero remote stragglers
