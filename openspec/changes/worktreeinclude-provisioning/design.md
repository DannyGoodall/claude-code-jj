## Context

`jj-delegate` provisions a worker workspace with `jj workspace add -r <base-rev>
<path>` (see the existing "Workspace provisioning with explicit base revision"
requirement). That carries tracked/snapshotted content but not gitignored files.
Step 3 of `plugins/jj-concurrent/skills/jj-delegate/SKILL.md` currently papers
over the gap with ad-hoc guidance: "copy gitignored env files the workload needs
(`cp .env.local ../wt-<slug>/` etc.)". This is manual, per-file, easy to forget,
and does not scale to the real set of files (multiple env files, local config,
service credentials) a workspace needs to build the app or run integration tests.

Claude Code already faces the identical problem when it commissions a git
worktree and solves it declaratively: it copies a configured set of gitignored
files into the newly created worktree. The opportunity is to honour that same
convention from `jj-delegate` rather than maintaining an inferior bespoke
mechanism. Evidence in the local Claude Code changelog confirms the mechanism
exists (entries on "worktree file copy", `worktree.*` settings, and
`WorktreeCreate` hooks that copy gitignored/in-progress files), but does not
unambiguously pin the exact declaration filename/key — captured below as an open
question.

This change is proposal/spec-only. It defines the behaviour requirement on the
`jj-delegate` capability; the SKILL.md edit is downstream work under apply.

## Goals / Non-Goals

**Goals:**
- Replace ad-hoc per-file `cp` provisioning with a single declarative read of the
  repository's worktree-include list, copying exactly the declared paths.
- Reuse Claude Code's existing worktree-include convention rather than inventing a
  jj-specific one, so a repo configures gitignored-file seeding once for both
  git-worktree and jj-workspace provisioning.
- Define deterministic resolution order, glob/path semantics, safety bounds, and a
  no-regression fallback.

**Non-Goals:**
- Editing plugin source, README, MANUAL, or ROADMAP (downstream of this proposal).
- Changing the base-revision provisioning requirement (`jj workspace add -r`).
- Designing a brand-new include format. We adopt Claude Code's real format; if it
  turns out to differ from the default below, implementation conforms to the real
  one.
- Copying tracked files (already carried by `jj workspace add`) or secrets
  management beyond a plain file copy.

## Decisions

**Decision: Read a declarative include list once, instead of ad-hoc per-file cp.**
The provisioning step resolves one include source and copies every path it
matches. Rationale: declarative + idempotent, scales to N files, makes the
"what does a workspace need" answer live in one tracked place rather than in
prose. Alternative considered: keep per-file `cp` but enumerate files in the
manifest — rejected, it duplicates a convention the repo already has for git
worktrees and drifts from it.

**Decision: Deterministic resolution order — repo-root include file, then
`.claude/settings.json` worktree copy-list, then fallback.** First source present
wins; no merging across sources, to keep behaviour predictable. Rationale: a
single authoritative source avoids surprising union semantics. Alternative: merge
all sources — rejected as harder to reason about and to debug a stray copy.

**Decision: gitignore-style path globs resolved from the repo root, copied
preserving relative layout.** Mirrors how gitignore/worktree-copy lists are
already authored, so users reuse mental models. Nested paths (e.g.
`config/local.env`) land at the same relative path in the workspace.

**Decision: Safety bounds enforced.** Only copy paths inside the repo root; never
copy `.jj/`/`.git/` internals; report (not silently skip) a declared path that
matches nothing. Rationale: a missing `.env.local` should surface at provisioning,
not as a confusing downstream runtime failure; and copying VCS internals would
corrupt the workspace.

**Decision: Graceful fallback preserves current behaviour.** When no declaration
exists, the orchestrator copies the needed gitignored files explicitly as today.
Rationale: zero regression for repos that have not adopted the convention.

## Risks / Trade-offs

- [The exact Claude Code declaration surface is not pinned from local sources] →
  Design against the real format; record it as an open question (below) with a
  sensible default; require confirmation at apply time before editing SKILL.md.
- [Over-broad globs could copy large/unwanted gitignored trees into every worker
  workspace] → Keep semantics to explicit gitignore-style entries the repo author
  chooses; do not auto-include all gitignored files; document that the list is
  curated.
- [Copying secrets into multiple workspaces widens their on-disk footprint] →
  Same exposure as today's manual `cp` and as Claude Code's own git-worktree copy;
  out of scope to change here, but note it.
- [A declared path missing at provisioning] → Reported, not silently skipped, so
  the operator notices before dispatching the worker.

## Migration Plan

Spec-only; no runtime migration. Downstream (under `/opsx:apply`):
1. Confirm the real Claude Code worktree-include surface (file name and/or
   settings key) — resolve the open question.
2. Edit step 3 of `jj-delegate` SKILL.md to read that declaration and copy the
   declared paths, with the documented resolution order, safety bounds, and
   fallback.
3. No rollback concern: absence of a declaration falls back to prior behaviour, so
   the change is backward compatible.

## Open Questions

**OPEN QUESTION (must be resolved before implementation): What is the exact
filename/format of Claude Code's worktree-include convention?**

Local evidence (Claude Code changelog) confirms the *mechanism* — Claude Code
copies gitignored files into newly created worktrees, exposes `worktree.*`
settings, and runs `WorktreeCreate` hooks — but does not unambiguously name the
declaration surface. Two candidates:
- (a) a dedicated repository-root include file (e.g. a `.worktreeinclude` file of
  newline-separated gitignore-style path globs); or
- (b) a `worktree`-namespaced copy-list key in `.claude/settings.json` (e.g. a
  `worktree.copyFiles`-style glob array).

**Sensible default adopted by this spec until confirmed:** prefer a repository-root
worktree-include file (gitignore-style globs) if present; else the
`.claude/settings.json` worktree copy-list; else fall back to explicit `cp`.
Implementation MUST verify the actual Claude Code surface (current docs/settings
schema) and conform the SKILL.md wording to whatever it really is; if it differs
from the default, the resolution order and key names in the spec are updated to
match before the SKILL.md edit lands.
