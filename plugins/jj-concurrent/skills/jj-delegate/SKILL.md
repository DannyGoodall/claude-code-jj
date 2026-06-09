---
name: jj-delegate
description: |
  Orchestrate one (or several concurrent) jj-workspace-worker subagents, each
  in its own Jujutsu (jj) workspace, to carry out a workload and integrate the
  result. The workload is either a skill invocation the worker runs via its
  Skill tool (e.g. "/opsx:apply my-change") or a plain slice spec. Triggers:
  /jj-delegate, "delegate this to a jj worker", "run <skill> in a jj workspace",
  "fan out agents on jj workspaces". Requires a jj repo (a .jj directory),
  ideally colocated with git for PRs. Workflow-agnostic: this skill owns the
  jj/workspace choreography only — what the worker does is the workload's business.
metadata:
  version: "0.1.0"
  author: outfitter-style
---

# jj-delegate — workspaces, workers, integrate

You are the **orchestrator**, working in the **primary (default) jj workspace**.
You own workspace lifecycle, all bookmark/ref operations, `jj git push`, and
integration. Workers own exactly their own workspace's commits. This skill is
the single- and multi-worker driver for that model.

Substrate knowledge (jj command surface, non-interactive rules, output
formats) comes from the installed `jj-vcs` skill — defer to it for command
detail; this skill owns only the orchestration.

## Roles (enforced by the worker contract + guard hook)

| Role | Where | Owns |
|------|-------|------|
| **Orchestrator** | primary/default workspace | workspace add/forget, **all** `jj bookmark` + `jj git push` + ref ops, integration, the agent-plan manifest, issue tracker |
| **Worker** | one jj workspace each | edits + shaping its own commits (`jj new`/`jj describe -m`). Never bookmarks, never pushes, never raw mutating git. |

## 1. Resolve parameters (infer first, ask only on ambiguity)

- **workload** — from the arguments. Two forms:
  - *Skill form*: a leading `/name` or `name:subname` token (e.g.
    `/opsx:apply my-change`) — the worker invokes it via its Skill tool.
  - *Spec form*: anything else is a plain slice spec (what to build,
    acceptance criteria).
  If no workload can be determined from arguments or conversation, ask.
- **bookmark** — explicit argument if given; else derive `feat/<short-slug>`
  from the workload, matching the repo's branch naming. Surface it in the
  confirmation step; do not ask separately.
- **workspace** — `../wt-<short-slug>`, derived from the bookmark.
- **base revision** — the revision the worker should build on (see §3).

## 2. Confirm (Phase 0 gate)

Bring the base up to date (`jj git fetch` if there is a remote), then present
one compact plan — workload, bookmark, workspace, base revision — and wait for
confirmation, exactly as single-agent planning requires.

## 3. Provision (orchestrator only)

**Choose a clean base revision.** jj auto-snapshots EVERYTHING not gitignored
into the current change `@`, so `@` may carry incidental working-tree churn
(local settings, other in-flight work). Do NOT blindly base a worker on a
polluted `@`. Either base on trunk, or on a curated change that contains
exactly the inputs the workload needs (e.g. a freshly-authored OpenSpec change
folder — see the jj-openspec binding). There is **no seed-commit ceremony**
(jj has no untracked-file limbo), but you MUST point the workspace at the
revision that contains the inputs:

```bash
jj workspace add -r <base-rev> ../wt-<slug>     # -r is required; default would
                                                # base on @'s PARENT and miss inputs
jj bookmark create <bookmark> -r @-             # create the worker's bookmark
                                                # (orchestrator owns all bookmarks)
```

Per-workspace environment is real: each workspace is its own directory, so
install dependencies / copy gitignored env files the workload needs
(`cp .env.local ../wt-<slug>/` etc.). If the workload runs the app, assign it
a distinct port and put that in the dispatch brief.

Write the manifest `.jj-agent-plan.json` at the repo root (gitignored) with
the slice(s): bookmark, workspace, base-rev, status, workload.

## 4. Dispatch worker(s)

Spawn `jj-workspace-worker` subagent(s) (NOT the harness `isolation: worktree`
option — the jj workspace IS the isolation). Each prompt MUST include:

- the workspace path (work there exclusively) and the bookmark name;
- the workload — for skill form: "Invoke the Skill tool with skill `<name>`
  and args `<args>`."; for spec form: the slice spec verbatim;
- situational facts only (base-rev, where env files live, assigned port,
  workload-specific test notes). The worker CONTRACT — workspace containment,
  never raw git, never bookmarks/push, non-interactive jj, snapshot discipline
  — lives in the agent definition; do NOT restate it.

**Dispatch in the background by default** (`run_in_background: true`): control
returns to the user immediately and you reconvene on the completion
notification. While a background worker runs, the user may dispatch MORE
workers — concurrent workspaces are the whole point. Provisioning always
serializes through you (the orchestrator); the workers run in parallel.

Foreground only when the user asks to wait or for a deliberate validation run
— warn that it blocks the session and that the worker's inline tool activity
is not the orchestrator doing the work.

## 5. Reconvene + integrate (per worker, as each reports)

jj makes this the easy part — **integration never halts**.

1. Read the worker's JSON report; its commits are already in the shared store
   and visible to you (`jj log --ignore-working-copy --no-pager`).
2. Verify the workload by its own standard (for a skill workload, prefer that
   workflow's verification step — e.g. `/opsx:verify` — over ad-hoc review).
3. Integrate. The worker shaped its commits under its bookmark; rebase/land it
   onto trunk. **A jj rebase always succeeds** — if there are conflicts they
   are recorded as first-class objects in the resulting commits, NOT a blocked
   pipeline. Resolve any conflicts deliberately (edit markers; never the
   interactive `jj resolve`).
   - **Amend after review (when fixes are scattered).** If a review pass leaves
     small fixes scattered across the working copy — each belonging to a
     different commit deeper in the integrated stack — run the amend-after-review
     step [`/jj-absorb`](../jj-absorb/SKILL.md) rather than amending each commit
     by hand. It previews the placement (`jj absorb --dry-run`), distributes each
     working-copy hunk into its downstack commit, reports where each landed, and
     leaves any ambiguous hunk in the working copy for deliberate manual
     placement. Skip it when there are no scattered fixes to absorb.
   - Then run the push-and-PR step:
     [`/jj-pr <bookmark>`](../jj-pr/SKILL.md) — it pushes the bookmark
     (`jj git push -b <bookmark>`, handling one-time `jj bookmark track`) and
     creates-or-updates the GitHub PR via `gh` with a generated body.

   **When the fan-out's siblings were stitched into a single linear stack**
   (`base → A → B → C`) rather than landed independently, the stacked submit step
   is [`/jj-stacked-pr <tip>`](../jj-stacked-pr/SKILL.md) instead — it derives the
   parent chain from the jj stack topology and opens/updates one PR per bookmark
   **based on its parent** (the root on trunk), composing `/jj-pr` per bookmark
   and adding a cross-reference stack-navigation comment. Use the single-change
   `/jj-pr <bookmark>` for a non-stacked change; use `/jj-stacked-pr <tip>` for a
   stitched stack.
4. **Tear down the workspace** to keep state minimal (the geirsson principle —
   abandon dead workspaces aggressively):
   ```bash
   jj workspace forget <workspace-name>
   rm -rf ../wt-<slug>            # the directory only — NEVER the repo .jj
   ```
   Update then delete the manifest entry.
5. Report to the user: bookmark, change-ids, PR/push outcome, test result,
   any conflicts surfaced.

## Concurrent siblings

Invoking jj-delegate again while a background worker runs is fine for
INDEPENDENT slices: provision the new workspace + bookmark off trunk, add it to
the manifest, dispatch. Each worker reconciles as it reports. Because jj
integration never halts and ops are lock-free, there is **no prune-before-
restack barrier** to wait on (unlike git worktrees) — but mind **staleness**:
do not move a revision that another live workspace builds on. If a workspace
goes stale, the fix is `jj workspace update-stale` in that workspace, not a
failure.

## Failure handling

- Worker reports `blocked_on` → leave its workspace intact for inspection,
  relay the blocker. Never resolve cross-workspace conflicts in its name.
- Worker died without a report (stall, hang, crash) → **resume-in-place**, and
  under jj it is nearly free:
  1. The worker's edits are already snapshotted (the snapshot hook + jj
     auto-snapshot), so its work sits in the workspace's working-copy commit —
     inspect with `jj log -R ../wt-<slug> --ignore-working-copy --no-pager` and
     `jj evolog`.
  2. Dispatch a FRESH worker into the SAME workspace with a resume brief: what
     is already committed/snapshotted and what remains. Nothing to salvage by
     hand — that is the jj payoff over git worktrees.
  3. Check the primary workspace for collateral and clean it up.
- **Repeated background stalls** (watchdog "no progress" kills at unrelated
  phases) → suspect the session's background-agent transport, not this skill;
  fall back to foreground for the resume and suggest a fresh session.
- **A jj command itself hangs** (a known jj rough edge in heavy use) → do not
  retry blindly and NEVER delete `.jj`; `jj op log`/`jj op restore` is the
  recovery surface, orchestrator-only.

## Situational awareness

`jj log` does not auto-snapshot sibling workspaces, so a plain log can show
stale state. For an at-a-glance view of every in-flight worker — snapshot each
live workspace first, then read jj state joined with the agent-plan manifest's
status/blocker — use [`/jj-fleet`](../jj-fleet/SKILL.md). Keep the operation log
short; abandon dead experiments.

## Variants

- **Foreground** ("wait for it") — blocks the session until the worker reports.
- **Single worker** — the common case; one workspace, one bookmark, reconcile,
  done.
- **Fan-out** — many independent workloads → repeat §3–§4 per slice in the
  background; reconcile each as it lands.
