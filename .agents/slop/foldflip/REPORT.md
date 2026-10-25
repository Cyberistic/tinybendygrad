# fold.bend -- the FLIP-era comments, re-pointed at the pin

**ONE FILE.** `tinybendygrad/uop/fold.bend`. **COMMENT-ONLY.** The code hash is
unchanged, the line count is unchanged, and the port's `Op` enum was NOT touched.

## 1. WHAT UPSTREAM ACTUALLY HAS AT THE PIN WHERE THE PORT SAID `FLIP`

The pin is `tinygrad/` tree `6c91e89777907c7b5b575372418750dec6068687`
(`.agents/UPSTREAM-PIN.md`'s OUR PIN `5c2bf39d6c4b`; the gate's own
`PIN_RECORD_DERIVE` names `45fc5ae734a2`, and BOTH carry that tree). `HEAD:tinygrad`,
`refs/remotes/upstream/master:tinygrad` and the pin are the SAME tree -- measured, not
assumed.

| what the port said | what upstream has AT THE PIN |
|---|---|
| `Ops.FLIP` exists | **NO `FLIP` AT ALL.** `tinygrad/uop/__init__.py` has no `FLIP`; the enum is 75 members. `900880433` ("remove Ops.FLIP [pr] (#18729)", 2026-10-11) DELETED it and took the enum 76 -> 75. |
| `GroupOp.Movement` has six arms | `tinygrad/uop/__init__.py:117` -- `Movement = {Ops.RESHAPE, Ops.EXPAND, Ops.PERMUTE, Ops.PAD, Ops.SHRINK}`. **FIVE arms, no FLIP.** |
| `case Ops.FLIP:` in `_shape`, at `ops.py:429-431` | **GONE.** The arm was `if len(ps) != len(self.marg) or not all(isinstance(x, bool) for x in self.marg): raise ValueError(f"bad flip on {ps}, {self.marg}")` then `return ps`. At `900880433`'s parent it was at `ops.py:412-413`; at the pin it is not in the file at all. |
| `case Ops.PERMUTE` / `case Ops.FLIP` at `ops.py:415-428` | `tinygrad/uop/ops.py:402-404` -- `case Ops.PERMUTE:` / `if sorted(self.marg) != list(range(len(ps))): raise ValueError(f"invalid permutation {self.marg} of len {len(ps)}")` / `return tuple(ps[i] for i in self.marg)`. It is an arm of `_shape` (`ops.py:323`), so the durable citation is `ops.py:402-404 symbol=_shape`. |
| `marg`'s `case Ops.PERMUTE \| Ops.FLIP: return self.arg` at `ops.py:815` / `ops.py:236` | `tinygrad/uop/ops.py:791-797` -- `@functools.cached_property def marg(self)` with THREE arms: `case Ops.RESHAPE \| Ops.EXPAND: return self.src[1].as_shape` (794), `case Ops.PAD \| Ops.SHRINK: return tuple(zip(...))` (795), `case Ops.PERMUTE: return self.arg` (796), `case _: raise RuntimeError(f"{self.op} is not a MovementOp")` (797). `ops.py:236` is `arg:Any = None` -- the `UOp.arg` FIELD, which is where `self.arg` comes from -- so the header's `ops.py:236` was always about the FIELD and never about `marg`. |
| `_mop`'s `case Ops.PERMUTE \| Ops.FLIP: src_args = []` | `tinygrad/uop/ops.py:799-813` -- `case Ops.PERMUTE: src_args = []` at **808**. No FLIP arm. |
| upstream's `flip` is an op | **A COMPOSITION.** `tinygrad/mixin/movement.py:233-268` -- `def flip(self, axis, *args) -> Self:` builds `_mop(Ops.PAD, ...)`, `_mop(Ops.SHRINK, ...)`, `.reshape` and `.transpose` and mints NO node of its own. |
| upstream's `spec.py` pattern covers PERMUTE and FLIP | `tinygrad/uop/spec.py:168` -- `(UPat(Ops.PERMUTE, name="mv", src=(UPat(),)), lambda mv: isinstance(mv.arg, tuple))`. **PERMUTE ONLY.** |
| upstream's `apply_movement_op` has a FLIP arm | `tinygrad/schedule/indexing.py:165-180` -- SHRINK, PERMUTE, EXPAND, PAD, RESHAPE. **No FLIP arm.** |

**THE PORT IS RIGHT.** `tinybendygrad/uop/fold.bend` implements NO FLIP arm; every
`FLIP` in it was inside a COMMENT. `69bfc2ee9` ("RE-INDEX Ops: GROUP and FLIP out,
77 -> 75") removed the port's `flip_ds` / `flip_len` defs and the `case O.OpsFLIP{}`
arm -- and left the COMMENTS behind. **THE DEFECT WAS A COMMENT AND NOTHING ELSE.**

## 2. EVERY COMMENT CHANGED

| fold.bend line | was | now |
|---|---|---|
| 28-35 (header) | "THREE OF THEM WERE NOT BEHIND THE WALL"; "`marg` for PERMUTE and FLIP is `self.arg` (ops.py:236)"; the five arms named `expand_ds, pad_ds, shrink_ds, perm_ds and flip_ds` | "ONE OF THEM"; "`marg` for PERMUTE is `self.arg` (ops.py:236 symbol=arg)"; the five arms are `reshape_ds, expand_ds, pad_ds, shrink_ds and perm_ds` -- "upstream's `GroupOp.Movement` is EXACTLY those five. FLIP IS GONE: `900880433` deleted it" |
| 2018 | "`marg` for PERMUTE and FLIP both" | "`marg` for PERMUTE (ops.py:796 symbol=marg)" |
| 2027-2046 (the orphaned block) | "# FLIP -- ops.py:429-431" + the whole CPython-bool-arg essay | "# THERE IS NO FLIP ARM HERE, and there is no FLIP in upstream either: `900880433` ... DELETED the member"; `tinygrad/uop/__init__.py:117 symbol=Movement`; "WHAT UPSTREAM DOES INSTEAD: `Tensor.flip` ... `tinygrad/mixin/movement.py:233 symbol=flip` ... a COMPOSITION"; "THE SURVIVING CONSTRUCT THIS BLOCK USED TO POINT AT IS `case Ops.PERMUTE:` -- ops.py:402-404 symbol=_shape ... and `marg`'s PERMUTE arm is ... (ops.py:796 symbol=marg); `perm_ds` is that arm." |
| 2642-2645 (the dispatch ladder) | "`case Ops.PERMUTE` / `case Ops.FLIP` -- ops.py:415-428 ... `marg` for both is `self.arg` (ops.py:815) ... See `perm_ds` and `flip_ds` above." | "`case Ops.PERMUTE:` -- ops.py:402-404 symbol=_shape ... `marg` for PERMUTE is `self.arg` (ops.py:796 symbol=marg) ... See `perm_ds` above. There is no `Ops.FLIP` arm." |
| 2725 | "the five movement arms this unit added are `expand_ds`, `pad_ds`, `shrink_ds`, `perm_ds`, `flip_ds`" | "... `reshape_ds`, `expand_ds`, `pad_ds`, `shrink_ds`, `perm_ds`" |
| 5411 | "the PERMUTE and FLIP src" | "the PERMUTE src" |
| 7000 | "PERMUTE \| FLIP -> `self.arg`" | "PERMUTE -> `self.arg`" |
| 7002-7003 | "RESHAPE, EXPAND, PAD, SHRINK, PERMUTE and FLIP all answer now" | "RESHAPE, EXPAND, PAD, SHRINK and PERMUTE all answer now" |
| 7242 (table header) | "the table is its output and nothing here is transcribed by hand." | "... by hand. RE-TAKEN 2026-10-25." |
| 7246 (M1) | 3 rows | 4 rows (`+mv_expsym_pos`) |
| 7247 (M2) | 5 rows | 6 rows (`+mmk_pad5`) |
| 7251 (M6) | "`flip_ds.put`: ... `mv_fliplen` (1) \| `len(ps) != len(self.marg)` -- the one reachable half of FLIP's `if`." | "**NOT APPLIED (0)** \| **DEAD WITH THE OP, AND IT SAYS SO.** The anchor is `flip_ds.put`, and that def is GONE: upstream removed `Ops.FLIP` at `900880433` and the port's FLIP arm went with it, so the harness reports 'the anchor text is not in the file' and the mutation cannot run at all." |
| 7257 (M11) | 2 rows | 3 rows (`+mmk_pad5`) |
| 7258 (M12) | 4 rows including `mv_flip` `mv_fliplen`; "It moves FIVE rows" | 3 rows (`mv_perm` `mv_permrep` `mv_permlen`); "`marg` for PERMUTE is `self.arg` (ops.py:796 symbol=marg) ... It moves THREE rows; the two FLIP rows it used to move are gone with the op" |
| 7259 (M13) | 2 rows | 4 rows (`+mv_expsym` `+mv_expsym_pos`) |
| 7267-7271 (the summary) | "**EIGHTEEN OF TWENTY-ONE MOVE ROWS.** The three zero-movers are `M9` and `M17b` ... and `M10`" | "**FIFTEEN OF TWENTY MOVE ROWS.** The five non-movers are `M6`, whose subject went with the op; `M9` and `M17b` ...; `M10` ...; and `L2`, the control." |
| 7273-7277 | "`ops.bend:763` ... See `flip_ds`'s header: CPython's own `isinstance(x, bool)` ..." | "`ops.bend:1237` ... The upstream op that carried such an arg is GONE (`900880433`), so this is about the ARENA now, and not about an upstream arm." |
| 1160 (a SELF-citation) | "`derived.put` (fold.bend:2477)" | "`derived.put` (fold.bend:2828)" -- `derived.put` is at 2828 today |

**THE MUTATION TABLE WAS RE-TAKEN, NOT EDITED BY HAND.** The table's own header says
"the table is its output and nothing here is transcribed by hand", and the numbers had
drifted because the tree grew since the last run. The instrument is the TRACKED
`oracles/fold-mut.py`; its `MUTATIONS` list is READ by `ast.literal_eval` (never
copied), and it was run against a SNAPSHOT of `tinybendygrad/` so that no
`fold.bend.mut` scratch file ever lands in the tree the substrate digest walks.
Baseline: **339 rows, both lanes identical.** M6 is **NOT APPLIED** -- the harness
says "the anchor text is not in the file", because `flip_ds.put` is gone. M12 moves
**3** rows, not 4. M1 4, M2 6, M11 3, M13 4; M3 M4 M5 M7 M8 M10b M14 M15 M16 M17
unchanged; M9 M10 M17b L2 still 0. **FIFTEEN MOVERS OF TWENTY ROWS.**

Instruments (working tree, `.agents/slop/foldflip/`, not committed):
`mut.py` (the mutation re-take), `plant.py` (the plant), `codehash.py` (the
comment-only proof). Row dumps: `mut-all.out`, `mut-tail.out`.

## 3. THE 29 FILES THAT CITE `fold.bend`, AND THE STALE CLAIMS AMONG THEM

MEASURED: **28 TRACKED `.bend` files cite `fold.bend` BY LINE** (`fold.bend:NNN`) --
27 others plus `fold.bend`'s own self-cite -- and **one UNTRACKED scratch copy**
(`tinybendygrad/codegen/late/.linearizer-mut.bend`) makes **29**. **52 TRACKED files
cite `fold.bend` BY NAME.** There are **78 `fold.bend:NNN` citations** in the tree.

### 3a. THE FILES THAT REPEAT A STALE FLIP CLAIM -- REPORTED, NOT EDITED

| file | lines | the stale claim |
|---|---|---|
| `tinybendygrad/uop/ops.bend` | 1173-1182 | "`ops.py:428` asserts `all(isinstance(x, bool) for x in self.marg)`"; "`UOp(Ops.FLIP, src, (1, 0))` RAISES `bad flip on (7, 3), (1, 0)`" -- upstream has no `Ops.FLIP`; it also names `fold.bend`'s `order_arg` as reading a FLIP's arg, and fold.bend's `order_arg` matches `O.ATuple` and `O._` only |
| `tinybendygrad/uop/ops.bend` | 1238-1246 | "`tuple[bool, ...]` -- FLIP's arg, and the ONLY reason upstream's `Ops.FLIP` has a guard"; "`spec.py:166` asserts `isinstance(mv.arg, tuple)` over PERMUTE and FLIP TOGETHER" -- upstream's is `spec.py:168`, PERMUTE ONLY |
| `tinybendygrad/uop/spec.bend` | 1755 | "`spec.py:166 (UPat((Ops.PERMUTE, Ops.FLIP), name=\"mv\", ...))`" -- upstream's `spec.py:168` is PERMUTE ONLY. **THE CODE IS RIGHT** (`OP_PERMFLIP` returns `[O.OpsPERMUTE{}]`); only the comment quotes the old upstream |
| `tinybendygrad/uop/spec.bend` | 2058 | `O.PMEntry{7, OP_PERMFLIP(), Nil{}},   # 166` -- the spec.py line marker is 168 at the pin |
| `tinybendygrad/mixin/movement.bend` | 69, 95, 780, 786, 1198, 1308, 1331 | "`fold.bend:1620-1626` answers `None{}` for PERMUTE, EXPAND, PAD, SHRINK and FLIP" -- fold.bend:1620-1626 is `sym_dim.end` TODAY, and fold.bend answers all five movement arms |
| `tinybendygrad/mixin/movement.bend` | 523-538, 554, 577, 713, 803-807, 825, 1003, 1159, 1277 | upstream's `marg` quoted as `case Ops.PERMUTE \| Ops.FLIP: return self.arg`; "the FLIP arm (ops.py:429)"; "A FLIP's marg is a list of 0/1 FLAGS" -- all pre-`900880433` upstream |
| `tinybendygrad/mixin/op.bend` | 62, 152 | "`fold.bend:1622-1625` leaves PERMUTE, EXPAND, PAD, SHRINK and FLIP un-answered"; "the five ops `dt_shape` defers (fold.bend:1622-1625)" |
| `tinybendygrad/nn/onnx.bend` | 85, 1942 | "`fold.bend:1620-1626`'s refusal to answer EXPAND/SHRINK/PAD/FLIP"; "fold.bend refuses EXPAND/SHRINK/PAD/FLIP" |
| `tinybendygrad/codegen/late/linearizer.bend` (+ the untracked `.linearizer-mut.bend`) | 101 | "`uop/fold.bend` cannot answer for PAD/SHRINK/EXPAND/FLIP (`fold.bend:1620-1626`)" |
| `tinybendygrad/schedule/indexing.bend` | 46, 579, 594 | quotes upstream's OLD `apply_movement_op` (indexing.py:170-187) WITH a FLIP arm; upstream's at the pin (indexing.py:165-180) has none. (The other five mentions there are the PORT's own indexer flip decision and are fine.) |
| `tinybendygrad/schedule/prepare.bend` | 269-271 | "PERMUTE and FLIP take their marg in the ARG (`ops.py:818`)" -- `marg` is at 792 at the pin, and there is no FLIP |
| `tinybendygrad/schedule/prepare.bend` | 367 | a diagnostic dump whose op list still names `FLIP` and `GROUP` |
| `tinybendygrad/schedule/multi.bend` | 1461 | "A FLIP's marg is a per-axis BOOL (ops.py:812's `if self.op is Ops.FLIP:`" -- neither the arm nor the line exists at the pin |
| `tinybendygrad/tensor.bend` | 1611, 2600 | `MopArg`'s `AOrder` is labelled "PERMUTE / FLIP: `src_args = []`"; "FLIP and PERMUTE, the `src_args = []` arm" -- upstream's `_mop` has `case Ops.PERMUTE: src_args = []` and no FLIP arm |

**ALREADY CORRECTED IN THE TREE (not stale, listed so the census is complete):**
`mixin/movement.bend:25` ("`Ops.FLIP` is NOT IN upstream at this pin") and
`mixin/movement.bend:1545-1557` (the "UPSTREAM HAS NO `Ops.FLIP` AND HAS NOT FOR A
WEEK" block) -- **THIS IS THE PATTERN THIS CHANGE FOLLOWS**; and
`tensor.bend:3114-3115` ("`Ops.FLIP` does not exist at the pin `5c2bf39d6c4b`").

### 3b. A BIGGER, SEPARATE DEFECT THE CENSUS FOUND -- REPORTED, NOT EDITED

**78 citations point at `fold.bend` BY LINE, AND MOST NOW POINT AT THE WRONG LINE**,
because `fold.bend` has grown since they were written. Measured examples:
`fold.bend:1620-1626` is `sym_dim.end` (7 files claim it is the movement-arm
deferral); `fold.bend:1537` is `pre_all` (4 files claim `reshape_ds`); `fold.bend:999`
is blank (5 files claim `F.alu_ds`); `fold.bend:2176` is a comment (4 files claim a
`Counter` fold); `fold.bend:4038` is `mm.bin.enter`; `fold.bend:4013` is a dtype
match; `fold.bend:4372` is `mm.lift.mv`. **STILL CORRECT:** `fold.bend:2608-2630`
(`dt_shape`), `fold.bend:4764` (`fold.shape`), `fold.bend:5081` (the `_min_max`
walk), and roughly `fold.bend:1949`, `2430-2436`, `4059`, `6540`.

**NO INSTRUMENT READS A `.bend` CITATION.** `gates/todo-cite-gate.py` judges only
`.py` subjects ("a `.bend` subject is the port's own file and is not an upstream
citation at all") and `gates/pin-cite-gate.py` reads a file's HEADER BLOCK only. So
these 78 pointers are UNMEASURED, which is why they rotted. **THE DURABLE FORM DOES
NOT EXIST FOR THEM**: the `symbol=` field is admitted only for `.py` subjects. **THE
FIX IS STRUCTURAL -- a name-based citation for a `.bend` target -- and not a line
number that will rot again the next time that file's owner edits it.** I did not fix
these: they are in OTHER UNITS' files, they are not FLIP claims, and the mechanical
fix is the wrong fix.

## 4. VERIFICATION

**COMMENT-ONLY** -- `checks/port-compile-gate.py`'s OWN `strip_comments()` (loaded BY
PATH), blank lines dropped, sha256 over the stripped code:

    lines            live=7393 head=7393 SAME
    code sha256      live=7cad89603cc594401007f47d1f9c2bbd26838c42d0addd1b780662d7688e2bb0
                     head=7cad89603cc594401007f47d1f9c2bbd26838c42d0addd1b780662d7688e2bb0
    VERDICT          COMMENT-ONLY

**THE LINE COUNT IS UNCHANGED ON PURPOSE.** `fold.bend`'s line numbers are an
INTERFACE -- 28 other tracked files cite them -- so a comment-only edit here must not
move a code line. 7393 before, 7393 after.

**COMPILE** -- one `bend` at a time, verdict TOKEN read and not the exit code:

    .venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend tinybendygrad/uop/fold.bend
    [bounded] WITHIN-LIMITS  rc=0  peak-RSS=584 MB (ceiling 2048)  1s

(`fold.bend`'s measured peak in `.agents/slop/peakrss/census.rows:127` is **484 MB**;
the observed 584-694 MB across three runs is under the 2048 MB ceiling.)

**THE CITATION GATES.** `gates/todo-cite-gate.py` (the `symbol=` population, which is
the one that reads the re-pointed citations):

    BEFORE   1131 citations in 97 files   0 WRONG-LINE  0 WRONG-SYMBOL  0 UNRESOLVABLE   PASS
    AFTER    1141 citations in 97 files   0 WRONG-LINE  0 WRONG-SYMBOL  0 UNRESOLVABLE   PASS

(The +10 are the ten new `symbol=` fields, and all ten RESOLVE.) `gates/pin-cite-gate.py`
reads only the HEADER BLOCK, and fold.bend's five header citations are all still
`at_pin`; the ONE remaining dangling claim in the tree is
`tinybendygrad/renderer/ptx.bend:31`, which is not mine. **BEFORE and AFTER were
re-measured on FROZEN TREES with the SAME gate version** (`--tree`), because the gate
file itself was being edited by another unit during this session:

    PIN-BEFORE  cite.total=2588 cite.at_pin=1333 cite.at_no_revision_dangling=2
    PIN-AFTER   cite.total=2588 cite.at_pin=1333 cite.at_no_revision_dangling=2

**THE PLANT** -- a TEXT EDIT on a COPY of the LIVE file (never `git show HEAD:`), plus
a BYTE-IDENTICAL copy:

    BEFORE  : the live tree with THIS CHANGE'S OWN DIFF REVERSED (a text edit, not a
              materialised commit)
    CONTROL : byte-identical to the live file (424286 bytes)
    PLANT   : ops.py:796 symbol=marg -> ops.py:801 symbol=marg  (the citation occurs
              4 times; ONE was edited)

    LIVE     rc=0  POPULATION : 1141 citations   # todo-cite-gate: PASS
    CONTROL  rc=0  POPULATION : 1141 citations   # todo-cite-gate: PASS
    PLANTED  rc=1  POPULATION : 1141 citations   # todo-cite-gate: FAIL -- 1 of 1141
                                                             marker citations are false

    and the RED ROW IS THE ONE I BROKE:
      tinybendygrad/uop/fold.bend:2018  ops.py:801  symbol=marg  how=symbol-moved
        the cited line does not hold the claim; `marg` is declared at :792

**A CITATION THAT CANNOT GO RED IS A LABEL.** The ten re-pointed citations are now
`symbol=` rows, so a line number that drifts becomes a `WRONG-LINE` row and not a
silent falsehood.

**THE SUBSTRATE DIGEST** (the corpus's freshness pin; it covers the WORKING TREE, so
any `.bend` edit moves it):

    BEFORE (session start)          a48f77449a582ba868191c371270c3fb1f3750dae2300e20a593ef64236da85b
    AFTER  (this change committed)   123ad85e6722fc5145d04bc4c51c7dfc7498ff5c749aee6d9cd64faf6d996937

    CONTROLLED ATTRIBUTION (computed by re-hashing the 416 digest entries with
    fold.bend's blob swapped, WITHOUT touching the tree):
      digest with fold.bend at HEAD  4394046a4ecf4221e7e43684b20cec1cdfe059ead735b5a14652edb78e23c207
      digest with fold.bend at LIVE  123ad85e6722fc5145d04bc4c51c7dfc7498ff5c749aee6d9cd64faf6d996937
      digest WITHOUT fold.bend       0b4293e4fc5ea1b1ca944ad039802e527cd44989bc249d1bd561889e3237d53e

    ⇒ MY EDIT IS EXACTLY THE DIFFERENCE BETWEEN THE FIRST TWO. The
      `a48f7744 -> 123ad85e` move ALSO contains **34 OTHER UNITS' IN-FLIGHT EDITS**
      under `tinybendygrad/` (measured with `git status --porcelain -- tinybendygrad/`),
      which is why the controlled attribution is stated and the raw move is not
      attributed to this change alone.

## 5. WHAT I DID NOT FIX, AND WHY

1. **THE 78 STALE `fold.bend:NNN` POINTERS IN OTHER FILES** (section 3b). They are
   in other units' files, they are not FLIP claims, and the mechanical fix (nudging a
   line number) is the WRONG fix: no instrument reads a `.bend` citation and the
   target file is under another unit's edit right now, so the pointer rots again.
   **THE FIX IS A NAME-BASED CITATION FOR A `.bend` TARGET**, and that instrument does
   not exist yet.
2. **THE TEN FILES THAT REPEAT THE STALE FLIP CLAIM** (section 3a). Reported, not
   edited: the brief owns `fold.bend` only, and `ops.bend` / `spec.bend` /
   `mixin/movement.bend` / `schedule/*` / `tensor.bend` may be held by other units.
3. **THE CODE.** Nothing in the port needed changing. The port's `Op` enum is exactly
   upstream's 75 members, 0 missing, 0 extra; `fold.bend` implements no FLIP arm; and
   `fold.bend`'s `order_arg` matches `O.ATuple{ys}` and `O._`, so a bool arg can no
   longer reach it. **THE COMMENTS WERE THE ONLY THING WRONG.**
4. **THE `ops.bend:NNN` POINTERS INSIDE `fold.bend` ITSELF** -- `ops.bend:823`
   (claimed `SInt.uop`, which is at 815), `ops.bend:940` (claimed `AInk`, which is at
   1248), `ops.bend:3036` (claimed `UOp.new.param`) -- measured STALE and REPORTED, not
   fixed, for the reason in (1): `ops.bend` is another unit's file and is being edited
   right now, so a line number written today is wrong tomorrow. The ONE `.bend`
   pointer inside `fold.bend` that points at `fold.bend` -- `derived.put (fold.bend:2477)`
   -- WAS fixed, because fold.bend is this unit's file and this change does not move
   its line count.
5. **`oracles/fold-mut.py` ITSELF.** Its `M6` entry is a mutation whose anchor no
   longer exists, so the harness PRINTS "NOT APPLIED" for it -- which is the honest
   outcome and not a crash, but the entry is dead weight in a tracked oracle. It is
   another unit's file. **`oracles/fold-mut.rows` IS A STALE RECORD** (dated Oct 5,
   baseline "27 rows"; today 339) and it disagrees with the table in fold.bend. It is
   another unit's file and I did not edit it.
6. **THE COMMIT** -- see below.
