# ptx.bend -- tinygrad/renderer/ptx.py: `render`'s NAMING WALK, ptx.py:171-228
#
# ===========================================================================
# WHAT IS HERE, WHAT IS NOT, AND WHY NEITHER IS A SECOND COPY
# ===========================================================================
# `renderer/tc_ptx.bend` already ports ptx.py's EMITTERS -- `render_val`, the
# twenty-one `asm_for_op` entries, `supports_half`/`doesnt_support_half`,
# `modifier`, `mem_type`, `render_wmma` and its two `dt_map`s, the three dtype
# tables, `supported_dtypes`, `tensor_cores`, `fmt` and `render_kernel`'s HEADER
# -- because tc.py and ptx.py are one feature. This file redefines NONE of it.
# It IMPORTS `tc_ptx.bend` as `P` and calls `P.types_of` (the three dtype
# tables), `P.fmt` (the line formatter) and `P.esc`; the row builder is `T.r`,
# which the 1:1 split moved out of `tc_ptx.bend` into `tc.bend`.
# ONE definition per shared name: the second copy is the drift bug, and a dtype
# rename in `LAWS/spec.bend` moves BOTH copies or neither.
#
# What tc_ptx.bend's header calls STAGE 3 and names NOT STARTED is here: the
# `ssa` COUNTER (ptx.py:180-183), the per-op register assignment (ptx.py:185-220),
# the `.reg` DECLARATIONS `render_kernel` prepends from `c.items()` (ptx.py:165),
# the `bufs` collection (ptx.py:209), the entry-point NAME (ptx.py:185, 191-192)
# and the ONE REFUSAL the walk raises (ptx.py:203).
#
# NOT HERE, and named rather than faked:
#   * `string_rewrite` (ptx.py:81-135) -- nineteen graph-pattern rules whose BODY
#     is an f-string over `ctx.r[x]`. It is CONSUMABLE exactly once the walk
#     below supplies `ctx.r`, so it is the natural NEXT file and not a wall.
#   * `ptx_matcher` (ptx.py:40-57) -- seven graph REWRITES, tc_ptx.bend's
#     `TODO(p3) ptx.py:42`-`56` block.
#   * `to_function_name`'s `ansistrip` (helpers.py:156) -- a regex ANSI strip.
#     The KEEP/HEX branch is ported and gated; the strip is the wall.
#   * `Ops.WMMA`'s `wmma_r` (ptx.py:210-215) -- it needs the three fragment
#     tables, which are tc_ptx.bend's `Tc`, and it is named in its ARM.
#
# ===========================================================================
# THE GATE. 224 rows, all STRINGS, and `py=` is a LITERAL, never an expression:
#   python3 .agents/slop/ptx-s3-oracle.py rows > .agents/slop/ptxown/s3py.txt
#   ./bin/bend tinybendygrad/renderer/ptx.bend          > .agents/slop/ptxown/bd.txt
#   ./bin/bend tinybendygrad/renderer/ptx.bend -o /tmp/p3 && /tmp/p3 > .agents/slop/ptxown/bdn.txt
#   diff .agents/slop/ptxown/bd.txt  .agents/slop/ptxown/s3py.txt
#   diff .agents/slop/ptxown/bdn.txt .agents/slop/ptxown/s3py.txt
# BOTH lanes byte-identical, and never gate on an exit status: `--check-only`
# exits 1 on this repo even when the file is fine (14 unfilled `dtype.bend`
# laws). Read its FIRST LINE.
#
# THE ORACLE STUBS EXACTLY ONE THING AND SAYS WHY. `render` finishes the whole
# register map BEFORE it first calls `string_rewrite.rewrite(u, ctx=self)`
# (ptx.py:222), and the rewrite answers kernel LINES rather than register names,
# so returning `[]` leaves this file's entire subject intact and removes only
# the surface this file does not port. `render_kernel` is NOT stubbed: its `.reg`
# declarations ARE `c.items()`, so they are this file's output.
#
# FOUR DIRECTIONS, because a one-directional table cannot see half the bugs:
#   * `r[i]`    -- node -> register. ptx.py:204's pick / copy / skip arms, and
#     `is_list`, which is NOT one test: a REG buffer of ONE element is still a
#     list (`f6_regbuf1` prints `{%reg_f32_0}`) while a LOAD of one element is a
#     bare string (ptx.py:208 tests `max_numel > 1`).
#   * `reg[i]`  -- counter key -> count, IN `c`'s INSERTION ORDER, which is what
#     `c.items()` hands `render_kernel` and which no sort reproduces.
#   * `entry`   -- the SINK's arg through `to_function_name`.
#   * `REFUSAL` -- a TRUNCATED trace. ptx.py:203 raises BEFORE it has a register,
#     so the row is the message plus the offending op and nothing else; the
#     message's own tail is `{u}`, a UOp repr, i.e. the GRAPH and not a value.
# ===========================================================================

import Base
import ./tc_ptx.bend as P
import ./tc.bend as T
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O

# ===========================================================================
# THE STATE. `r` is `dict[UOp, str | list[str]]` (ptx.py:176), `c` is a
# `defaultdict[int]` over a STRING key (ptx.py:175), `kern` is ptx.py:227's
# `.reg .u32` lines and `ref` is the walk's refusal, which in Python is an
# exception and here is a value because a Bend fold cannot raise.
#
# `Rg` holds `parts` rather than a rendered string because ptx.py:204 SUBSCRIPTS
# it -- `r[u.src[0]][u.src[1].src[0].val]` -- so the element has to be
# addressable, and a pre-joined string would force a parse to get it back.
# ===========================================================================
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
# ptx.py:203 has fired -- which also STOPS the walk, because in CPython the
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
# `src[1].src[0].val` and `idx_ok` is ptx.py:202's CONST-of-CAST guard.
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

# ===========================================================================
# `ssa` -- ptx.py:180-183, the whole of it:
#     def ssa(prefix, u=None, dtype=None):
#       prefix += f"_{dtype if dtype is not None else self.types[unwrap(u).dtype]}_"
#       c[prefix] += 1
#       return f"%{prefix}{c[prefix]-1}"
#
# THE KEY IS THE WHOLE `prefix_dtype_` STRING, trailing underscore and all, so
# `cast` over five DIFFERENT dtypes is FIVE `.reg` lines and not one (`f3_cast`),
# while `cast_f32` reaches 5 over five casts of one dtype (`f2_counter`). The
# returned index is `c[prefix]-1` read AFTER the bump, which is the value
# BEFORE it -- so the first use of a key is 0. `cnt_n` reads and `cnt_bump`
# writes, and swapping the two prints `%alu_f32_1` on the first ALU of every
# fixture. `cnt_bump` REPLACES IN PLACE -- `List.append(cs, [bumped])` is
# `cs ++ [bumped]`, which keeps the head AND adds a copy, so the True arm builds
# from the TAIL. `c`'s order is therefore FIRST-USE order, which is `c.items()`
# and therefore the `.reg` order, and no sort reproduces it.
# ===========================================================================
# A RECORD PATTERN BINDS, IT DOES NOT TEST. MEASURED: `case Cnt{key, ty, n}`
# matches every entry, so these two took their FIRST arm for every key -- `c`
# grew one entry per ALLOCATION (seven for three keys) and every register read
# the HEAD's counter, printing `%alu_f32_1` seven times. `cnt.is` is the
# comparison, and it has to be a def because a `match` cannot scrutinise a
# computed value.
def Cnt.is(c: Cnt, key: String) -> Bool: String.eq(Cnt.key(c), key)

def cnt_n(+cs: List<&2, Cnt>, +key: String) -> U32:
  match cs:
    case Nil{}        : 0
    case c <> +t      : Bool.pick(U32, Cnt.is(c, key), Cnt.n(c), cnt_n(t, key))

# BOTH ARMS GROW FROM THE HEAD. `List.append(a, b)` is `a ++ b`, and a hit
# REPLACES the head while a miss KEEPS it -- so the hit arm is `[bumped] ++ t`
# and the miss arm is `[c] ++ recurse(t)`. MEASURED both wrong ways: growing
# from the tail dropped every key but the last (`nc=1`), and growing the miss
# arm from the whole list put `cast_f32_` in `c` TWICE.
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

# THE BUMP IS `k`, NOT ONE. MEASURED: ptx.py:198 and 208 call `ssa` ONCE PER
# ELEMENT, and `c[prefix] += 1` runs inside `ssa`, so a four-element REG buffer
# leaves the counter at FOUR and `.reg .f32 %reg_f32_<4>;` -- bumping by one
# printed `<1>`, and the SECOND vector LOAD of `f10_loads` restarted at 1 instead
# of 8. The names are still the PRE-bump series positions, which is what
# `c[prefix]-1` reads.
def ssa_many(+cs: List<&2, Cnt>, +key: String, +ty: String, +k: U32) -> Ssa2:
  Bool.pick(Ssa2, U32.is_eq(k, 0), Ssa2{cs, Nil{}},
    ssa_many.ago(U32.to_nat(k), cnt_n(cs, key), cnt_bump(cs, key, ty, k), key))

# ===========================================================================
# THE PREFIX TABLE -- ptx.py:216-218, plus ptx.py:197-208's three allocating
# overrides folded in so ONE `alloc` covers all four:
#
#     Ops.CAST/BITCAST -> ("cast", None)    Ops.END    -> ("pred", "pred")
#     Ops.RANGE        -> ("ridx", None)    Ops.BUFFER -> ("local", "u64")
#     Ops.INDEX/SHRINK -> ("bidx", "u64")   Ops.PARAM  -> ("dat", "u64" if GLOBAL)
#     every ALU op     -> ("alu", None)     else       -> (None, None)
#     Ops.RANGE and u.dtype == dtypes.void  ->  prefix = None        (ptx.py:219)
#
# `Pf{has, prefix, ty, k, lst}` IS that tuple plus the two facts ptx.py spells at
# the USE SITE rather than in the table: `k`, how many `ssa` calls this uop makes,
# and `lst`, whether the answer is a list. `ty = ""` is Python's `None`, meaning
# "read `P.types_of(dt)`" -- no PTX type name is empty, so one field carries
# both the sentinel and the read.
#
# THE FOUR `k`/`lst` CASES and the fixture that separates each PAIR:
#   REG BUFFER  k = max_numel, lst ALWAYS true    f5 (4 -> `{a,b,c,d}`), f6 (1 -> `{a}`)
#   LOAD        k = max_numel, lst = max_numel>1  f10 (8 -> a list); the scalar
#                                                   LOAD of f19 shares the walk
#   PARAM       k = 1,          lst false         f13 (`%dat_u64_0`, `%dat_f32_0`)
#   table op    k = 1,          lst false         f1..f4
# ===========================================================================
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
# ptx.py:200 -- `u.src[0].addrspace in (AddrSpace.REG, AddrSpace.ALU)`. ALU IS
# the special's own address space (ops.py:910), which is why a LOAD of a
# SPECIAL is a copy and not a memory read.
def on_regsrc(+op: O.Op, +addr: S.Addr) -> Bool:
  Bool.and(Bool.or(is_idx(op), is_op(op, O.OpsLOAD{})),
    Bool.or(O.eq_addr(addr, S.AReg{}), O.eq_addr(addr, S.Aalu{})))

# ptx.py:219 -- `if u.op is Ops.RANGE and u.dtype == dtypes.void: prefix = None`.
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

# ===========================================================================
# THE ARM SELECTOR. ptx.py:186-220 is a chain of `if`s whose ORDER is
# load-bearing, because two of them overlap:
#
#   187  op in {NOOP, GROUP, CONST}        -> skip, no register
#   188  AFTER                             -> alias src0
#   191  SINK                              -> maybe rename the entry point
#   194  STACK                             -> collect srcs
#   197  BUFFER on a REG space             -> a LIST of `reg` registers
#   200  INDEX|SHRINK|LOAD on REG/ALU src0 -> pick / copy / REFUSE
#   206  SPECIAL                           -> "%" + arg, and a `.reg .u32`
#   207  LOAD                              -> scalar or list of `val`
#   209  PARAM                             -> `dat`, and a `.param`
#   210  WMMA                              -> tc_ptx.bend's `Tc` fragments; NAMED
#   216  the prefix table                  -> one `ssa`
#
# 197 BEFORE 216 is what keeps a REG buffer out of the table, and 200 BEFORE
# 207/209 is what keeps an on-REG LOAD from reading memory. In Python those two
# facts are two `if`s in one loop; here they are the order of this `Bool.pick`
# chain, so reordering it here is a mutation the table measures.
#
# A_REFUSE IS ITS OWN ARM rather than an error, because the gate wants the
# REFUSAL as a row (ptx.py:203) and a Bend fold cannot raise.
# ===========================================================================
def is_any3(+op: O.Op, os: List<&2, O.Op>) -> Bool: List.contains(~O.Op, O.eq_op, os, op)

# THE TAGS, AND `wk1.go`'s CASES ARE THESE NUMBERS. The two had drifted: A_ALLOC
# was 8 and `wk1.go` had no `case 8`, so every ordinary uop fell through `case _:`
# and the walk emitted NOTHING -- a green compile, 76 rows, every one of them
# empty. A_REG and A_ALLOC are ONE tag because `pf.of` already folded ptx.py:197
# into the same table, so they are the same action.
def A_SKIP() -> U32: 0
def A_NAME() -> U32: 1
def A_ALIAS() -> U32: 2
def A_STACK() -> U32: 3
def A_PICK() -> U32: 4
def A_REFUSE() -> U32: 5
def A_SPEC() -> U32: 6
def A_ALLOC() -> U32: 7

# ptx.py:202-204. `LOAD` copies the whole register; `INDEX`/`SHRINK` SUBSCRIPT
# it, and a subscript that is not a CONST-of-CAST is the refusal.
def arm.regsrc(+op: O.Op, idx_ok: Bool) -> U32:
  Bool.pick(U32, is_op(op, O.OpsLOAD{}), A_ALIAS(),
  Bool.pick(U32, idx_ok, A_PICK(), A_REFUSE()))

def arm.of(+op: O.Op, +addr: S.Addr, idx_ok: Bool) -> U32:
  Bool.pick(U32, is_any3(op, [O.OpsNOOP{}, O.OpsGROUP{}, O.OpsCONST{}]), A_SKIP(),
  Bool.pick(U32, is_op(op, O.OpsSINK{}), A_NAME(),
  Bool.pick(U32, is_op(op, O.OpsAFTER{}), A_ALIAS(),
  Bool.pick(U32, is_op(op, O.OpsSTACK{}), A_STACK(),
  Bool.pick(U32, is_reg(op, addr), A_ALLOC(),
  Bool.pick(U32, on_regsrc(op, addr), arm.regsrc(op, idx_ok),
  Bool.pick(U32, is_op(op, O.OpsSPECIAL{}), A_SPEC(),
  A_ALLOC())))))))

# ===========================================================================
# THE REFERENCE ARMS. `refs` are INDICES into the registers emitted so far,
# which is `r[u.src[i]]`; `List.get` over a `Data` list answers `Some` for every
# in-range index (MEASURED -- the `List<&2, Bool>` note in agent-core.md is
# about `Bool`, not about records).
# ===========================================================================
# THE "THIS STEP ALLOCATED NOTHING" MARKER: an `Rg` with no parts. It is what
# keeps `Wal.r` and the step list the same length, and `r_go` skips it.
def none_rg() -> Rg: Rg{False{}, Nil{}}
def has_rg(r: Rg) -> Bool: Bool.not(List.is_empty(&2, String, Rg.p(r)))

def rg_at.maybe(m: Maybe<&2, Rg>) -> Rg:
  match m:
    case Some{r}: r
    case None{}  : Rg{False{}, Nil{}}

def rg_at(w: Wal, +i: U32) -> Rg: rg_at.maybe(List.get(&2, Rg, Wal.r(w), U32.to_nat(i)))

# ptx.py:195 -- `[cast(str, r[x]) for x in u.src]`. `cast` is `typing.cast`, a
# runtime no-op, so the srcs' registers concatenate, and `Rg.l` is `True` even
# when ONE src was a bare string. That is the one place `is_list` is set without
# consulting `max_numel`, and `f11_stack` is the row: `{%local_u64_0, %alu_f32_0}`
# is a two-element list built from two SCALARS.
def st_walk(+rs: List<&2, Rg>, +ii: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ii:
    case Nil{}   : acc
    case i <> +t :
      +rest = st_walk(rs, t, acc)
      List.append(&2, String, Rg.p(rg_at.maybe(List.get(&2, Rg, rs, U32.to_nat(i)))), rest)

def rg_stack(w: Wal, +s: Wk) -> Rg: Rg{True{}, st_walk(Wal.r(w), Wk.refs(s), Nil{})}

# ptx.py:204 -- `r[u.src[0]][u.src[1].src[0].val]`, a SUBSCRIPT and so always a
# scalar string: `f7_reuse` prints `%reg_f16_2` where its INDEX's value is 2. The
# `Maybe` reader is here because `List.get` is the subscript and it answers
# `None` past the end, which a REG buffer never gets to in a legal kernel.
def rg_pick.pick(m: Maybe<&2, String>) -> Rg:
  match m:
    case Some{x}: Rg{False{}, [x]}
    case None{}  : Rg{False{}, Nil{}}

def rg_pick(w: Wal, +s: Wk) -> Rg:
  rg_pick.pick(List.get(&2, String, Rg.p(rg_at(w, 0)), U32.to_nat(Wk.idx(s))))

# ===========================================================================
# ===========================================================================
# `to_function_name` -- helpers.py:156, reached from ptx.py:192 through
# `KernelInfo.function_name` (ops.py:1349):
#     ''.join(c if c in (ascii_letters+digits+'_') else f'{ord(c):02X}' for c in ansistrip(s))
#
# UPPERCASE hex, TWO digits, so "my kernel" is `my20kernel`. THE WALL is
# `ansistrip`, a regex ANSI strip: no fixture here carries an escape, so the
# gate covers the KEEP/HEX branch and not the strip. `hex1`/`hexdig` are
# tc_ptx.bend's (`P.hex1`) -- consumed, because a second hex table is the drift.
# ===========================================================================
# A RANGE IS `and(ge, le)`. MEASURED: writing `or(ge(c,48), le(c,57))` says
# "c >= 48 OR c <= 57", which is EVERY c, so `fn_name` became the identity and
# `to_function_name 'my kernel'` came back `my kernel` instead of `my20kernel`.
# Eight `to_function_name` rows and five of them moved; this is the gate working.
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
# ===========================================================================
# ptx.py:206 and 227 -- `r[u] = "%" + u.arg`, and the `.reg .u32` line is
# PREPENDED (`kernel = [f".reg .u32 %{u.arg};"] + kernel`), so `f10_loads`
# emits `%g2, %g1, %g0`. `List.append(acc, [x])` APPENDS and would print them
# in toposort order: a byte diff on three rows and a Bool either way.
def wk_spec.go(+w: Wal, +line: String, +reg: String) -> Wal:
  Wal.rput(Wal.kset(w, List.append(&2, String, [P.fmt(line)], Wal.kern(w))), Rg{False{}, [reg]})

def wk_spec(+w: Wal, +s: Wk) -> Wal:
  wk_spec.go(w, String.concat([".reg .u32 %", Wk.nm(s), ";"]), String.concat(["%", Wk.nm(s)]))

# ptx.py:185 and 191-192 -- `name` starts at "test" and a SINK carrying an arg
# renames it. NAMED here, because the entry point is a WALK output: the `.reg`
# block is not.
def wk_name(+w: Wal, +s: Wk) -> Wal: Bool.pick(Wal, is_op(Wk.op(s), O.OpsSINK{}), Wal.nset(w, fn_name(Wk.nm(s))), w)

# ptx.py:220 -- `if prefix: r[u] = ssa(prefix, u, dtype)`, and ptx.py:197-208's
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
    case 2: Wal.rput(w, rg_at(w, 0))
    case 3: Wal.rput(w, rg_stack(w, s))
    case 4: Wal.rput(w, rg_pick(w, s))
    case 5: Wal.rput(Wal.refset(w, O.Ops.name.of(Wk.op(s))), none_rg())
    case 6: wk_spec(w, s)
    case _: wk_alloc(w, s)

def wk1(+w: Wal, +s: Wk) -> Wal: wk1.go(arm.of(Wk.op(s), Wk.addr(s), Wk.idx_ok(s)), w, s)

# ptx.py:203 -- the raise ENDS `render`, so the walk STOPS. `Bool.pick` is
# NOT an `if`: it CHOOSES, and `wk_all(wk1(w, s), t)` in the losing arm would
# still be evaluated and would burn the list, so the recursion is bound first
# and the guard reads the RESULT of one step.
def wk_all(+ss: List<&2, Wk>, w: Wal) -> Wal:
  match ss:
    case Nil{}   : w
    case s <> +t :
      +n1 = wk1(w, s)
      Bool.pick(Wal, String.is_empty(Wal.ref(n1)), wk_all(t, n1), n1)

# ===========================================================================
# THE `.reg` BLOCK. ptx.py:165 hands `render_kernel` `c.items()` and it prints
#
#     f".reg .{reg.split('_')[-2]} %{reg}<{cnt}>;"    for reg,cnt in regs
#
# `reg` is the COUNTER KEY, so `[-2]` is the key's DTYPE field -- `reg_f32_`
# splits to `["reg","f32",""]` -- and `<cnt>` is how many times `ssa` allocated
# under it. The key is built from `(prefix, ty)`, so the split is not
# re-derived, and `f3_cast` is the row that says the dtype field is the SECOND
# and not the first: `cast_s32_` prints `.s32`, so a `[-1]` would print `.s32`
# too and a `[-3]` would print `.cast`.
#
# `render_kernel` puts these BEFORE the body and the body BEFORE `ret;`, and
# ptx.py:227's `.reg .u32` lines are INSIDE the body, so the whole block is
# `decls ++ kern`. `f10_loads` pins the `++`: `kern ++ decls` is a byte diff.
# ===========================================================================
def reg_line(+key: String, +ty: String, +n: U32) -> String:
  P.fmt(String.concat([".reg .", ty, " %", key, "<", U32.show(n), ">;"]))

def reg_go(+cs: List<&2, Cnt>, +acc: List<&2, String>) -> List<&2, String>:
  match cs:
    case Nil{}   : acc
    case c <> +t : reg_go(t, List.append(&2, String, acc, [reg_line(Cnt.key(c), Cnt.ty(c), Cnt.n(c))]))

def reg_block(+w: Wal) -> List<&2, String>:
  List.concat(&2, String, [reg_go(Wal.c(w), Nil{}), Wal.kern(w)])

# ===========================================================================
# THE GATE ROWS.
# ===========================================================================
# A ROW IS (its suffix, the answer, the LITERAL). `Wt.want` is generated from
# the oracle's rows by `.agents/slop/ptx-s3-gen.py` and is NEVER typed -- five
# incidents in this repo where a typed oracle agreed with a swapped argument.
# `T.r` and `P.esc` are CONSUMED: the row builder (in `tc.bend`) and the TAB
# escape are one definition each, and a second copy would let the two files
# drift on the format.
# ===========================================================================
type Wt is Data:
  Wt{nm: String, want: String}
def Wt.nm(+w: Wt) -> String:
  match w:
    case Wt{nm, want}: nm
def Wt.want(+w: Wt) -> String:
  match w:
    case Wt{nm, want}: want

# THE COMPUTED SIDE, ONE ENTRY PER ROW -- a LIST, not one concatenated string,
# because `zip.of` reads the computed value by index and a string would be
# indexed by CHARACTER.
#
# `r[i]` for every step the walk gave a register to, in the FIXTURE'S OWN order.
# A skipped uop (NOOP/GROUP/CONST/SINK) contributes no row, and that ABSENCE is
# a claim: `f14_skips` has three skipped steps at indices 0..2 and its first `r`
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
# non-empty only when ptx.py:203 fired, and then NOTHING ELSE is produced -- the
# raise ends `render`, so there is no register and no `.reg` block at all.
def gots.happy(+ss: List<&2, Wk>, +w: Wal) -> List<&2, String>:
  List.concat(&2, String, [r_go(ss, Wal.r(w), 0, Nil{}), gots.fix(w)])

# THE FIXTURE'S OWN ROW COUNT, appended as the LAST row. The per-line diff cannot
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

# THE WANTS DRIVE AND THE COMPUTED VALUES ARE READ BY INDEX. A `Wt` with no
# computed value prints `<none>` and the walk CONTINUES; a computed value with no
# `Wt` prints as `.EXTRA[i]`. A gate that silently drops its tail is a gate that
# agrees with a port that stops early, and `reg.count` is the one row that makes
# either visible in a single place. The lists are at most thirty rows, so the
# quadratic `List.get` is the price of not needing a MUTUAL recursion -- which
# Bend refuses, and which is why `zip.of` walks ONE list.
# THE COMPUTED VALUES THE WANTS NEVER REACHED. `zip.of` reads `gs` BY INDEX, so
# the leftovers are `dropn(gs, i)` -- dropping them is what stops every computed
# value being reported twice, once matched and once as EXTRA.
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
def r_fns() -> String: String.concat([T.r(String.concat(["to_function_name ", "'test'"]), fn_name("test"), "test"), T.r(String.concat(["to_function_name ", "'my kernel'"]), fn_name("my kernel"), "my20kernel"), T.r(String.concat(["to_function_name ", "'MyKernel'"]), fn_name("MyKernel"), "MyKernel"), T.r(String.concat(["to_function_name ", "'a-b'"]), fn_name("a-b"), "a2Db"), T.r(String.concat(["to_function_name ", "'x$y.z'"]), fn_name("x$y.z"), "x24y2Ez"), T.r(String.concat(["to_function_name ", "'  lead'"]), fn_name("  lead"), "2020lead"), T.r(String.concat(["to_function_name ", "'trail  '"]), fn_name("trail  "), "trail2020"), T.r(String.concat(["to_function_name ", "'a b c'"]), fn_name("a b c"), "a20b20c"), T.r(String.concat(["to_function_name ", "'a~b'"]), fn_name("a~b"), "a7Eb"), T.r(String.concat(["to_function_name ", "'a/b'"]), fn_name("a/b"), "a2Fb"), T.r(String.concat(["to_function_name ", "'a:b'"]), fn_name("a:b"), "a3Ab"), T.r(String.concat(["to_function_name ", "'a0b'"]), fn_name("a0b"), "a0b"), T.r(String.concat(["to_function_name ", "'a_b'"]), fn_name("a_b"), "a_b")])

def f1_alu_ss() -> List<&2, Wk>:
   [Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsMUL{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f1_alu() -> String: r_fix("f1_alu", f1_alu_ss(),
   [Wt{".r[0] BUFFER", "%local_u64_0"},
   Wt{".r[2] CAST", "%cast_f32_0"},
   Wt{".r[3] ADD", "%alu_f32_0"},
   Wt{".r[5] CAST", "%cast_f32_1"},
   Wt{".r[6] MUL", "%alu_f32_1"},
   Wt{".r[8] CAST", "%cast_f32_2"},
   Wt{".r[9] ADD", "%alu_f32_2"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %cast_f32_<3>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.f32 %alu_f32_<3>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "13"}])
def f2_counter_ss() -> List<&2, Wk>:
   [Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f2_counter() -> String: r_fix("f2_counter", f2_counter_ss(),
   [Wt{".r[0] BUFFER", "%local_u64_0"},
   Wt{".r[2] CAST", "%cast_f32_0"},
   Wt{".r[3] ADD", "%alu_f32_0"},
   Wt{".r[5] CAST", "%cast_f32_1"},
   Wt{".r[6] ADD", "%alu_f32_1"},
   Wt{".r[8] CAST", "%cast_f32_2"},
   Wt{".r[9] ADD", "%alu_f32_2"},
   Wt{".r[11] CAST", "%cast_f32_3"},
   Wt{".r[12] ADD", "%alu_f32_3"},
   Wt{".r[14] CAST", "%cast_f32_4"},
   Wt{".r[15] ADD", "%alu_f32_4"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %cast_f32_<5>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.f32 %alu_f32_<5>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "17"}])
def f3_cast_ss() -> List<&2, Wk>:
   [Wk{O.OpsBUFFER{}, S.int32(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsBUFFER{}, S.uint32(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.uint32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsBUFFER{}, S.int64(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.int64(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsBUFFER{}, S.half(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.half(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f3_cast() -> String: r_fix("f3_cast", f3_cast_ss(),
   [Wt{".r[0] BUFFER", "%local_u64_0"},
   Wt{".r[1] CAST", "%cast_s32_0"},
   Wt{".r[2] BUFFER", "%local_u64_1"},
   Wt{".r[3] CAST", "%cast_u32_0"},
   Wt{".r[4] BUFFER", "%local_u64_2"},
   Wt{".r[5] CAST", "%cast_s64_0"},
   Wt{".r[6] BUFFER", "%local_u64_3"},
   Wt{".r[7] CAST", "%cast_f16_0"},
   Wt{".r[8] BUFFER", "%local_u64_4"},
   Wt{".r[9] CAST", "%cast_f32_0"},
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
   [Wk{O.OpsBUFFER{}, S.int32(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.int32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsEND{}, S.int32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f4_pred() -> String: r_fix("f4_pred", f4_pred_ss(),
   [Wt{".r[0] BUFFER", "%local_u64_0"},
   Wt{".r[2] CAST", "%cast_s32_0"},
   Wt{".r[3] ADD", "%alu_s32_0"},
   Wt{".r[4] END", "%pred_pred_0"},
   Wt{".reg.count", "4"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.s32 %cast_s32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.s32 %alu_s32_<1>;"},
   Wt{".reg[3]", "\\t.reg\\t\\t.pred %pred_pred_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "11"}])
def f5_regbuf_ss() -> List<&2, Wk>:
   [Wk{O.OpsBUFFER{}, S.single(), S.AReg{}, 4, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f5_regbuf() -> String: r_fix("f5_regbuf", f5_regbuf_ss(),
   [Wt{".r[0] BUFFER", "{%reg_f32_0, %reg_f32_1, %reg_f32_2, %reg_f32_3}"},
   Wt{".reg.count", "1"},
   Wt{".reg[0]", "\\t.reg\\t\\t.f32 %reg_f32_<4>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "5"}])
def f6_regbuf1_ss() -> List<&2, Wk>:
   [Wk{O.OpsBUFFER{}, S.single(), S.AReg{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f6_regbuf1() -> String: r_fix("f6_regbuf1", f6_regbuf1_ss(),
   [Wt{".r[0] BUFFER", "{%reg_f32_0}"},
   Wt{".reg.count", "1"},
   Wt{".reg[0]", "\\t.reg\\t\\t.f32 %reg_f32_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "5"}])
def f7_reuse_ss() -> List<&2, Wk>:
   [Wk{O.OpsBUFFER{}, S.half(), S.AReg{}, 4, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsINDEX{}, S.single(), S.AReg{}, 1, "", [0], 2, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSPECIAL{}, S.single(), S.Aalu{}, 1, "g0", Nil{}, 0, True{}},
   Wk{O.OpsLOAD{}, S.single(), S.AReg{}, 4, "", [0], 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f7_reuse() -> String: r_fix("f7_reuse", f7_reuse_ss(),
   [Wt{".r[0] BUFFER", "{%reg_f16_0, %reg_f16_1, %reg_f16_2, %reg_f16_3}"},
   Wt{".r[2] CAST", "%cast_s32_0"},
   Wt{".r[3] INDEX", "%reg_f16_2"},
   Wt{".r[5] SPECIAL", "%g0"},
   Wt{".r[6] LOAD", "{%reg_f16_0, %reg_f16_1, %reg_f16_2, %reg_f16_3}"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.f16 %reg_f16_<4>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.s32 %cast_s32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.u32 %g0;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "11"}])
def f8_refuse_ss() -> List<&2, Wk>:
   [Wk{O.OpsBUFFER{}, S.half(), S.AReg{}, 4, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.int32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsINDEX{}, S.single(), S.AReg{}, 1, "", [0], 0, False{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f8_refuse() -> String: r_fix("f8_refuse", f8_refuse_ss(),
   [Wt{".REFUSAL", "PTX does not support dynamic register indexing: INDEX"}])
def f9_special_ss() -> List<&2, Wk>:
   [Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSPECIAL{}, S.single(), S.Aalu{}, 1, "l1", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f9_special() -> String: r_fix("f9_special", f9_special_ss(),
   [Wt{".r[0] BUFFER", "%local_u64_0"},
   Wt{".r[2] SPECIAL", "%l1"},
   Wt{".r[3] ADD", "%alu_f32_0"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %alu_f32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.u32 %l1;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "9"}])
def f10_loads_ss() -> List<&2, Wk>:
   [Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 8, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSPECIAL{}, S.single(), S.Aalu{}, 1, "g0", Nil{}, 0, True{}},
   Wk{O.OpsLOAD{}, S.single(), S.AGlobal{}, 8, "", Nil{}, 0, True{}},
   Wk{O.OpsSPECIAL{}, S.single(), S.Aalu{}, 1, "g1", Nil{}, 0, True{}},
   Wk{O.OpsLOAD{}, S.single(), S.AGlobal{}, 8, "", Nil{}, 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 8, "", Nil{}, 0, True{}},
   Wk{O.OpsSPECIAL{}, S.single(), S.Aalu{}, 1, "g2", Nil{}, 0, True{}},
   Wk{O.OpsLOAD{}, S.single(), S.AGlobal{}, 8, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f10_loads() -> String: r_fix("f10_loads", f10_loads_ss(),
   [Wt{".r[0] BUFFER", "%local_u64_0"},
   Wt{".r[2] SPECIAL", "%g0"},
   Wt{".r[3] LOAD", "{%val_f32_0, %val_f32_1, %val_f32_2, %val_f32_3, %val_f32_4, %val_f32_5, %val_f32_6, %val_f32_7}"},
   Wt{".r[4] SPECIAL", "%g1"},
   Wt{".r[5] LOAD", "{%val_f32_8, %val_f32_9, %val_f32_10, %val_f32_11, %val_f32_12, %val_f32_13, %val_f32_14, %val_f32_15}"},
   Wt{".r[6] BUFFER", "%local_u64_1"},
   Wt{".r[7] SPECIAL", "%g2"},
   Wt{".r[8] LOAD", "{%val_f32_16, %val_f32_17, %val_f32_18, %val_f32_19, %val_f32_20, %val_f32_21, %val_f32_22, %val_f32_23}"},
   Wt{".reg.count", "5"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<2>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %val_f32_<24>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.u32 %g2;"},
   Wt{".reg[3]", "\\t.reg\\t\\t.u32 %g1;"},
   Wt{".reg[4]", "\\t.reg\\t\\t.u32 %g0;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "16"}])
def f11_stack_ss() -> List<&2, Wk>:
   [Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSTACK{}, S.single(), S.Aalu{}, 1, "", [0, 3], 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f11_stack() -> String: r_fix("f11_stack", f11_stack_ss(),
   [Wt{".r[0] BUFFER", "%local_u64_0"},
   Wt{".r[2] CAST", "%cast_f32_0"},
   Wt{".r[3] ADD", "%alu_f32_0"},
   Wt{".r[4] STACK", "{%local_u64_0, %alu_f32_0}"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %cast_f32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.f32 %alu_f32_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "10"}])
def f12_after_ss() -> List<&2, Wk>:
   [Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsAFTER{}, S.single(), S.Aalu{}, 1, "", [0], 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f12_after() -> String: r_fix("f12_after", f12_after_ss(),
   [Wt{".r[0] BUFFER", "%local_u64_0"},
   Wt{".r[1] AFTER", "%local_u64_0"},
   Wt{".reg.count", "1"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "6"}])
def f13_param_ss() -> List<&2, Wk>:
   [Wk{O.OpsPARAM{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsPARAM{}, S.single(), S.ALocal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f13_param() -> String: r_fix("f13_param", f13_param_ss(),
   [Wt{".r[0] PARAM", "%dat_u64_0"},
   Wt{".r[1] PARAM", "%dat_f32_0"},
   Wt{".reg.count", "2"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %dat_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %dat_f32_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "7"}])
def f14_skips_ss() -> List<&2, Wk>:
   [Wk{O.OpsNOOP{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsGROUP{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

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
   [Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSPECIAL{}, S.single(), S.Aalu{}, 1, "g0", Nil{}, 0, True{}},
   Wk{O.OpsINDEX{}, S.single(), S.AGlobal{}, 1, "", [0], 0, True{}},
   Wk{O.OpsSPECIAL{}, S.single(), S.Aalu{}, 1, "g1", Nil{}, 0, True{}},
   Wk{O.OpsSHRINK{}, S.single(), S.AGlobal{}, 1, "", [0, 0], 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f15_bidx() -> String: r_fix("f15_bidx", f15_bidx_ss(),
   [Wt{".r[0] BUFFER", "%local_u64_0"},
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
   [Wk{O.OpsBUFFER{}, S.int32(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsBITCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f16_bitcast() -> String: r_fix("f16_bitcast", f16_bitcast_ss(),
   [Wt{".r[0] BUFFER", "%local_u64_0"},
   Wt{".r[1] CAST", "%cast_f32_0"},
   Wt{".r[2] BITCAST", "%cast_f32_1"},
   Wt{".reg.count", "2"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %cast_f32_<2>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "8"}])
def f17_u64_ss() -> List<&2, Wk>:
   [Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSPECIAL{}, S.single(), S.Aalu{}, 1, "g0", Nil{}, 0, True{}},
   Wk{O.OpsINDEX{}, S.single(), S.AGlobal{}, 1, "", [0], 0, True{}},
   Wk{O.OpsSPECIAL{}, S.single(), S.Aalu{}, 1, "g1", Nil{}, 0, True{}},
   Wk{O.OpsSHRINK{}, S.single(), S.AGlobal{}, 1, "", [0, 0], 0, True{}},
   Wk{O.OpsBUFFER{}, S.int32(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.int32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsEND{}, S.int32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f17_u64() -> String: r_fix("f17_u64", f17_u64_ss(),
   [Wt{".r[0] BUFFER", "%local_u64_0"},
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
   [Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f18_name() -> String: r_fix("f18_name", f18_name_ss(),
   [Wt{".r[0] BUFFER", "%local_u64_0"},
   Wt{".r[2] CAST", "%cast_f32_0"},
   Wt{".r[3] ADD", "%alu_f32_0"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %cast_f32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.f32 %alu_f32_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "9"}])
def f19_mixed_ss() -> List<&2, Wk>:
   [Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSPECIAL{}, S.single(), S.Aalu{}, 1, "g0", Nil{}, 0, True{}},
   Wk{O.OpsINDEX{}, S.single(), S.AGlobal{}, 1, "", [0], 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsPARAM{}, S.half(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSPECIAL{}, S.single(), S.Aalu{}, 1, "g1", Nil{}, 0, True{}},
   Wk{O.OpsLOAD{}, S.single(), S.AGlobal{}, 4, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f19_mixed() -> String: r_fix("f19_mixed", f19_mixed_ss(),
   [Wt{".r[0] BUFFER", "%local_u64_0"},
   Wt{".r[1] CAST", "%cast_s32_0"},
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
   [Wk{O.OpsBUFFER{}, S.int32(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.int32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsEND{}, S.int32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f20_idx_pred() -> String: r_fix("f20_idx_pred", f20_idx_pred_ss(),
   [Wt{".r[0] BUFFER", "%local_u64_0"},
   Wt{".r[2] CAST", "%cast_s32_0"},
   Wt{".r[3] ADD", "%alu_s32_0"},
   Wt{".r[4] END", "%pred_pred_0"},
   Wt{".reg.count", "4"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.s32 %cast_s32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.s32 %alu_s32_<1>;"},
   Wt{".reg[3]", "\\t.reg\\t\\t.pred %pred_pred_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "11"}])
def f21_name_ss() -> List<&2, Wk>:
   [Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "my kernel", Nil{}, 0, True{}}]

def f21_name() -> String: r_fix("f21_name", f21_name_ss(),
   [Wt{".r[0] BUFFER", "%local_u64_0"},
   Wt{".r[2] CAST", "%cast_f32_0"},
   Wt{".r[3] ADD", "%alu_f32_0"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %cast_f32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.f32 %alu_f32_<1>;"},
   Wt{".entry", ".visible .entry my20kernel ("},
   Wt{".rows", "9"}])
def f22_name2_ss() -> List<&2, Wk>:
   [Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "MyKernel", Nil{}, 0, True{}}]

def f22_name2() -> String: r_fix("f22_name2", f22_name2_ss(),
   [Wt{".r[0] BUFFER", "%local_u64_0"},
   Wt{".r[2] CAST", "%cast_f32_0"},
   Wt{".r[3] ADD", "%alu_f32_0"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %cast_f32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.f32 %alu_f32_<1>;"},
   Wt{".entry", ".visible .entry MyKernel ("},
   Wt{".rows", "9"}])
def f23_load1_ss() -> List<&2, Wk>:
   [Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSPECIAL{}, S.single(), S.Aalu{}, 1, "g0", Nil{}, 0, True{}},
   Wk{O.OpsLOAD{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f23_load1() -> String: r_fix("f23_load1", f23_load1_ss(),
   [Wt{".r[0] BUFFER", "%local_u64_0"},
   Wt{".r[2] SPECIAL", "%g0"},
   Wt{".r[3] LOAD", "%val_f32_0"},
   Wt{".reg.count", "3"},
   Wt{".reg[0]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.f32 %val_f32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.u32 %g0;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "9"}])
def f24_range_ss() -> List<&2, Wk>:
   [Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.int32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsRANGE{}, S.int32(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f24_range() -> String: r_fix("f24_range", f24_range_ss(),
   [Wt{".r[1] CAST", "%cast_s32_0"},
   Wt{".r[2] RANGE", "%ridx_s32_0"},
   Wt{".r[3] BUFFER", "%local_u64_0"},
   Wt{".r[5] CAST", "%cast_f32_0"},
   Wt{".r[6] ADD", "%alu_f32_0"},
   Wt{".reg.count", "5"},
   Wt{".reg[0]", "\\t.reg\\t\\t.s32 %cast_s32_<1>;"},
   Wt{".reg[1]", "\\t.reg\\t\\t.s32 %ridx_s32_<1>;"},
   Wt{".reg[2]", "\\t.reg\\t\\t.u64 %local_u64_<1>;"},
   Wt{".reg[3]", "\\t.reg\\t\\t.f32 %cast_f32_<1>;"},
   Wt{".reg[4]", "\\t.reg\\t\\t.f32 %alu_f32_<1>;"},
   Wt{".entry", ".visible .entry test ("},
   Wt{".rows", "13"}])
def f25_rangevoid_ss() -> List<&2, Wk>:
   [Wk{O.OpsNOOP{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsRANGE{}, S.void(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsBUFFER{}, S.single(), S.AGlobal{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCONST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsCAST{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsADD{}, S.single(), S.Aalu{}, 1, "", Nil{}, 0, True{}},
   Wk{O.OpsSINK{}, S.single(), S.Aalu{}, 1, "test", Nil{}, 0, True{}}]

def f25_rangevoid() -> String: r_fix("f25_rangevoid", f25_rangevoid_ss(),
   [Wt{".r[2] BUFFER", "%local_u64_0"},
   Wt{".r[4] CAST", "%cast_f32_0"},
   Wt{".r[5] ADD", "%alu_f32_0"},
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

# ===========================================================================
# THE MUTATION TABLE. Measured 2026-10-02 with `.agents/slop/ptx-s3-mutate.py`:
# 30 mutations, one textual edit at a time, each row diffed against the
# unmutated 281 by WHOLE `name=value` LINE and never by row NAME -- a
# name-comparing harness reported 0 for every mutation in two other units. The
# mutated copy is written BESIDE this file (`_ptxmut.bend`) because ptx.bend
# IMPORTS ./tc_ptx.bend by a relative path and a copy in a scratch dir cannot
# resolve it. Full table with every row count: `.agents/slop/notes/bend2-constraints.md`,
# search `MUT-PTX-S3`.
#   python3 .agents/slop/ptx-s3-mutate.py > .agents/slop/ptxown/mut.txt
#
# WHAT THE TABLE SAYS
# ---------------------------------------------------------------------------
# M29 IS A THEOREM FOR THIS FILE, NOT A FIXTURE GAP. Dropping CONST from the skip
# list routes it to `A_ALLOC`, and `pf.of` has no CONST arm -- so it takes
# `no_pf()` and `wk_alloc.go` writes the SAME `none_rg()` the skip arm writes. A
# CONST allocates nothing under every arm, so no graph can separate the two. It
# matters upstream only because `string_rewrite` gives a CONST a `mov` LINE
# (ptx.py:83), which this file does not port. The honest record: `arm.of`'s skip
# LIST is not gated by this file, and its CONST member is dead here.
#
# M12, M13 AND M14 WERE BLINDS UNTIL THREE FIXTURES EXISTED -- the clearest
# argument in this file for the discipline. There was no fixture with a LOAD of
# `max_numel == 1` and none with an `Ops.RANGE` AT ALL. `f23_load1` is the fix for
# M12 and is the ONLY thing separating ptx.py:208's `if max_numel > 1` from
# ptx.py:198's comprehension. `f24_range`/`f25_rangevoid` fix M13/M14; `f25` had
# to be built with `UOp.loop`, NOT `UOp.range(..., dtype=void)`, because the
# latter's bound is `CAST(CONST 3) -> void` and a CAST to void asks `types[void]`
# for a key ptx.py's table does not have, so CPython raised KeyError at ptx.py:181
# before the walk reached the RANGE. MEASURED, and it is why `f25` has a NOOP at
# index 0. M10 was a blind for a different reason: the first edit pattern did not
# match the source, so the "mutation" was a no-op -- a mutation that does not
# apply is a zero that means nothing.
#
# M03 MOVES ONLY TWO ROWS AND THAT IS THE POINT. `c[prefix] += 1` runs inside
# `ssa`, once per ELEMENT, so a four-element REG buffer leaves the counter at four.
# M15 AND M16 ARE BOTH ORDER BUGS IN OPPOSITE DIRECTIONS: ptx.py:227 PREPENDS each
# SPECIAL's `.reg .u32` line and `render_kernel` puts the declarations BEFORE the
# body, so the block is `decls ++ kern` and the specials come out in REVERSE
# toposort order (`f10_loads` prints `%g2, %g1, %g0`). A gate that compared the
# block as a SET would notice neither. M26 IS WHAT MAKES A PERMUTATION VISIBLE --
# `f1_alu.rows` is that fixture's own row count, so a right-length wrong-ORDER
# list is a moved row rather than a green gate.
#
# THE CONSTANTS SWEEP (`+1` on every numeric literal in the non-generated,
# comment-stripped code -- SEVENTEEN sites) went 5, then 10, then 13, then 15 over
# four rounds, and each round was a missing FIXTURE, not a weak harness: round 1
# added `a~b` (126, one above 122), `a/b` (47, one below 48), `a:b` (58, one below
# 65) because no `to_function_name` input sat just OUTSIDE a range; round 2 added
# `a0b` and `a_b` because no input contained a DIGIT (`48` is the digit range's LOW
# bound) or an UNDERSCORE (`95` is `_`). THE TWO THAT REMAIN ARE PROVEN INERT, not
# unexplained: `A_ALLOC`'s value 7 is absorbed by `case _:`, so `wk1.go`'s
# catch-all makes the LAST tag unobservable -- the tag's MEANING is pinned instead
# by M28 (14 rows), which reaches it through `arm.of` rather than through its
# number; and `P.px_pline(3)`'s index has exactly one consumer (the `.entry` row)
# and is CONSUMED from tc_ptx.bend, so a second copy could not be wrong here
# either. "PROVEN INERT" is the difference between a blind list and an excuse:
# `case _` and a single consumer are readable facts about the code.
#
# AND THE SWEEP ITSELF HAD THREE BUGS BEFORE IT MEASURED ANYTHING, all three worth
# recording because each reported a confident 0: (1) it rewrote byte 0 of the file
# for every site (the offset was into the LINE, not into the source), so all 119
# sites -- every one of them a comment -- reported 0; (2) after the offset fix it
# still reported 0, because it spliced the GENERATED region out and ran the result,
# so `r_all()` called defs that no longer existed and every site was a COMPILE
# ERROR; (3) after that it still reported 0, because `BASE_OFF` was advanced after
# the `continue` that skips 0/1/2, so the offsets drifted on exactly the lines that
# had a skipped literal. The hand check that caught (1) -- bump `A_STACK` to 9 and
# see seven rows move -- is the only reason the sweep is worth believing. It also
# REPRODUCES x86's measured finding that a constants sweep finds NONE of the logic
# defects: the moving sites are all `to_function_name` and the tag constants, and
# every port-defect class in this file was found by a RULE mutation or by the
# string diff, not by `+1`.
# ===========================================================================
