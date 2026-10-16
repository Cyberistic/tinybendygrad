# L2IPOOL -- A POOL THAT IS FED BUT NEVER USED, THIRD INSTANCE

Unit scope: `gates/decomp_graph_census*`, `gates/decomp_value*`. `tinybendygrad/codegen/decomp/`
was NOT touched -- `git diff --stat HEAD -- tinybendygrad/codegen/decomp/` is EMPTY.

## 1. THE POOL, AND HOW MANY MEMBERS REACH `l2i`

Two hand-written tables feed `l2i`'s arguments, and both are in `gates/decomp_graph_census.bend`:

| table | arms | TARGET dtypes |
|---|---|---|
| `dc_l2i_pick` (:126) | **31** | `int32` 19, `int64` 6, `uint32` 3, `uint64` 1, `single` 1, `double` **1** |
| `dc_lc_pick` (:205) | **3** | `int64` 1, `uint64` 2 |

MEASURED (regex over the two tables, both lanes' fixtures). Before this unit the `double`
count was **0 of 30**, so `gates/decomp_graph_census` had zero `l2i` rows with a 64-bit float
target. The source side is blind the same way: the four source dtypes in use are `uint32` 24,
`single` 3, `int32` 3, `boolean` 1 -- no `u8`/`u16`/`u64` word of `dd_wpool` is ever a source,
and no `f64` word exists in the pool to be one.

## 2. `lgv`/`lgw`/`lgx` AND `l2i`'s f64 STARVATION: ONE CAUSE OR TWO

**TWO. Measured on both lanes, 43 rows each, same names** (`py.rows` vs `bd.out`):

```
lgv byte-identical=True   CAST/1[i32],CAST/1[u32],CONST/0,CAST/1[i32]
lgw byte-identical=True   CAST/1[u32],CONST/0
lgx byte-identical=True   CAST/1[u32],CONST/0,CAST/1[u32],CONST/0
```

The fixture defect the last unit found -- `l2i.const` passing `S.uint32()` while the CPython
lane was driven on `int32` -- is FIXED, and both sides now pass `uint32`
(`dc_lc_pick` :205-209 and the oracle's `UOp.const(_v, dtypes.uint32)`). That defect was on
the **SOURCE** axis of three rows. The f64 starvation is on the **TARGET** axis of the other
table, and it is a property of BOTH the target table and the pool (`dd_wpool` has no f64 word
either). Different tables, different axes, different rows: not one cause.

## 3. THE ROW, AND WHAT IT CANNOT DISTINGUISH

`lgz` = `l2i(Ops.CAST, f64, <the pool's two f32 words at 19,20>)`.

- **`decomp_graph_census.bend`** -- `dc_l2i_pick`'s `case 29`; `L2I_N()` 30n -> 31n.
- **`decomp_graph_census-oracle.py`** -- `("lgz", Ops.CAST, dtypes.double, dtypes.float32, 19, 2)`.
- **`decomp_graph_census-gate.py`** -- `ROWS` 42 -> 43, `UNBUILT = ("lgu", "lgz")`. **NO NEW
  CLASS.** `classes_hold`'s UNBUILT assertion is `port == "refused:unported"` and
  `cpy.split(",")[0] == "WHERE/3"`, and both hold.
- **`decomp_graph_census-pins.rows`** -- `--refresh` rewrote 4 lines: the header count, `lgu`'s
  class comment, `lgz`'s class comment, `lgz`'s pin. **THE OTHER 15 PINS ARE BYTE-IDENTICAL.**

`lgz` is `lgu`'s own cell with `dt`'s WIDTH changed and nothing else -- same op, same source
dtype, same two pool words. CPython answers a 22-token
`WHERE(OR(AND,AND),Pf64,ADD(MUL,CAST))` and the port answers `refused:unported`.

**WHAT IT CANNOT DISTINGUISH.** The census's refusal token is ONE STRING, so `lgz`, `lgu`, the
`f16` cell and the `bf16` cell are indistinguishable in it. And no `ADt`/`FOLD` mutation can
move `lgz`, because a mutation that changes a node's argument cannot change the string
`refused:unported` -- measured: A1..A13 move **exactly the same** rows as they did at 42
(6/4/16/6/0/4/1/2/1/1/18/3/1). What carries the fact is `lgz`'s PAIR with `lg5`.

## 4. WHAT THE PAIR MEASURED, AND THE FOOTER IT REFUTES

`lg5` is `(i64 <- f32)` and already was a row. `lgz` is `(f64 <- f32)`. `probe65.bend`:

```
lg5 i64<-f32 sel=1 is_long=T srcfl=T flt=F l2i_dt=i32
lgz f64<-f32 sel=1 is_long=T srcfl=T flt=T l2i_dt=NONE
lgu f32<-f32 sel=2 is_long=F srcfl=T flt=T l2i_dt=NONE
lgv i64<-u32 sel=0 is_long=T srcfl=F flt=F l2i_dt=i32
f64<-u32      sel=0 is_long=T srcfl=F flt=T l2i_dt=NONE
u64<-f32      sel=1 is_long=T srcfl=T flt=F l2i_dt=u32
```

Two same-`sel` opposite-answer pairs, each differing in ONE field of `dt` -- its CLASS at 64
bits: `lg5` builds a 14-token `l2i_cast1` cone, `lgz` refuses; `lgv` builds `l2i_cast0`,
`f64 <- u32` refuses. **`sel` is therefore not what decides.**

The gate's own footer said the 20 `dt == double` cells "ARE MISATTRIBUTED ... they are
`lgu`'s missing arm reached through a wrong guard", named `l2i_cast.got`'s `case 2: None{}`
(dtype.bend:667) as the blocker, and said "THE SELECTOR MUST BE FIXED FIRST". **Its COUNTS are
right** (`bits == 64` True for 3 of 20, `dt in (long, ulong)` True for 2 of 20, the 20 f64 cells
split 12 at `sel == 0` and 8 at `sel == 1`). **Its INFERENCE is wrong:** all 20 cells REFUSE,
none reaches `l2i_cast0`/`l2i_cast1`, and `l2i_cast.ldt` (:680-683) routes `case 0`, `case 1`
AND `case 2` all through `l2i_cast.wide` (:675-678), whose `match m` refuses on
`l2i_dt(dt) == None` **one line before `l2i_cast.got` is entered**. Fixing `dd_is_long` changes
nothing observable. The footer is corrected in place.

What actually has to change: `l2i_cast.ldt` ALREADY HAS THE SHAPE -- `case 3` (:682) bypasses
the `l2i_dt` guard entirely. A `case 2:` at that level is what f64 needs, AND IT NEEDS A BODY
(`l2i_cast2` does not exist). **NOT LANDED**: half a fix makes `classes_hold` red
("`lgz` is now a DELETION ... drop it from UNBUILT"), which is a new finding, not a partial
green.

## 5. THE FIXTURE-REPAIR PROOF, AND THE ZERO-MOVER

`gates/decomp_graph_census-mutate.py` gained `A14` -- the table's only non-`ADt` entry.
It teaches `l2i_dt` a `CFloat` entry (`dtype.bend:276`, one inserted arm), so `l2i_dt(double)`
answers, `l2i_cast.wide` stops refusing, and `l2i_cast.got`'s `sel == 1` arm builds.

```
BASE LANE: 43 rows, and the gate's `ROWS` names 43
A14    GUARD     1    1  lgz  visible under the bare printer too
1 MUTATION(S) MOVED NO ROW: A5=DEAD on this population
```

`lgz` is **LIVE**, and it needed a GUARD mutation to show it because its token is a refusal.

**THE ZERO-MOVER AND ITS CAUSE.** `A5` -- `dd_cast_bool`'s True arm -- moves 0 rows. Cause:
**DEAD BY REACHABILITY** (the seventh named cause). `sel == 1` requires `dd_is_float(xdt)`
and `dd_is_bool(xdt)` is `Cls.is_bool`, DISJOINT `match`es over the seven-member `Cls`, so
0 of the 400 cells of `l2i_cast`'s dtype product can select it.

**TWO MORE ZERO-EVENTS, BOTH THE SEVENTH CAUSE -- A FORM THAT DID NOT COMPILE.**
1. `probe64.bend` run 1: rc=1, `no such file: .agents/tinybendygrad/helpers.bend` (relative
   import depth off by one level), peak 8 MB.
2. `probe64.bend` run 2: rc=1, `expected : cases for True, observed: {}` at `p64_pick` --
   bend requires a `case _` on a `U32` `match`, peak 437 MB. Rewritten as eight straight-line
   calls.

**AND THE NEW CAUSE THIS ROW ADDS TO THE LIST.** *A row whose token IS a refusal cannot be
moved by a token-level mutation.* It is a property of the row, not a defect of the instrument,
and it is the reason `A14` exists. The eighth named cause.

## 6. VERDICTS, ROW COUNTS, RSS

| run | rows | rc | peak RSS | wall | timestamp (UTC) |
|---|---|---|---|---|---|
| baseline `decomp_graph_census-gate.py` | 42 | 0 | **599 MB** | 176 s | 2026-10-16T12:39Z |
| after, `lgz` landed | 43 | **0** | **925 MB** | 39 s | 2026-10-16T12:46Z |
| after, final | 43 | **0** | **1211 MB** | 29 s | 2026-10-16T12:55Z |
| `decomp_graph_census-mutate.py` (14 bend runs) | 43 base | 0 | **1071 MB** | 90 s | 2026-10-16T12:49Z |
| `decomp_value-gate.py` | 198 comparisons | 0 | 43 MB | 88 s | 2026-10-16T12:52Z |
| `--refresh` | 43 | 0 | 687 MB | 8 s | 2026-10-16T12:43Z |
| `probe64.bend` | 8 cells | 0 | 582 MB | 2 s | 2026-10-16T12:31Z |
| `probe65.bend` | 8 cells | 0 | 483 MB | 2 s | 2026-10-16T12:35Z |

**THE RSS SPREAD IS 2.02x ON ONE COMMAND AND ONE TREE (599 / 925 / 1211 MB)**, so a single
number quoted without its timestamp is a lie here. Every run above reported
`[bounded] WITHIN-LIMITS`; every run also reported `MACHINE: VIOLATED -- loadavg 5.2..20.1 on
12 cores`, so **NO WALL TIME IN THIS TABLE IS ATTRIBUTABLE TO THE CHILD.** Ceiling 8192 MB.

## 7. NEIGHBOURING GATES

- `decomp_value-gate.py` -- **PASS, rc=0, 11 PROMOTION rows x 18 families = 198 comparisons,
  0 DIFFER.** Unchanged: `lgz` is not a `PROMOTION` row, and `decomp_value` loads
  `CENSUS.PROMOTION_CASTS` by path, not `ROWS`.
- `pins-shape-gate.py` -- rc=1, `decomp_graph_census-pins.rows rows=17 cols=3`, shape correct.
  **THE RED IS PRE-EXISTING AND NOT MINE**: the finding names `cstyle-live.rows` ("no header
  declares who writes it"), and the gate is **byte-identically red at HEAD** (measured by
  restoring `git show HEAD:gates/decomp_graph_census-pins.rows` and re-running).
- `gates/gates-pop.ledger.tsv:97` names this gate as `py-main` with no row count, so it needs
  no regeneration. NOT TOUCHED (out of grant).

## 8. FOUND BUT NOT DONE

- **`l2i.pick` (`dtype.bend:2780-2834`) STILL HAS NO `f64` ARM.** The census does not read it --
  it MIRRORS it -- so `lgz` needed no port edit. Adding the arm to `l2i.pick` would change
  `dtype.bend`'s own 208-row `gate()` (:3068) and its count assertions, in the largest file in
  the port, where another unit is adjacent. **NOT DONE, AND NOT NEEDED FOR THIS ROW.**
- **`f16` and `bf16` CELLS.** MEASURED (`probe64.bend`): both REFUSE, as `lgu` does, because
  `l2i_dt` is `None` for every non-`CSint`/`CUint` 64-bit class and `bits != 64` puts them at
  `sel == 2`. **NOT ADDED AS ROWS**: the census's refusal token cannot distinguish them from
  `lgu`, so two more rows would be two more copies of one string.
- **`dd_is_long` FIX.** One non-comment site (`dtype.bend:686`), measured. **NOT LANDED**: per
  §4 it changes nothing observable, and landing it alone would move `sel` on 20 cells with no
  row moving -- a mutation that moves nothing for a reason already named.
- **THE 400-CELL `(dt, xdt)` PRODUCT IS STILL NOT A POPULATION.** It is measured by
  `.agents/slop/decomppromo/dtdt.py --emit`, off-gate, in ANOTHER unit's scratch directory. A
  gate that ranged it would make the target axis DISCOVERED instead of HAND-WRITTEN, which is
  the only real cure for this class. **NOT BUILT**: it is a new instrument, not a row.