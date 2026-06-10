---
name: jj-release
description: |
  Cut a GitHub release for the repository at a single commit in one orchestrator
  step — the "ship a milestone" step the jj→GitHub lifecycle lacks (the reconcile
  tail ends at /jj-land; nothing then publishes a release). Relay-shaped: a
  PREPARE phase resolves the target commit, runs a CI gate off that commit's
  check-runs/combined status (not `gh pr checks` — the PR is merged by release
  time), proposes a SemVer bump from conventional commits since the last tag
  (`feat`→minor, `fix`→patch, breaking/`!`→major) that the human ALWAYS confirms
  or overrides (asking outright on a first release or non-conventional history),
  generates release notes from commits/PRs editable in-conversation, defaults
  0.x to `--prerelease` ON, and runs an optional opaque project-supplied
  artifacts command; then a single human GO/NO-GO gate; then a PUBLISH phase that
  on "go" creates the release server-side via `gh release create <tag>
  --target <sha>` (tag-only `vMAJOR.MINOR.PATCH` versioning — no manifest is
  edited; the tag is created on the remote, sidestepping jj 0.42's missing tag
  creation and the guard hook's block on raw `git tag`). Refuses (does not
  overwrite) when a release for the tag already exists. Triggers: /jj-release,
  "cut a release", "ship a GitHub release", "release this commit", "tag and
  publish a release". Orchestrator-only (never invoked inside a worker);
  non-interactive (`--no-pager`, no `-i`, no editor — human input arrives only
  through the relay gate); makes no commit, edits no file, force-pushes nothing.
  Requires a colocated jj↔git repo with an `origin` remote and `gh` authenticated
  with release-create scope. Ships in the jj-lifecycle plugin and is usable
  without any concurrency or OpenSpec plugin.
metadata:
  version: "0.1.0"
  author: outfitter-style
---

# jj-release — cut a GitHub release for the repo at a commit

You are the **orchestrator**. The jj→GitHub lifecycle has a push step (`/jj-pr`),
a land step (`/jj-land`) — and then stops. Work gets merged, but nothing cuts a
GitHub **release**: pick a version, lay down a tag, write notes, decide
pre-release, publish. That is a recurring, error-prone manual chore. This skill
is the missing "ship a milestone" step — it cuts a GitHub release for the whole
repository at one commit, with a single human go/no-go gate guarding an immutable
public artifact.

This skill is deliberately **universal**: it owns the generic
version→tag→notes→CI-gate→publish core and knows nothing about how any project is
built or versioned. It is **tag-only** — the git tag *is* the version; it never
edits `plugin.json` / `package.json` / `Cargo.toml` or any other manifest. It
ships **no** build logic; producing release artifacts is the repo owner's job,
attached through an optional opaque hook (§7).

Substrate knowledge (jj command surface, revsets, templates, non-interactive
rules, output formats) comes from the installed `jj-vcs` skill — defer to it for
jj command detail; this skill owns only the release choreography. `jj` is used
read-only here (target/commit/tag inspection); the mutating step is `gh`.

## Preconditions (verify, don't assume)

- **Orchestrator role only.** A release tags trunk, touches refs, and publishes a
  public artifact — none of which the worker contract permits. NEVER invoke
  `/jj-release` inside a worker. It runs in the primary/default workspace, after
  any integration is complete. In a delegated flow the orchestrator releases
  once, never a worker.
- **Colocated jj↔git repo with an `origin` remote.** The release is created on
  GitHub via `gh`, which resolves the repo from the `origin` remote. If there is
  no `origin` remote, stop and report — this skill does not create remotes.
- **`gh` available and authenticated with release-create scope.** Every step that
  reads checks, lists releases, and creates the release is `gh`; a missing,
  unauthenticated, or under-scoped `gh` is a reported blocker checked up front
  (§1), never an improvised workaround.
- **Non-interactive substrate.** Every `jj` / `git` / `gh` command runs
  non-interactively: `jj … --no-pager --ignore-working-copy`, `gh` with explicit
  flags, **no `-i`/`--interactive`, no spawned editor**. The ONLY human
  interaction point is the relay gate (§8). Notes are passed via `--notes-file`,
  never an editor.
- **Tag-only, no manifest mutation.** The skill creates a tag and a release and
  changes **no file in the working tree** — it never bumps a version field and
  never commits. Repo manifest versions may diverge from the release tag; that is
  acceptable and explicitly allowed (it neither reads them for mutation nor
  reconciles them).

## Arguments

```
/jj-release [<version>] [--target <rev>] [--notes-file <path>] \
            [--prerelease | --no-prerelease] [--draft] \
            [--artifacts-cmd "<command>"] [--trunk <branch>]
```

- **`<version>`** (optional) — the version to release, with or without a leading
  `v` (normalised to `vMAJOR.MINOR.PATCH`). If omitted, the skill proposes one
  (§5) and the human confirms at the gate. Supplying it does **not** skip the
  gate — it is still confirmed.
- **`--target <rev>`** (optional) — the commit to release (a change id / commit
  id / bookmark). Defaults to trunk HEAD (§3). Resolved to a concrete sha.
- **`--notes-file <path>`** (optional) — pre-written notes; otherwise notes are
  generated (§6) and editable in conversation.
- **`--prerelease` / `--no-prerelease`** (optional) — force the pre-release flag,
  overriding the 0.x default (§7). Also overridable conversationally at the gate.
- **`--draft`** (optional) — create the release as a GitHub draft preview rather
  than publishing it live (§6.2 / §9).
- **`--artifacts-cmd "<command>"`** (optional) — the opaque project-supplied
  command that produces release asset files (§7). If omitted, the skill may also
  ask conversationally at prepare time; with neither, the release is source-only.
- **`--trunk <branch>`** (optional) — the trunk branch whose HEAD is the default
  target and whose name resolves the default last-tag baseline. Defaults to the
  repo's resolved `trunk()` branch.

## 1. Dependency preflight (fail fast, never hang)

Before any work, confirm the publish step can run. A missing dependency stops the
whole run up front rather than half-preparing a release:

```bash
command -v gh >/dev/null 2>&1 || echo "BLOCKER: gh not installed"
gh auth status 2>&1            # non-zero / "not logged into" ⇒ blocker
gh repo view --json nameWithOwner --jq .nameWithOwner 2>&1   # confirms origin + repo resolution
```

If `gh` is absent, unauthenticated, or under-scoped (the release-create call later
returns a scope error), **report a clear blocker and do nothing else** — do not
prepare notes, do not create a tag, and do not hang on an interactive auth
prompt (`gh auth status` is non-interactive and returns promptly). Resolve
`<owner>/<repo>` once here; every later `gh api repos/<owner>/<repo>/…` reuses it.
If there is no `origin`/repo resolution, that too is an up-front blocker.

## 2. Detect existing releases / tags early (refuse on collision, find the baseline)

List existing tags and releases once — this both finds the **baseline** for the
version proposal (§5) and notes (§6), and lets the skill **refuse** a collision
before doing any work:

```bash
gh release list --limit 100 --json tagName,isDraft,isPrerelease,createdAt 2>&1
git tag --list 'v*' 2>&1                 # read-only git is allowed
```

- **No releases and no `v*` tags** → this is a **first release** (§5 first-release
  path; §6 generates notes over all history).
- **Releases/tags present** → the most recent SemVer tag is the **baseline** the
  bump is proposed from (§5) and the notes range starts at (§6).
- Once a candidate version is known (§5), check that exact tag: if a release
  already exists for `v<version>`, the skill **refuses** — see §10. (Doing the
  collision check here too lets a `--version`-supplied run fail fast.)

## 3. Resolve the target commit (default trunk HEAD)

The release is cut from a single commit. Default to trunk HEAD; honour
`--target`:

```bash
# default target = trunk HEAD; resolve to a concrete commit sha (read-only jj)
jj log -r '<trunk-or-target>' --ignore-working-copy --no-pager --no-graph \
  -T 'commit_id ++ "\n"'
```

Resolve `<target>` to a concrete commit **sha** (`gh release create --target`
accepts a sha or branch; a sha is unambiguous and is what the CI gate keys on).
The target sha is what §4 gates, §10 tags, and the report (§11) records. If the
target does not resolve to a single commit, report and stop — do not guess.

## 4. CI gate on the **target commit** (not the PR)

Refuse to publish unless the required checks on the **target commit** are green.
By release time the originating PR is merged, so PR-scoped queries
(`gh pr checks`) no longer apply — read the **commit's** check-runs and combined
status directly:

```bash
gh api "repos/<owner>/<repo>/commits/<sha>/check-runs" \
  --jq '.check_runs[] | {name, status, conclusion}'
gh api "repos/<owner>/<repo>/commits/<sha>/status" \
  --jq '{state, statuses: [.statuses[] | {context, state}]}'
```

Verdict (v1 = "all green"):

- **Green** — every check-run on the target commit has `status=completed` with
  `conclusion=success` (treat `neutral`/`skipped` as non-blocking), AND the
  combined status `state` is `success` (or no legacy statuses exist) → permit the
  flow to proceed to the gate.
- **Red** — any check-run concluded `failure`/`cancelled`/`timed_out`, or the
  combined status `state=failure` → **refuse to publish**, name the failing
  check(s), and note that a manual release outside the plugin is the user's
  prerogative. Do not poll-wait on a red check.
- **Pending** — any required check is still `queued`/`in_progress`, or combined
  status `state=pending` → **refuse to publish for now**, name the pending
  check(s), and report that the release can be retried once checks conclude. (v1
  does not poll indefinitely; a bounded re-check is acceptable but a long wait is
  not — a release is not time-critical the way a land is.)

The skill reads the check state GitHub reports; it does not define what "required"
means and never bypasses a non-success verdict. (Branch-protection "required
contexts" are branch-scoped, fuzzier on a bare commit; v1 treats green as "all
check-runs on the target concluded success with none failing/pending" and surfaces
the actual check list at the gate.)

## 5. Propose the version (always confirmed; ask outright when there's no basis)

Tag format is **`vMAJOR.MINOR.PATCH`** — normalise any supplied/confirmed version
to that shape; reject anything that is not valid SemVer.

### 5a. First release — ask, no default

When §2 found **no prior tag/release**, there is nothing to bump from. **Do NOT
assume a default** (not `v0.1.0`, not `v1.0.0`). Ask the user for the initial
version explicitly and proceed with it after confirmation at the gate.

### 5b. Auto-propose a SemVer bump from conventional commits — then ALWAYS confirm

When there **is** a baseline tag, read the commits since it and derive a proposed
bump from conventional-commit prefixes:

```bash
# commits since the last tag, read-only (jj revset: baseline tag .. target)
jj log -r '<baseline-tag>..<target>' --ignore-working-copy --no-pager --no-graph \
  -T 'description.first_line() ++ "\n"'
```

- a breaking change (a `!` after the type, or a `BREAKING CHANGE:` footer) → **major**
- any `feat:` → **minor**
- otherwise any `fix:` → **patch**

Propose the resulting version (e.g. baseline `v0.7.1` + a `feat:` → `v0.8.0`) and
**ALWAYS require the human to confirm or override** it at the gate (§8). The skill
**never** publishes an unconfirmed version — even when `<version>` was passed as
an argument, that is the *proposal*, still confirmed.

### 5c. Non-conventional history — don't guess, ask

When the commits since the baseline are **not** parseable as conventional commits
(no recognisable `type:` prefixes), the skill does **not** guess a bump. It
reports that history is non-conventional and **asks the user for the version
directly** (same as 5a, but with the baseline shown for context).

## 6. Generate release notes (editable in conversation)

Generate notes from the commits/PRs merged since the baseline tag (over all
history on a first release):

```bash
# commit subjects since the baseline, oldest-first, read-only
jj log -r '<baseline-tag>..<target>' --ignore-working-copy --no-pager \
  --no-graph --reversed -T 'description.first_line() ++ "\n"'
# (optionally enrich with merged PR titles/numbers since the baseline)
gh pr list --state merged --base <trunk> --limit 100 \
  --json number,title,mergedAt --jq '.[] | "#\(.number) \(.title)"'
```

Compose a readable changelog (grouped by `feat`/`fix`/other where the prefixes
allow it) into a notes string.

### 6.1 In-conversation editing before the gate

Present the generated notes and let the user **amend them in conversation** —
add a "Highlights" section, drop a line, reword. On each requested change,
**regenerate and re-present** the notes, then carry the final text to the gate.
Notes are written to a **temp `--notes-file`** for publish — never an editor.

### 6.2 Optional draft preview (rendered safety net)

If the user wants to see the release rendered on GitHub before going live, the
skill MAY create it as a **draft** (`--draft`, §10), report the draft URL, and
only publish (un-draft) on a subsequent "go". A draft is a preview, not a
publication — it is still gated.

## 7. Pre-release default and the optional artifacts hook

### 7.1 0.x → `--prerelease` ON by default (plugin policy)

GitHub does not infer pre-release from the version string. This skill's **policy**
(reflecting SemVer's "0.x is unstable") is: when the confirmed version is in the
`0.x` range (major component `0`), default the `--prerelease` flag **ON**; for
`1.x`+ default it **OFF**. Either way the flag is shown in the gate summary and is
**overridable** there (or via `--prerelease`/`--no-prerelease`). Document it as
policy so users are not surprised.

### 7.2 Optional opaque artifacts hook (owner-owned, no build logic)

The skill provides an optional seam for attaching assets and **ships no build
logic** — producing artifacts is the repo owner's obligation.

- **No artifacts command** (none supplied via `--artifacts-cmd` and none given
  conversationally) → a **source-only** release (GitHub's auto-generated source
  archive), no attached assets.
- **An artifacts command supplied** → run it as an opaque command, collect the
  files it emits (the command names/produces the output paths), **list them in
  the gate summary**, and upload them to the release on publish (§10) — **without
  interpreting how they were built**. The skill's obligation ends at "run the
  hook + upload its output". If the command fails, report it as a blocker at the
  gate (no partial-asset publish).

## 8. The relay gate (single human go/no-go)

Having done all computable work — target resolved, CI gate passed, version
proposed, notes generated/edited, pre-release decided, assets gathered — present
**one** summary and wait for an explicit go/no-go. Publish **only** on "go":

```
RELEASE SUMMARY — review before publishing
  version:     v0.8.0            (proposed: minor bump from v0.7.1 via feat:)
  target:      <sha>  (main HEAD)
  CI gate:     green — 3/3 checks passed (lint, test, json)
  pre-release: ON   (0.x policy — say "not a pre-release" to override)
  draft:       no
  assets:      none (source-only)   |   or: dist/foo.tgz, dist/foo.sha256
  notes:       <rendered notes preview>
Publish this release? (go / no)
```

- **"go"** → proceed to PUBLISH (§10).
- **"no" / "cancel"** → make **no tag, no release, no remote change**, and report
  that nothing was published. The gate is the only commit point; nothing
  irreversible happens before it.

The skill SHALL NOT publish without passing through this gate, even when every
argument was supplied on the command line.

## 9. (PUBLISH) Re-confirm no collision immediately before creating

Immediately before creating the release, re-check the exact tag (the version may
have been changed at the gate): see §10's refusal. This guards against a release
for the chosen tag having appeared between §2 and the gate.

## 10. Publish — server-side tag creation; refuse on an existing release

### 10.1 Refuse to overwrite an existing release

If a GitHub release already **exists** for the target tag, **refuse** — tags are
immutable once depended upon. Unlike `/jj-pr`'s create-or-update, `/jj-release`
does **not** mutate a published artifact:

```bash
gh release view "v<version>" --json tagName 2>/dev/null \
  && echo "REFUSE: release v<version> already exists — choose a new version"
```

Report the collision clearly, do not modify the existing release, and ask for a
new version (loop back to §5). This is a refusal, not a failure.

### 10.2 Create the release (server-side tag, no local `git tag`)

On "go" and no collision, create the release. The **tag is created on the remote**
at the target sha as part of release creation — this sidesteps both jj 0.42's
missing native tag-creation and the guard hook's block on raw `git tag`:

```bash
gh release create "v<version>" \
  --target "<sha>" \
  --title "v<version>" \
  --notes-file "<notes-file>" \
  [--prerelease] \
  [--draft] \
  [<asset-file> ...]              # only when an artifacts hook produced files
```

- `--target <sha>` creates the tag `v<version>` server-side at the target commit.
- `--prerelease` is passed iff the gate's pre-release flag is ON.
- `--draft` is passed for a draft preview (§6.2); a later "go" un-drafts via
  `gh release edit "v<version>" --draft=false`.
- Asset files are appended only when §7.2 produced them.

Confirm success by the created release rather than only the exit code:

```bash
gh release view "v<version>" --json url,isDraft,isPrerelease,tagName \
  --jq '{url, isDraft, isPrerelease, tagName}'
```

The skill SHALL NOT pass any force/overwrite flag and SHALL NOT delete or
re-create an existing tag.

## 11. Report (report-shaped result)

Return a compact result:

- **version / tag** published (`v<version>`).
- **target** sha (and the branch it was the HEAD of).
- **CI verdict** at the gate (green; the checks that passed) — or the refusal
  reason if it never reached the gate.
- **pre-release** and **draft** flags as published.
- **assets** uploaded (the file list, or "source-only").
- **release URL** — or, when nothing was published, the explicit outcome
  (`declined-at-gate` / `refused-existing-release` / `ci-not-green` / `blocker:…`).

Example shape:

```
released: v0.8.0
target:   <sha>  (main HEAD)
CI:       green (lint, test, json)
flags:    pre-release=on  draft=no
assets:   source-only
url:      https://github.com/org/repo/releases/tag/v0.8.0
```

Declined / refused example:

```
not released: refused — release v0.7.1 already exists (tags are immutable)
action:       choose a new version and re-run /jj-release
```

## Failure modes (each reported, none improvised)

- **`gh` absent / unauthenticated / under-scoped** → up-front blocker, nothing
  prepared or published (§1).
- **No `origin` / repo not resolvable** → up-front blocker; the skill does not
  create remotes (§1).
- **Target does not resolve to one commit** → reported, stop; never guess a
  target (§3).
- **CI red or pending on the target commit** → refuse to publish, name the
  check(s), note the manual-release prerogative; do not poll a red check forever
  (§4).
- **First release / non-conventional history** → ask for the version outright, no
  guessed default (§5a / §5c).
- **Unconfirmed version** → never published; the gate confirmation is mandatory
  even for an argument-supplied version (§5b / §8).
- **Artifacts command fails** → reported at the gate; no partial-asset publish
  (§7.2).
- **User declines at the gate** → no tag, no release, no remote change (§8).
- **Release already exists for the tag** → refuse, do not overwrite, ask for a
  new version (§10.1) — a refusal, not a silent no-op.
- **A jj command itself hangs** → do not retry blindly and NEVER delete `.jj`;
  `jj op log` / `jj op restore` is the orchestrator-only recovery surface.

## Where this is called

`/jj-release` is the **ship a milestone** step that sits *after* the reconcile
tail, not inside it:

- The tail's submit/land steps —
  [`jj-pr`](../../../jj-concurrent/skills/jj-pr/SKILL.md) and
  [`jj-land`](../../../jj-concurrent/skills/jj-land/SKILL.md) (in the
  `jj-concurrent` plugin) — push and merge work. `/jj-release` then cuts a
  release for a chosen trunk commit once milestones accumulate. It depends on
  **none** of them: it reads commit-level CI, not PR CI, precisely because the
  PRs are already merged by release time.
- It has **no dependency** on any concurrency or OpenSpec machinery and ships in
  its own `jj-lifecycle` plugin, so a release-only user can install just this
  plugin and use `/jj-release` without `jj-concurrent`,
  `jj-concurrent-openspec`, or `jj-concurrent-linear` present.
- It defers all jj command detail to the installed `jj-vcs` skill and owns only
  the release choreography; the artifacts hook is opaque, mirroring
  `jj-delegate`'s "the skill owns the choreography; the workload is the
  workload's business".
