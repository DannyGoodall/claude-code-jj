## Why

The `jj-concurrent-linear` binding (change `jj-concurrent-linear`, capability `jj-linear-sync`) updates a worker's Linear sub-issue at reconcile — but it explicitly treats *creating* the umbrella issue and sub-issues as a Non-Goal, assumed to be done by "an upstream step" before dispatch. Today that step is manual: a human hand-creates the umbrella + one sub-issue per worker and hand-records the IDs before a fan-out, or the reconcile-side updates simply have nothing to update. This change is that upstream step: it auto-creates the umbrella and sub-issues at dispatch and threads their IDs into the orchestrator's manifest, so the reconcile-side mapping has real, correctly-keyed issues to act on.

## What Changes

- At the start of a `/jj-openspec apply` or any `jj-delegate` fan-out, the Linear binding SHALL **auto-create one Linear umbrella issue** for the change/fan-out and **one sub-issue per worker (per task-group)**, before workers are dispatched.
- Each created sub-issue (and the umbrella) SHALL receive a configurable **label** (default `ready-for-agent`) marking it as agent-bound work.
- The created **umbrella ID and per-worker sub-issue IDs SHALL be threaded into the orchestrator's agent-plan manifest**, keyed by workspace path — the exact `{ workspacePath → { umbrellaId, subIssueId } }` custody that the reconcile-side `jj-linear-sync` mapping already reads. The umbrella/sub-issue IDs created here are precisely the IDs that the existing change updates at reconcile.
- The **worker stays Linear-agnostic**: its dispatch brief and JSON report carry no Linear identifier; ID custody belongs entirely to the orchestrator (mirroring the reconcile-side contract).
- Creation SHALL be **idempotent**: a re-dispatch, a retried plan, or a resume-in-place of an existing workspace SHALL reuse the recorded umbrella/sub-issue rather than create duplicates.
- When the **Linear MCP is unavailable** (or the binding is not enabled), creation SHALL be skipped with a non-fatal note and dispatch SHALL proceed unaffected — the fan-out is never blocked by Linear.

## Capabilities

### New Capabilities
- `jj-linear-sync`: ADD the dispatch-side creation half of the Linear binding — auto-creation of the umbrella issue and per-worker sub-issues, label application, ID-threading into the manifest at dispatch, idempotent re-dispatch/resume, and skip-and-note when Linear is unavailable. (The capability's reconcile-side update half is authored by the active `jj-concurrent-linear` change; this change is scoped strictly to ADDED requirements on the same capability and does not depend on that change already being in `openspec/specs/`.)

### Modified Capabilities
<!-- None. This change adds requirements to jj-linear-sync only; it changes no requirement of jj-delegate, jj-openspec-binding, jj-workspace-worker, or jj-safety-hooks. It reads the jj-delegate dispatch point and agent-plan manifest, and the jj-openspec-binding apply/fan-out trigger, without altering either spec. -->

## Impact

- Part of the `jj-concurrent-linear` plugin; requires the `jj-concurrent` plugin (the `jj-delegate` dispatch mechanism + agent-plan manifest) and a configured Linear MCP server, consistent with the reconcile-side half.
- Adds Linear *write* calls (issue creation, label application) at the dispatch boundary; the binding must hold a label/project/team config (default label `ready-for-agent`).
- Composes with the existing `jj-concurrent-linear` reconcile half on the shared manifest contract: this change writes `{ umbrellaId, subIssueId }` keyed by workspace path; the reconcile half reads it. No new field is added to the worker report contract.
- No change to `jj-delegate`, `jj-workspace-worker`, `jj-openspec-binding`, or `jj-safety-hooks` specs, and no change to any target project's application code.
