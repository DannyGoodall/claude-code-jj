# migrate-lifecycle-skills (FUTURE / NOT YET READY — description only)

> **Status: deferred, description-only.** This is a forward-looking note that
> captures a follow-up to `add-jj-release`. It is **not** a ready change: it has
> no design, specs, or tasks, and **must not be implemented** until promoted into
> a full change of its own. Nothing here moves any skill yet.
>
> It is intentionally a `README.md`, **not** a `proposal.md`, so that
> `openspec validate --all --strict` (the repo's CI gate) does not treat this
> directory as a parseable change and fail on its (deliberately) missing deltas.
> When this is promoted to a real change, rename it to `proposal.md` and author
> the design / specs / tasks alongside it.

## Why

`add-jj-release` introduced the `jj-lifecycle` plugin and shipped `/jj-release`
as its first skill, deliberately decoupled from concurrency and OpenSpec. But the
reconcile-tail skills that are *also* really just the solo jj→GitHub lifecycle —
`jj-pr`, `jj-land`, `jj-absorb`, `jj-pr-fixup`, `jj-keep-current`,
`jj-stacked-pr` — still live in `jj-concurrent`. They are not actually *about*
concurrency; they are the single-threaded lifecycle that concurrent work flows
into. Leaving them in `jj-concurrent` keeps two homes for lifecycle tooling and
forces a release-/PR-only user to install the whole concurrency machinery.

## What Changes (proposed, for the future change)

- **Migrate** the reconcile-tail skills (`jj-pr`, `jj-land`, `jj-absorb`,
  `jj-pr-fixup`, `jj-keep-current`, `jj-stacked-pr`) out of `jj-concurrent` and
  into `jj-lifecycle`, so `jj-lifecycle` becomes the **base** layer of solo
  jj→GitHub lifecycle skills.
- **Establish the layering** `jj-lifecycle` (base) ← `jj-concurrent` (composes
  the tail) ← bindings (`jj-concurrent-openspec`, `jj-concurrent-linear`).
- **Dependency-direction implication:** `jj-concurrent` would then **depend on
  `jj-lifecycle`** (its reconcile tail composes those skills), reversing today's
  arrangement where the tail skills live inside `jj-concurrent`. Cross-skill
  references (e.g. `/jj-delegate` and `/jj-openspec apply` invoking `/jj-pr`,
  `/jj-land` deferring to `jj-delegate` Teardown) and the relative SKILL.md links
  between them would need re-pathing across the plugin boundary.

## Why this is deferred (not done in `add-jj-release`)

`jj-concurrent` composes these skills, so moving them is a cross-plugin
refactor with real blast radius: the marketplace entries, every relative skill
link, the guard/snapshot hook wiring, and the dev-loop (uninstall → reinstall →
restart) all have to be reworked and re-validated together. `add-jj-release`
keeps its blast radius to **adding** one plugin and one skill; this migration is
its own change with its own design, specs, and validation, to be authored when
the team is ready to take it on.

## Out of scope for this note

No specs, no design, no tasks, and no implementation. Promote this into a full
change (via the OpenSpec workflow) before doing any of the migration.
