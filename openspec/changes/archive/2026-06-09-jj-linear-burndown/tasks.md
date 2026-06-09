## 1. Skill scaffold and enablement

- [x] 1.1 Create `plugins/jj-concurrent-linear/skills/jj-burndown/SKILL.md` with frontmatter declaring the `/jj-burndown <board>` trigger, orchestrator-only scope, and the requirement of the `jj-concurrent` plugin plus a configured Linear MCP server.
- [x] 1.2 Document that the skill is part of the `jj-concurrent-linear` plugin (third skill alongside the `jj-linear-sync` binding) and is absent where the plugin is not enabled.
- [x] 1.3 Add a pre-flight check: abort the run with a clear message if the Linear MCP server is unreachable, before any worker is dispatched.

## 2. Board query and queue construction

- [x] 2.1 Implement board-argument resolution: resolve `<board>` to a single Linear board by name or id; on ambiguous/no match, report the failure and dispatch nothing.
- [x] 2.2 Query the resolved board for issues in the `ready-for-agent` state (triage-labels convention); exclude all other states.
- [x] 2.3 Order the candidate set by the stable key (board position, then priority, then issue identifier) so dispatch order is deterministic and re-queryable.

## 3. Bounded sliding-window drain

- [x] 3.1 Read the concurrency cap (default 3, configurable override) and document the override surface in the SKILL.md.
- [x] 3.2 Implement the dispatch loop: fill the window up to `cap`, then on each landing pull-and-dispatch the next ready issue; never exceed `cap` in flight; never fan out the whole board at once.
- [x] 3.3 Track per-run dispatched/completed issue ids keyed by workspace path so slots and identity are unambiguous.

## 4. Per-issue dispatch via jj-delegate

- [x] 4.1 For each pulled issue, dispatch exactly one `jj-delegate` worker in its own workspace, in the background by default, passing the issue body/spec as the worker's workload.
- [x] 4.2 Ensure the skill issues no `jj workspace`, bookmark, push, or rebase commands itself — all jj/workspace choreography goes through `jj-delegate`.
- [x] 4.3 Confirm one-issue-to-one-worker mapping (no bundling of multiple issues into a single worker).

## 5. Per-issue landing update

- [x] 5.1 On a worker report, detect whether the `jj-linear-sync` (C2) binding is enabled.
- [x] 5.2 When `jj-linear-sync` is enabled, defer the per-issue transition to its report-to-Linear mapping (do not redefine the mapping).
- [x] 5.3 When absent, apply a minimal inline update: in-progress → done on a clean report (`blocked_on` null, no conflicts); post a comment with the blocker/conflict text and hold (not done) on a blocked/conflicted report; flag degraded mode in the readout.
- [x] 5.4 Leave an issue untouched when its worker stalls without a report (resume-in-place); only a successor report drives the next update.

## 6. Readout and termination

- [x] 6.1 Emit a running summary on each window advance with queue-remaining, in-flight, done, and blocked counts.
- [x] 6.2 Re-query the board as the queue drains so newly-labelled `ready-for-agent` issues are picked up mid-run; make dispatch idempotent per issue so a re-queried in-flight/completed issue is never re-dispatched.
- [x] 6.3 Terminate when a re-query returns no `ready-for-agent` issues and no workers are in flight; emit the final summary.

## 7. Composition notes and cross-references

- [x] 7.1 Cross-reference `jj-delegate` (orchestrator/worker split, concurrent-sibling provisioning, background dispatch) and `jj-linear-sync` (report → Linear mapping) from the SKILL.md without restating their contracts.
- [x] 7.2 Note composition with C1 (umbrella/sub-issues consumed, not produced) and the graceful flat-board fallback when C1 is absent.
- [x] 7.3 Validate the change with `openspec validate jj-linear-burndown` and confirm the spec/scenarios parse.
