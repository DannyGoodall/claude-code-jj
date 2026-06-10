## Why

`/jj-absorb` (capability `jj-absorb-fixup`) hard-requires `jj absorb --dry-run` for its preview step, and its preflight reports a clear blocker when that flag is absent. **jj 0.42 ships `jj absorb` but not `--dry-run`** (`jj absorb --dry-run` → `error: unexpected argument '--dry-run' found`), so on the current toolchain `/jj-absorb` cannot complete at all. And because `/jj-pr-fixup` *composes* `/jj-absorb` at its §5 land step, the entire automated amend-after-review loop is blocked too — its live-exercise task (`jj-pr-fixup` 8.2) was validated only up to provisioning and could not exercise absorb-placement or the in-place PR update.

A dry-run is not the only way to make a mutation safe. jj's own `jj absorb --help` points the way: *"The modification made by `jj absorb` can be reviewed by `jj op show -p`."* The operation log already gives jj a reviewable, **fully reversible** mutation surface — the same one `/jj-checkpoint` and `/jj-rewind` (capability `jj-op-checkpoint`) expose. So `/jj-absorb` can offer the same see-the-placement / undo-if-wrong safety on a dry-run-less jj by capturing the pre-absorb operation, running the absorb, reviewing the result via `jj op show -p`, and surfacing a one-command `jj op restore` undo.

## What Changes

- **Capability detection.** `/jj-absorb` SHALL detect whether the installed `jj absorb` supports `--dry-run` (probe `jj absorb --help`) and select its preview mode accordingly.
- **Preview mode (dry-run available)** — unchanged: preview the planned placement with `jj absorb --dry-run`, report it, then run the mutating `jj absorb`; "nothing to absorb" still short-circuits with no mutation.
- **Fallback mode (dry-run unavailable)** — new: record the pre-absorb operation id (a reversible checkpoint), run the mutating `jj absorb`, read the resulting hunk-to-commit placement from `jj op show -p` of the absorb operation, and present that placement **together with the exact one-command undo** (`jj op restore <pre-absorb-op>`) so an unsatisfactory or surprising absorb can be rolled back as a whole.
- **Preflight softened.** A missing `--dry-run` SHALL NO LONGER be a blocker; only a missing `jj absorb` blocks. The skill switches to the fallback instead of refusing.
- **Same post-conditions in both modes.** The orchestrator sees the placement, nothing is silently lost, and an undesired result is recoverable — by not-running (preview) or by op-restore (fallback). Remainder handling (ambiguous hunks left in the working copy) is unchanged; jj leaves un-absorbed hunks in place in both modes.
- **`/jj-pr-fixup` inherits the fix transitively.** Its §5 absorb step now works on a dry-run-less jj, so `jj-pr-fixup` 8.2 becomes closeable. This is a composition benefit, not a separate contract change — `/jj-pr-fixup` calls `/jj-absorb` and gains the new behaviour for free; no delta on the `jj-pr-fixup` capability is required.

## Capabilities

### Modified Capabilities
- `jj-absorb-fixup`: generalize the preview requirement from a hard `jj absorb --dry-run` dependency to a **dry-run-or-op-log-review** choice driven by capability detection, and soften the orchestrator-contract preflight so a missing `--dry-run` selects the op-log review-and-undo fallback rather than reporting a blocker.

## Impact

- **Skill edit**: `plugins/jj-concurrent/skills/jj-absorb/SKILL.md` — add the `--dry-run` capability probe, gate the existing preview path behind it, and add the fallback branch (pre-absorb op capture → `jj absorb` → `jj op show -p` placement read → surfaced `jj op restore` undo). Bump the `jj-concurrent` plugin version.
- **Composition (reuse, not re-derive)**: the checkpoint/restore mechanics are exactly what the `jj-op-checkpoint` capability (`/jj-checkpoint` + `/jj-rewind`) already provides; the fallback SHOULD reuse that op-id-capture + `jj op restore` surface (whether by invoking those skills or by an inline op-id capture for this transient step — see `design.md`), never re-deriving op-log handling.
- **Transitively unblocks** `/jj-pr-fixup` on jj 0.42 — closing the residual `jj-pr-fixup` 8.2 live exercise once this lands.
- **Non-interactive throughout** (`jj … --no-pager`; `jj op show -p` and `jj op restore` are non-interactive); the orchestrator-only / no-bookmark / no-push contract is unchanged.
- No changes to any target project's application code — this only reshapes how `/jj-absorb` previews its own mutation.
