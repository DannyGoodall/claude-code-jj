---
name: jj-linear
description: |
  Linear binding over the jj-concurrent orchestrator, in two halves that meet
  only on the agent-plan manifest. At DISPATCH: auto-create one umbrella issue
  per fan-out + one sub-issue per worker, label them ready-for-agent, and thread
  { workspacePath → { umbrellaId, subIssueId } } into the manifest before any
  worker is dispatched. At RECONCILE: map each worker's structured JSON report
  to its sub-issue — transition in-progress → done on a clean finish, post a
  blocker/conflict comment otherwise — keyed by the worker's workspace path.
  Triggers: /jj-linear, "create Linear issues for the fan-out", "sync worker
  reports to Linear", "update Linear sub-issues from the jj fan-out", "reconcile
  workers into Linear". Requires: the jj-concurrent plugin (jj-delegate +
  jj-workspace-worker) and a configured Linear MCP server (mcp__linear-server__*).
  Enable only in Linear-tracked repos.
metadata:
  version: "0.2.0"
  author: outfitter-style
---

# jj-linear — Linear issues ↔ jj fan-out workers

A thin binding in **two halves** that meet only on the agent-plan manifest:

- **Dispatch half (§1):** at the start of a `/jj-openspec apply` or `jj-delegate`
  fan-out, **create** the umbrella + one sub-issue per worker, label them
  `ready-for-agent`, and thread their IDs into the manifest before dispatch.
- **Reconcile half (§2–§4):** at the orchestrator's reconcile point, turn each
  worker's existing JSON report into Linear sub-issue updates.

It layers **only** over `jj-delegate`'s existing dispatch + reconcile points and
the `jj-workspace-worker`'s existing JSON report contract. It owns **no**
jj/workspace choreography (that is `jj-delegate`'s) and **no** report format
(that is `jj-workspace-worker`'s). If either changes, this binding should not
need to.

It requires the `jj-concurrent` plugin and a configured Linear MCP server
(`mcp__linear-server__*`). Where this plugin is **not** enabled, the orchestrator
behaves exactly as the bare `jj-concurrent` mechanism does — no triggers, no
Linear calls.

## Relationship to `linear-github-sync`

This binding automates the existing **`linear-github-sync` convention**: each
fan-out has an **umbrella issue** and **one sub-issue per delegated slice/worker**,
each carrying a `ready-for-agent` agent-bound label. The binding has **two
halves that meet only on the manifest contract**
(`{ workspacePath → { umbrellaId, subIssueId } }`):

- **Dispatch half (§1):** *creates* the umbrella + one sub-issue per worker
  before workers are dispatched, labels them `ready-for-agent`, and threads
  their IDs into the manifest keyed by workspace path. (This is the upstream
  step the convention used to require a human/`to-issues` step for.)
- **Reconcile half (§2–§4):** *updates* those recorded sub-issues from each
  worker's JSON report.

**Non-goals** (held out deliberately):

- No GitHub PR ↔ Linear cross-linking — that stays the `linear-github-sync`
  concern. This binding stops at issue creation + labelling + ID-threading
  (dispatch half) and sub-issue status + comments (reconcile half).
- No report-driven updates from the dispatch half — creating + recording IDs
  is all it does; all status transitions and blocker/conflict comments are the
  reconcile half's job (§2–§4).
- No Linear capability or identifier given to the worker, on either half.

## 1. Dispatch — create issues and record the ID map

This is the **dispatch half**. It runs on the dispatch edge — the moment the
orchestrator settles on a fan-out plan and **before** any worker is provisioned
or dispatched — when it begins a `/jj-openspec apply` or any `jj-delegate`
fan-out. Like the reconcile half it owns **no** jj/workspace choreography (that
is `jj-delegate`'s) and **no** worker report format (that is
`jj-workspace-worker`'s). Its single job here: create the Linear issues the
reconcile half will update, and thread their IDs into the manifest.

ID custody belongs **entirely to the orchestrator**, on both halves. The
dispatch half is the **producer** of the manifest map the reconcile half
**consumes**:

```
{ workspacePath → { umbrellaId, subIssueId } }
```

- **Key:** the worker's **workspace path** — the worker's stable identity across
  its whole lifecycle. It is fixed at provision time, survives resume-in-place
  (a successor re-targets the *same* workspace), and is the `workspace` field the
  report echoes back. (Bookmarks can be renamed by the orchestrator; change-ids
  are only known after the worker runs — neither is a stable dispatch-time key.)
- **Value:** the `umbrellaId` for the fan-out and the `subIssueId` for *that*
  specific worker.

The manifest's physical location and exact schema are owned by `jj-delegate`;
this binding only **writes** the `{ umbrellaId, subIssueId }` fields keyed by
workspace path. This is the **exact shape the reconcile half reads** (§2.1) —
**no new field is added to the worker JSON report contract**.

### 1.1 Binding config read at dispatch

The dispatch half reads **one shared binding config block** (the same block the
reconcile half reads — both halves coordinate to a single config, e.g. the
reconcile half's per-team "Blocked" state lives alongside these):

- **`label`** — the agent-bound label applied to every created issue. Default
  `ready-for-agent`.
- **Linear team / project routing** — which team (and optionally project) the
  umbrella and sub-issues are created in.

### 1.2 Create the umbrella and sub-issues (before dispatch)

When the orchestrator begins an apply/fan-out, before provisioning workers:

1. **One umbrella issue per fan-out/apply**, representing the change/fan-out.
   Exactly one — including a single-worker `/jj-openspec apply <change>`, which
   gets one umbrella + one sub-issue (umbrella-always, for uniformity with the
   reconcile half's parent/child model).
2. **One sub-issue per worker** (one per task-group), each **parented to the
   umbrella**. Derive each sub-issue **title** from the **task-group name** when
   the fan-out plan names it, else from the **workspace basename**.

Creation happens on the **orchestrator side only**; no worker is involved.

**Ordering invariant:** the orchestrator SHALL NOT dispatch a worker before that
worker's sub-issue exists — *or* creation has been explicitly skipped per the
unavailability rule (§1.6). Concretely: create the sub-issue → record its IDs in
the manifest (§1.4) → then provision/dispatch that worker.

### 1.3 Label every created issue

Apply the configured **`label`** (default `ready-for-agent`) to the umbrella
**and** every sub-issue, marking them as agent-bound work.

**Missing label is non-fatal:** if the configured label does not exist in the
Linear workspace, **skip labelling** with a non-fatal note and **still create**
the issues — never fail creation over a missing label. Dispatch proceeds.

### 1.4 Thread the IDs into the manifest

Immediately after creating a worker's sub-issue, record in the agent-plan
manifest the **umbrella ID** for the fan-out and the **sub-issue ID** for that
worker, keyed by that worker's **provision-time workspace path**:

```
{ W → { umbrellaId, subIssueId: S } }
```

so a later report from workspace `W` resolves to sub-issue `S` and **no other**.

- **All sibling workers under one fan-out record the same `umbrellaId`**, and
  **each records its own distinct `subIssueId`**. The umbrella is created once
  per fan-out plan, not once per worker.

### 1.5 Idempotency — the manifest is the authoritative record

Idempotency is **manifest-driven**: the presence of a recorded ID means "already
created". **Before creating**, check the manifest:

- an existing **umbrella** for the fan-out → reuse the recorded `umbrellaId`,
  create no new umbrella;
- an existing **sub-issue** for the workspace path → reuse the recorded
  `subIssueId`, create no new sub-issue.

This makes the following safe with **no Linear-side dedup query** (which would be
slower, racy under concurrent fan-outs, and prone to title collisions):

- **Resume-in-place** — a successor worker provisioned at the *same* workspace
  path `W` reuses the sub-issue already recorded for `W`; creates no new
  sub-issue and no new umbrella.
- **Retried / re-run plan** — a fan-out whose umbrella is already recorded
  reuses that umbrella and the recorded per-workspace sub-issues; creates no
  duplicate issues.

### 1.6 Skip-and-note when Linear is unavailable or the binding is absent

- **Linear MCP unreachable at dispatch** → **skip issue creation entirely**,
  emit a non-fatal note in the dispatch report, and provision + dispatch workers
  **exactly as without the binding**. The fan-out is **never blocked** by Linear
  availability.
- **Binding not enabled** → no triggers, **no Linear calls**, no issues created;
  the orchestrator fans out exactly as the bare `jj-concurrent` mechanism would.

Where creation is skipped, **no `{ umbrellaId, subIssueId }` entry is written**.
The reconcile half then finds no sub-issue recorded for those workers and its
existing **"no sub-issue recorded → skip-and-note, no fallback"** rule (§4.2)
handles it cleanly — both halves share one degradation story.

### 1.7 The worker stays Linear-agnostic

Creating issues introduces **no Linear identifier into the worker's world**. The
worker's dispatch **brief carries no Linear identifier the worker must use or
return**, and the worker's **JSON report carries none**. The orchestrator alone
maps a report back to a sub-issue via the manifest. Any human-readable
cross-reference dropped into a brief (e.g. an issue URL for context) is
**advisory only** — never something the worker must echo back or act upon.
(Rationale: putting Linear in the worker would leak Linear credentials/IDs into
every workspace, couple the worker contract to Linear, and let a dying worker
leave a half-applied update.)

## 2. Reconcile — map the report to the sub-issue

At reconcile, when a worker's JSON report lands, run the **reconcile-tail
lookup** then apply the mapping. This is best-effort and **never** blocks the
worker's integration (rebase/merge/teardown).

### 2.1 Resolve the sub-issue (lookup by workspace path)

Take the report's `workspace` field and look up
`manifest[report.workspace].subIssueId`. That sub-issue — and **no other** — is
the target of every report-driven update below.

- If **no sub-issue is recorded** for that workspace path → **skip-and-note**:
  surface a non-fatal note in the reconcile report and **do not** fall back to
  the umbrella or any sibling sub-issue (§4.2).
- If the **Linear MCP is unavailable** → **skip-and-note** and proceed (§4.1).

### 2.2 Mapping table (single source of truth)

Derive the Linear update **solely** from the documented report fields
(`workspace`, `bookmark`, `changes`, `submitted`, `tests_run`, `blocked_on`,
`conflicts_seen`, `notes`) — no new report field is required.

| Report condition | Linear update to the worker's sub-issue |
|---|---|
| `blocked_on` null **AND** `conflicts_seen` null (clean finish) | transition in-progress → done (**idempotent**, §3.2) |
| `blocked_on` non-null | post a comment with the blocker text; **do NOT** mark done; leave needing-attention (§3.3) |
| `conflicts_seen` non-null | post a comment describing the conflict; **do NOT** mark done (§3.4) |
| no report at all (stall, resume-in-place) | **no update**; wait for a successor's report (§4.3) |
| Linear MCP unavailable / no sub-issue recorded | skip; note in reconcile report; integration proceeds (§4.1 / §4.2) |

`submitted` is **not** a finish signal — it is always `false` for workers (the
orchestrator pushes). A clean finish is `blocked_on` **and** `conflicts_seen`
both null.

### 3.2 Clean-finish transition (idempotent)

When `blocked_on` and `conflicts_seen` are **both null**, transition the
sub-issue from its in-progress state to its done state via the Linear MCP.

**Idempotent — state-check before transition:** read the sub-issue's current
state first; if it is already done, the transition is a **no-op** (not a
duplicate transition, not an error). Reconcile can be retried; re-applying the
same clean report must leave the sub-issue done with no side effects.

### 3.3 Blocker comment

When `blocked_on` is **non-null**, post a comment to the sub-issue carrying the
blocker text, and **do NOT** transition to done. Leave the sub-issue signalling
attention is needed — remaining in-progress, or moved to a dedicated "Blocked"
state if the team's workflow defines one (configurable per team).

### 3.4 Conflict comment

When `conflicts_seen` is **non-null**, post a comment to the sub-issue describing
the conflict, and **do NOT** transition to done. (A report can carry both
`blocked_on` and `conflicts_seen`; post the relevant comment(s) and withhold the
done transition in either case.)

### 3.5 Folding context into comments (never a state driver)

`tests_run`, `changes`, and `notes` **MAY** be folded into the done-transition
comment or the blocker/conflict comment as context (e.g. "tests: vitest run —
pass", the list of change-ids, integration notes). They are **context only** —
they **never by themselves drive a state change**. The state transition is driven
strictly by the §2.2 mapping (the `blocked_on` / `conflicts_seen` nullity).

## 4. Failure & edge handling

### 4.1 Linear MCP unavailable → skip-and-note

If the Linear MCP server is not reachable, **skip** the Linear update and surface
a non-fatal note in the orchestrator's reconcile report. The worker's
integration (rebase / merge / teardown) **proceeds unaffected** — a Linear
outage or latency is never fatal and never blocks workspace integration.

### 4.2 No recorded sub-issue → skip-and-note, never fall back

If the manifest has no sub-issue ID keyed to the reporting worker's workspace
path, **skip** the Linear update for that worker and note the missing mapping.
**Never** update the umbrella or any sibling sub-issue as a fallback — keying is
strict on workspace path.

### 4.3 Stalled / no-report worker → leave the sub-issue untouched

A worker that dies **without emitting a report** (recovered by the orchestrator's
resume-in-place) leaves its sub-issue **unchanged**. No report ⇒ no update. Only
a real report — from the original worker or a resume-in-place successor in the
**same** workspace — drives the next Linear update for that sub-issue. A stall
must **never** silently mark a sub-issue done.

### 4.4 Last-comment guard (no duplicate blocker comment)

Reconcile can be retried. Comments are append-only, so before posting a
blocker/conflict comment, **check the sub-issue's last comment**: if it is
byte-identical to the comment about to be posted, **skip** the post. This keeps a
reconcile retry from posting the same blocker comment twice.

## Summary

The orchestrator is the only role holding **both** the worker's report and the
Linear identifiers, so the binding lives at its reconcile point. Dispatch records
`{ workspacePath → { umbrellaId, subIssueId } }`; reconcile looks the sub-issue
up by `report.workspace` and applies the §2.2 mapping — idempotent done
transition on a clean finish, blocker/conflict comment otherwise — best-effort,
strictly keyed, never blocking integration, never marking a stall done.
