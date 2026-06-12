# reduce-skill-token-cost — final report (2026-06-12)

## Headline numbers

- **Frontmatter descriptions (the always-on per-session cost): 19,566 → 9,773 chars (−50%, ~2,450 tokens saved per session).** All 15 descriptions now ≤700 chars (hard ceiling 1024); every one carries ≤4 trigger phrases.
- **Total SKILL.md footprint (per-invocation cost): 276,997 → 256,727 bytes (−20,270 bytes, ~5,000 tokens), 5,446 → 5,128 lines, 16 → 15 files.**
- Body-only savings: ~10,477 bytes (the rest is frontmatter).
- Lint (`scripts/lint-skills.py`): green at every stage boundary from stage 2 onward with no waiver; stage 1 boundary used the designed `--skip boilerplate` waiver (the duplicated prose was scheduled for stage 2).
- Content-preservation manifest: 108 items snapshotted before any change; **0 lost**, 2 deliberate in-place modifications recorded via `--allow-drop` (below).

## Per-stage diffstat (one commit per stage)

| Stage | Commit | Diffstat |
|---|---|---|
| proposal | docs(openspec): propose reduce-skill-token-cost | 6 files, +330/−0 |
| 0 | chore(verify): lint + content-preservation manifest, baseline | 5 files, +1242/−3 |
| 1 | docs(skills): trim all frontmatter descriptions to ≤700 chars | 17 files, +222/−256 |
| 2 | docs(skills): single-source the shared contract in jj-delegate | 13 files, +123/−48 |
| 3 | docs(skills): within-file dedupe of guardrails/preconditions | 7 files, +83/−70 |
| 4 | docs(jj-openspec): diet — examples → references/, wrapper → scripts/ | 6 files, +233/−154 |
| 5 | feat(jj-concurrent)!: merge jj-rewind into jj-checkpoint (rewind verb) | 11 files, +278/−255 |
| 6 | docs(jj-linear): fix heading numbering; confirm trigger caps | 3 files, +95/−33 |

## Per-file before → after

See `counts-stage0.json` … `counts-final.json` alongside this file. Highlights:
jj-openspec 42,432→35,528 B (735→610 lines); jj-checkpoint+jj-rewind combined
16,676→12,626 B; every over-limit description (11 of 16) now ≤700 chars.
Two files grew by design: jj-delegate (+611 B, it absorbed the canonical
shared-conventions section) and jj-checkpoint (+4,975 B, it absorbed the whole
rewind verb while the 9,025 B jj-rewind file disappeared).

## Content-preservation manifest results

- 108 fenced code blocks + tables snapshotted at stage 0; all verified present after every stage.
- 2 allowed drops, both deliberate in-place modifications (not deletions):
  - `314a437fc258ae85` — jj-checkpoint's JSON record example: internal section ref `§2` → `R2` after the merged file's renumbering.
  - `8aada9aef9cedb41` — jj-linear's mapping table: `§3.2/§3.3/§3.4` refs renumbered to `§2.3/§2.4/§2.5`.
- Moved-not-lost (matched by content at new homes): the `opsx_filtered` fence → `plugins/jj-concurrent-openspec/skills/jj-openspec/scripts/opsx_filtered.sh`; three worked examples → `…/jj-openspec/references/examples.md`; all of jj-rewind's fences → the merged `jj-checkpoint/SKILL.md`.

## Cross-references updated

- `plugins/jj-concurrent/skills/jj-delegate/SKILL.md` — 2 links to `../jj-rewind/` → merged-skill verb form.
- `plugins/jj-concurrent/skills/jj-absorb/SKILL.md` — `/jj-rewind` mention → `/jj-checkpoint rewind`.
- `MANUAL.md` — component-table row for the two skills → one skill, two verbs.
- `README.md` — plugin table (line 21) + skills list (line 130).
- `ROADMAP.md` — capability listing.
- `docs/case-studies/linkstack-walkthrough.md` — 5 instructional references (it teaches current usage).
- `plugins/jj-concurrent/.claude-plugin/plugin.json` — description's "jj-checkpoint/jj-rewind safety net" → "jj-checkpoint … with the rewind verb".
- `openspec/specs/jj-op-checkpoint/spec.md` — updated via this change's delta spec at archive time (5 MODIFIED requirements), not edited directly.
- `.claude-plugin/marketplace.json` — checked; contains no skill-level references, no edit needed.

## Deliberately NOT changed (one line each)

- `agents/jj-workspace-worker.md` and all hooks — explicitly out of scope (the guard hook still mechanically enforces the hard bans).
- `docs/case-studies/fleet-fanout-2026-06-09.md` — narrative record of a past session (quotes real logs/commit messages); rewriting it would falsify history.
- Archived openspec changes (`openspec/changes/archive/**`) — historical record by project convention.
- `.claude/` and `.agent/` openspec skill copies — vendored upstream skills, not part of this plugin family.
- jj-fleet/jj-openspec/jj-burndown/jj-from-linear/jj-linear got no shared-contract reference line — they never carried the boilerplate paragraph; adding the line would add tokens for nothing.
- The bash name-legend comment block in jj-delegate §3 — it is the densest expression of the back-compat naming and is content-manifest-tracked; the two prose restatements around it were collapsed instead.
- plugin.json description length — verified to cost zero context tokens (UI-only), so trimming it is cosmetic and out of scope; only the checkpoint/rewind naming was touched.
- Pre-existing cross-plugin relative links in jj-release (e.g. to `../../../jj-concurrent/skills/jj-pr/SKILL.md`) — pre-date this change; new references use prose names per design D2, but rewriting the old ones was not in scope.

## Manual trigger-phrase smoke checks (fresh session each)

Skill triggering can't be tested statically. After push → marketplace refresh → reinstall → restart:

1. **jj-concurrent / jj-delegate**: say "fan out agents on jj workspaces" → expect `/jj-delegate` to engage.
2. **jj-concurrent-openspec / jj-openspec**: say "apply <some-change> on a jj workspace" → expect `/jj-openspec` to engage.
3. **jj-concurrent-linear / jj-burndown**: say "burn down the board" → expect `/jj-burndown` to engage.
4. **jj-lifecycle / jj-release**: say "cut a release" → expect `/jj-release` to engage.
5. **Merged skill, rewind verb**: say "roll back that rebase" (no slash command) → expect `/jj-checkpoint`'s rewind verb to engage — this is the key regression check for the stage-5 merge.

## Dev-loop caveat

Local plugin edits are not live in a running session: push → refresh the
marketplace → reinstall the plugins → quit/resume the session before running
the smoke checks (hooks and skill descriptions do not hot-reload).
