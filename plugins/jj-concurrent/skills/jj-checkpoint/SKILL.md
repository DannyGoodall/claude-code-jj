---
name: jj-checkpoint
description: |
  Op-log save points for risky orchestration steps, in two verbs.
  `/jj-checkpoint <label>` records the current operation id under a label in
  the agent-plan manifest, read-only with respect to history;
  `/jj-checkpoint rewind [label]` rolls the whole repo back to a checkpoint
  (bare rewind: the most recent) via `jj op restore` after a confirmation
  summary of the operations undone and affected workspaces/bookmarks — and is
  itself reversible. Triggers: /jj-checkpoint, "checkpoint before this
  rebase", "undo back to the checkpoint", "roll back that rebase". Requires a
  jj repo (rewind: at least one recorded checkpoint); orchestrator-only.
metadata:
  version: "0.2.0"
  author: outfitter-style
---

# jj-checkpoint — op-log save points: record + rewind

You are the **orchestrator**, working in the **primary (default) jj workspace**.
This skill is the op-log safety net around a deliberately risky step — a §5
fan-out integration that rebases several workers' changes onto trunk, or a
large history rewrite — in two verbs:

- **Record** — `/jj-checkpoint <label>` captures the repository's **current
  operation id** (read from `jj op log`) under your `<label>` and stores it in
  the orchestrator's agent-plan manifest.
- **Rewind** — `/jj-checkpoint rewind [label]` returns the **whole repository**
  — every workspace, bookmark, and working copy — to the operation that was
  current when a checkpoint was recorded, via `jj op restore <op-id>`.

`jj op restore <op-id>` is the exact inverse of "everything since `<op-id>`",
so the op id is all a rewind needs. Because a restore is a **whole-repo undo**,
not a per-workspace edit, the rewind verb is **summary-first and
confirmation-gated**: it shows what the restore will change before touching
anything.

Shared contract: [jj-delegate §Roles & shared conventions](../jj-delegate/SKILL.md)
— orchestrator-only, non-interactive jj; defer to the installed `jj-vcs`
skill for jj command detail;
this skill owns only the checkpoint record/rewind choreography.

## Preconditions (verify, don't assume)

- **Orchestrator role only.** Checkpoints live in the agent-plan manifest,
  which the orchestrator owns, and a whole-repo restore affects every live
  workspace and the bookmarks the orchestrator owns. NEVER invoke
  `/jj-checkpoint` (either verb) inside a worker. It runs in the
  primary/default workspace.
- **Operation log is the substrate.** Both verbs operate on the whole-repo
  operation log; every jj repo has one. No remote, no `gh`, no application code
  involved.
- **Recording is strictly read-only with respect to history.** It runs
  `jj op log` to *read* the current op id and writes only the manifest record.
  It MUST NOT create, abandon, rebase, or restore any operation — so taking a
  checkpoint can never itself become the thing that needs undoing.
- **Rewinding needs at least one checkpoint.** Records live in the manifest's
  `checkpoints` section (written by the record verb). With none, there is
  nothing to rewind to — report that and stop.
- **Op-log only.** `jj op log` to read, `jj op restore` as the **sole**
  rollback path; never touch bookmarks or push directly (the shared contract
  covers the `.jj`-deletion and raw-git bans).

## Arguments

```
/jj-checkpoint <label> [note...]     # record verb
/jj-checkpoint rewind [label]        # rewind verb
```

- **`<label>`** (record: required, non-empty) — a stable handle for this save
  point (e.g. `pre-fanout-integration`). Used later as
  `/jj-checkpoint rewind <label>`.
- **`[note...]`** (record: optional) — free-text note recorded alongside the
  checkpoint (e.g. "before rebasing auth+billing onto trunk").
- **`rewind [label]`** — the rollback verb. With a label, targets that named
  checkpoint; bare, targets the **most recently recorded** checkpoint (the
  common "undo the thing I just guarded" case).

## The record verb

### R1. Validate the label (fail fast, record nothing on failure)

A label is a required, non-empty handle:

- **Empty or missing label** → report that a non-empty label is required and
  **record nothing**. Do not invent a label, do not fall through to capture.

### R2. Resolve the current op id (read-only)

Capture the **absolute** operation id at `@` — not a relative ref like `@-`,
which would drift as new ops land and no longer point where intended:

```bash
jj op log --no-pager --limit 1 -T 'id ++ "\n"' --no-graph
```

The first (top) entry is the current operation. Capture its full op id verbatim;
store the absolute id, never a relative offset. This is a pure read — it mutates
nothing.

### R3. Handle label reuse non-destructively

Before writing, check the manifest's `checkpoints` for an existing record under
`<label>`:

- **Label is new** → proceed to R4 and append the record.
- **Label already exists** → do **NOT** silently overwrite the prior op id (an
  earlier save point must never be lost to a typo). Either:
  - **refuse** with a clear message — report the existing record (its op id and
    timestamp) and suggest a different label; or
  - **update in place only on explicit confirmation** — state that `<label>`
    already points at `<old-op-id>` (recorded `<timestamp>`) and ask the
    orchestrator to confirm replacing it with the current op id before writing.

Never replace an existing label's op id without an explicit go-ahead.

### R4. Persist the checkpoint record (manifest write only)

Write the record into the agent-plan manifest's `checkpoints` section — the same
`.jj-agent-plan.json` at the repo root that [`/jj-delegate`](../jj-delegate/SKILL.md)
owns. This is the **only** side effect of a checkpoint.

- If `.jj-agent-plan.json` does not yet exist, create it with a `checkpoints`
  array (the manifest gains an optional `checkpoints` section the first time
  the record verb runs). If it exists without a `checkpoints` key, add one
  without disturbing the existing slice entries.
- Append (or, on confirmed reuse, replace) one record:

  ```json
  {
    "label": "pre-fanout-integration",
    "op_id": "<absolute op id from R2>",
    "timestamp": "<ISO-8601 time of recording>",
    "note": "before rebasing auth+billing onto trunk"
  }
  ```

  `note` is optional; omit or leave empty when no note was given.

Read the manifest defensively (a schema addition elsewhere must not break this),
and write back only the `checkpoints` change — never rewrite or drop the slice
entries the manifest already carries.

### R5. Report

Return a compact result:

```
checkpoint: pre-fanout-integration
op id:      <absolute op id>
recorded:   <timestamp>
note:       before rebasing auth+billing onto trunk
```

Then point at the rollback verb: roll the whole repo back to this point with
`/jj-checkpoint rewind pre-fanout-integration` (or bare `/jj-checkpoint rewind`
while this is the most recent checkpoint).

## The rewind verb

### W1. Resolve the target checkpoint

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

### W2. Verify the stored op id still resolves (graceful, not opaque)

The op log retention is finite; a stored op id can be pruned/garbage-collected
between checkpoint and rewind. Confirm it still resolves before promising a
restore:

```bash
jj op log --no-pager -T 'id ++ "\n"' --no-graph | grep -F '<stored-op-id>'
```

- **Resolves** → proceed to the summary (W3).
- **Does not resolve** (pruned/GC'd) → report **clearly** that the checkpoint's
  op id is no longer in the operation log (checkpoints are session-scoped
  recovery aids, not long-term archives) rather than failing opaquely on the
  restore. Run no restore.

### W3. Build the confirmation summary (before any restore)

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

#### Flag live sibling workspaces (cross-workspace blast radius)

`jj op restore` is repo-wide, not scoped to one workspace. If the operations
being undone include work that **other live workspaces** depend on (a sibling
worker still building on a revision the restore rolls back), **flag those
workspaces explicitly** in the summary so the orchestrator can weigh the
collateral before confirming. Default messaging must make clear the restore is
**repo-wide**, not limited to the primary workspace.

### W4. Gate on explicit confirmation

Print the W3 summary, then **require explicit confirmation** before running any
restore. Do not restore for speed — the blast radius (sibling workspaces a worker
is still building on) is exactly what the orchestrator must weigh first. If
confirmation is not given, run no restore and stop.

### W5. Restore via `jj op restore` only

On confirmation, perform the rollback with `jj op restore` **and nothing else**
— no `.jj` deletion, no raw git, no bookmark/push ops:

```bash
jj op restore <stored-op-id> --no-pager
```

This returns the whole repo (all workspaces, bookmarks, working copies) to the
state at the captured op.

### W6. Surface the post-restore op id (the rewind is itself reversible)

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

### W7. Note the stale-workspace follow-up

A whole-repo restore can leave **sibling workspaces stale** (their working-copy
base moved underneath them). This skill does **not** auto-fix them (it stays
single-purpose). Surface the follow-up as a hint, consistent with existing
jj-delegate/jj-fleet guidance:

> Affected sibling workspaces may now be stale — fix each with
> `jj -R <ws> workspace update-stale` (or `cd <ws> && jj workspace update-stale`).
> This skill does not run it for you.

## Rewind failure modes (each reported, none improvised)

- **Unknown label** → report it + list available checkpoints; no restore (W1).
- **No checkpoints recorded** → nothing to rewind to; stop (W1).
- **Stored op id pruned/GC'd** → clear "op no longer in the log" message, not an
  opaque restore failure; no restore (W2).
- **Confirmation withheld** → no restore; stop (W4).
- **A jj command itself hangs** → do not retry blindly and NEVER delete `.jj`;
  the op log itself is the recovery surface — report the hang and stop.

## Where this is called

The two verbs are the **before/after-a-risky-step** beats of the reconcile
lifecycle:

- [`jj-delegate`](../jj-delegate/SKILL.md) §5 invokes `/jj-checkpoint <label>`
  immediately before a fan-out integration or a large rebase; if that step goes
  wrong, `/jj-checkpoint rewind [label]` rolls back to it — the labelled form
  of jj-delegate's existing `jj op log`/`jj op restore` recovery surface.
