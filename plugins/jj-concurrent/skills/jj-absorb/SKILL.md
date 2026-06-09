---
name: jj-absorb
description: |
  Distribute scattered working-copy fixes into the downstack commits they
  belong to — the jj analog of the amend-after-review loop — in one
  orchestrator step. After a review pass leaves many small hunks in one working
  copy, each logically belonging to a different commit deeper in the stack,
  `/jj-absorb` previews the placement with `jj absorb --dry-run`, runs the
  mutating `jj absorb` to move each hunk into the closest downstack commit that
  last touched those lines, reports where each hunk landed (keyed to the
  destination change-id + description), and leaves any ambiguous hunk in the
  working copy with a named manual escape hatch. Accepts an optional fileset and
  optional `--into <rev>`/downstack-target to scope which changes are absorbed.
  Triggers: /jj-absorb, "absorb these fixes", "amend each commit after review",
  "distribute working-copy hunks downstack". The reconcile-tail amend step for
  /jj-delegate. Orchestrator-only (reshapes the orchestrator's own stack); never
  invoked inside a worker, moves no bookmarks, performs no push, runs every
  command non-interactively (`--no-pager`, no `-i`). Requires a jj that ships
  `jj absorb` and `jj absorb --dry-run`.
metadata:
  version: "0.1.0"
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
- **`jj absorb` (with `--dry-run`) must be supported** — preflight first (§1).

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

## 1. Support preflight (fail fast, never hang, never improvise)

Before any absorb, confirm the installed `jj` ships `jj absorb` **and** its
`--dry-run` flag — both are relatively recent. Probe non-interactively:

```bash
jj absorb --help --no-pager >/dev/null 2>&1 || echo "BLOCKER: jj absorb unsupported"
jj absorb --help --no-pager 2>&1 | grep -q -- '--dry-run' || echo "BLOCKER: jj absorb --dry-run unsupported"
```

If `jj absorb` is absent, **report a clear blocker and stop** — do not fall back
to a different mutating command (e.g. a guessed `jj squash`). If `jj absorb`
exists but `--dry-run` does not, that is equally a blocker for this skill, whose
contract is preview-before-mutate: report it and stop rather than running an
unpreviewed mutating absorb. `--help` returns promptly and never prompts, so
this cannot hang.

## 2. Dry-run preview (always first, before any commits move)

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
the source of truth for the report.

### 2a. Nothing-to-absorb path

If the dry-run shows **no hunk has a downstack home** (every hunk would be left
in the working copy, or the working copy is empty / conflicted with nothing
placeable), report **"nothing to absorb"** and **STOP** — do **not** run a
mutating `jj absorb`. There is nothing to amend; surfacing that cleanly is the
correct outcome.

## 3. Mutating absorb (only after the dry-run plan exists)

Only once §2 has produced a plan with at least one placeable hunk, run the real
absorb with the *same* scope:

```bash
jj absorb --no-pager [--from <rev>] [--into <rev>] [<fileset>...]
```

jj moves each unambiguous hunk into its destination commit and leaves the rest
in the source (working-copy) commit. If the source commit ends up empty and has
no description, jj abandons it — that is expected.

## 4. Per-hunk landing report (derived, not scraped)

Derive the report by **diffing the §2 dry-run plan against the post-run working
copy** rather than parsing the mutating run's stdout — this is robust to absorb
output-format drift across jj versions and cleanly separates absorbed from
remaining hunks.

1. Inspect the working copy after the run:

   ```bash
   jj diff --ignore-working-copy --no-pager        # what remains in @
   jj log --ignore-working-copy --no-pager -r 'mutable()'   # destinations + descriptions
   ```

2. A hunk that was in the dry-run plan **and is no longer in the working copy**
   was **absorbed** — to the rev the plan named. Look up that rev's change-id
   and description (`jj log -r <rev> -T 'change_id.short() ++ " " ++ description.first_line()'`)
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

## 5. Ambiguous remainder (left in place, never dropped or force-fitted)

After the run, detect the hunks still in the working copy — the **ambiguous
remainder** (no unambiguous downstack home, so jj left them in the source, which
is jj's default and correct behaviour):

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

- **preflight** (absorb + dry-run supported / blocker).
- **plan** (the dry-run hunk→commit placement, or "nothing to absorb").
- **absorbed** hunks, each keyed to destination change-id + description (§4).
- **remaining (manual)** hunks, each with its named placement option (§5).

## Failure modes (each reported, none improvised)

- **`jj absorb` / `--dry-run` unsupported** → up-front blocker, nothing run; no
  fallback to a different mutating command (§1).
- **Nothing to absorb** → reported cleanly, no mutating run (§2a).
- **Surprising placement (multiple downstack commits touched the same lines)** →
  the mandatory dry-run preview exposes the target before history moves (§2).
- **Ambiguous remainder** → left in the working copy and surfaced with a named
  manual option; never dropped or force-fitted (§5).
- **A jj command itself hangs** (a known jj rough edge in heavy use) → do not
  retry blindly and NEVER delete `.jj`; `jj op log` / `jj op restore` is the
  orchestrator-only recovery surface. (Absorb is reversible via `jj op restore`
  if a placement turns out wrong.)

## Where this is called

`/jj-absorb` is the canonical **amend-after-review** step of the reconcile tail:

- [`jj-delegate`](../jj-delegate/SKILL.md) §5 calls `/jj-absorb` after a review
  pass leaves scattered fixes across a worker's integrated stack — it distributes
  the fixes into their downstack commits and reports the landings, before the
  push-and-PR step [`/jj-pr <bookmark>`](../jj-pr/SKILL.md).
