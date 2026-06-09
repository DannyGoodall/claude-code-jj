---
name: jj-pr
description: |
  Push a jj bookmark to its GitHub remote and create-or-update its pull request
  in one orchestrator step — the "submit" that jj lacks (jj git push moves a
  bookmark but never opens a PR). Given a bookmark, it pushes with
  `jj git push -b <bookmark>`, handles the one-time `jj bookmark track` need on a
  freshly colocated repo, then creates (none exists) or updates (one exists) the
  GitHub PR via `gh`, generating a what/why/benefit body from the change's
  commits and any OpenSpec proposal.md. Triggers: /jj-pr, "push and open the PR",
  "submit this bookmark", "open/update the PR for <bookmark>". The reconcile-tail
  push step for /jj-delegate and /jj-openspec apply. Orchestrator-only (owns refs
  and push); never invoked inside a worker. Requires a colocated jj↔git repo with
  an `origin` remote and `gh` authenticated.
metadata:
  version: "0.1.0"
  author: outfitter-style
---

# jj-pr — push a bookmark, open or update its GitHub PR

You are the **orchestrator**. jj has no native "submit": `jj git push` moves a
bookmark to the remote but never opens a pull request. This skill is the missing
push-and-PR step — it pushes a bookmark, handles one-time remote tracking, then
creates or updates that bookmark's GitHub PR via `gh`, with a generated body.

Substrate knowledge (jj command surface, non-interactive rules, output formats)
comes from the installed `jj-vcs` skill — defer to it for jj command detail;
this skill owns only the push-and-PR choreography.

## Preconditions (verify, don't assume)

- **Orchestrator role only.** This skill owns ref and push operations, which the
  worker contract forbids. NEVER invoke `/jj-pr` inside a worker. It runs in the
  primary/default workspace, the role that owns all bookmarks and pushes.
- **Colocated jj↔git repo with an `origin` remote.** PRs need a GitHub remote;
  `jj git push` targets `origin` by default. If there is no `origin` remote, stop
  and report — this skill does not create remotes.
- **`gh` available and authenticated.** The PR step is `gh`; a missing or
  unauthenticated `gh` is a reported blocker, not an improvised workaround (see
  §1). The skill never spawns an editor and never force-pushes.
- **Bookmark = GitHub head branch.** The colocated default; assumed equal and not
  auto-reconciled. The caller owns the bookmark's existence and name — `/jj-pr`
  only pushes, tracks, and PRs it.

## Arguments

```
/jj-pr <bookmark> [--issue <N>] [--base <branch>] [--draft] [--change <name>]
```

- **`<bookmark>`** (required) — the bookmark to push and open/update a PR for.
- **`--issue <N>`** (optional) — issue to close; emits `Fixes #N` in the body.
- **`--base <branch>`** (optional) — PR base branch; defaults to the repo's
  default/trunk branch. (No stacked-PR base management — see Non-Goals in design.)
- **`--draft`** (optional) — open the PR as a draft; default non-draft.
- **`--change <name>`** (optional) — the OpenSpec change name whose `proposal.md`
  seeds the body. If omitted, infer from the bookmark slug and look for
  `openspec/changes/<slug>/proposal.md`; fall back to commits if absent.

## 1. Dependency preflight (fail fast, never hang)

Before touching the remote, confirm the PR step can run:

```bash
command -v gh >/dev/null 2>&1 || echo "BLOCKER: gh not installed"
gh auth status 2>&1            # non-zero / "not logged into" ⇒ blocker
```

If `gh` is absent or unauthenticated, **report a clear blocker for the PR step
and stop before pushing** — do not half-do the work and do not hang on an
interactive auth prompt. (`gh auth status` is non-interactive and returns
promptly.) Distinguish this up-front blocker, where nothing was done, from a
mid-run failure where the push already succeeded (see §3 / §4).

## 2. Track (conditional) and push

### 2a. One-time remote tracking

On a freshly colocated repo a bookmark may not yet track `origin`. Detect the
tracking state first, then track **only if untracked** — running
`jj bookmark track` on an already-tracked bookmark is at best noise, at worst an
error.

```bash
jj bookmark list --all-remotes --ignore-working-copy --no-pager <bookmark>
# Look for an `<bookmark>@origin` tracking entry. If the bookmark exists locally
# but has no @origin tracking line, it is UNTRACKED against origin.
```

If untracked against `origin`:

```bash
jj bookmark track <bookmark> --remote=origin --no-pager   # one-time; not re-run when tracked
```

(The older `jj bookmark track <bookmark>@origin` form still works but is
deprecated in recent jj — prefer `--remote=origin`.) If the bookmark already
tracks `origin`, skip this step; running it on an already-tracked bookmark just
warns "Remote bookmark already tracked" and changes nothing.

### 2b. Push

```bash
jj git push -b <bookmark> --no-pager
```

Capture the outcome as **separable from the PR step**:

- **Success** — bookmark is on `origin`; proceed to §3.
- **Push rejected** (non-fast-forward / diverged remote bookmark) — report the
  jj message as a push failure and stop. **Do NOT force-push** — force is an
  orchestrator decision outside this skill's scope. Nothing about the PR is
  attempted.

## 3. Create or update the PR (idempotent, keyed on head branch)

Detect an existing open PR for the bookmark's head branch, then branch:

```bash
gh pr list --head <bookmark> --state open --json number,url --jq '.[0].url'
```

- **Zero results → create.** Build the body (§4) into a temp file, then:

  ```bash
  gh pr create \
    --head <bookmark> \
    --base <base-or-default> \
    --title "<generated title>" \
    --body-file <body-file> \
    [--draft]
  ```

- **One result → update** (idempotent re-run after follow-up commits). Update the
  existing PR's body/title in place; do NOT open a second PR for the same head:

  ```bash
  gh pr edit <bookmark> \
    --title "<generated title>" \
    --body-file <body-file>
  ```

Re-running `/jj-pr <bookmark>` after a worker amends and the orchestrator
re-pushes therefore **updates the same PR** rather than duplicating it — the
canonical reconcile-tail behaviour.

If the **push succeeded but the `gh` PR step fails** (API error), report
**"pushed, PR not created"** distinctly — never collapse it into overall
success, and never silently swallow the failure.

## 4. Generate the PR body

The body is `what` / `why` / `benefit` plus an optional `Fixes <issue>` line,
with a deterministic source precedence.

### 4a. Source from the OpenSpec proposal when present

Locate `openspec/changes/<change>/proposal.md` (`<change>` from `--change` or the
bookmark slug). When it exists, map its sections:

- `## Why` → **why**
- `## What Changes` → **what**
- `## Impact` (and any benefit-shaped content) → **benefit**

Use the proposal's `# <title>` or the change name for the PR `--title`. This is
the richer, already-reviewed source and takes precedence over commits.

### 4b. Fall back to commit messages

When no proposal is present — or its headers are missing/odd — degrade
gracefully to the bookmark's commit descriptions rather than failing:

```bash
jj log -r <bookmark> --no-pager --ignore-working-copy \
  -T 'description ++ "\n"' --no-graph
```

Use the commit subjects/bodies for the what/why; omit sections you cannot fill
rather than emitting empty headers. A single-commit change yields a one-line
body; a multi-commit change concatenates descriptions.

### 4c. `Fixes <issue>` line (only when known)

Emit `Fixes #<N>` **only** from:

1. an explicit `--issue <N>` argument, or
2. a `Fixes #<N>` / issue reference already present in a commit message.

When no issue is known, **omit the line** — never infer an issue from the branch
name or free text (a wrong `Fixes` would auto-close the wrong issue).

## 5. Report (report-shaped result)

Return a compact result the reconcile tail can surface:

- **bookmark** pushed and its **track outcome** (already-tracked / tracked-now).
- **push outcome** (pushed / push-rejected with the jj message).
- **PR action** (created / updated / not-created-because-…).
- **PR URL** (from `gh pr create` / `gh pr view <bookmark> --json url`).

Example shape:

```
bookmark: feat/add-export  (tracked now)
push:     ok
pr:       updated  https://github.com/org/repo/pull/42
```

## Failure modes (each reported, none improvised)

- **`gh` absent/unauthenticated** → up-front blocker, nothing pushed (§1).
- **Push rejected** → reported with the jj message; no force-push (§2b).
- **Push ok, PR step errors** → "pushed, PR not created", not overall success (§3).
- **Proposal headers missing/odd** → degrade to commit-message body (§4b).
- **No issue known** → omit `Fixes`, do not guess (§4c).
- **A jj command itself hangs** → do not retry blindly and NEVER delete `.jj`;
  `jj op log` / `jj op restore` is the orchestrator-only recovery surface.

## Where this is called

`/jj-pr` is the canonical push-and-PR step of the reconcile tail:

- [`jj-delegate`](../jj-delegate/SKILL.md) §5 calls `/jj-pr <bookmark>` after it
  integrates a worker's commits onto the change branch.
- [`jj-openspec`](../../../jj-concurrent-openspec/skills/jj-openspec/SKILL.md) §5
  apply shape calls `/jj-pr <bookmark>` as its verify → push/PR tail's push step.
