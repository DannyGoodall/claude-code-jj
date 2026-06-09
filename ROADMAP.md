# Roadmap

What's proposed but **not yet built**. Each item below is a live OpenSpec
proposal under [`openspec/changes/`](openspec/changes/) — read the change's
`proposal.md` for the full why, `design.md` for the approach, and `tasks.md` for
the implementation breakdown. Shipped features live in the
[README](README.md#status) and [MANUAL](MANUAL.md); the plugin is self-hosting,
so these are applied the same way it builds everything else —
`/jj-openspec apply <change-name>` on a jj workspace.

This is a backlog, not a commitment or an ordering. As of jj-concurrent v0.6.0 /
jj-concurrent-openspec v0.2.0 there are **6 active proposals**.

**Recently shipped (jj-concurrent v0.6.0)** — the workspace & dev-environment
batch, applied as a 3-worker fan-out and landed via the now-fixed `/jj-land`:
`worktreeinclude-provisioning` (declarative gitignored-file seeding on provision),
`jj-preview-skill` (`/jj-preview <rev>` throwaway dev-env), and
`sparse-workspace-partitions` (opt-in `--sparse-patterns` hard file-ownership).

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

**Recently shipped (jj-concurrent v0.5.0)** — `multi-orchestrator-namespacing`:
implemented via a **within-a-change** fan-out (three workers, one change — session-id
+ manifest namespacing, naming + stale-sweep, and the `/jj-fleet` union — stitched
into one branch). More than one orchestrator can now run in a repo without
clobbering the manifest or colliding on names.

**Recently shipped (jj-concurrent v0.5.1)** — `jj-land-colocated-cleanup`: fixes
`/jj-land` under colocated jj — judge merge success by PR **state** (not the
`gh pr merge` exit code that fails on jj's detached git HEAD), drop
`--delete-branch`, and **explicitly delete each merged PR's remote branch** in
cleanup so no stragglers remain. Found — and validated by hand — landing/cleaning
PRs #11–#14.

**Recently shipped (jj-concurrent v0.4.0)** — `jj-land` (`/jj-land`): land a stack
of GitHub PRs bottom-up, CI-gated, **retargeting each child's base to trunk
before merge** so a stack can no longer orphan its upper PRs onto deleted feature
branches (the hazard that stranded the earlier #6/#7 content). Applied alongside
three new proposals authored in the same four-worker fan-out (below).

---

## jj-native stack & history (git-flow parity)

The Graphite workflows this plugin succeeds, rebuilt on jj primitives.

| Change | What it would add |
|--------|-------------------|
| [`jj-pr-fixup`](openspec/changes/jj-pr-fixup/) | Reads a PR's review comments, fixes them in a workspace based on the PR head, absorbs each fix into the commit it belongs to, and re-pushes — the amend-after-review loop end-to-end. Builds on the shipped `/jj-absorb` and `/jj-pr`. |
| [`jj-keep-current`](openspec/changes/jj-keep-current/) | Detect trunk moved → fetch → `jj rebase` the stack → push → re-check CI; gate landing behind a green required-checks signal so a stale-but-green PR never lands. |

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

The proposals here have all shipped: the guard-hook role rule
(`workspace-aware-guard-role-enforcement`, v0.3.0), `multi-orchestrator-namespacing`
(v0.5.0), and `sparse-workspace-partitions` (v0.6.0). Intentionally empty until
new safety/isolation work is proposed.

## Workspaces & dev environment

Both proposals — `worktreeinclude-provisioning` and `jj-preview-skill` — shipped
in v0.6.0 (see Recently shipped, above). Intentionally empty until new
workspace/dev-env work is proposed.

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
- the **PR family** (`jj-pr-fixup`, `jj-keep-current`) all build on the shipped `/jj-pr` / `/jj-stacked-pr` / `/jj-land` (the `jj-github-pr` capability).

Apply the members of a family in sequence, not in a single blind fan-out, so the
spec merges stay legible.
