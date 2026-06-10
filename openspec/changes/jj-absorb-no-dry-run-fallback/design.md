# Design — jj-absorb-no-dry-run-fallback

## Context

`/jj-absorb` was specified against a jj that ships `jj absorb --dry-run`. The
installed toolchain (jj 0.42.0) has `jj absorb` but not `--dry-run`, so the
skill's "preview first" requirement and its preflight blocker make the skill
unrunnable here — and `/jj-pr-fixup`, which composes `/jj-absorb`, inherits the
block. This change makes the *preview* requirement adapt to the installed jj
while preserving the actual safety property the preview existed to give:
**the orchestrator sees where hunks landed and can back the whole thing out.**

The original requirement conflated two things: (1) *previewing* placement, and
(2) doing so *before* the mutation. jj's first-class operation log means (2) is
not load-bearing — a mutation you can atomically undo is as safe as one you
preview first. `jj absorb --help` says as much: review with `jj op show -p`.

## Goals / non-goals

- **Goal**: `/jj-absorb` runs on jj with *or* without `absorb --dry-run`, with
  equivalent see-placement / undo-if-wrong safety, and transitively unblocks
  `/jj-pr-fixup`.
- **Goal**: reuse the existing `jj-op-checkpoint` op-log surface; do not
  re-derive op handling.
- **Non-goal**: changing the dry-run path's behaviour when `--dry-run` exists.
- **Non-goal**: any change to remainder handling, the orchestrator-role
  contract, the fileset / `--into` arguments, or the per-hunk landing report's
  shape (only its *source* differs in fallback mode — `jj op show -p` instead of
  the dry-run output).

## Decisions

### 1. Capability detection: probe `jj absorb --help`

Detect support once per run by probing the help text rather than attempting a
`--dry-run` and parsing the error:

```bash
if jj absorb --help 2>&1 | grep -q -- '--dry-run'; then DRYRUN=1; else DRYRUN=0; fi
```

A help-probe is deterministic, side-effect-free, and does not depend on the
specific error string of a failed `--dry-run` attempt (which can change between
jj releases). `jj absorb` presence itself is the existing hard preflight; only
the `--dry-run` sub-capability is newly optional.

### 2. Fallback mechanics: checkpoint → absorb → review → surfaced undo

In fallback mode the skill:

1. **Captures the pre-absorb operation id** — the reversible save point. This is
   exactly `jj-op-checkpoint`'s job. Prefer an **inline capture**
   (`jj op log -n1 --no-graph -T 'id.short()'`, or `--at-op` semantics) over
   writing a manifest checkpoint, because this save point is *transient* — it
   exists only for the duration of one absorb and should not litter the
   agent-plan manifest or require a label. (`/jj-checkpoint` remains the right
   tool when an operator wants a *named, persisted* save point across a larger
   risky step; this transient one does not.) The skill MAY instead call
   `/jj-checkpoint <auto-label>` + `/jj-rewind` if reuse is preferred — both are
   acceptable; the spec requires only that the undo be a real `jj op restore` to
   the captured pre-absorb op.
2. **Runs the mutating `jj absorb`** (with the same fileset / `--into` scoping).
3. **Reads the resulting placement** from `jj op show -p` of the absorb
   operation — the diff of that op shows which downstack commits changed, which
   is the same hunk→commit mapping the dry-run would have previewed, read after
   the fact. Map it to the existing per-hunk landing report (destination
   change-id + description first line) on a best-effort basis; when the op diff
   cannot be attributed cleanly, report the raw `jj op show -p` summary rather
   than inventing a mapping.
4. **Surfaces the one-command undo** — print the exact
   `jj op restore <pre-absorb-op>` so the operator (or a calling skill like
   `/jj-pr-fixup`) can roll the whole absorb back atomically if the placement is
   wrong. The skill does not auto-undo; it presents the result + the escape
   hatch, mirroring how the dry-run path lets the operator decline before
   mutating.

### 3. "Nothing to absorb" in fallback mode

With `--dry-run` the skill detects "nothing absorbable" *before* mutating. In
fallback mode it runs `jj absorb`; if absorb moved nothing (no hunk had a
downstack home), the operation is effectively a no-op — the working copy is
unchanged and the captured checkpoint need never be used. The skill reports
"nothing to absorb" by observing that `jj op show -p` of the absorb op is empty
(no commits changed), and notes the no-op explicitly. This matches the dry-run
path's outcome without a pre-mutation gate.

### 4. Reporting parity

The per-hunk landing report (destination change-id + description, absorbed vs.
left-in-working-copy) is unchanged in shape. Source differs by mode:
- dry-run mode: from the `jj absorb --dry-run` output (as today);
- fallback mode: from `jj op show -p` of the absorb operation, plus the
  surfaced `jj op restore` undo line.

### 5. Remainder handling unchanged

`jj absorb` leaves un-absorbed hunks in the working copy in *both* modes, so the
"ambiguous remainder left for manual placement" requirement is untouched and
needs no delta — it already describes jj's default behaviour, which the fallback
also relies on.

## Transitive effect on `/jj-pr-fixup`

`/jj-pr-fixup` §5 invokes `/jj-absorb` to land the worker's fixes. Once
`/jj-absorb` runs in fallback mode, §5 completes on jj 0.42, so the full
amend-after-review loop (read comments → dispatch → absorb → update PR) runs
end-to-end and `jj-pr-fixup` 8.2 can be exercised and ticked. No change to the
`jj-pr-fixup` capability or skill is required for the behaviour; the skill MAY
add a one-line note that the absorb step now works on dry-run-less jj, but that
is documentation, not contract.

## Risks

- **Placement attribution from `jj op show -p` is best-effort.** The op diff is
  authoritative about *which commits changed* but mapping individual
  working-copy hunks to destinations is less direct than a dry-run's explicit
  plan. Mitigation: report the raw op diff when attribution is ambiguous; the
  `jj op restore` undo makes a mis-read non-destructive.
- **Two code paths to maintain.** Mitigation: the fallback is the more general
  path (capture → mutate → review → undo); when jj everywhere ships `--dry-run`
  the preview path could later be retired, but both are kept now for parity and
  to avoid changing behaviour where `--dry-run` exists.
