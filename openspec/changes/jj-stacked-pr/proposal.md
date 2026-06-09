## Why

When `/jj-delegate` fans out several sibling workers and the orchestrator stitches their changes into a single jj stack (base → A → B → C), each change still wants its own reviewable GitHub PR. Today the only push primitive (the in-flight `/jj-pr`) opens one PR per bookmark against trunk, which collapses a stack into N parallel PRs that each show every ancestor's diff — exactly the noisy, un-reviewable shape Graphite's stacked PRs were built to avoid. There is no skill that derives the parent chain from the jj stack and points each PR at its parent, so the headline Graphite workflow this plugin is meant to replace has no equivalent here.

## What Changes

- A new orchestrator skill **`/jj-stacked-pr`** that, given a stitched jj stack (an ordered list of stacked bookmarks, or a tip bookmark whose ancestry it walks), opens or updates one GitHub PR per bookmark with each PR's **base set to its parent bookmark** rather than trunk — the stack's root PR bases on trunk, every later PR bases on the bookmark below it.
- **Base-chain derivation from the jj stack topology**: the skill reads the linear ancestry of the stitched stack (via jj revsets over the bookmarked changes) to compute, for each bookmark, its parent bookmark (or trunk for the root), producing the `--base` argument for each PR. The stack is assumed linear (base → A → B → C) as produced by `jj-delegate` stitching; a non-linear or gapped selection is reported, not guessed.
- **Per-bookmark push + PR delegated to the `/jj-pr` primitive**: for each bookmark, bottom-up, the skill performs the push-and-PR-create/update step (conceptually D1's `/jj-pr <bookmark> --base <parent>`), so stacked-PR support is a *composition* over the single-bookmark primitive, not a re-implementation of push/track/PR-body logic.
- **Cross-reference stack comment**: each PR receives (or has updated) a single skill-managed comment containing the full ordered stack — every bookmark, its PR link, and a "you are here" marker — so a reviewer on any PR can navigate the whole stack. The comment is delimited by a stable marker so re-runs update it in place rather than appending.
- **Base updates on rebase**: when the stack is rebased (a lower change amended, the stack reordered, or a change dropped), re-running `/jj-stacked-pr` recomputes the parent chain and updates each existing PR's base via `gh pr edit --base <new-parent>` and refreshes the cross-reference comment, keeping the GitHub stack in sync with the jj stack without opening duplicates.
- Stays within the orchestrator role contract: only the orchestrator (which owns refs, push, and integration) runs `/jj-stacked-pr`; workers never do.

## Capabilities

### New Capabilities
- `jj-stacked-pr`: the `/jj-stacked-pr` orchestrator skill — derive the PR base chain from a stitched jj stack's topology, open/update one GitHub PR per bookmark based on its parent bookmark (composing the per-bookmark `/jj-pr` push+PR primitive), maintain a cross-reference stack-navigation comment on every PR, and re-point PR bases when the stack is rebased.

### Modified Capabilities
<!-- None. This capability builds conceptually on the in-flight jj-github-pr (`/jj-pr`) change, which is not yet canonical in openspec/specs/, so there is no existing spec to delta. It references jj-delegate (stitching siblings into a stack) one-directionally without changing jj-delegate's requirements. No delta spec required. -->

## Impact

- New skill `plugins/jj-concurrent/skills/jj-stacked-pr/SKILL.md` (or equivalent) in the **core `jj-concurrent` plugin**; bumps that plugin's version. No new plugin.
- Conceptual dependency on the `/jj-pr` per-bookmark primitive (in-flight `jj-github-pr` change) for the push-and-PR step; hard runtime dependency on the `gh` GitHub CLI (authenticated) supporting `pr create/edit --base` and `pr comment`, and on a colocated jj↔git repo with an `origin` remote.
- Reconcile-tail prose in `jj-delegate` (the stitch-into-a-stack path) gains a pointer to `/jj-stacked-pr` as the stacked submit step, alongside the single-change `/jj-pr` step (documentation/wiring only; no behaviour change to `jj-delegate`'s existing requirements).
- No changes to any target project's application code — this orchestrates pushes, PR bases, and stack-navigation comments; it ships no application behaviour.
