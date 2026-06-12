# Design — reduce-skill-token-cost

## Context

The four plugins (`jj-concurrent`, `jj-concurrent-openspec`, `jj-concurrent-linear`, `jj-lifecycle`) ship 16 SKILL.md files. Measured baseline (2026-06-12):

- Frontmatter descriptions: **20,124 chars total**; 11 of 16 over the 1024-char guidance (worst: jj-land 1843, jj-burndown 1763, jj-release 1762, jj-keep-current 1693, jj-from-linear 1468).
- Bodies: 274 KB / 5,746 lines total; jj-openspec alone is 42 KB / 735 lines with four worked examples (§"Worked example: …", lines 579–695) and two rationale essays (§"Two orthogonal concurrency axes", §"Fallback guarantee").
- "Substrate knowledge comes from the installed jj-vcs skill" appears verbatim in 11 files. Orchestrator-only / non-interactive / never-raw-mutating-git assertions recur within single files (description + preconditions + guardrails). The guard hook already mechanically enforces the mutating-git and `.jj`-deletion bans.
- The existing `jj-op-checkpoint` spec mandates **two separate skills** (`/jj-checkpoint`, `/jj-rewind`), so Stage 5's merge is a spec-level change (delta spec in this change).
- `plugins/jj-concurrent/.claude-plugin/plugin.json`'s `description` names "jj-checkpoint/jj-rewind" and must stay consistent after the merge.
- There is no repo-level `scripts/` or `tests/` dir yet; a root `DESIGN.md` exists (home for any rationale text worth keeping).

Constraint from the request: **no behavior change** — skill procedures, hooks, and `agents/jj-workspace-worker.md` are untouched; only doc shape, packaging, and the new verification tooling change.

## Goals / Non-Goals

**Goals:**
- Every frontmatter description ≤700 chars (hard ceiling 1024), preserving routing quality (what + ≤4 triggers + hard preconditions).
- Single-source the repeated contract boilerplate; dedupe within files; shrink jj-openspec; merge checkpoint+rewind; fix jj-linear numbering.
- Verification tooling exists **before** the first content edit and stays afterward as a regression gate.
- Every stage is one commit, independently revertable; lint green after every stage.

**Non-Goals:**
- No changes to runtime behavior, hooks, the worker agent definition, archived openspec changes, or the vendored `.claude/`/`.agent/` openspec skills.
- No removal of any skill-unique constraint (only repeated/derivable text is collapsed).
- No trimming of `plugin.json` descriptions beyond consistency edits — verified zero per-session token cost (UI-only; see Open Questions), so it has no place in a token-cost change.

## Decisions

### D1 — Merged skill keeps the `jj-checkpoint` name; rewind becomes a verb
Merge into `plugins/jj-concurrent/skills/jj-checkpoint/` exposing two verbs: `/jj-checkpoint <label>` records (unchanged surface); `/jj-checkpoint rewind [label]` restores. The `jj-rewind` directory is deleted. The merged description carries **both** trigger-phrase sets ("checkpoint before this rebase"; "undo back to the checkpoint", "roll back that rebase") so model-routing for rewind intent still lands. *Alternatives:* keep two dirs with one a stub (no token savings); rename to `jj-savepoint` (breaks both existing commands). Trade-off accepted: `/jj-rewind` stops existing as a standalone slash command — recorded as **BREAKING** in the proposal and covered by a smoke check.

### D2 — Canonical contract home: jj-delegate §"Roles & shared conventions"
The shared boilerplate (substrate-knowledge pointer, orchestrator-only/never-in-a-worker, non-interactive jj contract, never raw mutating git, never delete `.jj`) lives once in `plugins/jj-concurrent/skills/jj-delegate/SKILL.md` under a stable heading. Every other skill replaces its repeated paragraphs with one line that (a) names the reference ("Shared contract: jj-delegate §Roles & shared conventions") and (b) restates only the two binding essentials inline — orchestrator-only + non-interactive — so a skill loaded standalone keeps its operative constraints. Cross-plugin references (jj-release, the linear/openspec bindings) use the **prose name, not a relative path**, because plugins install as separate directory trees and a relative link would dangle in an installed cache. *Alternative:* a repo-root CONVENTIONS.md — rejected for the same installed-cache reason (it isn't shipped inside any plugin).

### D3 — Lint checks prose, not commands
`--no-pager` legitimately appears in command examples up to 12× per file (jj-absorb). The duplicate-boilerplate lint therefore counts occurrences **outside fenced code blocks** of the convention *prose* markers — "Substrate knowledge", "never invoked inside a worker", and the non-interactive-contract sentence pattern — and fails on >1 prose occurrence per file. Other lint rules: description length >1024 hard-fails (warn >700); relative links/anchors in any plugin SKILL.md must resolve; required frontmatter keys (`name`, `description`) present.

### D4 — Verification tooling location and shape
`scripts/lint-skills.py` and `scripts/skill-content-manifest.py` (python3 stdlib only, exit non-zero on failure). The manifest tool has `snapshot` (extract every fenced code block + table from each plugin SKILL.md, normalized whitespace, keyed by content hash → `scripts/skill-content-baseline.json`, committed in Stage 0) and `check` (each baseline entry must exist somewhere in the repo: same file, a `references/` file, `DESIGN.md`, or `scripts/`). Content matching is by normalized content, not path, so Stage 4/5 moves don't false-flag. Deliberate deletions require a `--allow-drop <hash>` allowlist recorded in the final report.

### D5 — jj-openspec diet specifics
Keep "Worked example: two disjoint groups fanned out into one branch" inline (the flagship fan-out shape), compressed; move the verify-GATE, independent-changes-landed-concurrently, and declared-dependency-stitched-stack examples to `skills/jj-openspec/references/examples.md` (linked relatively — same plugin, link survives install). Move the `opsx_filtered` wrapper into `skills/jj-openspec/scripts/opsx_filtered.sh`; the SKILL.md invokes/sources it by relative path. Compress "Two orthogonal concurrency axes" and "Fallback guarantee" to ≤3 sentences each; full text goes to the root `DESIGN.md` only if it adds rationale not already there, else dropped via the D4 allowlist.

### D6 — Stage order and commit discipline
Stage 0 (tooling + baseline snapshot + lint baseline report) commits first; Stages 1–6 in the numbered order, one commit each, lint + manifest check green before each commit. Stage 5 runs after the dedupe stages so the merged file is written once, post-slimming. Byte/line counts per file captured at every stage boundary for the final report.

## Risks / Trade-offs

- [Trigger-routing regression after description trims / the merge] → Both verb trigger sets kept in the merged description; ≤4 strongest triggers retained per skill; 5 manual smoke checks listed in the final report (one per plugin + merged-skill rewind verb), since triggering can't be tested statically.
- [Operative detail silently lost from a description] → Stage 1 rule: any detail removed from frontmatter must be located in the body first (verify, don't assume); content manifest catches dropped code blocks/tables; prose loss is covered by per-file review in the stage commit.
- [Standalone skill loses contract context after Stage 2] → One-line reference retains the two binding essentials inline; the guard hook still mechanically enforces the hard bans regardless of prose.
- [Cross-references drift (MANUAL.md, README.md, ROADMAP.md, docs/case-studies, plugin.json)] → Per-stage repo-wide grep for every renamed/moved/merged heading and skill name; archived openspec changes are explicitly left as historical record.
- [Installed-plugin link breakage] → Relative links only within a plugin; cross-plugin references by prose name (D2); lint link-checker enforces resolvable relative links.

## Migration Plan

Each stage is one commit on a feature branch/bookmark; revert = drop that commit. Plugin consumers pick up changes via the existing dev-loop (push → refresh marketplace → reinstall → restart session). Rollback of Stage 5 restores the `jj-rewind` directory verbatim.

## Open Questions

- None blocking. Checked and resolved: `plugins/jj-concurrent/.claude-plugin/plugin.json`'s ~2 KB description costs **zero** context tokens — plugin.json and marketplace.json descriptions are UI-only (the `/plugin` browser) and are never injected into model context; only SKILL.md frontmatter descriptions are (per the Claude Code plugins reference's always-on token-cost model). Trimming it is therefore out of scope for a token-cost change; this change edits it only for checkpoint/rewind naming consistency in Stage 5.
