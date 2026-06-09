## 1. Merge step (§4 of jj-land/SKILL.md)

- [x] 1.1 Change the merge invocation to `gh pr merge <pr> --squash` (drop `--delete-branch`); keep `--method` configurable, never `--admin`/force
- [x] 1.2 After merging, confirm success via `gh pr view <pr> --json state` → `MERGED`; treat a non-zero `gh pr merge` exit as non-fatal when state is `MERGED`
- [x] 1.3 Only a non-`MERGED` state aborts the remaining stack (existing §3.3 abort semantics unchanged)

## 2. Cleanup step (§5 of jj-land/SKILL.md)

- [x] 2.1 Resolve `<owner>/<repo>` once (e.g. `gh repo view --json nameWithOwner` or the `origin` remote)
- [x] 2.2 For each merged change, delete its remote head branch via `gh api -X DELETE repos/<owner>/<repo>/git/refs/heads/<branch>`, treating 404/422 (already gone) as success
- [x] 2.3 Keep the existing local-bookmark delete and jj-delegate Teardown workspace-forget; make §5 an explicit three-part merged-only pass (local bookmark + remote branch + workspace)
- [x] 2.4 Guarantee cleanup is merged-only — never touch un-merged PRs' bookmarks, remote branches, or workspaces

## 3. Docs / gotcha

- [x] 3.1 Add a gotcha note to jj-land/SKILL.md documenting the detached-HEAD `gh pr merge` behaviour under colocated jj (non-zero exit + skipped server-side `--delete-branch`)
- [x] 3.2 Update the §6 report shape if needed so remote-branch deletions are reported alongside bookmark deletions

## 4. Validation

- [x] 4.1 Run `openspec validate jj-land-colocated-cleanup` and resolve any issues
- [ ] 4.2 Exercise live: land a ≥2-PR stack in this colocated repo and confirm (a) a non-zero `gh pr merge` exit does not abort when state is `MERGED`, and (b) zero remote-branch stragglers remain on `origin` afterward (PARTIAL: the fix's approach was validated by hand merging PR #14 — `--squash` with no `--delete-branch` produced no error, explicit API branch-delete left no straggler — but the full ≥2-stack exercise with the *installed* fixed skill is still pending)
