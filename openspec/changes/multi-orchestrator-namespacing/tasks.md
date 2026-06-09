## 1. Session identity and manifest namespacing

- [ ] 1.1 Resolve a stable, filesystem- and ref-safe session id token for the orchestrator (slugified session identity, bounded length), deterministic across resume
- [ ] 1.2 Compute the manifest path `.jj-agent-plan.<session-id>.json`, falling back to the unnamespaced `.jj-agent-plan.json` when no session id is resolvable
- [ ] 1.3 Route all orchestrator manifest reads/writes (slices, status, blockers, checkpoints) through the resolved per-session path
- [ ] 1.4 Add a liveness marker to the manifest schema (owning session id + heartbeat timestamp) and refresh the heartbeat as the orchestrator operates

## 2. Per-orchestrator workspace and bookmark naming

- [ ] 2.1 Derive a stable per-session prefix from the session id (reproduced on resume)
- [ ] 2.2 Apply the prefix to workspace directory names (`../wt-<session-prefix>-<slug>`) when a session id is present
- [ ] 2.3 Apply the prefix to bookmark names (`<session-prefix>-<slug>`) when a session id is present
- [ ] 2.4 Preserve unprefixed workspace/bookmark names in the back-compat single-orchestrator (no session id) path

## 3. Stale-state cleanup (orchestrator)

- [ ] 3.1 Implement a startup sweep that scans sibling `.jj-agent-plan.*.json` manifests
- [ ] 3.2 Implement the liveness/TTL check (heartbeat past threshold and/or explicit "session ended" marker, no live owner) to classify a manifest as stale
- [ ] 3.3 Remove or archive provably stale manifests, leaving live sessions' manifests and all worker commits untouched
- [ ] 3.4 Guarantee the sweep never reclaims a manifest whose owner still appears live (fresh heartbeat within TTL), even if idle

## 4. Union fleet view (jj-fleet)

- [ ] 4.1 Discover all manifests in the repo: every `.jj-agent-plan.<session-id>.json` plus the default `.jj-agent-plan.json`
- [ ] 4.2 Union the manifests' slices and join onto live workspaces by path, with per-session attribution on each row
- [ ] 4.3 Apply the read-only staleness exclusion: omit or visibly demote slices from manifests past the TTL or marked session-ended (never delete a manifest)
- [ ] 4.4 Preserve graceful degradation: derive the workspace set from `jj workspace list` and mark manifest-only fields (status, blocker, workload, owning session) as unknown when no/partial manifest coverage exists

## 5. Back-compat and verification

- [ ] 5.1 Confirm a lone single-orchestrator session (no session id) reads/writes the default manifest path and uses unprefixed names, identical to prior behaviour
- [ ] 5.2 Confirm an existing repo carrying a plain `.jj-agent-plan.json` works without migration
- [ ] 5.3 Verify two concurrent orchestrators produce non-colliding manifests, workspace dirs, and bookmarks, and that `/jj-fleet` unions both sessions
- [ ] 5.4 Verify a stale manifest from a dead orchestrator is excluded from the fleet view and swept on next startup, with worker commits untouched
- [ ] 5.5 Run `openspec validate multi-orchestrator-namespacing` and resolve any issues
