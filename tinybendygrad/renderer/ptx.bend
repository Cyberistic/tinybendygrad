# ptx.bend -- tinygrad/renderer/ptx.py: `render`'s NAMING WALK, ptx.py:171-229
#

# `renderer/tc_ptx.bend` already ports ptx.py's EMITTERS -- `render_val`, the
# twenty-one `asm_for_op` entries, `supports_half`/`doesnt_support_half`,
# `modifier`, `mem_type`, `render_wmma` and its two `dt_map`s, the three dtype
# tables, `supported_dtypes`, `tensor_cores`, `fmt` and `render_kernel`'s HEADER
# -- because tc.py and ptx.py are one feature. This file redefines NONE of it.
#
# What tc_ptx.bend's header calls STAGE 3 and names NOT STARTED is here: the
# `ssa` COUNTER (ptx.py:180-183), the per-op register assignment (ptx.py:185-221),
# the `.reg` DECLARATIONS `render_kernel` prepends from `c.items()` (ptx.py:165),
# the `bufs` collection (ptx.py:210), the entry-point NAME (ptx.py:173, 192-193)
# and the ONE REFUSAL the walk raises (ptx.py:204).
#
# NOT HERE, and named rather than faked:
#   * `string_rewrite` (ptx.py:81-135) -- twenty-three graph-pattern rules whose BODY
#     is an f-string over `ctx.r[x]`. It is CONSUMABLE exactly once the walk
#     below supplies `ctx.r`, so it is the natural NEXT file and not a wall.
#
#     ONE OF THOSE RULES IS THE **ADDRESS ARITHMETIC** AND IT IS THE ONE
#     THAT IS NOT A SPELLING: "address computation: addr = buf + idx*itemsize"
#     -- ptx.py:87, upstream's comment ON THE `Ops.INDEX`/`Ops.SHRINK` RULE.
#     IT EMITS **TWO** LINES AND NOT ONE:
#       * `cvt.s64.{TYPE} {x}, {idx};` -- THE INDEX IS **CONVERTED** TO A
#         64-BIT SIGNED INTEGER, AND `{TYPE}` IS THE **INDEX'S OWN** DTYPE
#         (`ctx.types[idx.dtype]`), SO THE CONVERSION'S WIDTH IS CHOSEN BY
#         THE INDEX AND NOT BY THE BUFFER. PTX'S ADDRESS ARITHMETIC IS
#         64-BIT, SO A 32-BIT INDEX MUST BE WIDENED, AND THE `s64` MEANS
#         **SIGNED** -- A NEGATIVE INDEX IS A LEGAL WAY TO ADDRESS (AN
#         OFFSET FROM THE END).
#       * `mad.lo.s64 {x}, {x}, {itemsize}, {buf};` -- AND THEN THE SCALE IS
#         FOLDED INTO A MULTIPLY-ADD: THE ADDRESS IS `buf + idx *
#         ITEMSIZE`. SO THE **ITEM SIZE** IS THE BUFFER'S ELEMENT WIDTH,
#         NOT A CONSTANT, AND IT IS THE THIRD OPERAND OF THE `mad`.
#     WHICH IS THE POINT OF THE TWO LINES: THE INDEX IS IN **ELEMENTS** AND
#     THE ADDRESS IS IN **BYTES**, AND THE CONVERSION IS NOT A NO-OP
#     COSMETIC BUT A SIGN CHANGE: A `u32` INDEX SIGN-EXTENDED TO 64 BITS IS
#     A DIFFERENT NUMBER, AND WHICH ONE IS RIGHT DEPENDS ON WHETHER THE
#     INDEX WAS SIGNED TO BEGIN WITH.
#   * `ptx_matcher` (ptx.py:40-57) -- eight graph REWRITES, and tc_ptx.bend's
#     `DONE(p3)`/`WALL(p3)` block over ptx.py:40-57 `ptx_matcher` is where each
#     of the eight is recorded -- upstream's `ptx_matcher` IS that PatternMatcher
#     and it opens at :40.
#     `TODO(p3) ptx.py:40 symbol=ptx_matcher`.
#
#     THE **REASONS** FOR THE EIGHT ARE WORTH NAMING HERE, BECAUSE A WALL
#     WITH NO REASON IS A WALL A READER CANNOT SIZE, AND THREE OF THE EIGHT
#     ARE **TARGET CONSTRAINTS** THAT ANY READER OF THE EMITTED PTX NEEDS:
#       * "bool CMPNE is XOR, bool CMPLT is XOR+AND (universal makes this
#         slow, this is for renderer only)" -- ptx.py:41. THE PARENTHESIS
#         IS THE REASON AND IT IS A **SCOPE** CLAIM: A `bool` COMPARE HAS A
#         GENERAL SPELLING SOMEWHERE UPSTREAM -- THE "UNIVERSAL" ONE -- AND
#         THAT ONE IS SLOW, SO THE RENDERER MAY USE A CHEAPER SPELLING: A
#         `bool` CMPNE IS AN **XOR** (TWO BOOLEANS ARE DIFFERENT EXACTLY
#         WHEN THEIR BITS DIFFER) AND A `bool` CMPLT IS **XOR+AND** (XOR
#         FOR "DIFFERENT" AND AND FOR "THE LARGER ONE'S BIT").
#         "THIS IS FOR RENDERER ONLY" IS SAYING THAT THIS REWRITE IS A
#         **RENDERER-LOCAL** SPELLING AND NOT A CHANGE TO WHAT A `bool`
#         COMPARE MEANS. THE SAME REWRITE APPEARS IN `x86.py:143` FOR THE
#         SAME REASON AND WITH THE SAME `bool`-ONLY MATCH, SO THE TWO
#         RENDERERS AGREE WITHOUT A SHARED TABLE.
#       * "a bool is a predicate register in PTX but a byte in memory, so a
#         bool buffer is accessed through a uint8 view of it" -- ptx.py:48.
#         PTX HAS A **DEDICATED PREDICATE REGISTER TYPE** FOR BOOLEANS AND
#         MEMORY HOLDS A **BYTE**. SO A `bool` BUFFER IS ADDRESSED AS
#         `uint8` AND THE PREDICATE IS PRODUCED BY A COMPARISON, NOT READ.
#         THE SAME RULE IS IN `nir.py` (nir.py:124) WITH A DIFFERENT BECAUSE:
#         NIR'S `bool` IS A **ONE-BIT VALUE**, NOT A PREDICATE REGISTER.
#       * "ptx shr and shl instructions require y to be uint" -- ptx.py:54.
#         THE SHIFT **AMOUNT** MUST BE UNSIGNED, SO A SIGNED COUNT IS CAST
#         TO `uint` FIRST. NIR'S RULE (nir.py:130) IS THE SAME CAST FOR A
#         DIFFERENT REASON -- NIR WANTS A **32-BIT** AMOUNT, PTX WANTS AN
#         **UNSIGNED** ONE -- AND THE TWO WOULD DISAGREE ABOUT A `u16`
#         COUNT, SO THE TWO RENDERERS MUST NOT SHARE ONE RULE.
##   * `to_function_name`'s `ansistrip` (tinygrad/helpers.py:157) -- a regex ANSI strip.
#     The KEEP/HEX branch is ported and gated; the strip is the wall.
#   * `Ops.WMMA`'s `wmma_r` (ptx.py:211-216) -- it needs the three fragment
#     tables, which are tc_ptx.bend's `Tc`, and it is named in its ARM.
#
#     UPSTREAM'S COMMENT ON IT IS "registers for packing/unpacking input and
#     acc" (ptx.py:212), AND THE THREE TABLES ARE NOT INTERCHANGEABLE --
#     THE COMMENT'S THREE WORDS ARE THREE DIFFERENT JOBS:
#       * `wmma_in` -- the **PACKING** REGISTERS. A AND B ARE COPIED INTO
#         32-BIT REGISTERS BEFORE THE `mma` INSTRUCTION, AND THE NUMBER OF
#         THEM IS `len(r[src]) / (4 // src.dtype.itemsize)`: FOUR `f16`
#         ELEMENTS PER 32-BIT REGISTER, EIGHT `f8` ELEMENTS. SO THE COUNT
#         DEPENDS ON THE **INPUT** DTYPE AND NOT ON K.
#       * `wmma_acc` -- the **ACCUMULATOR** REGISTERS. THESE ARE THE `mma`'S
#         OWN DESTINATION, SO THEIR COUNT IS `len(r[src[2]]) /
#         (4 // OUTPUT.dtype.itemsize)` -- THE OUTPUT dtype, WHICH IS NOT
#         THE INPUT dtype.
#       * `wmma` -- the **UNPACKING** REGISTERS. THE RESULT IS COPIED OUT OF
#         THE ACCUMULATOR REGISTERS INTO ONE REGISTER PER RESULT ELEMENT.
#     SO THE THREE TABLES ARE COUNTED BY **THREE DIFFERENT DTYPES** -- TWO
#     INPUTS AND ONE OUTPUT -- AND THE PORT NAMES THE WALL RATHER THAN
#     GUESSING AT THE COUNTS, BECAUSE A COUNT THAT IS RIGHT FOR ONE OF THE
#     THREE IS WRONG FOR THE OTHERS.
#
#     ⚠ AND UPSTREAM'S OWN B COUNT USES **A's** DTYPE, NOT B's:
#     `range(0, len(r[u.src[1]]), 4 // u.src[0].dtype.itemsize)` -- THE
#     DIVISOR READS `src[0]` IN **BOTH** LISTS (ptx.py:213-214). WHICH IS
#     CORRECT BECAUSE A AND B MUST HAVE THE SAME ELEMENT WIDTH FOR THE
#     `mma` AT ALL -- A `f16` A WITH AN `f8` B IS NOT A LEGAL MMA -- SO
#     READING A's DTYPE TWICE IS A WAY OF SAYING "THEY ARE THE SAME" AND
#     NOT A TYPO. BUT IT IS A **COUNT** THAT DEPENDS ON A DIFFERENT NODE
#     THAN THE COUNT IT SAYS, AND A PORT THAT READ `src[1]`'S DTYPE FOR
#     THE SECOND LIST WOULD AGREE WITH UPSTREAM ON EVERY LEGAL GRAPH AND
#     DISAGREE ON AN ILLEGAL ONE.
#

# THE GATE. 281 rows, all STRINGS, and `py=` is a LITERAL, never an expression:
#   .venv/bin/python gates/ptx_render_census-oracle.py > /tmp/s3py.rows
#   ./bin/bend tinybendygrad/renderer/ptx.bend          > /tmp/bd.rows
#   ./bin/bend tinybendygrad/renderer/ptx.bend -o /tmp/p3 && /tmp/p3 > /tmp/bdn.rows
#   diff /tmp/bd.rows  /tmp/s3py.rows
#   diff /tmp/bdn.rows /tmp/s3py.rows
# RETARGETED 2026-10-16. These four lines read `.agents/slop/ptx-s3-oracle.py` and
# `.agents/slop/ptxown/{s3py,bd,bdn}.txt`; the oracle was deleted by the sweep of 2026-10-05
# (blob e853efc4b, 13071 B) and `ptxown/` is gone with it. The oracle that replaced it is
# `gates/ptx_render_census-oracle.py`, MEASURED rc=0 at 593 rows from `gates/`. The path

import Base
import ./tc_ptx.bend as P
import ./tc.bend as T
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O

# THE STATE. `r` is `dict[UOp, str | list[str]]` (ptx.py:176), `c` is a

type Rg is Data:
  Rg{is_list: Bool, parts: List<&2, String>}
def Rg.l(r: Rg) -> Bool:
  match r:
    case Rg{is_list, parts}: is_list
def Rg.p(r: Rg) -> List<&2, String>:
  match r:
    case Rg{is_list, parts}: parts

# `f"{x}"` for the scalar and `"{" + ", ".join(x) + "}"` for the list. Both arms
# are separate rows: a `String.concat` that drops a brace is invisible to a Bool.
def rgl.of(+r: Rg) -> String:
  Bool.pick(String, Rg.l(r), String.concat(["{", String.join(Rg.p(r), ", "), "}"]),
    Maybe.default(&2, String, List.get(&2, String, Rg.p(r), 0n), ""))

type Cnt is Data:
  Cnt{key: String, ty: String, n: U32}
def Cnt.n(+c: Cnt) -> U32:
  match c:
    case Cnt{key, ty, n}: n
def Cnt.key(+c: Cnt) -> String:
  match c:
    case Cnt{key, ty, n}: key
def Cnt.ty(+c: Cnt) -> String:
  match c:
    case Cnt{key, ty, n}: ty

# `Wal.ref` is `""` while the walk is healthy and the offending OP'S NAME once
# ptx.py:204 has fired -- which also STOPS the walk, because in CPython the
# raise ends `render` and nothing after it is computed.
type Wal is Data:
  Wal{r: List<&2, Rg>, c: List<&2, Cnt>, kern: List<&2, String>, nm: String, ref: String}
def Wal.r(w: Wal) -> List<&2, Rg>:
  match w:
    case Wal{r, c, kern, nm, ref}: r
def Wal.c(w: Wal) -> List<&2, Cnt>:
  match w:
    case Wal{r, c, kern, nm, ref}: c
def Wal.kern(w: Wal) -> List<&2, String>:
  match w:
    case Wal{r, c, kern, nm, ref}: kern
def Wal.nm(w: Wal) -> String:
  match w:
    case Wal{r, c, kern, nm, ref}: nm
def Wal.ref(w: Wal) -> String:
  match w:
    case Wal{r, c, kern, nm, ref}: ref
def Wal.rset(+w: Wal, +rs: List<&2, Rg>) -> Wal: Wal{rs, Wal.c(w), Wal.kern(w), Wal.nm(w), Wal.ref(w)}

# ONE ENTRY PER STEP, always. `r[u] = ...` SETS one key of a dict, but `Wal.r` is
# POSITIONAL -- `r[i]` and `refs` are step indices -- so the walk APPENDS an
# EMPTY `Rg` for a step that produced no register. Without that, `f14_skips`'s
# three skipped steps shift every later index and the `.reg` block is right while
# every `r` row names the wrong node. MEASURED: `nr=1` over three steps.
def Wal.rput(+w: Wal, r: Rg) -> Wal: Wal.rset(w, List.append(&2, Rg, Wal.r(w), [r]))
def Wal.cset(+w: Wal, +cs: List<&2, Cnt>) -> Wal: Wal{Wal.r(w), cs, Wal.kern(w), Wal.nm(w), Wal.ref(w)}
def Wal.kset(+w: Wal, +ks: List<&2, String>) -> Wal: Wal{Wal.r(w), Wal.c(w), ks, Wal.nm(w), Wal.ref(w)}
def Wal.nset(+w: Wal, n: String) -> Wal: Wal{Wal.r(w), Wal.c(w), Wal.kern(w), n, Wal.ref(w)}
def Wal.refset(+w: Wal, s: String) -> Wal: Wal{Wal.r(w), Wal.c(w), Wal.kern(w), Wal.nm(w), s}

def wal0() -> Wal: Wal{Nil{}, Nil{}, Nil{}, "test", ""}

# ONE uOP of the walk, in toposort order, carrying EXACTLY what `render` reads
# of it. `addr` is the node's OWN address space for BUFFER/PARAM and `src[0]`'s
# for INDEX/SHRINK/LOAD -- the only way those two reads are told apart.
# `refs` are INDICES into the registers emitted SO FAR; `idx` is
# `src[1].src[0].val` (ptx.py:205) and `idx_ok` is ptx.py:203's CONST-of-CAST guard.
type Wk is Data:
  Wk{op: O.Op, dt: S.Dt, addr: S.Addr, nmn: U32, nm: String, refs: List<&2, U32>, idx: U32, idx_ok: Bool}
def Wk.op(w: Wk) -> O.Op:
  match w:
    case Wk{op, dt, addr, nmn, nm, refs, idx, idx_ok}: op
def Wk.dt(w: Wk) -> S.Dt:
  match w:
    case Wk{op, dt, addr, nmn, nm, refs, idx, idx_ok}: dt
def Wk.addr(w: Wk) -> S.Addr:
  match w:
    case Wk{op, dt, addr, nmn, nm, refs, idx, idx_ok}: addr
def Wk.nmn(w: Wk) -> U32:
  match w:
    case Wk{op, dt, addr, nmn, nm, refs, idx, idx_ok}: nmn
def Wk.nm(w: Wk) -> String:
  match w:
    case Wk{op, dt, addr, nmn, nm, refs, idx, idx_ok}: nm
def Wk.refs(w: Wk) -> List<&2, U32>:
  match w:
    case Wk{op, dt, addr, nmn, nm, refs, idx, idx_ok}: refs
def Wk.idx(w: Wk) -> U32:
  match w:
    case Wk{op, dt, addr, nmn, nm, refs, idx, idx_ok}: idx
def Wk.idx_ok(w: Wk) -> Bool:
  match w:
    case Wk{op, dt, addr, nmn, nm, refs, idx, idx_ok}: idx_ok

# `ssa` -- ptx.py:180-183, the whole of it:
def Cnt.is(c: Cnt, key: String) -> Bool: String.eq(Cnt.key(c), key)

def cnt_n(+cs: List<&2, Cnt>, +key: String) -> U32:
  match cs:
    case Nil{}        : 0
    case c <> +t      : Bool.pick(U32, Cnt.is(c, key), Cnt.n(c), cnt_n(t, key))

# BOTH ARMS GROW FROM THE HEAD. `List.append(a, b)` is `a ++ b`, and a hit
# REPLACES the head while a miss KEEPS it -- so the hit arm is `[bumped] ++ t`
# and the miss arm is `[c] ++ recurse(t)`. MEASURED both wrong ways: growing
def cnt_bump(+cs: List<&2, Cnt>, +key: String, +ty: String, +k: U32) -> List<&2, Cnt>:
  match cs:
    case Nil{}   : [Cnt{key, ty, k}]
    case c <> +t :
      +rest = cnt_bump(t, key, ty, k)
      Bool.pick(List<&2, Cnt>, Cnt.is(c, key),
        List.append(&2, Cnt, [Cnt{key, ty, U32.add(Cnt.n(c), k)}], t),
        List.append(&2, Cnt, [c], rest))

def pkey(+prefix: String, +ty: String) -> String: String.concat([prefix, "_", ty, "_"])
def ssa_name(+key: String, n: U32) -> String: String.concat(["%", key, U32.show(n)])

# `k` `ssa` calls under ONE key. The counter is bumped ONCE, so the names are
# the key's series positions `n .. n+k-1` -- which is what makes a vector LOAD
# continue a previous LOAD's series rather than starting a second one (`f10`:
# 0..7, 8..15, 16..23, one `.reg .f32 %val_f32_<24>`).
type Ssa2 is Data:
  Ssa2{c: List<&2, Cnt>, ps: List<&2, String>}
def Ssa2.c(s: Ssa2) -> List<&2, Cnt>:
  match s:
    case Ssa2{c, ps}: c
def Ssa2.ps(s: Ssa2) -> List<&2, String>:
  match s:
    case Ssa2{c, ps}: ps

def ssa_many.ago(k: Nat, +n: U32, +c: List<&2, Cnt>, +key: String) -> Ssa2:
  match k:
    case 0n    : Ssa2{c, Nil{}}
    case 1n+fm :
      +rest = ssa_many.ago(fm, U32.add(n, 1), c, key)
      Ssa2{Ssa2.c(rest), List.append(&2, String, [ssa_name(key, n)], Ssa2.ps(rest))}

# the bump is `k`, not one. measured: ptx.py:199 and 209 call `ssa` once per
def ssa_many(+cs: List<&2, Cnt>, +key: String, +ty: String, +k: U32) -> Ssa2:
  Bool.pick(Ssa2, U32.is_eq(k, 0), Ssa2{cs, Nil{}},
    ssa_many.ago(U32.to_nat(k), cnt_n(cs, key), cnt_bump(cs, key, ty, k), key))

# THE TABLE IS IN `.agents/slop/tables/renderer-ptx-339.md` -- THE PREFIX TABLE -- ptx.py:217-219, plus ptx.py:198-209's three allocating

type Pf is Data:
  Pf{has: Bool, prefix: String, ty: String, k: U32, lst: Bool}
def Pf.has(p: Pf) -> Bool:
  match p:
    case Pf{has, prefix, ty, k, lst}: has
def Pf.prefix(p: Pf) -> String:
  match p:
    case Pf{has, prefix, ty, k, lst}: prefix
def Pf.ty(p: Pf) -> String:
  match p:
    case Pf{has, prefix, ty, k, lst}: ty
def Pf.k(p: Pf) -> U32:
  match p:
    case Pf{has, prefix, ty, k, lst}: k
def Pf.lst(p: Pf) -> Bool:
  match p:
    case Pf{has, prefix, ty, k, lst}: lst

def no_pf() -> Pf: Pf{False{}, "", "", 0, False{}}
def pf1(p: String, ty: String, k: U32, l: Bool) -> Pf: Pf{True{}, p, ty, k, l}

# CONSUMED, not re-derived: the twelve-arm `types` table is tc_ptx.bend's.
def pf.ty_of(+ty: String, +dt: S.Dt) -> String: Bool.pick(String, String.is_empty(ty), P.types_of(dt), ty)

def is_op(+op: O.Op, +o2: O.Op) -> Bool: O.eq_op(op, o2)
def is_idx(+op: O.Op) -> Bool: Bool.or(is_op(op, O.OpsINDEX{}), is_op(op, O.OpsSHRINK{}))
def is_reg(+op: O.Op, +addr: S.Addr) -> Bool: Bool.and(is_op(op, O.OpsBUFFER{}), O.eq_addr(addr, S.AReg{}))
def is_global(+addr: S.Addr) -> Bool: O.eq_addr(addr, S.AGlobal{})
# ptx.py:201 -- `u.src[0].addrspace in (AddrSpace.REG, AddrSpace.ALU)`. ALU IS
# the special's own address space (ops.py:899), which is why a LOAD of a
# SPECIAL is a copy and not a memory read.
def on_regsrc(+op: O.Op, +addr: S.Addr) -> Bool:
  Bool.and(Bool.or(is_idx(op), is_op(op, O.OpsLOAD{})),
    Bool.or(O.eq_addr(addr, S.AReg{}), O.eq_addr(addr, S.Aalu{})))

# ptx.py:220 -- `if u.op is Ops.RANGE and u.dtype == dtypes.void: prefix = None`.
# A loop header has a LABEL and no register. The test is `O.eq_dt` and NOT a
# priority compare, because `S.boolean()` is also priority 0 and only bits
# differ.
def pf.rng(+dt: S.Dt) -> Pf: Bool.pick(Pf, O.eq_dt(dt, S.void()), no_pf(), pf1("ridx", pf.ty_of("", dt), 1, False{}))

# THE TABLE. `ty` is resolved HERE rather than at the use site so the resolved
# string is what the key is built from, and the resolution is a gate row.
def pf.of(+op: O.Op, +dt: S.Dt, +addr: S.Addr, +nmn: U32) -> Pf:
  Bool.pick(Pf, is_reg(op, addr), pf1("reg", pf.ty_of("", dt), nmn, True{}),
  Bool.pick(Pf, is_op(op, O.OpsLOAD{}), pf1("val", pf.ty_of("", dt), nmn, U32.is_gt(nmn, 1)),
  Bool.pick(Pf, is_op(op, O.OpsCAST{}), pf1("cast", pf.ty_of("", dt), 1, False{}),
  Bool.pick(Pf, is_op(op, O.OpsBITCAST{}), pf1("cast", pf.ty_of("", dt), 1, False{}),
  Bool.pick(Pf, is_op(op, O.OpsEND{}), pf1("pred", "pred", 1, False{}),
  Bool.pick(Pf, is_op(op, O.OpsBUFFER{}), pf1("local", "u64", 1, False{}),
  Bool.pick(Pf, is_idx(op), pf1("bidx", "u64", 1, False{}),
  Bool.pick(Pf, is_op(op, O.OpsPARAM{}), pf1("dat", Bool.pick(String, is_global(addr), "u64", pf.ty_of("", dt)), 1, False{}),
  Bool.pick(Pf, is_op(op, O.OpsRANGE{}), pf.rng(dt),
  Bool.pick(Pf, O.GroupOp.alu(op), pf1("alu", pf.ty_of("", dt), 1, False{}),
  no_pf()))))))))))

# THE ARM SELECTOR. ptx.py:186-221 is a chain of `if`s whose ORDER is

def is_any3(+op: O.Op, os: List<&2, O.Op>) -> Bool: List.contains(~O.Op, O.eq_op, os, op)

# the tags, and `wk1.go`'s cases are these numbers. The two had drifted: a_alloc
# was 8 and `wk1.go` had no `case 8`, so every ordinary uop fell through `case _:`
# and the walk emitted NOTHING -- a green compile, 76 rows, every one of them
# empty. A_REG and A_ALLOC are ONE tag because `pf.of` already folded ptx.py:198
def A_SKIP() -> U32: 0
def A_NAME() -> U32: 1
def A_ALIAS() -> U32: 2
def A_STACK() -> U32: 3
def A_PICK() -> U32: 4
def A_REFUSE() -> U32: 5
def A_SPEC() -> U32: 6
def A_ALLOC() -> U32: 7

# ptx.py:203-205. `LOAD` copies the whole register; `INDEX`/`SHRINK` SUBSCRIPT
def arm.regsrc(+op: O.Op, idx_ok: Bool) -> U32:
  Bool.pick(U32, is_op(op, O.OpsLOAD{}), A_ALIAS(),
  Bool.pick(U32, idx_ok, A_PICK(), A_REFUSE()))

def arm.of(+op: O.Op, +addr: S.Addr, idx_ok: Bool) -> U32:
  Bool.pick(U32, is_any3(op, [O.OpsNOOP{}, O.OpsCONST{}]), A_SKIP(),
  Bool.pick(U32, is_op(op, O.OpsSINK{}), A_NAME(),
  Bool.pick(U32, is_op(op, O.OpsAFTER{}), A_ALIAS(),
  Bool.pick(U32, is_op(op, O.OpsSTACK{}), A_STACK(),
  Bool.pick(U32, is_reg(op, addr), A_ALLOC(),
  Bool.pick(U32, on_regsrc(op, addr), arm.regsrc(op, idx_ok),
  Bool.pick(U32, is_op(op, O.OpsSPECIAL{}), A_SPEC(),
  A_ALLOC())))))))

# THE REFERENCE ARMS. `refs` are INDICES into the registers emitted so far,
# which is `r[u.src[i]]`; `List.get` over a `Data` list answers `Some` for every
# in-range index (MEASURED -- the `List<&2, Bool>` note in agent-core.md is
def none_rg() -> Rg: Rg{False{}, Nil{}}
def has_rg(r: Rg) -> Bool: Bool.not(List.is_empty(&2, String, Rg.p(r)))

def rg_at.maybe(m: Maybe<&2, Rg>) -> Rg:
  match m:
    case Some{r}: r
    case None{}  : Rg{False{}, Nil{}}

def rg_at(w: Wal, +i: U32) -> Rg: rg_at.maybe(List.get(&2, Rg, Wal.r(w), U32.to_nat(i)))

# ptx.py:196 -- `[cast(str, r[x]) for x in u.src]`. `cast` is `typing.cast`, a
def st_walk(+rs: List<&2, Rg>, +ii: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ii:
    case Nil{}   : acc
    case i <> +t :
      +rest = st_walk(rs, t, acc)
      List.append(&2, String, Rg.p(rg_at.maybe(List.get(&2, Rg, rs, U32.to_nat(i)))), rest)

def rg_stack(w: Wal, +s: Wk) -> Rg: Rg{True{}, st_walk(Wal.r(w), Wk.refs(s), Nil{})}

# ptx.py:205 -- `r[u.src[0]][u.src[1].src[0].val]`, a SUBSCRIPT and so always a
# scalar string: `f7_reuse` prints `%reg_f16_2` where its INDEX's value is 2. The
# `Maybe` reader is here because `List.get` is the subscript and it answers
# `None` past the end, which a REG buffer never gets to in a legal kernel.
def rg_pick.pick(m: Maybe<&2, String>) -> Rg:
  match m:
    case Some{x}: Rg{False{}, [x]}
    case None{}  : Rg{False{}, Nil{}}

# ptx.py:190 (`r[u] = self.r[u.src[0]]`) and ptx.py:205 (`r[u.src[0]][u.src[1].src[0].val]`)
def rg_src0(+s: Wk) -> U32: Maybe.default(&2, U32, List.get(&2, U32, Wk.refs(s), 0n), 0)

def rg_alias(w: Wal, +s: Wk) -> Rg: rg_at(w, rg_src0(s))

def rg_pick(w: Wal, +s: Wk) -> Rg:
  rg_pick.pick(List.get(&2, String, Rg.p(rg_alias(w, s)), U32.to_nat(Wk.idx(s))))

# `to_function_name` -- helpers.py:157, reached from ptx.py:193 through
def fn_kp(+c: U32) -> Bool:
  Bool.or(Bool.or(Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)),
      Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90))),
    Bool.or(Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)), U32.is_eq(c, 95)))

def fn_name.go(+cs: List<&2, Char>, +acc: String) -> String:
  match cs:
    case Nil{}    : acc
    case c <> +t  : fn_name.go(t, String.concat([acc, Bool.pick(String, fn_kp(Char.to_u32(c)),
      String.from_list([c]), String.concat([P.hex1(U32.shrn(Char.to_u32(c), 4n)), P.hex1(Char.to_u32(c))]))]))

def fn_name(+s: String) -> String: fn_name.go(String.to_list(s), "")

# THE FOLD. The STEP LIST is the first parameter and the state the second,
# because a decreasing self-call is `args before the shrinking one must pass
# unchanged` and here the state changes every step while the list shrinks. One
# step in, one `Wal` out. `wk1.go` is the ONLY def that calls
# itself (convention 9), so the arm tag is a PARAMETER of it -- a `match` may not
# scrutinise a computed value, and `arm.of(...)` is one. Its arms are the
# `A_*` TAGS, in tag order, so `A_ALIAS = 1` is `case 1`.
# ptx.py:207 and 228 -- `r[u] = "%" + u.arg`, and the `.reg .u32` line is
def wk_spec.go(+w: Wal, +line: String, +reg: String) -> Wal:
  Wal.rput(Wal.kset(w, List.append(&2, String, [P.fmt(line)], Wal.kern(w))), Rg{False{}, [reg]})

def wk_spec(+w: Wal, +s: Wk) -> Wal:
  wk_spec.go(w, String.concat([".reg .u32 %", Wk.nm(s), ";"]), String.concat(["%", Wk.nm(s)]))

# ptx.py:185 and 192-193 -- `name` starts at "test" and a SINK carrying an arg
# renames it. NAMED here, because the entry point is a WALK output: the `.reg`
# block is not.
def wk_name(+w: Wal, +s: Wk) -> Wal: Bool.pick(Wal, is_op(Wk.op(s), O.OpsSINK{}), Wal.nset(w, fn_name(Wk.nm(s))), w)

# ptx.py:221 -- `if prefix: r[u] = ssa(prefix, u, dtype)`, and ptx.py:198-209's
# three overrides land here because `pf.of` already folded them into the same
# tuple. ONE `ssa_many`, so ONE bump, so a vector LOAD continues a series.
def wk_alloc.go(+p: Pf, +w: Wal, +s: Wk) -> Wal:
  match p:
    case Pf{has, prefix, ty, k, lst}:
      +s2 = ssa_many(Wal.c(w), pkey(prefix, ty), ty, k)
      Bool.pick(Wal, Pf.has(p), Wal.rput(Wal.cset(w, Ssa2.c(s2)), Rg{Pf.lst(p), Ssa2.ps(s2)}),
        Wal.rput(w, none_rg()))

def wk_alloc(+w: Wal, +s: Wk) -> Wal:
  wk_alloc.go(pf.of(Wk.op(s), Wk.dt(s), Wk.addr(s), Wk.nmn(s)), w, s)

def wk1.go(+a: U32, +w: Wal, +s: Wk) -> Wal:
  match a:
    case 0: Wal.rput(w, none_rg())
    case 1: Wal.rput(wk_name(w, s), none_rg())
    case 2: Wal.rput(w, rg_alias(w, s))
    case 3: Wal.rput(w, rg_stack(w, s))
    case 4: Wal.rput(w, rg_pick(w, s))
    case 5: Wal.rput(Wal.refset(w, O.Ops.name.of(Wk.op(s))), none_rg())
    case 6: wk_spec(w, s)
    case _: wk_alloc(w, s)

def wk1(+w: Wal, +s: Wk) -> Wal: wk1.go(arm.of(Wk.op(s), Wk.addr(s), Wk.idx_ok(s)), w, s)

# ptx.py:204 -- the raise ENDS `render`, so the walk STOPS. `Bool.pick` is
# NOT an `if`: it CHOOSES, and `wk_all(wk1(w, s), t)` in the losing arm would
# still be evaluated and would burn the list, so the recursion is bound first
# and the guard reads the RESULT of one step.
def wk_all(+ss: List<&2, Wk>, w: Wal) -> Wal:
  match ss:
    case Nil{}   : w
    case s <> +t :
      +n1 = wk1(w, s)
      Bool.pick(Wal, String.is_empty(Wal.ref(n1)), wk_all(t, n1), n1)

# THE `.reg` BLOCK. ptx.py:229 hands `render_kernel` `c.items()` and ptx.py:165 prints

def reg_line(+key: String, +ty: String, +n: U32) -> String:
  P.fmt(String.concat([".reg .", ty, " %", key, "<", U32.show(n), ">;"]))

def reg_go(+cs: List<&2, Cnt>, +acc: List<&2, String>) -> List<&2, String>:
  match cs:
    case Nil{}   : acc
    case c <> +t : reg_go(t, List.append(&2, String, acc, [reg_line(Cnt.key(c), Cnt.ty(c), Cnt.n(c))]))

def reg_block(+w: Wal) -> List<&2, String>:
  List.concat(&2, String, [reg_go(Wal.c(w), Nil{}), Wal.kern(w)])

# THE GATE ROWS.

type Wt is Data:
  Wt{nm: String, want: String}
def Wt.nm(+w: Wt) -> String:
  match w:
    case Wt{nm, want}: nm
def Wt.want(+w: Wt) -> String:
  match w:
    case Wt{nm, want}: want

# the computed side, one entry per row -- a list, not one concatenated string,
# because `zip.of` reads the computed value by index and a string would be
# indexed by CHARACTER.
#
# `r[i]` for every step the walk gave a register to, in the FIXTURE'S OWN order.
# A skipped uop (NOOP/CONST/SINK) contributes no row, and that ABSENCE is
# a claim: `f14_skips` has two skipped steps at indices 0..1 and its first `r`
# row is `[3]`.
def r_go.put(+r: Rg, i: U32, +s: Wk) -> List<&2, String>:
  Bool.pick(List<&2, String>, has_rg(r), [rgl.of(r)], Nil{})

def r_go(+ss: List<&2, Wk>, +rs: List<&2, Rg>, +i: U32, acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}   : acc
    case s <> +t :
      +rest = r_go(t, rs, U32.add(i, 1), acc)
      List.append(&2, String, r_go.put(Maybe.default(&2, Rg, List.get(&2, Rg, rs, U32.to_nat(i)), none_rg()), i, s), rest)

# THE `.reg` block, one line per emitted line, already `fmt`-ed and ESCAPED, so
# a dropped TAB is a byte diff and not an invisible-space difference.
def reg_lines(+ls: List<&2, String>, +i: U32, acc: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}   : acc
    case l <> +t :
      +rest = reg_lines(t, U32.add(i, 1), acc)
      List.append(&2, String, [P.esc(l)], rest)

def gots.fix(+w: Wal) -> List<&2, String>:
  +ls = reg_block(w)
  List.concat(&2, String, [[U32.show(U32.from_nat(List.length(&2, String, ls)))],
    reg_lines(ls, 0, Nil{}), [String.concat([P.px_pline(3), " ", Wal.nm(w), " ("])]])

# THE WHOLE FIXTURE, in the order the oracle prints it: the refusal if there is
# one, else the `r` rows, then the `.reg` block, then the entry point. `ref` is
# non-empty only when ptx.py:204 fired, and then NOTHING ELSE is produced -- the
# raise ends `render`, so there is no register and no `.reg` block at all.
def gots.happy(+ss: List<&2, Wk>, +w: Wal) -> List<&2, String>:
  List.concat(&2, String, [r_go(ss, Wal.r(w), 0, Nil{}), gots.fix(w)])

# the fixture's own row count, appended as the last row. The per-line diff cannot
# see a PERMUTATION -- the same rows in the wrong order -- and this is the one row
# a permutation would have to break to stay invisible.
def gots.seal(+ls: List<&2, String>, n: U32) -> List<&2, String>:
  List.append(&2, String, ls, [U32.show(n)])

def gots.of(+ref: String, +ss: List<&2, Wk>, +w: Wal) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(ref),
    gots.seal(gots.happy(ss, w), U32.add(U32.from_nat(List.length(&2, String, gots.happy(ss, w))), 1)),
    [String.concat(["PTX does not support dynamic register indexing: ", ref])])

def gots(+nm: String, +ss: List<&2, Wk>) -> List<&2, String>:
  gots.of(Wal.ref(wk_all(ss, wal0())), ss, wk_all(ss, wal0()))

def zip1(+g: String, +nm: String, +w: Wt) -> String:
  T.r(String.concat([nm, Wt.nm(w)]), g, Wt.want(w))

def zip.over(+gs: List<&2, String>, +nm: String, +i: U32) -> String:
  match gs:
    case Nil{}   : ""
    case g <> +r : String.concat([T.r(String.concat([nm, ".EXTRA[", U32.show(i), "]"]), g, "<no row>"),
                                 zip.over(r, nm, U32.add(i, 1))])

# the wants drive and the computed values are read by INDEX. a `Wt` with no
def dropn(+xs: List<&2, String>, +n: U32) -> List<&2, String>:
  match xs:
    case Nil{}    : Nil{}
    case _ <> +r : Bool.pick(List<&2, String>, U32.is_eq(n, 0), r, dropn(r, U32.sub(n, 1)))

def zip.of(+nm: String, +ws: List<&2, Wt>, +gs: List<&2, String>, +i: U32) -> String:
  match ws:
    case Nil{}   : zip.over(dropn(gs, i), nm, i)
    case w <> +t : String.concat([zip1(Maybe.default(&2, String,
                     List.get(&2, String, gs, U32.to_nat(i)), "<none>"), nm, w),
                     zip.of(nm, t, gs, U32.add(i, 1))])

def r_fix(+nm: String, +ss: List<&2, Wk>, +ws: List<&2, Wt>) -> String:
  zip.of(nm, ws, gots(nm, ss), 0)

# ==== BEGIN GENERATED FIXTURES
def r_fns() -> String: String.concat([T.rd(String.concat(["to_function_name ", "'test'"]), fn_name("test")), T.rd(String.concat(["to_function_name ", "'my kernel'"]), fn_name("my kernel")), T.rd(String.concat(["to_function_name ", "'MyKernel'"]), fn_name("MyKernel")), T.rd(String.concat(["to_function_name ", "'a-b'"]), fn_name("a-b")), T.rd(String.concat(["to_function_name ", "'x$y.z'"]), fn_name("x$y.z")), T.rd(String.concat(["to_function_name ", "'  lead'"]), fn_name("  lead")), T.rd(String.concat(["to_function_name ", "'trail  '"]), fn_name("trail  ")), T.rd(String.concat(["to_function_name ", "'a b c'"]), fn_name("a b c")), T.rd(String.concat(["to_function_name ", "'a~b'"]), fn_name("a~b")), T.rd(String.concat(["to_function_name ", "'a/b'"]), fn_name("a/b")), T.rd(String.concat(["to_function_name ", "'a:b'"]), fn_name("a:b")), T.rd(String.concat(["to_function_name ", "'a0b'"]), fn_name("a0b")), T.rd(String.concat(["to_function_name ", "'a_b'"]), fn_name("a_b"))])

def f1_alu_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", [2], 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 4, "", [1, 3], 0, True{}},
   Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", [5], 0, True{}},
   Wk{O.OpsMUL{}, S.single(), S.Aalu{}, 4, "", [1, 6], 0, True{}},
   Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", [8], 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 4, "", [4, 9], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [4, 7, 10], 0, True{}}]

def f1_alu() -> String: r_fix("f1_alu", f1_alu_ss(),
   [Wt{".r[1] BUFFER", "%local_u64_0"},
   Wt{".r[3] CAST", "%cast_f32_0"},
   Wt{".r[4] ADD", "%alu_f32_0"},
   Wt{".r[6] CAST", "%cast_f32_1"},
   Wt{".r[7] MUL", "%alu_f32_1"},
   Wt{".r[9] CAST", "%cast_f32_2"},
   Wt{".r[10] ADD", "%alu_f32_2"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %cast_f32_<3>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.f32 %alu_f32_<3>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "13"}])

def f2_counter_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", [2], 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 4, "", [1, 3], 0, True{}},
   Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", [5], 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 4, "", [1, 6], 0, True{}},
   Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", [8], 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 4, "", [1, 9], 0, True{}},
   Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", [11], 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 4, "", [1, 12], 0, True{}},
   Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", [14], 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 4, "", [1, 15], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [4, 7, 10, 13, 16], 0, True{}}]

def f2_counter() -> String: r_fix("f2_counter", f2_counter_ss(),
   [Wt{".r[1] BUFFER", "%local_u64_0"},
   Wt{".r[3] CAST", "%cast_f32_0"},
   Wt{".r[4] ADD", "%alu_f32_0"},
   Wt{".r[6] CAST", "%cast_f32_1"},
   Wt{".r[7] ADD", "%alu_f32_1"},
   Wt{".r[9] CAST", "%cast_f32_2"},
   Wt{".r[10] ADD", "%alu_f32_2"},
   Wt{".r[12] CAST", "%cast_f32_3"},
   Wt{".r[13] ADD", "%alu_f32_3"},
   Wt{".r[15] CAST", "%cast_f32_4"},
   Wt{".r[16] ADD", "%alu_f32_4"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %cast_f32_<5>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.f32 %alu_f32_<5>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "17"}])

def f3_cast_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.int32(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.AGlobal{}, 4, "", [1], 0, True{}},
   Wk{O.OpsBUFFER{}, S.uint32(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCAST{}, S.uint32(), S.AGlobal{}, 4, "", [3], 0, True{}},
   Wk{O.OpsBUFFER{}, S.int64(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCAST{}, S.int64(), S.AGlobal{}, 4, "", [5], 0, True{}},
   Wk{O.OpsBUFFER{}, S.half(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCAST{}, S.half(), S.AGlobal{}, 4, "", [7], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.AGlobal{}, 4, "", [9], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [2, 4, 6, 8, 10], 0, True{}}]

def f3_cast() -> String: r_fix("f3_cast", f3_cast_ss(),
   [Wt{".r[1] BUFFER", "%local_u64_0"},
   Wt{".r[2] CAST", "%cast_s32_0"},
   Wt{".r[3] BUFFER", "%local_u64_1"},
   Wt{".r[4] CAST", "%cast_u32_0"},
   Wt{".r[5] BUFFER", "%local_u64_2"},
   Wt{".r[6] CAST", "%cast_s64_0"},
   Wt{".r[7] BUFFER", "%local_u64_3"},
   Wt{".r[8] CAST", "%cast_f16_0"},
   Wt{".r[9] BUFFER", "%local_u64_4"},
   Wt{".r[10] CAST", "%cast_f32_0"},
   Wt{".reg.count", "6"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<5>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.s32 %cast_s32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.u32 %cast_u32_<1>;"},
   Wt{".reg[3]", "\\t.reg\\t\\t.s64 %cast_s64_<1>;"},
   Wt{".reg[4]", "\\t.reg\\t\\t.f16 %cast_f16_<1>;"},
   Wt{".reg[5]", "\\t.reg\\t\\t.f32 %cast_f32_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "19"}])

def f4_pred_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.int32(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.Aalu{}, 1, "", [2], 0, True{}},
   Wk{O.OpsADD{}, S.int32(), S.Aalu{}, 4, "", [1, 3], 0, True{}},
   Wk{O.OpsEND{}, S.int32(), S.Aalu{}, 4, "", [4], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [5], 0, True{}}]

def f4_pred() -> String: r_fix("f4_pred", f4_pred_ss(),
   [Wt{".r[1] BUFFER", "%local_u64_0"},
   Wt{".r[3] CAST", "%cast_s32_0"},
   Wt{".r[4] ADD", "%alu_s32_0"},
   Wt{".r[5] END", "%pred_pred_0"},
   Wt{".reg.count", "4"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.s32 %cast_s32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.s32 %alu_s32_<1>;"},
   Wt{".reg[3]", "\\t.reg\\t\\t.pred %pred_pred_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "11"}])

def f5_regbuf_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AReg{}, 4, "", [0], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [1], 0, True{}}]

def f5_regbuf() -> String: r_fix("f5_regbuf", f5_regbuf_ss(),
   [Wt{".r[1] BUFFER", "{%reg_f32_0, %reg_f32_1, %reg_f32_2, %reg_f32_3}"},
   Wt{".reg.count", "1"},
   Wt{".reg[0]", "\\t.reg\\t\\t.f32 %reg_f32_<4>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "5"}])

def f6_regbuf1_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AReg{}, 1, "", [0], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [1], 0, True{}}]

def f6_regbuf1() -> String: r_fix("f6_regbuf1", f6_regbuf1_ss(),
   [Wt{".r[1] BUFFER", "{%reg_f32_0}"},
   Wt{".reg.count", "1"},
   Wt{".reg[0]", "\\t.reg\\t\\t.f32 %reg_f32_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "5"}])

def f7_reuse_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.half(), S.AReg{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.Aalu{}, 1, "", [2], 0, True{}},
   Wk{O.OpsINDEX{}, S.half(), S.AReg{}, 1, "", [1, 3], 2, True{}},
   Wk{O.OpsSPECIAL{}, S.weakint(), S.Aalu{}, 1, "g0", [0], 0, True{}},
   Wk{O.OpsLOAD{}, S.half(), S.AReg{}, 4, "", [1, 5], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [4, 6], 0, True{}}]

def f7_reuse() -> String: r_fix("f7_reuse", f7_reuse_ss(),
   [Wt{".r[1] BUFFER", "{%reg_f16_0, %reg_f16_1, %reg_f16_2, %reg_f16_3}"},
   Wt{".r[3] CAST", "%cast_s32_0"},
   Wt{".r[4] INDEX", "%reg_f16_2"},
   Wt{".r[5] SPECIAL", "%g0"},
   Wt{".r[6] LOAD", "{%reg_f16_0, %reg_f16_1, %reg_f16_2, %reg_f16_3}"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.f16 %reg_f16_<4>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.s32 %cast_s32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.u32 %g0;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "11"}])

def f8_refuse_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.half(), S.AReg{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.Aalu{}, 1, "", [2], 0, True{}},
   Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.Aalu{}, 1, "", [4], 0, True{}},
   Wk{O.OpsADD{}, S.int32(), S.Aalu{}, 1, "", [3, 5], 0, True{}},
   Wk{O.OpsINDEX{}, S.half(), S.AReg{}, 1, "", [1, 6], 0, False{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [7], 0, True{}}]

def f8_refuse() -> String: r_fix("f8_refuse", f8_refuse_ss(),
   [Wt{".REFUSAL", "PTX does not support dynamic register indexing: INDEX"}])

def f9_special_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsSPECIAL{}, S.weakint(), S.Aalu{}, 1, "l1", [0], 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 4, "", [1, 2], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [3], 0, True{}}]

def f9_special() -> String: r_fix("f9_special", f9_special_ss(),
   [Wt{".r[1] BUFFER", "%local_u64_0"},
   Wt{".r[2] SPECIAL", "%l1"},
   Wt{".r[3] ADD", "%alu_f32_0"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %alu_f32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.u32 %l1;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "9"}])

def f10_loads_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 8, "", [0], 0, True{}},
   Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsSPECIAL{}, S.weakint(), S.Aalu{}, 1, "g0", [2], 0, True{}},
   Wk{O.OpsLOAD{}, S.single(), S.AGlobal{}, 8, "", [1, 3], 0, True{}},
   Wk{O.OpsSPECIAL{}, S.weakint(), S.Aalu{}, 1, "g1", [2], 0, True{}},
   Wk{O.OpsLOAD{}, S.single(), S.AGlobal{}, 8, "", [1, 5], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 8, "", [0], 0, True{}},
   Wk{O.OpsSPECIAL{}, S.weakint(), S.Aalu{}, 1, "g2", [2], 0, True{}},
   Wk{O.OpsLOAD{}, S.single(), S.AGlobal{}, 8, "", [7, 8], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [4, 6, 9], 0, True{}}]

def f10_loads() -> String: r_fix("f10_loads", f10_loads_ss(),
   [Wt{".r[1] BUFFER", "%local_u64_0"},
   Wt{".r[3] SPECIAL", "%g0"},
   Wt{".r[4] LOAD", "{%val_f32_0, %val_f32_1, %val_f32_2, %val_f32_3, %val_f32_4, %val_f32_5, %val_f32_6, %val_f32_7}"},
   Wt{".r[5] SPECIAL", "%g1"},
   Wt{".r[6] LOAD", "{%val_f32_8, %val_f32_9, %val_f32_10, %val_f32_11, %val_f32_12, %val_f32_13, %val_f32_14, %val_f32_15}"},
   Wt{".r[7] BUFFER", "%local_u64_1"},
   Wt{".r[8] SPECIAL", "%g2"},
   Wt{".r[9] LOAD", "{%val_f32_16, %val_f32_17, %val_f32_18, %val_f32_19, %val_f32_20, %val_f32_21, %val_f32_22, %val_f32_23}"},
   Wt{".reg.count", "5"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<2>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %val_f32_<24>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.u32 %g2;"},
   Wt{".reg[3]", "\\t.reg\\t\\t.u32 %g1;"},
   Wt{".reg[4]", "\\t.reg\\t\\t.u32 %g0;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "16"}])

def f11_stack_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", [2], 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 4, "", [1, 3], 0, True{}},
   Wk{O.OpsSTACK{}, S.single(), S.AGlobal{}, 8, "", [1, 4], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [5], 0, True{}}]

def f11_stack() -> String: r_fix("f11_stack", f11_stack_ss(),
   [Wt{".r[1] BUFFER", "%local_u64_0"},
   Wt{".r[3] CAST", "%cast_f32_0"},
   Wt{".r[4] ADD", "%alu_f32_0"},
   Wt{".r[5] STACK", "{%local_u64_0, %alu_f32_0}"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %cast_f32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.f32 %alu_f32_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "10"}])

def f12_after_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsAFTER{}, S.single(), S.AGlobal{}, 4, "", [1], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [2], 0, True{}}]

def f12_after() -> String: r_fix("f12_after", f12_after_ss(),
   [Wt{".r[1] BUFFER", "%local_u64_0"},
   Wt{".r[2] AFTER", "%local_u64_0"},
   Wt{".reg.count", "1"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "6"}])

def f13_param_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsPARAM{}, S.single(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsPARAM{}, S.single(), S.ALocal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [1, 2], 0, True{}}]

def f13_param() -> String: r_fix("f13_param", f13_param_ss(),
   [Wt{".r[1] PARAM", "%dat_u64_0"},
   Wt{".r[2] PARAM", "%dat_f32_0"},
   Wt{".reg.count", "2"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %dat_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %dat_f32_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "7"}])

def f14_skips_ss() -> List<&2, Wk>:
   [Wk{O.OpsNOOP{}, S.void(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 4, "", [2], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", [1], 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 4, "", [3, 4], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [0, 1, 5], 0, True{}}]

def f14_skips() -> String: r_fix("f14_skips", f14_skips_ss(),
   [Wt{".r[3] BUFFER", "%local_u64_0"},
   Wt{".r[4] CAST", "%cast_f32_0"},
   Wt{".r[5] ADD", "%alu_f32_0"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %cast_f32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.f32 %alu_f32_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "9"}])

def f15_bidx_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsSPECIAL{}, S.weakint(), S.Aalu{}, 1, "g0", [0], 0, True{}},
   Wk{O.OpsINDEX{}, S.single(), S.AGlobal{}, 1, "", [1, 2], 0, False{}},
   Wk{O.OpsSPECIAL{}, S.weakint(), S.Aalu{}, 1, "g1", [0], 0, True{}},
   Wk{O.OpsSHRINK{}, S.single(), S.AGlobal{}, 3, "", [1, 2, 4], 0, False{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [3, 5], 0, True{}}]

def f15_bidx() -> String: r_fix("f15_bidx", f15_bidx_ss(),
   [Wt{".r[1] BUFFER", "%local_u64_0"},
   Wt{".r[2] SPECIAL", "%g0"},
   Wt{".r[3] INDEX", "%bidx_u64_0"},
   Wt{".r[4] SPECIAL", "%g1"},
   Wt{".r[5] SHRINK", "%bidx_u64_1"},
   Wt{".reg.count", "4"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.u64 %bidx_u64_<2>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.u32 %g1;"},
   Wt{".reg[3]", "\\t.reg\\t\\t.u32 %g0;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "12"}])

def f16_bitcast_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.int32(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.AGlobal{}, 4, "", [1], 0, True{}},
   Wk{O.OpsBITCAST{}, S.single(), S.AGlobal{}, 4, "", [1], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [2, 3], 0, True{}}]

def f16_bitcast() -> String: r_fix("f16_bitcast", f16_bitcast_ss(),
   [Wt{".r[1] BUFFER", "%local_u64_0"},
   Wt{".r[2] CAST", "%cast_f32_0"},
   Wt{".r[3] BITCAST", "%cast_f32_1"},
   Wt{".reg.count", "2"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %cast_f32_<2>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "8"}])

def f17_u64_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsSPECIAL{}, S.weakint(), S.Aalu{}, 1, "g0", [0], 0, True{}},
   Wk{O.OpsINDEX{}, S.single(), S.AGlobal{}, 1, "", [1, 2], 0, False{}},
   Wk{O.OpsSPECIAL{}, S.weakint(), S.Aalu{}, 1, "g1", [0], 0, True{}},
   Wk{O.OpsSHRINK{}, S.single(), S.AGlobal{}, 3, "", [1, 2, 4], 0, False{}},
   Wk{O.OpsBUFFER{}, S.int32(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.Aalu{}, 1, "", [7], 0, True{}},
   Wk{O.OpsADD{}, S.int32(), S.Aalu{}, 4, "", [6, 8], 0, True{}},
   Wk{O.OpsEND{}, S.int32(), S.Aalu{}, 4, "", [9], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [3, 5, 10], 0, True{}}]

def f17_u64() -> String: r_fix("f17_u64", f17_u64_ss(),
   [Wt{".r[1] BUFFER", "%local_u64_0"},
   Wt{".r[2] SPECIAL", "%g0"},
   Wt{".r[3] INDEX", "%bidx_u64_0"},
   Wt{".r[4] SPECIAL", "%g1"},
   Wt{".r[5] SHRINK", "%bidx_u64_1"},
   Wt{".r[6] BUFFER", "%local_u64_1"},
   Wt{".r[8] CAST", "%cast_s32_0"},
   Wt{".r[9] ADD", "%alu_s32_0"},
   Wt{".r[10] END", "%pred_pred_0"},
   Wt{".reg.count", "7"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<2>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.u64 %bidx_u64_<2>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.s32 %cast_s32_<1>;"},
   Wt{".reg[3]", "\\t.reg\\t\\t.s32 %alu_s32_<1>;"},
   Wt{".reg[4]", "\\t.reg\\t\\t.pred %pred_pred_<1>;"},
   Wt{".reg[5]", "\\t.reg\\t\\t.u32 %g1;"},
   Wt{".reg[6]", "\\t.reg\\t\\t.u32 %g0;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "19"}])

def f18_name_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", [2], 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 4, "", [1, 3], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [4], 0, True{}}]

def f18_name() -> String: r_fix("f18_name", f18_name_ss(),
   [Wt{".r[1] BUFFER", "%local_u64_0"},
   Wt{".r[3] CAST", "%cast_f32_0"},
   Wt{".r[4] ADD", "%alu_f32_0"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %cast_f32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.f32 %alu_f32_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "9"}])

def f19_mixed_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.AGlobal{}, 4, "", [1], 0, True{}},
   Wk{O.OpsSPECIAL{}, S.weakint(), S.Aalu{}, 1, "g0", [0], 0, True{}},
   Wk{O.OpsINDEX{}, S.single(), S.AGlobal{}, 1, "", [1, 3], 0, False{}},
   Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", [5], 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 4, "", [1, 6], 0, True{}},
   Wk{O.OpsPARAM{}, S.half(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsSPECIAL{}, S.weakint(), S.Aalu{}, 1, "g1", [0], 0, True{}},
   Wk{O.OpsLOAD{}, S.single(), S.AGlobal{}, 4, "", [1, 9], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [2, 4, 7, 8, 10, 2, 4, 7, 8, 10], 0, True{}}]

def f19_mixed() -> String: r_fix("f19_mixed", f19_mixed_ss(),
   [Wt{".r[1] BUFFER", "%local_u64_0"},
   Wt{".r[2] CAST", "%cast_s32_0"},
   Wt{".r[3] SPECIAL", "%g0"},
   Wt{".r[4] INDEX", "%bidx_u64_0"},
   Wt{".r[6] CAST", "%cast_f32_0"},
   Wt{".r[7] ADD", "%alu_f32_0"},
   Wt{".r[8] PARAM", "%dat_u64_0"},
   Wt{".r[9] SPECIAL", "%g1"},
   Wt{".r[10] LOAD", "{%val_f32_0, %val_f32_1, %val_f32_2, %val_f32_3}"},
   Wt{".reg.count", "9"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.s32 %cast_s32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.u64 %bidx_u64_<1>;"},
   Wt{".reg[3]", "\\t.reg\\t\\t.f32 %cast_f32_<1>;"},
   Wt{".reg[4]", "\\t.reg\\t\\t.f32 %alu_f32_<1>;"},
   Wt{".reg[5]", "\\t.reg\\t\\t.u64 %dat_u64_<1>;"},
   Wt{".reg[6]", "\\t.reg\\t\\t.f32 %val_f32_<4>;"},
   Wt{".reg[7]", "\\t.reg\\t\\t.u32 %g1;"},
   Wt{".reg[8]", "\\t.reg\\t\\t.u32 %g0;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "21"}])

def f20_idx_pred_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.int32(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.Aalu{}, 1, "", [2], 0, True{}},
   Wk{O.OpsADD{}, S.int32(), S.Aalu{}, 4, "", [1, 3], 0, True{}},
   Wk{O.OpsEND{}, S.int32(), S.Aalu{}, 4, "", [4], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [5, 5], 0, True{}}]

def f20_idx_pred() -> String: r_fix("f20_idx_pred", f20_idx_pred_ss(),
   [Wt{".r[1] BUFFER", "%local_u64_0"},
   Wt{".r[3] CAST", "%cast_s32_0"},
   Wt{".r[4] ADD", "%alu_s32_0"},
   Wt{".r[5] END", "%pred_pred_0"},
   Wt{".reg.count", "4"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.s32 %cast_s32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.s32 %alu_s32_<1>;"},
   Wt{".reg[3]", "\\t.reg\\t\\t.pred %pred_pred_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "11"}])

def f21_name_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", [2], 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 4, "", [1, 3], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "my kernel", [4], 0, True{}}]

def f21_name() -> String: r_fix("f21_name", f21_name_ss(),
   [Wt{".r[1] BUFFER", "%local_u64_0"},
   Wt{".r[3] CAST", "%cast_f32_0"},
   Wt{".r[4] ADD", "%alu_f32_0"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %cast_f32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.f32 %alu_f32_<1>;"},
   Wt{".entry", ".visible .entry my20kernel ("},
   Wt{".rows", "9"}])

def f22_name2_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 4, "", [0], 0, True{}},
   Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", [2], 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 4, "", [1, 3], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "MyKernel", [4], 0, True{}}]

def f22_name2() -> String: r_fix("f22_name2", f22_name2_ss(),
   [Wt{".r[1] BUFFER", "%local_u64_0"},
   Wt{".r[3] CAST", "%cast_f32_0"},
   Wt{".r[4] ADD", "%alu_f32_0"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %cast_f32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.f32 %alu_f32_<1>;"},
   Wt{".entry", ".visible .entry MyKernel ("},
   Wt{".rows", "9"}])

def f23_load1_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 1, "", [0], 0, True{}},
   Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsSPECIAL{}, S.weakint(), S.Aalu{}, 1, "g0", [2], 0, True{}},
   Wk{O.OpsLOAD{}, S.single(), S.AGlobal{}, 1, "", [1, 3], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [4], 0, True{}}]

def f23_load1() -> String: r_fix("f23_load1", f23_load1_ss(),
   [Wt{".r[1] BUFFER", "%local_u64_0"},
   Wt{".r[3] SPECIAL", "%g0"},
   Wt{".r[4] LOAD", "%val_f32_0"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %val_f32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.u32 %g0;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "9"}])

def f24_range_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.Aalu{}, 1, "", [0], 0, True{}},
   Wk{O.OpsRANGE{}, S.int32(), S.Aalu{}, 1, "", [1], 0, True{}},
   Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 4, "", [3], 0, True{}},
   Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", [5], 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 4, "", [4, 6], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [2, 7], 0, True{}}]

def f24_range() -> String: r_fix("f24_range", f24_range_ss(),
   [Wt{".r[1] CAST", "%cast_s32_0"},
   Wt{".r[2] RANGE", "%ridx_s32_0"},
   Wt{".r[4] BUFFER", "%local_u64_0"},
   Wt{".r[6] CAST", "%cast_f32_0"},
   Wt{".r[7] ADD", "%alu_f32_0"},
   Wt{".reg.count", "5"},
   Wt{".reg[0]", "\\t.reg\\t\\t.s32 %cast_s32_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.s32 %ridx_s32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[3]", "\\t.reg\\t\\t.f32 %cast_f32_<1>;"},
   Wt{".reg[4]", "\\t.reg\\t\\t.f32 %alu_f32_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "13"}])

def f25_rangevoid_ss() -> List<&2, Wk>:
   [Wk{O.OpsNOOP{}, S.void(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsRANGE{}, S.void(), S.Aalu{}, 1, "", [0], 0, True{}},
   Wk{O.OpsCONST{}, S.weakint(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 4, "", [2], 0, True{}},
   Wk{O.OpsCONST{}, S.weakfloat(), S.Aalu{}, 1, "", [], 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", [4], 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 4, "", [3, 5], 0, True{}},
   Wk{O.OpsSINK{}, S.void(), S.Aalu{}, 1, "test", [1, 6], 0, True{}}]

def f25_rangevoid() -> String: r_fix("f25_rangevoid", f25_rangevoid_ss(),
   [Wt{".r[3] BUFFER", "%local_u64_0"},
   Wt{".r[5] CAST", "%cast_f32_0"},
   Wt{".r[6] ADD", "%alu_f32_0"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %cast_f32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.f32 %alu_f32_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "9"}])
# ==== END GENERATED FIXTURES

def r_all() -> String:
  String.concat([r_fns(), f1_alu(), f2_counter(), f3_cast(), f4_pred(), f5_regbuf(), f6_regbuf1(),
    f7_reuse(), f8_refuse(), f9_special(), f10_loads(), f11_stack(), f12_after(), f13_param(),
    f14_skips(), f15_bidx(), f16_bitcast(), f17_u64(), f18_name(), f19_mixed(), f20_idx_pred(),
    f21_name(), f22_name2(), f23_load1(), f24_range(), f25_rangevoid()])

# `T.r` ENDS EVERY ROW WITH A NEWLINE and `IO.print` appends one more, so the last
# one is DROPPED here: the oracle's `sys.stdout.write(rows() + "\n")` supplies
# exactly one frame and this is that frame. Without the drop the two lanes differ
# by one blank line, which is a real byte diff and not a formatting quibble.
def r_body() -> String:
  String.take(r_all(), U32.to_nat(U32.sub(U32.from_nat(String.length(r_all())), 1)))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(r_body())

# THE MUTATION TABLE. Measured 2026-10-02 with `.agents/slop/ptx-s3-mutate.py`:
# 30 mutations, one textual edit at a time, each row diffed against the
# unmutated 281 by WHOLE `name=value` LINE and never by row NAME -- a
# name-comparing harness reported 0 for every mutation in two other units. The
# mutated copy is written BESIDE this file (`_ptxmut.bend`) because ptx.bend
# IMPORTS ./tc_ptx.bend by a relative path and a copy in a scratch dir cannot
# resolve it. Full table with every row count: `.agents/slop/notes/bend2-constraints.md`,
# search `MUT-PTX-S3`.
#   .venv/bin/python gates/ptx_render_census-mutate.py > /tmp/ptxmut.rows
# RETARGETED 2026-10-16. This read `.agents/slop/ptx-s3-mutate.py`, deleted by the sweep of
# 2026-10-05 (blob e853efc4b, 10195 B). The harness that replaced it is
# `gates/ptx_render_census-mutate.py`, beside its own gate and its own `.bend` driver.
#
# WHAT THE TABLE SAYS
# M29 is a theorem for this file, not a fixture gap. Dropping CONST from the skip
# list routes it to `A_ALLOC`, and `pf.of` has no CONST arm -- so it takes
# `no_pf()` and `wk_alloc.go` writes the SAME `none_rg()` the skip arm writes. A
# CONST allocates nothing under every arm, so no graph can separate the two. It
# matters upstream only because `string_rewrite` gives a CONST a `mov` LINE
# (ptx.py:83), which this file does not port. The honest record: `arm.of`'s skip
