# Tasks — jj-guard-hardening

## 1. jj-repo gating (v0.1.1)

- [x] 1.1 Add a cheap upward `.jj` walk to the guard; fail open (exit 0) when not in a jj repo
- [x] 1.2 Verify: inside a jj repo blocks raw git / allows jj; outside a jj repo all git allowed

## 2. cwd-aware detection (v0.1.2)

- [x] 2.1 Parse a single leading `cd <dir>` (incl. `(cd`, quoted/relative/absolute/`~`) to compute the effective directory; detect `.jj` from there
- [x] 2.2 Verify 6/6: cd-into-jj blocks, cd-out-to-non-jj allows, bare commands judged from cwd, jj always allowed in a jj repo

## 3. Document residual limits

- [x] 3.1 Note in the guard and DESIGN that string-matching catches mentions and `git -C <dir>` slips past; the worker contract is the primary line
