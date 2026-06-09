---
name: jj-stacked-pr
description: |
  Open or update a stack of GitHub PRs from a stitched linear jj stack — one PR
  per bookmark, each based on its parent bookmark instead of trunk (the root on
  trunk), so reviewers see only each change's own diff. Given an ordered list of
  stacked bookmarks, or a single tip bookmark whose ancestry it walks, it derives
  the parent chain from the jj stack topology, composes the per-bookmark `/jj-pr`
  push-and-PR primitive bottom-up with the right `--base`, maintains a single
  marker-delimited cross-reference stack-navigation comment on every PR, and
  re-points PR bases idempotently when the stack is rebased, reordered, or has a
  change dropped. Triggers: /jj-stacked-pr, "open the stacked PRs", "submit this
  jj stack", "open/update stacked PRs for <tip>". The stacked submit step of the
  /jj-delegate stitch-into-a-stack reconcile tail, alongside the single-change
  /jj-pr step. Orchestrator-only (owns refs and push); never invoked inside a
  worker. Requires a colocated jj↔git repo with an `origin` remote and `gh`
  authenticated and supporting `pr create/edit --base` and `pr comment`.
metadata:
  version: "0.1.0"
  author: outfitter-style
---

# jj-stacked-pr — open or update a stack of based PRs from a jj stack

You are the **orchestrator**. When a stitched linear jj stack
(`base → A → B → C`) is ready, each change is a separate reviewable unit and
wants its own GitHub PR — but each PR must be **based on its parent bookmark**,
not trunk. Basing every PR on trunk collapses the stack into N parallel PRs that
each show every ancestor's diff (the noisy, un-reviewable shape stacked PRs
exist to avoid).

This skill is a thin orchestration **over** [`/jj-pr`](../jj-pr/SKILL.md): it
derives the parent chain from the jj stack topology, calls the per-bookmark
push-and-PR primitive once per bookmark with the right `--base`, and adds a
cross-reference comment so a reviewer on any PR can navigate the whole stack. It
does NOT re-implement push / `jj bookmark track` / PR-body generation — those
are owned by `/jj-pr`.

Substrate knowledge (jj command surface, revsets, templates, non-interactive
rules) comes from the installed `jj-vcs` skill — defer to it for jj command
detail; this skill owns only the stacked-PR choreography.

## Preconditions (verify, don't assume)

- **Orchestrator role only.** This skill owns ref and push operations, which the
  worker contract forbids. NEVER invoke `/jj-stacked-pr` inside a worker. It runs
  in the primary/default workspace, the role that owns all bookmarks and pushes.
- **An already-stitched, linear jj stack.** `/jj-delegate` (or you) owns building
  and ordering the stack; this skill consumes an already-stitched **linear** one
  (`base → A → B → C`). A non-linear, gapped, or branching selection is reported
  and stopped on (see §2.2), not guessed.
- **Colocated jj↔git repo with an `origin` remote.** PRs need a GitHub remote;
  `jj git push` targets `origin` by default. If there is no `origin` remote, stop
  and report — this skill does not create remotes.
- **`gh` available, authenticated, and supporting `pr create/edit --base` and
  `pr comment`.** The push/PR preflight is inherited from `/jj-pr` (its §1). The
  comment step additionally needs `gh pr comment` / `gh pr view --json comments`;
  if that surface is unavailable, the skill degrades (see §4.3) rather than
  failing the opened PRs.
- **Bookmark = GitHub head/base branch.** The colocated default; assumed equal
  and not auto-reconciled (same precondition as `/jj-pr`).

## Arguments

```
/jj-stacked-pr <tip-bookmark> [--draft]
/jj-stacked-pr <bm-root> <bm-1> … <bm-tip> [--draft]
```

- **`<tip-bookmark>`** — a single tip bookmark whose linear ancestry is walked
  into the ordered root-first list (§2.1). The common call from the stitch tail.
- **`<bm-root> … <bm-tip>`** — an explicit, already-ordered (root-first) list of
  stacked bookmarks, for the gapped/curated case where you do not want ancestry
  walked.
- **`--draft`** (optional) — pass-through to `/jj-pr`; opens every PR in the
  stack as a draft. Default non-draft; the calling reconcile tail decides.

Any other `/jj-pr` pass-through flag (e.g. `--issue`) applies per-bookmark and is
forwarded unchanged; this skill only adds `--base`.

## 1. Preflight (fail fast, never hang)

Confirm the push/PR step can run before touching the remote. This is the same
preflight `/jj-pr` performs (its §1), surfaced here so a missing dependency stops
the whole stack up front rather than mid-way:

```bash
command -v gh >/dev/null 2>&1 || echo "BLOCKER: gh not installed"
gh auth status 2>&1            # non-zero / "not logged into" ⇒ blocker
```

If `gh` is absent or unauthenticated, **report a clear blocker and stop before
pushing anything** — do not half-open the stack and do not hang on an auth
prompt. Distinguish this up-front blocker (nothing done) from a mid-run failure
(some PRs already opened, see §3 / §6).

## 2. Resolve the stack to an ordered list and derive bases

### 2.1 Input resolution → ordered root-first list

- **Explicit ordered list given** → use it as-is (root first), but still run the
  linearity assertion (§2.2) against the jj topology to catch a stale/curated
  list that no longer matches the stack.
- **Single tip bookmark given** → walk its ancestry over the bookmarked changes
  on `trunk()..<tip>`, ordered root-first. List the bookmarked changes in the
  trunk-to-tip range and read their bookmarks:

  ```bash
  jj log -r 'trunk()..<tip> & bookmarks()' \
    --ignore-working-copy --no-pager --no-graph --reversed \
    -T 'bookmarks ++ "\n"'
  ```

  `--reversed` yields root-first order; `& bookmarks()` keeps only the
  bookmarked changes (the stack's PR units), skipping intervening unbookmarked
  commits. Strip any trailing tags/whitespace the template emits, and drop the
  tip's own working-copy/empty trailer if present.

### 2.2 Linearity assertion (before touching any PR)

Verify the resolved set is a single linear chain. Stop and report — touching no
PR — if any of these hold:

- **Fork** — a change in `trunk()..<tip>` has two children (the stack branches).
  Detect with the children revset, e.g. a change `c` where
  `children(c) & (trunk()..<tip>)` has more than one entry.
- **Gap** — a resolved bookmark is not an ancestor-or-descendant of its
  neighbours in the chain (the chain is not contiguous).
- **Out of range** — an explicitly listed bookmark resolves outside
  `trunk()..<tip>` (not part of this stack).

Report the offending topology (which change forks, which bookmark is out of
range) and **stop before creating, updating, or re-basing any PR** — never guess
a base. This matches `/jj-delegate`'s linear stitched-stack contract.

### 2.3 Base-chain computation from list position

For the ordered list `[A, B, C]` over trunk `T`, the base of each PR is the
bookmark immediately below it, the root basing on trunk:

```
A → T   (trunk / default branch)
B → A
C → B
```

This is the entire stacked-PR contract, computed purely from list position, so
it is trivially re-derivable on every re-run (§5). Resolve `T` to the repo's
default/trunk branch name (the `trunk()` bookmark) for the root's `--base`.

## 3. Per-bookmark push + PR, bottom-up (compose over /jj-pr)

Process the ordered list **bottom-up (root first)**. For each bookmark, invoke
the per-bookmark primitive with its computed base:

```
/jj-pr <bookmark> --base <parent> [--draft]   # parent = trunk for the root
```

`/jj-pr` inherits, unchanged: the push (`jj git push -b`), one-time
`jj bookmark track`, create-or-update PR detection (keyed on the head branch),
and PR-body generation. This skill adds only the `--base <parent>` and the
ordering. Do NOT re-implement push/track/PR-body here.

### 3.1 If `/jj-pr` is unavailable, fall back inline

If the `/jj-pr` skill is not installed in the session, perform the same
primitive operations inline per bookmark (still bottom-up):

```bash
jj bookmark track <bookmark> --remote=origin --no-pager   # only if untracked
jj git push -b <bookmark> --no-pager
# create vs update, keyed on the head branch:
gh pr list --head <bookmark> --state open --json url --jq '.[0].url'
#   zero results → gh pr create --head <bookmark> --base <parent> --title … --body-file … [--draft]
#   one  result  → gh pr edit   <bookmark> --base <parent> --title … --body-file …
```

Composing over `/jj-pr` is the preferred wiring; the inline form is the stable
floor when the primitive is absent or its flag shape differs.

### 3.2 Bottom-up ordering is load-bearing

Root-first ordering guarantees each PR's **base branch is already pushed** before
the child PR references it — GitHub rejects a `--base` whose branch is not yet on
the remote. A child PR is created only after its parent bookmark's push (the
prior iteration) has completed. Never create PRs before all pushes, and never
reorder to top-down.

### 3.3 Capture per-bookmark outcomes

For each bookmark record, for the final report (§6): the **PR URL**, the **base**
it targets, and whether the PR was **created vs updated** (from `/jj-pr`'s report,
or the create/edit branch in the inline fallback). Carry these forward; the
cross-reference comment (§4) needs every PR URL.

## 4. Cross-reference stack-navigation comment (in place)

After every PR exists and its URL is known, maintain one skill-managed comment on
**each** PR listing the full ordered stack, so a reviewer on any PR can navigate
the whole thing.

### 4.1 Compose the marker-delimited stack block

Build a single ordered block — each line `<n>. <bookmark> — <PR-url>`, with the
**current** PR marked (e.g. `👈 (this PR)`) — wrapped in a stable HTML-comment
marker pair so re-runs can find and replace it:

```
<!-- jj-stack:start -->
**Stack** (bottom → top):
1. <bm-root> — <pr-url-root>
2. <bm-1> — <pr-url-1> 👈 (this PR)
3. <bm-tip> — <pr-url-tip>
<!-- jj-stack:end -->
```

Only the "you are here" marker differs between PRs; the ordered list is identical
on every PR in the stack.

### 4.2 Edit in place or post new — never duplicate

For each PR, detect an existing marker-delimited stack comment and update it in
place; only post a new one when none exists:

```bash
# Find a prior stack comment (one carrying the jj-stack:start marker):
gh pr view <bookmark> --json comments \
  --jq '.comments[] | select(.body | contains("<!-- jj-stack:start -->")) | .url'
#   (or `gh api` on the comments endpoint to get the comment id for an edit)
```

- **Existing marked comment found** → edit that comment in place (e.g.
  `gh api -X PATCH …/issues/comments/<id> -f body=@<file>`), replacing the
  marker-delimited block. Never append a second stack comment.
- **No marked comment** → `gh pr comment <bookmark> --body-file <file>`.

The stable marker makes re-runs idempotent: update in place, never accumulate
duplicate stack comments across runs.

### 4.3 Degrade clearly when the comment surface is unavailable

If the comment surface fails (no `gh pr comment` support, comments API error),
**do not fail the opened PRs**. Report **"PRs opened, stack comment not posted"**
distinctly in the result, so the orchestrator knows the PRs are good but the
cross-references are missing. Never hang on a prompt; never roll back the opened
PRs.

## 5. Rebase / re-stack handling (full recompute on every re-run)

A re-run is always a full recompute, never a diff against persisted state — the
skill holds no state; the stack is re-derived from jj and GitHub each run.

### 5.1 Re-resolve and re-point only changed bases

Re-resolve the ordered bookmark list from the current jj stack (§2.1–2.2) and
recompute every base (§2.3). For each **surviving** PR whose base **changed**:

```bash
gh pr edit <bookmark> --base <new-parent>
```

Leave PRs whose base is unchanged untouched (avoid a no-op edit). Pushes happen
before base edits in the same bottom-up pass, so a `--base` edit never points at
a not-yet-pushed reordered branch.

### 5.2 Regenerate the comment from the new order

Regenerate the cross-reference comment (§4) from the **new** order and update it
in place on **every** PR in the stack — including PRs whose base did not change,
since their position/neighbours in the list may have moved.

### 5.3 Report orphans — do not auto-close

A bookmark that has **left the stack** (its change was dropped/abandoned, or it
no longer resolves in `trunk()..<tip>`) but still has an open PR is an **orphan**.
**Report each orphaned PR** (bookmark + PR URL) for the orchestrator to close or
retarget — **never auto-close it**. Closing destroys review history on what may
be a transient re-stack and is an orchestrator decision outside this skill.

## 6. Report (report-shaped result)

Return a compact, ordered result the reconcile tail can surface:

- The **ordered stack**, bottom → top: each `bookmark → PR-url → base`, with the
  created/updated action per PR.
- Any **base re-point actions** taken on a rebase re-run (`<bookmark>: <old-base>
  → <new-base>`).
- Any **orphaned PRs** reported (bookmarks that left the stack).
- The **cross-reference comment** outcome — posted/updated on all PRs, or the
  distinct **"PRs opened, stack comment not posted"** degradation (§4.3).

Example shape:

```
stack (bottom → top):
  1. feat/data-layer   created  base=main          https://github.com/org/repo/pull/40
  2. feat/api          created  base=feat/data-layer  https://github.com/org/repo/pull/41
  3. feat/ui           updated  base=feat/api      https://github.com/org/repo/pull/42
re-points: (none)
orphans:   (none)
stack comment: posted/updated on all 3 PRs
```

## Failure modes (each reported, none improvised)

- **`gh` absent/unauthenticated** → up-front blocker, nothing pushed (§1).
- **Non-linear / gapped / out-of-range stack** → topology reported, no PR
  touched (§2.2).
- **Child PR's base branch not yet pushed** → prevented by strict bottom-up
  ordering (§3.2); never worked around with a top-down pass.
- **Push rejected for a bookmark** → inherited from `/jj-pr` (no force-push);
  report and stop the remaining (higher) PRs, since their base would be missing.
- **Comment surface unavailable** → "PRs opened, stack comment not posted",
  PRs left intact (§4.3).
- **Bookmark left the stack** → reported as an orphan, NOT auto-closed (§5.3).
- **A jj command itself hangs** → do not retry blindly and NEVER delete `.jj`;
  `jj op log` / `jj op restore` is the orchestrator-only recovery surface.

## Where this is called

`/jj-stacked-pr` is the **stacked** submit step of the reconcile tail, the
multi-PR sibling of `/jj-pr`:

- [`jj-delegate`](../jj-delegate/SKILL.md) §5 — when the fan-out's siblings are
  stitched into a single linear stack, `/jj-stacked-pr <tip>` opens/updates the
  whole stack with based PRs; the single-change `/jj-pr <bookmark>` remains the
  step for a non-stacked change.
- Composes over [`/jj-pr`](../jj-pr/SKILL.md) for each bookmark's push-and-PR
  step (with `--base <parent>`); it never re-implements push/track/PR-body.
