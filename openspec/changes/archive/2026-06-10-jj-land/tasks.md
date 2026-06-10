## 1. Skill scaffold in core jj-concurrent

- [x] 1.1 Create `plugins/jj-concurrent/skills/jj-land/SKILL.md` with frontmatter (name, description, `/jj-land` trigger) declaring it an orchestrator-only skill that takes an optional stack-top / trunk argument and optional merge-method, poll-interval, and timeout flags
- [x] 1.2 State the preconditions in the skill body: orchestrator role only (never a worker), colocated jj↔git repo with an `origin` remote and a trunk branch, `gh` available and authenticated, and each stacked change already having an open GitHub PR
- [x] 1.3 Bump `plugins/jj-concurrent/.claude-plugin/plugin.json` version and update its description to mention the stack-aware land step

## 2. Stack discovery and merge order

- [x] 2.1 Implement bottom-up order derivation: a jj revset over the stack (trunk upward) via `jj log --no-pager -r <trunk()..top> -T <template>`, rendered oldest-first
- [x] 2.2 Map each change to its bookmark and resolve that bookmark's open GitHub PR (`gh pr list --head <bookmark> --state open` / `gh pr view`)
- [x] 2.3 Skip changes whose PR is already merged (`gh pr view --json state`) so a re-run resumes from the first still-open PR
- [x] 2.4 Enforce strict bottom-up sequencing: never consider an upper PR until every PR beneath it has merged

## 3. Per-step CI wait

- [x] 3.1 Implement the dependency preflight: `gh auth status` (and `gh` presence) check that reports a clear blocker without hanging, before any merge
- [x] 3.2 Implement the poll loop per PR: query `gh pr checks <pr>` / `gh pr view <pr> --json statusCheckRollup,mergeStateStatus` on the configured interval until required checks succeed
- [x] 3.3 Implement clean abort on a red required check or an elapsed per-PR timeout: stop the remaining stack, leave merged PRs merged, report the stopping PR and reason

## 4. Merge and base retargeting

- [x] 4.1 Implement the merge step `gh pr merge <pr>` with the configured method flag (default `--squash`) and `--delete-branch`; never `--admin`, never force
- [x] 4.2 Detect and report a branch-protection / merge-blocked outcome as a blocker rather than overriding it
- [x] 4.3 After each lower PR merges, retarget the next-up PR's base to trunk via `gh pr edit <pr> --base <trunk>`, before that PR's CI wait
- [x] 4.4 Record per-PR outcomes (merged / waiting-timed-out / checks-red / blocked) and the base value set for each retargeted PR

## 5. Post-merge cleanup

- [x] 5.1 Run `jj git fetch --no-pager` to sync the local trunk with the merged commits
- [x] 5.2 Delete the local bookmarks for the merged changes only (`jj bookmark delete <name> --no-pager`); leave un-merged PRs' bookmarks intact
- [x] 5.3 For each merged change with a linked jj workspace, forget that workspace by deferring to the `jj-delegate` Teardown mechanism (`jj workspace forget` + directory removal); never re-implement workspace lifecycle here
- [x] 5.4 Ensure cleanup acts only on merged PRs so an aborted run leaves the un-landed tail (PRs, bookmarks, workspaces) fully intact

## 6. Reporting and wiring

- [x] 6.1 Return a report-shaped result: per-PR outcome list plus the cleanup summary (fetched, bookmarks deleted, workspaces forgotten)
- [x] 6.2 Note composition in the skill body: lands PRs opened by `/jj-pr` (jj-github-pr) or by hand, with no dependency on any in-flight change being canonical

## 7. Validation

- [x] 7.1 Run `openspec validate jj-land` and resolve any structural errors
- [x] 7.2 Manually exercise `/jj-land` against a scratch colocated repo with a two-PR stack: clean bottom-up land + retarget + cleanup; a red-check abort leaving the tail intact; and a re-run resuming from the first open PR (DEFERRED: requires authenticated `gh` + a live multi-PR stack; orchestrator runs this at reconcile)
