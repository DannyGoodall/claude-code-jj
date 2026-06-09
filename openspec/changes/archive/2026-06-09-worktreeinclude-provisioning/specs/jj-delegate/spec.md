## ADDED Requirements

### Requirement: Seed gitignored workload files from the worktree-include declaration

The orchestrator SHALL, after provisioning a worker workspace with `jj workspace add`, seed the gitignored files the workload needs by reading the repository's declarative worktree-include list — the same convention Claude Code uses to copy selected gitignored files into a newly commissioned git worktree — and copying exactly the paths it declares into the new workspace. The orchestrator SHALL NOT copy gitignored files ad hoc on a per-file basis when such a declaration exists.

Resolution SHALL be deterministic and follow this order, using the first source
present:
1. a repository-root worktree-include file (gitignore-style, newline-separated
   path globs), then
2. the worktree copy-list key in `.claude/settings.json`.

Each declared entry SHALL be interpreted as a path glob resolved relative to the
repository root, and matched files SHALL be copied into the new workspace
preserving their path relative to the repository root.

The orchestrator SHALL apply the following safety bounds:
- only copy paths that resolve inside the repository root (never escape it);
- never copy version-control internals (`.jj/`, `.git/`);
- report any declared path that matches nothing, rather than silently skipping
  it, so a missing required input is visible at provisioning time.

#### Scenario: Declared gitignored files are seeded into the new workspace

- **WHEN** the orchestrator provisions a worker workspace and a worktree-include
  declaration lists gitignored paths the workload needs (e.g. `.env.local`)
- **THEN** the orchestrator reads that declaration once and copies exactly the
  declared paths into the new workspace, preserving their relative layout
- **AND** it does not issue ad-hoc per-file copies outside the declaration

#### Scenario: Resolution order is deterministic

- **WHEN** both a repository-root worktree-include file and a worktree copy-list
  key in `.claude/settings.json` are present
- **THEN** the orchestrator uses the repository-root include file as the
  authoritative source and does not also apply the settings copy-list

#### Scenario: A declared but missing path is reported, not silently dropped

- **WHEN** the worktree-include declaration lists a path that matches no file in
  the repository
- **THEN** the orchestrator reports the missing declared path at provisioning
  time rather than silently continuing

### Requirement: Fallback to explicit copy when no include declaration exists

The orchestrator SHALL, when the repository has no worktree-include declaration (neither a repository-root include file nor a worktree copy-list in `.claude/settings.json`), fall back to the prior behaviour of copying the specific gitignored files the workload needs explicitly (e.g. `cp .env.local <workspace-path>/`). The absence of a declaration SHALL NOT block provisioning and SHALL NOT regress existing flows.

#### Scenario: No declaration present

- **WHEN** the orchestrator provisions a worker workspace in a repository with no
  worktree-include declaration
- **THEN** provisioning proceeds and the orchestrator copies the needed gitignored
  files explicitly, as before, without error
