---
name: jj-burndown
description: |
  Board-as-work-queue driver over the jj-concurrent orchestrator: drain a
  Linear board's ready-for-agent backlog as a live, bounded, concurrent
  burndown. Resolves the board, selects ready issues deterministically,
  dispatches one jj-delegate worker per issue under a sliding-window cap
  (default 3), updates each issue as its worker reports (done, or blocker
  comment + hold), re-queries the board as it drains, and emits a live readout
  plus a final summary. Triggers: /jj-burndown <board>, "burn down the board",
  "drain the ready-for-agent backlog", "run the board as a work queue".
  Requires the jj-concurrent plugin and a configured Linear MCP server;
  orchestrator-only.
metadata:
  version: "0.1.0"
  author: outfitter-style
---

# jj-burndown — a Linear board as a drainable jj work queue

A board accumulates `ready-for-agent` issues — work triaged to "specified enough
for an autonomous agent." `jj-delegate` can already run many workers concurrently
on jj workspaces, and `jj-linear-sync` (the C2 binding) can already write a
worker's report back to its Linear issue. The missing piece is the **queue
driver**: drain the board's `ready-for-agent` issues as a *bounded stream* of
concurrent `jj-delegate` workers and update each issue as its worker lands. That
makes the board itself a work queue, with jj as the engine behind a live
burndown.

This skill is the **inverse direction** of `jj-linear-sync`: that binding maps a
worker-report → an issue; this driver maps a board → a stream of workers. The two
compose — at the landing step the burndown **reuses** `jj-linear-sync`'s mapping
when it is enabled — but the burndown does **not** depend on that binding being
canonical, and degrades to a minimal inline update when it is absent.

**Altitude.** This skill owns the **queue logic only** — board query, the cap,
the sliding window, re-query, the readout, termination. It owns **no**
jj/workspace choreography: workspace add, background dispatch, integration
(rebase/merge), and teardown all belong to `jj-delegate`. It owns **no**
report-to-Linear mapping: that is `jj-linear-sync`'s contract, reused here. If
either changes, this driver should not need to.

## Scope & contract

- **Orchestrator-only.** Runs in the repository's **primary (default) jj
  workspace** as a loop the orchestrating agent executes. It never runs inside a
  worker.
- **Issues no jj commands of its own.** It dispatches no `jj workspace`, no
  `jj bookmark`, no `jj git push`, no `jj rebase` — every such command is
  `jj-delegate`'s. The burndown only *invokes* `jj-delegate` and reads back the
  worker reports.
- **Requires** the `jj-concurrent` plugin (the `jj-delegate` mechanism +
  `jj-workspace-worker` report contract) and a configured Linear MCP server
  (`mcp__linear-server__*`).
- **Absent when the plugin is disabled.** Where `jj-concurrent-linear` is not
  enabled, the `/jj-burndown` trigger is **not present** and **no** board query
  or Linear update is attempted — the third skill in this separately-enableable
  plugin, alongside the `jj-linear-sync` binding and its `jj-linear-reconcile`
  umbrella layer.

## 0. Pre-flight

Before constructing any queue or dispatching any worker:

1. **Linear MCP reachability.** Probe the Linear MCP server (`mcp__linear-server__*`).
   If it is **unreachable**, **abort the run** with a clear message that Linear
   is unavailable, and dispatch **nothing**. No worker is partially dispatched
   and left unaccounted for — the abort happens before the first `jj-delegate`
   call, so there is no in-flight state to reconcile.
2. **`jj-concurrent` present.** Confirm `jj-delegate` is available (this plugin
   hard-depends on it). If not, abort with a message naming the missing
   dependency.

## 1. Board → work queue (selection)

### 1.1 Resolve the board argument

Resolve `<board>` to **exactly one** Linear board, accepting either a **board
name** or a **board id**. The argument may also name a team/project view that
carries the `ready-for-agent` issues per the repo's triage-labels convention.

- **No match** or **ambiguous match** (more than one board matches the name) →
  **report the resolution failure** and **dispatch nothing**. Resolution failure
  is fatal to the run, never a silent fall-through to "all boards."

### 1.2 Select the `ready-for-agent` candidate set

Query the resolved board for issues in the **`ready-for-agent`** state (the
triage-labels convention: a label on an otherwise-`Backlog`/`Todo` issue marking
it agent-bound work). **Exclude every other state** — backlog without the label,
in-progress, done, canceled. Only `ready-for-agent` issues enter the queue.

The selection SHALL be **deterministic and re-queryable**: the same board state
yields the same candidate set (so a re-query mid-run — §6.2 — is meaningful).

### 1.3 Order the candidate set (stable dispatch key)

Order the candidates by a **defined, stable key** so dispatch order is
reproducible and a re-query of an unchanged board reproduces the same ordered
set:

1. **Board position** (the issue's manual order on the board), then
2. **Priority** (Urgent → High → Medium → Low → No priority), then
3. **Issue identifier** (e.g. `PTS-123`) as the final tie-breaker.

This is the order in which slots are filled as the window advances.

## 2. The bounded sliding-window drain

### 2.1 The cap (default 3, configurable)

The drain runs under a **concurrency cap** — the maximum number of `jj-delegate`
workers in flight at once. The cap **defaults to 3** (moderate: exercises
concurrency without flooding workspaces or the Linear API) and is **configurable**.

**Override surface.** The cap is read once at the start of the run, in this
precedence (highest first):

1. A **positional second argument** — `/jj-burndown <board> <cap>` (e.g.
   `/jj-burndown PTS-Sprint 5`).
2. A **plugin/skill config key** if the project defines one (e.g. a
   `jj-burndown.cap` setting read at start).
3. The **default of 3** when neither is given.

The spec fixes only "moderate default, configurable, never exceeded"; the above
is this skill's concrete surface. The cap is **never exceeded** regardless of
queue depth.

### 2.2 The dispatch loop

Maintain a **sliding window** of in-flight workers:

1. **Fill** the window: pull issues from the head of the ordered queue and
   dispatch each (§3) until either the window holds `cap` workers or the queue is
   empty.
2. **Wait** for any in-flight worker to **land** (report) — do not block on a
   *specific* worker; reconcile whichever lands first (workers are background
   concurrent siblings, §3).
3. On a landing: **reconcile** it (§4), **free** its slot, then **pull and
   dispatch the next ready issue** if any remain (§6.2 re-query feeds the queue).
4. **Emit** a window-advance summary (§5).
5. Repeat from step 2 until the **termination condition** (§6.3) holds.

This is explicitly **NOT** a single fan-out of the whole board. In-flight count
is `≤ cap` at every moment; the remaining issues wait in the queue until a slot
frees, and a freed slot is **reused** (not left idle) while the queue is
non-empty.

### 2.3 Per-run bookkeeping (keyed by workspace path)

Track, for the duration of the run:

- **`dispatched`** — the set of issue ids already dispatched this run, each paired
  with **its worker's workspace path** (`issueId ↔ workspacePath`).
- **`completed`** — the set of issue ids whose worker has landed and reconciled.
- **`inFlight`** — `dispatched − completed` (the occupied slots).

The **workspace path is the stable per-worker identity** (as in `jj-delegate` and
`jj-linear-sync`): it is fixed at provision time and survives resume-in-place.
Keying on it means that when `jj-linear-sync` is also present, both agree on which
issue a landing belongs to **without a second identity scheme** — no new identity
is introduced by this skill. Dispatch is **idempotent per issue**: an issue id
already in `dispatched` is never dispatched again (§6.2).

## 3. Per-issue dispatch via jj-delegate

For each pulled issue:

- Dispatch **exactly one** `jj-delegate` worker in **its own jj workspace**
  (concurrent siblings, per `jj-delegate`'s orchestrator/worker split and
  concurrent-sibling provisioning). **One issue → one worker → one workspace**;
  the skill **never bundles** multiple issues into a single worker.
- The **issue body / specification is the worker's workload** — the brief
  `jj-delegate` hands the worker. (A human-readable issue URL may be included as
  advisory context, but per `jj-linear-sync` §1.7 the worker stays
  Linear-agnostic: it is handed no Linear identifier it must use or echo back.)
- Workers are dispatched **in the background by default**, consistent with
  `jj-delegate`'s background-sibling dispatch. The driver then returns to
  reconcile landings rather than blocking on any single worker.

All workspace provisioning, the background dispatch itself, integration, and
teardown are performed **by `jj-delegate`** — the burndown issues **no**
`jj workspace`, bookmark, push, or rebase command itself (§Scope & contract).

## 4. Per-issue landing update

When a worker reports (its structured `jj-workspace-worker` JSON report — keyed
back to its issue by the worker's `workspace` path, §2.3):

### 4.1 Detect the C2 binding

Detect whether the **`jj-linear-sync` (C2) status-sync binding** is enabled (its
reconcile half is active in this session/plugin set).

### 4.2 Reuse the binding when present

When `jj-linear-sync` **is enabled**, **defer the per-issue transition to its
report-to-Linear mapping** — it is the single source of truth. The burndown does
**not** redefine the mapping and does **not** apply a competing inline update;
only one mapping ever runs per landing. (Because the issues drained here are the
same issues `jj-linear-sync` keys by workspace path, the binding resolves the
right issue from the report's `workspace` field unaided.)

### 4.3 Degraded inline update when absent

When `jj-linear-sync` is **absent**, apply a **minimal inline status update**
following the **same clean/blocked rule** as the canonical mapping, and **note in
the readout that the run is in degraded mode**:

| Report condition | Inline update to the worker's issue |
|---|---|
| `blocked_on` null **AND** `conflicts_seen` null (clean finish) | transition the issue **in-progress → done** |
| `blocked_on` non-null | post a comment carrying the **blocker** text; **do NOT** mark done; leave in a needs-attention state |
| `conflicts_seen` non-null | post a comment describing the **conflict**; **do NOT** mark done |

`submitted` is **not** a finish signal (it is always `false` for workers — the
orchestrator pushes). A clean finish is `blocked_on` **and** `conflicts_seen`
**both** null. `tests_run` / `changes` / `notes` MAY be folded into the comment as
context but never by themselves drive a state change. If the inline update and the
canonical mapping ever diverged, the binding (when enabled) **wins** — §4.2 defers
to it entirely.

### 4.4 Stalled worker → leave untouched

A worker that **dies without emitting a report** (recovered by `jj-delegate`'s
resume-in-place) leaves its issue **unchanged** — no report ⇒ no update. The slot
stays **occupied** (counted as in-flight) until a successor in the **same**
workspace reports, so the cap is respected and a stall **never silently marks an
issue done**. Only that successor's real report drives the next update.

## 5. Live burndown readout

Emit a **running summary** at a defined cadence — **at minimum each time the
sliding window advances** (a worker lands and/or a new worker is dispatched).
Each summary shows:

- **queue-remaining** — `ready-for-agent` issues not yet dispatched (from the
  most recent re-query, §6.2),
- **in-flight** — workers currently occupying a slot,
- **done** — cumulative clean landings this run,
- **blocked** — cumulative blocked/conflicted landings this run.

When running **degraded** (no `jj-linear-sync`, §4.3) the readout flags it.

Keep the readout at the **queue-counts altitude**. For per-workspace detail
(issue ↔ workspace ↔ change-id), lean on the **`jj-fleet`** view rather than
inlining it here.

**Final summary.** When the run terminates (§6.3), emit a **final summary**
reflecting the end state: total **done**, total **blocked**, and an **empty
queue**.

## 6. Re-query and termination

### 6.1 Live queue, not a start-time snapshot

The queue is **re-queried as it drains** rather than frozen at start, so issues
moved to `ready-for-agent` **during** the run are picked up **within the same
run**. Re-query the board (§1.2 selection + §1.3 ordering) at each window advance
(or on a small cadence) — the extra board query per advance is cheap and keeps the
burndown useful while a board is actively triaged.

### 6.2 Idempotent dispatch on re-query

A re-query that surfaces an issue **already in `dispatched` or `completed`** this
run (§2.3) is a **no-op for that issue** — it is **never re-dispatched**. Only
issues not yet seen this run are appended to the queue (re-ordered into the stable
key, §1.3). This makes a re-query that returns an in-flight issue safe.

### 6.3 Termination (the drained fixpoint)

The run **terminates** when a **re-query returns no `ready-for-agent` issues**
**AND** **no workers are in flight**. At that fixpoint, emit the final summary
(§5). A long-lived drain against a continuously-triaged board is acceptable — the
run terminates only at the fixpoint, and an operator may stop it at any time.

## 7. Composition (referenced, not restated)

- **`jj-delegate`** (jj-concurrent) — owns the orchestrator/worker split,
  concurrent-sibling workspace provisioning, background dispatch, integration, and
  teardown. The burndown supplies *which issue* and *how many at once*; everything
  jj/workspace is `jj-delegate`'s. Its contracts are **not** restated here.
- **`jj-linear-sync`** (C2, this plugin) — owns the **report → Linear** mapping
  reused at §4.2. The burndown defers to it when present; it does **not** redefine
  the mapping.
- **C1 umbrella / sub-issues** (the `jj-linear` dispatch half) — **consumed, not
  produced.** When the umbrella/sub-issue convention is in play, the drained
  `ready-for-agent` issues are already the sub-issues under an umbrella and the
  burndown simply drives them. When it is **absent**, the burndown treats the
  board's `ready-for-agent` issues as **flat top-level work** (graceful
  fallback). The driver **never** creates umbrellas or sub-issues — that
  structure is C1's.
- **`jj-fleet`** (jj-concurrent) — the per-workspace status view the readout
  defers to for issue ↔ workspace ↔ change-id detail (§5).

## Summary

`/jj-burndown <board>` makes a Linear board a drainable work queue. Pre-flight
aborts if Linear is unreachable. The board's `ready-for-agent` issues form a
deterministic, re-queryable, ordered candidate set; a **sliding window** under a
**configurable cap (default 3, never exceeded)** dispatches **one `jj-delegate`
worker per issue** (issue body = workload) and, on each landing, pulls-and-
dispatches the next. Each landing updates its issue — **reusing `jj-linear-sync`**
when present, a **minimal inline update** (with a degraded-mode note) when absent
— clean → done, blocked/conflict → comment + hold, stall → untouched. The board
is **re-queried** as it drains (idempotent per issue), a **live readout**
(queue-remaining / in-flight / done / blocked) prints on each advance, and the run
**terminates** at the drained fixpoint (no ready issues, no workers in flight)
with a final summary. The driver owns the queue; `jj-delegate` owns the
choreography; `jj-linear-sync` owns the mapping.
