## Why

After a review pass, fixes are typically scattered across the working copy even though each hunk logically belongs to a different commit deeper in the stack. In Graphite-style git workflows this was the amend-after-review loop (edit, then amend each commit). jj has a native answer — `jj absorb` distributes each working-copy hunk into the downstack commit that last touched those lines — but the orchestrator has no skill that runs it deliberately, previews the placement, and reports where each hunk landed. Without it, the reconcile/amend step the `jj-delegate` tail relies on stays manual and opaque.

## What Changes

- A new orchestrator skill **`/jj-absorb`** that, given working-copy changes (optionally scoped to a fileset or a downstack target), runs `jj absorb` to distribute each hunk into the downstack commit it belongs to — the jj analog of the amend-after-review loop.
- **Dry-run preview first**: the skill SHALL run `jj absorb --dry-run` before any mutating run and surface the planned placement (which hunk → which commit) so the orchestrator can confirm before commits move.
- **Per-hunk landing report**: after the real `jj absorb`, the skill reports where each absorbed hunk landed, keyed to the destination change-id/description, by diffing the dry-run plan against the resulting working copy.
- **Unabsorbed remainder is left in place**: any hunk with no unambiguous downstack home is left in the working copy (jj's default behaviour) and called out explicitly for manual placement (`jj squash --into <rev>` or a fresh change) rather than being silently dropped or force-fitted.
- **Orchestrator-role contract**: the skill operates only on the orchestrator's own change stack; it moves no bookmarks, performs no push, and runs every command non-interactively (`--no-pager`, no `-i`).
- **Reconcile-tail integration**: `/jj-absorb` is the canonical amend step the `jj-delegate` reconcile tail can call after a review pass, replacing ad-hoc "amend each commit" instructions with one skill.

## Capabilities

### New Capabilities
- `jj-absorb-fixup`: the `/jj-absorb` orchestrator skill — preview with `jj absorb --dry-run`, run `jj absorb` to distribute working-copy hunks into their downstack commits, report where each hunk landed, and leave any ambiguous hunk in the working copy for manual placement, all non-interactively and within the orchestrator role.

### Modified Capabilities
<!-- None. jj-delegate already describes a reconcile/amend tail abstractly; this change supplies the concrete absorb skill that tail can reference without changing jj-delegate's existing requirements. The reference is one-directional (this capability points at jj-delegate), so no delta spec is required. -->

## Impact

- New skill `plugins/jj-concurrent/skills/jj-absorb/SKILL.md` in the **core `jj-concurrent` plugin**; bumps that plugin's version. No new plugin.
- Hard dependency on a `jj` version that ships `jj absorb` (and `jj absorb --dry-run`); the skill SHALL preflight-check and report a clear blocker when absent.
- Reconcile-tail prose in the `jj-delegate` skill points at `/jj-absorb` as the amend-after-review step (documentation/wiring only, no behaviour change to its spec).
- No changes to any target project's application code — this orchestrates the orchestrator's own commit stack, it ships no application behaviour.
