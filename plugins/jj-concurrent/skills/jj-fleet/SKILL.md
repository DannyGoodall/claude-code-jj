---
name: jj-fleet
description: |
  Render a single at-a-glance status view of all in-flight jj-workspace-
  workers across every concurrent orchestrator session. Snapshots every live
  workspace first, then reads jj state read-only and unions every agent-plan
  manifest in the repo, joining each slice's status/blocker/workload/owning
  session onto its workspace; stale manifests are excluded. Strictly read-only
  — never touches bookmarks, push, manifests, or workers' commits. Triggers:
  /jj-fleet, "show the fleet", "fleet status", "what are the workers doing".
  Requires a jj repo with linked workspaces; orchestrator-only.
metadata:
  version: "0.1.0"
  author: outfitter-style
---

# jj-fleet — at-a-glance fleet status

You are the **orchestrator**, working in the **primary (default) jj workspace**.
`/jj-fleet` renders one consolidated, on-demand view of every in-flight
`jj-workspace-worker` **across every concurrent orchestrator session**: the
change each holds, its conflict/stale flags, the workflow status (in-flight /
done / blocked) from the agent-plan manifests, and the **owning session** each
slice belongs to. Multiple orchestrators may run against the same repo, each
owning its own per-session manifest; this view unions them all.

This skill is **strictly read-only**. It exists to *observe* the fleet, never to
change it. Integration, bookmarks, push, and any mutation stay with
[`/jj-delegate`](../jj-delegate/SKILL.md).

## Why this exists

`jj log` does not auto-snapshot sibling workspaces — a worker that has edited
files but not run a jj command since will report a **stale** working-copy commit
in a plain log. And `jj` alone cannot know a worker is *blocked*: that workflow
state lives in the gitignored agent-plan manifests that `/jj-delegate` owns.
Since the orchestrator became per-session-namespaced, there is no longer a
single manifest — each orchestrator session owns its own
`.jj-agent-plan.<session-id>.json` (with the unnamespaced `.jj-agent-plan.json`
still valid for the lone-orchestrator back-compat case). A repo with two
concurrent orchestrators therefore carries two (or more) manifests, and a single
fleet view must **union** them. This skill fixes all of it: snapshot-then-read
for correctness, then union every manifest and join workflow status onto each
workspace, attributing each row to its owning session.

## Procedure

Run these passes in order. Everything here is non-mutating.

### 1. Discover and union every manifest

There may be **more than one** manifest. Discover them all at the repo root:

- every per-session manifest matching `.jj-agent-plan.*.json` (one per
  orchestrator session — `.jj-agent-plan.<session-id>.json`); **and**
- the default unnamespaced `.jj-agent-plan.json` (the lone-orchestrator
  back-compat path), if present.

```bash
# Discover all manifests at the repo root (sorted, deduped). Both forms.
ls -1 .jj-agent-plan.json .jj-agent-plan.*.json 2>/dev/null
```

For each manifest found, read its slice entries (each slice carries
`workspace`, `bookmark`, `base-rev`, `status`, `workload`/`blocker`) **and** its
top-level liveness marker (owning `session` id + `heartbeat` timestamp, and any
explicit `ended`/session-ended marker). The owning session id is the manifest's
own session — from the liveness marker, falling back to the `<session-id>` in
the filename; the default file's owner is the implicit single session.

**Staleness gate (read-only — see §1a).** Before a manifest contributes any
slice to the view, classify it live or stale. A **stale** manifest's slices are
excluded (or visibly demoted) — they are never presented as live in-flight work.

**Union the live manifests' slices** into one set, keyed by **workspace path**,
tagging every slice with its **owning session** so each row stays attributable.
This unioned set is the join source for workflow metadata; the workspace set for
the view is the union of these slice workspaces and `jj workspace list` (§5).

- If **no** manifest exists (neither form), derive the workspace set from
  `jj workspace list` instead (graceful degradation — see §5). The view still
  renders; manifest-only columns (including owning session) are marked `unknown`.

Treat **every** manifest as **read-only**: never write, add, or delete an entry
in any session's manifest, and never delete a manifest file — not even a stale
one (reclamation is `/jj-delegate`'s startup sweep, not this skill's).

### 1a. Staleness exclusion (read-only)

Each manifest carries a liveness marker the owning orchestrator refreshes as it
operates. Classify a manifest **stale** when either:

- its `heartbeat` timestamp is **older than the liveness TTL** (the threshold
  `/jj-delegate` uses for its sweep), with no fresher liveness signal; **or**
- it carries an explicit **session-ended** marker (e.g. `ended: true`).

Stale manifests are dead/abandoned orchestrator state. **Exclude their slices**
from the live view, or visibly demote them (e.g. a separate, clearly-labelled
"stale / abandoned" section) so they can never be mistaken for live in-flight
work. A live workspace that only appears in a stale manifest still renders from
live jj state (§5) with its manifest-only fields marked `unknown`.

This exclusion is **strictly read-only**: omit/demote in the rendered view only.
Do **not** delete, archive, or modify any stale manifest file — that is the
orchestrator's responsibility, not this skill's.

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
| Session | owning orchestrator session (manifest liveness marker / filename) |
| Change | held change-id (live jj) |
| Description | held change description (live jj) |
| Conflict | conflict flag (live jj) |
| Stale | stale flag (live jj `workspace list`) |
| Status | in-flight / done / blocked (manifest slice, joined by workspace path) |
| Blocker / Workload | blocker note or workload (manifest slice) |

The **live jj** columns (Change, Description, Conflict, Stale) are always the
source of truth for change state — a stale manifest can never misreport them.
The **manifest** columns (Session, Status, Blocker/Workload) are joined onto the
live row by **workspace path** from the unioned live manifests (§1).

When more than one session is present, every row is attributable to its owning
session via the **Session** column; optionally group or sub-head rows by
session, but a single consolidated table is the default. The **Session** column
is itself a manifest-only field — mark it `unknown` for any workspace with no
matching live-manifest slice.

#### Example rendered output

```markdown
## Fleet status — 3 workspaces · 2 sessions

| Workspace        | Session  | Change   | Description                  | Conflict | Stale | Status    | Blocker / Workload          |
| ---------------- | -------- | -------- | ---------------------------- | -------- | ----- | --------- | --------------------------- |
| wt-apply-auth    | sess-a1  | qpvuntsm | feat: add login action       | —        | —     | in-flight | /opsx:apply add-auth        |
| wt-apply-billing | sess-a1  | zzrlkokm | fix: prorate cancellations   | conflict | —     | blocked   | merge conflict in plan.sql  |
| wt-spike-rt      | sess-b2  | mlinkrwq | wip: poke at realtime        | —        | stale | in-flight | spike realtime              |
| wt-adhoc-old     | unknown  | rwzpkqtn | wip: leftover                | —        | —     | unknown   | unknown (no live manifest)  |
```

Two orchestrator sessions (`sess-a1`, `sess-b2`) are unioned into one table; the
last row matches no live manifest slice (its only manifest was stale, or it is
absent from every manifest) so its Session/Status/Blocker are `unknown`. If any
manifest was **stale**, its slices do not appear here as live — optionally list
them under a clearly-labelled demoted section, never mixed into the live rows.

`jj workspace update-stale` (run **in that workspace**) is the fix for a stale
row — surface it as a hint next to the table; **never auto-run it**:

> `wt-adhoc-spike` is stale — fix with `jj -R <ws> workspace update-stale` (or
> `cd <ws> && jj workspace update-stale`). This skill does not run it for you.

### 5. Graceful degradation

The view must **never fail**; render what you can and mark the rest `unknown`.
The live workspace set always comes from `jj workspace list`; the manifests only
*enrich* rows. Manifest-only fields are **Session (owning session), Status,
Blocker/Workload** — each is `unknown` when no live manifest covers that
workspace.

- **No manifest at all** (neither default nor any per-session file) → derive
  workspaces from `jj workspace list`; render the live-derived columns (Change,
  Description, Conflict, Stale); mark Session, Status, and Blocker/Workload
  `unknown`.
- **Partial coverage** (some workspaces in a live manifest, some not — common
  with multiple sessions, or when a workspace's only manifest was stale) →
  union from `jj workspace list` so every live workspace appears; enrich the
  covered rows; mark the uncovered rows' Session/Status/Blocker `unknown`.
- **Workspace not in any live manifest** → still render its live-derived
  columns; mark Session and Status `unknown` for that row.
- **Manifest field missing on a slice** → treat the missing key as `unknown`
  (read defensively; a manifest schema addition must not break the view).
- **Manifest present but stale** (§1a) → treat its workspaces as uncovered for
  the live view (manifest-only fields `unknown`), since stale slices are
  excluded; the row still renders from live jj state.

## Guardrails

- **Read-only jj only**, plus `jj util snapshot` (which records only a sibling's
  own working copy). Reads use `--ignore-working-copy` and `--no-pager`.
- **No manifest writes.** Every agent-plan manifest (the default
  `.jj-agent-plan.json` and each per-session `.jj-agent-plan.<session-id>.json`)
  is owned by a `/jj-delegate` session; read them, never write/add/delete
  entries, and **never delete or archive a manifest file** — not even a stale
  one. Excluding a stale manifest from the view is a render-time decision only;
  reclamation is the orchestrator's startup sweep.
- **No new hooks.** This skill relies only on existing read-only jj behavior and
  introduces no hooks or background processes.
