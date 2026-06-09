# Roadmap

What's proposed but **not yet built**. Each item below is a live OpenSpec
proposal under [`openspec/changes/`](openspec/changes/) — read the change's
`proposal.md` for the full why, `design.md` for the approach, and `tasks.md` for
the implementation breakdown. Shipped features live in the
[README](README.md#status) and [MANUAL](MANUAL.md); the plugin is self-hosting,
so these are applied the same way it builds everything else —
`/jj-openspec apply <change-name>` on a jj workspace.

This is a backlog, not a commitment or an ordering. As of jj-concurrent v0.3.0
there are **12 active proposals**.

**Recently shipped (v0.3.0)** — applied concurrently by the plugin's own workers
and reconciled in one stack ([case study](docs/case-studies/fleet-fanout-2026-06-09.md)):
`jj-absorb-fixup` (`/jj-absorb`), `jj-stacked-pr` (`/jj-stacked-pr`),
`jj-op-checkpoint` (`/jj-checkpoint` + `/jj-rewind`), and
`workspace-aware-guard-role-enforcement` (guard now blocks worker bookmark/push).

---

## jj-native stack & history (git-flow parity)

The Graphite workflows this plugin succeeds, rebuilt on jj primitives.

| Change | What it would add |
|--------|-------------------|
| [`jj-pr-fixup`](openspec/changes/jj-pr-fixup/) | Reads a PR's review comments, fixes them in a workspace based on the PR head, absorbs each fix into the commit it belongs to, and re-pushes — the amend-after-review loop end-to-end. Builds on the shipped `/jj-absorb` and `/jj-pr`. |
| [`jj-keep-current`](openspec/changes/jj-keep-current/) | Detect trunk moved → fetch → `jj rebase` the stack → push → re-check CI; gate landing behind a green required-checks signal so a stale-but-green PR never lands. |
| [`jj-land`](openspec/changes/jj-land/) | Land a whole stack of PRs bottom-up (the `gt merge` equivalent): wait for CI at each step, restack the rest, sync local trunk, tidy merged bookmarks and stale workspaces. |

## OpenSpec orchestration

Sharpening the `jj-concurrent-openspec` binding.

| Change | What it would add |
|--------|-------------------|
| [`gate-verify-autoarchive-on-apply`](openspec/changes/gate-verify-autoarchive-on-apply/) | Make `/opsx:verify` a real **gate** in the apply tail (a change that fails verify never reaches trunk/PR), and auto-archive on green — sync delta specs to canonical and move the change to `archive/`, so a clean apply leaves no manual follow-up. |
| [`jj-openspec-relay`](openspec/changes/jj-openspec-relay/) | A single propose → (review) → apply entry point, with the apply base-revision flowing automatically from the just-approved proposal — instead of two human-initiated commands with a manual hand-off. |
| [`jj-openspec-healthcheck`](openspec/changes/jj-openspec-healthcheck/) | Validate a change's artifacts **before** provisioning a workspace (fail fast with an operator-facing blocker, not confusing worker output), and filter the known-harmless opsx schema-config stderr so a genuine error doesn't hide in the noise. |
| [`multi-change-concurrent-pipeline`](openspec/changes/multi-change-concurrent-pipeline/) | `/jj-openspec apply` over a **set** of independent changes as concurrent siblings — the across-changes axis of concurrency — landed independently or stitched into one stack. |

## Linear integration

Extending the `jj-concurrent-linear` binding from "report → sub-issue" to a full board↔fan-out loop.

| Change | What it would add |
|--------|-------------------|
| [`linear-dispatch-issue-creation`](openspec/changes/linear-dispatch-issue-creation/) | Auto-create the umbrella + per-worker sub-issues at **dispatch** and thread their IDs into the orchestrator's manifest — the upstream step the current reconcile-side update assumes already happened. |
| [`jj-linear-dispatch`](openspec/changes/jj-linear-dispatch/) | One command from a triaged (`ready-for-agent`) Linear issue to a dispatched `jj-delegate` worker, with the bookmark and PR/change back-link derived deterministically from the issue itself. |
| [`jj-linear-burndown`](openspec/changes/jj-linear-burndown/) | Drain a board's `ready-for-agent` issues as a bounded stream of concurrent jj workers, updating each issue as its worker lands — the board becomes a work queue with jj as the engine. |
| [`jj-linear-reconcile-summary`](openspec/changes/jj-linear-reconcile-summary/) | Turn reconcile into a posted **umbrella summary** (root cause, tests, PR link) and, when warranted, an explicit human-gate sub-issue — instead of a terse status flip that loses the narrative. |

## Safety & isolation

Hardening the concurrency model from convention into structure.

| Change | What it would add |
|--------|-------------------|
| [`sparse-workspace-partitions`](openspec/changes/sparse-workspace-partitions/) | Use `jj workspace add --sparse-patterns` so a worker's working copy only materialises its declared lane — making "these are the only files you touch" a structural guarantee, not a request that surfaces as a conflict at integration. |

(The orchestrator-only role rule is now enforced *in the guard hook* — shipped in
v0.3.0 as `workspace-aware-guard-role-enforcement`.)

---

## Applying these

```bash
/jj-openspec apply <change-name>          # one change on its own workspace
/jj-openspec apply <change-name>  (fan out across task groups)   # if tasks.md has separable groups
```

**Archive-time canonical-spec collisions** — some pairs touch the same canonical
capability spec, so applying both means merging the delta into one spec at
archive time rather than two independent syncs:

- the **OpenSpec-binding** changes (`jj-openspec-relay`, `jj-openspec-healthcheck`, `multi-change-concurrent-pipeline`) all extend the `jj-openspec-binding` capability;
- the **Linear** changes (`linear-dispatch-issue-creation`, `jj-linear-dispatch`, `jj-linear-burndown`, `jj-linear-reconcile-summary`) all extend the `jj-linear-sync` capability;
- the **PR family** (`jj-pr-fixup`, `jj-keep-current`, `jj-land`) all build on the shipped `/jj-pr` / `/jj-stacked-pr` (the `jj-github-pr` capability).

Apply the members of a family in sequence, not in a single blind fan-out, so the
spec merges stay legible.
