## Context

The `jj-concurrent` plugin orchestrates stacks of jj changes through workspaces, integration, push, and PR creation (`/jj-pr`). The in-flight `/jj-land` (D4) adds a land step. But between "PR opened, CI green" and "PR landed", trunk frequently moves: another stack merges, a hotfix lands. A stack tested against old trunk can then land dirty or fail CI on the merge queue.

jj is uniquely suited to fix this cheaply: `jj rebase` never halts. Where a git rebase stops at the first conflicting hunk and forces an interactive resolution, jj rebases the whole stack in one shot, records each conflict as a first-class object inside the resulting change, and exits 0. The `jj-delegate` spec already codifies this as the **"Integration never halts"** invariant. This change reuses that invariant for the trunk-tracking case and adds a CI gate so a stack is never landed stale or red.

This is authored as a standalone capability. `/jj-land` (D4) is in-flight, not canonical; `/jj-keep-current` must be mergeable and testable on its own, exposing a verdict that a land flow *consults* but does not require to exist.

## Goals / Non-Goals

**Goals:**
- Emit a single, machine-readable verdict for a stack: **landable** (current + required CI green) or **not-landable** with a typed reason (`trunk-moved`, `rebase-conflicted`, `ci-failing`, `ci-pending`, `ci-missing`).
- Detect trunk movement by fetching the trunk bookmark and comparing the stack's base to the fetched trunk tip.
- Auto-rebase the stack onto the new trunk using jj's never-halt semantics; surface conflicts as first-class objects (change-ids + paths), never auto-resolve, never invoke interactive `jj resolve`.
- Push the rebased stack so the PR rebuilds against the new base, then re-run the CI gate with a bounded poll for pending checks.
- Stay strictly within the orchestrator role contract (fetch/rebase/push/PR-read are orchestrator-only).

**Non-Goals:**
- Performing the actual merge/land (that is `/jj-land`, D4). This skill only answers "is it safe and current to land?".
- Resolving rebase conflicts. A conflicted rebase is reported and blocks; resolution is a deliberate human/orchestrator follow-up.
- Triggering, configuring, or interpreting CI internals — it reads check status via `gh`, nothing more.
- Continuous/background watching of trunk. This is a point-in-time pre-land check, optionally re-checked in a bounded loop; standing watch is out of scope.

## Decisions

**Decision: One skill, two phases (rebase-current then gate), single verdict.**
The skill runs: (1) fetch + detect + (conditional) rebase + push; (2) CI gate with bounded re-check; then returns one verdict object. Rationale: callers (a human, or `/jj-land`) want one yes/no with a reason, not a sequence of sub-results to reassemble. Alternative considered — two separate skills (`/jj-rebase-current` + `/jj-ci-gate`) — rejected for v1 because the re-check loop intrinsically couples them (a push invalidates the prior CI verdict); they can be split later if a caller needs only one half.

**Decision: CI gate keys off *required* checks, with explicit fallbacks.**
Use `gh pr checks <ref> --required` when required checks are configured; otherwise fall back to all checks. Map states: any failing/errored ⇒ `ci-failing` (block); any pending/queued ⇒ `ci-pending` (hold, then poll); all success ⇒ green; zero checks ⇒ `ci-missing` (reported explicitly, **not** treated as green). Rationale: "no CI" silently passing is the dangerous default; surfacing it lets the caller decide. Alternative — treat missing as green — rejected as unsafe.

**Decision: Trunk-movement detection via fetch-then-compare, with a no-op fast path.**
`jj git fetch` the trunk bookmark, then compare the stack base revision to the fetched trunk tip (revset comparison). If equal, skip rebase and push entirely (fast path). Rationale: avoids needless pushes that re-trigger CI and churn the merge queue. Alternative — always rebase — rejected for CI churn and wasted runs.

**Decision: Never-halt rebase, conflicts as blocking first-class objects.**
`jj rebase -b <stack-base> -d <trunk-tip>` always exits 0. After it, inspect the rebased changes for conflict markers / conflict state; if any change is conflicted, the verdict is `rebase-conflicted` with the conflicted change-ids and file paths, and the skill stops before pushing (do not push a conflicted stack). Rationale: this is the `jj-delegate` "Integration never halts" invariant applied to trunk-tracking — the operation succeeds, the *stack* carries the conflict, and resolution is deliberate. Interactive `jj resolve` is forbidden by the worker/orchestrator contract and by command hygiene.

**Decision: Bounded re-check loop, not unbounded wait.**
After pushing, re-run the gate; if `ci-pending`, poll at a configurable interval up to a configurable max attempts, then return `ci-pending` (not a failure — the caller may retry later). Rationale: a fresh push triggers a new CI run that needs time to register; an unbounded wait would hang a long-lived session (command-hygiene violation). Alternative — single immediate re-check — rejected because it would almost always report `ci-pending` right after a push.

**Decision: Compose with `/jj-land` by verdict, not by dependency.**
`/jj-keep-current` returns its verdict; `/jj-land` (when it exists) calls it and refuses to land on anything but `landable`. This change documents that composition in prose but adds no requirement that depends on D4. Rationale: D4 is in-flight; coupling would make this change un-mergeable until D4 is canonical, violating the worker contract's "do not depend on in-flight changes being canonical".

## Risks / Trade-offs

- **[Pushing a rebased stack re-triggers CI, adding queue load.]** → The no-op fast path skips push when trunk hasn't moved; rebase+push only happen on genuine trunk movement.
- **[A conflicted rebase mutates the local stack into a conflicted state.]** → The rebase is reported as `rebase-conflicted` and the stack is left conflicted-but-recoverable (jj first-class conflict, `jj op restore`-able); the skill never pushes it and never auto-resolves, so the remote PR is untouched until a human resolves.
- **[`ci-missing` could be read as "safe".]** → It is a distinct, explicitly-surfaced verdict reason, never folded into green; the caller decides policy.
- **[Bounded poll can return `ci-pending` while CI is still healthy.]** → `ci-pending` is a hold, not a block; the verdict is re-runnable, so the caller retries rather than failing the stack.
- **[Trunk bookmark name varies per repo (main/master/trunk).]** → Trunk bookmark is a resolved input (config/arg), not hardcoded.
- **[Concurrent stacks all rebasing onto a moving trunk could thrash.]** → Out of scope to coordinate; each invocation is point-in-time and idempotent via the fast path. Documented as a non-goal (no standing watch).
