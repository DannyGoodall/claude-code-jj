# Roadmap

What's proposed but **not yet built**. Each item below is a live OpenSpec
proposal under [`openspec/changes/`](openspec/changes/) — read the change's
`proposal.md` for the full why, `design.md` for the approach, and `tasks.md` for
the implementation breakdown. Shipped features live in the
[README](README.md#status) and [MANUAL](MANUAL.md); the plugin is self-hosting,
so these are applied the same way it builds everything else —
`/jj-openspec apply <change-name>` on a jj workspace.

This is a backlog, not a commitment or an ordering. As of jj-concurrent v0.3.0 /
jj-concurrent-openspec v0.2.0 there are **8 active proposals**.

**Recently shipped (jj-concurrent v0.3.0)** — applied concurrently by the plugin's
own workers and reconciled in one stack
([case study](docs/case-studies/fleet-fanout-2026-06-09.md)):
`jj-absorb-fixup` (`/jj-absorb`), `jj-stacked-pr` (`/jj-stacked-pr`),
`jj-op-checkpoint` (`/jj-checkpoint` + `/jj-rewind`), and
`workspace-aware-guard-role-enforcement` (guard now blocks worker bookmark/push).

**Recently shipped (jj-concurrent-openspec v0.2.0)** — a second four-worker
fan-out, reconciled through a deliberate 4-way merge on `jj-openspec/SKILL.md`
([case study](docs/case-studies/openspec-pipeline-fanout-2026-06-09.md)):
`gate-verify-autoarchive-on-apply`, `jj-openspec-relay`, `jj-openspec-healthcheck`,
and `multi-change-concurrent-pipeline`.

---

## jj-native stack & history (git-flow parity)

The Graphite workflows this plugin succeeds, rebuilt on jj primitives.

| Change | What it would add |
|--------|-------------------|
| [`jj-pr-fixup`](openspec/changes/jj-pr-fixup/) | Reads a PR's review comments, fixes them in a workspace based on the PR head, absorbs each fix into the commit it belongs to, and re-pushes — the amend-after-review loop end-to-end. Builds on the shipped `/jj-absorb` and `/jj-pr`. |
| [`jj-keep-current`](openspec/changes/jj-keep-current/) | Detect trunk moved → fetch → `jj rebase` the stack → push → re-check CI; gate landing behind a green required-checks signal so a stale-but-green PR never lands. |
| [`jj-land`](openspec/changes/jj-land/) | Land a whole stack of PRs bottom-up (the `gt merge` equivalent): wait for CI at each step, restack the rest, sync local trunk, tidy merged bookmarks and stale workspaces. |

## OpenSpec orchestration

All four proposals that sharpened the `jj-concurrent-openspec` binding —
`gate-verify-autoarchive-on-apply`, `jj-openspec-relay`, `jj-openspec-healthcheck`,
and `multi-change-concurrent-pipeline` — **shipped in binding v0.2.0** (see
Recently shipped, above). This section is intentionally empty until new
binding work is proposed.

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

- the **Linear** changes (`linear-dispatch-issue-creation`, `jj-linear-dispatch`, `jj-linear-burndown`, `jj-linear-reconcile-summary`) all extend the `jj-linear-sync` capability;
- the **PR family** (`jj-pr-fixup`, `jj-keep-current`, `jj-land`) all build on the shipped `/jj-pr` / `/jj-stacked-pr` (the `jj-github-pr` capability).

Apply the members of a family in sequence, not in a single blind fan-out, so the
spec merges stay legible.
