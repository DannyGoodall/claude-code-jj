---
name: jj-checkpoint
description: |
  Record a named, op-log-based save point before a risky orchestration step (a
  fan-out integration, a large history rewrite). Captures the current
  operation id under a human-supplied <label> in the agent-plan manifest so
  /jj-rewind [label] can roll the whole repo back via `jj op restore`;
  recording itself is read-only with respect to history. Triggers: /jj-
  checkpoint, "checkpoint before this rebase", "record a save point", "label
  this op". Requires a jj repo; orchestrator-only.
metadata:
  version: "0.1.0"
  author: outfitter-style
---

# jj-checkpoint — name an op-log save point before a risky step

You are the **orchestrator**, working in the **primary (default) jj workspace**.
`/jj-checkpoint <label>` records a **named save point** just before a
deliberately risky step — a §5 fan-out integration that rebases several workers'
changes onto trunk, or a large history rewrite — so a later `/jj-rewind [label]`
can return the whole repo to exactly this point.

A checkpoint captures the repository's **current operation id** (read from
`jj op log`) under your `<label>` and stores it in the orchestrator's agent-plan
manifest. `jj op restore <op-id>` is the exact inverse, so the op id is all
`/jj-rewind` needs. The companion rollback skill is
[`/jj-rewind`](../jj-rewind/SKILL.md).

Substrate knowledge (jj command surface, non-interactive rules, output formats)
comes from the installed `jj-vcs` skill — defer to it for jj command detail;
this skill owns only the checkpoint-recording choreography.

## Preconditions (verify, don't assume)

- **Orchestrator role only.** Checkpoints live in the agent-plan manifest, which
  the orchestrator owns. NEVER invoke `/jj-checkpoint` inside a worker. It runs
  in the primary/default workspace.
- **Operation log is the substrate.** This skill operates on the whole-repo
  operation log via `jj op log` (read only). Every jj repo has one; no remote,
  no `gh`, no application code involved.
- **Strictly read-only with respect to history.** Recording a checkpoint runs
  `jj op log` to *read* the current op id and writes only the manifest record.
  It MUST NOT create, abandon, rebase, or restore any operation — so taking a
  checkpoint can never itself become the thing that needs undoing.
- **Op-log only, never deletes repo metadata.** Uses `jj op log` exclusively;
  never deletes `.jj` (or any repository metadata), never runs raw mutating git,
  never touches bookmarks or push. Non-interactive jj only (`--no-pager`, no
  editor, no `-i`/`--interactive`).

## Arguments

```
/jj-checkpoint <label> [note...]
```

- **`<label>`** (required, non-empty) — a stable handle for this save point
  (e.g. `pre-fanout-integration`). Used later as `/jj-rewind <label>`.
- **`[note...]`** (optional) — free-text note recorded alongside the checkpoint
  (e.g. "before rebasing auth+billing onto trunk").

## 1. Validate the label (fail fast, record nothing on failure)

A label is a required, non-empty handle:

- **Empty or missing label** → report that a non-empty label is required and
  **record nothing**. Do not invent a label, do not fall through to capture.

## 2. Resolve the current op id (read-only)

Capture the **absolute** operation id at `@` — not a relative ref like `@-`,
which would drift as new ops land and no longer point where intended:

```bash
jj op log --no-pager --limit 1 -T 'id ++ "\n"' --no-graph
```

The first (top) entry is the current operation. Capture its full op id verbatim;
store the absolute id, never a relative offset. This is a pure read — it mutates
nothing.

## 3. Handle label reuse non-destructively

Before writing, check the manifest's `checkpoints` for an existing record under
`<label>`:

- **Label is new** → proceed to §4 and append the record.
- **Label already exists** → do **NOT** silently overwrite the prior op id (an
  earlier save point must never be lost to a typo). Either:
  - **refuse** with a clear message — report the existing record (its op id and
    timestamp) and suggest a different label; or
  - **update in place only on explicit confirmation** — state that `<label>`
    already points at `<old-op-id>` (recorded `<timestamp>`) and ask the
    orchestrator to confirm replacing it with the current op id before writing.

Never replace an existing label's op id without an explicit go-ahead.

## 4. Persist the checkpoint record (manifest write only)

Write the record into the agent-plan manifest's `checkpoints` section — the same
`.jj-agent-plan.json` at the repo root that [`/jj-delegate`](../jj-delegate/SKILL.md)
owns. This is the **only** side effect of a checkpoint.

- If `.jj-agent-plan.json` does not yet exist, create it with a `checkpoints`
  array (the manifest gains an optional `checkpoints` section the first time
  `/jj-checkpoint` runs). If it exists without a `checkpoints` key, add one
  without disturbing the existing slice entries.
- Append (or, on confirmed reuse, replace) one record:

  ```json
  {
    "label": "pre-fanout-integration",
    "op_id": "<absolute op id from §2>",
    "timestamp": "<ISO-8601 time of recording>",
    "note": "before rebasing auth+billing onto trunk"
  }
  ```

  `note` is optional; omit or leave empty when no note was given.

Read the manifest defensively (a schema addition elsewhere must not break this),
and write back only the `checkpoints` change — never rewrite or drop the slice
entries the manifest already carries.

## 5. Confirm recording stayed read-only

Before reporting success, confirm that **no history-mutating jj command ran**
during this checkpoint: only `jj op log` (read) and a manifest file write
occurred. The repository's working copy, bookmarks, and commits are unchanged;
the sole effect is the new checkpoint record. (You can sanity-check that the op
id at `@` is unchanged from what you captured in §2.)

## 6. Report

Return a compact result:

```
checkpoint: pre-fanout-integration
op id:      <absolute op id>
recorded:   <timestamp>
note:       before rebasing auth+billing onto trunk
```

Then point at the rollback verb: roll the whole repo back to this point with
`/jj-rewind pre-fanout-integration` (or bare `/jj-rewind` while this is the most
recent checkpoint).

## Guardrails — orchestrator-only, read-only-to-history

- **Primary workspace only.** Orchestrator capability; never inside a worker.
- **Read-only to history.** Only `jj op log` (read) + a manifest write. No
  `jj op restore`, no rebase, no abandon, no `jj new`/`describe` during a
  checkpoint — recording must never be the thing that needs undoing.
- **Op-log only.** Never delete `.jj` or any repo metadata; never run raw
  mutating git; never touch bookmarks or push.
- **Non-interactive jj only.** `--no-pager`; no editor; no `-i`/`--interactive`.
- **Manifest is the only store.** No new external/dedicated checkpoint file;
  records ride in the orchestrator-owned `.jj-agent-plan.json`.

## Where this is called

`/jj-checkpoint` is the **before-a-risky-step** beat of the reconcile lifecycle:

- [`jj-delegate`](../jj-delegate/SKILL.md) §5 invokes `/jj-checkpoint <label>`
  immediately before a fan-out integration or a large rebase; if that step goes
  wrong, [`/jj-rewind`](../jj-rewind/SKILL.md) `[label]` rolls back to here.
