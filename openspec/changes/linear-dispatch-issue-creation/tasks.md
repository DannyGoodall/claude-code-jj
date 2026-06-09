## 1. Binding skill: dispatch-side creation hook

- [x] 1.1 Extend the `jj-concurrent-linear` binding skill (`plugins/jj-concurrent-linear/skills/jj-linear/SKILL.md`) with a dispatch-side section: triggered when the orchestrator begins a `/jj-openspec apply` or a `jj-delegate` fan-out, before workers are provisioned/dispatched. Declare that it owns no jj/workspace choreography and no report-format ownership (consistent with the reconcile half).
- [x] 1.2 Document the binding config block read at dispatch: agent-bound label (default `ready-for-agent`), and the Linear team/project routing — coordinated with the reconcile half so both halves read one config.

## 2. Issue creation

- [x] 2.1 Specify creation of exactly one umbrella issue per fan-out/apply, representing the change/fan-out.
- [x] 2.2 Specify creation of one sub-issue per worker (per task-group), each parented to the umbrella; derive the sub-issue title from the task-group name when the plan names it, else the workspace basename.
- [x] 2.3 Enforce the ordering invariant: no worker is dispatched before its sub-issue exists (or creation is explicitly skipped per the unavailability rule).

## 3. Labelling

- [x] 3.1 Apply the configured agent-bound label (default `ready-for-agent`) to the umbrella and every created sub-issue.
- [x] 3.2 Handle a missing/non-existent configured label: skip labelling with a non-fatal note, do NOT fail creation.

## 4. Manifest ID threading (dispatch → reconcile contract)

- [x] 4.1 After creating a worker's sub-issue, record `{ workspacePath → { umbrellaId, subIssueId } }` in the orchestrator's agent-plan manifest, keyed by that worker's provision-time workspace path.
- [x] 4.2 Ensure all sibling workers under one fan-out record the same umbrella ID and each its own distinct sub-issue ID.
- [x] 4.3 Document that this is the exact shape the reconcile half reads; no new field is added to the worker JSON report contract.

## 5. Worker Linear-agnosticism

- [x] 5.1 Specify that the worker brief carries no Linear identifier the worker must use or return, and the worker report carries none; any issue URL placed in a brief is advisory-only.

## 6. Idempotency

- [x] 6.1 Before creating, check the manifest for an existing umbrella (for the fan-out) and an existing sub-issue (for the workspace path); reuse recorded IDs when present.
- [x] 6.2 Ensure resume-in-place (successor at the same workspace path) reuses the recorded sub-issue and creates no new umbrella/sub-issue.
- [x] 6.3 Ensure a retried/re-run plan reuses the recorded umbrella and per-workspace sub-issues with no duplicates.

## 7. Degradation & edge handling

- [x] 7.1 Skip-and-note when the Linear MCP is unreachable at dispatch; provision and dispatch workers exactly as without the binding.
- [x] 7.2 Skip creation entirely when the binding is not enabled (no triggers, no Linear calls).
- [x] 7.3 Confirm that a skipped creation writes no manifest entry, so the reconcile half's existing "no sub-issue recorded → skip-and-note, no fallback" path handles it cleanly.

## 8. Documentation

- [x] 8.1 Document the dispatch-side creation flow and the shared `{ workspacePath → { umbrellaId, subIssueId } }` manifest contract in the skill, cross-referencing the reconcile-half change (`jj-concurrent-linear`).
- [x] 8.2 Note the relationship to the `linear-github-sync` convention (umbrella + sub-issue per slice, `ready-for-agent` label) and the explicit non-goals (no report-driven updates, no PR cross-linking) it hands off to the reconcile half.
