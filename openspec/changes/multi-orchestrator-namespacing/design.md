## Context

The jj-concurrent plugin family (`jj-delegate` orchestrator, `jj-fleet` status, `jj-workspace-worker`, plus `jj-checkpoint`/`jj-rewind` which record op-log checkpoints) coordinates background workers through a single shared agent-plan manifest at the repo root: `.jj-agent-plan.json`. The orchestrator owns this file (writes slices, status, blockers, checkpoints); `jj-fleet` reads it; workers never touch it.

This design assumes one orchestrator per repo. The failure modes when a second orchestrator session runs concurrently:

1. **Manifest clobber.** Both sessions write the same `.jj-agent-plan.json`. The last writer wins; the other session's slices vanish, so `/jj-fleet` shows a corrupted or merged view and reconcile decisions are made against stale data.
2. **Name contention.** Workspace dirs are conventionally `../wt-<slug>` and bookmarks `<slug>` derived from the workload. Two orchestrators delegating similar workloads pick the same `../wt-auth` dir or the same bookmark, and the second `jj workspace add` / bookmark op fails or, worse, attaches to the other session's workspace.
3. **No reclamation.** A dead/abandoned orchestrator leaves its manifest (and its workspaces) behind. Nothing sweeps them, so the file lingers and pollutes any future fleet view.

The orchestrator process already has a stable session identifier available (the agent/session id). This design uses it as the namespacing discriminator.

## Goals / Non-Goals

**Goals:**
- Each orchestrator session owns a private manifest file that no other session can clobber.
- `/jj-fleet` presents one view spanning every concurrent orchestrator, with per-session attribution.
- Workspace dirs and bookmark names never collide across concurrent orchestrators.
- Manifests (and the awareness of state) left by dead orchestrators/agents are swept or ignored, never accumulated, never shown as live.
- A single lone orchestrator behaves exactly as it does today (no required prefix, default manifest path still valid).

**Non-Goals:**
- No cross-orchestrator coordination of *work* (no shared queue, no leader election, no locking the repo). Sessions remain independent; only their state files are isolated.
- No change to worker behaviour or the worker JSON report contract.
- No change to push/PR/ref ownership rules — the orchestrator still owns all refs.
- No automatic teardown of another live orchestrator's workspaces (cleanup targets only state proven stale).
- No implementation in this change — proposal/authoring shape only.

## Decisions

### Decision 1: Session-id in the manifest filename, not a single file with a sessions map

Namespace the manifest by filename: `.jj-agent-plan.<session-id>.json`. Each orchestrator reads/writes only its own file.

- **Why over a single shared file with an internal `sessions: {}` map:** a single file reintroduces the clobber problem — concurrent read-modify-write on one JSON file is exactly the race we are removing. Separate files make writes conflict-free at the filesystem level (each session touches only its own path) and make stale-cleanup a simple per-file decision.
- **Session id source:** the orchestrator's own session/agent id, slugified to a filesystem- and ref-safe token (lowercase alphanumeric + dashes, bounded length). Deterministic per session so resume re-attaches to the same manifest.

### Decision 2: Back-compat via a default unnamespaced path

When no session id is resolvable, or for an existing repo that already has a plain `.jj-agent-plan.json`, the orchestrator uses the unnamespaced default path and unprefixed names — identical to today. Namespacing engages when a session id is present. `/jj-fleet`'s union includes the default file, so a single-session repo renders exactly as before.

- **Why:** zero migration; the common single-orchestrator case is unchanged. The discriminator is additive.

### Decision 3: Per-orchestrator name prefix derived from the session id

Workspace dirs become `../wt-<session-prefix>-<slug>` and bookmarks `<session-prefix>/<slug>` (or `<session-prefix>-<slug>`), where `<session-prefix>` is a short stable token derived from the session id. The single-session default omits the prefix.

- **Why a derived prefix over random suffixes:** the prefix is stable across resume (same session → same names), human-legible in `jj workspace list` and `gh pr list`, and groups one orchestrator's artifacts together. A random suffix per workspace would defeat resume-in-place and scatter names.
- **Why bookmarks too, not just dirs:** bookmark contention is a hard failure on integration; prefixing removes it. The orchestrator still owns all ref mutation, so prefixing is purely a naming policy on its side.

### Decision 4: Liveness marker + sweep, conservative by default

Each manifest carries a liveness marker: the owning session id and a heartbeat timestamp the orchestrator refreshes as it operates. Staleness is decided by TTL (heartbeat older than a threshold) and/or an explicit "session ended" marker.

- **Startup sweep:** on orchestrator start, scan sibling `.jj-agent-plan.*.json` files; any past TTL with no live owner is eligible for cleanup (archive/remove the manifest; its workspaces are left for inspection unless explicitly reclaimed).
- **Fleet exclusion:** `/jj-fleet` excludes (or visibly demotes) manifests that are past TTL so abandoned state never appears as live, even before a sweep runs.
- **Why TTL + marker over killing on sight:** an orchestrator that is merely idle (not dead) must not have its manifest reclaimed mid-flight. The conservative rule — only sweep what is provably stale (past TTL, no heartbeat) and never delete another session's manifest while it appears live — protects in-flight work. Cleanup never touches worker commits or refs.

### Decision 5: Cleanup ownership stays orchestrator-only

The sweep and TTL logic live in the orchestrator (`jj-delegate`) and the read-side exclusion in `jj-fleet`. `jj-fleet` stays strictly read-only — it excludes stale manifests from the view but never deletes them; deletion/archival is the orchestrator's startup sweep.

- **Why:** preserves the existing invariant that `/jj-fleet` is non-mutating, and keeps state mutation in the single role that already owns the manifest.

## Risks / Trade-offs

- **Stale TTL too aggressive could reclaim a live-but-idle orchestrator's manifest** → make TTL generous and require both past-TTL *and* no fresh heartbeat; never sweep a manifest whose owner still appears live; leave workspaces intact (resume-in-place still works) rather than destroying them.
- **Session id not available or unstable across resume** → fall back to the unnamespaced default path (back-compat branch); document that resume must reuse the same session id to re-attach to the same manifest and prefixed names.
- **Union view performance with many manifests** → manifests are small JSON; the sweep keeps their count bounded, so unioning a handful of files per fleet render is cheap.
- **Two orchestrators still share one object store and trunk** → out of scope by design (Non-Goals); they integrate independently and may produce divergent bookmarks, which is acceptable because names no longer collide.
- **Mixed old/new manifests during rollout** → the default-path back-compat branch means a plain `.jj-agent-plan.json` is always still readable and writable, so a repo can carry both forms without breakage.

## Migration Plan

No data migration. The default unnamespaced manifest path remains valid, so existing single-session repos need no action. New behaviour is additive: namespacing and prefixes engage only when a session id is present; the sweep only acts on provably stale manifests. Rollback is removing the namespacing branch — the default path keeps working.

## Open Questions

- Exact TTL/heartbeat threshold and whether the heartbeat is a manifest field vs. a separate liveness file.
- Whether the startup sweep should *archive* stale manifests (move aside) rather than delete, to aid post-mortem.
- Whether to optionally reclaim a dead orchestrator's *workspaces* (not just its manifest) during the sweep, or always leave them for manual inspection.
- Bookmark prefix separator (`/` vs `-`) given remote ref and `gh` constraints.
