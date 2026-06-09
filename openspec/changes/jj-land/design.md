## Context

The `jj-concurrent` orchestrator can fan work out across jj workspaces, integrate it into a stack, and (with `jj-github-pr`'s `/jj-pr`) push each change and open/update a correctly-stacked GitHub PR. What it cannot do is *land* that stack. GitHub merges one PR at a time; `gh pr merge` neither understands stack order nor retargets the PRs above the one it merged, and nothing syncs the local trunk or cleans up the merged bookmarks and now-stale workspaces afterward. Graphite solved this with `gt merge`. This design covers the jj analog: a single `/jj-land` skill that lands a stack of PRs bottom-up, waiting for CI at each step, restacking remaining PRs onto the new base as lower ones merge, and finishing with a trunk sync + cleanup pass.

It runs strictly in the orchestrator role — the role that already owns bookmarks, push, refs, and fetch. Workers are forbidden these operations by their contract, so `/jj-land` is never invoked inside a worker. It composes with two existing capabilities without depending on either being canonical: it lands the PRs that `jj-github-pr`'s `/jj-pr` opened (but lands hand-opened PRs equally), and it defers the workspace-forget step to the `jj-delegate` capability's existing Teardown requirement rather than re-implementing workspace lifecycle.

## Goals / Non-Goals

**Goals:**
- One skill that lands a jj stack of GitHub PRs bottom-up, in an order derived from the jj stack itself.
- A per-step CI gate: each PR is merged only after its required checks pass; a red check or wait-timeout aborts the rest of the stack cleanly and reports where it stopped.
- Base retargeting of the remaining PRs as each lower PR merges, so every PR is merged against a base that still exists.
- A post-merge cleanup pass: `jj git fetch` to sync trunk, delete merged bookmarks, forget stale workspaces (via jj-delegate Teardown).
- Strictly orchestrator-role, non-interactive, and force-free.

**Non-Goals:**
- Opening or updating PRs — that is `/jj-pr` (`jj-github-pr`); `/jj-land` assumes each stacked change already has an open PR.
- Building or reshaping the stack — the caller already owns the stack's shape; `/jj-land` reads it, it does not author it.
- CI configuration, required-check policy, or branch-protection setup — `/jj-land` reads the check state GitHub reports; it does not define what "required" means and never overrides protection (no admin-merge, no force).
- Multi-remote / multi-forge support — `origin` + GitHub via `gh` only.
- Conflict resolution during the land — if a merge is blocked by a conflict or an out-of-date base that retargeting cannot fix, `/jj-land` stops and reports rather than resolving in the merge UI.
- Rollback of an already-merged PR — landing is forward-only; a mid-stack abort leaves merged PRs merged.

## Decisions

- **Bottom-up order is derived from the jj stack, not from PR metadata.** The skill computes the linear change order from trunk upward with a jj revset over the stack (e.g. `trunk()..<top>` rendered oldest-first via `jj log --no-pager -r … -T …`), maps each change to its bookmark and thus its PR, and merges in that order. Reading order from jj rather than from each PR's `base` field means the order is correct even before any retargeting has happened and even if a PR's base was set by hand. *Alternative considered:* walking PR `base`→`head` links on GitHub — rejected because it depends on the bases already being correct, which is precisely what this skill maintains, and because the jj stack is the source of truth the rest of the plugin already uses.
- **Refuse to merge an upper PR before everything beneath it has merged.** The loop is strictly sequential bottom-up; the skill never merges out of order even if an upper PR's checks go green first. This preserves the invariant that each PR merges against trunk (or a still-open lower branch) and never against a branch that is about to disappear underneath it.
- **CI wait is a poll loop with an explicit timeout, gated on GitHub's own required-check verdict.** Per PR, the skill polls `gh pr checks <pr>` / `gh pr view <pr> --json statusCheckRollup,mergeStateStatus` on an interval until the required checks reach success, then merges. A failing required check or an elapsed timeout stops the run. *Alternative considered:* `gh pr merge --auto` (let GitHub auto-merge when checks pass) — rejected as the primary path because auto-merge yields control of ordering and retargeting to GitHub's queue, breaking the strict bottom-up restack; an explicit poll keeps the skill in control of sequencing. (Auto-merge is noted as a possible future opt-in for the single-PR tail.)
- **Merge method is the repo/PR default, never forced and never admin-overridden.** The skill calls `gh pr merge <pr>` with an explicit method flag matching the project convention (e.g. `--squash` or `--merge`, configurable) and `--delete-branch` so the merged head branch is cleaned up server-side. It SHALL NOT pass `--admin` and SHALL NOT force; if branch protection blocks the merge, that is a reported blocker, not something to override.
- **Retarget the next PR's base immediately after the lower PR merges.** Once PR *n* merges, the skill sets PR *n+1*'s base to trunk (the merged commits are now on trunk) via `gh pr edit <pr_{n+1}> --base <trunk>`. Retargeting to trunk (rather than to the next surviving lower branch) is correct because lower PRs are merged before upper ones, so by the time *n+1* is considered its entire downstack is already on trunk. Retargeting is done before *n+1*'s CI wait so checks run against the right base.
- **Cleanup is a single tail pass, and workspace-forget defers to jj-delegate.** After the loop (whether it completed or aborted), the skill: (1) runs `jj git fetch` to bring the merged commits onto the local trunk-tracking bookmark; (2) deletes the local bookmarks for PRs that actually merged (`jj bookmark delete <name>`), leaving bookmarks for un-merged PRs intact; (3) for each merged change that still has a linked jj workspace, forgets that workspace via the mechanism the `jj-delegate` Teardown requirement already owns (`jj workspace forget` + directory removal), rather than re-implementing it here. Cleanup acts only on PRs that merged, so an aborted run leaves the un-landed tail fully intact for a re-run.
- **Idempotent and resumable.** Re-running `/jj-land` after a partial land skips PRs already merged (detected via `gh pr view --json state`) and resumes from the first still-open PR, re-deriving order from the (now shorter) jj stack. This makes "fix the red check, run `/jj-land` again" the natural recovery path.
- **Non-interactive and report-shaped.** Like the rest of the plugin: `jj … --no-pager`, `gh` with explicit flags, no editor spawn, no interactive prompts. The skill returns a per-PR outcome list (merged / waiting-timed-out / checks-red / blocked) plus the cleanup summary so the caller can see exactly how far the stack landed.

## Risks / Trade-offs

- **CI never goes green (flaky or stuck)** → the per-step timeout bounds the wait; on timeout the skill aborts the remaining stack and reports the stuck PR, leaving already-merged PRs merged and the rest open for a re-run. It does not loop forever.
- **A red required check mid-stack** → the run stops at that PR; lower PRs stay merged, the red PR and everything above it stay open with bases already retargeted as far as the merge got. Re-running after a fix resumes cleanly.
- **Retarget races a human editing the same PR** → `gh pr edit --base` is last-writer-wins; the skill sets the base it computed from the jj stack and reports the value it set, so a divergence is visible rather than silent.
- **Branch protection / admin-only merge blocks a step** → reported as a blocker for that PR; the skill never passes `--admin` or forces, so it stops rather than escalating privileges.
- **`jj git fetch` brings trunk forward but local stack bookmarks now look behind/abandoned** → expected; merged bookmarks are deleted in the same cleanup pass, and un-merged ones are left for the operator to restack and re-land. The skill does not auto-rebase the surviving tail (that is a separate restack concern).
- **A merged PR's head branch was already deleted server-side by `--delete-branch`, so a later local op references a gone branch** → the local bookmark delete is keyed on merge state, not on the remote branch still existing, so a server-side-deleted branch is fine.
- **`gh` unauthenticated or absent** → detected up front (`gh auth status`) and reported as a blocker before any merge is attempted, so the skill never half-lands a stack because of a missing tool.

## Migration Plan

Additive: a new skill in the existing core `jj-concurrent` plugin, bumping that plugin's version. No existing behaviour changes. The skill reads the `jj-delegate` Teardown mechanism for workspace forget; that capability's spec is unchanged. Rollback is removing the skill file and reverting the plugin version bump; the skill holds no persistent state of its own (merge/PR state lives in GitHub and jj), so a partial land simply leaves a shorter stack to re-run against.

## Open Questions

- **Default merge method** — squash vs merge-commit vs rebase: ship a single project-configurable default (likely `--squash` to match a clean trunk history) or read it from repo settings? Leaning configurable-with-squash-default; resolve during implementation.
- **Poll interval and timeout defaults** — concrete numbers (e.g. 30s interval, 30min per-PR timeout) to be fixed during implementation, both overridable by flag.
- **Surviving-tail restack** — whether `/jj-land` should, after a partial land, auto-restack the un-merged tail onto the freshly-fetched trunk, or leave that to a separate restack skill. Current lean: leave it out (Non-Goal) to keep land forward-only and side-effect-bounded.
