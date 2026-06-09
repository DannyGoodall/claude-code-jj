## Context

`jj-delegate` defines an orchestrator that fans out `jj-workspace-worker` subagents, each in its own jj workspace. At the **reconcile** step the orchestrator receives a worker's structured JSON report (`workspace`, `bookmark`, `changes`, `submitted`, `tests_run`, `blocked_on`, `conflicts_seen`, `notes`) as data, integrates the change, and — under the `jj-openspec-binding` reconcile tail — runs verify and (for the implementing shape) pushes / opens a PR. The verify outcome (pass/fail) and the PR link are produced at that tail.

Teams that track each fan-out under a Linear umbrella issue (the `linear-github-sync` convention: umbrella + sub-issue per change) get only a transient view of all this in the orchestrator's session. The narrative a reviewer actually wants on the umbrella — what changed, why it broke, what tests ran, where the PR is — and any residual *human* gate (a manual UI/visual check automated verify cannot cover) are lost unless hand-transcribed. The inputs already exist; this capability is the binding that posts them.

`jj-concurrent-linear` already establishes the packaging stance (separate, separately-enableable plugin requiring `jj-concurrent` + the Linear MCP) and the dispatch→reconcile ID-threading idea (manifest keyed by workspace path). This capability is authored as a **standalone capability inside that plugin** so it can land without the in-flight `jj-linear-sync` change being canonical first; the two share a plugin and the manifest-threading idea but neither is a hard dependency of the other.

## Goals / Non-Goals

**Goals:**
- Post a single, **structured** umbrella summary comment at reconcile, composed only from the worker report and the verify/PR outcome, with four defined sections (what changed, root cause, test results, PR link).
- Define the **human-gate rule** precisely: auto-create a `ready-for-human`-labelled sub-issue under the umbrella only when a manual UI/visual check that automated verify cannot cover is signalled, with a body that says what to check, why automation cannot cover it, and where to look.
- Keep the worker entirely Linear-agnostic and read-only over existing inputs; add no jj/workspace choreography; never block integration or teardown on a Linear call.
- Make summary posting idempotent across reconcile retries.

**Non-Goals:**
- Creating the umbrella issue itself, or the per-worker status sub-issues — that is the upstream fan-out/`to-issues` step and (for status flips) the in-flight `jj-linear-sync` capability. This capability only *posts to* an existing umbrella and *creates* the human-gate sub-issue.
- Worker-status transitions (in-progress → done) and blocker-comment-on-sub-issue — that is `jj-linear-sync`'s concern; this capability deliberately does not duplicate it and does not depend on it.
- GitHub PR ↔ Linear cross-linking beyond pasting the PR link into the summary.
- Changing `jj-delegate`, `jj-workspace-worker`, `jj-safety-hooks`, `jj-openspec-binding`, or the JSON report shape.
- Deciding *how* a manual/visual check is signalled inside verify — this capability consumes whatever signal the verify outcome / report exposes and defines the trigger contract, not the signal's production.

## Decisions

**Decision: Post at the orchestrator's reconcile point, not inside the worker.**
The orchestrator is the only role holding both the report and the Linear identifiers (umbrella id in the manifest), and it is where the verify outcome and PR link are produced. Putting the post there keeps the worker Linear-agnostic and means a stalled/no-report worker yields no umbrella post — the safe default. *Alternative:* let the worker post. Rejected — it leaks Linear access/IDs into every workspace and a dying worker could half-post.

**Decision: Resolve the umbrella by the worker's workspace path.**
Mirrors `jj-concurrent-linear`'s threading: the manifest records `{ workspacePath → { umbrellaId, subIssueId } }` at dispatch; at reconcile the binding looks up the umbrella by the report's `workspace`. Workspace path is the worker's stable identity across resume-in-place. *Alternative:* key on bookmark/change-id. Rejected for the same reasons that change rejected them (renameable / not known until after the run).

**Decision: Four fixed summary sections with named sources.**

| Section | Source |
|---|---|
| What changed | worker report `changes` (+ PR title/diff from reconcile tail if present) |
| Root cause(s) | worker report `notes`; plus `blocked_on` / `conflicts_seen` text when present |
| Test results | worker report `tests_run` + the `jj-openspec-binding` verify outcome (pass/fail) |
| PR link | reconcile-tail push/PR output; else "no PR" + integrated change-id(s) |

A section with no source data renders an explicit "none reported" rather than fabricated prose. This makes the comment reproducible from documented inputs and reviewable. *Alternative:* free-form LLM summary. Rejected — non-reproducible, can hallucinate, and the spec could not pin down content.

**Decision: Human-gate trigger is a manual/visual-verification signal, not a blocker.**
A `ready-for-human` sub-issue is created **only** when the report or verify outcome carries a manual/visual-check signal (e.g. a `notes`/verify field saying a UI/visual pass is outstanding). A fully-automated clean finish creates no sub-issue (summary only). A blocker or conflict does **not**, by itself, create a human-gate sub-issue — that is a different failure mode, surfaced in the summary's Root-cause section (and, in `jj-linear-sync`, on the status sub-issue). Separating "needs a human's eyes on the running UI" from "is blocked" keeps the `ready-for-human` label meaningful. *Alternative:* raise `ready-for-human` on any non-clean finish. Rejected — it would flood the label with blockers that are not visual gates.

**Decision: Human-gate sub-issue body is a checklist of what/why/where.**
What to verify (the specific UI/visual behaviour), why automated verify cannot cover it, and where to look (PR link / affected route / screenshot target). This makes the sub-issue actionable by a human with no session context. The summary comment references that the gate was raised, so the umbrella reader sees the residual work.

**Decision: Idempotent summary, best-effort Linear.**
Reconcile can be retried, so the binding guards on the last summary comment for that worker to avoid byte-identical duplicates. Every Linear call (comment, sub-issue create) is best-effort: failure or an unreachable MCP is non-fatal, skipped with a note in the reconcile report, and never blocks integration/teardown.

**Decision: Standalone capability inside `jj-concurrent-linear`, independent of `jj-linear-sync`.**
Same plugin, same packaging requirement (requires `jj-concurrent` + Linear MCP, absent triggers when disabled), but its own spec. It neither imports nor is imported by `jj-linear-sync`; if both ship, `jj-linear-sync` flips the per-worker status sub-issue while this capability posts the umbrella summary and raises the human gate. Authoring it standalone lets it validate and land without `jj-linear-sync` being canonical.

## Risks / Trade-offs

- **Linear MCP latency/outage at reconcile** → treated as best-effort: skip + note, never block integration/teardown.
- **Wrong umbrella posted** → mitigated by resolving strictly via the manifest keyed on workspace path and refusing any fallback when no umbrella is recorded.
- **Human-gate over-fires (every non-clean finish becomes a visual gate)** → mitigated by the precise trigger: only a manual/visual signal fires it; blockers/conflicts do not.
- **Human-gate under-fires (a needed visual check is missed)** → accepted residual: the binding can only act on the signal the report/verify exposes; producing that signal is a verify-side concern (Open Question below).
- **Duplicate summaries on reconcile retry** → mitigated by the last-comment idempotency guard.
- **Scope overlap with `jj-linear-sync`** → held apart by Non-Goals: this capability does not transition status sub-issues or post blocker comments to them; it owns the umbrella summary and the human-gate sub-issue only.

## Open Questions

- How the manual/visual-verification signal is represented in the verify outcome / worker report (a dedicated field vs. a convention in `notes`). This capability defines the trigger contract ("when a manual/visual signal is present") but coordinates the signal's exact shape with the `jj-openspec-binding` verify tail.
- Whether the `ready-for-human` label must pre-exist in the team's Linear workspace or the binding should create it on first use (default: require it to pre-exist, skip-and-note if absent, consistent with best-effort).
- The exact agent-plan manifest schema is owned by `jj-delegate`; this capability only reads the `umbrellaId` keyed by workspace path and should coordinate if/when that schema is formalized.
