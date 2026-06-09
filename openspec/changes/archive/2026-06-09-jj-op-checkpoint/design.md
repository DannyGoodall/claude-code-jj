## Context

jj records every repository mutation as an operation in the operation log; `jj op log` lists them and `jj op restore <op-id>` returns the whole repo (all workspaces, bookmarks, working copies) to the state at that operation. This is jj's killer recovery primitive and the `jj-delegate` skill already names it as the orchestrator's last-resort recovery surface ("a jj command itself hangs → `jj op log`/`jj op restore` is the recovery surface, orchestrator-only").

Today that surface is reached only reactively, after damage, by eyeballing raw op ids under pressure. The orchestrator runs deliberately risky steps — fan-out integration that rebases several workers' changes onto trunk (§5 of jj-delegate), or a large history rewrite — with no labelled save point to return to. This change makes the op log a *labelled* workflow: name a save point before the risky step, roll back to it by name if needed.

The orchestrator already owns an agent-plan manifest (workspace/bookmark bookkeeping). Checkpoint records ride alongside it, so no new store is introduced.

## Goals / Non-Goals

**Goals:**
- Two orchestrator-only skills, `/jj-checkpoint <label>` and `/jj-rewind [label]`, that wrap `jj op log` (read) and `jj op restore` (rollback) as a named save-point workflow.
- Recording a checkpoint is read-only with respect to history — it only remembers the current op id.
- Rewinding always prints a confirmation summary (what gets undone, which workspaces/bookmarks are affected) and requires explicit confirmation before restoring.
- Persist checkpoint records (label → op id → timestamp → note) alongside the existing agent-plan manifest so they survive across steps in a session.
- Slot cleanly into the jj-delegate reconcile lifecycle as the before/after-a-risky-step beats.

**Non-Goals:**
- No new rollback mechanism — `jj op restore` is the only rollback path; we never delete `.jj`, never raw-git-reset, never touch bookmarks/refs/push (orchestrator ref contract is unchanged).
- Not a replacement for per-workspace `jj workspace update-stale` or for resolving conflicts; this is whole-repo time-travel, not surgical edit.
- No cross-session durability guarantees beyond what the manifest already provides; not an external/remote checkpoint store.
- No automatic checkpointing — the orchestrator decides when a step is risky; this change supplies the verbs, and the lifecycle prose suggests where.

## Decisions

**Decision: Capture the op id, not a tag or a commit.**
A checkpoint stores the op id resolved from `jj op log` at record time. `jj op restore <op-id>` is the exact inverse. Alternatives considered: (a) bookmark/tag the working-copy commit — rejected: that only captures one revision, not the whole-repo state (other workspaces, abandoned commits, the op graph), and bookmarks are the orchestrator's ref surface we must not casually spend; (b) `jj op restore @-` style relative refs — rejected: relative offsets drift as new ops land, so a label recorded before a multi-op fan-out would no longer point where intended. An absolute op id is stable.

**Decision: Recording is strictly read-only.**
`/jj-checkpoint` runs `jj op log` to read the current op id and writes only the manifest record. It deliberately does NOT run any history-mutating op, so taking a checkpoint can never itself be the thing that needs undoing. This keeps the mental model clean: checkpoints are free and side-effect-free.

**Decision: Store records in the agent-plan manifest, not a new file format.**
The orchestrator already owns and reads/writes the manifest each step. A `checkpoints` section (list of {label, op_id, timestamp, note}) reuses that ownership and lifecycle. Alternative: a dedicated `.jj-checkpoints` file — rejected as an extra artifact to manage, snapshot, and clean up; the manifest is already the orchestrator's session memory.

**Decision: Rewind is confirmation-gated and summary-first.**
`jj op restore` is a whole-repo undo affecting every live workspace, so `/jj-rewind` resolves the label → op id, diffs `jj op log` from the captured op to `@` to enumerate the operations that will be undone, lists affected workspaces/bookmarks, prints that summary, and only restores after explicit confirmation. Alternative: restore immediately for speed — rejected: the blast radius (sibling workspaces a worker is still building on) is exactly what an orchestrator must weigh first.

**Decision: Bare `/jj-rewind` targets the latest checkpoint; named targets that label.**
The common case is "undo the thing I just guarded," so a label-less rewind picks the most recent record. Naming is for reaching back past intervening checkpoints. Unknown labels are reported with the available list, never guessed.

**Decision: Reversibility is inherent — no special "redo".**
`jj op restore` is itself recorded as a new operation, so a rewind can be rewound by restoring to the pre-rewind op. We surface that op id in the rewind summary rather than building a separate redo verb.

**Decision: Label reuse is non-destructive.**
A second `/jj-checkpoint <same-label>` does not silently overwrite the prior op id; it refuses or updates only on explicit confirmation, so an earlier save point is never lost by a typo.

## Risks / Trade-offs

- **Op log gets pruned/garbage-collected before a rewind** → a stored op id could become unreachable. Mitigation: document that `jj op log` retention is finite; checkpoints are session-scoped recovery aids, not long-term archives; `/jj-rewind` reports clearly if the op id no longer resolves rather than failing opaquely.
- **Rewinding undoes a live sibling worker's in-flight work** (whole-repo blast radius) → Mitigation: the mandatory confirmation summary enumerates affected workspaces/bookmarks so the orchestrator sees the collateral before confirming; default messaging warns that restore is repo-wide, not scoped to one workspace.
- **Stale working copies after a restore** → restoring can leave other workspaces stale. Mitigation: note in the skill that `jj workspace update-stale` is the follow-up in affected workspaces, consistent with existing jj-delegate guidance.
- **Manifest and op log drift apart** (manifest edited/lost) → a checkpoint record could reference an op the orchestrator can't contextualize. Mitigation: `/jj-rewind` re-resolves and re-summarizes from live `jj op log` at rewind time rather than trusting only the stored note.

## Migration Plan

Additive only. Two new skill folders under `plugins/jj-concurrent/skills/`, a version bump and description tweak to the plugin manifest, and a documentation beat added to the `jj-delegate` reconcile lifecycle pointing at the new verbs. No data migration; existing manifests gain an optional `checkpoints` section the first time `/jj-checkpoint` runs. Rollback of this change is removal of the two skill folders and the doc beat — nothing stateful to unwind.

## Open Questions

- Manifest schema detail: exact key/shape of the `checkpoints` section (deferred to apply; must align with the manifest format jj-delegate already uses).
- Whether `/jj-rewind` should offer to auto-`update-stale` affected sibling workspaces after a restore, or only report them (leaning: report only, keep the verb single-purpose).
- Whether to expose a `/jj-checkpoint --list` (or a thin list affordance) for inspecting recorded checkpoints, or rely on reading the manifest directly.
