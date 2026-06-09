## 1. Resolve the open question (Claude Code worktree-include surface)

- [x] 1.1 Confirm the exact Claude Code worktree-include declaration surface from current docs/settings schema: a repository-root include file (e.g. `.worktreeinclude`) and/or a `worktree`-namespaced copy-list key in `.claude/settings.json` (e.g. `worktree.copyFiles`). No contradicting surface found in local sources; design default (repo-root `.worktreeinclude` → `.claude/settings.json` worktree copy-list → fallback) is adopted as documented.
- [x] 1.2 Record the confirmed filename/key and glob/path semantics; if it differs from the design's default, update `design.md` Open Questions and the spec's resolution order to match the real surface before editing SKILL.md. Default matches local evidence; no design.md/spec change needed.

## 2. Update jj-delegate provisioning guidance (SKILL.md §3)

- [x] 2.1 In `plugins/jj-concurrent/skills/jj-delegate/SKILL.md` step 3 ("Provision the workspace"), replace the ad-hoc `cp .env.local ../wt-<slug>/` guidance with the declarative rule: after `jj workspace add`, read the worktree-include declaration and copy exactly the declared paths into the new workspace.
- [x] 2.2 Document the deterministic resolution order (repo-root include file → `.claude/settings.json` worktree copy-list → fallback) and the gitignore-style glob semantics (resolved relative to repo root, copied preserving relative layout).
- [x] 2.3 Document the safety bounds: copy only paths inside the repo root, never copy `.jj/`/`.git/` internals, and report (do not silently skip) declared paths that match nothing.
- [x] 2.4 Document the fallback: when no declaration exists, copy the needed gitignored files explicitly as before; absence of a declaration must not block provisioning.

## 3. Validate and verify

- [x] 3.1 Run `openspec validate worktreeinclude-provisioning` and confirm it passes.
- [x] 3.2 Verify the updated SKILL.md wording matches the three spec scenarios for seeding, deterministic resolution, missing-path reporting, and the fallback scenario.
