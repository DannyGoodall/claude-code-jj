## 1. Capability detection

- [x] 1.1 In `plugins/jj-concurrent/skills/jj-absorb/SKILL.md`, add a `--dry-run` capability probe (`jj absorb --help` grepped for `--dry-run`) that resolves once per run to a `dry-run` vs `fallback` mode, and document it as the mode selector
- [x] 1.2 Keep the existing hard preflight that `jj absorb` itself is present (a missing `jj absorb` is still a blocker); scope the blocker to absorb-absence only, not `--dry-run`-absence

## 2. Preview mode (dry-run available) — preserved

- [x] 2.1 Gate the existing "preview with `jj absorb --dry-run` then mutate" choreography behind the `dry-run` mode so its behaviour is unchanged where `--dry-run` exists
- [x] 2.2 Keep the "nothing to absorb → report and do not mutate" short-circuit in dry-run mode

## 3. Fallback mode (dry-run unavailable)

- [x] 3.1 Capture the pre-absorb operation id as a reversible checkpoint (inline `jj op log -n1` capture for this transient step; document that `/jj-checkpoint` + `/jj-rewind` are the named/persisted alternative and that either satisfies the contract, the requirement being a real `jj op restore` to the captured op)
- [x] 3.2 Run the mutating `jj absorb` (honouring the same fileset / `--into` scoping arguments)
- [x] 3.3 Read the resulting hunk-to-commit placement from `jj op show -p` of the absorb operation and map it to the existing per-hunk landing report (destination change-id + description first line), falling back to the raw op diff when attribution is ambiguous
- [x] 3.4 Surface the exact one-command undo `jj op restore <pre-absorb-op>`; do NOT auto-undo — present placement + undo and leave the decision to the operator/caller
- [x] 3.5 Handle the fallback "nothing to absorb" case: an empty `jj op show -p` for the absorb op ⇒ report "nothing to absorb", note the no-op, checkpoint never restored

## 4. Preflight softening

- [x] 4.1 Remove the "report a blocker when `jj absorb --dry-run` is unsupported" behaviour; a missing `--dry-run` selects the fallback path instead
- [x] 4.2 Update the skill's frontmatter description and `Requires:`/preconditions prose so it no longer claims a hard `jj absorb --dry-run` dependency (requires `jj absorb`; `--dry-run` optional, selects preview vs fallback)

## 5. Reporting parity

- [x] 5.1 Ensure the per-hunk landing report shape (absorbed hunks keyed to destination change-id + description, separately from hunks left in the working copy) is identical in both modes, differing only in source (dry-run output vs `jj op show -p`)
- [x] 5.2 Confirm remainder handling is unchanged (un-absorbed hunks remain in the working copy in both modes; the "ambiguous remainder" requirement needs no edit)

## 6. Composition note for /jj-pr-fixup (documentation only)

- [x] 6.1 Add a one-line note to `jj-pr-fixup/SKILL.md` §5 that the absorb step now completes on a jj without `absorb --dry-run` (transitive benefit; no contract change to the `jj-pr-fixup` capability)

## 7. Plugin + docs

- [x] 7.1 Bump `plugins/jj-concurrent/.claude-plugin/plugin.json` version and update its description so the `/jj-absorb` clause reflects the dry-run-or-op-log-review behaviour
- [x] 7.2 Update README/MANUAL `/jj-absorb` rows/sections to describe the fallback and drop any claim that `jj absorb --dry-run` is required; remove the "jj 0.42 lacks `absorb --dry-run` ⇒ /jj-absorb blocks" gotcha (now handled), replacing it with a note that the skill adapts
- [ ] 7.3 Update ROADMAP (move this out of the active backlog on archive)

## 8. Validation

- [x] 8.1 `openspec validate jj-absorb-no-dry-run-fallback` passes
- [x] 8.2 Exercise `/jj-absorb` fallback mode live on jj 0.42: scattered working-copy hunks across ≥2 downstack commits → confirm capture → absorb → `jj op show -p` placement report → surfaced `jj op restore` undo, and that the undo restores the pre-absorb state exactly
- [x] 8.3 Re-run the `jj-pr-fixup` 8.2 live exercise end-to-end (now that §5 absorb completes on jj 0.42): confirm absorb-placement into the reviewer's commit and the in-place PR update — and tick `jj-pr-fixup` 8.2 once green
- [x] 8.4 Confirm the dry-run path is untouched where `--dry-run` exists (mode-selection test: simulate/inspect both branches)
