## 1. Skill scaffold in core jj-concurrent

- [x] 1.1 Create `plugins/jj-concurrent/skills/jj-stacked-pr/SKILL.md` with frontmatter (name, description, `/jj-stacked-pr` trigger) declaring it an orchestrator-only skill that takes either an ordered list of stacked bookmarks or a single tip bookmark, plus optional pass-through flags (e.g. `--draft`)
- [x] 1.2 State the preconditions in the skill body: orchestrator role only (never a worker), an already-stitched **linear** jj stack, colocated jj↔git repo with an `origin` remote, `gh` available/authenticated and supporting `pr create/edit --base` and `pr comment`
- [x] 1.3 Bump `plugins/jj-concurrent/.claude-plugin/plugin.json` version and update its description to mention stacked-PR support

## 2. Stack resolution and base-chain derivation

- [x] 2.1 Implement input resolution: accept an explicit ordered bookmark list, or walk a single tip bookmark's ancestry via a jj revset over the bookmarked changes on `trunk()..<tip>` (`jj log --no-pager` with a template), emitting the root-first ordered list
- [x] 2.2 Implement linearity assertion: detect forks (a change with two children), gaps, or bookmarks outside `trunk()..<tip>`; report the offending topology and stop before touching any PR
- [x] 2.3 Implement base-chain computation from list position: root → trunk branch, each later bookmark → the bookmark immediately below it

## 3. Per-bookmark push + PR (compose over /jj-pr)

- [x] 3.1 Process the ordered list bottom-up, invoking the per-bookmark primitive `/jj-pr <bookmark> --base <parent>` (inheriting push, one-time `jj bookmark track`, create-or-update detection, PR-body generation); fall back to inline `jj git push -b` + `gh pr create/edit --base` if `/jj-pr` is unavailable
- [x] 3.2 Ensure bottom-up ordering guarantees each parent bookmark is pushed before its child PR references it as `--base` (avoid GitHub `--base` rejection)
- [x] 3.3 Capture per-bookmark outcomes (PR URL, base, created vs updated) for the final report

## 4. Cross-reference stack comment

- [x] 4.1 Compose the ordered stack block (each line `<n>. <bookmark> — <PR-url>`, current PR marked) wrapped in a stable marker pair (e.g. `<!-- jj-stack:start -->`…`<!-- jj-stack:end -->`)
- [x] 4.2 For each PR, detect an existing marker-delimited stack comment (`gh pr view --json comments` / `gh api`) and `gh pr edit`/edit-comment it in place, or `gh pr comment` a new one; never append a duplicate
- [x] 4.3 Degrade clearly to "PRs opened, stack comment not posted" when the comment surface is unavailable, without failing the opened PRs

## 5. Rebase / re-stack handling

- [x] 5.1 On re-run, re-resolve the ordered list and recompute every base; `gh pr edit --base <new-parent>` only for surviving PRs whose base changed, leaving unchanged bases untouched
- [x] 5.2 Regenerate the cross-reference comment from the new order on every PR
- [x] 5.3 Report bookmarks that have left the stack as orphaned PRs (do not auto-close)

## 6. Reconcile-tail wiring

- [x] 6.1 Update the `jj-delegate` stitch-into-a-stack reconcile-tail prose to point at `/jj-stacked-pr` as the stacked submit step, alongside the single-change `/jj-pr` step

## 7. Validation

- [x] 7.1 Run `openspec validate jj-stacked-pr` and resolve any structural errors
- [ ] 7.2 Manually exercise `/jj-stacked-pr` against a scratch colocated repo with a 3-change stack: fresh create (correct bases + comment), re-run after amending a lower change (idempotent), reorder (bases re-pointed), and drop a change (orphan reported); confirm a missing-comment-surface degradation report
  - DEFERRED (orchestrator): live PR exercise requires authenticated `gh`, a pushable `origin`, and ref/push operations the worker contract forbids; run at integration/reconcile.
