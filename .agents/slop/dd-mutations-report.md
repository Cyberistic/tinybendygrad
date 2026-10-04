# THE MUTATION TABLE for codegen/decomp/dtype.bend — classified

Snapshot `e4618a7127cedfd04201156fa426facf4ad9ece9` (`.agents/slop/dd-mutations.frozen.bend`)
against tree `e17d3f7dd48cf84c7a101b3d6aee11c0284a165e`. Baseline
`.agents/slop/dd-gate-base-182.txt`, **182 rows**.

**Both are pinned, and both had to be.** During this run the live `dtype.bend` moved
**four** times (`d9189ae5` → `c4380cfc` → `62a650a5` → `c4380cfc` → `e4618a71` → `cdd85227`)
while its owner fixed three more defects in `l2i_cdiv` and in `dd_fuel`. `dd-mutate.py`
pins both and refuses to write a table unless the unmutated mirror reproduces the baseline
(`probe_substrate`).

## Controls (RULE C) — all three SAME

| id | edit | verdict |
|---|---|---|
| C00 | byte-identical rewrite | **SAME** |
| C01 | comment-only (a `#` line above a def) | **SAME** |
| C02 | whitespace-only (re-indent one trailing statement) | **SAME** |

And they earned their keep in this run — see "RULE C caught a mutant baseline" below, where
all three read **MOVED 6 rows** on a baseline that was itself the M09 mutant.

## The table

**31 MOVED · 5 THEOREM (each re-measured, each with a measurement not an argument) · 0 REQUEST
· 0 DID-NOT-COMPILE · 0 DEAD ANCHOR.** The previous table was 28 · 5 · **1 REQUEST** · 2.

| id | what it changes | status | rows |
|---|---|---|---|
| M01 | `dd_cast_sel` long arm 0/1 | MOVED | 36 |
| M02 | `dd_cast_sel` non-long arm 2/3 | MOVED | 12 |
| M03 | `dd_cast_fold` never folds | MOVED | 18 |
| M04 | `dd_cast_bool` inverted | MOVED | 2 |
| M05 | `l2i_cast3.bitc` never bitcasts | **MOVED (was 0; `lgy` closes it)** | **4** |
| M06 | `l2i_cast.got` sel 3 → arm 0 | **THEOREM (intercepted)** | 0 |
| M07 | `dd_bc` never folds | MOVED | 15 |
| M08 | `l2i_cast0.sgn` −1 as 1 | MOVED | 7 |
| M09 | `l2i_shl.hi` OR halves swapped | **MOVED (REQUEST → MOVED)** | **8** |
| M10 | `l2i_shl.hi` `>>31−n` → `>>n` | MOVED | 18 |
| M11 | `l2i_shr.fill` always sign-extends | MOVED | 5 |
| M12 | `l2i_shr.fill` always zero-fills | MOVED | 4 |
| M13 | `l2i_shl.ge` `>=32` → `<32` | MOVED | 25 |
| M14 | `l2i_mul.p` cross terms swapped | **MOVED (was DID-NOT-COMPILE)** | **2** |
| M15 | `l2i_mul.w` shift direction | MOVED | 2 |
| M16 | `l2i_cmplt` OR halves swapped | MOVED | 9 |
| M17 | `l2i_where` branch pairs swapped | MOVED | 8 |
| M18 | `l2i_max` WHERE branches | MOVED | 1 |
| M19 | `l2i_binop` forced AND | MOVED | 6 |
| M20 | `dd_rsub31` `31−n` → `31+n` | MOVED | 14 |
| M21 | `unpack32` mask 0xFFFF → 0x10000 | MOVED | 6 |
| M22 | `unpack32` shift source | MOVED | 2 |
| M23 | `reindex.scaled` mul order | **THEOREM (unreachable)** | 0 |
| M24 | `l2i_cdiv` 64 → 63 iterations | MOVED | 7 |
| M25 | `l2i_cast0.pick` sign/zero extend | MOVED | 31 |
| M26 | `dd_rs.push` visit src[n] first | MOVED | 29 |
| M27 | `dd_rs.has` never remembers | MOVED | 8 |
| M28 | `l2i.roots` low word only | MOVED | 36 |
| M29 | `l2i.gone` prints `none` | MOVED | 1 |
| M30 | `dd_eck` counts a CONST by its first src | **MOVED (was DID-NOT-COMPILE)** | **24** |
| M31 | `dd_join.add` joins with `-` | MOVED | 48 |
| M32 | `l2i.went` never calls `l2i` | MOVED | 138 |
| M33 | `l2i_define.size2` stops doubling | **THEOREM (unreachable)** | 0 |
| M34 | `f2f.up.tail` always non-fnuz | **THEOREM (unreachable)** | 0 |
| M35 | `rne.sel` refuses every shift | **THEOREM (unreachable)** | 0 |
| M36 | `l2i_cdiv.uns` re-arms the CDIV/CMOD swap | MOVED | 8 |

### The proofs, for every THEOREM — re-run, not inherited

Every one was re-measured **on this snapshot** (`e4618a71`), not carried over from the
previous table's snapshot. Each is a rename (`dd-mut-proof.py`) or an arm deletion
(`dd-mut-tether.py`) whose gate output came back byte-identical to the 182-row baseline.
"I read the code and saw no caller" is not a proof and is not offered as one.

```
dd-mut-proof.py  dd-gate-base-182.txt dd-mutations.frozen.bend l2i_define f2f reindex
  l2i_define   THEOREM -- rename compiled, output BYTE-IDENTICAL     (M33)
  f2f          THEOREM -- rename compiled, output BYTE-IDENTICAL     (M34, M35)
  reindex      THEOREM -- rename compiled, output BYTE-IDENTICAL     (M23)

dd-mut-tether.py dd-gate-base-182.txt dd-mutations.frozen.bend
  M06a-delete-got-case3   THEOREM      -- compiled, output BYTE-IDENTICAL
  M06b-delete-ldt-case3   STILL REACHED -- 137 of 184 lines differ (180 vs 184 lines)
```

- **M06 — intercepted.** Deleting `l2i_cast.got`'s `case 3` arm compiled and changed nothing.
  Deleting the *interceptor* instead (`l2i_cast.ldt`'s `case 3`) changed **137 of 184 lines**.
  Both directions measured; neither read off a comment.
- **M23 — unreachable.** Renaming `def reindex(` compiled, output byte-identical.
- **M33 — unreachable.** Renaming `def l2i_define(` compiled, output byte-identical.
- **M34, M35 — unreachable.** Renaming `def f2f(` compiled, output byte-identical. `f2f.up.tail`
  and `rne.sel` are reachable only through `f2f`.

## M09 — REQUEST → **MOVED, 8 rows**, and the fixture that closed it

```
M09 l2i_shl.hi: OR the halves the other way round
  MOVED  8 rows
    hi42        <-- the NEW fixture, and it reads the ORDER
    hi42k       <-- the NEW fixture
    hi42sig     <-- the NEW fixture
    lg9sig
    lgqsig
    lgrsig
    lgssig
    lgtsig
```

### The previous REQUEST was a MISDIAGNOSIS, and here is the measurement

The old table said the `hi` site was unreachable and asked for a fixture with `b0 < 32`. Both
halves of that are wrong, and the wrongness is visible in one row:

| `lg9p` on the old snapshot `73b0e1e7` | `lg9p` on this snapshot |
|---|---|
| `WHERE(CMPNE(CMPLT,C(1)),BITCAST(SHL),BITCAST(WHERE))` | `WHERE(CMPNE(CMPLT,C(1)),BITCAST(SHL),BITCAST(OR))` |

`l2i_shl.hi` was **called unconditionally** on both snapshots — it is not unreachable and was
never unreachable. On `73b0e1e7` it computed the right node and then the arena-aliasing defect
the dtype unit has since fixed **overwrote the index that pointed at it**, so the row printed
`BITCAST(WHERE)`: the `OR` was not in the cone and no printer depth could recover it. The old
report's own conclusion — "`lg9p` printed `BITCAST(WHERE)` where CPython has `BITCAST(OR)`" —
was the tell, and it was read as a coverage fact instead of a port defect. **A 0 measured
against a snapshot with a known defect in it is a statement about the snapshot.**

### The fixture: `hi42`, dtype.py:42's `hi` as a fixture's ANSWER

`tinygrad/codegen/decomp/dtype.py:41-44`

```python
case Ops.SHL:
  a0u, a1u, n = a0.bitcast(uint), a1.bitcast(uint), (b0 & 31).cast(uint)
  lo, hi = (a0u << n).bitcast(dt), ((a1u << n) | ((a0u >> 1) >> (31 - n))).bitcast(dt)
  return (b0 >= 32).where(zero, lo), (b0 >= 32).where(lo, hi)
```

`l2i` hands `hi` back only as the `y` of `(b0 >= 32).where(lo, hi)`, which is `dd_where` — a
three-src `WHERE`. `dd_tree` prints **two** levels (`dd_sfx2.put` calls `dd_sh1` on each src;
`dd_sfx1.put` calls the bare `dd_lab`), so `hi` is two levels down and `lg9p` can only say
`BITCAST(OR)`. **The operand ORDER of that `|` is in no `lg9` row except `lg9sig`, and only
because the cone walk happens to read src[0] before src[1.** An instance of this swap reached
`origin/master` with 147 rows green. It wants a row that *reads* it.

`hi42` roots the cone **at the `|` itself**, so the order is the answer's own text:

```
hi42=OR(SHL(BITCAST,CAST),SHR(SHR,ADD))                       <- the port
hi42=OR(SHR(SHR,ADD),SHL(BITCAST,CAST))                       <- under M09
```

All four rows are **called from CPython**, `.agents/slop/dd-mut-fixtures.py hi42`, and agree
byte for byte:

| row | port | CPython |
|---|---|---|
| `hi42` | `OR(SHL(BITCAST,CAST),SHR(SHR,ADD))` | same |
| `hi42n` | `14` | `14` |
| `hi42sig` | `OR/2,SHL/2,BITCAST/1,PARAM/0,CAST/1,AND/2,PARAM/0,CONST/0,SHR/2,SHR/2,BITCAST/1,PARAM/0,CONST/0,ADD/2,MUL/2,CONST/0` | same |
| `hi42k` | `C(31),C(1),C(-1)` | same |

and the script prints the order **read back out of CPython's own graph**, so the row cannot be
one that encodes M09:

```
# hi.src[0] = SHL(BITCAST(Pi321),CAST(AND))   <- a1u << n, dtype.py:42's LEFT
# hi.src[1] = SHR(SHR(BITCAST,C(1)),ADD(C(31),MUL))   <- (a0u>>1)>>(31-n), the RIGHT
# r1 = WHERE/3  ->  hi is r1.src[2]
```

Three choices in the fixture are load-bearing, and each is a measured reason rather than a taste:

- **`dt = uint32`, not `int32`.** `dtype.py:42`'s `hi` is `(... | ...).bitcast(dt)`, so at an
  `int32` `dt` CPython puts a `BITCAST` **outside** the `|` and the node at `r1.src[2]` is the
  BITCAST (measured: the first version of the probe asserted `hi.op is OR` and it failed with
  `Ops.BITCAST`). At `uint32` the bitcast folds (`mixin/dtype.py:53`), `hi` **is** the `|`, and
  both lanes reach it at one address — CPython's `r1.src[2]`, the port's
  `O.Arena.src(ar, r1, 2)`.
- **`xdt = int32`, not `lg9`'s `uint32`.** With a `u32` source `a0u`/`a1u` fold to bare PARAMs
  and both halves of the `|` look alike; with an `i32` source each half carries its own
  `BITCAST`, so the row also reaches `dd_bcast`'s and `dd_cast_fold`'s **False** arms inside the
  SHL arm — neither of which `lg9` reaches.
- **`W2{ar, o, 0}`** is this gate's own idiom for "the answer is one node": `l2i.two` reads
  `hi == 0` as such, so `l2i.ph` prints nothing and `l2i.roots` roots the cone at `lo` alone.

On the requested precondition: **`b0` in `0..31` is not chosen, it is guaranteed.** `n = b0 & 31`
puts the shift in `0..31` for every input, which *is* the arm's precondition; and the two halves
are a `SHL` and a `SHR`, so no input makes them coincide. Separately, the literal `b0 < 32` case
**was already covered and I measured it**: `l2i_cdiv` calls
`l2i(SHL, uint, *r, UOp.const(1, uint), z)` at `dtype.py:58`, so `lgq`/`lgr`/`lgs`/`lgt` all reach
the `hi` arm with `b0 = C(1)`, and M09 moves `lgqsig lgrsig lgssig lgtsig` for exactly that
reason.

## The REQUEST sweep — five zeros, each re-proved, and one new REQUEST found and closed

**Every zero got a reachability check, because M09 proved a plausible-looking zero can be blind
for a structural reason.** A zero is a THEOREM when the site is unreachable *and that is
measured*; otherwise it is a REQUEST for a fixture.

| id | zero | check | verdict |
|---|---|---|---|
| M06 | 0 | `dd-mut-tether.py`, both directions | THEOREM (intercepted) |
| M23 | 0 | `dd-mut-proof.py reindex` | THEOREM (rename byte-identical) |
| M33 | 0 | `dd-mut-proof.py l2i_define` | THEOREM (rename byte-identical) |
| M34 | 0 | `dd-mut-proof.py f2f` | THEOREM (rename byte-identical) |
| M35 | 0 | `dd-mut-proof.py f2f` | THEOREM (rename byte-identical) |

### And the sweep found a REQUEST the old table did not have: **M05**

Re-aiming M05 at the live file's `l2i_cast3.bitc` (whose body is now the single call
`dd_bcast(isu, ar, a0, S.uint32())`, so the old three-arm anchor was a dead patch) gave **0 rows**
— and `dd-mut-proof.py` **REFUSED to rename it**:

```
l2i_cast3        REACHABLE-WAS -- bend REFUSED the rename: ... observed : l2i_cast3
l2i_cast3.bitc   REACHABLE-WAS -- bend REFUSED the rename: ... observed : l2i_cast3.bitc
```

So the site is **live**, and the 0 is **invisibility**. The reason, and it is structural:
`l2i_cast3` is reached only at `sel == 3`, which `dd_cast_sel` returns only when `dt` is neither
long nor float; `lg7` (`dt=int32, xdt=uint32`) is the only such fixture, and on it
`bitcast(dtypes.uint)` **folds** because the dtypes already agree (`mixin/dtype.py:53`). So
`lg7=CAST(Pu320)` carries no BITCAST, and **the node dtype.py:39's arm exists to build was in no
row in the gate.**

The fixture is `lgy`: same `dt`, same arm, one dtype over on the source. Two words, because
`dtype.py:39` reads `a0`, which `l2i` binds only at `len(uops) >= 2` (`dtype.py:23`) — measured,
one word is `UnboundLocalError`.

```
lgy=CAST(BITCAST(Pi320))    lgyn=2    lgysig=CAST/1,BITCAST/1,PARAM/0    lgyk=-
```

all four called from CPython (`.agents/slop/dd-mut-fixtures.py lgy`). M05 now reads
**MOVED 4 rows: `lgy lgyn lgysig hi42n`.**

## RULE C caught a mutant baseline — the one that mattered most in this run

The first 182-row baseline I generated **was the M09 mutant**: `hi42=OR(SHR(SHR,ADD),SHL(BITCAST,CAST))`
in the *baseline file*. The hand-built mirror it came from had been left holding a mutated
`dtype.bend` by the M09 probe, and nothing checked. Every mutation then moved exactly 6 rows and
**all three controls read MOVED**, so `dd-mutate.py` aborted and wrote no table.

That is RULE C catching a defect it was not written for, and it is why the rules are in this
file twice over. Two things came out of it:

- **`dd-mut-base.sh`** now builds the baseline and cannot produce a mutant: a fresh mirror per
  run from `git archive`, the frozen file dropped in, **the digest asserted on both sides**, and
  two consecutive stable 150+ row outputs before anything is written.
- The same defect, **in my own oracle replay**, was found and fixed one step later:
  `dd-mut-fixtures.py` replayed the gate's fixture order *including the fixture it was about to
  measure*, so `lgyn` read `0` against the port's `2`. A replay that includes the row under test
  is the same error as a baseline taken from a mutant mirror — **the row under measurement is
  measured after it already happened.**

## One deliberate deviation, and why

`dd-mut-base.sh` prints a loud **WARNING** when the live `dtype.bend` no longer matches the
frozen snapshot, where the brief asked for a hard assertion. `dtype.bend` moved four times while
this table was built, so a hard `frozen == live` assertion makes the script unrunnable exactly
when it is needed. What is asserted, and what the table's validity rests on, is unchanged: the
frozen file still hashes to `FROZEN_SHA1` (RULE I) and the mirror is byte-identical to it. The
table therefore measures **one** named, digested file whatever the live tree does, and its header
says which. This run's snapshot `e4618a71` was equal to the live file at the moment it was
frozen; the live file has since moved to `cdd85227` and **both fixtures are still in it and it
still compiles**.

## The 23 rows no mutation moved

`c0..c7`, `l2idt0 l2idt1`, `f2fdt0..8`, `lg7n lgnn lgon lgv`. Not zeros — **rows with no mutation
aimed at them**, and they split three ways:

- **`c0..c7`** are `f2f_clamp_max`'s VALUE, and `f2f_clamp` is reached by nothing in this gate
  (the `f2f` rename is a THEOREM above). They are the subject of `dd-divE-probe.py`, not of this
  table.
- **`lg7n`, `lgnn`, `lgon`, `lgv`** are an interning count and three one-node/refusal rows. A
  mutation that changes *which* nodes exist moves them; none of the 31 does, and
  `lgv=CAST(CAST(C(0)))` is the zero-extend arm where `lo` and `lo.const_like(0)` are the same
  node, so `hi == 0` and there is no second word to move.
- **`l2idt0 l2idt1` and `f2fdt0..8`** are the two dtype-name tables. **The table has no mutation
  entry for either**, and that is a gap in the TABLE rather than in the gate: both are live
  (`dd_dtb.to` is on every `l2i` fixture's path) and a one-line swap of `l2i_dt`'s two values
  would move `l2idt0 l2idt1`. Not added here — out of scope for a REQUEST sweep, and recorded so
  the next reader does not mistake it for a coverage claim.

## Reproducibility

Two independent invocations produce a **byte-identical `.tsv`** (`dd-mutations.txt.tsv`), the
machine-readable verdict. The prose table differs between a fresh run and a cached re-run in the
provenance note only (`1 attempt(s)` vs `cached`), for the non-`MOVED` rows — that is by design,
and it is the defect the previous unit fixed in the TSV.

## Out of my files

- **`l2i_shl.hi`'s operand order** — the M09 defect is fixed upstream of this unit and is now
  *frozen in* this table: the snapshot has the correct order and `hi42` reads it. Nothing to fix.
- **M05's uncovered arm** — `l2i_cast3.bitc`'s False arm had no fixture at all; `lgy` is the
  fixture, added as a row only. No port logic touched.
- **The live `dtype.bend` moved four times under this run** and once more after the table was
  written. Its owner also fixed `l2i_cdiv`'s `*r` aliasing and a `dd_fuel` truncation defect while
  this ran; both are in the snapshot (`dd_fuel`'s own comment records the truncated-cone
  measurement). Not defects of this unit, but the reason the snapshot is pinned.