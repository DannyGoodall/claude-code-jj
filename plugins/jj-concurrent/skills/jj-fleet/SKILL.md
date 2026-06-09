---
name: jj-fleet
description: |
  Render a single at-a-glance fleet status view of all in-flight
  jj-workspace-workers. Snapshots every live jj workspace first (so siblings are
  never stale), then reads jj state read-only and joins the agent-plan manifest's
  per-slice status/blocker/workload onto it. Triggers: /jj-fleet, "show the fleet",
  "fleet status", "what are the workers doing". Orchestrator-only and strictly
  read-only: runs in the primary (default) workspace, uses only read-only jj plus
  `jj util snapshot`, never touches bookmarks, push, raw mutating git, the manifest,
  or any worker's commits. Requires a jj repo with linked workspaces.
metadata:
  version: "0.1.0"
  author: outfitter-style
---

# jj-fleet — at-a-glance fleet status

You are the **orchestrator**, working in the **primary (default) jj workspace**.
`/jj-fleet` renders one consolidated, on-demand view of every in-flight
`jj-workspace-worker`: the change each holds, its conflict/stale flags, and the
workflow status (in-flight / done / blocked) from the agent-plan manifest.

This skill is **strictly read-only**. It exists to *observe* the fleet, never to
change it. Integration, bookmarks, push, and any mutation stay with
[`/jj-delegate`](../jj-delegate/SKILL.md).

## Why this exists

`jj log` does not auto-snapshot sibling workspaces — a worker that has edited
files but not run a jj command since will report a **stale** working-copy commit
in a plain log. And `jj` alone cannot know a worker is *blocked*: that workflow
state lives in the gitignored agent-plan manifest `.jj-agent-plan.json` that
`/jj-delegate` owns. This skill fixes both: snapshot-then-read for correctness,
then join the manifest for workflow status.

## Procedure

Run these passes in order. Everything here is non-mutating.

### 1. Resolve the workspace set

- If `.jj-agent-plan.json` exists, read it and take the workspace set from its
  slice entries (each slice carries `workspace`, `bookmark`, `base-rev`,
  `status`, `workload`/`blocker`). This is the join source for workflow metadata.
- If the manifest is **absent**, derive the workspace set from
  `jj workspace list` instead (graceful degradation — see §5). The view still
  renders; manifest-only columns are marked `unknown`.

Treat the manifest as **read-only**: never write, add, or delete an entry.

### 2. Snapshot pass (BEFORE any read)

Loop over every live workspace and snapshot it first:

```bash
for ws in <workspace paths>; do
  jj -R "$ws" util snapshot
done
```

`jj util snapshot` records **only that workspace's own working copy**. It does
not move revisions, create or move bookmarks, rebase, or alter any worker's
commits — so this pass is safe to run over siblings mid-flight. Worst case the
view is one snapshot behind; it is never corrupt.

Always-snapshot every live workspace (snapshot is cheap and idempotent); do not
try to guess which siblings are idle.

### 3. Read pass (read-only)

After snapshotting, read state without re-snapshotting the primary:

```bash
# Per-workspace held change-id, description, and conflict indicator at @:
jj log --ignore-working-copy --no-pager -r <workspace's @>
# Workspace list + stale indicator:
jj workspace list --no-pager
```

Use `--ignore-working-copy` so the read pass never re-snapshots the primary
workspace. Gather, per workspace:

- **change-id** and **description** of the change it currently holds (its `@`);
- **conflict flag** — from jj's conflict indicator on that workspace's `@`;
- **stale flag** — from `jj workspace list` (a stale working copy whose base was
  moved by another operation).

### 4. Render the fleet view

Render **one row per workspace** as a markdown table with these columns:

| Column | Source |
| --- | --- |
| Workspace | workspace path/name (manifest or `jj workspace list`) |
| Change | held change-id (live jj) |
| Description | held change description (live jj) |
| Conflict | conflict flag (live jj) |
| Stale | stale flag (live jj `workspace list`) |
| Status | in-flight / done / blocked (manifest slice, joined by workspace path) |
| Blocker / Workload | blocker note or workload (manifest slice) |

The **live jj** columns (Change, Description, Conflict, Stale) are always the
source of truth for change state — a stale manifest can never misreport them.
The **manifest** columns (Status, Blocker/Workload) are joined onto the live row
by **workspace path**.

#### Example rendered output

```markdown
## Fleet status — 3 workspaces

| Workspace        | Change   | Description                  | Conflict | Stale | Status    | Blocker / Workload          |
| ---------------- | -------- | ---------------------------- | -------- | ----- | --------- | --------------------------- |
| wt-apply-auth    | qpvuntsm | feat: add login action       | —        | —     | in-flight | /opsx:apply add-auth        |
| wt-apply-billing | zzrlkokm | fix: prorate cancellations   | conflict | —     | blocked   | merge conflict in plan.sql  |
| wt-adhoc-spike   | mlinkrwq | wip: poke at realtime        | —        | stale | unknown   | unknown (no manifest entry) |
```

`jj workspace update-stale` (run **in that workspace**) is the fix for a stale
row — surface it as a hint next to the table; **never auto-run it**:

> `wt-adhoc-spike` is stale — fix with `jj -R <ws> workspace update-stale` (or
> `cd <ws> && jj workspace update-stale`). This skill does not run it for you.

### 5. Graceful degradation

The view must **never fail**; render what you can and mark the rest `unknown`:

- **Manifest absent** → derive workspaces from `jj workspace list`; render the
  live-derived columns (Change, Description, Conflict, Stale); mark Status and
  Blocker/Workload `unknown`.
- **Workspace not in the manifest** → still render its live-derived columns;
  mark Status `unknown` for that row.
- **Manifest field missing on a slice** → treat the missing key as `unknown`
  (read defensively; a manifest schema addition must not break the view).

## Guardrails — orchestrator-only, strictly read-only

- **Primary workspace only.** This is an orchestrator capability; run it from the
  primary (default) workspace, not a worker workspace.
- **Read-only jj only**, plus `jj util snapshot` (which records only a sibling's
  own working copy). Reads use `--ignore-working-copy` and `--no-pager`.
- **No bookmarks.** Never create or move a bookmark.
- **No push.** Never `jj git push`.
- **No raw mutating git.** No `git commit` / `add` / `checkout` / `reset` /
  `rebase` (read-only git is fine, but prefer jj).
- **No manifest writes.** The `.jj-agent-plan.json` manifest is owned by
  `/jj-delegate`; read it, never write/add/delete entries.
- **No new hooks.** This skill relies only on existing read-only jj behavior and
  introduces no hooks or background processes.

If you need to *change* anything in the fleet (integrate, land, unblock, abandon),
that is `/jj-delegate`'s job — not this skill's.
