## Why

There is no quick way to stand up a runnable dev environment from a specific change, commit, or bookmark *before* its work is verified, archived, or merged. Today the only way to eyeball a revision running is to rebase `@` onto it — disturbing your working copy — then start the app by hand on an arbitrary port, with no clean way to supply the gitignored files the app needs and no tidy teardown. The orchestrator already provisions throwaway jj workspaces and assigns a port per worker that runs the app; what is missing is a read-only "just let me look at this revision running" path that reuses that machinery without touching history.

## What Changes

- Add a new **orchestrator-only** skill `/jj-preview <rev>` that provisions a *throwaway* jj workspace at a given commit or bookmark with `jj workspace add -r <rev> ../wt-preview-<slug>`, leaving the working copy `@` and all bookmarks/refs exactly as they were (never rebases `@`).
- The skill copies the gitignored files the app needs (`.env`, local config, etc.) into the preview workspace, **composing with the existing per-workspace-environment worktree-include convention** where that convention is available, rather than inventing a new copy mechanism.
- The skill **assigns a distinct port** to the preview — reusing the design's existing "assign a port per worker that runs the app" convention — so multiple previews and live workers never collide.
- The skill runs the project's dev/app command in the preview workspace and reports the URL + PID back to the operator.
- The skill provides clean **teardown**: `jj workspace forget` plus removing the throwaway directory (never touching the repo `.jj`).
- Strictly a preview: it **never moves bookmarks, never pushes, never archives**, and is **read-only with respect to history**. Orchestrator-only — never invoked inside a worker. Ships as an additive `SKILL.md` in the `jj-concurrent` plugin; no new hooks, no change to the worker report shape.

## Capabilities

### New Capabilities
- `jj-preview`: An orchestrator-only skill that stands up a throwaway, read-only-to-history jj workspace at an arbitrary revision, provisions its per-workspace environment (gitignored-file copy + worktree-include) and a distinct port, runs the project dev/app command, reports URL + PID, and tears the workspace down cleanly — never moving bookmarks, pushing, or archiving.

### Modified Capabilities
<!-- None. The preview reuses jj-delegate's existing workspace provisioning, per-workspace environment, and port-assignment conventions without changing their requirements. -->

## Impact

- New skill file `SKILL.md` under the `jj-concurrent` plugin (additive only).
- Reuses, without modifying, `jj-delegate`'s workspace provisioning (`jj workspace add`/`forget`), per-workspace environment provisioning (gitignored-file copy + worktree-include), and port-per-worker assignment.
- No new hooks. No change to the worker agent or its structured JSON report shape.
- Requires a jj repo (ideally colocated with git). No GitHub, push, or bookmark operations are involved.
