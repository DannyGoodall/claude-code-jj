# jj-fleet-status Specification

## Purpose
TBD - created by archiving change add-jj-fleet-status. Update Purpose after archive.
## Requirements
### Requirement: Snapshot every live workspace before reading state

The fleet-status skill SHALL refresh every live jj workspace before reading any cross-workspace state. Because jj does not auto-snapshot sibling workspaces, a plain `jj log` can report stale working-copy state for workers still editing. The skill SHALL therefore loop `jj -R <ws> util snapshot` over every live workspace first, THEN read state with `jj log --ignore-working-copy --no-pager`. The snapshot pass SHALL only record each sibling's own working copy and SHALL NOT move revisions, bookmarks, or any worker's commits.

#### Scenario: Stale sibling is refreshed before rendering

- **WHEN** a worker has edited files but not run a jj command since, and the orchestrator runs the fleet-status skill
- **THEN** the skill first runs `jj -R <ws> util snapshot` for that workspace
- **AND** the rendered view reflects the worker's current working-copy change-id and description, not a stale one

#### Scenario: Snapshot pass is non-mutating

- **WHEN** the skill snapshots each live workspace
- **THEN** no bookmark is created or moved, no revision is rebased, and no worker commit is altered

### Requirement: Render a single fleet view

The fleet-status skill SHALL render one consolidated view of all in-flight workers. For each workspace it SHALL show: the workspace path or name, the change-id and description of the change it currently holds, a conflict flag, a stale flag, and an in-flight/done/blocked status. The change-id, description, conflict flag, and stale flag SHALL be derived from live jj state (read-only `jj log` / `jj workspace list`); the status (in-flight/done/blocked) and any blocker text SHALL be read from the agent-plan manifest entry for that workspace where present.

#### Scenario: Each workspace is summarized in one row

- **WHEN** the skill renders the fleet view with three live workspaces
- **THEN** the output shows one row per workspace with its path, held change-id + description, conflict flag, stale flag, and status

#### Scenario: Conflict flag reflects first-class conflicts

- **WHEN** a workspace holds a change that jj records as conflicted
- **THEN** that workspace's row shows the conflict flag set

#### Scenario: Stale flag reflects a stale working copy

- **WHEN** a workspace's working copy is stale (its base was moved by another operation)
- **THEN** that workspace's row shows the stale flag set, indicating `jj workspace update-stale` is the fix

### Requirement: Join status from the agent-plan manifest

The fleet-status skill SHALL discover and read every agent-plan manifest present in the repo — all session-namespaced manifests (`.jj-agent-plan.<session-id>.json`) and the unnamespaced default (`.jj-agent-plan.json`) where present — and join each manifest slice's metadata (status, workload, bookmark, base-rev) onto the matching workspace by path, producing one fleet view that UNIONS every orchestrator session. Each row SHALL be attributable to its owning session. The manifests are owned by their respective jj-delegate orchestrator sessions; the fleet-status skill SHALL treat every manifest as read-only and SHALL NOT write or delete manifest entries.

#### Scenario: Manifest status appears in the view

- **WHEN** a manifest marks a workspace's slice as `blocked` with a blocker note
- **THEN** that workspace's row shows status `blocked` and surfaces the blocker note

#### Scenario: Manifest is treated as read-only

- **WHEN** the skill reads the manifests to render the view
- **THEN** it does not modify, add, or remove any manifest entry in any session's manifest

#### Scenario: View unions multiple orchestrator sessions

- **WHEN** two orchestrator sessions each own a session-namespaced manifest with live slices
- **THEN** the rendered fleet view includes the workspaces from both sessions in one consolidated view
- **AND** each row is attributable to its owning session

### Requirement: Graceful degradation without the manifest

The fleet-status skill SHALL still produce a useful view when no agent-plan manifest is present or when the available manifests only partially cover the live workspaces. In that case it SHALL derive the workspace set from `jj workspace list`, render every flag it can compute from live jj state (change-id, description, conflict, stale), and mark manifest-only fields (status, blocker, workload, owning session) as unknown rather than failing.

#### Scenario: No manifest present

- **WHEN** the skill runs and no `.jj-agent-plan.json` or `.jj-agent-plan.<session-id>.json` file exists
- **THEN** it lists workspaces from `jj workspace list` and renders the live-derived columns, marking status/blocker as unknown

#### Scenario: Workspace missing from every manifest

- **WHEN** a live workspace has no matching entry in any session's manifest
- **THEN** its row still shows live-derived change-id, description, conflict, and stale, with status and owning session marked unknown

### Requirement: Orchestrator-only and strictly read-only

The fleet-status skill SHALL run only in the primary (default) workspace as an orchestrator capability. It SHALL use only read-only jj commands plus `jj util snapshot` (which records only a sibling's own working copy). It SHALL NOT create or move bookmarks, SHALL NOT push, SHALL NOT run raw mutating git, and SHALL NOT alter any worker's commits or the manifest. It introduces no new hooks.

#### Scenario: Read-only invocation from the primary workspace

- **WHEN** the orchestrator invokes the fleet-status skill
- **THEN** it reads jj state and the manifest and renders the view without any bookmark, push, rebase, or manifest write

#### Scenario: No new hooks introduced

- **WHEN** the skill is installed
- **THEN** it adds no hooks and relies only on existing read-only jj behavior

### Requirement: Exclude stale manifests from the fleet view

The fleet-status skill SHALL exclude (or visibly demote) manifests left by dead orchestrators/agents so abandoned state never appears as live in the view, even before the orchestrator's startup sweep removes them. A manifest SHALL be treated as stale when its liveness marker is past the TTL (heartbeat older than the threshold) or it carries an explicit "session ended" marker. The skill SHALL make this exclusion read-only — it SHALL NOT delete or archive any stale manifest; reclamation remains the orchestrator's responsibility.

#### Scenario: Stale manifest is not shown as live

- **WHEN** a session-namespaced manifest's heartbeat is past the liveness TTL
- **THEN** the fleet view does not present that manifest's slices as live in-flight work

#### Scenario: Exclusion is read-only

- **WHEN** the skill detects a stale manifest while rendering
- **THEN** it omits or demotes those entries in the view
- **AND** it does not delete or modify the stale manifest file

