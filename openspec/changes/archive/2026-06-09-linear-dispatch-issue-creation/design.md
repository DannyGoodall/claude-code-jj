## Context

The `jj-concurrent` plugin's `jj-delegate` mechanism provisions one jj workspace per worker and dispatches workers in the background, tracking them in an agent-plan manifest. The `jj-concurrent-linear` binding (capability `jj-linear-sync`) layers Linear over that mechanism: at reconcile it reads a worker's JSON report and updates the worker's Linear sub-issue (in-progress → done, or a blocker comment). That binding deliberately keys all lookups on the worker's **workspace path** and reads a `{ workspacePath → { umbrellaId, subIssueId } }` map from the manifest — but it lists umbrella/sub-issue *creation* as an explicit Non-Goal, assuming "an upstream step" populates that map before dispatch.

This change is that upstream step. It runs on the **dispatch** edge — the moment the orchestrator decides on a fan-out plan and begins provisioning workspaces — and it is the producer for the same manifest the reconcile half consumes. The two halves meet only on the manifest contract (`{ workspacePath → { umbrellaId, subIssueId } }`); neither touches the worker report contract nor the jj/workspace choreography.

The documented team convention (`linear-github-sync`: umbrella issue per change, one sub-issue per slice, with a `ready-for-agent` label for agent-bound work) is what this automates.

## Goals / Non-Goals

**Goals:**
- Auto-create exactly one umbrella + one sub-issue per worker at the start of an apply/fan-out, before any worker is dispatched.
- Apply a configurable agent-bound label (default `ready-for-agent`) to created issues.
- Thread the created umbrella/sub-issue IDs into the agent-plan manifest keyed by workspace path, so the reconcile half resolves the right issue for the right worker with no further plumbing.
- Keep the worker entirely Linear-agnostic — ID custody stays with the orchestrator, mirroring the reconcile half.
- Be idempotent across re-dispatch, retried plans, and resume-in-place.
- Never block a fan-out on Linear availability.

**Non-Goals:**
- Updating issues from worker reports (status transitions, blocker/conflict comments) — that is the existing `jj-concurrent-linear` reconcile half; this change only *creates* and *records* the IDs it will use.
- GitHub PR ↔ Linear cross-linking — owned by the `linear-github-sync` convention; this change stops at creation + labelling + ID-threading.
- Owning the manifest's physical schema or location — that belongs to `jj-delegate`; this change only writes the `{ umbrellaId, subIssueId }` fields keyed by workspace path.
- Any change to `jj-delegate`, `jj-workspace-worker`, `jj-openspec-binding`, or `jj-safety-hooks` requirements, or to the worker JSON report format.

## Decisions

**1. Create on the dispatch edge, before provisioning workers — not lazily at first report.**
Creating issues up front means the umbrella + sub-issues exist (and are visible to humans) the moment the fan-out begins, and the reconcile half always finds a recorded sub-issue for a clean worker. *Alternative considered:* create lazily the first time a worker reports. Rejected — it leaves no Linear trace for in-flight or stalled work, and a stalled worker (which by the reconcile contract must leave its sub-issue untouched) would have no sub-issue at all.

**2. Key created IDs on workspace path, identical to the reconcile half.**
The workspace path is the worker's stable identity (it survives resume-in-place and is the `workspace` field the report echoes). Recording `{ workspacePath → { umbrellaId, subIssueId } }` at creation makes the producer and consumer share one key. *Alternative considered:* key on bookmark or change-id. Rejected for the same reasons the reconcile half rejects them — bookmarks can be renamed and change-ids are only known after the worker runs, whereas the workspace path is fixed at provision time.

**3. Idempotency is manifest-driven: presence of a recorded ID means "already created".**
Before creating, the binding checks the manifest for an existing umbrella (for the fan-out) and an existing sub-issue (for the workspace path). If present, it reuses them. This makes re-dispatch, retried plans, and resume-in-place safe without needing Linear-side dedup queries. *Alternative considered:* query Linear for an existing issue by title/label on each dispatch. Rejected — slower, racy under concurrent fan-outs, and title collisions are plausible; the manifest is the authoritative record the orchestrator already owns.

**4. Worker stays Linear-agnostic; any URL in a brief is advisory.**
The orchestrator may optionally drop a human-readable issue URL into a brief for traceability, but nothing the worker does or returns depends on it. This preserves the reconcile-half invariant that the report contract carries no Linear identifier, so the two halves never diverge on what a worker knows.

**5. Skip-and-note on unavailability; the absence propagates cleanly to reconcile.**
If Linear is unreachable or the label is missing, creation degrades (skip labelling, or skip creation entirely) with a non-fatal note rather than failing the fan-out. When creation is skipped, no manifest entry is written, and the reconcile half's existing "no sub-issue recorded → skip-and-note, no fallback" rule handles the rest. The two halves share one degradation story.

## Risks / Trade-offs

- **Orphaned issues if a fan-out is aborted after creation but before any work** → Mitigated by labelling everything `ready-for-agent` (so aborted work is discoverable) and by idempotency (a re-run reuses, never re-creates); cleanup of truly-abandoned umbrellas is left to the team's normal Linear hygiene, out of scope here.
- **Concurrent fan-outs racing on the manifest** → Mitigated by keying strictly on workspace path (unique per worker) and by the orchestrator owning all manifest writes single-threaded at dispatch; the umbrella is created once per fan-out plan, not per worker.
- **Linear write latency at the dispatch boundary slows fan-out start** → Accepted trade-off; creation is a bounded set of writes (1 umbrella + N sub-issues) done once at the start, and unavailability is a skip, never a block.
- **Drift from the reconcile half's manifest schema** → Mitigated by treating `{ workspacePath → { umbrellaId, subIssueId } }` as the shared contract documented in both changes; the field shape is owned by `jj-delegate`'s manifest and both halves coordinate to it.
- **Wrong label / wrong team scoping creates issues in the wrong place** → Mitigated by making label (and team/project routing) configurable per repo, with a missing-label skip rather than a hard failure.

## Open Questions

- Whether sub-issue titles should be derived from task-group names (when a fan-out plan names them) versus a generic `worker N` scheme — proposed default is task-group name when available, else workspace basename.
- Whether the umbrella should also be created for a single-worker `apply` (one umbrella + one sub-issue) or collapse to a single issue — this change specifies the umbrella-always shape for uniformity with the reconcile half's parent/child model; a future toggle could collapse it.
- Exact Linear team/project routing config and where it lives — coordinate with the reconcile half's per-team config (e.g. the "Blocked" state question) so both halves read one binding config block.
