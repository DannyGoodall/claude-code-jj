## Context

The plugin family already provides a GitHub-lifecycle "reconcile tail" — `/jj-pr`, `/jj-stacked-pr`, `/jj-land`, `/jj-pr-fixup`, `/jj-keep-current`, `/jj-absorb` — but it stops at *merge*. There is no skill that cuts a GitHub **release**. This change adds `/jj-release` and, in doing so, surfaces a latent architectural seam: those tail skills are not really *about* concurrency; they are the single-threaded jj→GitHub lifecycle that concurrent work flows into. `/jj-release` is the cleanest possible first member of a dedicated lifecycle plugin because it has zero coupling to concurrency or OpenSpec.

Constraints that shape the design:
- **jj 0.42** ships no native tag-creation command, and the `jj-concurrent` guard hook blocks raw mutating git (including `git tag`).
- The plugin's skills are deliberately **non-interactive** (no editor, no `-i`), yet a release needs human judgment (version, notes).
- A release is cut from a commit on trunk; by then the originating PR is merged, so PR-scoped CI queries no longer apply.
- This is the repo's **first-ever** release tooling — no existing tags or releases to build on.

## Goals / Non-Goals

**Goals:**
- A reusable `/jj-release` skill that cuts a GitHub release for *any* project shape, owning the generic version→tag→notes→publish core.
- Human-in-the-loop safety via a relay gate, on a non-interactive substrate.
- Decouple release tooling from concurrency/OpenSpec by shipping it in a new `jj-lifecycle` plugin.
- An opaque, optional seam for attaching build artifacts without the skill knowing how anything is built.

**Non-Goals (v1):**
- Monorepo / per-package releases (the unit is the whole repo at one commit).
- Manifest version bumping (tag-only).
- Registry publishing (npm / PyPI / crates).
- Building executables or multi-platform build matrices.
- Migrating the existing reconcile-tail skills into `jj-lifecycle` (deferred to a separate change).

## Decisions

**D1 — New `jj-lifecycle` plugin instead of adding to `jj-concurrent`.**
`/jj-release` has no dependency on the delegate/worker/concurrency machinery, and some users will want release tooling without it. A separate plugin gives a release-only install path. *Alternative considered:* drop it into `jj-concurrent` (simplest, zero new scaffolding) — rejected because it reinforces exactly the coupling we want to remove and forces release-only users to install concurrency. The target end-state layering is `jj-lifecycle` (base: solo jj→GitHub) ← `jj-concurrent` (composes the tail) ← bindings; reaching it requires migrating the other tail skills, which is **deferred** to its own change because `jj-concurrent` composes those skills and would then depend on `jj-lifecycle`.

**D2 — Relay shape (prepare → human gate → publish), reusing the `/jj-openspec relay` pattern.**
A release needs human judgment, but the substrate is non-interactive. The relay pattern already in the family resolves this: do all computable work, halt at a single go/no-go gate, execute on "go". *Alternative considered:* a fully non-interactive `--yes` flow — rejected for v1 as too dangerous for an immutable, public artifact (though it could be a future opt-in).

**D3 — Tag-only versioning.**
The tag *is* the version; no manifest is edited. This makes the skill universal (no per-ecosystem version-file knowledge) and keeps v1 small. The cost — repo release version may diverge from internal manifest versions — is acceptable and explicitly allowed. *Alternative considered:* detect-and-bump a manifest field then commit — richer, but requires per-ecosystem knowledge and a commit-and-push dance; deferred.

**D4 — Server-side tag creation via `gh release create --target <sha>`.**
Sidesteps both jj 0.42's missing tag creation and the guard hook's block on raw `git tag`. The tag is created on the remote at the chosen commit as part of release creation. *Alternative considered:* `git tag` + push — blocked by the guard hook and not available cleanly through jj.

**D5 — CI gate read from commit-level checks, not PR checks.**
By release time the PR is merged, so the skill reads the target commit's check-runs and combined status (`gh api repos/{owner}/{repo}/commits/{sha}/check-runs` and `.../commits/{sha}/status`) rather than `gh pr checks`. Failing/pending → refuse. This mirrors `/jj-land`'s "don't ship red" stance but at the commit granularity a release requires.

**D6 — SemVer auto-propose, always confirm; ask outright on first release / non-conventional commits.**
Conventional-commit prefixes drive the proposed bump, but the human always confirms — the skill never publishes an unconfirmed version. With no prior tag there is nothing to bump from, so the skill asks for the initial version with no default. With non-conventional history it degrades to asking.

**D7 — 0.x defaults to `--prerelease` ON (plugin policy).**
GitHub does not infer pre-release from the version string; this is the skill's policy, reflecting SemVer's "0.x is unstable". Overridable at the gate. Documented as policy so users aren't surprised.

**D8 — Refuse on an existing release for the tag.**
Tags are immutable once depended upon. Unlike `/jj-pr` (create-or-update), `/jj-release` refuses with a clear message and asks for a new version, rather than mutating a published artifact.

**D9 — Optional artifacts hook as an opaque, owner-owned seam.**
Mirrors `jj-delegate`'s "the skill owns the choreography; the workload is the workload's business". The skill runs a user-supplied command and uploads its output files; it ships no build logic. The skill's obligation ends at "provide the hook + upload". *Open sub-question:* how the hook is specified (CLI flag vs config entry vs conversational prompt) — see Open Questions.

## Risks / Trade-offs

- **Tag-only version diverging from manifest versions is confusing** → Mitigation: document the policy clearly in `MANUAL.md` and the case study; the gate summary shows the exact tag so there is no silent surprise.
- **`gh` lacking release scope / not authenticated** → Mitigation: a dependency preflight that reports a clear blocker before any work (consistent with `/jj-pr`).
- **Commit-level "required" checks are fuzzier than PR required checks** (branch-protection "required contexts" are branch-scoped) → Mitigation: v1 treats "green" as "all check-runs on the target commit concluded success with none failing/pending"; refine later if needed. Surface the actual check list at the gate.
- **Deferring the tail-skill migration leaves two homes for lifecycle skills temporarily** → Mitigation: explicitly scoped as a separate follow-up change; this change adds only `/jj-release` to `jj-lifecycle`.
- **Dev-loop friction**: newly developed plugin functionality is not picked up until uninstall → reinstall → quit → resume (hooks don't hot-reload), and the marketplace being a remote git repo means changes must be pushed and the remote marketplace refreshed before they're visible → Mitigation: a dedicated validation task documents the exact sequence and a manual smoke test.

## Migration Plan

This change is additive (new plugin + new skill + docs); no rollback of existing behavior is needed. To adopt: create the `jj-lifecycle` plugin scaffold, register it in `marketplace.json`, author the skill, then exercise the dev-loop (push to remote marketplace, reinstall, restart) and smoke-test `/jj-release` against a draft release. The reconcile-tail migration is a separate future change.

## Open Questions

- **Artifacts hook specification** — is the opaque build command supplied as a CLI argument to `/jj-release`, a config entry (e.g. a `jj-lifecycle` settings key), or a conversational prompt at prepare time? Leaning conversational for v1 (lowest ceremony, fits the relay), with a config entry as a likely fast-follow.
- **"Required" checks definition on a bare commit** — adopt branch-protection required contexts, or "all checks must be green"? v1 uses the simpler "all green"; revisit if it proves too strict/lax.
- **Initial repo release version for this repo specifically** — start a fresh `v0.1.0` repo line, or match the flagship plugin (`v0.7.1`)? An apply-time decision for the concrete first release, not a skill behavior.
