## 1. Skill scaffold in core jj-concurrent

- [ ] 1.1 Create `plugins/jj-concurrent/skills/jj-pr/SKILL.md` with frontmatter (name, description, `/jj-pr` trigger) declaring it an orchestrator-only skill that takes a bookmark argument and optional issue/base/draft flags
- [ ] 1.2 State the preconditions in the skill body: orchestrator role only (never a worker), colocated jj↔git repo with an `origin` remote, `gh` available and authenticated
- [ ] 1.3 Bump `plugins/jj-concurrent/.claude-plugin/plugin.json` version and update its description to mention the push-and-PR step

## 2. Push and one-time tracking

- [ ] 2.1 Implement the dependency preflight: `gh auth status` (and `gh` presence) check that reports a clear blocker without hanging
- [ ] 2.2 Implement tracking detection against `origin` and conditional `jj bookmark track <bookmark>@origin` only when untracked
- [ ] 2.3 Implement the push step `jj git push -b <bookmark> --no-pager`, capturing success vs push-rejected as separable outcomes (no force-push)

## 3. Create-or-update PR via gh

- [ ] 3.1 Implement existing-PR detection keyed on the head branch (`gh pr list --head <bookmark> --state open` / `gh pr view`)
- [ ] 3.2 Implement `gh pr create` (none exists) and `gh pr edit` (one exists) paths with explicit `--title`/`--body-file`/`--head`/`--base` flags, idempotent on re-run
- [ ] 3.3 Return the PR URL plus push/track outcomes in a report-shaped result

## 4. PR body generation

- [ ] 4.1 Implement OpenSpec proposal sourcing: locate `openspec/changes/<change>/proposal.md` and map `## Why` → why, `## What Changes` → what, `## Impact`/benefit → benefit
- [ ] 4.2 Implement commit-message fallback body from `jj log -r <bookmark>` descriptions when no proposal is present, and graceful degradation when proposal headers are missing/odd
- [ ] 4.3 Implement the `Fixes <issue>` line only from an explicit issue argument or an issue reference in the commits; omit when unknown

## 5. Reconcile-tail wiring

- [ ] 5.1 Update the `jj-delegate` skill's reconcile-tail prose to invoke `/jj-pr <bookmark>` as the push-and-PR step
- [ ] 5.2 Update the `jj-openspec` apply-shape reconcile-tail prose to invoke `/jj-pr <bookmark>`

## 6. Validation

- [ ] 6.1 Run `openspec validate jj-github-pr` and resolve any structural errors
- [ ] 6.2 Manually exercise `/jj-pr` against a scratch colocated repo: first-push (untracked) create path, and a re-run update path; confirm idempotence and a missing-`gh` blocker report
