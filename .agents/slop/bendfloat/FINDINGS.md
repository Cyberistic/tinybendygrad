# FINDINGS -- the BEND lane's f16 rule: the `k` token, the NaN payload, and the gate that holds them

Every number below was MEASURED with the command named beside it, on 2026-10-20 (UTC).
The instrument is `gates/bendfloat-gate.py`, which is new in this commit: it compiles the
live `tinybendygrad/dtype.bend` with `bin/bend` and compares the tree's own arithmetic
against CPython's own codec, over seven DISCOVERED classes.

## 1. THE TWO EDITS, AND THE THIRD ONE THAT WAS FOUND BESIDE THEM

`dtype.bend:713` (the token), `U32.sub(31, U32.from_nat(U32.log2(m)))` ->
`U32.from_nat(U32.log2(m))`, and the comment at `:707-710` with it.  bend2's `U32.log2`
IS `floor(log2 n)`, and the C's `31u - __builtin_clz(m)` is the SAME number
(`__builtin_clz(m)` is `31 - floor(log2 m)`); the `31 -` in front of it made the Bend's
exponent `31 - floor(log2 m) + 103`, which is 2**31 too large at `m = 1`.

The comment that went with it asserted the opposite -- "`k` is `31 - clz(m)` -- which is
exactly `31 - floor(log2 m)`, so `U32.log2` stands in for the C's `__builtin_clz`" -- and
it cited `dtype.c:151`, a line that is `:175-176` now.

THE THIRD EDIT, FOUND BY MEASUREMENT: the two NaN arms carried the payload, and CPython
canonicalises.  MEASURED, `.venv/bin/python` with `struct.pack('e', ...)`:
`0xFFFFFFFF -> 0xFE00`, `0x7F800001 -> 0x7E00`, `0x7FC00000 -> 0x7E00`,
`0xFFC00000 -> 0xFE00`, and half `0x7c01 -> f32 0x7FC00000`.  The comment in
`dtype.bend` claimed `0xFFFFFFFF` becomes half `0xFFFF`; it does not.  Both arms now
answer the one quiet NaN per sign, like `runtime/dtype.c:146` and `:172`.

## 2. THE MEASUREMENT, BEFORE AND AFTER

    .venv/bin/python gates/bendfloat-gate.py          # BEFORE: rc=1, FAIL
    .venv/bin/python gates/bendfloat-gate.py          # AFTER:  rc=0, PASS

  class  rows        BEFORE disagree  AFTER disagree  distinct before/after  oracle
  h2f      2046      2046            0                2046 / 2046            2046
  h2n      2046      2044            0                2046 / 2                  2
  h2i         2         0            0                2 / 2                     2
  f16b      154         0            0                58 / 58                  58
  seam_b    154       150            0                58 / 58                  58
  f16n 16777214  16744448            0                1024 / 2                   2
  seam_n    2046      2044            0                1024 / 2                   2

`h2f_1` was `0x43000000` (128.0) where CPython answers `0x33800000` (2**-24), and it now
answers `0x33800000`.  THE MAP WAS ALWAYS INJECTIVE: 1023 distinct f32 patterns over the
1023 positive half subnormals before AND after (2046 over both signs), so the Bend's
defect was a wrong MAGNITUDE and never a lost one -- which is what rules out the
non-injective reading.  The gate prints that row as its own line:

    h2f positive class: 1023 inputs, 1023 distinct f32 patterns (the map must be
    INJECTIVE), 1023 disagree      <- BEFORE
    h2f positive class: 1023 inputs, 1023 distinct f32 patterns (the map must be
    INJECTIVE), 0 disagree         <- AFTER

## 3. THE SEAM'S 75 OF 77: THE SAME DEFECT, AND HOW THEY WERE TOLD APART

`Dt.fp16` is `fp16_f32(fp16_encode(...))`, so the seam INHERITS the decode arm's answer.
The two were told apart by WHICH CLASS moves: the `k` fix takes `seam_b` from 150
disagreements to 0 and leaves `f16n` at 16744448, and the NaN fix takes `f16n` to 0 and
leaves `seam_b` at 0.  Two defects, two classes, one fix each.

## 4. THE NaN CLASS, IN FULL

`f16n` is the WHOLE f32 NaN class -- exponent field 0xff, mantissa not 0, both signs,
16777214 patterns -- not a prefix of it and not a sample of it, and the oracle is CPython's
own codec over the same class.  The prior unit's 64-pattern sample read "32 disagree";
the full class reads 16744448 disagree, because the payload survives for every mantissa
whose 13-bit truncation is not 0 and not 512.

## 5. THE GATE, AND WHY THE JS's PLANT DOES NOT COVER IT

`gates/bendfloat-gate.py` holds the Bend lane with four arms, each anchored on the tree's
own FIXED text and each applied to a COPY of `dtype.bend` that is recompiled:

    k-plant     rc=0   h2f disagree 0 -> 2046, seam_b 0 -> 150
    k-disarm    rc=0   every count moved by ZERO
    nan-plant   rc=0   h2n 0 -> 2044, f16n 0 -> 16744448, distinct 2 -> 2046 / 1024
    nan-disarm  rc=0   every count moved by ZERO

`gates/float-halfclass-gate.py`'s `norm-plant` gives the JS lane's `m << 14` back and
holds the JS lane's rule.  The Bend's rule is a different spelling (`U32.log2` where the
JS has `Math.clz32`), in a different file, in a different language, compiled by a
different compiler: a plant that perturbs the JS cannot move the Bend's rows, so a gate
whose plant does not move its own lane's rows cannot SEE its own lane fail.

## 6. THE ACCEPTANCE GATES, BEFORE AND AFTER

  gate                                     before    after
  gates/subnormal-flush-gate.py            rc=0      rc=0
  gates/js-lane-census.py --quick          rc=0      rc=0
  gates/js-lane-census.py (full)           rc=0      rc=0
  gates/float-halfclass-gate.py            rc=0      rc=0
  gates/bendfloat-gate.py                  rc=1      rc=0   (new)

THE THIRTEEN ARMS of the three sibling gates, measured BEFORE (with HEAD's `dtype.bend`
in place) and AFTER: the rc are IDENTICAL, and thirteen of them are rc=3 (REFUSED) --
nine census arms and four flush-gate arms.  THAT REFUSAL IS THE EARLIER FIX LANDING:
those arms' anchors are the PRE-fix JS and C text, which the JS lane's fix (636e797cb and
2eda0063e) removed, so "a precondition was absent" is the tree's own word for the defect
no longer being there.  `arith-plant` and `thr-plant` answer rc=1 BY DESIGN: the census
returns FAIL whenever the ARMED lane disagrees, and the armed lane is the point.

## 7. THE SUBSTRATE DIGEST

    .venv/bin/python .agents/slop/bendfloat/substrate-digest.py
    substrate digest LIVE (after the edit) : f0080ea2049ff9b74b1cd77564900674b3af0bcac6da31030d3eedd2efcaa8ea
    substrate digest with tinybendygrad/dtype.bend at HEAD : ce764c2890f3a470448686309b708a49aa754dacf447306d68937e95649cb202
    moved by this edit : True
    declared inputs: 413 entries

`runs/graphcmp/D/D0-run-summary.txt` records `8dc8b786...`, which was already stale
against this tree before this edit.  THE CORPUS WAS NOT RE-RUN: it needs `bend`, several
units are live, and `AGENTS.md` says to run it with nothing else compiling.

## 8. NOT DONE, AND WHY

  * The corpus (`checks/differ.py`) was NOT re-run: `AGENTS.md` forbids it here, and the
    digest it pins has moved.
  * `gates/gates-pop.ledger.tsv` was NOT updated for the new gate.  The ledger is already
    stale for many gates (`float-halfclass-gate.py` and `subnormal-flush-gate.py` are not
    in it), `gates/gates-pop.py` was RED before this commit and is RED after it for the
    same reason, and `--write-ledger` is a WRITER of a shared file.
  * The half NORMALS, the fp8 and bf16 rules, and the f32 -> half direction outside the
    band and outside the NaN class are not this gate's subject.
