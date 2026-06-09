## Why

`/jj-land` was exercised live for the first time landing a real 3-PR stack (#11–#13) in this colocated jj↔git repo, and surfaced a cleanup bug specific to colocation. In a colocated repo git HEAD is **detached** — jj owns the refs, not git branches — so `gh pr merge <n> --squash --delete-branch` fails its **local**-branch cleanup step with `could not determine current branch: failed to run git: not on any branch`. Two real consequences observed:

1. `gh pr merge` **exits non-zero even though the remote merge succeeded** (the PR reached `state=MERGED`). A caller trusting the exit code would wrongly conclude the merge failed and abort the rest of the stack.
2. The error aborts the command **before `--delete-branch` deletes the remote head branch**, leaving every merged PR's remote branch as a **straggler** on `origin` (confirmed: `chore/archive-v020-binding`, `chore/archive-v030`, `chore/archive-v050` all survived their merges and had to be deleted by hand).

Separately, `/jj-land`'s §5 cleanup only deletes **local jj bookmarks** — it never deletes remote branches at all, so even without the error there is no remote-branch cleanup. The net effect is a land that looks like it failed and leaves remote litter behind.

## What Changes

- `/jj-land` determines a PR's merge result from its **state** (`gh pr view <pr> --json state` → `MERGED`), **not** from `gh pr merge`'s exit code — the local-branch cleanup error is non-fatal to the merge and must not abort the stack.
- `/jj-land` **stops relying on `gh pr merge --delete-branch`** for branch removal in a colocated repo (its local step fails and aborts the server-side delete). The merge step drops `--delete-branch`.
- §5 cleanup becomes an explicit, **merged-only, three-part** pass per landed change: delete the **local jj bookmark**, delete the **remote head branch** (e.g. `gh api -X DELETE repos/<owner>/<repo>/git/refs/heads/<branch>`), and forget the **linked workspace** (via jj-delegate Teardown) when one exists — so no stragglers remain on `origin`.
- A **gotcha note** documents the detached-HEAD `gh pr merge` behaviour under colocated jj.

All steps stay non-interactive, force-free, orchestrator-only; never `--admin`; never touch un-merged PRs or their branches.

## Capabilities

### Modified Capabilities
- `jj-land`: the merge step keys success on PR state (not exit code) and drops `--delete-branch`; the cleanup step gains explicit merged-only remote-head-branch deletion alongside the existing local-bookmark and workspace-forget steps.

## Impact

- Spec/skill: `plugins/jj-concurrent/skills/jj-land/SKILL.md` (§4 merge, §5 cleanup, gotchas).
- **Sequencing:** the `jj-land` capability is not yet canonical (the `jj-land` change is unarchived pending its own `7.2`). This change's delta should be synced after `jj-land` archives; apply order is `jj-land` → `jj-land-colocated-cleanup`.
- Discovered landing PRs #11–#13; the same colocated detached-HEAD behaviour is worth noting wherever `gh pr merge --delete-branch` is used.
