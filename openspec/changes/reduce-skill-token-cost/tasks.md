# Tasks — reduce-skill-token-cost

## 1. Stage 0 — Verification tooling (BEFORE any content change; commit 1)

- [x] 1.1 Write `scripts/lint-skills.py` (python3 stdlib): fail on frontmatter description >1024 chars (warn >700); fail on missing `name`/`description` frontmatter keys; fail on any relative link or intra-file anchor in a plugin SKILL.md that doesn't resolve; fail on >1 prose occurrence per file (outside fenced code blocks) of the boilerplate markers "Substrate knowledge", "never invoked inside a worker", and the non-interactive-contract sentence
- [x] 1.2 Write `scripts/skill-content-manifest.py` with `snapshot` (extract every fenced code block + table from all 16 plugin SKILL.md files, whitespace-normalized, content-hash-keyed, written to `scripts/skill-content-baseline.json`) and `check` (every baseline entry must exist somewhere in the repo; `--allow-drop <hash>` allowlist for deliberate deletions; non-zero exit + item/source report otherwise)
- [x] 1.3 Run `snapshot` and the lint to produce the baseline; record per-file byte/line/description-char counts (the report's "before" column); commit tooling + baseline + lint-baseline notes

## 2. Stage 1 — Description trim (commit 2)

- [x] 2.1 For each of the 16 SKILL.md files: rewrite the frontmatter description to ≤700 chars (one sentence of what, ≤4 trigger phrases, hard preconditions only); before deleting any operative detail from the description, locate it in the body and move it there if absent (verify, don't assume)
- [x] 2.2 Run lint + manifest check; capture per-file counts; commit

## 3. Stage 2 — Shared contract (commit 3)

- [ ] 3.1 Add the canonical "Roles & shared conventions" section to `plugins/jj-concurrent/skills/jj-delegate/SKILL.md` consolidating: substrate-knowledge-from-jj-vcs, orchestrator-only/never-in-a-worker, non-interactive jj (`--no-pager`, no `-i`, no editor), never raw mutating git, never delete `.jj`
- [ ] 3.2 In the other 15 skills, replace the repeated boilerplate paragraphs with one reference line restating only orchestrator-only + non-interactive inline; cross-plugin skills (jj-release, jj-openspec, the three linear skills) reference by prose name, no relative path; do NOT remove any skill-unique constraint; do NOT touch `agents/jj-workspace-worker.md` or any hook
- [ ] 3.3 Run lint (boilerplate-marker rule now bites) + manifest check; capture counts; commit

## 4. Stage 3 — Within-file dedupe (commit 4)

- [ ] 4.1 Collapse Guardrails sections that mirror Preconditions (jj-checkpoint, jj-land, jj-release, jj-absorb; sweep all 16 — jj-fleet, jj-preview, jj-rewind also have Guardrails sections); keep the section with operative ordering
- [ ] 4.2 Remove read-only/role assertions beyond the first per file; remove pure-ceremony steps (e.g. jj-checkpoint §5 "confirm recording stayed read-only")
- [ ] 4.3 In jj-delegate §3, collapse the three restatements of the no-session-id back-compat path into one
- [ ] 4.4 Run lint + manifest check; capture counts; commit

## 5. Stage 4 — jj-openspec diet (commit 5)

- [ ] 5.1 Create `plugins/jj-concurrent-openspec/skills/jj-openspec/references/examples.md`; move the verify-GATE, independent-changes-landed-concurrently, and declared-dependency-stitched-stack worked examples there; keep "two disjoint groups fanned out into one branch" inline, compressed; link references/examples.md relatively from the SKILL.md
- [ ] 5.2 Move the `opsx_filtered` wrapper into `plugins/jj-concurrent-openspec/skills/jj-openspec/scripts/opsx_filtered.sh`; SKILL.md invokes it by relative path
- [ ] 5.3 Compress "Two orthogonal concurrency axes" and "Fallback guarantee" to ≤3 sentences each; move full text to root `DESIGN.md` only if it adds rationale not already there, else record the drop via `--allow-drop`
- [ ] 5.4 Run lint + manifest check (moved blocks must match by content); capture counts; commit

## 6. Stage 5 — Merge jj-checkpoint + jj-rewind (commit 6)

- [ ] 6.1 Rewrite `plugins/jj-concurrent/skills/jj-checkpoint/SKILL.md` to expose both verbs (`/jj-checkpoint <label>` record; `/jj-checkpoint rewind [label]` restore), preserving both trigger-phrase sets in the (≤700 char) description and the full rewind procedure (confirmation summary, op-restore semantics) in the body; delete `plugins/jj-concurrent/skills/jj-rewind/`
- [ ] 6.2 Update every live cross-reference to the two skills: jj-delegate SKILL.md, jj-absorb SKILL.md, MANUAL.md, README.md, ROADMAP.md, docs/case-studies/*, `plugins/jj-concurrent/.claude-plugin/plugin.json` description, and `openspec/specs/jj-op-checkpoint/spec.md` via this change's delta (archived openspec changes stay untouched as historical record); verify `.claude-plugin/marketplace.json` needs no edit
- [ ] 6.3 Run lint + manifest check (rewind's code blocks/tables must survive in the merged file); repo-wide grep for `jj-rewind` to confirm only historical/archive hits remain; capture counts; commit

## 7. Stage 6 — jj-linear numbering + trigger caps (commit 7)

- [ ] 7.1 Fix jj-linear heading drift (§2.1, §2.2 then §3.2–§3.5: renumber so sections are contiguous and §5.6's reference to "§2" still points at the right section); grep repo for references to the renumbered headings
- [ ] 7.2 Sweep all 16 descriptions to confirm ≤4 trigger phrases (should already hold from Stage 1; fix stragglers)
- [ ] 7.3 Run lint + manifest check; capture counts; commit

## 8. Final verification + report

- [ ] 8.1 Run the full lint + manifest check one last time; produce the final report: per-stage diffstat, total bytes/tokens saved split frontmatter vs bodies, content-preservation manifest results (including every `--allow-drop`), all cross-references updated, and everything deliberately NOT changed with a one-line reason each
- [ ] 8.2 List 5 manual trigger-phrase smoke checks for a fresh session: one per plugin (jj-concurrent → "fan out agents on jj workspaces"; jj-concurrent-openspec → "apply <change> on a jj workspace"; jj-concurrent-linear → "burn down the board"; jj-lifecycle → "cut a release") + the merged skill's rewind verb ("roll back that rebase")
- [ ] 8.3 Note the dev-loop caveat in the report: local plugin edits aren't live until push → refresh marketplace → reinstall → restart session
