## Why

When several jj-workspace-workers run concurrently, the orchestrator has no single view of the fleet: a plain `jj log` shows stale state because jj does not auto-snapshot sibling workspaces, and the agent-plan manifest (`.jj-agent-plan.json`) holds status/blocker/workload metadata that the log alone cannot show. Today this lives as one easily-skipped "Situational awareness" paragraph in jj-delegate, so the orchestrator reasons about in-flight work from stale or partial data.

## What Changes

- Add a new orchestrator-only skill `jj-fleet` (trigger `/jj-fleet`) under `plugins/jj-concurrent/skills/jj-fleet/SKILL.md` that renders a single at-a-glance fleet view of all in-flight workers.
- The skill SHALL refresh every live workspace before reading state: loop `jj -R <ws> util snapshot` over the manifest's workspaces first, THEN read with `jj log --ignore-working-copy --no-pager` — so the view reflects current working-copy state, not stale siblings.
- The rendered view SHALL show, per workspace: the workspace path/name, the change-id and description it holds, conflict and stale flags, and in-flight/done/blocked status, joining the manifest's per-slice metadata onto the live jj state.
- The skill SHALL degrade gracefully when the manifest is absent or partial (derive workspaces from `jj workspace list`; show flags it can compute, mark manifest-only fields unknown).
- The skill is strictly read-only: it runs in the primary workspace, uses only read-only jj commands plus `jj util snapshot` (which only records the sibling's own working copy), and SHALL NOT touch bookmarks, push, or mutate any worker's commits.
- No new hooks. The existing jj-delegate "Situational awareness" paragraph is promoted into this first-class skill (jj-delegate may reference it).

## Capabilities

### New Capabilities
- `jj-fleet-status`: An orchestrator-only fleet status view that snapshots every live jj workspace, then renders each workspace's held change-id + description, conflict/stale flags, and in-flight/done/blocked status, joining live jj state with the agent-plan manifest and degrading gracefully when the manifest is absent.

### Modified Capabilities
<!-- None. jj-delegate and jj-workspace-worker specs are referenced for role context but their requirements do not change. -->

## Impact

- New skill file: `plugins/jj-concurrent/skills/jj-fleet/SKILL.md`.
- Reads (does not write) the gitignored `.jj-agent-plan.json` manifest owned by jj-delegate.
- Reads jj state via read-only commands only; no new hooks, no changes to the guard/snapshot hooks.
- Cross-reference only: jj-delegate's "Situational awareness" paragraph points at this skill.
