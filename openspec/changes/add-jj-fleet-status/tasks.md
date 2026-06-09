## 1. Scaffold the skill

- [ ] 1.1 Create the directory `plugins/jj-concurrent/skills/jj-fleet/` and an empty `SKILL.md`.
- [ ] 1.2 Add SKILL.md frontmatter: `name: jj-fleet`, a description naming the trigger `/jj-fleet` and the orchestrator-only/read-only nature, and `metadata.version`/`author` matching the sibling skills.

## 2. Snapshot-then-read core

- [ ] 2.1 Document the workspace-set resolution: read `.jj-agent-plan.json` where present, else derive from `jj workspace list` (graceful degradation).
- [ ] 2.2 Document the snapshot pass: loop `jj -R <ws> util snapshot` over every live workspace BEFORE any read, with a note that this records only each sibling's own working copy and is non-mutating.
- [ ] 2.3 Document the read pass: `jj log --ignore-working-copy --no-pager` (and `jj workspace list`) to gather change-id, description, conflict flag, and stale flag per workspace.

## 3. Render the fleet view

- [ ] 3.1 Specify the rendered view (one row per workspace): workspace path/name, held change-id + description, conflict flag, stale flag, status (in-flight/done/blocked), and blocker note.
- [ ] 3.2 Specify how each column is sourced: change-id/description/conflict/stale from live jj; status/blocker/workload from the manifest entry joined by workspace path.
- [ ] 3.3 Specify graceful degradation: mark manifest-only columns "unknown" when the manifest is absent or a workspace has no matching entry; never fail.
- [ ] 3.4 Include a concrete example of the rendered output (markdown table) in SKILL.md.
- [ ] 3.5 Surface the stale-fix hint (`jj workspace update-stale` in that workspace) without auto-running it.

## 4. Guardrails and cross-reference

- [ ] 4.1 State the orchestrator-only + strictly read-only contract in SKILL.md: primary workspace only, read-only jj plus `jj util snapshot`, no bookmarks, no push, no raw mutating git, no manifest writes, no new hooks.
- [ ] 4.2 Update jj-delegate's "Situational awareness" paragraph to cross-reference `/jj-fleet` instead of duplicating the snapshot-then-log loop.

## 5. Validate

- [ ] 5.1 Run `openspec validate add-jj-fleet-status` and confirm it passes.
- [ ] 5.2 Confirm the skill loads (frontmatter parses) and the rendered example matches the spec's required columns.
