---
name: jj-pr-fixup
description: |
  Run the automated amend-after-review loop over a GitHub PR in one
  orchestrator step — the jj successor to Graphite's amend-after-review. Given a
  PR (number or URL), it reads that PR's review comments via `gh` (file/line-
  anchored review threads + the review summary, unresolved only), composes them
  into a single worker brief, dispatches a `jj-workspace-worker` on a workspace
  based on the PR head (`jj workspace add -r <pr-head-rev>`) so fixes apply on
  top of exactly the commits under review, lands the worker's working-copy fixes
  into their owning downstack commits via the `/jj-absorb` step, then re-pushes
  and updates the same PR in place via the `/jj-pr` step — so a reviewer asking
  to fix commit B gets commit B amended, not a fixup commit dangling at the tip.
  Triggers: /jj-pr-fixup, "fix up the PR from review comments", "amend the PR's
  commits after review", "address review comments and update the PR". Composes
  /jj-delegate (dispatch), /jj-absorb (land), and /jj-pr (push/update); defines
  only the comment→brief mapping, PR-head basing, and the orchestration.
  Orchestrator-only (owns workspace lifecycle, absorb, refs, push); never invoked
  inside a worker. Requires a colocated jj↔git repo with an `origin` remote, the
  PR head branch fetchable locally, `gh` authenticated with PR-comment read
  scope, and the `/jj-absorb` and `/jj-pr` skills present.
metadata:
  version: "0.1.0"
  author: outfitter-style
---

# jj-pr-fixup — automated amend-after-review over an existing PR

You are the **orchestrator**. When a PR comes back with review comments, the
fixes belong in the *original* commits under review — not in a fresh "address
review" commit dangling at the tip. A reviewer asking to rename a symbol in
commit B wants commit B amended, not a fixup commit at HEAD. The Graphite
predecessor did this by hand (find the commit, amend it, repeat). This skill is
the jj conductor: it reads the PR's review comments, briefs a worker to address
them on a workspace **based on the PR head**, lands each fix into the commit it
belongs to via `/jj-absorb`, then updates the same PR via `/jj-pr`.

This skill **composes** existing pieces; it does not reimplement them. It owns
only three things: the **comment → worker-brief mapping**, the **PR-head
basing**, and the **orchestration** that strings the pieces together. The
hunk-landing step is delegated to [`/jj-absorb`](../jj-absorb/SKILL.md)
(capability `jj-absorb-fixup`) and the push-and-update step to
[`/jj-pr`](../jj-pr/SKILL.md) (capability `jj-github-pr`). Worker provisioning
and dispatch follow [`/jj-delegate`](../jj-delegate/SKILL.md).

Substrate knowledge (jj command surface, revsets, non-interactive rules, output
formats) comes from the installed `jj-vcs` skill — defer to it for jj command
detail; this skill owns only the read-comments → dispatch → absorb → push loop.

## Preconditions (verify, don't assume)

- **Orchestrator role only.** This skill owns workspace lifecycle, absorb, refs,
  and push — all of which the worker contract forbids. NEVER invoke
  `/jj-pr-fixup` inside a worker. It runs in the primary/default workspace, the
  role that owns all bookmarks and pushes.
- **Colocated jj↔git repo with an `origin` remote.** Reading the PR and pushing
  the update both need a GitHub remote. If there is no `origin` remote, stop and
  report — this skill creates no remotes.
- **The PR head branch is fetchable locally.** Provisioning bases the worker on
  the PR head resolved to a *local* jj revision; if it cannot be resolved or
  fetched, that is a reported blocker before any workspace is provisioned (§4).
- **`gh` available and authenticated with PR-comment read scope.** A missing,
  unauthenticated, or under-scoped `gh` is a reported blocker for the
  comment-fetch step — never an empty brief that masquerades as "no comments"
  (§1, §3).
- **The `/jj-absorb` and `/jj-pr` skills are present.** They are in-flight
  composition dependencies. If either is unavailable in the session, report a
  clear blocker for that step — NEVER open-code an absorb or a push in their
  place (§1).
- **Every command non-interactive.** Always `jj … --no-pager`; reads use
  `--ignore-working-copy`; never `-i` / `--interactive`; never spawn an editor.
  `gh` calls are non-interactive (`gh auth status`, `--json`) and return
  promptly, so nothing here hangs.

## Arguments

```
/jj-pr-fixup <pr> [--workspace <path>] [--base <rev>]
```

- **`<pr>`** (required) — the PR to fix up, as a number or a full GitHub URL.
- **`--workspace <path>`** (optional) — explicit fixup-workspace directory;
  defaults to a derived `../wt-pr-fixup-<pr>` sibling per `/jj-delegate`.
- **`--base <rev>`** (optional) — override the resolved PR-head revision the
  worker is based on. Default and intended path is the resolved PR head; this
  escape hatch exists only for a deliberately different base, not routine use.

## 1. Dependency preflight (fail fast, never hang, never improvise)

Before reading anything, confirm every composed piece can run. Each missing
piece is a reported blocker, not a silent workaround.

```bash
command -v gh >/dev/null 2>&1 || echo "BLOCKER: gh not installed"
gh auth status 2>&1            # non-zero / "not logged into" ⇒ blocker
```

- **`gh` absent / unauthenticated** → report a clear blocker for the
  comment-fetch step and stop before provisioning anything. Do not proceed with
  an empty brief.
- **`/jj-absorb` or `/jj-pr` not present in the session** → confirm both skills
  are available before dispatch. If either is missing, report a clear blocker
  for that step and STOP — never substitute an open-coded absorb (`jj squash`
  guesses) or an open-coded push (`jj git push` + `gh pr edit`) for the skill
  it stands in for. This is the contract that keeps the loop reusing A4/D1
  rather than re-deriving their behaviour with drift risk.

Distinguish these up-front blockers, where nothing was done, from a mid-run
failure where fixes were already absorbed (see §6).

## 2. Resolve the PR (identity + head branch)

Normalise `<pr>` (number or URL) to a PR number and read its identity, head
branch, and state:

```bash
gh pr view <pr> --json number,headRefName,headRefOid,url,state,title --jq '.'
```

- A **closed/merged** PR is a reported blocker — there is nothing to update in
  place. Stop.
- Record `headRefName` (the head branch) and `url` for §4 and §6.

## 3. Read review comments → worker brief

The filtering is **deterministic orchestration work** that belongs to the
conductor; do NOT pass a raw comment dump and let the worker filter.

### 3a. Fetch review summary + line-anchored threads

Read both the review summaries and the file/line-anchored review-comment
threads via `gh` (settle the exact surface against the installed `gh`):

```bash
# Review summaries (APPROVE / REQUEST_CHANGES / COMMENT bodies):
gh pr view <pr> --json reviews --jq '.reviews[] | {author: .author.login, state, body}'

# File/line-anchored review-comment threads:
gh api repos/{owner}/{repo}/pulls/<pr>/comments \
  --jq '.[] | {path, line, original_line, body, in_reply_to_id, id}'
```

`{owner}/{repo}` come from `gh repo view --json nameWithOwner` (or the resolved
PR). Prefer the line-anchored comment API for the precise file/line context;
fold the review-summary bodies in as PR-level context.

### 3b. Exclude resolved and outdated threads

Filter out **resolved** and **outdated** threads up front — feeding resolved or
outdated comments produces churn and contradicts what the reviewer currently
wants. (Thread resolution lives on the GraphQL review-thread surface
`pullRequest.reviewThreads { isResolved isOutdated comments }`; use it to drop
resolved/outdated threads when the REST comment list does not expose resolution.)

### 3c. No-actionable-comments path

If, after filtering, **no actionable comments remain** (all resolved/outdated,
or the PR has no review comments), report **"no actionable comments"** and
**STOP** — make no commits, no absorb, no push, and **do not dispatch a worker
against an empty brief**. Surfacing that cleanly is the correct outcome.

### 3d. Compose the single worker brief

Compose the remaining items into **one** worker brief that preserves, for each
comment, its **file path**, **line/anchor**, and **body** so the worker can
locate and address each item — plus the **workspace path** and the **resolved
base revision** (§4). The review-summary bodies provide PR-level intent. The
brief MUST also state the worker-role fence: address comments inside the
workspace only, shape own commits, NEVER touch bookmarks / push / raw mutating
git (per the `jj-delegate` role split).

## 4. Provision the worker on the PR head

Per `/jj-delegate`'s explicit-base-revision rule, base the worker on the PR head
resolved to a *local* jj revision — never `@` or trunk — so the fixes apply on
top of exactly the commits under review and `/jj-absorb` can later land each
hunk into its owning commit.

### 4a. Resolve the PR head to a local revision (fetch when needed)

```bash
jj log -r <headRefName> --ignore-working-copy --no-pager -T 'change_id.short()' --no-graph 2>&1
# If the branch is not present locally, fetch it (orchestrator-owned),
# then re-resolve. If it still cannot be resolved → BLOCKER.
```

If the PR head branch **cannot be resolved or fetched to a local jj revision**,
report a clear blocker and **provision no workspace**. (Basing on `@` or trunk
would detach the fixes from the commits the reviewer commented on and defeat
absorb — so a missing head is a hard stop, not a substitution.)

### 4b. Provision

```bash
jj workspace add -r <pr-head-rev> <workspace-path>     # -r required; explicit base
```

`<pr-head-rev>` is the resolved local revision from §4a (or the `--base`
override). `<workspace-path>` defaults to the derived sibling (§Arguments).

### 4c. Dispatch (background by default)

Dispatch a single `jj-workspace-worker` subagent with the §3d brief, in the
background by default per `/jj-delegate` (`run_in_background: true`). The worker
addresses the review comments inside its workspace and shapes only its own
commits; its working-copy edits are snapshotted into `@` automatically. It does
NOT touch bookmarks, push, or run raw mutating git — all of that is the
orchestrator's in §5–§6.

## 5. Absorb fixes into their owning commits

After the worker reports, land its working-copy fixes into their owning
downstack commits by invoking the [`/jj-absorb`](../jj-absorb/SKILL.md) step
over the worker's fixes — do NOT re-derive placement here.

- `/jj-absorb` previews with `jj absorb --dry-run`, runs the mutating
  `jj absorb`, and reports each hunk keyed to its **destination change-id +
  description first line** — so each fix lands in the commit a reviewer
  commented on rather than as a new tip commit.
- **Any hunk with no unambiguous downstack home** is surfaced by `/jj-absorb`'s
  remainder handling for deliberate placement — it is **NOT** force-fitted into
  a guessed commit and **NOT** silently pushed as a new tip commit. Carry that
  remainder into the final report (§6) as items still needing manual placement;
  do not paper over them.
- **Capture the per-hunk landing report** (fix → destination change-id /
  description) from `/jj-absorb` for the final result.

If the worker reports a **blocker** instead of clean fixes, do not absorb or
push: surface the blocker, leave the workspace intact for a resume (§7), and
stop.

## 6. Update the PR in place

Once fixes are absorbed, re-push and update the **existing** PR via the
[`/jj-pr`](../jj-pr/SKILL.md) step — `/jj-pr` already handles create-or-update
idempotence and one-time remote tracking, so reuse it rather than open-coding
`jj git push` + `gh pr edit`.

```
/jj-pr <bookmark>      # bookmark = the PR head branch
```

- Because `/jj-pr` keys on the head branch, this **updates the same PR in
  place** with the amended commits — it does **not** open a second PR for the
  same head branch, and it does **not** force-push beyond what `/jj-pr`
  performs.
- **Push-step failure is reported distinctly.** If absorb succeeded but the
  `/jj-pr` push-and-update step fails, report **"fixes absorbed, PR not
  updated"** — distinct from overall success. Never silently report the loop as
  complete when the PR was not updated.

## 7. Teardown (or leave intact for resume)

- **On a clean loop** (worker fixes absorbed, PR updated), tear the fixup
  workspace down per `/jj-delegate`: `jj workspace forget <workspace-name>` then
  remove the workspace directory.
- **On a worker blocker** (or a conflict the worker could not resolve), leave
  the workspace **intact** so a fresh worker can resume in the SAME workspace
  with a resume brief, per `/jj-delegate`. Never tear down work that is not done.

## 8. Report (report-shaped result)

Return a compact result:

- **comments** — how many actionable comments were briefed (or "no actionable
  comments", or the fetch blocker).
- **base** — the resolved PR-head revision the worker was provisioned on.
- **worker** — done / blocked (with the blocker if any).
- **absorbed** — the per-hunk landing report (fix → destination change-id +
  description) from `/jj-absorb`, plus any `remaining (manual)` items.
- **pr** — updated (with the URL) / "fixes absorbed, PR not updated" / not
  reached.

Example shape:

```
comments: 3 actionable (1 resolved thread excluded)
base:     kostkqrq  (PR head feat/add-export)
worker:   done
absorbed:
  src/auth.ts (40-47)  → kostkqrq  feat: validate session token
  README (12-14)       → nvrnonuw  docs: document the config flag
pr:       updated  https://github.com/org/repo/pull/42
```

## Failure modes (each reported, none improvised)

- **`gh` absent / unauthenticated / under-scoped** → up-front blocker, nothing
  provisioned; no empty brief masquerading as "no comments" (§1, §3).
- **`/jj-absorb` or `/jj-pr` skill missing** → blocker for that step; never
  open-coded (§1).
- **PR closed/merged, or head not resolvable locally** → reported blocker, no
  workspace provisioned (§2, §4a).
- **All comments resolved/outdated** → "no actionable comments", no dispatch,
  no commits, no push (§3c).
- **Ambiguous fix (no unambiguous downstack home)** → surfaced by `/jj-absorb`
  remainder handling for manual placement; never force-fitted or pushed as a
  tip commit (§5).
- **Worker's fixes conflict on integration** → governed by `jj-delegate`'s
  "integration never halts": the rebase succeeds with a first-class conflict the
  orchestrator resolves by editing markers, never interactive `jj resolve`.
- **Absorb ok, push step errors** → "fixes absorbed, PR not updated", distinct
  from overall success (§6).
- **A jj command itself hangs** → do not retry blindly and NEVER delete `.jj`;
  `jj op log` / `jj op restore` is the orchestrator-only recovery surface.

## Where this is called

`/jj-pr-fixup` is the automated **amend-after-review loop** over an existing PR
— the conductor for the same reconcile-tail family as `/jj-absorb` and `/jj-pr`:

- It **dispatches** a worker via [`/jj-delegate`](../jj-delegate/SKILL.md),
  based on the PR head.
- It **lands** the worker's fixes via [`/jj-absorb`](../jj-absorb/SKILL.md) §5,
  keyed to each fix's owning downstack commit.
- It **updates** the PR via [`/jj-pr`](../jj-pr/SKILL.md), in place, idempotently.
