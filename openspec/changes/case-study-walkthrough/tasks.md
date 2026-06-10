## 1. Scaffold & conventions

- [x] 1.1 Create `docs/case-studies/linkstack-walkthrough.md` with title, a short intro (who Sam is, what `linkstack` is, the repo's three files), and a "how to read this" note explaining the per-section template
- [x] 1.2 State the doc conventions (Requirement → In Claude → 🔧 Skill → 💡 Tip → Under the hood) and the Linear-vs-GitHub rule (Linear = planned-feature agent queue; GitHub = full-time backend + ad-hoc issues)

## 2. Setup

- [x] 2.1 Setup section: `jj git init --colocate`, install the three plugins, restart; introduce the **snapshot + guard hooks** (capability `jj-safety-hooks`) and what they protect

## 3. Part 1 — the everyday loop (foreground · no OpenSpec · no CI)

- [x] 3.1 Dark-mode toggle: foreground Claude edits; **snapshot hook** auto-saves; **`/jj-pr`**; a raw `jj st`/`jj log` peek; **`/jj-land`** single PR with **no CI** (the no-CI land path)
- [x] 3.2 **`/jj-absorb`** — distribute messy review fixes into their downstack commits
- [x] 3.3 **`/jj-pr-fixup`** — read an open PR's review comments, fix, re-push, in one command
- [x] 3.4 **`/jj-checkpoint`** + **`/jj-rewind`** — checkpoint before a risky refactor, roll back when it goes wrong (with a raw `jj op log` peek)
- [x] 3.5 **`/jj-preview`** — run the page in a throwaway workspace to *see* a change before merging
- [x] 3.6 The **guard hook** — a raw `git push` / `rm .jj` is blocked, and why

## 4. Part 2 — going bigger (background workers · OpenSpec)

- [x] 4.1 **`/jj-delegate`** (background) + the **`jj-workspace-worker`** agent; foreground-vs-background explained
- [x] 4.2 **`/jj-fleet`** — one status view of running workers
- [x] 4.3 **`/jj-openspec propose`** — author a spec for a feature worth proposing; review it
- [x] 4.4 **`/jj-openspec apply`** — apply in the background, with the **healthcheck** pre-flight and **gate-verify** auto-archive-on-green
- [x] 4.5 **Fan-out across task groups** (`jj-openspec-fanout`) — split one change across workers, reconcile into one branch
- [x] 4.6 **Multi-change pipeline** (`jj-openspec-pipeline`) — apply a *set* of small changes concurrently
- [x] 4.7 **`/jj-openspec new` + `ff`** — a quick spec'd tweak created and fast-forward-applied in one go
- [x] 4.8 **`/jj-openspec relay`** — draft a proposal → go/no-go gate → apply, in one command
- [x] 4.9 **`/jj-stacked-pr`** — a naturally stacked (two dependent changes) submission

## 5. Part 3 — issues & CI

- [x] 5.1 A community **GitHub issue** → quick ad-hoc fix with **no OpenSpec** → delegate + **`/jj-pr`**
- [x] 5.2 Planned work via **Linear** — the fan-out auto-creates an umbrella + per-worker sub-issues and reconciles reports back (status / four-section summary / human-gate) (`jj-linear`)
- [x] 5.3 **`/jj-from-linear`** — one triaged `ready-for-agent` Linear issue → a dispatched worker
- [x] 5.4 **Add CI** (GitHub Actions: a lint + a tiny JS test) — the no-CI era ends
- [x] 5.5 **`/jj-keep-current`** — rebase the stack onto moved trunk + gate landing on green CI (only meaningful now CI exists)
- [x] 5.6 **`/jj-land` with CI** — wait for green; the **red-check abort** leaves the tail intact

## 6. Appendix — when you grow

- [x] 6.1 **Multi-orchestrator namespacing** + **`/jj-fleet` across sessions** — two Claude sessions in one repo without collisions
- [x] 6.2 **Sparse-workspace partitions** (`--sparse-patterns`) — hard file-ownership when workers would conflict
- [x] 6.3 **Worktree-include provisioning** — declaratively seed gitignored files (e.g. a `.env`) into each workspace
- [x] 6.4 **`/jj-burndown`** — drain a whole Linear board as a bounded concurrent stream

## 7. Closing, cross-links & verification

- [x] 7.1 Closing **cheat-sheet** table: every skill → one-line purpose → the under-the-hood primitive it wraps
- [x] 7.2 Cross-link the walkthrough from `README.md` (docs list) and `MANUAL.md` (a "learn by walkthrough" pointer)
- [x] 7.3 **Coverage matrix**: confirm every capability under `openspec/specs/`, the four OpenSpec modes (propose/apply/new+ff/relay), foreground-vs-background, GitHub-vs-Linear issues, and the CI-late timeline each map to ≥1 section (include the matrix in the doc)
- [x] 7.4 **Template check**: every numbered feature section carries the three highlighted elements (🔧 Skill callout, 💡 Tip callout, Under-the-hood commands)
