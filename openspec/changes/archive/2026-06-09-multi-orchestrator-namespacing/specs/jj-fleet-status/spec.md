## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: Exclude stale manifests from the fleet view

The fleet-status skill SHALL exclude (or visibly demote) manifests left by dead orchestrators/agents so abandoned state never appears as live in the view, even before the orchestrator's startup sweep removes them. A manifest SHALL be treated as stale when its liveness marker is past the TTL (heartbeat older than the threshold) or it carries an explicit "session ended" marker. The skill SHALL make this exclusion read-only — it SHALL NOT delete or archive any stale manifest; reclamation remains the orchestrator's responsibility.

#### Scenario: Stale manifest is not shown as live

- **WHEN** a session-namespaced manifest's heartbeat is past the liveness TTL
- **THEN** the fleet view does not present that manifest's slices as live in-flight work

#### Scenario: Exclusion is read-only

- **WHEN** the skill detects a stale manifest while rendering
- **THEN** it omits or demotes those entries in the view
- **AND** it does not delete or modify the stale manifest file
