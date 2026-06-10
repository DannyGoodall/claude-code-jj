## 1. New `jj-lifecycle` plugin scaffold

- [x] 1.1 Create `plugins/jj-lifecycle/.claude-plugin/plugin.json` with `name: jj-lifecycle`, `version: 0.1.0`, and a description scoped to "solo jj→GitHub lifecycle (release, …)".
- [x] 1.2 Register `jj-lifecycle` in `.claude-plugin/marketplace.json` (new entry under `plugins`, `source: ./plugins/jj-lifecycle`).
- [x] 1.3 Create the `plugins/jj-lifecycle/skills/jj-release/` directory for the skill.

## 2. Author the `/jj-release` skill

- [ ] 2.1 Write `plugins/jj-lifecycle/skills/jj-release/SKILL.md` front-matter (name, description, trigger phrases) following the voice/shape of existing `jj-concurrent` skills.
- [ ] 2.2 Document **Preconditions**: orchestrator-only; colocated jj↔git repo with `origin`; `gh` authenticated with release scope; non-interactive substrate (`--no-pager`, no `-i`, no editor).
- [ ] 2.3 Implement the **dependency preflight** (`gh` present + authenticated; `origin` remote present) reporting clear blockers before any work.
- [ ] 2.4 Implement **target resolution** (default trunk HEAD) and the **CI gate** reading commit-level check-runs + combined status (`gh api repos/{owner}/{repo}/commits/{sha}/check-runs` and `.../commits/{sha}/status`); refuse on red/pending with a clear message. *(spec: CI gate on the target commit)*
- [ ] 2.5 Implement **version proposal**: detect last tag; if none, ask for the initial version with no default; else auto-propose a SemVer bump from conventional commits and ALWAYS require confirm/override; degrade to asking on non-conventional history. Enforce `vMAJOR.MINOR.PATCH` tag format. *(spec: SemVer bump proposal; First-release handling; Tag-only versioning)*
- [ ] 2.6 Implement **notes generation** (commits/PRs since last tag) with in-conversation editing before the gate; support an optional GitHub **draft** preview. *(spec: Release notes generation and editing)*
- [ ] 2.7 Implement the **0.x → `--prerelease` ON** default, overridable at the gate. *(spec: Pre-release default for 0.x)*
- [ ] 2.8 Implement the **optional artifacts hook**: run a project-supplied command if provided, collect emitted files, list them at the gate, upload on publish; ship no build logic. *(spec: Optional opaque artifacts hook)*
- [ ] 2.9 Implement the **relay gate**: present version, target sha, notes, prerelease flag, draft flag, asset list; publish only on explicit "go"; make no changes on "no". *(spec: Relay-shaped release flow)*
- [ ] 2.10 Implement **publish** via `gh release create <tag> --target <sha> --notes-file … [--prerelease] [--draft] [assets…]` (server-side tag creation); **refuse** if a release for the tag already exists. *(spec: Server-side tag creation; Refuse to overwrite an existing release)*
- [ ] 2.11 Add a **report-shaped result** (version, target, CI verdict, prerelease/draft, assets, release URL or the blocker/refusal reason) and a **Failure modes** section, matching the family's conventions.

## 3. Documentation

- [ ] 3.1 *(after the skill is finalized)* Add a new feature step to `docs/case-studies/linkstack-walkthrough.md` demonstrating `/jj-release`, matching the existing requirement → In Claude → Skill/Tips → Under the hood pattern.
- [ ] 3.2 Add the `/jj-release` row to the case study's Coverage map and Cheat-sheet tables, with anchor links, consistent with the doc's existing style.
- [ ] 3.3 Add a `MANUAL.md` entry for `/jj-release` (what it does, the tag-only/version policy, the 0.x pre-release default, the CI gate, the artifacts hook boundary).

## 4. Validation (dev-loop + smoke test)

- [ ] 4.1 Document and follow the repo's dev-loop for picking up new plugin functionality: push the changes to the remote, refresh the remote marketplace, then **uninstall → reinstall → quit → resume** the session (skills may appear without this, but hooks do not hot-reload).
- [ ] 4.2 Smoke-test `/jj-release` end to end against a **draft** release on this repo: confirm CI gate, version proposal/confirm, notes editing, prerelease default, and that re-running on an existing tag is refused.
- [ ] 4.3 Run `openspec validate add-jj-release --strict` and the repo's CI checks (openspec validate / shellcheck / json) before opening the PR.

## 5. Deferred follow-up (describe only — do NOT implement in this change)

- [ ] 5.1 Author a separate future change proposing migration of the reconcile-tail skills (`jj-pr`, `jj-land`, `jj-absorb`, `jj-pr-fixup`, `jj-keep-current`, `jj-stacked-pr`) from `jj-concurrent` into `jj-lifecycle`, establishing the layering `jj-lifecycle` (base) ← `jj-concurrent` (composes it) ← bindings, and noting the dependency-direction implication (`jj-concurrent` would then depend on `jj-lifecycle`).
