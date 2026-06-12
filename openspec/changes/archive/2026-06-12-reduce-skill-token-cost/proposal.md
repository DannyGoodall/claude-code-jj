# Reduce skill token cost

## Why

The 16 plugin SKILL.md frontmatter descriptions total ~20 KB and load into every Claude Code session's context; 11 of 16 exceed the 1024-char description guidance (jj-land 1843, jj-burndown 1763, jj-release 1762, jj-keep-current 1693). Beyond frontmatter, the same contract boilerplate ("Substrate knowledge comes from the installed jj-vcs skill" — verbatim in 11 files; orchestrator-only / non-interactive-jj / never-raw-mutating-git assertions repeated within single files) and oversized bodies (jj-openspec at 735 lines with four worked examples and two rationale essays) inflate per-invocation token cost without adding behavior — much of it restates what the guard hook already mechanically enforces.

## What Changes

Six stages, one commit each (independently revertable), with verification tooling built **before** any content change:

- **Stage 0 (verification first)**: a lint script (`scripts/lint-skills.sh` or equivalent) failing on: description >1024 chars, broken relative links/anchors in any SKILL.md, known boilerplate prose appearing more than once per file, missing required frontmatter keys; plus a content-preservation manifest that snapshots every fenced code block and table before changes and confirms each survives somewhere in the repo afterward.
- **Stage 1 — Description trim**: every frontmatter description rewritten to ≤700 chars (hard ceiling 1024): one sentence of what, 3–4 trigger phrases, hard preconditions only. Operative detail removed from a description is verified to exist in (or is moved into) the body.
- **Stage 2 — Shared contract**: repeated boilerplate paragraphs extracted to one canonical home and replaced in each skill body by a one-line reference. Skill-unique constraints are never removed. The agent definition (`agents/jj-workspace-worker.md`) and hooks are untouched.
- **Stage 3 — Within-file dedupe**: Guardrails sections that mirror Preconditions removed; read-only/role assertions beyond the first removed; pure-ceremony steps removed (e.g. jj-checkpoint §5); jj-delegate §3's three restatements of the no-session-id back-compat path collapsed to one.
- **Stage 4 — jj-openspec diet**: three of four worked examples moved to `skills/jj-openspec/references/examples.md` (strongest kept inline, compressed); `opsx_filtered` wrapper moved to a `scripts/` file the skill invokes; "Two orthogonal concurrency axes" and "Fallback guarantee" compressed to ≤3 sentences each with full text preserved in DESIGN.md if worth keeping.
- **Stage 5 — Merge jj-checkpoint + jj-rewind** into one skill exposing both verbs (both trigger-phrase sets kept); all cross-references updated (jj-delegate, MANUAL.md, README.md, ROADMAP.md, docs/case-studies, plugin.json). **BREAKING** (invocation surface): `/jj-rewind` as a standalone slash command becomes a verb of the merged skill.
- **Stage 6 — jj-linear heading-numbering fix** (§2.x jumps to §3.2); trigger lists everywhere capped at ≤4 phrases.

Regression sweep each stage: grep the whole repo (MANUAL.md, README.md, docs/case-studies, openspec/) for renamed/moved/merged sections; marketplace.json and plugin.json kept consistent with any directory merge. Final report: per-stage diffstat, frontmatter-vs-body savings, manifest results, updated cross-references, deliberate non-changes, and 5 manual trigger-phrase smoke checks.

Explicit non-goals: no behavior change to any skill's runtime procedure; no edits to hooks or the worker agent definition; no removal of skill-unique constraints.

## Capabilities

### New Capabilities
- `skill-doc-budget`: token-budget and single-sourcing conventions for plugin skill docs — frontmatter description ceiling, shared-contract reference instead of repeated boilerplate, lint enforcement, and content-preservation guarantee for restructures.

### Modified Capabilities
- `jj-op-checkpoint`: the checkpoint and rewind capabilities are delivered by one skill exposing both verbs instead of two separate skills; recording and restore semantics are unchanged, but the invocation surface (skill name / slash command for rewind) changes and both trigger-phrase sets must keep routing.

## Impact

- **Files rewritten**: all 16 `plugins/*/skills/*/SKILL.md`; new `plugins/jj-concurrent-openspec/skills/jj-openspec/references/examples.md` and `scripts/` wrapper; one skill directory removed/merged under `plugins/jj-concurrent/skills/`.
- **Cross-reference updates**: MANUAL.md, README.md, ROADMAP.md, docs/case-studies/*, `plugins/jj-concurrent/.claude-plugin/plugin.json`, jj-delegate SKILL.md (links to both checkpoint and rewind). `.claude-plugin/marketplace.json` checked for consistency.
- **New tooling**: lint script + content-preservation manifest under `tests/` or `scripts/` (kept after the change as a regression gate).
- **Not touched**: `agents/jj-workspace-worker.md`, all hooks, archived openspec changes (historical record), the `.claude/`/`.agent/` openspec skill copies (vendored, not part of the plugin family).
- **Risk**: skill triggering cannot be tested statically — mitigated by the 5 manual smoke checks listed in the final report.
