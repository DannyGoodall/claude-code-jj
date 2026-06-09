## Why

The jj-concurrent orchestrator assumes exactly one orchestrator session per repo. Two concurrent orchestrators both write the single shared `.jj-agent-plan.json` manifest (last-write-wins clobber), so `/jj-fleet` renders a corrupted or merged view; they can also collide on workspace directory names (`../wt-auth`) and bookmark names. Nothing reclaims manifests or state left by a dead or abandoned orchestrator/agent, so stale files accumulate and pollute the fleet view. As soon as a second human or scheduled session runs the orchestrator against the same repo, in-flight work is silently lost.

## What Changes

- **Per-session manifest namespacing.** The agent-plan manifest is keyed to the orchestrator session — `.jj-agent-plan.<session-id>.json` — so each orchestrator owns its own file and no write clobbers another session's slices.
- **Union fleet view.** `/jj-fleet` discovers and unions every per-session manifest in the repo (plus the default unnamespaced file for back-compat) so a single fleet view spans all concurrent orchestrators, attributing each slice to its owning session.
- **Per-orchestrator name prefixes.** Workspace directory names (`../wt-…`) and bookmark names are prefixed/derived from the session id so two orchestrators never contend for the same workspace dir or bookmark.
- **Stale-state cleanup.** A startup sweep plus a liveness/TTL check removes or ignores manifests left by dead orchestrators/agents, so abandoned files neither accumulate nor pollute the fleet view. Cleanup never touches a live session's manifest or any worker's commits.
- **Back-compat default.** A lone orchestrator behaves exactly as today: the unnamespaced `.jj-agent-plan.json` path and unprefixed workspace/bookmark names remain valid for the common single-session case; namespacing engages only when a session id is present or contention is detected.

This is a proposal only — no plugin source, README, MANUAL, or ROADMAP is changed here.

## Capabilities

### New Capabilities
- (none)

### Modified Capabilities
- `jj-delegate`: the orchestrator's manifest ownership becomes per-session (namespaced manifest path), workspace-dir and bookmark naming gain per-orchestrator prefixes to avoid cross-orchestrator collisions, and teardown/failure handling gains a stale-manifest cleanup sweep with a liveness/TTL check; single-orchestrator default behaviour is preserved.
- `jj-fleet-status`: the manifest join becomes a union over all per-session manifests (not a single `.jj-agent-plan.json`), with per-session attribution, graceful degradation preserved, and stale/abandoned manifests excluded from the rendered view.

## Impact

- Affected capabilities/specs: `jj-delegate`, `jj-fleet-status` (delta specs in this change).
- Affected plugin skills (implementation, out of scope for this proposal): `jj-delegate`, `jj-fleet`, and any orchestrator skill that reads or writes the agent-plan manifest (`jj-checkpoint`/`jj-rewind` record checkpoints in the manifest).
- Manifest schema/path: a session-id discriminator in the manifest filename and a liveness marker (e.g. heartbeat timestamp / owning session id) inside each manifest.
- Back-compat: existing single-session repos with a plain `.jj-agent-plan.json` continue to work unchanged; no migration required.
- No database, API, or external dependency impact.
