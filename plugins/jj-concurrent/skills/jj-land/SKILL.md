---
name: jj-land
description: |
  Land a stack of GitHub PRs bottom-up in one orchestrator step — the jj analog
  of Graphite's `gt merge`. Given a jj stack whose changes already have open
  GitHub PRs, it derives the merge order from the jj stack itself (trunk upward),
  then for each PR in turn waits for required CI, merges it (`gh pr merge`,
  default `--squash`, never `--admin`/force; success judged by PR state, not exit
  code), retargets the next-up PR's base to trunk via `gh pr edit --base`, and
  continues up the stack. A red required check or a per-PR wait-timeout aborts the
  rest of the stack cleanly, leaving merged PRs merged and the un-reached tail
  open. After the loop it runs a single cleanup pass: `jj git fetch` to sync local
  trunk, delete the merged bookmarks AND their remote branches, and forget any
  stale linked workspaces via jj-delegate Teardown. Re-running resumes from the
  first still-open PR. Triggers: /jj-land,
  "land the stack", "merge this jj stack bottom-up", "land/merge the stacked PRs
  for <top>". The land step of the /jj-delegate reconcile tail, downstack of
  /jj-pr and /jj-stacked-pr. Orchestrator-only (owns bookmarks, refs, push,
  fetch); never invoked inside a worker. Non-interactive (`jj … --no-pager`, `gh`
  with explicit flags, no editor) and performs no force operations. Requires a
  colocated jj↔git repo with an `origin` remote and a trunk branch, `gh`
  authenticated, and each stacked change already having an open GitHub PR.
metadata:
  version: "0.1.0"
  author: outfitter-style
---

# jj-land — land a jj stack of GitHub PRs bottom-up

You are the **orchestrator**. A stitched jj stack whose changes each have an open
GitHub PR (`base → A → B → C`, opened by `/jj-pr` / `/jj-stacked-pr` or by hand)
has no native "merge the whole stack" verb. `gh pr merge` merges one PR at a
time, leaves the PRs above it pointing at a base branch the merge just deleted,
and never syncs the local trunk or cleans up the merged bookmarks and now-stale
workspaces. This was Graphite's `gt merge`. This skill is the jj analog: it lands
the stack **bottom-up**, waits for CI at each step, retargets the rest as lower
PRs merge, and finishes with a trunk sync + cleanup pass.

This directly closes a hazard: merging a stacked-PR set by hand can merge a child
PR onto its parent feature branch (which is then deleted by `--delete-branch`)
instead of onto trunk, orphaning that child's content. Landing bottom-up with
base-retargeting at each step is the single safe command that avoids it.

Substrate knowledge (jj command surface, revsets, templates, non-interactive
rules) comes from the installed `jj-vcs` skill — defer to it for jj command
detail; this skill owns only the land choreography.

## Preconditions (verify, don't assume)

- **Orchestrator role only.** This skill owns bookmark, push, ref, and fetch
  operations, all of which the worker contract forbids. NEVER invoke `/jj-land`
  inside a worker. It runs in the primary/default workspace — the role that owns
  every bookmark, push, and fetch.
- **Colocated jj↔git repo with an `origin` remote and a trunk branch.** Merges
  happen on GitHub via `gh`; the trunk sync is `jj git fetch` against `origin`.
  If there is no `origin` remote or no resolvable trunk branch, stop and report —
  this skill does not create remotes or trunks.
- **`gh` available and authenticated.** Every merge, check-poll, and base edit is
  `gh`; a missing or unauthenticated `gh` is a reported blocker checked up front
  (see §1), not an improvised workaround. The skill never spawns an editor and
  never force-merges.
- **Each stacked change already has an open GitHub PR for its bookmark's head
  branch.** `/jj-land` lands existing PRs; it does not open them. Opening/updating
  PRs is `/jj-pr` / `/jj-stacked-pr`. A stacked change with no open PR is reported
  and stops that step, not guessed.
- **Bookmark = GitHub head/base branch.** The colocated default; assumed equal
  and not auto-reconciled (same precondition as `/jj-pr`).

## Arguments

```
/jj-land [<top-bookmark>] [--trunk <branch>] [--method squash|merge|rebase] \
         [--poll-interval <seconds>] [--timeout <seconds>]
```

- **`<top-bookmark>`** (optional) — the tip of the stack to land; its ancestry
  over `trunk()..<top>` is the stack (§2.1). If omitted, infer the tip from the
  current stack (the bookmarked change at the head of `trunk()..@`); if that is
  ambiguous (more than one tip), report and stop rather than guess.
- **`--trunk <branch>`** (optional) — the trunk branch PRs are retargeted to and
  fetched from. Defaults to the repo's resolved `trunk()` branch name.
- **`--method squash|merge|rebase`** (optional) — the `gh pr merge` method.
  Default **`--squash`** (clean trunk history). Never `--admin`, never force.
- **`--poll-interval <seconds>`** (optional) — CI poll interval. Default **30s**.
- **`--timeout <seconds>`** (optional) — per-PR CI wait timeout. Default
  **1800s** (30 min). On elapse the run aborts the remaining stack (§3.3).

## 1. Preflight (fail fast, never hang)

Confirm the land can run before touching any PR. A missing dependency must stop
the whole run up front rather than half-land the stack:

```bash
command -v gh >/dev/null 2>&1 || echo "BLOCKER: gh not installed"
gh auth status 2>&1            # non-zero / "not logged into" ⇒ blocker
```

If `gh` is absent or unauthenticated, **report a clear blocker and merge nothing**
— do not start the loop and do not hang on an interactive auth prompt.
Distinguish this up-front blocker (nothing merged) from a mid-run abort (some PRs
already merged, see §3.3 / §6).

Resolve the trunk branch name once (the `--trunk` value, else the `trunk()`
bookmark's branch); every retarget (§4.3) and the post-merge fetch (§5.1) use it.

## 2. Derive the bottom-up stack order from jj

### 2.1 Order from a jj revset, oldest-first

Read the merge order from the **jj stack**, not from the PRs' `base` fields. The
linear order of changes from trunk upward is the merge order:

```bash
jj log -r 'trunk()..<top> & bookmarks()' \
  --ignore-working-copy --no-pager --no-graph --reversed \
  -T 'bookmarks ++ "\n"'
```

`--reversed` yields **oldest-first** (trunk-adjacent change first) — the exact
bottom-up merge order. `& bookmarks()` keeps only the bookmarked changes (the
stack's PR units), skipping intervening unbookmarked commits. Strip trailing
tags/whitespace the template emits. If no `<top>` was given, resolve the tip
first (§Arguments) and substitute it here.

Reading order from jj rather than from each PR's `base` field means the order is
correct even before any retargeting has happened and even if a PR's base was set
by hand.

### 2.2 Map each change to its bookmark and its open PR

For each bookmark in the ordered list, resolve its open GitHub PR by head branch:

```bash
gh pr list --head <bookmark> --state open --json number,url --jq '.[0]'
```

- **One open PR** → that is the PR to land for this change.
- **Already merged** (no open PR; confirm with `gh pr view <bookmark> --json state`
  → `MERGED`) → skip it (§2.3) — a re-run resumes past it.
- **No open and no merged PR** → report this change has no PR and **stop** before
  merging anything above it; do not open one (that is `/jj-pr`'s job).

### 2.3 Skip already-merged changes (resume-from-first-open)

A change whose PR is already `MERGED` is skipped: it stays in the cleanup set
(§5) but is not re-merged. This makes a re-run after a partial land resume from
the first **still-open** PR, re-deriving order from the now-shorter jj stack — so
"fix the red check, run `/jj-land` again" is the natural recovery path.

### 2.4 Strict bottom-up sequencing

Process the ordered list **bottom-up (oldest-first)** and merge strictly in that
order. NEVER consider an upper PR until every PR beneath it has merged — even if
an upper PR's checks go green first. This preserves the invariant that each PR
merges against trunk (or a still-open lower branch), never against a branch about
to disappear underneath it. Order is read from jj (§2.1), not from PR metadata.

## 3. Per-PR CI wait (poll with timeout, gated on GitHub's verdict)

For each not-yet-merged PR in turn, **wait for its required checks before
merging**. Poll on the configured interval until GitHub reports the required
checks succeeded:

```bash
gh pr checks <pr> --json bucket,state,name             # per-check buckets
gh pr view  <pr> --json statusCheckRollup,mergeStateStatus,state
```

- **Required checks all `pass` / rollup success** → proceed to merge (§4).
- **Still pending/running** → sleep `--poll-interval` and poll again, bounded by
  `--timeout` (§3.3). Do NOT loop indefinitely.

### 3.1 Use a bounded, non-interactive poll

Each poll is a single non-interactive `gh` call; between polls wait the interval
with a bounded sleep, and track elapsed time against `--timeout`. Never block on
an interactive prompt and never wait forever — the timeout is the hard ceiling.

### 3.2 Required-check verdict comes from GitHub, not from this skill

The skill reads the check state GitHub reports (`statusCheckRollup`,
`mergeStateStatus`); it does not define what "required" means. It merges only on
GitHub's own success verdict and never bypasses a non-success verdict.

### 3.3 Clean abort on a red check or an elapsed timeout

On a **failing** required check, or when `--timeout` elapses with checks not yet
green, **abort the remaining stack cleanly**:

- Merge nothing further; leave the offending PR and every PR above it **open**.
- Leave every PR **merged so far merged** — landing is forward-only, never rolled
  back.
- Run the cleanup pass (§5) over the PRs that actually merged, then report which
  PR stopped the run and why (`checks-red` vs `waiting-timed-out`, §4.4 / §6).

A re-run after a fix resumes from the first still-open PR (§2.3).

## 4. Merge and base retargeting

### 4.1 Merge the gated PR (no force, no admin)

Once the PR's required checks pass, merge it with the configured method —
**without** `--delete-branch` (branch removal is done explicitly in §5.2):

```bash
gh pr merge <pr> --squash                         # --method default: squash
#   or --merge / --rebase per --method; NEVER --admin, NEVER force
#   NOTE: no --delete-branch — see the colocated gotcha below
```

Then **confirm the merge by PR state, not by the command's exit code**:

```bash
gh pr view <pr> --json state --jq '.state'        # expect: MERGED
```

A `state` of `MERGED` means the merge succeeded; proceed (the head branch is
removed in §5.2). The skill SHALL NOT pass `--admin`, SHALL NOT force, and SHALL
NOT override branch protection.

**Colocated gotcha — why `--delete-branch` is dropped and exit code is not
trusted.** In a colocated jj↔git repo, jj keeps git HEAD **detached** (jj owns
the refs, not git branches). `gh pr merge … --delete-branch` then fails its
*local*-branch cleanup step with `could not determine current branch: failed to
run git: not on any branch`, which (a) makes `gh pr merge` **exit non-zero even
though the remote merge succeeded**, and (b) **aborts before the server-side
branch delete**, leaving the remote branch as a straggler. So the merge step
omits `--delete-branch` (no local step to fail) and judges success from
`gh pr view --json state`; §5.2 deletes the remote branch explicitly.

### 4.2 Branch-protection / merge-blocked is a reported blocker

If the merge is rejected by branch protection, a required review, an out-of-date
base that retargeting cannot fix, or a conflict, **report it as a blocker and
stop** the remaining stack (the same clean-abort shape as §3.3, reason
`blocked`). Do NOT escalate with `--admin`, do NOT force, do NOT resolve a
conflict in the merge UI. Lower PRs stay merged; this PR and everything above it
stay open for the operator.

### 4.3 Retarget the next PR's base to trunk, before its CI wait

After PR *n* merges, its merged commits are on trunk and its head branch is gone.
Retarget the **next-up** PR (*n+1*)'s base to trunk **before** waiting on *n+1*'s
checks, so *n+1*'s checks run against the correct base:

```bash
gh pr edit <pr_{n+1}> --base <trunk>
```

Retargeting to **trunk** (not to the next surviving lower branch) is correct
because lower PRs always merge before upper ones — by the time *n+1* is
considered, its entire downstack is already on trunk. Skip the edit if *n+1*'s
base is already `<trunk>` (avoid a no-op). This is the step that prevents the
orphaned-child hazard: the child is always merged onto trunk, never onto a
deleted parent branch.

### 4.4 Record per-PR outcomes and retarget bases

For the final report (§6), record per PR: its outcome —
`merged` / `waiting-timed-out` / `checks-red` / `blocked` — and, for each PR
whose base was retargeted, the **base value set** (e.g. `feat/api → main`).

## 5. Post-merge cleanup (one tail pass, merged-only)

After the loop completes **or** aborts, run a single cleanup pass that acts
**only on the PRs that actually merged**. An aborted run's un-landed tail (PRs,
bookmarks, workspaces) is left fully intact for a re-run.

### 5.1 Sync local trunk

```bash
jj git fetch --no-pager
```

Brings the merged commits onto the local trunk-tracking bookmark so the local
trunk reflects what landed on GitHub.

### 5.2 Delete merged bookmarks and their remote branches

For each change whose PR merged, delete BOTH its local bookmark and its remote
head branch (§4.1 no longer deletes the branch server-side); leave un-merged PRs'
bookmarks and branches intact:

```bash
# local bookmark
jj bookmark delete <name> --no-pager
# remote head branch — explicit, since the merge no longer passes --delete-branch.
# Resolve <owner>/<repo> once: gh repo view --json nameWithOwner --jq .nameWithOwner
gh api -X DELETE "repos/<owner>/<repo>/git/refs/heads/<branch>"
```

The remote-branch delete is **idempotent**: an already-absent branch returns
404/422, which is treated as success (e.g. a re-run, or a branch GitHub auto-
deleted). Both deletes are keyed on **merge state** — never delete a bookmark or
remote branch whose PR did not merge. This explicit remote delete is what keeps
`origin` free of stragglers now that the merge step omits `--delete-branch`
(which fails under colocated jj — see §4.1).

### 5.3 Forget stale workspaces via jj-delegate Teardown

For each merged change that still has a linked jj workspace, forget that
workspace by **deferring to the `jj-delegate` capability's Teardown mechanism**
(`jj workspace forget <name>` + removing the workspace directory). Do NOT
re-implement workspace lifecycle here — the [`jj-delegate`](../jj-delegate/SKILL.md)
Teardown requirement owns that surface; this skill only triggers it for the
merged changes.

### 5.4 Cleanup is strictly merged-only

Cleanup SHALL NOT touch un-merged PRs, their bookmarks, or their workspaces. An
aborted run (§3.3 / §4.2) cleans up only the PRs that landed and leaves the tail
exactly as it was, so the re-run finds the surviving stack intact.

## 6. Report (report-shaped result)

Return a compact, ordered result the reconcile tail can surface:

- **Per-PR outcome list**, bottom → top: each `bookmark → PR → outcome`, where
  outcome is `merged` / `waiting-timed-out` / `checks-red` / `blocked` /
  `skipped-already-merged`, plus the **base value set** for each retargeted PR.
- **Where the run stopped**, if it aborted: the stopping PR and the reason
  (`checks-red`, `waiting-timed-out`, `blocked`).
- **Cleanup summary**: trunk fetched (yes/no), the bookmarks deleted, the remote
  branches deleted, and the workspaces forgotten — all keyed to the merged
  changes only.

Example shape:

```
landed (bottom → top):
  1. feat/data-layer  #40  merged   base=main
  2. feat/api         #41  merged   base set: feat/data-layer → main
  3. feat/ui          #42  checks-red  (run stopped here)
stopped: #42 feat/ui — required check failed
cleanup: jj git fetch ✓ | bookmarks deleted: feat/data-layer, feat/api |
         remote branches deleted: feat/data-layer, feat/api |
         workspaces forgotten: wt-data-layer, wt-api
```

## Failure modes (each reported, none improvised)

- **`gh` absent/unauthenticated** → up-front blocker, nothing merged (§1).
- **A stacked change has no open PR** → reported, stop before merging above it;
  never open one here (§2.2).
- **Red required check / wait-timeout** → clean abort of the remaining stack;
  merged PRs stay merged, tail stays open, cleanup runs over merged-only (§3.3).
- **Branch protection / required review / conflict blocks a merge** → reported as
  a blocker, stop; never `--admin`, never force, never resolve in the merge UI
  (§4.2).
- **Retarget races a human editing the same PR** → `gh pr edit --base` is
  last-writer-wins; the skill sets the base it computed and reports it (§4.4), so
  a divergence is visible, not silent.
- **A jj command itself hangs** → do not retry blindly and NEVER delete `.jj`;
  `jj op log` / `jj op restore` is the orchestrator-only recovery surface.

## Composition (lands PRs, does not open or own them)

`/jj-land` is the **land** step of the reconcile tail, downstack of the submit
steps:

- It lands the PRs that [`jj-pr`](../jj-pr/SKILL.md) (single change) and
  [`jj-stacked-pr`](../jj-stacked-pr/SKILL.md) (a based stack) opened — but it
  lands **hand-opened PRs equally**. Its only precondition on each stacked change
  is that the change has an open GitHub PR for its bookmark's head branch.
- It has **no dependency** on any in-flight change being canonical: the
  references to `jj-github-pr` (`/jj-pr`) and to `jj-delegate` Teardown are
  one-directional (this skill points at them); it changes no requirement of
  either.
- It defers the workspace-forget step to the
  [`jj-delegate`](../jj-delegate/SKILL.md) Teardown requirement (§5.3) rather than
  duplicating workspace-lifecycle logic.

## Where this is called

`/jj-land` is the land step of the [`jj-delegate`](../jj-delegate/SKILL.md)
reconcile tail: once the fan-out's changes are stitched into a stack and their
PRs are open (via `/jj-pr` / `/jj-stacked-pr`), `/jj-land [<top>]` lands the whole
stack bottom-up and tidies up. It composes over `gh` for the merge/poll/retarget
and over jj for the order derivation and cleanup; it never opens PRs, never
reshapes the stack, and never forces a merge.
