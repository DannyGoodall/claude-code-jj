## Context

`/jj-delegate` can fan out several sibling workers and then stitch their changes into a single linear jj stack (base → A → B → C) — `jj-delegate`'s "Integration never halts" requirement already covers rebasing a worker's change onto a sibling, which is exactly how the stack is built. Once stitched, each change is a separate reviewable unit and wants its own GitHub PR. The in-flight `jj-github-pr` change supplies `/jj-pr <bookmark>`: the per-bookmark push-and-PR primitive that already handles `jj git push -b`, one-time `jj bookmark track`, create-or-update PR detection, PR-body generation, and an optional `--base`. What it does **not** do is reason about a *stack* of bookmarks — it opens each PR against trunk by default.

This design covers `/jj-stacked-pr`: a thin orchestration **over** `/jj-pr` that derives the parent chain from the jj stack, calls the primitive once per bookmark with the right `--base`, and adds a cross-reference comment that lets a reviewer navigate the whole stack. It runs strictly in the orchestrator role (which owns refs, push, and integration); workers are forbidden these operations by their contract.

`/jj-pr` (the `jj-github-pr` capability) is **in-flight, not yet canonical** in `openspec/specs/`. This design therefore treats `/jj-pr` as a *named conceptual primitive* — "push bookmark + create/update its PR with an optional base" — and does not depend on its spec text. If `/jj-pr` is absent at implementation time, the same primitive operations (`jj git push -b`, `gh pr create/edit --base`) are performed inline; composing over `/jj-pr` is the preferred wiring, not a hard precondition.

## Goals / Non-Goals

**Goals:**
- Open or update one GitHub PR per bookmark in a stitched jj stack, each based on its parent bookmark (root on trunk).
- Derive the base chain deterministically from the jj stack topology (linear ancestry of the bookmarked changes), not from branch-name guesses.
- Keep a single, in-place-updated cross-reference comment on every PR listing the full ordered stack with a "you are here" marker.
- Re-point PR bases and refresh the comment idempotently when the stack is rebased, reordered, or has a change dropped.
- Compose over the per-bookmark `/jj-pr` primitive rather than re-implementing push/track/PR-body logic.

**Non-Goals:**
- The single-bookmark push/track/PR-body/`gh` preflight mechanics themselves — owned by `/jj-pr` (the `jj-github-pr` capability); this skill orchestrates, it does not reimplement them.
- Creating, naming, ordering, or stitching the stack — `/jj-delegate` owns building the stack; `/jj-stacked-pr` consumes an already-stitched stack.
- Merging, land/rebase-on-merge, auto-merge, or the "merge the bottom and restack" flow — the skill opens/updates the stacked PRs and stops.
- Non-linear / branching stacks (a change with two children). The stitched-stack contract is linear; a non-linear selection is reported, not handled.
- Multi-remote / non-GitHub forges — `origin` + GitHub via `gh` only.

## Decisions

- **Input is a stack, resolved to an ordered bottom-up bookmark list.** The skill accepts either an explicit ordered list of stacked bookmarks or a single tip bookmark whose ancestry it walks. It resolves the linear chain with a jj revset over the bookmarked changes — e.g. the bookmarked changes on `trunk()..<tip>` ordered by ancestry — and emits the list root-first. *Alternative considered:* require the caller to always pass the full ordered list. Rejected as the primary mode because the stitching step already knows the tip; walking ancestry keeps the call site simple, but the explicit-list form is retained for the gapped/curated case.

- **Base of each PR = the bookmark immediately below it; root bases on trunk.** For the ordered list `[A, B, C]` over trunk `T`, the bases are `A→T`, `B→A`, `C→B`. This is the entire stacked-PR contract and is computed purely from list position, so it is trivially re-derivable on rebase. *Alternative considered:* base every PR on trunk and rely on GitHub's "files changed" base selector — rejected because that is precisely the collapsed, every-ancestor-diff view stacked PRs exist to avoid.

- **Process bottom-up; delegate each PR to `/jj-pr <bookmark> --base <parent>`.** Pushing and PR-creating from the root upward guarantees each PR's base branch already exists on the remote before the child PR references it (GitHub rejects a `--base` whose branch is not yet pushed). Each step is the per-bookmark primitive, so push, one-time `jj bookmark track`, create-or-update detection, and PR-body generation are inherited unchanged. *Alternative considered:* push all bookmarks first, then create all PRs — rejected as it duplicates the primitive's push step and loses the primitive's per-bookmark report shape.

- **Cross-reference comment is one marker-delimited block, rewritten in place.** After all PRs exist, the skill composes a single ordered list — each line `<n>. <bookmark> — <PR-url>`, the current PR marked (e.g. `👈` / `(this PR)`) — wrapped in a stable HTML-comment marker pair (e.g. `<!-- jj-stack:start -->…<!-- jj-stack:end -->`). For each PR it finds the existing marked comment (via `gh pr view --json comments` / `gh api`) and edits it, or posts a new one (`gh pr comment`) when none exists. The marker makes re-runs idempotent — update in place, never append a second stack comment. *Alternative considered:* put the stack list in the PR body — rejected because the body is owned/generated by `/jj-pr`; a separate marked comment keeps the two concerns (body vs stack-nav) independently re-renderable.

- **Rebase updates are a full recompute, not a diff.** On any re-run the skill re-resolves the ordered bookmark list from the current jj stack and re-derives every base. For each surviving PR whose base changed it runs `gh pr edit --base <new-parent>`; PRs whose base is unchanged are left as-is (no-op edit avoided). A bookmark that left the stack is reported (its PR is *not* auto-closed — closing is an orchestrator decision outside this skill). The cross-reference comment is regenerated from the new order on every PR. This makes "the stack moved" a single idempotent re-run rather than a bespoke migration.

- **Linearity is asserted, not assumed silently.** If the resolved ancestry is not a single linear chain (a gap, a fork, or a bookmark outside `trunk()..<tip>`), the skill reports the offending topology and stops before touching any PR, rather than guessing a base. This matches `jj-delegate`'s linear stitched-stack contract.

- **Non-interactive and report-shaped, like the rest of the plugin.** `jj … --no-pager`; `gh` with explicit flags (`--base`, `--head`, `--json`, `--body`/`--body-file`); no editor spawn. The skill returns the ordered list of bookmark → PR-url → base, plus any rebase re-point actions taken, so the reconcile tail can surface the whole stack.

## Risks / Trade-offs

- **Child PR created before its parent branch is pushed → GitHub `--base` rejection.** → Mitigated by strict bottom-up ordering: a PR is only created after its parent bookmark's push (the prior iteration) has completed.
- **A dropped/abandoned bookmark leaves an orphaned open PR whose base no longer exists.** → The skill reports orphaned PRs (bookmarks no longer in the stack) for the orchestrator to close/retarget; it does not auto-close, to avoid destroying review history on a transient re-stack.
- **Rebase that reorders the stack swaps two PRs' bases mid-flight, briefly creating a base cycle on GitHub.** → Recompute-and-edit is applied bottom-up in the new order, and GitHub tolerates a transient mismatch between edits; the final state is consistent. A `--base` edit pointing at a not-yet-pushed reordered branch is avoided because pushes happen before base edits in the same bottom-up pass.
- **`gh` lacks/changes the comment or `--base` edit surface.** → The skill preflights `gh` availability/auth (inherited from the `/jj-pr` primitive) and degrades to reporting "PRs opened, stack comment not posted" distinctly, rather than failing the whole stack.
- **Bookmark name ≠ GitHub head/base branch in exotic setups.** → Assumed equal (the colocated default, same precondition as `/jj-pr`); documented, not auto-reconciled.
- **Composing over an in-flight `/jj-pr` that lands with a different flag shape.** → This design pins only the conceptual contract ("push bookmark + create/update PR with optional base"); the inline fallback (`jj git push -b` + `gh pr create/edit --base`) is the stable floor if the primitive's surface differs at implementation time.

## Migration Plan

Additive: a new skill in the existing `jj-concurrent` plugin, bumping that plugin's version. No existing behaviour changes — single-change `/jj-pr` submits are unaffected and remain the default for non-stacked changes. The `jj-delegate` stitch-into-a-stack prose gains a pointer to `/jj-stacked-pr` as the stacked submit step. Rollback is removing the skill file and reverting that prose pointer; the skill holds no persisted state (the stack is re-derived from jj and GitHub each run, and the cross-reference comment is marker-delimited and removable).

## Open Questions

- Should `/jj-stacked-pr` open the whole stack as **draft** by default until the bottom PR is reviewed, deferring to a `--draft` pass-through to `/jj-pr`? (Leaning: pass-through, default non-draft, decided by the calling reconcile tail.)
- When a bottom PR merges, should `/jj-stacked-pr` offer a "restack onto trunk and re-point bases" follow-up, or is that a separate land/restack capability? (Leaning: separate capability — this one stops at open/update.)
- Should the cross-reference comment also be mirrored into each PR's body for forges/tools that do not surface comments prominently, or is the marked comment sufficient? (Leaning: comment-only to keep the body owned by `/jj-pr`.)
