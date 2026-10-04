# `s5_copy_sel` -- the row, the reading, and the fixtures

Unit: `copy_to_device`'s refusals. `uop/ops.bend` NOT touched (single ownership). No commits.

## 1. MY OWN READING OF UPSTREAM, `file:line`, and bare `assert` vs `raise`

Read from `tinygrad/uop/ops.py`, then CALLED (`vw-refusal-truth.py` prints all seven lines).

| line | text | mechanism |
|---|---|---|
| `tinygrad/uop/ops.py:758` | `def copy_to_device(self, device, arg=None):` | -- |
| `tinygrad/uop/ops.py:759` | `if is_disk_device(device):` | test |
| `tinygrad/uop/ops.py:760` | `raise RuntimeError("COPY to DISK is not allowed; use STORE to an explicit disk buffer")` | **`raise`, WITH a message** |
| `tinygrad/uop/ops.py:761` | `assert arg is None or isinstance(self.device, tuple)` | **BARE `assert`, NO MESSAGE** |
| `tinygrad/uop/ops.py:762` | `inp = self if arg is None else UOp(Ops.MSELECT, src=(self,), arg=arg)` | -- |
| `tinygrad/uop/ops.py:763` | `if inp.dtype in dtypes.weaks: raise RuntimeError(f"cannot create storage for weak dtype {inp.dtype}")` | **`raise`, WITH a message** |
| `tinygrad/uop/ops.py:892` | `assert isinstance(self.src[0].device, tuple), f"mselect must be on tuple device, getting {self.src[0].device}"` | **`assert` WITH a message**, and LAZY |

**`ops.py:761` is a bare `assert`.** Its observable is `AssertionError` with an **empty
string**, which is why the oracle prints `REFUSED AssertionError: ` with nothing after the colon.
MEASURED live, twice, md5 identical (`vw-refusal-truth.py`):

    s5_copy_sel PORT node4 SHRINK = RAISED AssertionError:
    refuse_disk                   = RAISED RuntimeError: COPY to DISK is not allowed; ...
    refuse_weakint                = RAISED RuntimeError: cannot create storage for weak dtype dtypes.weakint
    mselect_device_read           = RAISED AssertionError: mselect must be on tuple device, getting None

**FOUR refusals, not three.** `ops.bend:6998`'s comment says "THE TWO `raise`s ARE NOT PORTED",
which under-counts: two `raise`s AND two `assert`s. `ops.py:892` is inside `UOp.device`'s
MSELECT arm, is absent from the port's comment, has a **message** where 761 has none, and fires
**lazily** -- `UOp.mselect(1)` on the refused fixture CONSTRUCTS fine
(`mselect_construct = ok`) and only the first `.device` READ raises.

**THE TWO COORDINATES, MEASURED, because the boundary is 4 quadrants and 2 `arg` spellings:**

    assert_q scalardev argnone=ok            assert_q tupledev argnone=ok
    assert_q scalardev argzero=RAISED AssertionError:     assert_q tupledev argzero=ok
    assert_q scalardev argone =RAISED AssertionError:     assert_q tupledev argone =ok
    assert_q scalardev argneg1=RAISED AssertionError:     assert_q tupledev argneg1=ok

`arg=0` **REFUSES**. `arg is None` is an IDENTITY test, so a falsy index is still an index, and
the port's `k: Maybe<&2, U32>` invites the guard "an empty shard index means no shard", which
passes an `arg=1` fixture and fails an `arg=0` one. That is a row the previous draft did not have.

## 2. THE CHANGE `ops.bend` NEEDS -- REPORTED, NOT EDITED

`ops.bend:7009`, `def UOp.copy_to_device(+ar, +self, k: Maybe<&2, U32>, +dev: S.Dev) -> Found`.

**It is a RETURN-TYPE change, not a `Bool` guard.** CPython raises on three of its five lines; a
refusal is not a `Found`. `ops.bend:6989-7003` argues the refusals "cannot change the node" --
true, and irrelevant: the fix is to widen the answer to `Found | Refusal`, which changes every
one of `ops.bend:7020-7031`'s three callers.

| upstream | what `ops.bend` needs | where | blocked on |
|---|---|---|---|
| `ops.py:761` bare assert | **`UOp.device` (ops.py:887-899) does not exist in the port.** Grep for `def UOp.device` finds only `device_range_src`. It is a 9-arm ladder (`PARAM`/`STAGE`/`AFTER`/`MSELECT`/`MSTACK`/`BUFFER,ALLOC`/`COPY`/`ALLREDUCE`) plus the two-line fall-through, and the SHRINK falls THROUGH it. Then a guard keyed on `k is None or device(self) is a tuple`. | new `def UOp.device(ar, i) -> Maybe<&2, S.Dev>` above `ops.bend:7009`; guard at `ops.bend:7009` | nothing -- `ParamArg.device`, `Arena.arg`, `Arena.srcs` all exist |
| `ops.py:759` DISK | `device.bend:213`'s `is_disk` is ported but takes `List<&2, String>`; `S.Dev` is `D1{tag: U32}` / `Dn{tags}` (spec.bend:85-87), a TAG with no name to case-fold or colon-split. **AND TWO PORTED TAG SPACES DISAGREE**: `device.bend:340`'s `tag_of` gives DISK **6**; `schedule/memory.bend:999` says `disk() = S.D1{1}`. | reconcile the tag space, then `ops.bend:7009` | the tag space, which is not this file's |
| `ops.py:763` weak dtype | reads `inp.dtype`, i.e. `Ops.dtype_from_uop` (ops.py:182) over the arena -- the dtype fold. `spec.bend:719-743` has `weakint()`/`weakfloat()`/`Dt.cls`, so the *set* is expressible; computing a node's dtype is not. | `ops.bend:7009` | `uop/fold.bend` (live unit) |
| `ops.py:892` | the MSELECT arm of the same missing `UOp.device`, WITH its message | same | same as 761 |

**The `s5_copy_sel` row itself: `ops.bend:7020-7022` and `ops.bend:7031`.**

    def s5.selrow(+ar: Arena) -> IO(Unit):
      +f = UOp.copy_to_device(ar, 4, Some{1}, s5.dn(2))
      srow("s5_copy_sel", s5.minted.go(Found.ar(f), f))

Once the guard lands this call REFUSES, so `s5_copy_sel` stops being printed and
`ops-501-gate.sh` reports "the two lanes disagree on WHICH ROWS exist". **The row must be
removed from `s5.devrows` (`ops.bend:7031`)**, and the refusal is then asserted by
`c2d_761 selrow` in `validate.bend`, which is a row I own.

## 3. WHAT I DID TO `s5_copy_sel` -- AND THE FIXTURE WAS WRONG THREE TIMES OVER

I cannot edit `ops.bend:7022` or `ops-501-oracle.py:209`. **What I did instead:**

**A. I re-derived the fixture, and the brief's premise was FALSE.** The brief said "node 4 is
`ParamArg.of(2, int32)` with `device = None`". MEASURED by running the port
(`ops.bend:7095` hands `s5.devrows` **`s5.ga.arena()`**, not `s5.arena()`):

    probe_ga_op_1=Ops.BUFFER  probe_ga_op_2=Ops.ALLOC  probe_ga_op_3=Ops.PARAM
    probe_ga_op_4=Ops.SHRINK   probe_ga_nsrc_4=1       probe_ga_src_4_0=Ops.BUFFER

Node 4 is `Node{OpsSHRINK{}, [1], ATuple{Nil{}}}` (`ops.bend:6435`) -- a **SHRINK** with an
`ATuple` arg and **not an `AParam` at all**. `ParamArg(2, int32)` is `s5.ga.arena()`'s node **2**
(`ops.bend:6433`): the SLOT was read as the INDEX. Both arenas have an index 4.

**The refusal still happens, by a route nobody had.** `UOp.device` (`ops.py:887-899`) has no
SHRINK arm, so it falls through to `for x in self.src: if x.device is not None: return
x.device` / `return None`; the BUFFER at node 1 is `ParamArg(1, int32)` (`ops.bend:6432` via
`s5.pa(1)`) with `device=None` (`ops.py:34`). MEASURED `node4_device = None`. So: a `None` from
the fall-through, not from a `ParamArg` field. A port that special-cases `AParam` gets the other
fixture right and this one wrong.

**B. The oracle's fixture was a THIRD thing.** `s5_copy_sel`'s CPython side is
`ops-501-oracle.py:209` on `multi` (`ops-501-oracle.py:164`) -- an `Ops.ALLOC`,
`ParamArg(3, int32, 4, device=('PYTHON','PYTHON'))`. It differs from the port's node in **OP,
SLOT, SIZE and DEVICE**, and `sig()` (`ops-501-oracle.py:45`) prints the root op and the src op
SEQUENCE, so it can see **none of the four**. MEASURED, both sides:

    row_name_s5_copy_sel PORT fixture    = RAISED AssertionError:
    row_name_s5_copy_sel ORACLE fixture  = ok | COPY/MSELECT RANGE

**So the green row compared an ACCEPTED node against a REFUSED one, and the disagreement was
invisible to the row's own printer.** The fix is not a better signature; it is **twelve rows
about the fixture's identity**, and they are in `validate.bend`: `c2d_selrow_op`, `_nsrc`,
`_src0`, `_arg_is_tuple`, `_arg_is_param`, `_src0_slot`, `_src0_size_is_none`,
`_src0_device_is_none`, `c2d_node2_op`, `_arg_is_param`, `_slot`, `_device_is_none`. All twelve
green. `c2d_selrow_arg_is_param = False` is the row that makes "node 4 is a `ParamArg`"
refutable rather than a comment.

**C. `s5_copy_sel`'s true claim now exists under a name I own**, and it is RED:
`c2d_761 selrow = REFUSED AssertionError:` against the port's
`BUILT Ops.COPY/Ops.MSELECT Ops.RANGE`. That is not a green row asserting agreement on a node
that raises -- it is a red row saying the port builds one.

## 4. THE GATE ROWS -- `validate.bend`'s `c2d` lane, with the DENOMINATOR

`tinybendygrad/uop/validate.bend` (`c2d` block, +~250 lines, **zero removed lines** --
`jj diff` reports 0 deletions) and `.agents/slop/c2d-refusal-rows.py` (the CPython side,
every value CALLED, run twice, md5 identical). `validate-oracle.py` LOADS and RUNS the c2d
module rather than copying its fixture list.

**THE LOAD, and every count carries it:**

    port rows    200   (was 158 at @--:  +42 c2d)
    oracle rows  464   (was 411:          +52 c2d + c2d_lane_loaded)
    shared       183   <-- THE DENOMINATOR (was 142: +41)
    agree        163 of 183  (89.1%)
    disagree      20   = 13 PRE-EXISTING + 7 INTENDED

    the c2d lane alone:  port 42 / oracle 53 (52 rows + the load row) / SHARED 41
                          agree 34 of 41 / disagree 7

**The 13 pre-existing reds are PROVEN pre-existing**, not asserted: staging `@--`'s
`validate.bend` beside the live one and running the gate gives `142 shared / 13 disagree`,
and `163 - 129 = 34` new agreements against `142 - 129 = 13`... measured directly: 13 vs 20.
They are `dv_bad_dtype_bitcast`, `dv_cmod4`(+2), `dv_rank_shr1`(+1), `dv_shl2`(+1),
`dv_shr2`(+1), `dv_unsup_stack`, `dv_unsup_two`(+1) -- the z3-normalisation and raise-vs-list
residuals `validate-oracle.py`'s own header documents. **My change to `validate.bend` removes
zero lines**, so it cannot have caused them.

### 4a. THE SEVEN RED NEGATIVES, and each one's POSITIVE NEIGHBOUR ONE STEP AWAY

| red row (7) | CPython | positive neighbour, one step | why one step |
|---|---|---|---|
| `c2d_761 selrow` | `REFUSED AssertionError:` | `c2d_761 argnone` (GREEN) | same node, `arg` `Some{1}` -> `None{}` |
| `c2d_761 argzero` | `REFUSED AssertionError:` | `c2d_761 argnone` (GREEN) | same node, `Some{0}` -> `None{}`; catches "no shard index means no shard" |
| `c2d_761 scalardevargone` | `REFUSED AssertionError:` | `c2d_761 scalarnone` (GREEN) | 4th quadrant: same node, `arg` `Some{1}` -> `None{}` |
| `c2d_759 disk` | `REFUSED RuntimeError: COPY to DISK...` | `c2d_759 cpu` (GREEN) | same node, device tag `6` -> `0` |
| `c2d_759 disktuple` | `REFUSED RuntimeError: COPY to DISK...` | `c2d_759 cputuple` (GREEN) | same node, tuple tags `[6,0]` -> `[0,0]` |
| `c2d_763 weakint` | `REFUSED RuntimeError: cannot create storage for weak dtype dtypes.weakint` | `c2d_763 i32` (GREEN) | same op/arity/device, dtype only |
| `c2d_763 weakfloat` | `REFUSED RuntimeError: ... dtypes.weakfloat` | `c2d_763 f32` (GREEN) | same op/arity/device, dtype only |

**THE POSITIVE CONTROL THAT CATCHES A GUARD REFUSING EVERYTHING** is
`c2d_761 tupledev` = `BUILT Ops.COPY/Ops.MSELECT Ops.RANGE`: the port's own node 4 with **only
`device` changed** (over a tuple-device BUFFER), same op, slot, size and `arg`. It also pins the
guard to `self.device` and not to the `device` ARGUMENT. **Twelve of the nineteen shared outcome
rows are green and must keep building**, which is the number that makes "refuse everything"
detectable.

### 4b. THE TWELVE THAT MUST FAIL FOR THE RIGHT REASON

`AssertionError` and `RuntimeError` are in the row VALUE, not in a row of its own, so a diff of
row NAMES cannot miss them. Oracle-only tallies, counted from the rows:
`c2d_refused_n=10`, `c2d_built_n=14`, `c2d_refused_assertion_n=4`, `c2d_refused_runtime_n=6`,
`c2d_shared_refused_n=7`, `c2d_shared_built_n=12`. The seven are 3 x `AssertionError` from 761
and 4 x `RuntimeError` (2 from 759, 2 from 763) -- **no row accepts either class.**

### 4c. THE SIX ROWS THE PORT CANNOT PRINT, REPORTED NOT HIDDEN

`c2d_oracle_only_n = 5`, named in the gate's `oracle only` list:

| row | why the port cannot answer it |
|---|---|
| `c2d_759 disklower` (`'disk'`) | `S.Dev` is a TAG (`spec.bend:85-87`); no name to case-fold |
| `c2d_759 disksuffix` (`'DISK:0'`) | no name to `:`-split |
| `c2d_759 nodisk` (`'NODISK'`) | no tag for a non-device name |
| `c2d_759 diskx` (`'DISKX'`) | ditto |
| `c2d_892 deviceread` | **`UOp.device` is not ported**, so the port cannot perform the read the assert guards |

`c2d_port_built_n=19` is the port-only load row.

## 5. THE BOUNDARIES I RE-DERIVED, AND WHAT THEY TURNED OUT TO BE

`vw-boundaries.py` (131 rows, run twice, md5 identical) EXHAUSTS each finite set the boundaries
are drawn across; `vw-refusal-truth.py` re-measures the three facts it depends on so it stands
alone.

| boundary | re-derived by | what it turned out to be |
|---|---|---|
| `dtypes.weaks` | enumerate `dtypes.all + dtypes.weaks + (void, char)` from `tinygrad/dtype.py:161`, deduped, membership printed per dtype | **size 2** out of **20** dtypes -- so 763 has **eighteen** positives, not one. `dtypes.all` does NOT contain `weaks`, and `char` is `uint8`, so the raw sum is 21 and the dedup is 20 |
| `weakint in dtypes.weaks` | called | **`True`** (as the brief said) |
| `weakfloat in dtypes.weaks` | called | **`True`** |
| `UOp.range`'s dtype | **all eight `AxisType` members**, `range_dtype_*` per member | **EVERY `UOp.range` is `weakint`** -- `range_dtype_all_weakint=1`, `distinct=1`. **A RANGE cannot be a positive 763 fixture on any axis type.** That is why no range appears on either side of the 763 rows |
| `is_disk_device` | 17 strings + 10 tuples, each asked twice (the def and its one caller) | exact, case-folded, `:`-split HEAD match: `'disk'`,`'Disk'`,`'dIsK'`,`'DISK:0'`,`'DISK:0:1'`,`'DISK:'` all refuse; `'NODISK'`,`'NDISK'`,`'XDISK'`,`'DISKX'`,`'0DISK'`,`''` all build. Position in the tuple is irrelevant |
| the 761 assert | 2 x 4 quadrant table, `arg` in `{None, 0, 1, -1}` | **2 of 4 refuse**, and **`arg=0` refuses** -- so the test is `is None`, NOT truth. `isinstance(None, tuple)` is False on the SHRINK's fall-through device |

**Two of these were wrong when first written and were caught only by calling**, which is the
point: `dtypes.weakint in dtypes.weaks` is `True`, and every `UOp.range` is `weakint`. A positive
row written from belief is a positive row FOR a refusal, and it is green.

## 6. FILES

**Mine, written:** `.agents/slop/vw-refusal-truth.py` (rewritten: upstream reading + the
corrected fixture + re-measured boundaries) · `.agents/slop/vw-boundaries.py` (new, 131 rows of
exhaustion) · `.agents/slop/c2d-refusal-rows.py` (new, the CPython side of the lane) ·
`.agents/slop/c2d-node4-truth.py` (new, the `s5_copy_sel` fixture identity) ·
`.agents/slop/validate-oracle.py` (loads the c2d module) · `tinybendygrad/uop/validate.bend`
(the `c2d` lane) · `.agents/slop/notes/bend2-constraints.md` (**appended CT-1..CT-5 at the END**,
numbering continues from `LN-6`).

**Not touched:** `uop/ops.bend` and every other `.bend`, `rebase-gate.py`, `helpers.bend`,
`LAWS/**`, `PROOF*.bend`.

**Deleted:** `.agents/slop/c2d-fixture-identity.py` (superseded by `c2d-node4-truth.py`) and
`tinybendygrad/uop/zz-probe-c2d.bend` (a staged scratch probe, never a deliverable; `jj status`
shows it as `D` against a snapshot that picked it up).

**Every number above came from running something twice with identical md5:**
`vw-refusal-truth.py` `68347a1a…` · `vw-boundaries.py` `91e4909e…` · `c2d-refusal-rows.py`
`52157572…` · `validate-oracle.py` `91842fa9…`.

## 7. OPEN ITEMS, FOR THEIR OWNERS

1. `uop/ops.bend` owner: widen `ops.bend:7009` to `Found | Refusal`, add `UOp.device`
   (`ops.py:887-899`), and delete `s5_copy_sel` from `ops.bend:7031`. Nineteen shared outcome
   rows are already waiting, seven of them red.
2. `device.bend` / `schedule/memory.bend` owners: **DISK is tag 6 in one ported table and tag 1
   in the other.** Until that is reconciled the DISK guard is not decidable, and `s5.dn(n)`'s
   tags are all `1`.
3. `uop/fold.bend` owner: `ops.py:763` needs a node's dtype, which is your fold.