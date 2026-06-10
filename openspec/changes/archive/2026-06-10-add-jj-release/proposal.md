## Why

Cutting a GitHub release is a recurring, error-prone, manual chore — pick a version, lay down a tag, write notes, decide pre-release, publish — and there is no skill in the plugin family that streamlines it. The reconcile tail today ends at `/jj-land`: work gets merged, but shipping a release is left to the human. This change adds the missing "ship a milestone" step as a reusable skill that works for **any** project shape, and ships it in a way that release-only users can adopt without taking on the concurrency or OpenSpec machinery.

## What Changes

- **New skill `/jj-release`** — a relay-shaped (prepare → human go/no-go gate → publish) skill that cuts a GitHub release for the repository at a single commit. v1 scope:
  - **Tag-only versioning** — the git tag *is* the version; the skill never edits manifest files. Tag format `vMAJOR.MINOR.PATCH`.
  - **SemVer bump auto-proposed** from conventional-commit prefixes since the last tag (`feat`→minor, `fix`→patch, breaking/`!`→major), but the human **always** confirms/overrides. On a first release (no prior tag), no default is assumed — the user is asked outright.
  - **Release notes generated** from commits/PRs since the last tag, **editable in-conversation** before the gate; optional GitHub **draft** release as a rendered-preview/safety net.
  - **0.x defaults `--prerelease` ON** (plugin policy reflecting SemVer "0.x is unstable"; overridable at the gate).
  - **CI gate** — refuses to release unless required checks on the **target commit** are green (read off commit-level check-runs/status, since the PR is already merged by release time). The user can still release manually outside the plugin.
  - **Refuses on an existing release** for the target tag (tags are immutable) — not create-or-update.
  - **Optional artifacts hook** — an opaque, project-supplied "produce release artifacts" command the skill runs and whose output it uploads. The skill ships **no** build logic; producing artifacts is the repo owner's obligation.
  - **Server-side tag creation** via `gh release create <tag> --target <sha>` — sidesteps jj 0.42's lack of native tag creation and the guard hook that blocks raw `git tag`.
  - **Orchestrator-only, non-interactive substrate** — human input arrives through the relay gate, never an editor or `-i`.
- **New plugin `jj-lifecycle`** — `/jj-release` ships here, decoupled from `jj-concurrent` / `jj-concurrent-openspec` / `jj-concurrent-linear`, so release-only users install just this plugin. Registered in `.claude-plugin/marketplace.json`.
- **Documentation** — a new feature step in the linkstack case-study walkthrough demonstrating `/jj-release` (matching the one-step-per-feature pattern, with Coverage-map / Cheat-sheet rows), and a `MANUAL.md` entry.
- **Deferred follow-up (described, not implemented here)** — a later change to migrate the reconcile-tail skills (`jj-pr`, `jj-land`, `jj-absorb`, `jj-pr-fixup`, `jj-keep-current`, `jj-stacked-pr`) out of `jj-concurrent` into `jj-lifecycle`, establishing the layering `jj-lifecycle` (base) ← `jj-concurrent` (composes it) ← bindings.

Out of scope for v1: monorepo/per-package releases, manifest version bumping, registry publishing (npm/PyPI/crates), building executables, multi-platform build matrices.

## Capabilities

### New Capabilities
- `jj-release`: Cut a GitHub release for the repo at a commit — relay-shaped version/notes/CI-gate/publish flow, tag-only, with an opaque optional artifacts hook — shipped as the first skill of a new `jj-lifecycle` plugin.

### Modified Capabilities
<!-- None. This change introduces a new capability and a new plugin; the deferred migration of existing reconcile-tail skills into jj-lifecycle is a separate future change, not part of this one. -->

## Impact

- **New plugin directory**: `plugins/jj-lifecycle/` with `.claude-plugin/plugin.json` (version `0.1.0`) and a `skills/jj-release/SKILL.md`.
- **`.claude-plugin/marketplace.json`**: a new entry registering `jj-lifecycle`.
- **`docs/case-studies/linkstack-walkthrough.md`**: a new feature step + Coverage-map / Cheat-sheet rows.
- **`MANUAL.md`**: a new entry for `/jj-release`.
- **External dependencies**: relies on `gh` (authenticated, with release-create scope) and read-only `jj`/git; targets a colocated jj↔git repo with an `origin` remote. No new runtime dependencies.
- **No changes to existing plugins' behavior** in this change; the reconcile-tail migration is explicitly deferred.
