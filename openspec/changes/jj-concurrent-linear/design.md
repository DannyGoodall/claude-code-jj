## Context

`jj-concurrent` defines an orchestrator that fans out `jj-workspace-worker` subagents, each in its own jj workspace. The worker's final message is a structured JSON report (`workspace`, `bookmark`, `changes`, `submitted`, `tests_run`, `blocked_on`, `conflicts_seen`, `notes`) consumed by the orchestrator as data at the reconcile step. `jj-concurrent-openspec` already demonstrates the binding pattern: a separate, separately-enableable plugin that layers a domain concern over the generic mechanism without owning any jj/workspace choreography.

Teams that track each delegated slice as a Linear sub-issue under an umbrella issue (the documented `linear-github-sync` convention: umbrella + sub-issue per change) currently hand-transcribe worker outcomes into Linear. The signal is already machine-readable in the report; what is missing is a binding that consumes it. Linear access is sensitive and repo-specific, so the binding must be opt-in and absent by default — exactly the packaging stance `jj-concurrent-openspec` takes toward OpenSpec.

## Goals / Non-Goals

**Goals:**
- Drive Linear sub-issue updates off the worker's existing structured JSON report, with zero changes to the report format or the worker agent.
- Define the report-field → Linear-update mapping precisely (status transition on clean finish; blocker/conflict comment otherwise).
- Define how umbrella and sub-issue IDs are threaded from dispatch to reconcile, with the worker kept entirely Linear-agnostic.
- Package as a third marketplace plugin, separately enableable, requiring `jj-concurrent` + the Linear MCP — mirroring `jj-concurrent-openspec`.

**Non-Goals:**
- Creating the umbrella issue or the sub-issues. That belongs to whatever authored the fan-out plan (e.g. a `to-issues` / Linear-sync step upstream); this binding only updates sub-issues that already exist and are recorded in the manifest.
- Changing `jj-delegate`, `jj-workspace-worker`, `jj-safety-hooks`, or the JSON report shape.
- GitHub PR ↔ Linear cross-linking (that is the existing `linear-github-sync` concern; this binding stops at sub-issue status + comments).
- Giving the worker any Linear capability or identifier.

## Decisions

**Decision: Bind at the orchestrator's reconcile point, not inside the worker.**
The orchestrator already receives the report as data at reconcile and already owns the agent-plan manifest, bookmarks, and integration. It is the only role with both the report and the Linear identifiers. Putting Linear there keeps the worker Linear-agnostic (no Linear MCP in the worker's tool surface, no IDs in its brief) and means a stalled/no-report worker simply yields no Linear update — the safe default. *Alternative considered:* let the worker call Linear directly. Rejected — it would leak Linear credentials/IDs into every workspace, couple the worker contract to Linear, and a dying worker could leave a half-applied update.

**Decision: Key the dispatch→reconcile ID map on the worker's workspace path.**
The workspace path is the worker's stable identity across the lifecycle (it is how resume-in-place re-targets a successor, and it is the `workspace` field the report echoes back). The manifest records `{ workspacePath → { umbrellaId, subIssueId } }` at dispatch; at reconcile the binding looks up by the report's `workspace`. *Alternative considered:* key on bookmark or change-id. Rejected — bookmarks can be renamed by the orchestrator and change-ids are only known after the worker runs, whereas the workspace path is fixed at provision time and survives resume-in-place.

**Decision: Mapping table from report fields to Linear updates.**

| Report condition | Linear update to the worker's sub-issue |
|---|---|
| `blocked_on` null AND `conflicts_seen` null (clean finish) | transition in-progress → done (idempotent) |
| `blocked_on` non-null | post comment with the blocker text; do NOT mark done; leave needing-attention |
| `conflicts_seen` non-null | post comment describing the conflict; do NOT mark done |
| no report at all (stall, resume-in-place) | no update; wait for a successor's report |
| Linear MCP unavailable / no sub-issue recorded | skip; note in reconcile report; integration proceeds |

`tests_run`, `changes`, and `notes` MAY be folded into the done-transition comment or the blocker comment as context, but they never by themselves drive a state change. *Alternative considered:* derive done from `submitted`. Rejected — `submitted` is always false for workers (the orchestrator pushes), so it is not a finish signal; a clean finish is `blocked_on`/`conflicts_seen` both null.

**Decision: Idempotent transitions.**
Reconcile can be retried. The binding checks the sub-issue's current state before transitioning, so re-applying a clean report is a no-op rather than a duplicate transition or error. Comments are append-only by nature; on retry the binding SHOULD avoid posting a byte-identical blocker comment twice (e.g. guard on the last comment).

**Decision: Mirror `jj-concurrent-openspec` packaging.**
Third entry in `.claude-plugin/marketplace.json`; its own `plugins/jj-concurrent-linear/` tree; a thin `jj-linear` skill (or reconcile-tail extension) that the orchestrator consults. Hard requirement on `jj-concurrent` and the Linear MCP; absent triggers when not enabled.

## Risks / Trade-offs

- **Linear MCP latency or outage stalls reconcile** → the binding treats Linear updates as best-effort: a failed/unreachable Linear call is non-fatal, skipped with a note, and never blocks workspace integration or teardown.
- **Wrong sub-issue updated** → mitigated by keying strictly on workspace path and refusing any fallback to the umbrella or a sibling when no sub-issue is recorded.
- **Stalled worker silently looks "done"** → explicitly prevented: no report means no update; only a real report (from the original or a resume-in-place successor) moves the sub-issue.
- **Duplicate updates on reconcile retry** → mitigated by idempotent state-check transitions and a last-comment guard.
- **Scope creep into issue creation / PR cross-linking** → held out by Non-Goals; this binding only updates existing sub-issues with status + comments.

## Open Questions

- Whether to use a dedicated Linear "Blocked" state (if the team defines one) versus leaving the sub-issue in-progress with a blocker comment — the spec allows either; the default should be configurable per team.
- Where the manifest physically lives and its exact schema is owned by `jj-delegate`; this binding only adds the `{ umbrellaId, subIssueId }` fields keyed by workspace path and should coordinate with the manifest format if/when it is formalized.
