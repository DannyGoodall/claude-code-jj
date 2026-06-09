---
name: jj-keep-current
description: |
  Bring a jj stack up to date with trunk and answer "is it safe to land?" in one
  orchestrator step — the currency precondition a land flow consults. Given a
  stack (its tip bookmark, or the current stack) and a resolved trunk bookmark,
  it (1) `jj git fetch`es trunk and compares the stack's base to the freshly
  fetched trunk tip; if trunk has not moved it skips straight to the gate (no-op
  fast path), otherwise it `jj rebase`s the stack onto the new trunk with jj's
  never-halt semantics (the rebase always exits 0; any conflict is recorded as a
  first-class conflicted change, never auto-resolved, never via interactive
  `jj resolve`) and — only on a conflict-free rebase — pushes the moved
  bookmark(s) so the PR rebuilds against the new base; then (2) runs a CI gate
  off the PR's required checks (`gh pr checks <ref> --required`, falling back to
  all checks), with a bounded poll for pending checks after a push. It emits a
  single typed verdict — landable (current + green) or not-landable/hold with a
  reason from `trunk-moved`, `rebase-conflicted`, `ci-failing`, `ci-pending`,
  `ci-missing` — that a human or `/jj-land` consumes. Triggers: /jj-keep-current,
  "keep this stack current", "is this stack current and green?", "rebase onto
  trunk and re-check CI before landing". The currency precondition upstack of
  /jj-land in the reconcile tail. Orchestrator-only (owns fetch, rebase, push,
  and PR/CI reads); never invoked inside a worker. Non-interactive (`jj …
  --no-pager`, no interactive `jj resolve`, bounded waits, `gh` with explicit
  flags). Requires a colocated jj↔git repo with an `origin` remote, a resolved
  trunk bookmark, and `gh` authenticated.
metadata:
  version: "0.1.0"
  author: outfitter-style
---

# jj-keep-current — bring a jj stack current with trunk and gate landing on CI

You are the **orchestrator**. A jj stack that was green when it was pushed goes
stale the moment trunk moves: another stack merges, a hotfix lands, and the PR
may now merge dirty, fail CI against the new base, or land code only ever tested
against an old trunk. jj makes the fix cheap — `jj rebase` never halts; it
rebases the whole stack in one shot and records each conflict as a first-class
object rather than dropping you into a halted, interactive rebase. This skill
automates the loop "detect trunk moved → fetch → rebase the stack → push →
re-check CI" and gates landing behind a green required-checks signal, emitting a
single **landable / not-landable** verdict.

It is the standalone *"is this stack current and green?"* precondition that a
land flow consults. It defines a clear verdict contract **without depending on
`/jj-land` (D4) existing**: if D4 lands, its skill calls this one and lands only
on `landable`; but this capability stands alone and is independently testable.

Substrate knowledge (jj command surface, revsets, templates, non-interactive
rules) comes from the installed `jj-vcs` skill — defer to it for jj command
detail; this skill owns only the keep-current choreography. It reuses the
[`jj-delegate`](../jj-delegate/SKILL.md) **"Integration never halts"** invariant
for its rebase — it references that invariant, it does not change it.

## Preconditions (verify, don't assume)

- **Orchestrator role only.** This skill performs `jj git fetch`, `jj rebase`,
  `jj git push`, and reads PR/CI status — every one reserved to the orchestrator
  and forbidden to the worker contract. NEVER invoke `/jj-keep-current` inside a
  worker. It runs in the primary/default workspace, the role that owns every
  fetch, rebase, push, and ref.
- **Colocated jj↔git repo with an `origin` remote.** The fetch and push target
  `origin`; PR/CI reads need a GitHub remote. If there is no `origin` remote,
  stop and report — this skill does not create remotes.
- **A resolved trunk bookmark.** The trunk bookmark (`main` / `master` / `trunk`
  / repo-specific) is a **resolved input** — the `--trunk` argument, else the
  repo's `trunk()`. It is **never hardcoded**. If it cannot be resolved, stop and
  report.
- **`gh` available and authenticated.** The CI gate is `gh`; a missing or
  unauthenticated `gh` is a reported blocker checked up front (§1), not an
  improvised workaround. The skill never spawns an editor, never force-pushes,
  never force-rebases.
- **Each stack unit already has an open GitHub PR for its bookmark's head
  branch.** This skill reads CI for an existing PR; it does not open one (that is
  `/jj-pr` / `/jj-stacked-pr`). A stack unit with no PR is reported, not guessed.

## Arguments

```
/jj-keep-current [<top-bookmark>] [--trunk <bookmark>] \
                 [--poll-interval <seconds>] [--max-attempts <n>]
```

- **`<top-bookmark>`** (optional) — the tip of the stack to keep current; its
  ancestry over `trunk()..<top>` is the stack (§2). If omitted, infer the tip
  from the current stack (the bookmarked change at the head of `trunk()..@`); if
  that is ambiguous (more than one tip), report and stop rather than guess.
- **`--trunk <bookmark>`** (optional) — the trunk bookmark to fetch, compare
  against, and rebase onto. Defaults to the repo's resolved `trunk()` bookmark.
  Resolved, never hardcoded.
- **`--poll-interval <seconds>`** (optional) — CI re-check poll interval after a
  push. Default **30s**.
- **`--max-attempts <n>`** (optional) — maximum CI re-check polls before the loop
  returns its last result. Default **10**. The loop is **bounded** — it never
  waits indefinitely.

## 1. Dependency preflight (fail fast, never hang)

Before touching the remote, confirm the gate can run, and resolve the trunk
bookmark name once (every fetch, compare, and rebase below uses it):

```bash
command -v gh >/dev/null 2>&1 || echo "BLOCKER: gh not installed"
gh auth status 2>&1            # non-zero / "not logged into" ⇒ blocker
```

If `gh` is absent or unauthenticated, **report a clear blocker and do nothing
further** — do not fetch, rebase, or push, and do not hang on an interactive
auth prompt (`gh auth status` is non-interactive and returns promptly).

Resolve `<top-bookmark>` (or the inferred tip) and the trunk bookmark now. If the
tip is ambiguous or the trunk bookmark cannot be resolved, report and stop.

## 2. Detect trunk movement (fetch, then compare — with a no-op fast path)

Fetch the resolved trunk bookmark, then read its freshly-fetched tip:

```bash
jj git fetch -b <trunk> --no-pager
```

Identify the **stack base** — the trunk-adjacent parent the stack currently sits
on — and the **fetched trunk tip**, and compare them by revset:

```bash
# stack base: the parent of the oldest change in trunk()..<top>
jj log -r 'roots(trunk()..<top>)-' \
  --ignore-working-copy --no-pager --no-graph -T 'commit_id ++ "\n"'
# fetched trunk tip
jj log -r '<trunk>' \
  --ignore-working-copy --no-pager --no-graph -T 'commit_id ++ "\n"'
```

- **Trunk has NOT moved** — the stack base already equals the fetched trunk tip.
  **Skip rebase and push entirely** (the no-op fast path) and go straight to the
  CI gate (§5). This avoids needless pushes that re-trigger CI and churn the
  merge queue. The stack is already current; only the gate decides landability.
- **Trunk HAS moved** — the fetched trunk tip differs from the stack base.
  Proceed to rebase (§3). The currency reason for any not-green verdict that
  follows is informed by this (the stack *was* `trunk-moved` and is now being
  brought current).

Reading the base from the jj stack (not from a PR's `base` field) keeps the
comparison correct even before any retargeting and regardless of hand-edited PR
bases.

## 3. Never-halt auto-rebase onto the moved trunk

When trunk has moved, rebase the **whole stack** onto the fetched trunk tip:

```bash
jj rebase -b <top> -d <trunk> --no-pager
```

This **always exits 0** — it inherits the [`jj-delegate`](../jj-delegate/SKILL.md)
**"Integration never halts"** invariant. Where a git rebase stops at the first
conflicting hunk and forces interactive resolution, jj rebases the whole stack in
one shot, records each conflict as a **first-class conflicted change** inside the
resulting change, and exits cleanly. The skill SHALL NOT invoke interactive
`jj resolve` and SHALL NOT silently resolve conflicts.

### 3.1 Inspect the rebased stack for conflicts

After the rebase, inspect the rebased changes for conflicted state and collect
the conflicted change-ids and the conflicting file paths:

```bash
# conflicted changes in the rebased stack
jj log -r 'trunk()..<top> & conflicts()' \
  --ignore-working-copy --no-pager --no-graph \
  -T 'change_id ++ " " ++ description.first_line() ++ "\n"'
# per-conflicted-change file paths
jj resolve --list -r <conflicted-change> --no-pager   # LIST only — never the interactive resolve
```

(`jj resolve --list` is the read-only listing form; it is **not** the forbidden
interactive `jj resolve`. Do not omit the `--list` and do not pass `-i`.)

### 3.2 A conflicted rebase blocks land — report, do NOT push

If **any** rebased change is conflicted, the verdict is **not-landable with
reason `rebase-conflicted`**:

- Report the conflicted **change-ids** and the conflicting **file paths** (§3.1).
- **Do NOT push** the conflicted stack — the remote PR is left untouched until a
  human resolves.
- Never auto-resolve and never invoke interactive `jj resolve`.

The local stack is left conflicted-but-recoverable (a jj first-class conflict,
`jj op restore`-able). Resolution is a deliberate human/orchestrator follow-up,
out of this skill's scope (a Non-Goal). Stop here and emit the verdict (§6).

## 4. Push the rebased stack (only after a conflict-free rebase)

When the rebase onto the moved trunk is **conflict-free**, push the moved
bookmark(s) so the PR rebuilds against the new base:

```bash
jj git push -b <each moved bookmark> --no-pager
```

Push each bookmark in the stack that the rebase moved. This is what makes the
PR's CI re-run against the new trunk. **Never force-push** — force is an
orchestrator decision outside this skill's scope; a rejected push is reported,
not forced. After a successful push, proceed to the CI gate with the bounded
re-check loop (§5), because the push has invalidated any prior CI verdict.

## 5. CI gate (off required checks, bounded re-check after a push)

The gate reads the PR's CI status via `gh` and maps it to a gate state. Run it
against the relevant head: after the no-op fast path (§2) it runs once against
the current head; after a push (§4) it runs in the bounded re-check loop below.

### 5.1 Read required checks, fall back to all checks

```bash
gh pr checks <ref> --required --json bucket,state,name   # required checks
# if NONE are marked required, fall back to all checks:
gh pr checks <ref>            --json bucket,state,name
```

Use `--required` when required checks are configured; when none are marked
required, fall back to **all** checks. The skill reads the check states GitHub
reports — it does not define what "required" means.

### 5.2 Map check states to a gate state

- **Any failing or errored check** ⇒ **`ci-failing`** (block — not-landable).
- **Any pending or queued check** (and none failing) ⇒ **`ci-pending`** (hold;
  poll in §5.3 when this followed a push).
- **All evaluated checks succeed AND at least one check exists** ⇒ **green**.
- **Zero checks at all** ⇒ **`ci-missing`** — surfaced **explicitly**, **never**
  folded into a green gate. "No CI" silently passing is the dangerous default;
  this skill reports `ci-missing` and lets the caller decide policy. The gate is
  green **only** when at least one check exists and every evaluated check
  succeeds.

### 5.3 Bounded re-check loop after a push

A fresh push triggers a **new** CI run that needs time to register, so an
immediate single re-check would almost always read `ci-pending`. After a push,
re-run the gate; while it is `ci-pending`, **poll** at `--poll-interval` up to
`--max-attempts`, then return the last gate result:

- Each poll is a single non-interactive `gh pr checks` call; between polls wait
  the interval with a bounded sleep and count against `--max-attempts`.
- Return as soon as the gate is **non-pending** (green / `ci-failing` /
  `ci-missing`), or once the attempt budget is exhausted.
- If checks remain pending past `--max-attempts`, return a **`ci-pending` hold**
  — **not** a failure. The verdict is re-runnable; the caller retries later. The
  loop is **bounded** and SHALL NOT wait indefinitely (an unbounded wait would
  hang a long-lived session — a command-hygiene violation).

(The no-op fast path with no push runs the gate **once**, with no poll — there is
no freshly-triggered run to wait for.)

## 6. Verdict (single typed result)

Emit **exactly one** verdict for the stack:

- **`landable`** — the stack is current with trunk (fast-path no-op, **or** a
  clean rebase that was pushed) **and** the CI gate is green.
- **not-landable / hold** — carrying a typed reason:
  - **`rebase-conflicted`** — the rebase left conflicted change(s); reported with
    change-ids + file paths; not pushed (§3.2). *(not-landable)*
  - **`ci-failing`** — an evaluated check failed/errored (§5.2). *(not-landable)*
  - **`ci-pending`** — checks still pending after the bounded loop (§5.3).
    *(hold — re-runnable, not a hard block)*
  - **`ci-missing`** — the PR has zero checks (§5.2); never green. *(not-landable
    by default; caller decides policy)*
  - **`trunk-moved`** — surfaced when trunk had moved (§2); on a clean rebase +
    push this resolves toward the gate verdict, but a caller that only wants the
    currency answer sees that trunk had moved and the stack was brought current.

The verdict is the skill's **primary output** for a caller — a human, or a land
flow — to consume. Report it alongside what happened: fast-path vs rebased,
pushed vs not, and the gate detail (which checks, which state).

Example shape:

```
stack:   feat/api → feat/ui  (top: feat/ui)
trunk:   main  (moved: yes — rebased onto a1b2c3, pushed feat/api, feat/ui)
ci gate: required checks — 2 success, 0 pending  ⇒ green
verdict: landable
```

```
stack:   feat/api → feat/ui  (top: feat/ui)
trunk:   main  (moved: yes — rebase produced conflicts)
conflicts:
  xkqp  feat/ui: update export  — src/export.ts, src/index.ts
verdict: not-landable  (rebase-conflicted)  — not pushed
```

## Failure modes (each reported, none improvised)

- **`gh` absent/unauthenticated** → up-front blocker, nothing fetched/rebased/
  pushed (§1).
- **Trunk bookmark unresolvable / tip ambiguous** → reported, stop before
  fetching (§1).
- **Rebase produces conflicts** → `rebase-conflicted` verdict with change-ids +
  paths; stack left conflicted-but-recoverable; **not pushed**; never
  auto-resolved, never interactive `jj resolve` (§3.2).
- **Push rejected** (non-fast-forward / diverged) → reported with the jj message;
  **no force-push**; the gate is not run against a stale head (§4).
- **Zero CI checks** → `ci-missing`, surfaced explicitly, never green (§5.2).
- **Checks pending past the budget** → `ci-pending` hold, re-runnable, never an
  indefinite wait (§5.3).
- **A jj command itself hangs** → do not retry blindly and NEVER delete `.jj`;
  `jj op log` / `jj op restore` is the orchestrator-only recovery surface.

## Composition (answers "current + green?"; does not land)

`/jj-keep-current` is the **currency precondition** of the reconcile tail,
upstack of [`jj-land`](../jj-land/SKILL.md):

- It **answers** "is this stack current and green?" and emits a verdict; it does
  **not** perform the merge/land — that is [`jj-land`](../jj-land/SKILL.md) (D4).
  When `/jj-land` exists, it consults this verdict and lands **only** on
  `landable`, declining on any not-landable or hold reason.
- It has **no dependency** on any in-flight change being canonical. The reference
  to `/jj-land` (D4) is **one-directional** (D4 points at this skill's verdict);
  this skill changes no requirement of `jj-land` and does not require `/jj-land`
  to exist. Invoked standalone with no land skill present, it completes and
  returns its verdict without erroring on D4's absence.
- It reuses — and does not modify — the
  [`jj-delegate`](../jj-delegate/SKILL.md) **"Integration never halts"**
  invariant for its rebase (§3); the reference is one-directional.

## Where this is called

`/jj-keep-current` is the pre-land currency check of the
[`jj-delegate`](../jj-delegate/SKILL.md) reconcile tail: once a fan-out's changes
are stitched into a stack and their PRs are open (via `/jj-pr` /
`/jj-stacked-pr`), `/jj-keep-current [<top>]` brings the stack current with trunk
and returns whether it is landable. A land flow ([`jj-land`](../jj-land/SKILL.md),
D4) consults that verdict before merging. It composes over jj for the
fetch/rebase/push and over `gh` for the CI gate; it never opens PRs, never lands,
and never forces a push or rebase.
