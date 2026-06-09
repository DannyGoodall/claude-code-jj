---
name: jj-linear
description: |
  Linear binding over the jj-concurrent orchestrator. At the orchestrator's
  reconcile point, map each background worker's structured JSON report to its
  Linear sub-issue: transition in-progress → done on a clean finish, post a
  blocker/conflict comment otherwise — threading umbrella + sub-issue IDs from
  dispatch keyed by the worker's workspace path. Triggers: /jj-linear, "sync
  worker reports to Linear", "update Linear sub-issues from the jj fan-out",
  "reconcile workers into Linear". Requires: the jj-concurrent plugin
  (jj-delegate + jj-workspace-worker) and a configured Linear MCP server
  (mcp__linear-server__*). Enable only in Linear-tracked repos.
metadata:
  version: "0.1.0"
  author: outfitter-style
---

# jj-linear — worker reports → Linear sub-issues

A thin binding. It layers **only** over `jj-delegate`'s existing reconcile point
and the `jj-workspace-worker`'s existing JSON report contract. It owns **no**
jj/workspace choreography (that is `jj-delegate`'s) and **no** report format
(that is `jj-workspace-worker`'s). If either changes, this binding should not
need to. Its single job: turn the report the orchestrator already has into
Linear sub-issue updates.

It requires the `jj-concurrent` plugin and a configured Linear MCP server
(`mcp__linear-server__*`). Where this plugin is **not** enabled, the orchestrator
behaves exactly as the bare `jj-concurrent` mechanism does — no triggers, no
Linear calls.

## Relationship to `linear-github-sync`

This binding assumes the existing **`linear-github-sync` convention**: each
fan-out has an **umbrella issue** and **one sub-issue per delegated slice/worker**,
authored upstream (e.g. by a `to-issues` / Linear-sync step) *before* dispatch.
This binding does **not** create the umbrella or the sub-issues — it only
**updates sub-issues that already exist** and are recorded in the manifest.

**Non-goals** (held out deliberately):

- No issue creation (umbrella or sub-issue).
- No GitHub PR ↔ Linear cross-linking — that stays the `linear-github-sync`
  concern. This binding stops at sub-issue status + comments.
- No Linear capability or identifier given to the worker.

## 1. Dispatch — record the ID map (worker stays Linear-agnostic)

ID custody belongs **entirely to the orchestrator**. At dispatch — when
`jj-delegate` provisions a workspace and a worker — this binding records, in the
orchestrator's **agent-plan manifest**, the Linear identifiers for that worker:

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
this binding only adds the `{ umbrellaId, subIssueId }` fields keyed by workspace
path.

**The worker stays Linear-agnostic.** The worker's dispatch **brief carries no
Linear identifier**, and the worker's **JSON report carries no Linear
identifier**. The orchestrator alone maps a report back to a sub-issue via the
manifest. (Rationale: putting Linear in the worker would leak Linear
credentials/IDs into every workspace, couple the worker contract to Linear, and
let a dying worker leave a half-applied update.)

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
