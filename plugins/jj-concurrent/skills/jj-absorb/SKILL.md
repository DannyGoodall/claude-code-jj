---
name: jj-absorb
description: |
  Distribute scattered working-copy fixes into the downstack commits they
  belong to — the jj analog of the amend-after-review loop. Previews placement
  (`jj absorb --dry-run` where available, else an op-log review-and-undo
  fallback), runs `jj absorb`, reports where each hunk landed, and leaves
  ambiguous hunks in the working copy with a manual escape hatch. Accepts an
  optional fileset and `--into <rev>` to scope the absorb. Triggers: /jj-
  absorb, "absorb these fixes", "amend each commit after review", "distribute
  working-copy hunks downstack". Requires a jj that ships `jj absorb`;
  orchestrator-only.
metadata:
  version: "0.2.0"
  author: outfitter-style
---

# jj-absorb — amend-after-review by distributing hunks downstack

You are the **orchestrator**. After a review pass your working copy often holds
many small fixes, each of which logically belongs to a *different* commit deeper
in the stack. The Graphite predecessor handled this with an amend-after-review
loop (find the right commit, amend it, repeat). jj's native equivalent is
`jj absorb`: it splits each working-copy hunk and moves it into the closest
mutable downstack commit that last modified those same lines. This skill is the
deliberate wrapper around that primitive — it **previews** the placement, **runs**
the absorb, and **reports** where each hunk landed, leaving any ambiguous hunk in
the working copy for you to place by hand.

The preview adapts to the installed jj. Where `jj absorb --dry-run` exists, the
skill previews *before* mutating (§2). Where it does not (e.g. jj 0.42, which
ships `jj absorb` without `--dry-run`), the skill gives the **same safety** the
other way round — it records a reversible op-log checkpoint, runs the absorb,
reviews the result via `jj op show -p`, and surfaces a one-command
`jj op restore` undo (§3). Either way you can see the hunk-to-commit placement
and back the whole thing out; a missing `--dry-run` is never a blocker.

Substrate knowledge (jj command surface, revsets, filesets, non-interactive
rules, output formats) comes from the installed `jj-vcs` skill — defer to it for
jj command detail; this skill owns only the preview → absorb → report
choreography.

## Preconditions (verify, don't assume)

- **Orchestrator role only.** This skill reshapes the orchestrator's *own*
  change stack. NEVER invoke `/jj-absorb` inside a worker — workers shape only
  their own workspace commits and never reach across the stack. It runs in the
  primary/default workspace.
- **Operates on the orchestrator's own stack only.** `jj absorb` defaults to
  source `@` and destination `mutable()`; it touches only the orchestrator's
  mutable downstack commits. It does not reach into a worker's workspace.
- **No bookmark / push / raw-git operations.** This skill moves no bookmarks,
  runs no `jj git push`, and runs no raw mutating git. It only redistributes
  working-copy hunks among local commits via `jj absorb`. Pushing is `/jj-pr`'s
  job and happens later in the reconcile tail.
- **Every command non-interactive.** Always `--no-pager`; never `-i` /
  `--interactive`; never spawn an editor. Reads use `--ignore-working-copy`.
  The skill never opens an interactive hunk picker — ambiguous hunks are left
  for deliberate manual placement (see §5), never force-fitted.
- **`jj absorb` must be supported** — preflight first (§1). The `--dry-run` flag
  is *optional*: its absence selects the op-log review-and-undo fallback (§3),
  not a blocker.

## Arguments

```
/jj-absorb [<fileset>...] [--into <rev>] [--from <rev>]
```

- **`<fileset>...`** (optional) — limit absorb to hunks matching these paths
  (jj fileset syntax). Hunks outside the fileset stay untouched in the working
  copy. Omit to consider the whole working copy.
- **`--into <rev>`** (optional) — restrict the destination to this downstack
  target / revset (jj's `-t/--into`, alias `--to`); only ancestors of the
  source are considered. Omit to let jj choose among all `mutable()` ancestors.
- **`--from <rev>`** (optional) — source revision to absorb from (jj's
  `-f/--from`); defaults to `@` (the working-copy commit).

Default behaviour is whole-working-copy absorb (`--from @`, `--into mutable()`),
with the fileset and target purely optional scopes.

## 1. Support preflight & mode selection (fail fast, never hang, never improvise)

Before any absorb, confirm the installed `jj` ships `jj absorb`, then detect
whether it also ships `--dry-run` — that detection *selects the mode*, it does
not gate the skill. Probe non-interactively:

```bash
jj absorb --help --no-pager >/dev/null 2>&1 || echo "BLOCKER: jj absorb unsupported"
if jj absorb --help --no-pager 2>&1 | grep -q -- '--dry-run'; then
  MODE=dry-run     # §2: preview before mutating
else
  MODE=fallback    # §3: checkpoint → mutate → review via op show -p → surfaced undo
fi
```

- If **`jj absorb` is absent**, report a clear blocker and **stop** — do not fall
  back to a different mutating command (e.g. a guessed `jj squash`). This is the
  only hard preflight blocker.
- If **`jj absorb` exists but `--dry-run` does not**, this is **not** a blocker —
  select `MODE=fallback` (§3). The skill still gives see-the-placement /
  undo-if-wrong safety, via the operation log instead of a pre-run preview.

`--help` returns promptly and never prompts, so this cannot hang. Use the
selected mode for §2 **or** §3 below; §4–§6 are shared.

## 2. Dry-run mode — preview first, then mutate (`MODE=dry-run`)

Run the dry-run, scoped to the optional fileset/target, and capture the plan:

```bash
jj absorb --dry-run --no-pager [--from <rev>] [--into <rev>] [<fileset>...]
```

The dry-run reports which hunk *would* land in which destination revision
without moving anything. Surface this **planned hunk-to-commit placement** to
the user so the plan can be confirmed before history changes — absorb can land a
hunk in a surprising ancestor when several downstack commits touched the same
lines, and the preview is the confirmation point.

Record the plan as a map of `hunk (path + line range) → destination rev` for use
in the landing report (§4). This dry-run plan, not the mutating run's stdout, is
the source of truth for the report in this mode.

### 2a. Nothing-to-absorb path

If the dry-run shows **no hunk has a downstack home** (every hunk would be left
in the working copy, or the working copy is empty / conflicted with nothing
placeable), report **"nothing to absorb"** and **STOP** — do **not** run a
mutating `jj absorb`. There is nothing to amend; surfacing that cleanly is the
correct outcome.

### 2b. Mutating absorb (only after the dry-run plan exists)

Only once §2 has produced a plan with at least one placeable hunk, run the real
absorb with the *same* scope:

```bash
jj absorb --no-pager [--from <rev>] [--into <rev>] [<fileset>...]
```

jj moves each unambiguous hunk into its destination commit and leaves the rest
in the source (working-copy) commit. If the source commit ends up empty and has
no description, jj abandons it — that is expected. Proceed to the shared landing
report (§4).

## 3. Fallback mode — checkpoint, mutate, review, surface undo (`MODE=fallback`)

When `--dry-run` is unavailable, the placement cannot be previewed *before* the
run — so make it **reviewable and reversible after** the run instead. jj's
operation log makes the whole absorb a single, atomically-undoable operation;
`jj absorb --help` itself points here ("The modification made by `jj absorb` can
be reviewed by `jj op show -p`").

### 3a. Capture the pre-absorb operation (the reversible checkpoint)

Record the current operation id **before** mutating, so the entire absorb can be
rolled back as one unit:

```bash
PRE_OP=$(jj op log --no-pager --no-graph -n1 -T 'id.short()')
```

This is the same op-log save point `/jj-checkpoint` records; for this transient,
single-step use an inline capture is enough (no named manifest checkpoint
needed). When an operator wants a *named, persisted* save point spanning a larger
risky sequence, `/jj-checkpoint <label>` + `/jj-rewind` are the right tools and
either satisfies the contract — what matters is that the undo is a real
`jj op restore` to `PRE_OP`.

### 3b. Run the mutating absorb

```bash
jj absorb --no-pager [--from <rev>] [--into <rev>] [<fileset>...]
```

Same scoping arguments as dry-run mode. jj distributes each unambiguous hunk and
leaves the remainder in the working copy (§5), exactly as in §2b.

### 3c. Review the placement via the operation log

Read what the absorb operation actually did — which downstack commits it changed
— and use it as the source of truth for the landing report (§4) in this mode:

```bash
jj op show -p --no-pager @          # the diff of the absorb operation just run
```

Map the changed commits to the per-hunk landing report (§4). When the op diff
cannot be attributed to individual hunks cleanly, report the raw `jj op show -p`
summary rather than inventing a mapping — the undo (§3d) keeps a mis-read
non-destructive.

### 3d. Surface the one-command undo (do NOT auto-undo)

Present the placement **together with** the exact command that reverses the whole
absorb, so the operator (or a calling skill like `/jj-pr-fixup`) can back it out
if the placement is wrong:

```
undo this absorb:  jj op restore <PRE_OP>
```

Mirroring how dry-run mode lets the operator decline *before* mutating, fallback
mode presents the result and the escape hatch *after* — it never auto-restores.

### 3e. Nothing-to-absorb path (post-hoc)

If `jj absorb` moved nothing (no hunk had a downstack home), `jj op show -p` of
the absorb op shows no commit changed and the working copy is unchanged. Report
**"nothing to absorb"**, note the no-op, and the captured `PRE_OP` simply never
needs restoring.

## 4. Per-hunk landing report (derived, not scraped)

Derive the report from the mode's placement source — the **§2 dry-run plan**
(dry-run mode) or the **§3c `jj op show -p` diff** (fallback mode) — against the
post-run working copy, rather than parsing the mutating run's stdout. This is
robust to absorb output-format drift across jj versions and cleanly separates
absorbed from remaining hunks.

1. Inspect the working copy after the run:

   ```bash
   jj diff --ignore-working-copy --no-pager        # what remains in @
   jj log --ignore-working-copy --no-pager -r 'mutable()'   # destinations + descriptions
   ```

2. A hunk that the placement source named **and that is no longer in the working
   copy** was **absorbed** — to the rev named. Look up that rev's change-id and
   description (`jj log -r <rev> -T 'change_id.short() ++ " " ++ description.first_line()'`)
   to key the report.
3. A hunk that **remains in the working copy** is part of the remainder (§5).

Report each **absorbed hunk** keyed to its **destination change-id + that
change's description first line**, e.g.:

```
absorbed:
  src/auth.ts (lines 40-47)   → kostkqrq  feat: validate session token
  src/auth.ts (lines 88-91)   → kostkqrq  feat: validate session token
  README config note (12-14)  → nvrnonuw  docs: document the config flag
```

**Separate the absorbed hunks from the remainder** in the output — the report
has two clearly labelled sections (`absorbed:` and `remaining (manual):`, §5).
The report shape is identical in both modes; only its source differs.

## 5. Ambiguous remainder (left in place, never dropped or force-fitted)

After the run, detect the hunks still in the working copy — the **ambiguous
remainder** (no unambiguous downstack home, so jj left them in the source, which
is jj's default and correct behaviour, in both modes):

```bash
jj diff --ignore-working-copy --no-pager        # everything still in @ after absorb
```

For **each** remaining hunk, surface it explicitly as **needing manual
placement**. Do **not** silently drop it, do **not** force-fit it into a guessed
commit, and do **not** invoke any interactive command to place it. Name the
manual options:

- `jj squash --into <rev> <fileset>` (non-interactively, with an explicit
  fileset + `-m`) to land the hunk into a chosen downstack commit, or
- shape a **fresh change** for it (`jj new -m "…"` / `jj describe -m "…"`) when
  it does not belong downstack at all.

```
remaining (manual):
  src/util.ts (lines 5-9) — touched by two downstack commits; ambiguous.
    place with:  jj squash --into <rev> 'src/util.ts'   (or shape a fresh change)
```

Forcing an ambiguous hunk into a guessed commit is exactly the silent-mistake
class the orchestrator contract forbids — leaving it visible and naming the
escape hatch is the contract-correct behaviour.

## 6. Report (report-shaped result)

Return a compact result the reconcile tail can surface:

- **preflight / mode** (`jj absorb` supported; `dry-run` or `fallback` mode).
- **plan** (the dry-run hunk→commit placement, the fallback `jj op show -p`
  placement, or "nothing to absorb").
- **absorbed** hunks, each keyed to destination change-id + description (§4).
- **remaining (manual)** hunks, each with its named placement option (§5).
- **undo** (fallback mode only) — the exact `jj op restore <PRE_OP>` that
  reverses the whole absorb.

## Failure modes (each reported, none improvised)

- **`jj absorb` unsupported** → up-front blocker, nothing run; no fallback to a
  different mutating command (§1).
- **`jj absorb --dry-run` unsupported** → *not* a blocker; selects fallback mode
  (§3), which keeps see-placement / undo-if-wrong safety via the op log (§1).
- **Nothing to absorb** → reported cleanly; no lingering mutation (dry-run §2a
  short-circuits before mutating; fallback §3e observes the no-op).
- **Surprising placement (multiple downstack commits touched the same lines)** →
  exposed by the dry-run preview before history moves (§2), or by `jj op show -p`
  with a one-command `jj op restore` undo after (§3).
- **Ambiguous remainder** → left in the working copy and surfaced with a named
  manual option; never dropped or force-fitted (§5).
- **A jj command itself hangs** (a known jj rough edge in heavy use) → do not
  retry blindly and NEVER delete `.jj`; `jj op log` / `jj op restore` is the
  orchestrator-only recovery surface. (Absorb is reversible via `jj op restore`
  if a placement turns out wrong — the basis of fallback mode.)

## Where this is called

`/jj-absorb` is the canonical **amend-after-review** step of the reconcile tail:

- [`jj-delegate`](../jj-delegate/SKILL.md) §5 calls `/jj-absorb` after a review
  pass leaves scattered fixes across a worker's integrated stack — it distributes
  the fixes into their downstack commits and reports the landings, before the
  push-and-PR step [`/jj-pr <bookmark>`](../jj-pr/SKILL.md).
- [`jj-pr-fixup`](../jj-pr-fixup/SKILL.md) §5 composes `/jj-absorb` to land a
  PR's review fixes into their owning commits — and inherits this fallback, so
  the amend-after-review loop runs on a jj without `absorb --dry-run` too.
