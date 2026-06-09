## Context

The jj-concurrent plugin already defines the orchestrator/worker split (see `openspec/specs/jj-delegate` and `openspec/specs/jj-workspace-worker`). The orchestrator provisions linked jj workspaces, dispatches `jj-workspace-worker` subagents, and owns the gitignored agent-plan manifest `.jj-agent-plan.json` (per-slice: bookmark, workspace, base-rev, status, workload).

Today the orchestrator's cross-workspace situational awareness is a single paragraph in the jj-delegate SKILL.md: "jj does not auto-snapshot sibling workspaces, so loop `jj -R <ws> util snapshot` then `jj log`." This is easy to skip, produces no consistent rendered view, and does not join the manifest's status/blocker metadata onto the live jj state. With multiple concurrent workers this is exactly the moment the orchestrator most needs an accurate fleet picture.

This change promotes that paragraph into a first-class, read-only skill `jj-fleet` (capability `jj-fleet-status`).

## Goals / Non-Goals

**Goals:**
- One command (`/jj-fleet`) that yields an accurate, at-a-glance view of every in-flight worker.
- Correctness over siblings: snapshot first so the view is never stale.
- Join live jj state (change-id, description, conflict, stale) with manifest metadata (status, blocker, workload) in a single rendered table.
- Degrade gracefully: still useful with a missing/partial manifest.
- Strictly read-only and orchestrator-only; no new hooks.

**Non-Goals:**
- Mutating any worker state, integrating/landing changes, or touching bookmarks/push (those remain jj-delegate's job).
- A long-running/live-refreshing dashboard or TUI. This is a single non-interactive render on demand.
- Changing the manifest schema or who owns it (jj-delegate continues to own writes).
- Adding hooks or background processes.

## Decisions

**Decision: Snapshot-then-log, driven by the manifest workspace set.**
The skill loops `jj -R <ws> util snapshot` over each live workspace, then reads once with `jj log --ignore-working-copy --no-pager`. `jj util snapshot` records only the target workspace's own working copy — it does not move revisions or bookmarks — so the refresh pass is safe and non-mutating. Reads use `--ignore-working-copy` so the read pass itself never re-snapshots the primary.
*Alternative considered:* rely on `jj log` alone (rejected: shows stale siblings, the core bug). *Alternative considered:* snapshot only when a worker looks idle (rejected: snapshot is cheap and idempotent; always-snapshot is simpler and always correct).

**Decision: Manifest is the join key by workspace path; live jj is the source of truth for change state.**
Status / blocker / workload come from `.jj-agent-plan.json`; change-id, description, conflict and stale flags come from jj itself. This keeps each field sourced from its authority and means a stale manifest can never misreport conflict/stale.
*Alternative considered:* compute status from jj alone (rejected: in-flight/done/blocked is workflow state the manifest holds; jj cannot know a worker is "blocked").

**Decision: Derive flags from read-only jj surfaces.**
- Conflict flag: from jj log/template conflict indicator on the workspace's `@`.
- Stale flag: from `jj workspace list` / the stale indicator (the fix is `jj workspace update-stale`, surfaced as a hint, never auto-run).
- Change-id + description: from the workspace's working-copy commit via `jj log`.
The SKILL.md specifies the exact read-only templates; this design fixes the sourcing, not the template string.

**Decision: Graceful degradation derives the workspace set from `jj workspace list` when the manifest is absent.**
Live-derivable columns always render; manifest-only columns show "unknown" rather than erroring. This keeps the skill useful for ad-hoc multi-workspace setups not created through jj-delegate.

**Decision: jj-delegate cross-references this skill.**
The existing "Situational awareness" paragraph points at `/jj-fleet` rather than duplicating the loop. (Pointer only — jj-delegate's requirements do not change, so no delta spec for it.)

## Risks / Trade-offs

- [Snapshotting a sibling races a worker mid-write] → `jj util snapshot` is idempotent and records a consistent working-copy state; a subsequent worker jj command simply re-snapshots. Worst case the view is one snapshot behind, never corrupt.
- [Manifest and live state disagree (e.g. manifest says in-flight but the change is conflicted)] → By design both are shown side by side; the divergence is information for the orchestrator, not an error to reconcile.
- [Stale flag misread as failure] → The view labels stale as recoverable and names `jj workspace update-stale` as the fix; the skill never auto-runs it.
- [Skill drifts from jj-delegate's manifest schema] → Skill reads defensively (treat missing keys as unknown) so a manifest field addition does not break it.

## Migration Plan

Additive only: a new skill directory `plugins/jj-concurrent/skills/jj-fleet/SKILL.md`. No schema, hook, or existing-skill behavior changes (jj-delegate gains a one-line cross-reference). Nothing to roll back beyond removing the new file and the cross-reference.

## Open Questions

- Output format: markdown table vs. compact aligned text. Leaning markdown table for readability; the SKILL.md will pick one and show an example. Non-blocking for the spec.
