# Roadmap

What's proposed but **not yet built**. Each item below is a live OpenSpec
proposal under [`openspec/changes/`](openspec/changes/) — read the change's
`proposal.md` for the full why, `design.md` for the approach, and `tasks.md` for
the implementation breakdown. Shipped features live in the
[README](README.md#status) and [MANUAL](MANUAL.md); the plugin is self-hosting,
so these are applied the same way it builds everything else —
`/jj-openspec apply <change-name>` on a jj workspace.

This is a backlog, not a commitment or an ordering. As of jj-concurrent v0.7.1 /
jj-lifecycle v0.1.0 / jj-concurrent-openspec v0.2.0 / jj-concurrent-linear v0.3.0
the backlog holds **one deferred item** — `migrate-lifecycle-skills` (below); every
other proposed change has shipped. New ideas land here as OpenSpec proposals.

## jj→GitHub lifecycle layering

`migrate-lifecycle-skills` — **deferred, description-only** (a forward-looking note
under [`openspec/changes/migrate-lifecycle-skills/`](openspec/changes/migrate-lifecycle-skills/),
deliberately a `README.md` rather than a `proposal.md` so the strict
`openspec validate` CI gate does not parse it as a ready change). It proposes
migrating the solo-lifecycle reconcile-tail skills — `jj-pr`, `jj-land`,
`jj-absorb`, `jj-pr-fixup`, `jj-keep-current`, `jj-stacked-pr` — out of
`jj-concurrent` and into `jj-lifecycle`, so `jj-lifecycle` becomes the **base**
layer (`jj-lifecycle` ← `jj-concurrent` ← the OpenSpec/Linear bindings) and a
release-/PR-only user need not install the concurrency machinery. It is a
cross-plugin refactor with real blast radius (marketplace entries, every relative
skill link, the hook wiring, the reinstall/restart dev-loop) and must be promoted
to a full change — rename to `proposal.md`, author design/specs/tasks — before any
implementation.

---

**Recently shipped (jj-lifecycle v0.1.0)** — `add-jj-release`: the new standalone
`jj-lifecycle` plugin and its first skill `/jj-release` (cut a GitHub release for
the repo at a commit — relay-shaped prepare → human go/no-go gate → publish, with a
CI gate on the target commit, an always-confirmed SemVer bump from conventional
commits, tag-only `vMAJOR.MINOR.PATCH` versioning via `gh release create --target`,
a `0.x → --prerelease` default, and an optional opaque artifacts hook). Decoupled
from concurrency and OpenSpec, so it installs on its own. (The follow-up that would
move the reconcile-tail skills into it is the deferred `migrate-lifecycle-skills`
note above.)

**Recently shipped (jj-concurrent v0.7.1)** — `jj-absorb-no-dry-run-fallback`:
`/jj-absorb` (and, by composition, `/jj-pr-fixup`) now runs on a jj that ships
`jj absorb` without `--dry-run` (e.g. 0.42). It detects `--dry-run`; where absent
it captures the pre-absorb op, runs `jj absorb`, reviews placement via
`jj op show -p`, and surfaces a one-command `jj op restore` undo. Validated live
on jj 0.42 — including the full `/jj-pr-fixup` loop end-to-end, which closed that
skill's last live-exercise task.

**Recently shipped (jj-concurrent v0.7.0 + jj-concurrent-linear v0.3.0)** — the
final batch: all four remaining proposals applied in one 4-worker fan-out and
landed as a 3-PR stack via `/jj-land`. jj-concurrent gained `/jj-pr-fixup` (the
amend-after-review loop over an already-open PR) and `/jj-keep-current` (restack
the stack onto moved trunk + gate landing on green CI); the Linear binding gained
its inbound half — `/jj-from-linear` (a triaged issue → a dispatched worker) and
`/jj-burndown` (drain a `ready-for-agent` board as a bounded worker stream). Each
change added its own new skill file, so the four worker branches were disjoint.

**Recently shipped (jj-concurrent-linear v0.2.0)** — landed as a 2-PR shared-file
stack (both edit `jj-linear/SKILL.md`) via the now-fixed `/jj-land`, validating
the stack-restack fix on a real shared-file stack: `linear-dispatch-issue-creation`
(auto-create umbrella + per-worker sub-issues at dispatch, thread IDs into the
manifest) and `jj-linear-reconcile-summary` (post a four-section umbrella summary
+ a human-gate sub-issue at reconcile).

**Recently shipped (jj-concurrent v0.6.1)** — `jj-land-stack-restack`: `/jj-land`
now waits for mergeability (not just CI) before each merge, defaults to `--merge`
for multi-PR stacks, and restacks+repushes the tail after a rewriting merge — so
a shared-file stack lands without cascade-conflicts. (Found + fixed landing PRs
#16–#19; the `/jj-land` family of fixes is now complete.)

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

## Robustness & portability

`jj-absorb-no-dry-run-fallback` — **shipped in v0.7.1** (see Recently shipped,
above): `/jj-absorb` adapts to a jj without `absorb --dry-run` via an op-log
review-and-undo fallback. Intentionally empty until new robustness/portability
work is proposed.

## jj-native stack & history (git-flow parity)

The Graphite workflows this plugin succeeds, rebuilt on jj primitives — **both
shipped in v0.7.0** (see Recently shipped, above): `jj-pr-fixup` (`/jj-pr-fixup`)
and `jj-keep-current` (`/jj-keep-current`). Intentionally empty until new
stack/history work is proposed.

## OpenSpec orchestration

All four proposals that sharpened the `jj-concurrent-openspec` binding —
`gate-verify-autoarchive-on-apply`, `jj-openspec-relay`, `jj-openspec-healthcheck`,
and `multi-change-concurrent-pipeline` — **shipped in binding v0.2.0** (see
Recently shipped, above). This section is intentionally empty until new
binding work is proposed.

## Linear integration

The `jj-concurrent-linear` binding's board↔fan-out loop — **both shipped in
binding v0.3.0** (see Recently shipped, above): `jj-linear-dispatch`
(`/jj-from-linear`) and `jj-linear-burndown` (`/jj-burndown`). Intentionally empty
until new Linear work is proposed.

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

**Archive-time canonical-spec collisions** — when two queued changes touch the
same canonical capability spec, archive them in sequence (not a blind fan-out) so
the delta merges into one spec legibly. (The only open backlog item,
`migrate-lifecycle-skills`, is a deferred description-only note with no specs, so it
poses no collision today; this note is kept for the next time a family of related
changes is queued. The v0.7.0 / linear v0.3.0 batch had no such collision at apply
time — each change added its own new skill file — so all four applied as one
disjoint fan-out.)
