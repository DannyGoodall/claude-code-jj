## 1. Skill scaffold in core jj-concurrent

- [ ] 1.1 Create `plugins/jj-concurrent/skills/jj-absorb/SKILL.md` with frontmatter (name, description, `/jj-absorb` trigger) declaring it an orchestrator-only skill that takes an optional fileset and optional `--into <rev>`/downstack-target argument
- [ ] 1.2 State the preconditions in the skill body: orchestrator role only (never a worker), operates on the orchestrator's own change stack, no bookmark/push/raw-git operations, every command non-interactive (`--no-pager`, no `-i`)
- [ ] 1.3 Bump `plugins/jj-concurrent/.claude-plugin/plugin.json` version and update its description to mention the absorb amend-after-review step

## 2. Preflight and dry-run preview

- [ ] 2.1 Implement the support preflight: confirm the installed `jj` supports `jj absorb` (and `--dry-run`); report a clear blocker without hanging or falling back to another mutating command
- [ ] 2.2 Implement `jj absorb --dry-run --no-pager` (scoped to the optional fileset/target) and capture the planned hunk-to-commit placement
- [ ] 2.3 Implement the "nothing to absorb" path: when the dry-run shows no hunk has a downstack home, report it and skip the mutating run

## 3. Mutating absorb and landing report

- [ ] 3.1 Implement the mutating `jj absorb --no-pager` (scoped to the optional fileset/target), only after the dry-run plan is produced
- [ ] 3.2 Derive the per-hunk landing report by diffing the dry-run plan against the post-run working copy; key each absorbed hunk to its destination change-id and description
- [ ] 3.3 Separate absorbed hunks from the remainder in the report output

## 4. Ambiguous remainder handling

- [ ] 4.1 Detect hunks left in the working copy after the run (the ambiguous remainder)
- [ ] 4.2 Surface each remaining hunk explicitly as needing manual placement, naming `jj squash --into <rev>` (or shaping a fresh change) as the manual option; never drop it or invoke an interactive command

## 5. Reconcile-tail wiring

- [ ] 5.1 Update the `jj-delegate` skill's reconcile-tail prose to invoke `/jj-absorb` as the amend-after-review step when fixes are scattered across the stack

## 6. Validation

- [ ] 6.1 Run `openspec validate jj-absorb-fixup` and resolve any structural errors
- [ ] 6.2 Manually exercise `/jj-absorb` against a scratch jj stack: scatter fixes belonging to two downstack commits plus one ambiguous hunk; confirm the dry-run preview, the per-hunk landing report, that the ambiguous hunk is left in the working copy and reported, and the missing-absorb-support blocker path
