## 1. Plugin packaging & skill scaffolding

- [x] 1.1 Add the `jj-from-linear` skill under `plugins/jj-concurrent-linear/skills/jj-from-linear/SKILL.md`, alongside the outbound binding skill in the same opt-in plugin (no new marketplace entry beyond the one the `jj-concurrent-linear` change already introduces).
- [x] 1.2 Declare frontmatter: the hard requirement on the `jj-concurrent` plugin and a configured Linear MCP, the optional reach to the `jj-openspec` binding, and triggers (`/jj-from-linear <issue>`, "dispatch a worker from this Linear issue").
- [x] 1.3 State in the skill that it owns no jj/workspace choreography (that is `jj-delegate`'s) and no OpenSpec artifact rules (those are the opsx skills'); it only resolves the issue, picks the workload form, derives the bookmark, records identity, and hands off.

## 2. Issue resolution & input handling

- [x] 2.1 Accept a single Linear issue identifier (e.g. `PTS-18`) or issue URL as the command argument and resolve it through the Linear MCP.
- [x] 2.2 Fail closed before any provisioning when the Linear MCP is unreachable or the issue identifier does not resolve — report the failure, provision no workspace and no bookmark, dispatch no worker.
- [x] 2.3 Enforce single-issue scope: produce exactly one workload and one bookmark per invocation; do not fan out across an umbrella's sub-issues.

## 3. Issue body → workload mapping

- [x] 3.1 Define the change-reference detection rule: a recognised marker (e.g. an `OpenSpec:`/`opsx:` line, an `openspec/changes/<name>` path, or a fenced change identifier) naming a change that resolves to a real `openspec/changes/<name>/` directory.
- [x] 3.2 When a reference resolves, compose the opsx shape over that change as the workload (a skill invocation the worker runs, e.g. `/opsx:apply <name>`), handed to `jj-delegate` directly or via `jj-openspec` where enabled.
- [x] 3.3 When no reference resolves, compose a slice-spec workload whose brief is the issue title and description.
- [x] 3.4 Enforce precedence: referenced-change form wins over slice-spec form when both could apply.
- [x] 3.5 Fail closed on an unresolved change reference (named change has no real directory): stop and surface it; do not fall back to slice-spec and do not author a new change.

## 4. Bookmark derivation

- [x] 4.1 Implement the deterministic issue-id → bookmark-name function: identifier lowercased and kebab-normalised (e.g. `PTS-18` → `pts-18`), optionally under a stable configured prefix (e.g. `linear/`).
- [x] 4.2 Ensure the derivation is pure, so re-dispatch and resume-in-place for the same issue derive the identical bookmark name.
- [x] 4.3 Supply the derived name to the orchestrator for it to create/move; the binding never creates or moves the bookmark itself.

## 5. Issue identity threading & link-back

- [x] 5.1 Keep the worker Linear-agnostic: no Linear identifier in the worker brief or the worker's JSON report, and no Linear MCP in the worker's tool surface.
- [x] 5.2 Record `{ issueId, issueUrl }` in the orchestrator's agent-plan manifest keyed by the worker's workspace path (the same stable key the outbound binding uses), additively and without depending on the outbound `jj-linear-sync` mapping.
- [x] 5.3 Document that the issue identity reaches the PR/change link-back via the issue-derived bookmark name and the manifest record, and that opening the PR / any Linear status update is NOT this binding's job.

## 6. Documentation

- [x] 6.1 Document the two workload forms, the precedence rule, and the fail-closed behaviours (unresolved reference; unreachable MCP) as the single source of truth in the skill.
- [x] 6.2 Note the relationship to the inbound/outbound split: this binding is the Linear→worker direction, complementary to and independent of the outbound `jj-linear-sync` (worker report → Linear) direction; cross-reference the `linear-github-sync` umbrella+sub-issue convention.
