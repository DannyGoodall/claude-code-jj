# narrative-docs-maintenance Specification

## Purpose
TBD - created by archiving change refresh-narrative-docs. Update Purpose after archive.
## Requirements
### Requirement: Narrative docs reconciled against canonical source of truth

The repo's top-level narrative documentation SHALL be kept accurate against the
current source of truth, evaluated in this precedence order: (1) the canonical
capability specs under `openspec/specs/*/spec.md`; (2) the live `SKILL.md` files
under `plugins/*/skills/` and the plugin manifests at
`plugins/*/.claude-plugin/plugin.json`; (3) the marketplace manifest at
`.claude-plugin/marketplace.json`; (4) the hooks under
`plugins/jj-concurrent/hooks/`. Narrative docs MUST NOT be reconciled against
older or archived change proposals when these authoritative sources disagree
with them.

The in-scope narrative documentation set is: `DESIGN.md`, `JJ_OVERVIEW.md`,
`MANUAL.md`, `ROADMAP.md`, `README.md`, and the case studies under
`docs/case-studies/`.

#### Scenario: A doc claim diverges from the canonical spec or live SKILL

- **WHEN** an in-scope narrative doc makes a claim (a capability description, a
  skill name, a command list, a plugin-layout statement, or a cross-reference)
  that contradicts the current spec, live `SKILL.md`, plugin manifest, or
  marketplace manifest
- **THEN** the divergence SHALL be recorded as a delta for that doc and the doc
  SHALL be rewritten in place so the claim matches the authoritative source

#### Scenario: A doc references a renamed, moved, or retired skill or plugin

- **WHEN** an in-scope doc names a skill or plugin that has been renamed, moved
  to a different plugin, or retired (for example a lifecycle skill that now lives
  in the `jj-lifecycle` plugin)
- **THEN** the reference SHALL be corrected to the current name and location, or
  removed if the capability no longer exists

### Requirement: Audit-then-rewrite with per-doc independence

The maintenance process SHALL, for each in-scope doc, first AUDIT it (record the
concrete delta between the doc's claims and the current spec/SKILL/manifest
reality) and then REWRITE it in place to apply that delta. A doc whose audit
finds no divergence SHALL be recorded as a verified no-op and MUST NOT be
force-rewritten. The process SHALL produce in-place edits to the docs, never a
separate standalone report artifact.

#### Scenario: Audit finds a doc already accurate

- **WHEN** the audit of an in-scope doc finds no divergence from the current
  source of truth
- **THEN** that doc SHALL be recorded as a verified no-op and left unchanged

#### Scenario: Audit finds a doc has drifted

- **WHEN** the audit of an in-scope doc finds one or more divergences
- **THEN** only that doc SHALL be rewritten in place to resolve its own
  divergences, independently of the audit outcome of any other doc

### Requirement: Cross-consistency across docs and manifests

After the per-doc rewrites, the narrative docs SHALL be mutually consistent and
consistent with `.claude-plugin/marketplace.json`, the plugin manifests, and the
live skill descriptions — specifically the plugin names, the per-plugin skill
counts, and the command lists.

#### Scenario: Cross-consistency check after rewrites

- **WHEN** the per-doc audit-and-rewrite passes are complete
- **THEN** a final consistency check SHALL confirm that every plugin name, skill
  count, and command list stated in the docs agrees both across the docs and
  with the marketplace manifest, the plugin manifests, and the live `SKILL.md`
  descriptions

### Requirement: Documentation-only scope

This maintenance activity SHALL NOT change any behavior, code, capability spec,
plugin manifest, marketplace manifest, or hook. It edits only the in-scope
narrative documentation files.

#### Scenario: A behavioral change appears necessary

- **WHEN** the audit reveals that an authoritative behavioral artifact (a spec,
  SKILL, manifest, or hook) is itself wrong rather than the doc
- **THEN** the maintenance activity SHALL leave that artifact unchanged and
  record the finding for a separate behavioral change, editing only the
  documentation here
