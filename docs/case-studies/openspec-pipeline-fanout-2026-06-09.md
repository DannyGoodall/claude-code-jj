# Case study: an engineered 4-way merge (the OpenSpec-pipeline fan-out)

**Date:** 2026-06-09 · **jj:** 0.42.0 (colocated) · **Repo:** this one, self-hosting · **Companion:** [fleet-fanout-2026-06-09.md](fleet-fanout-2026-06-09.md)

The first fan-out case study deliberately picked changes with *mostly-disjoint*
files (one incidental 3-way conflict). This second run does the opposite: it
**engineers a conflict** by choosing four changes that all extend the same
capability and therefore all edit **one file** —
`plugins/jj-concurrent-openspec/skills/jj-openspec/SKILL.md`. The goal was to see
how the orchestrator/worker model handles "several agents each assume they own
the same file," and to submit the result as a real **stacked PR** via
`/jj-stacked-pr`.

---

## The batch (all extend `jj-openspec-binding`)

| Change | Tasks | Owns in `SKILL.md` |
|--------|-------|--------------------|
| `jj-openspec-healthcheck` | 12 | new `§3.5` pre-flight + stderr filter; frontmatter version |
| `jj-openspec-relay` | 16 | frontmatter description; verb-table `relay` row; new `§6`; Variants bullet |
| `gate-verify-autoarchive-on-apply` | 13 | verb-table `apply`/`propose` cells; `§5` verify-gate→archive tail; new worked example |
| `multi-change-concurrent-pipeline` | 21 | frontmatter description; new `§B`, `§4c`, `§P`; two worked examples |

Each worker was briefed that `SKILL.md` is a **shared, orchestrator-owned** file:
make your edits, but keep them scoped to your section and report exactly which
sections you touched. That briefing is what made the merge tractable.

## Fan-out (identical mechanism to run #1)

Four `jj-workspace-worker` agents off `main`, observed with `/jj-fleet` (t≈0 all
empty → mid-flight 2 writing → 1-done-3-inflight → all done). All four returned
clean, `openspec validate` passing, **13/16/12/21 tasks** ticked — and each
returned a **section-level map** of its `SKILL.md` edits.

## Reconcile — the engineered 4-way merge

Stacked `main → healthcheck → relay → gate-verify → multichange` with
`jj rebase` (never halts). Of the three rebases onto the growing stack:

- **`relay` onto `healthcheck` — clean.** Their frontmatter edits hit different
  lines (description vs version) and their body sections were disjoint (`§6`/verb-row
  vs `§3.5`/`§4`). jj auto-merged.
- **`gate-verify` — conflict.** It edits the verb→shape **table** that `relay`
  also edited (added a row). One conflict region.
- **`multichange` — conflict.** Four regions: the frontmatter **description** and
  **triggers** (also edited by relay), plus two **both-added** insertions where
  it and `gate-verify` each appended new sections (`§6`+`§P` before Variants;
  worked examples before Fallback).

Every resolution was mechanical, by **editing markers** (never `jj resolve`):

- **verb→shape table** — keep `gate-verify`'s rewritten `apply`/`propose` cells
  **and** `relay`'s new `relay` row.
- **frontmatter description / triggers** — **union** the relay sentence and the
  pipeline sentences; union both trigger lists.
- **both-added section blocks** — keep both insertions in order (`§6` then `§P`;
  the verify-GATE worked example then the pipeline worked examples). These showed
  an empty base between the markers — jj's signal for "both sides inserted here,"
  which merges by concatenation.

Result: all four commits `✓`, **zero markers**, `SKILL.md` coherent (relay `§6`,
pipeline `§B`/`§4c`/`§P`, both verb rows, all worked examples, frontmatter at
`0.2.0`), and all four changes still validate.

**Key observation:** even with four agents editing one file, only the genuinely
**overlapping regions** (the shared table + frontmatter) conflicted; disjoint
*new sections* merged for free. Physical isolation meant nothing raced; the
conflict surfaced only at integration, exactly where a human can reason about it.

## Submit — a real stacked PR

The four feature commits plus this docs commit were submitted with
**`/jj-stacked-pr`**: one PR per bookmark, each **based on its parent** rather
than trunk, so each PR's diff shows only its own change. This also sidesteps the
stray-local-bookmark issue from run #1 — every bookmark is pushed and tracked.

## Results

- `jj-concurrent-openspec` → **v0.2.0**; `jj-openspec` now offers `relay`, the
  verify **gate** + auto-archive, a pre-flight **health check**, and the
  **multi-change pipeline**.
- All four OpenSpec changes validated; worker workspaces torn down.
- Docs folded into README/MANUAL and the four removed from `ROADMAP.md`
  (12 → 8 active) by the orchestrator as single doc writer.

**Four agents, one shared file, a deliberate 4-way merge resolved in a handful of
marker edits, submitted as a parent-based PR stack — zero lost work, zero stalls.**
