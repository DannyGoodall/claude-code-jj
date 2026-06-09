## Context

The `jj-concurrent` orchestrator already knows how to provision a throwaway jj workspace at an arbitrary base revision (`jj workspace add -r <rev> ../wt-<slug>`), populate that workspace's per-workspace environment with the gitignored files the app needs (composing with a worktree-include convention), and assign a distinct port per worker that runs the app, then tear the workspace down with `jj workspace forget` + directory removal. All of this exists to let *workers* do mutating work and report back.

What is missing is the inverse, read-only use of the same machinery: an operator wants to *look at* a specific change/commit/bookmark running as a real app — before its work is verified, archived, or merged — without disturbing anything. Today the only path is to rebase `@` onto the target (mutating the working copy) and start the app by hand. This change adds `/jj-preview <rev>`: a strictly read-only-to-history skill that reuses the existing provisioning, environment, and port conventions to stand up a throwaway preview, report its URL + PID, and tear it down cleanly.

## Goals / Non-Goals

**Goals:**
- Stand up a runnable dev environment from any commit/change/bookmark with a single `/jj-preview <rev>` invocation, leaving `@` and all refs untouched.
- Reuse — not reinvent — `jj-delegate`'s workspace provisioning, per-workspace environment provisioning (gitignored-file copy + worktree-include), and port-per-worker assignment.
- Report a reachable URL and the process PID so the operator can interact with and later kill the preview.
- Provide clean teardown that never touches the repo `.jj`/`.git`.

**Non-Goals:**
- No bookmark movement, no push, no archive — ever. The skill is read-only with respect to history.
- No change to the worker agent or its structured JSON report shape; previews are not workers.
- No new hooks and no new marketplace plugin; ship as one additive `SKILL.md` in `jj-concurrent`.
- No persistent process supervisor or long-lived daemon; the preview is a foreground-detached dev process the operator owns until teardown.
- Not a verification or test-running step (that remains `jj-openspec verify` / the worker contract); preview is purely "let me see it running".

## Decisions

**D1 — Provision via `jj workspace add -r <rev>`, never rebase `@`.** A throwaway workspace at the target revision is the existing, isolation-correct primitive: it materialises `<rev>` on disk in its own directory while the orchestrator's `@` and every bookmark stay exactly where they were. *Alternative considered:* rebase `@` onto `<rev>`, run, then rebase back — rejected because it mutates the working copy and history (op-log churn, risk of conflicts), violating the read-only-to-history contract for a task that only ever reads.

**D2 — Distinct preview directory naming `../wt-preview-<slug>`.** Naming previews `wt-preview-<slug>` (slug derived from the revision/bookmark) keeps them visually distinct from worker workspaces and lets multiple previews coexist. The `preview-` prefix also makes teardown targeting unambiguous.

**D3 — Compose with the existing per-workspace environment provisioning.** Rather than defining a new gitignored-file copy mechanism, the skill reuses the orchestrator's per-workspace-environment provisioning: copy the gitignored files the app needs (`.env`, local config) into the preview, and compose with the worktree-include convention where the project declares one. *Rationale:* a preview that runs the app needs the same environment a worker that runs the app needs; one mechanism, one source of truth. *Alternative considered:* a bespoke preview-only copy list — rejected as drift-prone duplication.

**D4 — Reuse the port-per-worker assignment for the preview's port.** The orchestrator already assigns a distinct port per worker that runs the app; the preview draws a port from that same convention so a preview never collides with a running worker app or another concurrent preview. *Rationale:* collisions are the obvious failure mode when more than one app runs against shared local services; reusing the established allocator avoids inventing a second, conflicting scheme.

**D5 — Report URL + PID; teardown stops the process then forgets the workspace.** The skill reports the URL (host + assigned port) and the dev process PID so the operator can interact and later identify what to stop. Teardown is the mirror of provisioning: stop the process, `jj workspace forget` the preview, remove the `../wt-preview-<slug>` directory — and never `rm` anything under `.jj`/`.git`. *Rationale:* `jj workspace forget` is the supported way to drop a linked workspace from the repo's view without disturbing the shared object store.

**D6 — Orchestrator-only.** Only the orchestrator owns workspace provisioning and teardown (the same ownership rule as `jj-delegate`); a worker never previews. This keeps refs/workspace lifecycle authority in one place.

## Risks / Trade-offs

- **[A preview's app process is orphaned if the session dies before teardown]** → The skill reports the PID at startup so the operator can always kill it manually; teardown is idempotent (forget + rm tolerate an already-stopped process / already-removed dir).
- **[A preview competes with a worker for shared local services (DB, dev server backend)]** → Port distinctness (D4) prevents listen-port collisions; shared-state collisions on a single local DB are the operator's call, the same trade-off any concurrently-running app faces. The skill does not pretend to isolate shared services.
- **[Operator confuses a preview workspace with a worker workspace]** → The `wt-preview-` prefix (D2) and the explicit "read-only, never moves bookmarks" framing in the skill keep the two visually and behaviourally distinct.
- **[Project has no worktree-include convention declared]** → The skill falls back to copying the known gitignored files the app needs (D3); composing with worktree-include is an enhancement when present, not a hard dependency.
- **[`jj workspace add` or the dev command hangs]** → Provisioning and teardown commands are non-interactive (`--no-pager`); a hung dev command is reported with its PID so the operator can stop it, and the workspace is left available for teardown.

## Migration Plan

Additive only. Ship the `/jj-preview` `SKILL.md` inside the existing `jj-concurrent` plugin. No schema, no hook, no marketplace-plugin change, no change to the worker report shape. Enablement is the existing plugin enablement; absence of the skill means no trigger. Rollback is removing the single skill file — there is no persisted state to migrate, since the skill writes nothing to history (no bookmarks, no push, no archive) and only ever creates/removes a throwaway workspace directory.

## Open Questions

- Should `/jj-preview` accept an optional explicit port override for operators who want a fixed, memorable port instead of the auto-assigned one? Default is auto-assignment via the existing convention; an override is deferred unless an operator need emerges.
- Should teardown be auto-offered (e.g. a follow-up `/jj-preview --teardown <slug>` affordance) versus relying on the operator to forget + rm? Initial scope reports the teardown commands explicitly; a dedicated teardown sub-invocation is a candidate refinement.
