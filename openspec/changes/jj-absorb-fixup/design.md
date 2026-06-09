## Context

The `jj-concurrent` plugin orchestrates worker subagents in linked jj workspaces and reconciles their changes back onto the orchestrator's stack. The `jj-delegate` spec already describes a reconcile/amend tail abstractly (integrate, then amend) but offers no concrete amend mechanism for the common post-review situation: a single working copy holding many small fixes, each of which logically belongs to a *different* commit deeper in the stack. The Graphite predecessor handled this with an amend-after-review loop (find the right commit, amend it, repeat). jj's native equivalent is `jj absorb`, which moves each working-copy hunk into the closest downstack commit that last modified the same lines. This change wraps that primitive in an orchestrator skill that previews, runs, and reports the placement.

This is authoring-only: the change drafts proposal/design/specs/tasks. No skill is implemented here.

## Goals / Non-Goals

**Goals:**
- A `/jj-absorb` orchestrator skill that runs `jj absorb` over the working copy non-interactively, with a `--dry-run` preview first.
- A clear per-hunk landing report (hunk → destination change-id + description).
- Safe handling of the ambiguous remainder: hunks with no unambiguous home stay in the working copy and are surfaced for manual placement.
- Drop-in use as the `jj-delegate` reconcile-tail amend step.

**Non-Goals:**
- No bookmark, push, or PR behaviour (that is `/jj-pr`'s job; absorb only reshapes local commits).
- No interactive hunk picking — the skill never opens an editor or `-i` flow; ambiguous hunks are left for the orchestrator to place deliberately.
- No worker-side use — absorb operates on the orchestrator's own stack only.
- No new plugin and no application-code changes in any target project.

## Decisions

**Decision: Dry-run preview before every mutating absorb.**
`jj absorb --dry-run` is run first and its plan surfaced. Rationale: absorb moves commits silently and can land a hunk in a surprising ancestor when several downstack commits touched the same lines; a preview lets the orchestrator confirm before history changes. Alternative considered — run absorb directly and report after — rejected because it offers no confirmation point and makes a surprising placement harder to catch before it is committed.

**Decision: Derive the landing report by diffing the dry-run plan against the post-run state rather than parsing one absorb invocation.**
jj's absorb output names destination commits, but to report reliably we compare the dry-run plan (hunk → target rev) with the working copy that remains after the real run; what disappeared from the working copy was absorbed, to the rev the plan named. Rationale: this is robust to output-format drift across jj versions and naturally separates absorbed hunks from the remainder. Alternative — scrape only the mutating run's stdout — rejected as brittle and version-coupled.

**Decision: Leave the ambiguous remainder in the working copy (jj's default) and name the manual escape hatch.**
The skill does not try to place hunks that have no unambiguous downstack home; it reports them and points at `jj squash --into <rev>` or shaping a fresh change. Rationale: forcing an ambiguous hunk into a guessed commit is exactly the silent-mistake class the orchestrator contract forbids. Alternative — fall back to an interactive `jj squash -i` — rejected: interactive commands are hang-traps and violate the non-interactive contract.

**Decision: Preflight-check `jj absorb` support and ship in core `jj-concurrent`.**
`jj absorb` is relatively recent; the skill checks support (e.g. `jj absorb --help`) and reports a blocker if absent rather than improvising. It ships inside core `jj-concurrent` next to `/jj-pr`, not a separate plugin, because it is part of the same reconcile-tail family. Alternative — a separate `jj-concurrent-absorb` plugin — rejected as over-fragmentation for one skill.

## Risks / Trade-offs

- **Surprising placement when multiple downstack commits touched the same lines** → the mandatory `--dry-run` preview exposes the target before history moves; the orchestrator confirms.
- **jj version without `jj absorb` (or without `--dry-run`)** → preflight check reports a clear blocker; the skill never falls back to a different mutating command.
- **Landing report drifts if jj changes absorb output** → report is derived from the dry-run-plan vs post-run diff, decoupling it from exact stdout wording.
- **Absorb on a conflicted or empty working copy is a no-op or noisy** → the "nothing to absorb" path reports cleanly and skips the mutating run.
- **Authoring-only scope mistaken for implementation** → design and tasks state explicitly that this change drafts artifacts only.

## Migration Plan

Not applicable — authoring-only change introducing a new skill spec. No deployment, data, or rollback concerns. When implemented later via `/opsx:apply`, the skill is additive (a new `SKILL.md` plus a `jj-delegate` prose pointer) and carries no migration.

## Open Questions

- Should the skill default to absorbing the whole working copy or require an explicit fileset/target each call? (Draft leans whole-working-copy by default, fileset optional — confirm at apply time.)
- Exact preflight probe for absorb support (`jj absorb --help` exit code vs a version check) — settle during implementation.
