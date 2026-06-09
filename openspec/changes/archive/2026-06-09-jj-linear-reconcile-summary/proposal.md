## Why

When the `jj-delegate` orchestrator reconciles a worker, the rich outcome of that slice — what changed, why it broke, what tests ran, where the PR is, and whether a human still needs to eyeball something automated verify cannot cover — exists only transiently in the orchestrator's session. Teams that track each fan-out under a Linear umbrella issue get, at best, a terse status flip; the actual narrative (root cause, test results, PR link) and any residual human-gate work are lost or hand-transcribed. The worker's JSON report plus the `jj-openspec-binding` verify outcome already carry this signal — what is missing is a binding that turns reconcile into a posted umbrella summary and, when warranted, an explicit human-gate sub-issue.

## What Changes

- A new capability `jj-linear-reconcile` inside the **separately-enabled** `jj-concurrent-linear` plugin: at the orchestrator's reconcile step it composes a **structured summary comment** on the fan-out's umbrella Linear issue from the worker's JSON report (`changes`, `tests_run`, `blocked_on`, `conflicts_seen`, `notes`) and the verify/PR outcome of the binding's reconcile tail.
- The summary content is **defined precisely**: what changed (the worker's `changes` / PR diff), root cause(s) (from `notes` / blocker text), test results (from `tests_run` plus the verify outcome), and the PR link (from the reconcile tail), so the comment is reproducible from documented sources rather than free-form.
- An **auto human-gate rule**: when a reconciled change needs a human pass that automated verify cannot cover (e.g. a manual UI/visual check), the binding **auto-creates a Linear sub-issue labelled `ready-for-human`** under the umbrella, describing exactly what to check, why automated verify cannot cover it, and where to look (PR / route / screenshot target).
- The trigger for the human-gate sub-issue is **defined**: it fires when the worker report or verify outcome flags visual/manual-only verification (e.g. a `notes`/verify signal that a UI/visual check is outstanding), and SHALL NOT fire on a fully-automated clean finish.
- The binding layers **only** over `jj-delegate`'s existing reconcile point and the worker's existing report contract plus the binding's verify tail; it adds no jj/workspace choreography, does not change the worker agent or the report format, and treats every Linear call as best-effort (never blocks integration or teardown).

## Capabilities

### New Capabilities
- `jj-linear-reconcile`: the reconcile-time Linear-posting binding — the umbrella **summary comment** (defined content sourced from the worker report + verify outcome) and the **auto human-gate sub-issue** rule (when a manual/visual pass is needed, create a `ready-for-human`-labelled sub-issue describing exactly what to check), packaged in the separately-enabled `jj-concurrent-linear` plugin and best-effort against the Linear MCP.

### Modified Capabilities
<!-- None. This capability consumes the existing jj-delegate reconcile point, the jj-workspace-worker report contract, and the jj-openspec-binding verify outcome without changing any of those specs. It is authored as a standalone capability and does not depend on the in-flight jj-linear-sync change being canonical. -->

## Impact

- New capability `jj-linear-reconcile` shipped inside the `jj-concurrent-linear` plugin (the Linear binding), which already requires the `jj-concurrent` plugin and a configured Linear MCP server.
- Hard dependency on the `jj-concurrent` plugin (the `jj-delegate` reconcile point and `jj-workspace-worker` report contract) and, for the verify-outcome inputs, on the `jj-openspec-binding` reconcile tail; soft dependency on the Linear MCP being reachable (updates are best-effort).
- No change to `jj-delegate`, `jj-workspace-worker`, `jj-safety-hooks`, `jj-openspec-binding`, or the JSON report shape — the binding reads the report, the verify outcome, and the orchestrator's plan manifest only.
- Independent of the in-flight `jj-linear-sync` change: it shares the same plugin and the same umbrella/sub-issue threading idea but defines its own capability so it can land without `jj-linear-sync` being canonical first.
- No change to any target project's application code.
