## 1. Skill scaffold in core jj-concurrent

- [x] 1.1 Create `plugins/jj-concurrent/skills/jj-pr-fixup/SKILL.md` with frontmatter (name, description, `/jj-pr-fixup` trigger) declaring it an orchestrator-only skill that takes a PR (number/URL) argument and optional workspace-path/base override flags
- [x] 1.2 State the preconditions in the skill body: orchestrator role only (never a worker), colocated jj↔git repo with an `origin` remote, the PR's head branch fetchable locally, `gh` available and authenticated with PR-comment read scope, and the `/jj-absorb` and `/jj-pr` skills present
- [x] 1.3 Bump `plugins/jj-concurrent/.claude-plugin/plugin.json` version and update its description to mention the automated amend-after-review loop

## 2. Preflight and dependency checks

- [x] 2.1 Implement the `gh` preflight: presence + `gh auth status` and ability to read the PR's review comments, reporting a clear blocker without hanging
- [x] 2.2 Implement presence checks for the composed `/jj-absorb` and `/jj-pr` skills, reporting a clear blocker when either is unavailable (never open-code their behaviour)

## 3. Read PR review comments → worker brief

- [x] 3.1 Implement review-comment fetch via `gh` (review summary + file/line-anchored threads), settling the exact `gh pr view --json` / `gh api` calls
- [x] 3.2 Filter out resolved and outdated threads; on an all-resolved/empty result, report "no actionable comments" and stop before dispatch
- [x] 3.3 Compose a single worker brief preserving each comment's file path, line/anchor, and body, plus the workspace path and the resolved base revision

## 4. Provision worker on the PR head

- [x] 4.1 Resolve the PR head branch to a local jj revision (fetch when needed); report a clear blocker when it cannot be resolved, before provisioning
- [x] 4.2 Provision the worker with `jj workspace add -r <pr-head-rev> <path>` per the `jj-delegate` explicit-base-revision rule
- [x] 4.3 Dispatch the worker with the composed brief (background by default per `jj-delegate`); confirm the worker stays within its role (own commits only, no bookmarks/push)

## 5. Absorb fixes into owning commits

- [x] 5.1 After the worker reports, invoke the `/jj-absorb` step over the worker's working-copy fixes to land each hunk into its owning downstack commit
- [x] 5.2 Surface any ambiguous remainder for deliberate placement (per `/jj-absorb` remainder handling); never force-fit or push as a tip commit
- [x] 5.3 Capture the per-hunk landing report (fix → destination change-id/description) for the final result

## 6. Update the PR

- [x] 6.1 Invoke the `/jj-pr <bookmark>` push-and-PR step to re-push and update the existing PR in place (idempotent; no duplicate PR; no extra force-push)
- [x] 6.2 Report push/update failure distinctly ("fixes absorbed, PR not updated") from overall success; return the updated PR URL plus the landing report

## 7. Reconcile-tail wiring and teardown

- [x] 7.1 Update the `jj-delegate` skill's reconcile-tail prose to reference `/jj-pr-fixup` as the automated amend-after-review loop over an existing PR
- [x] 7.2 Tear the fixup workspace down after a successful loop (`jj workspace forget` + remove dir); leave it intact when the worker reports a blocker, per `jj-delegate`

## 8. Validation

- [x] 8.1 Run `openspec validate jj-pr-fixup` and resolve any structural errors
- [x] 8.2 Manually exercise `/jj-pr-fixup` against a scratch colocated repo with a real PR carrying review comments: confirm comment→brief mapping, PR-head basing, absorb placement, in-place PR update, and the no-actionable-comments and missing-dependency blocker paths
