## 1. Skill scaffold and inputs

- [x] 1.1 Create `plugins/jj-concurrent/skills/jj-keep-current/SKILL.md` with the `/jj-keep-current` trigger, orchestrator-role preamble, and a non-interactive command-hygiene note (no interactive `jj resolve`, bounded waits, `--no-pager`).
- [x] 1.2 Define skill inputs: stack reference (tip bookmark or current stack), trunk bookmark (resolved from config/arg, not hardcoded), and re-check loop parameters (poll interval, max attempts) with sane defaults.
- [x] 1.3 Document hard dependencies (`gh` authenticated, colocated jj↔git repo with `origin`) and the orchestrator-only constraint; assert a worker never invokes it.
- [x] 1.4 Bump the `jj-concurrent` plugin version for the new skill.

## 2. CI gate

- [x] 2.1 Implement PR/CI status read via `gh pr checks <ref> --required`, with fallback to all checks when none are required.
- [x] 2.2 Map check states to gate states: failing/errored → `ci-failing`; pending/queued → `ci-pending`; all success → green; zero checks → `ci-missing`.
- [x] 2.3 Ensure `ci-missing` is surfaced explicitly and never folded into a green gate.

## 3. Trunk-movement detection

- [x] 3.1 `jj git fetch` the resolved trunk bookmark and read the fetched trunk tip.
- [x] 3.2 Compare the stack base revision to the fetched trunk tip via a revset comparison.
- [x] 3.3 Implement the no-op fast path: when base equals trunk tip, skip rebase and push and go straight to the CI gate.

## 4. Never-halt auto-rebase

- [x] 4.1 When trunk has moved, run `jj rebase -b <stack-base> -d <trunk-tip>` (always exit 0), reusing the `jj-delegate` "Integration never halts" invariant.
- [x] 4.2 After rebase, inspect the rebased changes for conflicted state and collect conflicted change-ids and file paths.
- [x] 4.3 On any conflict, emit verdict `rebase-conflicted` with the conflicted change-ids and paths, and do NOT push; never invoke interactive `jj resolve` and never auto-resolve.

## 5. Push and re-check loop

- [x] 5.1 After a conflict-free rebase, push the moved bookmark(s) with `jj git push` so the PR rebuilds against the new trunk.
- [x] 5.2 Re-run the CI gate against the new head; while `ci-pending`, poll at the configured interval up to the max attempts, then return the last gate result (bounded, never indefinite).

## 6. Verdict and composition

- [x] 6.1 Emit a single verdict: landable (current + green) or not-landable/hold with a typed reason (`trunk-moved`, `rebase-conflicted`, `ci-failing`, `ci-pending`, `ci-missing`).
- [x] 6.2 Document forward-composition with `/jj-land` (D4): land consults this verdict and lands only on landable; assert no hard dependency on D4 existing or being canonical.
- [x] 6.3 Wire the reconcile-tail prose so `/jj-land` (when present) calls `/jj-keep-current`, documentation/wiring only — no requirement change to `jj-delegate` or any in-flight capability.

## 7. Validation

- [x] 7.1 Run `openspec validate jj-keep-current` and resolve any structural errors.
- [x] 7.2 Verify each spec scenario maps to a verifiable check (fast-path no-op, conflict surfaced+blocked, ci-missing not green, bounded re-check, standalone verdict).
