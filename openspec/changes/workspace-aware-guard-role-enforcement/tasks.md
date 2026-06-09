## 1. Role detection in the guard

- [ ] 1.1 In `plugins/jj-concurrent/hooks/scripts/jj-guard.sh`, capture the `.jj`-containing directory at the point the existing upward membership walk finds it (e.g. set `jjdir="$dir"` when `[ -e "$dir/.jj" ]` matches), so role can be classified without a second walk.
- [ ] 1.2 Add a cheap, jj-free role classifier after membership is confirmed: `role=orchestrator` when `test -d "$jjdir/repo"`, `role=worker` when `test -f "$jjdir/repo"`, and `role=unknown` otherwise. Use only filesystem type tests; never invoke jj.

## 2. Worker restriction rules

- [ ] 2.1 When (and only when) `role` is `worker`, block `jj bookmark …` using the existing matcher style (`(^|[^[:alnum:]_./-])jj[[:space:]]+bookmark([[:space:]]|$)`), with a message that bookmarks are orchestrator-only and the worker should report and let the orchestrator integrate.
- [ ] 2.2 When `role` is `worker`, block `jj git push` (`(^|[^[:alnum:]_./-])jj[[:space:]]+git[[:space:]]+push([[:space:]]|$)`), with a message that push is orchestrator-only.
- [ ] 2.3 Ensure `orchestrator` and `unknown` roles fall through and ALLOW `jj bookmark …` and `jj git push` (fail open), and that worker commit-shaping commands (`jj new`/`describe`/`squash`/`split`/`rebase`) remain unaffected.

## 3. Documentation

- [ ] 3.1 Update the `jj-guard.sh` header comment that says role rules are "enforced by the worker-agent contract in v0.1.0, not here" to describe the new role-detection + worker-restriction block.

## 4. Verification

- [ ] 4.1 In a real linked workspace (where `.jj/repo` is a regular file), verify the guard blocks `jj bookmark set x` and `jj git push`, and allows `jj new -m …`.
- [ ] 4.2 In the default workspace (where `.jj/repo` is a directory), verify the guard allows `jj bookmark set x` and `jj git push`.
- [ ] 4.3 Confirm the universal floor (raw mutating git, interactive jj, `rm` on `.jj`/`.git`) is still blocked for both roles and that the guard still fails open outside a jj repo.
- [ ] 4.4 Confirm no jj process is spawned by the guard during role detection (e.g. by inspecting the script / dry-running with a stubbed jj on PATH).
