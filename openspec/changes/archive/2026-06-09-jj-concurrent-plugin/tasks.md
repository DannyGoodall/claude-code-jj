# Tasks — jj-concurrent-plugin

## 1. Marketplace + plugin scaffolding

- [x] 1.1 Create the `claude-code-jj` marketplace manifest with two plugins (`jj-concurrent`, `jj-concurrent-openspec`)
- [x] 1.2 `jj-concurrent` plugin manifest + directory structure (skills/agents/hooks)
- [x] 1.3 `jj-concurrent-openspec` plugin manifest + directory structure (skills)

## 2. jj-delegate (mechanism)

- [x] 2.1 Author the `jj-delegate` skill: parameter resolution, Phase-0 confirm, role split
- [x] 2.2 Provisioning with explicit base revision (`jj workspace add -r <rev>`), seed-intent rule, manifest
- [x] 2.3 Background-by-default dispatch of `jj-workspace-worker` subagents; foreground opt-in
- [x] 2.4 Reconcile + integrate (never-halts), teardown, concurrent-siblings, failure handling (resume-in-place)

## 3. jj-workspace-worker (agent)

- [x] 3.1 Author the agent: workspace containment, jj-only VCS, never bookmarks/push
- [x] 3.2 Commit-per-task-group durability + non-interactive command hygiene
- [x] 3.3 Workflow-skill invocation contract + the structured JSON report format

## 4. jj-safety-hooks

- [x] 4.1 Snapshot hook (`jj-snapshot.sh`, PostToolUse on edits): `jj util snapshot`, fail-open, time-bounded, jj-repo-only
- [x] 4.2 Guard hook (`jj-guard.sh`, PreToolUse on Bash): block raw mutating git, interactive jj, `rm` on `.jj`/`.git`; never invoke jj
- [x] 4.3 `hooks.json` wiring both hooks to the plugin

## 5. jj-openspec-binding

- [x] 5.1 Author the `jj-openspec` skill: verb → shape map (apply/propose/new/ff/explore)
- [x] 5.2 Parameter resolution + handoff to `jj-delegate`; apply bases on the proposal revision
- [x] 5.3 Ship as a separate plugin requiring `jj-concurrent` + opsx skills

## 6. Dependency + docs

- [x] 6.1 Depend on `jj-vcs@toolbox` (unmodified) for jj command vocabulary
- [x] 6.2 README, MANUAL, JJ_OVERVIEW, DESIGN docs
