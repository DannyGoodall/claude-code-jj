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
| **Orchestrator** | primary/default workspace | workspace add/forget, **all** `jj bookmark` + `jj git push` + ref ops, integration, its own per-session agent-plan manifest (§3), issue tracker |
| **Worker** | one jj workspace each | edits + shaping its own commits (`jj new`/`jj describe -m`). Never bookmarks, never pushes, never raw mutating git. |

## 1. Resolve parameters (infer first, ask only on ambiguity)

- **workload** — from the arguments. Two forms:
  - *Skill form*: a leading `/name` or `name:subname` token (e.g.
    `/opsx:apply my-change`) — the worker invokes it via its Skill tool.
  - *Spec form*: anything else is a plain slice spec (what to build,
    acceptance criteria).
  If no workload can be determined from arguments or conversation, ask.
- **bookmark** — explicit argument if given; else derive `feat/<short-slug>`
  from the workload, matching the repo's branch naming. Under a session id this
  base name is prefixed with the per-session prefix at provision (see §3);
  surface the final name in the confirmation step; do not ask separately.
- **workspace** — `../wt-<short-slug>`, derived from the bookmark; likewise
  carries the per-session prefix (`../wt-<session-prefix>-<slug>`) when a
  session id is present (see §3), and stays unprefixed otherwise.
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

**Apply the per-session name prefix.** When this orchestrator is running under
a resolvable session id (the per-session manifest discriminator — see §1 /
Per-session manifest namespacing), derive a short, stable **session prefix**
from that same session id (reproduced identically on resume, so prefixed names
re-attach in place) and incorporate it into BOTH the workspace directory name
and the bookmark name so two concurrent orchestrators never contend for the
same `../wt-<slug>` dir or the same `<slug>` bookmark:

- workspace dir: `../wt-<session-prefix>-<slug>`
- bookmark: `<session-prefix>-<slug>`

In the **back-compat single-orchestrator path** — no session id is resolvable —
omit the prefix entirely: the workspace dir stays `../wt-<slug>` and the
bookmark stays the unprefixed `<slug>`/`feat/<short-slug>` form, identical to
today. Namespacing engages only when a session id is present; a lone
orchestrator is unchanged. Use the resolved names (prefixed or not) everywhere
below — in the `jj workspace add` target, the bookmark create, all dispatch
briefs, the manifest slice, and teardown — so a session's artifacts stay
consistent and grouped:

```bash
# <ws-dir>   = ../wt-<session-prefix>-<slug>   (prefixed under a session id)
#            = ../wt-<slug>                     (back-compat, no session id)
# <bookmark> = <session-prefix>-<slug>          (prefixed under a session id)
#            = <slug>/feat/<short-slug>          (back-compat, no session id)
jj workspace add -r <base-rev> <ws-dir>         # -r is required; default would
                                                # base on @'s PARENT and miss inputs
jj bookmark create <bookmark> -r @-             # create the worker's bookmark
                                                # (orchestrator owns all bookmarks)
```

**Seed gitignored workload files declaratively.** Per-workspace environment is
real: each workspace is its own directory, so `jj workspace add` carries only
tracked/snapshotted content — the gitignored files a workload needs to build or
test (env files like `.env.local`, local config, service credentials) are NOT
carried. Do NOT copy them ad hoc, file by file. Instead, after `jj workspace
add`, read the repository's **worktree-include declaration** — the same
convention Claude Code uses to copy selected gitignored files into a newly
commissioned git worktree — and copy exactly the paths it declares into the new
workspace. Resolve the declaration deterministically, using the **first source
present** (no merging across sources):

1. a repository-root worktree-include file (`.worktreeinclude`, gitignore-style
   newline-separated path globs), else
2. the worktree copy-list key in `.claude/settings.json` (a `worktree`-namespaced
   copy-list, e.g. `worktree.copyFiles`).

Treat each declared entry as a **gitignore-style path glob resolved relative to
the repo root**, and copy every matched file into the new workspace **preserving
its path relative to the repo root** (so `config/local.env` lands at
`<ws-dir>/config/local.env`). Apply these **safety bounds**:

- only copy paths that resolve **inside the repo root** — never escape it;
- never copy version-control internals (`.jj/`, `.git/`);
- **report** any declared path that matches nothing (do not silently skip it),
  so a missing required input surfaces here at provisioning rather than as a
  confusing downstream runtime failure.

**Fallback (no declaration):** when the repo has neither a `.worktreeinclude`
file nor a `.claude/settings.json` worktree copy-list, fall back to copying the
specific gitignored files the workload needs explicitly, exactly as before
(`cp .env.local <ws-dir>/` etc.). The absence of a declaration MUST NOT block
provisioning and MUST NOT regress existing flows.

Then install dependencies as the workload requires. If the workload runs the
app, assign it a distinct port and put that in the dispatch brief.

**Resolve the manifest path (per session).** Before touching any manifest,
resolve a stable **session-id token** for this orchestrator session and route
every manifest read/write through the per-session path it implies:

- **Session-id token** — slugify the orchestrator's own session/agent id to a
  filesystem- and ref-safe token: lowercase, `[a-z0-9-]` only (collapse any
  other run to a single `-`), trimmed of leading/trailing `-`, bounded to a
  short length (≈24 chars; if longer, truncate and keep enough to stay unique
  for this session). The token MUST be **deterministic** — the same session id
  always slugifies to the same token, so a resumed session resolves the same
  path and re-attaches to its existing manifest.
- **Per-session manifest path** — `.jj-agent-plan.<session-id>.json` at the
  repo root (gitignored). This session reads and writes ONLY this file; it
  never reads or writes another session's `.jj-agent-plan.*.json`.
- **Back-compat fallback** — when no session id is resolvable (the lone
  single-orchestrator case), fall back to the unnamespaced default path
  `.jj-agent-plan.json`, exactly as before. An existing repo carrying a plain
  `.jj-agent-plan.json` keeps working with no migration. Throughout this skill,
  "the manifest" means this resolved path (per-session when a session id
  exists, default otherwise).

Write the manifest at the resolved path (per §3's session-id resolution;
gitignored) with the slice(s): bookmark, workspace, base-rev, status, workload.
Also record the **liveness marker** so other tooling can judge staleness:
`session` (the owning session-id token, or `null` in the back-compat default
path) and `heartbeat` (an ISO-8601 timestamp). **Refresh the `heartbeat` on
every manifest write** as you operate (provision, dispatch, reconcile,
teardown), so a live session's manifest always carries a fresh timestamp and a
dead session's goes stale. The manifest's top-level shape is therefore:

```jsonc
{
  "session": "<session-id-token-or-null>",  // owning session (liveness marker)
  "heartbeat": "<ISO-8601 timestamp>",       // refreshed on every write
  "slices": [ /* bookmark, workspace, base-rev, status, workload, blocker */ ]
}
```

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
   onto trunk. **Before a risky integration step** — a fan-out pass that rebases
   several workers' changes onto trunk, or a large history rewrite — record a
   labelled save point first with
   [`/jj-checkpoint <label>`](../jj-checkpoint/SKILL.md) (it captures the current
   op id in the manifest, read-only to history). If the step then goes wrong,
   [`/jj-rewind [label]`](../jj-rewind/SKILL.md) rolls the whole repo back to that
   point via `jj op restore` after a confirmation summary — the labelled form of
   the `jj op log`/`jj op restore` recovery surface, instead of scanning the op
   log by hand under pressure. **A jj rebase always succeeds** — if there are
   conflicts they are recorded as first-class objects in the resulting commits,
   NOT a blocked pipeline. Resolve any conflicts deliberately (edit markers;
   never the interactive `jj resolve`).
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
   Update then delete the slice entry in the resolved manifest (the
   per-session `.jj-agent-plan.<session-id>.json`, or the default path in the
   back-compat case), refreshing the `heartbeat` on that write.
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

## Startup sweep — reclaim stale orchestrator state

Concurrent orchestrators are allowed (each owns its own session-namespaced
manifest), so a dead or abandoned orchestrator can leave its manifest behind.
On orchestrator startup, before provisioning, run a conservative sweep so
abandoned state neither accumulates nor pollutes the fleet view — while never
disturbing a peer that is merely idle:

1. **Scan siblings.** List every `.jj-agent-plan.*.json` manifest at the repo
   root (the session-namespaced files alongside the unnamespaced default). This
   is a read-only enumeration; you are looking only at sibling manifests, never
   at any worker's commits or working copy.
2. **Classify by liveness.** For each manifest read its liveness marker (the
   owning session id + heartbeat the owning orchestrator refreshes as it
   operates — see §1 / Per-session manifest namespacing for the marker the
   manifest carries). A manifest is **provably stale** only when BOTH hold:
   its heartbeat is older than the liveness TTL (or it carries an explicit
   "session ended" marker) AND no live owner is present. Your own current
   session's manifest is by definition live — never a sweep target.
3. **Reclaim only the stale.** Remove or archive (move aside, to aid
   post-mortem) each provably-stale manifest. Leave every other manifest
   exactly as found. **Never touch worker commits, bookmarks, or refs**, and
   **never remove a stale orchestrator's workspaces in the sweep** — leave the
   directories for inspection (resume-in-place still works); the sweep reclaims
   only the abandoned *manifest* state.
4. **Protect live-but-idle peers.** The conservative rule is decisive: if a
   manifest's owner still appears live — a fresh heartbeat within the TTL, even
   with no recent activity — the sweep leaves it untouched. A generous TTL plus
   the both-conditions test (past-TTL AND no fresh heartbeat) prevents
   reclaiming an in-flight peer mid-run. When in doubt, do not sweep.

This sweep is orchestrator-only and the only place manifests are deleted;
`/jj-fleet` may *exclude* stale manifests from its read-only view but never
removes them.

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
  recovery surface, orchestrator-only. When you guarded the risky step with
  [`/jj-checkpoint <label>`](../jj-checkpoint/SKILL.md) first, the labelled form
  of that surface is [`/jj-rewind [label]`](../jj-rewind/SKILL.md) — roll the
  whole repo back to the save point rather than hand-scanning op ids.

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
