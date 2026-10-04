# fold-lift -- what this unit landed, and how to re-verify it

`tinybendygrad/uop/fold.bend` only. Nothing else in the tree is this unit's except the
scratch files below, and `.agents/slop/notes/bend2-constraints.md` (append-only).

## The three pieces, in the order they landed

| piece | where in `fold.bend` | rows |
|---|---|---|
| `int(x).bit_length()` and `2**k - 1` -- `mm.bl32`, `mm.bl64`, `mm.mask64`, `mm_mask64` | the `# ==== ... int(x).bit_length()` section | `bl_*` 38 |
| the DTYPE LIMITS -- `Bnd`, `bnd_show`, `bnd_int`, `bnd_fmax`, `bnd_bool`, `bnd_lim` | the `# ==== ... Bound` section | `bl_dt_*` 20 + 4 width probes |
| the OP TABLE -- `mm.lift` and the signed arithmetic under it | the `# ==== ... THE OP TABLE` section | `lf_*` 127 |

The file header, the TODO block at `ops.py:1104`, and the mutation table at the foot of the
file all say which of these is a genuine solution and which is a reported gap.

## Re-verify

```bash
cd /Users/cyberistic/src/tries/2026-09-30-tinybendygrad
./bin/bend tinybendygrad/uop/fold.bend --check-only          # expect: ALL PROOFS CHECK
./bin/bend tinybendygrad/uop/fold.bend > /tmp/f.txt          # 195+ rows, one per line

# 1. the OP TABLE, against CPython
.venv/bin/python .agents/slop/mm-lift-gate.py            > /tmp/lift-py.txt
diff <(grep '^lf_' /tmp/lift-py.txt) <(grep '^lf_' /tmp/f.txt)      # expect: EMPTY

# 2. bit_length + the dtype limits, against CPython
.venv/bin/python .agents/slop/mm-bl-gate.py > /tmp/bl-py.txt
.venv/bin/python .agents/slop/mm-dt-gate.py > /tmp/dt-py.txt
diff <(grep '^bl_' /tmp/f.txt) <(cat /tmp/bl-py.txt <(grep '^bl_dt_' /tmp/dt-py.txt) | grep -v '^bl_w_')
# expect: EMPTY except the four `bl_dt_w*` width probes, which the oracle emits only in its
# own diagnostic form (`bl_w_*`) -- they are the DT1 width-guard fixture and are counted
# separately.

# 3. the mutation table
.venv/bin/python .agents/slop/fold-lift-mutate.py          # see the table at the foot of fold.bend
```

## THE KNOWN-BROKEN DEPENDENCY

`fold.bend` imports `./ops.bend`. `ops.bend` is being edited by another agent and went red
four times during this unit at four different defs (`EqAx.pairs`, `Rng.srcops`, `srow`,
`IdsStr.ids`). **When `fold.bend --check-only` reports an error whose `Location:` names a def
that is NOT in `fold.bend`, that error is `ops.bend`'s and not this unit's.** The check:
`grep -c '<the def name>' tinybendygrad/uop/fold.bend` is `0`.

## The `dtype=int` -> `dtype=i32` ROW MOVEMENT, AND IT IS NOT THIS UNIT'S

`LAWS/spec.bend` was renamed by another agent mid-session (upstream `793abbb1`), which
changed `Dt`'s FOURTH field -- the dtype's NAME -- from `"int"` to `"i32"` and
`"float8_e4m3"` to `"fp8e4m3"`. That moves eight of the pre-existing `mv_*` rows, which print
`dtype=<name>`.

**It also SILENTLY BROKE TWO NAME-BASED MATCHES IN THIS FILE, and that part IS this unit's
to report:**

* `promo_mask`'s four fp8 mask arms (folded up from the committed file)
* `bnd_lim`'s four fp8 maximum arms

Both were `ALL PROOFS CHECK` with the WRONG answer the moment the rename landed: a `case`
pattern that stops matching falls through to the next arm, and `bnd_lim`'s next arm is
`bnd_flt`, so all three fp8 maxima became `NInf`/`PInf` with no error anywhere. The fp8 rows
caught it. Both sites are fixed to the new spellings and both carry a comment naming the
exposure. **`promo_mask` and `bnd_lim` are the only two places in this file that depend on a
dtype's SPELLING, and `S.Dt`'s first three fields cannot tell `fp8e4m3` from `fp8e4m3fnuz`
(both are pri 10) -- so the name is load-bearing and a rename is a silent semantic change.**