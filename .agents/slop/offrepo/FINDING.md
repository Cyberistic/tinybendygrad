# OFF-REPO ROOTS: the twelve, re-measured after the `resolve_root` fix

Everything below is a MEASUREMENT or a DIFF. Nothing here is a reading of a constant.
Re-measured 2026-10-06 with two instruments that share no regex:
`.agents/slop/offrepo/where.py` (imports each file and reads the value the FILE computed) and
`.agents/slop/offrepo/plants.py` (the two columns).

## THE COUNT: 12 -> 1, and the 1 is NOT MINE

`gates/gates-pop.py` re-run after the eleven fixes: `1 resolve outside the repo`, and it is
`gates/gates-pop.py` ITSELF, which belongs to `gendirs`. **Its own root is CORRECT**:
`gates/gates-pop.py:64-65` is `HERE = Path(__file__).resolve().parent` / `ROOT = HERE.parent`,
which resolves to the repo root (MEASURED, `where.py`). Its finding is a **FALSE POSITIVE of the
class the brief already fixed once**: `ROOT_INLINE` matched the hunted line at `:571` and `:783`,
which are **STRING LITERALS inside `plants()` -- synthetic fixture content**, and `code_of()`
strips comments and docstrings but not string literals. `gates/gates-pop.py` has **zero
executable `sys.path.insert` calls** (AST-measured: `EXECUTABLE sys.path.insert calls: NONE`).
That is a fourth instance of "the discriminator is a literal rather than a shape", and the file
is not mine to fix. **Declared, not fixed, with the named consequence: the instrument's own
clause III reports 1 false and therefore cannot be used to certify that this count is 0.**

## THE ELEVEN, AND THE ANSWER EACH ONE TOOK

`3f0e70ff1` (2026-10-04, the "103 one-off `.sh` DELETED / 100 DUPLICATES REMOVED" cleanup) MOVED
all eleven out of `.agents/slop/<lane>/` into `checks/`, one level shallower, and carried the
`parents[N]` constant across in every case. Provenance measured per file with
`git show 3f0e70ff1^:<predecessor>`. **Answer 1 for all eleven: fix the depth, add `refuse()`.**
None needed answer 2 (no dead `sys.path` line survived except `both-census.py`'s, which was
live-but-wrong), none needed answer 3 (`parents[2]` at `checks/` is `/Users/cyberistic/src`,
which holds only `tries/` and `tries-2026-07-10-*` -- there is no `tinygrad`, no `graphcmp`, no
`tinybendygrad` there to reach for), and none was dead (see the caller counts).

| file | was | reaches now | runs now |
|---|---|---|---|
| `checks/both-census.py` | inline `sys.path.insert(HERE.parents[2])` -> `/Users/cyberistic/src` | repo root | **YES** (77-op denominator, measured) |
| `checks/gate.py` | `parents[2]` -> `/Users/cyberistic/src` | repo root | refuses rc 3 on a swept input |
| `checks/gate_norm.py` | `parents[2]` | repo root | **YES** |
| `checks/jsfix_gate.py` | `parents[2]` | repo root | **YES** (this one never raised -- it reported on a tree that does not exist) |
| `checks/nvrows-deadrow-gate.py` | `Path(__file__).resolve().parents[3]` -> `/Users/cyberistic/src` | repo root | **YES** |
| `checks/oracle_f64.py` | `Path(__file__).resolve().parents[3]` | repo root | **YES** |
| `checks/dup-census.py` | `parents[2]` AND `SLOP = HERE.parent` (both stale) | repo root + real `.agents/slop` | refuses rc 3 on `eq-census2.py` |
| `checks/nl-gate.py` | `parents[2]` AND `HERE.parent/"rebase-gate.py"` | repo root + real `.agents/slop` | refuses rc 3 on `nl-oracle.py` |
| `checks/nl-gate-noguard.py` | same, same commit | repo root + real `.agents/slop` | refuses rc 3 on `nl-oracle.py` |
| `checks/rn-gate.py` | `parents[2]` AND a `HERE`/`HERE.parent` search for two readers | repo root + real `.agents/slop` | refuses rc 3 on `eq-census2.py` |
| `checks/cl-port-gate.py` | `parents[3]` | repo root | refuses rc 2 on `clangshim/oracle.py` |

**Five are refused, on inputs the `371cc64c9` sweep took with it** --
`.agents/slop/eq/eq-census2.py`, `.agents/slop/nl/nl-oracle.py`,
`.agents/slop/clangshim/{oracle.py,fixture.h,libclang-ffi.c}`, and `checks/drive.mjs`. Every
refusal names the path AND the commit that removed it (`371cc64c9^:<path>` is recoverable).
**A refusal that names its absent input IS the correct output, and is not a passing gate.**

## THE PAIR FINDING, STATED PLAINLY

**A COPY IS NOT A MOVE, AND THE FIX LANDED ON ONE OF EACH.**

- `checks/both-census.py` and `checks/census.py` were the SAME FILE, byte-identical, at
  `3f0e70ff1^` (MEASURED: `diff` reports no difference for `both-census.py`; `census.py` differs
  only by the fix). `census.py` got `parents[0]` + `refuse()` + two tracked markers.
  `both-census.py` did not, and kept both dead `sys.path.insert` lines.
- `checks/nl-gate.py` and `checks/nl-gate-noguard.py` are a pair by construction -- the second's
  own docstring says it is "THE `nir_llvmir` GATE AS IT WAS, and the reason `nl-gate.py` exists."
  Both kept `parents[2]` and both had `HERE.parent/"rebase-gate.py"`; both are fixed here and now
  agree on the spelling, which the noguard copy's comment says they must.

The class is not a miscomputed depth. It is **a constant moved with a file and the fix applied to
one copy**. Four prior instances in this project, one per file (`abi4_gate.py`, `abi_gate.py`,
`census.py`, `hermetic-census.py`) -- and the three pre-existing pairs (`census.py`/
`hermetic-census.py` vs `both-census.py`, `abi_gate`/`abi4_gate` vs the ungated `abi4` copies in
`.agents/slop/abi4check/`) show the same shape. **The lesson that generalises: a fix applied to a
named file does not apply to its twin, and nothing in the tree says how many twins a file has.**

## WHO CALLS EACH, COUNTED

Two methods, no shared regex: AST string literals + `tokenize` (method A), and a raw text scan
whose discriminator is the FILENAME WITH ITS EXTENSION (method B). `.agents/slop/offrepo/callers.py`.

**MEASURED correction to the method:** the first version searched the bare stem `gate` and
counted **249 code files and 324 `.bend`/`.sh` files** as callers of `checks/gate.py` -- every
`.bend` in the tree contains the word "gate". That is `ORACLE`-by-basename in its purest form.
The probe itself was then counted as a caller of all twelve, because it names them. Both are
fixed; the numbers below are from the corrected run.

| file | code callers (name in a literal) | prose/named-only |
|---|---|---|
| `both-census.py` | 4 (`checks/census.py`, `checks/hermetic-census.py`, `.agents/slop/hermetic/audit-hermetic.py`, `gates/gendirs.py` -- prose in a docstring) | 13 |
| `cl-port-gate.py` | 2 (both under `.agents/slop/`, neither is a live gate) | 13 |
| `dup-census.py` | **0** | 11 |
| `gate.py` | 9 (`checks/e2e.py`, `checks/repro-paths.py`, 7 under `.agents/slop/`) | 21 |
| `gate_norm.py` | 1 (`.agents/slop/norm/canon.py`) | 11 |
| `jsfix_gate.py` | 3 (`checks/abi_gate.py`, `checks/abi4_gate.py` -- which assert on its exit code) | 18 |
| `nl-gate-noguard.py` | **0** | 5 |
| `nl-gate.py` | 2 (`checks/dup-gate.py`, `checks/nl-gate-noguard.py`) | 11 |
| `nvrows-deadrow-gate.py` | 0 code, 1 shell (`checks/sweep.py`, prose) | 9 |
| `oracle_f64.py` | 0 code, 3 shell (`checks/run-f64.sh`, `.agents/slop/f64/run-f64.sh`) | 10 |
| `rn-gate.py` | **0** | 10 |
| `gates-pop.py` | 1 (`gates/gendirs.py`, prose -- not mine) | 3 |

**NOTE, MEASURED AFTER THE FIRST COUNT:** a second pass picked up `gates/gendirs.py` naming
`both-census.py` and `gates-pop.py`. Every occurrence is inside a DOCSTRING
(`gendirs.py:6,123,152,250,492,601,633,697`) -- it is another instrument citing this work, not
calling it. Recorded because a caller count that grows between two runs of the same script is
exactly the kind of drift that teaches a reader to distrust the number.

**Answer 5 (delete the dead file) was MEASURED and REJECTED for all eleven**: four have zero code
callers but are each an input to another live instrument or are referenced by a gate that asserts
on them -- `jsfix_gate.py`'s exit code is asserted by `checks/abi4_gate.py:541`, and
`both-census.py` is LOADED BY PATH by `checks/hermetic-census.py:84` for `ops_of`. The three
with literally nothing (`dup-census.py`, `nl-gate-noguard.py`, `rn-gate.py`) each carry a
handful of prose references and a live-but-refusing state; deleting a gate is not a root fix and
would change what `gates-pop.py` clause I measures. **None deleted.**

## THE TWO COLUMNS, PER FILE

`.agents/slop/offrepo/plants.py`, run twice in each direction. **Column 1 is a discriminator on
the MESSAGE, not on the exit code**: five of eleven exit 3 and that is a correct refusal on a
swept input, so "did it run" would report five false failures. Column 2 has two independent ways
(A: the whole `checks/` directory copied one level deeper, keeping siblings; B: a bare copy in an
empty tree whose markers sit one level ABOVE it).

**ALL 11 GREEN on column 1. ALL 22 column-2 runs RED, each naming the directory it reached.**

```
checks/both-census.py           col1 PASS rc0   col2A RED rc3 names .../deeper   col2B RED rc3 names .../deeper
checks/cl-port-gate.py          col1 PASS rc2   col2A RED rc2 names .../deeper   col2B RED rc2 names .../deeper
checks/dup-census.py            col1 PASS rc3   col2A RED rc3 names .../deeper   col2B RED rc3 names .../deeper
checks/gate.py                  col1 PASS rc3   col2A RED rc3 names .../deeper   col2B RED rc3 names .../deeper
checks/gate_norm.py             col1 PASS rc0   col2A RED rc3 names .../deeper   col2B RED rc3 names .../deeper
checks/jsfix_gate.py            col1 PASS rc0   col2A RED rc3 names .../deeper   col2B RED rc3 names .../deeper
checks/nl-gate-noguard.py       col1 PASS rc3   col2A RED rc3 names .../deeper   col2B RED rc3 names .../deeper
checks/nl-gate.py               col1 PASS rc3   col2A RED rc3 names .../deeper   col2B RED rc3 names .../deeper
checks/nvrows-deadrow-gate.py   col1 PASS rc0   col2A RED rc3 names .../deeper   col2B RED rc3 names .../deeper
checks/oracle_f64.py            col1 PASS rc0   col2A RED rc2* .../deeper        col2B RED rc2* .../deeper
checks/rn-gate.py               col1 PASS rc3   col2A RED rc3 names .../deeper   col2B RED rc3 names .../deeper
```
(*`oracle_f64.py` uses exit 2 in `refuse()`, matching `gates/gates-pop.py`'s own convention; every
other file uses 3 after `checks/abi_gate.py`. Recorded rather than harmonised: the exit code is
this tree's convention, not mine to set.)

**No file fails both columns.** No file is a gate that always fails.

**Clause II's own counter, measured per file** (`REFUSE` and `MARKER` both true, via the
instrument's own `code_of`): all eleven are now `True/True`, so `gates-pop.py` clause II counts
each as asserting its root. The tree total reads `18/37 files that name a root also REFUSE` --
but that number is NOT quoted as an improvement, because I did not capture its pre-fix value from
this tree state and a before/after quoted from different trees is not a measurement.

**Two belt faults found in my own plants, both of the shape the brief warns about:**
- Column 2B's first version put the copy's markers BESIDE it, so `parents[1]` named the root, the
  root check PASSED, and the refusal came back about an absent input -- the plant was measuring
  its own incompleteness and would have read as a pass.
- `where.py`'s first version printed `SystemExit: 3` with the captured message DISCARDED, so a
  refusal on a swept input was indistinguishable from a refusal on a wrong root: same code, same
  empty message, opposite verdicts. Fixed by emitting the buffer with the failure.

## ONE FILE DELETED

**None.** Nothing was deleted; see the caller counts above for why answer 5 was rejected.

## WHAT ELSE I COULD NOT SETTLE

1. **`gates/gates-pop.py`'s self-finding.** Measured false (AST: zero executable `sys.path.insert`),
   owned by `gendirs`, not fixed. Its clause III therefore cannot certify this count is 0.
2. **`checks/drive.mjs` is gone** (swept, recoverable at `371cc64c9^:.agents/slop/jsfp8/`).
   `checks/gate.py` now refuses naming it rather than raising. Restoring it is not my call.
3. **The three `parents[3]` files disagree on nothing, but they disagree with `parents[2]` files
   about what a constant means**: from a DIRECTORY `parents[0]` is the repo root, from a FILE it
   is `checks/`. I kept each file's own spelling rather than unifying, because unifying would have
   been a rewrite of four files' first lines for no measured gain.
4. **`checks/nvrows-deadrow-gate.py`'s comment says `parents[3]` is "wrong in the OTHER direction
   too"** -- that phrasing is wrong (from a file at `checks/`, `parents[3]` is one level too MANY,
   and `parents[1]` is the only depth that lands on the root). The code is right; the sentence is
   not. Left in place because it is a comment another unit may be reading, and correcting prose I
   did not write is how two agents get a merge conflict over nothing.
5. **`checks/dup-gate.py:46` has the SAME stale `SLOP = HERE.parent` as `dup-census.py` and is NOT
   one of the twelve** (it names no `parents[N]`, so the instrument cannot see it). It will raise
   `FileNotFoundError` on `rebase-gate.py`. Not mine; naming it here so it is not lost.