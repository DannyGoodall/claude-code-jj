## 1. DESIGN.md

- [ ] 1.1 AUDIT `DESIGN.md`: record the delta between its claims and current specs / live `SKILL.md`s / plugin manifests / `marketplace.json` / hooks — check the ADR's status, the plugin/skill layout it implies, any superseded architecture claims, the Graphite-supersession framing, and all cross-references for staleness.
- [ ] 1.2 REWRITE `DESIGN.md` in place to apply the audited delta; no-op (verified, unchanged) if the audit found it accurate.

## 2. JJ_OVERVIEW.md

- [ ] 2.1 AUDIT `JJ_OVERVIEW.md`: record the delta against current source of truth — verify the "how the plugin uses jj" section names the current plugins/skills, the jj version references, the companion-doc cross-references, and any command lists.
- [ ] 2.2 REWRITE `JJ_OVERVIEW.md` in place to apply the audited delta; no-op if the audit found it accurate.

## 3. MANUAL.md

- [ ] 3.1 AUDIT `MANUAL.md`: record the delta against current source of truth — verify every skill it documents exists at the named plugin (incl. `jj-pr-fixup`, `jj-preview`, `jj-fleet`, the `jj-lifecycle`/`jj-release` migration, the Linear bindings `jj-from-linear`/`jj-linear`/`jj-burndown`, the `jj-openspec` healthcheck/relay/pipeline/fanout surface, sparse partitions, worktree-include provisioning, multi-orchestrator namespacing), the orchestrator/worker contract, the hooks description, command lists, the contents/TOC, and cross-references.
- [ ] 3.2 REWRITE `MANUAL.md` in place to apply the audited delta; no-op if the audit found it accurate.

## 4. ROADMAP.md

- [ ] 4.1 AUDIT `ROADMAP.md`: record the delta against current source of truth — reconcile the "recently shipped" / "backlog empty" claims and version numbers against the actual shipped capabilities and live `openspec/changes/` contents; flag anything listed as proposed that has in fact shipped, and vice versa.
- [ ] 4.2 REWRITE `ROADMAP.md` in place to apply the audited delta; no-op if the audit found it accurate.

## 5. README.md

- [ ] 5.1 AUDIT `README.md` (refreshed in PR #48 — expect minimal residual gaps): record any delta against current source of truth — verify the plugin table's names, skill lists, and the documentation cross-references match the live plugins/skills/manifests.
- [ ] 5.2 REWRITE `README.md` in place to apply the audited delta; no-op if the audit found it accurate.

## 6. docs/case-studies/fleet-fanout-2026-06-09.md

Case-study rule (applies to all three case studies — see design.md Decision 6): a case study is a point-in-time record of the commands the user **actually ran AT THAT TIME**. Do NOT retrofit it with capabilities or commands that did not exist / were not used then — they genuinely weren't used, and adding them rewrites history. The ONLY permitted rewrite is correcting a command / skill / plugin reference the doc **actually shows** that has since been **renamed, moved, or retired**, so the recorded command would no longer name the same thing today. Default outcome is a verified no-op.

- [ ] 6.1 AUDIT `docs/case-studies/fleet-fanout-2026-06-09.md`: of the commands / skills / plugins the doc actually shows, record only those that have since been renamed / moved to another plugin / retired. Do NOT flag "missing" newer capabilities — their absence is correct for the date.
- [ ] 6.2 REWRITE `docs/case-studies/fleet-fanout-2026-06-09.md` in place ONLY to correct a shown reference that has since changed name/location; otherwise record a verified no-op. Never add capabilities/commands that weren't used at the time.

## 7. docs/case-studies/linkstack-walkthrough.md

- [ ] 7.1 AUDIT `docs/case-studies/linkstack-walkthrough.md` (expected CURRENT — verify only): under the same case-study rule, of the commands / skills / plugins it actually shows, record only any that have since been renamed / moved / retired.
- [ ] 7.2 REWRITE `docs/case-studies/linkstack-walkthrough.md` in place ONLY to correct such a shown-and-since-changed reference; otherwise record a verified no-op (likely outcome). Do not add newer capabilities.

## 8. docs/case-studies/openspec-pipeline-fanout-2026-06-09.md

- [ ] 8.1 AUDIT `docs/case-studies/openspec-pipeline-fanout-2026-06-09.md`: under the same case-study rule, of the commands / skills / plugins it actually shows, record only those that have since been renamed / moved / retired on the current `jj-openspec` surface. Do NOT flag newer pipeline/relay/healthcheck/fanout features as "missing" — they weren't used on the date.
- [ ] 8.2 REWRITE `docs/case-studies/openspec-pipeline-fanout-2026-06-09.md` in place ONLY to correct a shown reference that has since changed name/location; otherwise record a verified no-op. Never retroactively add capabilities/commands.

## 9. Cross-consistency

- [ ] 9.1 Verify the docs agree with each other AND with `.claude-plugin/marketplace.json`, the plugin manifests (`plugins/*/.claude-plugin/plugin.json`), and the live skill descriptions: the set of plugin names, the per-plugin skill counts, and the command lists are consistent everywhere they appear; reconcile any remaining mismatch by editing the affected doc(s) only.
