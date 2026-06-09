## Why

When the `jj-delegate` orchestrator fans out background workers, each worker already emits a structured JSON report (status, change-ids, `blocked_on`, conflicts) — but that signal stays in the orchestrator's session and never reaches the issue tracker. In repos that track each delegated slice as a Linear sub-issue under an umbrella, a human still has to hand-transcribe "this worker finished" / "this worker is blocked on X" into Linear. The report is already machine-readable; the gap is a binding that turns it into Linear sub-issue updates. Linear access is not wanted in every repo, so this must be opt-in.

## What Changes

- A new **separately-enableable plugin** `jj-concurrent-linear` (the third marketplace plugin), mirroring how `jj-concurrent-openspec` is a distinct, separately-enabled binding. It requires the `jj-concurrent` plugin and the Linear MCP server; it is absent (no triggers, no Linear calls) wherever it is not enabled.
- A **report → Linear mapping**: the orchestrator, on receiving a worker's structured JSON report, transitions that worker's Linear sub-issue (in-progress → done on a clean finish) and posts a **blocker comment** when the report carries a non-null `blocked_on`. Stalls/no-report and conflicts map to defined Linear updates too.
- **ID threading**: a defined contract for how umbrella-issue and per-worker sub-issue IDs are carried from dispatch (when a workspace+worker is provisioned) through reconcile (when the report lands), so the right sub-issue is updated for the right worker.
- The binding layers **only** over `jj-delegate`'s existing reconcile point and the worker's existing report contract — it adds no jj/workspace choreography and does not change the worker agent or the report format.

## Capabilities

### New Capabilities
- `jj-linear-sync`: the Linear binding over `jj-delegate` — the worker-report → Linear sub-issue mapping (status transitions + blocker comments), the dispatch→reconcile ID-threading contract, and the separately-enabled-plugin packaging requiring `jj-concurrent` and the Linear MCP.

### Modified Capabilities
<!-- None. The binding consumes the existing jj-workspace-worker report contract and the existing jj-delegate reconcile point without changing either spec. -->

## Impact

- New plugin `jj-concurrent-linear` added to the `claude-code-jj` marketplace (`.claude-plugin/marketplace.json`), bringing the marketplace to three plugins: `jj-concurrent` (core), `jj-concurrent-openspec` (OpenSpec binding), `jj-concurrent-linear` (Linear binding).
- Hard dependency on the `jj-concurrent` plugin (the `jj-delegate` mechanism and `jj-workspace-worker` report contract) and on the Linear MCP server being configured in the host session.
- No change to `jj-delegate`, `jj-workspace-worker`, `jj-safety-hooks`, or the JSON report shape — the binding reads the report and the orchestrator's plan manifest only.
- No change to any target project's application code.
