# e2efix — the deleted `cstyle-live/port.txt` fixture behind stage 7

## 1. WHAT the fixture is, WHICH stage, and WHO wrote it (grep, not memory)

- The consumer is `checks/e2e.py` stage 7 (`checks/e2e.py:452-461`): it runs
  `zsh .agents/slop/f64/run-f64.sh`. Stage 7 SKIPs when that script exits 3
  (cold substrate / refusal) or 127 (no zsh) — `SKIP IS NOT PASS`.
- Inside stage 7, `.agents/slop/f64/run-f64.sh:120` calls
  `.agents/slop/f64/repair-dupes.py <in> <out>`. That script's last check is
  **byte-identity of the ported rows against a committed good run**:
  `GOOD = ... / "cstyle-live" / "port.txt"` (`.agents/slop/f64/repair-dupes.py:48`).
  If `GOOD` is absent it prints `absent -- rows vs the recorded good run CANNOT
  be checked` and exits 2; run-f64.sh turns any non-zero repair rc into exit 3
  (`run-f64.sh:126-131`) → e2e stage 7 SKIP.
- What the file must CONTAIN: the stdout of one good `./bin/bend
  tinybendygrad/renderer/cstyle.bend` run — 227 gate rows, 46291 bytes, taken
  at live-tree sha `07ae2766…` (docstring, both repair-dupes.py copies).
- The generator, by grep: `.agents/slop/cstyle-live/run-all.sh`, which writes
  `"$BEND" "$W/tree/.../cstyle.bend" > "$L/port.txt"` where
  `L=$REPO/.agents/slop/cstyle-live`. That directory now holds only
  `run-all.sh`; `port.txt` (and `run-all.log`, whose line 5 `run-f64.sh:97`
  still quotes, now printing an empty sha) were deleted by sweep commit
  `371cc64c9` (`git show 371cc64c9 --name-status`: `D .agents/slop/cstyle-live/port.txt`,
  `D …/run-all.log`, `D …/conversion.tsv`, etc., 2975 paths).
- `checks/repair-dupes.py` is the second copy; it disagreed on the path
  (`parents[1]/cstyle-live`, i.e. repo-root `cstyle-live/`, which does not
  exist either). Nothing outside the f64 copy is live for stage 7.

## 2. DECISION — (a) REGENERATE, because the content is KNOWN, not invented

The generator survives, but re-running it today would be dishonest in two
ways: (i) it writes through `./bin/bend`, which I did NOT run (another unit
holds it); (ii) the live tree's substrate is cold, so a fresh run would
produce an error dump, and making `GOOD` equal to that dump turns the
byte-identity check into `X == X` — the exact failure `e2e.py:99-100` warns
against.

The fixture's own docstring defines it as *the recorded good run*, and that
run is recoverable byte-for-byte from git: `git show
371cc64c9^:.agents/slop/cstyle-live/port.txt` is 46291 bytes, 227 rows with
`py=[` — exactly the documented content. So the restoration is a checkout of
a known artifact, not a guess.

Action:
- Restored at `gates/artifacts/cstyle-live/port.txt` (46291 B, 227 rows,
  sha256 `4ab4cadfc0827c0daa10fed47a3c7116aee08400a41188035b1b9b06299ada53`; the
  `07ae2766…` in the docstring is the tree sha the run was taken at, not the
  file's own sha). Non-swept path, beside the gate ledger per doctrine 1:
  a hand list is not a population; a deleted input is not a precondition.
- Repointed `GOOD` in BOTH copies:
  `.agents/slop/f64/repair-dupes.py:48` →
  `parents[3]/gates/artifacts/cstyle-live/port.txt`;
  `checks/repair-dupes.py:48` →
  `parents[1]/gates/artifacts/cstyle-live/port.txt`.
  Both now resolve to the same file (verified by import above).
- Updated the path mentions in both docstrings and the
  `checks/e2e.py:99-100` comment (was: "DELETED FIXTURE … neither retryable
  nor mine to regenerate" → now names cold substrate as the live cause of
  stage 7's SKIP, and records the fixture's new home).

## 3. VERDICT VOCABULARY — still honest

- `checks/e2e.py:512` `return 4` on any SKIP; `checks/e2e.sh:335` `exit 4`.
  Confirmed by read today.
- Absent-input plants: with `port.txt` moved away, both copies resolve
  `GOOD.exists() == False` and take the exit-2 `absent … CANNOT be checked`
  branch (smoke-tested by moving the file and restoring it; the bend-dependent
  caller path up to that branch requires `./bin/bend`, held by another unit,
  and was NOT executed — exit-2 → run-f64 exit 3 → stage 7 SKIP, so an absent
  fixture can never become a PASS).
- Stage 7's two SKIPs remain SKIP and cannot be laundered: rc 3 (run-f64
  refusal) and rc 127 (no zsh) at `e2e.py:453-458`, both counted in `SKIPS`,
  both making the gate print `PASS WITH N SKIP(S)` and exit 4.

## NOT fixed here (reported, not swept under)

- `.agents/slop/cstyle-live/run-all.log` is also gone; `run-f64.sh:97` now
  prints an empty quoted sha. Cosmetic; recoverable from the same git commit
  (`git show 371cc64c9^:.agents/slop/cstyle-live/run-all.log`) if wanted.
- With the substrate still cold, stage 7 will SKIP at the substrate check
  regardless of this fix; restoring the fixture removes the *second*,
  avoidable skip/refusal so that whenever the substrate warms again, the
  f64 lane compares against a real recorded good run rather than refusing
  on a missing file.
- Live plant run of `run-f64.sh` (which would exercise GOOD end-to-end)
  requires `./bin/bend` — not run, per the unit exclusivity rule.
