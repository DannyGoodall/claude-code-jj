## Context

The `claude-code-jj` marketplace has three plugins: `jj-concurrent` (the core `jj-delegate` orchestrator/worker mechanism), `jj-concurrent-openspec` (the OpenSpec binding), and `jj-concurrent-linear` (the Linear binding). The Linear binding's first capability, `jj-linear-sync` (the in-flight `jj-concurrent-linear` change), maps a worker's structured JSON report onto a Linear sub-issue — status transitions on a clean finish, blocker comments on a block — with umbrella/sub-issue IDs threaded through the orchestrator's agent-plan manifest. That binding answers "when a worker lands, update its issue." It does not answer "where does the stream of workers come from?"

This change adds the queue driver: `jj-burndown` reads a Linear board's `ready-for-agent` issues and feeds them, under a bounded concurrency window, into `jj-delegate`. It is the inverse direction of `jj-linear-sync` (board → workers, vs worker-report → issue) and composes with it: when `jj-linear-sync` is enabled, the burndown reuses its report-to-Linear mapping for the per-issue landing update; when absent, the burndown still drains the board and applies a minimal inline status update.

Constraints: the skill is orchestrator-only (primary workspace), owns no jj choreography, must not depend on the `jj-linear-sync` change being canonical, and must obey the worker/orchestrator contract (only `jj-delegate` touches workspaces, bookmarks, push, integration).

## Goals / Non-Goals

**Goals:**

- Turn a Linear board into a drainable work queue via one trigger, `/jj-burndown <board>`.
- Bound concurrency to a moderate, configurable cap with a sliding window so the queue drains steadily rather than as one big fan-out.
- Map one ready-for-agent issue to one `jj-delegate` worker, with the issue body as the workload.
- Update each issue as its worker lands, reusing `jj-linear-sync` when present and degrading gracefully when absent.
- Give a live burndown readout (queue depth, in-flight, done, blocked) and a final summary.
- Pick up newly-labelled issues mid-run via re-query, and terminate cleanly when the board is drained.

**Non-Goals:**

- No jj/workspace choreography of its own — provisioning, dispatch, integration, teardown all belong to `jj-delegate`.
- No redefinition of the worker-report → Linear mapping (that is `jj-linear-sync`'s contract; reuse it).
- No triage of issues into `ready-for-agent` (that is the `triage` workflow's job; the board state is an input, not something this skill mutates beyond the landing status update).
- No new hooks, no new marketplace plugin, no change to the worker report shape.
- No PR creation / merge policy — that is downstream of `jj-delegate` integration and out of scope here.

## Decisions

**D1 — Skill, not hook; orchestrator-only.** The driver is a `SKILL.md` at `plugins/jj-concurrent-linear/skills/jj-burndown/SKILL.md`, invoked by `/jj-burndown <board>`. It runs in the primary workspace as a loop that the orchestrating agent executes. Alternative considered: a hook on `jj-delegate` reconcile that auto-pulls the next issue. Rejected because a hook has no natural place to own board-query state, the cap, or the re-query cadence, and would entangle the queue driver with `jj-delegate`'s reconcile point. A skill keeps the queue logic in one readable place and keeps `jj-delegate` unchanged.

**D2 — Sliding window over single fan-out.** Dispatch up to `cap`, then on each landing pull-and-dispatch the next. Alternative: fan out the whole board at once and let `jj-delegate` run them all. Rejected — an unbounded fan-out floods workspaces/Linear, defeats the "moderate concurrency" intent, and makes the burndown readout meaningless. The window keeps in-flight ≤ cap and gives a steady, observable drain.

**D3 — Default cap 3, configurable.** Three is a moderate default that exercises concurrency without overwhelming a developer machine or the Linear API. Configurable via the skill's documented override (e.g. an argument or a config key read at start). The spec fixes only "moderate default, configurable, never exceeded"; the exact override surface is an implementation detail for the SKILL.md.

**D4 — Compose with `jj-linear-sync`, do not depend on it.** At the landing step the skill checks whether the C2 status-sync binding is enabled. If yes, it defers the transition to that binding's mapping (single source of truth). If no, it applies a minimal inline update (in-progress → done on clean; comment + hold on blocked) and flags degraded mode in the readout. This keeps the burndown shippable before the `jj-linear-sync` change is canonical, and avoids two competing report-to-Linear mappings when both are present.

**D5 — Re-query (live queue) over snapshot-at-start.** The queue is re-queried as it drains rather than frozen at start. Rationale: a burndown is most useful when the board is actively triaged — issues moved to `ready-for-agent` during a long run should be picked up in the same run, not require a second invocation. The cost (an extra board query per window advance) is small. To stay safe, dispatch is idempotent per issue within a run: the skill tracks dispatched/completed issue ids and never re-dispatches one a re-query surfaces again. Termination is the fixpoint: a re-query returning no ready issues with no workers in flight.

**D6 — Reuse `jj-delegate`'s manifest/identity, add no new identity.** Each worker's stable identity is its workspace path (as in `jj-delegate` and `jj-linear-sync`). The burndown keys its per-run dispatch/landing bookkeeping (issue id ↔ workspace) the same way, so when `jj-linear-sync` is present the two agree on which issue a landing belongs to without a second identity scheme.

**D7 — Compose with C1 umbrella when present, but do not require it.** When the C1 umbrella/sub-issue convention is in play, the drained issues are already the sub-issues under an umbrella and the burndown simply drives them. When it is absent, the burndown treats the board's ready-for-agent issues as flat top-level work. The driver does not create umbrellas or sub-issues — that structure is C1's, consumed here, not produced.

## Risks / Trade-offs

- **Re-query racing with a worker still in flight** → Idempotent per-issue dispatch (D5): the skill never dispatches an issue id it has already dispatched this run, so a re-query that returns an in-flight issue is a no-op.
- **Two report-to-Linear mappings if both `jj-linear-sync` and an inline update run** → D4 makes the inline update a strict fallback gated on the binding being absent; when present, the burndown defers entirely. Only one mapping ever runs per landing.
- **Linear API rate limits under wider caps** → The moderate default (3) and per-window re-query keep call volume low; a higher configured cap is the operator's choice and the readout makes the rate visible.
- **Long runs / board never drains (continuous triage)** → Acceptable: the run is a live drain and terminates only at the drained fixpoint; an operator can stop it. The spec defines termination but does not forbid a long-lived drain.
- **Worker stalls without a report** → Handled by `jj-delegate`'s resume-in-place; the burndown leaves that issue's status untouched until a successor reports (consistent with `jj-linear-sync`'s "a stall never silently marks done"). The slot is considered occupied until the worker resolves, so the cap is respected.
- **Degraded-mode inline update drift from the canonical mapping** → The inline update implements the same clean/blocked rule as `jj-linear-sync`; if the two ever diverge, the binding (when enabled) wins because the burndown defers to it.

## Migration Plan

Additive only. Ship the `jj-burndown` SKILL.md inside the existing `jj-concurrent-linear` plugin. No schema, no hook, no marketplace-plugin change. Enablement is the existing plugin enablement; absence means no trigger. Rollback is removing the skill file — no state migration, since the skill writes only Linear issue status (the same writes a human or `jj-linear-sync` would make) and the gitignored agent-plan manifest owned by `jj-delegate`.

## Open Questions

- Exact override surface for the cap (positional `/jj-burndown <board> <cap>`, a flag, or a plugin config key) — left to the SKILL.md; the spec only fixes the default/configurable/never-exceeded contract.
- Whether the summary readout should also surface per-issue links (issue id ↔ workspace ↔ change-id) inline, or defer that to the `jj-fleet` view — leaning on `jj-fleet` for the workspace-level detail and keeping the burndown readout at the queue-counts altitude.
