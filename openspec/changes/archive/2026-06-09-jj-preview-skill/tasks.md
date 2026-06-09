## 1. Skill scaffold (additive, orchestrator-only)

- [x] 1.1 Create `SKILL.md` for `/jj-preview` under the `jj-concurrent` plugin's skills directory (additive only; no new hook, no marketplace-plugin change, no change to the worker report shape).
- [x] 1.2 Write the skill frontmatter and triggers: `/jj-preview`, "preview this change running", "stand up a dev env at <rev>", "let me look at <rev> running"; state it is orchestrator-only (never invoked inside a worker) and requires a jj repo (ideally colocated).
- [x] 1.3 Document the contract banner: strictly a preview — never moves bookmarks, never pushes, never archives; read-only with respect to history; `@` and all refs left undisturbed.

## 2. Argument resolution

- [x] 2.1 Accept exactly one revision argument (commit id / change id / bookmark) and resolve it with read-only jj (`--no-pager`).
- [x] 2.2 On an unresolvable or ambiguous revision, report the resolution failure naming the revision and provision nothing.
- [x] 2.3 Derive a `<slug>` from the revision/bookmark for the preview directory name `../wt-preview-<slug>`.

## 3. Provision the throwaway preview workspace

- [x] 3.1 Provision with `jj workspace add -r <rev> ../wt-preview-<slug>` (non-interactive); never rebase `@`, never move a bookmark.
- [x] 3.2 Verify `@` and all bookmarks/refs are unchanged after provisioning (read-only check).

## 4. Per-workspace environment provisioning

- [x] 4.1 Copy the gitignored files the app needs (`.env`, local config) into the preview workspace, reusing the orchestrator's existing per-workspace-environment provisioning.
- [x] 4.2 Compose with the project's worktree-include convention when present; fall back to the known gitignored-file copy when no convention is declared.

## 5. Port assignment and run

- [x] 5.1 Assign a distinct port via the existing "assign a port per worker that runs the app" convention so the preview never collides with a live worker app or another concurrent preview.
- [x] 5.2 Run the project's dev/app command in the preview workspace on the assigned port.
- [x] 5.3 Report the preview URL (host + assigned port) and the process PID to the operator.
- [x] 5.4 On dev/app command start failure, report the failure (no URL) and leave the workspace available for inspection or teardown.

## 6. Teardown

- [x] 6.1 Stop the running preview process.
- [x] 6.2 Run `jj workspace forget` for the preview workspace and remove the `../wt-preview-<slug>` directory; never delete or mutate anything under `.jj`/`.git`.
- [x] 6.3 Make teardown idempotent (tolerate an already-stopped process / already-removed directory).

## 7. Validation

- [x] 7.1 Run `openspec validate jj-preview-skill` and confirm it passes.
