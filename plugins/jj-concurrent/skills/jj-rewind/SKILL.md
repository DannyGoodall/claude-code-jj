---
name: jj-rewind
description: |
  Roll the whole repository back to a checkpoint's captured operation via `jj
  op restore` — the rollback companion to /jj-checkpoint. Resolves [label]
  (bare: the most recent checkpoint) to its stored op id from the agent-plan
  manifest, prints a confirmation summary (target, operations undone, affected
  workspaces and bookmarks), and restores only after explicit confirmation;
  the restore is itself a new operation, so a rewind is reversible. Triggers:
  /jj-rewind, "undo back to the checkpoint", "roll back that rebase", "restore
  to <label>". Requires a jj repo with at least one recorded checkpoint;
  orchestrator-only.
metadata:
  version: "0.1.0"
  author: outfitter-style
---

# jj-rewind — restore the repo to a named checkpoint

You are the **orchestrator**, working in the **primary (default) jj workspace**.
`/jj-rewind [label]` is the rollback companion to
[`/jj-checkpoint`](../jj-checkpoint/SKILL.md): it returns the **whole repository**
— every workspace, bookmark, and working copy — to the operation that was current
when a checkpoint was recorded, via `jj op restore <op-id>`.

`jj op restore` is a **whole-repo undo**, not a per-workspace edit, so this skill
is **summary-first and confirmation-gated**: it shows what the restore will
change before touching anything.

Shared contract: [jj-delegate §Roles & shared conventions](../jj-delegate/SKILL.md)
— orchestrator-only, non-interactive jj; defer to the installed `jj-vcs`
skill for jj command detail;
this skill owns only the rewind choreography.

## Preconditions (verify, don't assume)

- **Orchestrator role only.** A whole-repo restore affects every live workspace
  and the bookmarks the orchestrator owns. NEVER invoke `/jj-rewind` inside a
  worker. It runs in the primary/default workspace.
- **At least one checkpoint exists.** Records live in the agent-plan manifest's
  `checkpoints` section (written by `/jj-checkpoint`). With no checkpoints, there
  is nothing to rewind to — report that and stop.
- **Op-log only.** Rollback is achieved by `jj op restore` **alone**; never
  touch bookmarks or push directly (the shared contract covers the rest).

## Arguments

```
/jj-rewind [label]
```

- **`[label]`** (optional) — the checkpoint to restore to. When given, targets
  that named checkpoint. When **omitted**, targets the **most recently recorded**
  checkpoint (the common "undo the thing I just guarded" case).

## 1. Resolve the target checkpoint

Read the manifest's `checkpoints` section (`.jj-agent-plan.json` at the repo
root, owned by [`/jj-delegate`](../jj-delegate/SKILL.md)). Read defensively.

- **Label given, record exists** → that checkpoint is the target.
- **No label (bare invocation)** → the **most recently recorded** checkpoint
  (the last appended / latest timestamp) is the target.
- **Label given, no matching record** → report the **unknown label** and **list
  the available checkpoints** (label, op id, timestamp). Run **no** `jj op
  restore` — never guess an op id.
- **No checkpoints at all** → report there is nothing to rewind to; stop.

Take the target's stored **absolute op id** — restore to exactly that op.

## 2. Verify the stored op id still resolves (graceful, not opaque)

The op log retention is finite; a stored op id can be pruned/garbage-collected
between checkpoint and rewind. Confirm it still resolves before promising a
restore:

```bash
jj op log --no-pager -T 'id ++ "\n"' --no-graph | grep -F '<stored-op-id>'
```

- **Resolves** → proceed to the summary (§3).
- **Does not resolve** (pruned/GC'd) → report **clearly** that the checkpoint's
  op id is no longer in the operation log (checkpoints are session-scoped
  recovery aids, not long-term archives) rather than failing opaquely on the
  restore. Run no restore.

## 3. Build the confirmation summary (before any restore)

Enumerate what the restore will change, sourced live from `jj op log` (re-resolve
at rewind time rather than trusting only the stored note):

- **Target checkpoint** — label, op id, timestamp (and note, if any).
- **Operations that will be undone** — those recorded *after* the captured op,
  i.e. the ops between the captured op and `@`:

  ```bash
  # the ops from the captured op (exclusive) up to the current @
  jj op log --no-pager -T 'separate(" ", id.short(), description) ++ "\n"' --no-graph
  ```

  List the operations newer than `<stored-op-id>` — those are exactly what the
  restore undoes.
- **Affected workspaces and bookmarks** — read-only:

  ```bash
  jj workspace list --no-pager
  jj bookmark list --all-remotes --ignore-working-copy --no-pager
  ```

  Note which workspaces and bookmarks change state when the repo returns to the
  captured op.

### Flag live sibling workspaces (cross-workspace blast radius)

`jj op restore` is repo-wide, not scoped to one workspace. If the operations
being undone include work that **other live workspaces** depend on (a sibling
worker still building on a revision the restore rolls back), **flag those
workspaces explicitly** in the summary so the orchestrator can weigh the
collateral before confirming. Default messaging must make clear the restore is
**repo-wide**, not limited to the primary workspace.

## 4. Gate on explicit confirmation

Print the §3 summary, then **require explicit confirmation** before running any
restore. Do not restore for speed — the blast radius (sibling workspaces a worker
is still building on) is exactly what the orchestrator must weigh first. If
confirmation is not given, run no restore and stop.

## 5. Restore via `jj op restore` only

On confirmation, perform the rollback with `jj op restore` **and nothing else**
— no `.jj` deletion, no raw git, no bookmark/push ops:

```bash
jj op restore <stored-op-id> --no-pager
```

This returns the whole repo (all workspaces, bookmarks, working copies) to the
state at the captured op.

## 6. Surface the post-restore op id (the rewind is itself reversible)

`jj op restore` is **itself recorded as a new operation**, so the rewind can be
rewound — there is no separate "redo" verb. Capture and report the new current
op id so the state *prior* to the rewind can be recovered by restoring to it:

```bash
jj op log --no-pager --limit 1 -T 'id ++ "\n"' --no-graph
```

Report the new repo state (the change(s) now at `@`, via
`jj log --ignore-working-copy --no-pager`) and the **pre-rewind op id** to restore
to if this rewind was a mistake:

```
restored to: pre-fanout-integration  (<stored-op-id>)
new op id:    <post-restore op id>
to undo this rewind:  jj op restore <pre-rewind op id> --no-pager
```

## 7. Note the stale-workspace follow-up

A whole-repo restore can leave **sibling workspaces stale** (their working-copy
base moved underneath them). This skill does **not** auto-fix them (it stays
single-purpose). Surface the follow-up as a hint, consistent with existing
jj-delegate/jj-fleet guidance:

> Affected sibling workspaces may now be stale — fix each with
> `jj -R <ws> workspace update-stale` (or `cd <ws> && jj workspace update-stale`).
> This skill does not run it for you.

## Failure modes (each reported, none improvised)

- **Unknown label** → report it + list available checkpoints; no restore (§1).
- **No checkpoints recorded** → nothing to rewind to; stop (§1).
- **Stored op id pruned/GC'd** → clear "op no longer in the log" message, not an
  opaque restore failure; no restore (§2).
- **Confirmation withheld** → no restore; stop (§4).
- **A jj command itself hangs** → do not retry blindly and NEVER delete `.jj`;
  the op log itself is the recovery surface — report the hang and stop.

## Where this is called

`/jj-rewind` is the **undo-a-risky-step** beat of the reconcile lifecycle:

- [`jj-delegate`](../jj-delegate/SKILL.md) §5 invokes `/jj-rewind [label]` to roll
  back a fan-out integration or large rebase that went wrong — the labelled form
  of jj-delegate's existing `jj op log`/`jj op restore` recovery surface.
- Pairs with [`/jj-checkpoint`](../jj-checkpoint/SKILL.md), which records the save
  point this restores to.
