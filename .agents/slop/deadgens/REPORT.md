# THE FOUR SWEPT INSTRUMENTS — three restored, one superseded copy

`.agents/slop/deadgens/` · 2026-10-06 · **nothing committed.** Every number below is a
measurement, and every command is one line of `git` or one gate run.

## 1. THE TABLE

| file | exists | ever committed | in which commit | who names it |
|---|---|---|---|---|
| `.agents/slop/helpers-oracle.py` | **NO** (was gone) | **YES**, 309 commits | deleted by `371cc64c9`; first-add `6e8d0d358` | `tinybendygrad/helpers.bend:13,2563,367`, `helpers-tc-gate.sh`, `.agents/slop/helpers-tc.bend` header, `checks/census.json:1749` |
| `.agents/slop/helpers-tc.bend` | **NO** (was gone) | **YES**, 306 commits | deleted by `371cc64c9`; first-add `10afe7f58` | `tinybendygrad/helpers.bend:13-14,2709`, `helpers-tc-gate.sh`, `gates/ew-consts.bend:19` |
| `.agents/slop/norm/canon.py` | **NO** (was gone) | **YES**, 40 commits | deleted by `371cc64c9` | `checks/gate_norm.py:8,30,47,167`, `.agents/slop/norm/canon.selftest.py:5,68,124-142` |
| `checks/graphcmp.py` | **NO** (was gone) | **YES**, 30 commits | **NOT `371cc64c9`** — no delete commit exists; lineage rebased out, not an ancestor of HEAD. Last lived at `603de407f` | **NOTHING.** `rg -F 'checks/graphcmp.py'` → **0 hits** |

### TWO OF THE BRIEF'S FOUR PREMISES WERE WRONG, AND BOTH WRONG PREMISES POINTED THE SAME WAY

**1. `canon.py` WAS COMMITTED. The brief's path was wrong.** It said "never committed", and
`git log --all -- .agents/slop/canon.py` does return **0 commits** — because the file was never at
that path. It was at **`.agents/slop/norm/canon.py`**, 40 commits, deleted by `371cc64c9`.
**THIS IS THE BRIEF'S OWN TRAP, REPRODUCED EXACTLY:** *"A `NEVER COMMITTED` verdict scoped to one
commit calls recoverable files unrecoverable."* Scoping to one **path** does it just as well as
scoping to one commit. The sibling `norm/canon.selftest.py` survived the sweep and is still live —
**a surviving sibling is the tell.**

**2. `checks/graphcmp.py` WAS NOT DELETED BY `371cc64c9`.** `git show --stat 371cc64c9 | grep -c
'checks/graphcmp.py'` → **0**. There is no delete commit for it anywhere (`--diff-filter=D` is
empty). Its 30 commits are **not ancestors of HEAD**; the lineage was rebased out. Content survives
in the object DB at `603de407f`. Attributing it to the sweep was a guess that happened to name a
commit that never touched the file.

## 2. WHICH OF THE THREE ANSWERS, PER FILE, AND THE MEASUREMENT THAT DECIDED IT

| file | answer | the deciding measurement |
|---|---|---|
| `helpers-oracle.py` | **1 — RESTORE** | 309 commits; `git show 371cc64c9^:<p>` is non-empty; caller `helpers-tc-gate.sh:38` runs it and 6 imported names all resolve |
| `helpers-tc.bend` | **1 — RESTORE** | 306 commits; caller runs `./bin/bend` on it **twice** + `--check-only`; every def it reaches through `H` still exists in `helpers.bend` |
| `norm/canon.py` | **1 — RESTORE** | 40 commits; exports exactly `bits`/`canon`/`canon_bits`, which is exactly what both callers call |
| `checks/graphcmp.py` | **NOT DEAD — SUPERSEDED COPY. DO NOT RESTORE.** | see §3 |

## 3. `checks/graphcmp.py` IS A SUPERSEDED COPY, AND RESTORING IT WOULD REINTRODUCE A SECOND DRIVER

**How I told a copy from a loss — three independent ways, all agreeing:**

1. **A LIVE, NEWER, CONTINUING TWIN EXISTS.** `.agents/slop/graphcmp.py` is **176,375 B, 636
   commits** — and it is still being edited (`41fbd8793`, Oct 5 23:33, is titled *"THE DIFFER NEVER
   ITERATED THE CORPUS"*). A loss has no successor.
2. **THE RECOVERED COPY IS A FROZEN SNAPSHOT OF THE TWIN.** `git show 603de407f:checks/graphcmp.py`
   is **byte-identical to `.agents/slop/graphcmp.py` as of `3bd2c9264` (Oct 4)** — SHA256
   `ddf753557e3770477a45e940419f5135aae9640a672829f1e4d00eb263460943` both sides. 589 diff lines
   behind. **A copy that equals an OLDER commit of another path is a copy, not an original.**
3. **NOTHING EVER IMPORTED IT.** All three `import graphcmp` sites put **`.agents/slop`** (or the
   repo root) on `sys.path` — `census.py:13-15`, `al-verdict.py:31-35`,
   `graphcmp-census-audit.py:32-38`. **`checks/` is never on any of them.**
   `checks/differ.py:41` hardcodes `GCMP = ".agents/slop/graphcmp.py"`, and did so **already at
   `603de407f`**, the very commit that last held the copy — `git log -S'checks/graphcmp.py' --
   checks/differ.py` → **0 commits, ever.** `rg -F 'checks/graphcmp.py'` → **0 hits tree-wide.**

**So the brief's suspicion is confirmed and acted on: restoring it would put a second, 589-lines-stale
`graphcmp.py` back on disk that no gate, no instrument and no `sys.path` should ever resolve.** The
same reasoning kills the concern about `differ.py` "replacing" it — `differ.py` is the *driver for*
the twin; it never claimed the copy.

## 4. THE THREE RESTORES — SHA256 AND VERIFICATION AGAINST THE CALLER

All three byte-exact (`git show 371cc64c9^:<p> | diff -q - <p>` → identical for all three).

| file | sha256 | verified against its caller, not merely that the bytes exist |
|---|---|---|
| `.agents/slop/helpers-oracle.py` | `776a3fd2f79f4affef02f63ac21fb1602036bf211e38311640dbd856042a70ae` | `helpers-tc-gate.sh:38` pipes stdout→`$GT.rows`. Ran it under the gate's env: **rc=0, 237 stdout rows**, 36 `#ungated` on stderr. `from tinygrad.helpers import trange, GlobalCounters, Context, ContextVar, floordiv, floormod` → **all 6 import OK** |
| `.agents/slop/helpers-tc.bend` | `b92329db3452835ef9d916f87e6f81365c2137d625e437d2da4716dfd279980f` | Gate runs it twice + `--check-only`. `./bin/bend … --check-only` printed **`ALL PROOFS CHECK`** — so it still typechecks against the CURRENT `helpers.bend`. Its `import ./../../tinybendygrad/helpers.bend as H` is correct from `.agents/slop/`. Every def it reaches through `H` is present: `trange:2716`, `Context.*:399-468`, `GlobalCounters.*:2572-2651`, `i64_or/and/shl/div/mod:1747-2175`, `gcd:2206`; `Flags{no_color,default_float,default_int,sum_dtype}` matches its `case Flags{nc, df, di, sd}` |
| `.agents/slop/norm/canon.py` | `b7958fa3713cd6d709c2fd28292bb901dcd86f675808f23a58ec044bc30de543` | Exports `bits`/`canon`/`canon_bits`/`round_to`/`spells_differ`; `canon.selftest.py` calls `canon.canon(s,"f32")` and `canon.canon_bits(0x3F800000,"f32")`, `gate_norm.py` calls `canon.bits(x,"f32")` (`gate_norm.py:53` `F32 = "f32"`, a **string**, so the width contract holds). **`.venv/bin/python .agents/slop/norm/canon.selftest.py` → IMPORTS AND RUNS: 4/4 motivating rows AGREE, injectivity over 1,044,482 non-NaN f32 patterns → 0 collisions** |

## 5. THE THREE GATES: DO THEY RUN, WITH VERDICTS

| gate | before | after | verdict |
|---|---|---|---|
| `sh .agents/slop/helpers-tc-gate.sh` | **rc=2, NO-VERDICT** | **rc=1** | **RUNS. 237 rows, all three lanes. `bd` == `bn` IDENTICAL. `py` vs `bd` = exactly ONE divergent row** |
| `.venv/bin/python checks/gate_norm.py` | `ModuleNotFoundError: No module named 'canon'` | **same error** | **STILL BROKEN — but NOT because `canon.py` is missing.** See §6 |
| `.venv/bin/python checks/census.py` | `ModuleNotFoundError: No module named 'graphcmp'` | **same error plain; RUNS with `PYTHONPATH=.agents/slop`** | **RUNS** once `sys.path` is right: emitted rows, measured `denominator: 77`, split 7 bend-only / 1 wall / 70 neither |

## 6. THE RESIDUAL BLOCKERS ARE **MOVE BUGS**, NOT SWEEP LOSSES — AND THE CALLER IS WRONG, NOT THE FILE

This is the part the brief's framing does not anticipate, and it matters more than the restores.

**`gate_norm.py` and `census.py` are COPIES whose depth-relative self-location did not move with
them.** `57d0fc387 slopcopies` (*"110 COPIES DELETED, 126 CITATIONS REPOINTED"*) deleted
`.agents/slop/norm/gate_norm.py` and left the copy at `checks/gate_norm.py`. But that file locates
itself by depth, and depth is now wrong by two levels:

| | `HERE` | `REPO = HERE.parents[2]` | `sys.path.insert(0, HERE)` |
|---|---|---|---|
| at `.agents/slop/norm/` (depth 3) | `<root>/.agents/slop/norm` | **`<root>` ✓** | `norm/` — where `canon.py` is ✓ |
| at `checks/` (depth 1) | `<root>/checks` | **grandparent of `<root>` ✗** | `checks/` — where `canon.py` is **NOT** ✗ |

`checks/gate_norm.py:42-44` does exactly the old arithmetic. **So restoring `norm/canon.py` to its
own home cannot fix it — the copy looks in `checks/`.** `checks/census.py:13-14` has the identical
bug, which is why §5 needs one env var to run it.

**The fix is a depth correction, NOT a second copy of `canon.py` into `checks/`** — putting a copy
in `checks/` would re-create the stale-duplicate class of §3 and re-break the moment either moves.

**I DID NOT MAKE THIS EDIT.** The brief grants me `gate_norm.py`/`census.py` *only if* answer 2 or 3
applies; **answer 1 applied to all three recovered files.** So §5's two "STILL BROKEN" verdicts are
reported, not papered over. Whoever owns those two files needs, per file, `parents[2]`→`parents[1]`
and a `sys.path` entry pointing at `.agents/slop/norm` (resp. `.agents/slop`).

## 7. THE GATE, RESTORED, IMMEDIATELY CAUGHT A DEFECT — AND THE DEFECT IS IN THE ORACLE, NOT THE PORT

This is the whole thesis of the sweep, caught in one row, and **it is why I did not "fix" the gate to
go green.**

    $ diff $GT.rows $GT.bd
    237c237
    < d_i64min_d=2147483648:0
    ---
    > d_i64min_d=-9223372036854775808

`grep -c '^[<>]'` → **2** (one `<`, one `>`): **exactly one row of 237 diverges.** The sibling
`d_i64min_x` row **agrees**, so the input is fine and only the rendering differs.

`helpers-oracle.py:286-288` states, in its own header, that *"CPython's `str(-2**63)` is
`-9223372036854775808`, and the port answers `2147483648:0` -- the bit pattern."* **Measured, that
is now BACKWARDS.** The oracle lane printed `2147483648:0`; **both port lanes printed
`-9223372036854775808`, which is correct.** CPython agrees: `str(-2**63)` → `-9223372036854775808`.

The cause is `helpers-oracle.py:317-322`:

    def dec_limit(x): return x == -(1 << 63)
    print(f"{nm}_d={words(v) if dec_limit(v) else v}")

**On this one row the oracle substitutes the port's expected bit pattern for CPython's own answer.**
So `_d` here is not a CPython measurement at all — it is a hardcoded expectation of what the port
will say, which is a **tautological row**, and one that is **inverted** against a port that has since
become correct.

**Deleting that substitution is the fix, and I did not make it:** the row is the single thing in this
gate with the power to fail, and silencing it to obtain `rc=0` would be the exact defect the house
rules call harmful. **The honest state of this gate is RED, and it is red because the oracle lies on
one row.**

## 8. UNSETTLED

- **`base.bend:1556` is now a BLANK LINE.** `helpers-oracle.py`'s header cites it as *"`F32.add` — a
  LAW at `base.bend:1556`, which live code may not call"*, and `helpers.bend:2563` repeats it. The
  line-number reference has drifted. It is inside a `#ungated` comment, so it gates nothing, but the
  claim is now unveriable as written.
- **`ctx_key_count=55`** on stderr. The oracle header says *"61 ContextVars upstream, 4 in this
  file's `Flags`"*. Measured 55. `#ungated`, so ungated — noted, not chased.
- **`canon.selftest.py` still fails, on a FIFTH swept input that is not mine:**
  `.agents/slop/norm/f32show.bend` does not exist (`bend -o emitted nothing for f32show.bend`).
  **Same class as these four, one directory over.** `canon.selftest.py` is restored-running up to
  that point and its normaliser proofs all pass.
- **`helpers-tc-gate.sh` writes `$GT.rows.err`/`.bd.err`/`.bn.err`** next to the lanes. I did not
  check whether `checks/no-txt.py` or the retention rule reads them (398 `.txt` remain, all other
  units' oracles; my three restores are `.py`/`.bend` and moved that count by 0).
- **`.agents/TODO.md` not ticked.** It is contended by seven running units and is not in my ownership
  list; editing it here risks clobbering another unit's line. Flagging rather than writing.