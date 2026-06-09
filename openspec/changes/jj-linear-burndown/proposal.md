## Why

A Linear board accumulates a backlog of issues that have been triaged to `ready-for-agent` — work that is specified enough for an autonomous agent to pick up. Today, turning that backlog into running work is manual: a human reads the board, decides what to dispatch, and hand-feeds each issue to `/jj-delegate` one at a time, watching for capacity. The `jj-delegate` mechanism can already run many workers concurrently on jj workspaces, and the `jj-concurrent-linear` plugin already knows how to write a worker's result back to a Linear issue — but nothing ties the *board* to the *fan-out*. The missing piece is a queue driver: drain the board's ready-for-agent issues as a bounded stream of concurrent jj workers and update each issue as its worker lands. That makes the board itself a work queue, with jj as the engine behind a live burndown.

## What Changes

- Add a new **orchestrator-only** skill `jj-burndown` (trigger `/jj-burndown <board>`) under `plugins/jj-concurrent-linear/skills/jj-burndown/SKILL.md` — the third skill in the separately-enableable `jj-concurrent-linear` plugin, alongside the `jj-linear-sync` binding.
- **Board → work queue selection**: the skill queries the named Linear board (resolved by name or id) for issues in the `ready-for-agent` state, producing a deterministic, re-queryable, ordered candidate set. Issues not `ready-for-agent` are excluded.
- **Bounded concurrent drain**: the queue drains under a moderate, configurable concurrency cap (default 3). The skill maintains a sliding window — as one worker lands and reconciles, the next ready issue is pulled and dispatched — never exceeding the cap. This is explicitly NOT a single big fan-out of the whole board.
- **Per-issue dispatch via jj-delegate**: each pulled issue becomes exactly one `jj-delegate` worker in its own jj workspace (concurrent siblings, dispatched in background by default per the `jj-delegate` spec). The issue's body/spec is the worker's workload. The skill owns no jj/workspace choreography — it delegates all of that to `jj-delegate`.
- **Per-issue update as it lands**: when a worker reports, the skill updates that issue's status (in-progress → done on a clean finish; blocker comment + leave-for-attention on blocked/conflict). Where the C2 status-sync binding (`jj-linear-sync`) is enabled it is reused for the transition; where it is absent the skill applies a minimal inline update and notes the degraded mode.
- **Live burndown readout**: a running summary at a defined cadence (each time the window advances) showing queue depth remaining, in-flight workers, done count, and blocked count; plus a final summary when the queue is empty.
- **Re-query + termination**: the queue is re-queried as it drains so newly-labelled issues are picked up within the same run; the run terminates when no `ready-for-agent` issues remain and no workers are in flight.

## Capabilities

### New Capabilities
- `jj-linear-burndown`: An orchestrator-only board-as-work-queue driver — the `/jj-burndown <board>` board/label query that selects the ready-for-agent candidate set, the bounded sliding-window concurrent drain that dispatches each issue as a `jj-delegate` worker, the per-issue Linear update as each worker lands (reusing the C2 status-sync binding when present, degrading to a minimal inline update when absent), the live burndown summary cadence, and the re-query/termination rule. It composes with the C1 umbrella/sub-issue and C2 status-sync bindings but does NOT hard-depend on them.

### Modified Capabilities
<!-- None. jj-delegate (orchestrator/worker split, concurrent-sibling provisioning, background dispatch) and jj-linear-sync (report → Linear mapping) are referenced for composition, but their requirements do not change. The burndown driver layers over jj-delegate's existing dispatch/reconcile points and reuses jj-linear-sync's mapping when present without altering either spec. -->

## Impact

- New skill file: `plugins/jj-concurrent-linear/skills/jj-burndown/SKILL.md`. No new hooks.
- New plugin skill within the existing `jj-concurrent-linear` plugin entry in the `claude-code-jj` marketplace; no new marketplace plugin.
- Hard dependency on the `jj-concurrent` plugin (the `jj-delegate` mechanism + `jj-workspace-worker` report contract) and on a configured Linear MCP server. Absent (no triggers, no Linear calls) wherever `jj-concurrent-linear` is not enabled.
- Soft/optional composition with the in-flight `jj-linear-sync` capability (C1 umbrella/sub-issues, C2 status sync): reused when enabled, degraded-but-functional when absent. This change does NOT depend on the `jj-concurrent-linear`/`jj-linear-sync` change being canonical.
- No change to `jj-delegate`, `jj-workspace-worker`, `jj-safety-hooks`, the JSON report shape, or any target project's application code.
