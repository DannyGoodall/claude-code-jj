## Why

When `jj-delegate` provisions a worker workspace, `jj workspace add` carries
only tracked (committed/snapshotted) content. The gitignored files a workload
actually needs to run — env files (`.env.local`), local config, credentials —
are not carried, so the SKILL.md tells the orchestrator to copy them by hand:
`cp .env.local ../wt-<slug>/`. This ad-hoc, per-file copy is manual, easy to
forget or get wrong, and does not scale to the real set of files a workspace
needs to build the app or run its tests. A worker that silently lacks an env
file fails in confusing ways far from the provisioning step.

Claude Code already solves exactly this problem when it commissions a git
worktree: it copies a declared set of gitignored files into the new worktree.
`jj-delegate` should honour that same declarative convention instead of
re-inventing an inferior manual one.

## What Changes

- Replace the ad-hoc `cp <file> ../wt-<slug>/` guidance in the `jj-delegate`
  provisioning step with a declarative rule: after `jj workspace add`, read the
  repository's worktree-include declaration and copy exactly the paths it lists
  into the new workspace.
- Define the include declaration's resolution order (which file/setting is
  authoritative) and matching semantics (gitignore-style path globs, resolved
  relative to the repo root, copied preserving relative layout).
- Specify graceful fallback: when no include declaration is present, fall back
  to the current explicit-copy behaviour so existing flows do not regress.
- Specify safety bounds: only copy paths that exist and are inside the repo
  root; never copy `.jj/` or `.git/` internals; report (do not silently skip)
  declared paths that are missing.
- Record an explicit OPEN QUESTION (in design.md) about the precise Claude Code
  declaration surface, with a sensible default, to be confirmed at apply time.

This change is proposal/spec-only: it defines the behaviour requirement for the
`jj-delegate` provisioning step. It does NOT edit plugin source, README,
MANUAL, or ROADMAP.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `jj-delegate`: the workspace-provisioning behaviour gains a requirement that
  gitignored workload files be seeded into a new worker workspace from a
  declarative worktree-include list (mirroring Claude Code's worktree file-copy
  convention), with deterministic resolution order, safety bounds, and fallback
  to the prior explicit-copy behaviour when no declaration exists.

## Impact

- **Spec**: `openspec/specs/jj-delegate/spec.md` — adds one requirement and
  amends the provisioning guidance.
- **Plugin source (downstream, NOT in this change)**: §3 ("Provision the
  workspace") of `plugins/jj-concurrent/skills/jj-delegate/SKILL.md` will later
  be updated to instruct the orchestrator to read the include list and copy
  those paths, with the documented fallback.
- **Dependencies**: none new. Relies only on the orchestrator's existing shell
  access (`cp`) and read access to a repo-root include file or
  `.claude/settings.json`.
- **Risk**: the exact Claude Code declaration surface is not unambiguously
  pinned from local sources; the design records this as an open question with a
  default and requires confirmation before implementation.
