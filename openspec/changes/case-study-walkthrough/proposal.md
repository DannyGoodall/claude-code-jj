## Why

The repo's docs are **reference + records**: `README` / `MANUAL` / `DESIGN` / `JJ_OVERVIEW` explain the components, and the two existing case studies are dated point-in-time records of specific fan-out exercises. There is **no single narrative tutorial** that walks a beginner — a "vibe coder" who understands jj, GitHub, Linear, and OpenSpec only *conceptually* — through **every feature** of all three plugins on **one simple repo**, showing exactly what they type in Claude and the complexity the plugin abstracts away.

This change adds that walkthrough: a long, **illustrative** (hand-authored, not executed) case study in which one person builds one tiny web app and, in doing so, touches every skill, hook, agent, OpenSpec mode, and Linear/GitHub integration the plugins provide.

## What Changes

- Add `docs/case-studies/linkstack-walkthrough.md`. A vibe coder, **Sam**, builds **`linkstack`** — a one-page "link-in-bio" web app (`index.html` + `app.js` + `style.css`) — and exercises every plugin feature along the way.
- **Structure**: a **main spine** of everyday features, then a **"When you grow" appendix** for advanced ones, then a closing cheat-sheet.
- **Per-section template** (every feature section): *The requirement* → *In Claude* (a short `you:`/`claude:` exchange) → a highlighted **🔧 Skill** callout → a highlighted **💡 Tip** callout → an **Under the hood** block of the equivalent `jj` / `gh` / Linear-MCP commands.
- The narrative deliberately covers: work **with and without** OpenSpec; Claude in the **foreground and as background workers**; **GitHub full-time** (issues + PRs) and **Linear occasionally** (so both GitHub *and* Linear issues appear); **large chunks with no CI**, then **CI added near the end**; and **occasional raw `jj`** on the command line for inspection/recovery.
- OpenSpec is shown in **propose**, **apply**, and **new + ff (fast-forward apply)** modes (plus **relay**), and some changes are made **outside OpenSpec** (no spec impact) to show that path too.
- A stated **Linear-vs-GitHub rule** keeps the split non-arbitrary: GitHub issues = lightweight/ad-hoc reports + all PR tracking; Linear = the planned-feature work queue dispatched to agents.
- **Cross-links**: add the walkthrough to the docs list in `README.md` and a "learn by walkthrough" pointer in `MANUAL.md`.

## Capabilities

### Added Capabilities
- `walkthrough-doc`: the verifiable contract for the walkthrough document — complete feature coverage (with a coverage matrix), the consistent per-section template (Skill / Tip / Under-the-hood), with-and-without-OpenSpec and foreground-and-background coverage, the GitHub-full-time / Linear-occasional split with both issue types, the CI-introduced-late timeline, and the illustrative-not-executed constraint.

This is otherwise a **documentation-only** change: it adds a narrative doc plus two cross-links and changes no plugin skill/hook/agent and no version. The `walkthrough-doc` capability exists purely to make the document's contract checkable via `openspec verify` (OpenSpec requires every change to carry at least one delta).

## Impact

- **New file**: `docs/case-studies/linkstack-walkthrough.md` (long; ~1,500–2,200 lines).
- **Edits**: `README.md` (docs list), `MANUAL.md` (walkthrough pointer).
- **No code/skill/spec/version change.** No real GitHub repo or Linear board is created — all commands and outputs are illustrative; the sample app's code appears as inline snippets only, not as real files in this repo.
- **Coverage is contractual** (see `tasks.md` task 7.3): every capability under `openspec/specs/`, the four OpenSpec modes, foreground-vs-background, GitHub-vs-Linear issues, and the CI-late timeline must each map to at least one section.
