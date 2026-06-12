---
name: jj-preview
description: |
  Stand up a throwaway jj workspace at an arbitrary revision so an operator
  can look at it running as a real app — before it is verified, archived, or
  merged — without disturbing the working copy. Provisions with `jj workspace
  add -r <rev>`, reuses the orchestrator's gitignored-file copy for per-
  workspace env, draws a distinct port, runs the project dev/app command,
  reports URL + PID, and tears everything down cleanly. Read-only to history:
  never moves a bookmark, never pushes, never archives. Triggers: /jj-preview,
  "preview this change running", "stand up a dev env at <rev>", "let me look
  at <rev> running". Requires a jj repo; orchestrator-only.
metadata:
  version: "0.1.0"
  author: outfitter-style
---

# jj-preview — stand up a throwaway dev env at a revision, read-only to history

You are the **orchestrator**, working in the **primary (default) jj workspace**.
`/jj-preview <rev>` provisions a *throwaway* jj workspace at a given commit,
change id, or bookmark, populates its environment, assigns it a distinct port,
runs the project's dev/app command, and reports the URL + PID — so an operator
can **look at that revision running** before its work is verified, archived, or
merged. It then tears the preview down cleanly.

This is the inverse of the worker path: workers do mutating work and report
back; a preview only ever *reads* a revision and runs it. It reuses — never
reinvents — [`/jj-delegate`](../jj-delegate/SKILL.md)'s workspace provisioning,
per-workspace environment provisioning (gitignored-file copy + worktree-include
composition), and port-per-worker assignment.

Substrate knowledge (jj command surface, non-interactive rules, output formats)
comes from the installed `jj-vcs` skill — defer to it for jj command detail;
this skill owns only the preview choreography.

## Contract — strictly a preview, read-only to history

> **A preview never moves a bookmark, never pushes, never archives.** It is
> **read-only with respect to history**: the orchestrator's working copy `@` and
> every bookmark/ref are left exactly as they were before invocation. The only
> side effects are creating, then removing, a throwaway `../wt-preview-<slug>`
> workspace directory and running a dev process the operator owns. Nothing under
> `.jj` (or `.git`) is ever deleted or mutated.

## Preconditions (verify, don't assume)

- **Orchestrator role only.** Only the orchestrator owns workspace provisioning
  and teardown (the same ownership rule as `/jj-delegate`). NEVER invoke
  `/jj-preview` inside a worker; a worker never previews. It runs in the
  primary/default workspace.
- **jj repo required.** A jj repository (ideally colocated with git) must be
  present. No remote, no `gh`, no push, no bookmark operation is involved.
- **Read-only to history.** Provisioning uses `jj workspace add -r <rev>`, which
  materialises `<rev>` in its own directory and never rebases `@` or moves a
  bookmark. Use non-interactive jj only (`--no-pager`, no editor, no
  `-i`/`--interactive`).

## Arguments

```
/jj-preview <rev>
```

- **`<rev>`** (required, exactly one) — a single revision to preview: a commit
  id, a change id, or a bookmark name resolvable by jj. More or fewer than one
  revision is out of contract; report and provision nothing.

## 1. Resolve the revision (read-only, fail fast)

Resolve `<rev>` to a single commit with read-only jj before provisioning
anything:

```bash
jj log --no-pager --ignore-working-copy -r <rev> --no-graph -T 'commit_id ++ "\n"'
```

- **Resolves to exactly one commit** → capture the commit id and proceed to §2.
- **Unresolvable or ambiguous** (no match, or `<rev>` resolves to more than one
  commit) → **report the resolution failure naming the revision** and
  **provision nothing**. Do not guess a revision, do not fall through to
  provisioning.

## 2. Derive the preview slug and directory

Derive a filesystem-safe `<slug>` from the revision/bookmark: lowercase,
`[a-z0-9-]` only (collapse any other run to a single `-`), trimmed of
leading/trailing `-`, bounded to a short length. Prefer the bookmark name when
`<rev>` is a bookmark, otherwise a short change/commit id.

The preview directory is **`../wt-preview-<slug>`**. The `preview-` prefix keeps
previews visually distinct from worker workspaces (`../wt-<slug>`) and makes
teardown targeting unambiguous; multiple previews coexist by slug.

## 3. Provision the throwaway preview workspace

Provision at the resolved revision, non-interactively:

```bash
jj workspace add -r <rev> ../wt-preview-<slug>     # -r required; never default
```

- `-r <rev>` is **required** — without it the workspace would base on `@`'s
  parent and miss the target. This **never rebases `@`** and **never creates or
  moves a bookmark** (unlike a worker provision, a preview creates no bookmark —
  it is read-only to history).

After provisioning, **verify history is undisturbed** (read-only check): the
orchestrator's `@` still points at the same commit it did before, and no
bookmark/ref has moved.

```bash
jj log --no-pager --ignore-working-copy -r @ --no-graph -T 'commit_id ++ "\n"'
jj bookmark list --no-pager --ignore-working-copy
```

Confirm `@`'s commit id and the bookmark list match their pre-invocation state.
If anything moved, something other than this skill acted — stop and report; do
not attempt to "fix" history.

## 4. Provision the preview's per-workspace environment

A preview that runs the app needs the same environment a worker that runs the
app needs — so reuse the orchestrator's existing per-workspace-environment
provisioning rather than inventing a preview-only copy list (one mechanism, one
source of truth):

- **Copy the gitignored files the app needs** (`.env`, `.env.local`, local
  config, etc.) into the preview directory, e.g. `cp .env.local
  ../wt-preview-<slug>/` — the same gitignored-file copy `/jj-delegate` does
  when a worker runs the app. These files are not in version control, so the
  fresh workspace will not have them until copied.
- **Compose with the worktree-include convention when present.** If the project
  declares a worktree-include convention for per-workspace environment files,
  compose with it to populate the preview rather than defining a new include
  mechanism. When no convention is declared, **fall back** to the known
  gitignored-file copy above — worktree-include composition is an enhancement
  when present, not a hard dependency.

## 5. Assign a port and run the dev/app command

- **Assign a distinct port** by drawing from the orchestrator's existing "assign
  a port per worker that runs the app" convention, so the preview never collides
  with a live worker app or another concurrent preview. Collisions are the
  obvious failure mode when more than one app runs against shared local
  services; reusing the established allocator avoids a second, conflicting
  scheme.
- **Run the project's dev/app command** inside the preview workspace on the
  assigned port (non-interactive; do not block the session waiting on a
  long-lived dev server — start it so it keeps running and capture its PID).
- **On success** → report to the operator the **preview URL** (host + assigned
  port) and the **process PID**:

  ```
  preview:  http://localhost:<port>
  rev:      <rev>  (commit <commit-id>)
  worktree: ../wt-preview-<slug>
  pid:      <pid>
  teardown: stop pid <pid> → jj workspace forget <name> → rm -rf ../wt-preview-<slug>
  ```

- **On dev/app start failure** → report the failure (its message), report **no
  URL**, and **leave the workspace available** for inspection or teardown. Do
  not silently retry or fabricate a URL.

The preview is a foreground-detached dev process the operator owns until
teardown; this skill is not a process supervisor and starts no long-lived
daemon. The PID is reported precisely so an orphaned preview can always be
killed manually if the session dies before teardown.

## 6. Teardown (mirror of provisioning, idempotent)

Teardown is the mirror of provisioning and must never touch repo metadata:

1. **Stop the running preview process** (by the reported PID). If it is already
   stopped, that is fine.
2. **`jj workspace forget`** the preview workspace — the supported way to drop a
   linked workspace from the repo's view without disturbing the shared object
   store:

   ```bash
   jj workspace forget <preview-workspace-name>    # non-interactive
   ```

3. **Remove the throwaway directory** `../wt-preview-<slug>`.

**Never `rm` anything under `.jj` (or `.git`)** — teardown only ever stops a
process, forgets a linked workspace, and removes the throwaway directory.

**Idempotent.** Teardown tolerates an already-stopped process and an
already-removed directory: a missing process, an already-forgotten workspace, or
an already-deleted directory is a no-op, not an error. Re-running teardown on a
torn-down preview is safe.

## Guardrails — orchestrator-only, read-only-to-history

- **Primary workspace only.** Orchestrator capability; never inside a worker.
  Only the orchestrator owns workspace provisioning and teardown.
- **Read-only to history.** `jj workspace add -r <rev>` only; NEVER rebase `@`,
  NEVER move/create a bookmark, NEVER push, NEVER archive. `@` and all refs are
  left exactly as they were.
- **No repo-metadata deletion.** Teardown stops the process, `jj workspace
  forget`s the preview, and removes the throwaway dir — never `rm` under
  `.jj`/`.git`, never raw mutating git.
- **Non-interactive jj only.** `--no-pager`; reads use `--ignore-working-copy`;
  no editor; no `-i`/`--interactive`.
- **No remote.** No `gh`, no push, no bookmark — a preview never reaches GitHub.
- **Reuse, don't reinvent.** Environment provisioning (gitignored-file copy +
  worktree-include) and port assignment are `/jj-delegate`'s existing
  conventions; the preview draws on them, it does not define new ones.

## Where this is called

`/jj-preview` is the **"just let me look at this revision running"** path
alongside the worker lifecycle:

- It complements [`jj-delegate`](../jj-delegate/SKILL.md): the same provisioning,
  per-workspace environment, and port conventions, used read-only for inspection
  instead of for mutating worker work.
- It is **not** a verification step — running tests / proving the contract
  remains the worker contract and `jj-openspec verify`. A preview is purely
  "let me see it running".
