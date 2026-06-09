## 1. Skill scaffolds in core jj-concurrent

- [ ] 1.1 Create `plugins/jj-concurrent/skills/jj-checkpoint/SKILL.md` with frontmatter (name, description, `/jj-checkpoint` trigger) declaring it orchestrator-only, taking a required `<label>` argument and an optional note
- [ ] 1.2 Create `plugins/jj-concurrent/skills/jj-rewind/SKILL.md` with frontmatter (name, description, `/jj-rewind` trigger) declaring it orchestrator-only, taking an optional `[label]` argument
- [ ] 1.3 State preconditions in both skill bodies: orchestrator role only (never a worker), operates on the whole-repo operation log, uses `jj op log`/`jj op restore` only, never deletes `.jj`, never touches bookmarks/push/raw git
- [ ] 1.4 Bump `plugins/jj-concurrent/.claude-plugin/plugin.json` version and extend its description to mention the checkpoint/rewind op-log safety net

## 2. Checkpoint recording (`/jj-checkpoint`)

- [ ] 2.1 Implement current-op-id resolution from `jj op log --no-pager` (capture the absolute op id at `@`)
- [ ] 2.2 Implement the non-empty-label precondition: reject empty/missing label with a clear message and record nothing
- [ ] 2.3 Implement persistence of the checkpoint record (label, op id, timestamp, optional note) in the orchestrator agent-plan manifest's `checkpoints` section
- [ ] 2.4 Implement non-destructive label reuse: refuse or update-on-explicit-confirmation when the label already exists; never silently overwrite a prior op id
- [ ] 2.5 Confirm recording is read-only: no history-mutating jj command runs during a checkpoint

## 3. Rewind resolution + summary (`/jj-rewind`)

- [ ] 3.1 Implement label resolution: named label → its stored record; bare invocation → most recently recorded checkpoint; unknown label → report and list available checkpoints, run no restore
- [ ] 3.2 Implement the confirmation summary: target checkpoint (label, op id, timestamp), the operations that will be undone (diff `jj op log` from captured op to `@`), and affected workspaces/bookmarks
- [ ] 3.3 Flag live sibling workspaces whose work the rewind would undo, so the orchestrator can weigh cross-workspace blast radius
- [ ] 3.4 Gate the restore on explicit confirmation after the summary

## 4. Rewind execution (`/jj-rewind`)

- [ ] 4.1 Implement the restore via `jj op restore <captured-op-id> --no-pager` only (no `.jj` deletion, no raw git, no bookmark/push ops)
- [ ] 4.2 Surface the post-restore op id so the rewind is itself reversible (restore-the-restore), and report the new repo state
- [ ] 4.3 Handle an unresolvable stored op id (pruned/GC'd op log) with a clear message rather than an opaque failure
- [ ] 4.4 Note the `jj workspace update-stale` follow-up for sibling workspaces left stale by the restore

## 5. Reconcile-lifecycle wiring

- [ ] 5.1 Update the `jj-delegate` reconcile/integration prose (§5 fan-out integration / large rebase) to invoke `/jj-checkpoint <label>` before the risky step and `/jj-rewind [label]` to undo it, replacing the hand-scan op-log recovery note
- [ ] 5.2 Cross-reference the new verbs from the jj-delegate failure-handling section as the labelled form of its existing `jj op log`/`jj op restore` recovery surface

## 6. Validation

- [ ] 6.1 Run `openspec validate jj-op-checkpoint` and resolve any structural errors
- [ ] 6.2 Manually exercise against a scratch jj repo: checkpoint → make changes → rewind-by-label and bare-rewind paths; confirm the summary precedes the restore, label reuse is non-destructive, an unknown label is reported, and a rewind is itself reversible
