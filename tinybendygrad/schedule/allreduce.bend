# allreduce.bend -- tinygrad/schedule/allreduce.py, the ring / all2all / naive
# allreduce lowering.
#
# what this file is, and what it is not. `allreduce.py` is 75 lines and two defs:
# `handle_allreduce` and `create_allreduce_function`. Almost all of
# `handle_allreduce` is BUILDING A GRAPH -- `mselect`, `copy_to_device`, `shrink`,
# `pad`, `mstack`, `usum`, `reshape`, `allreduce` -- and not one of those builders is
# ported (each is a `TODO(p3)` in `ops.bend`, ops.py:423 through :853). So what is
# here is the part that is ARITHMETIC AND DECISION, and that part is the whole
# algorithm: which of the three reductions runs, and with what chunk boundaries. The
# graph each one assembles is the wall, and it is named where it bites.
#
# DEPENDENCY ON A SIBLING. `schedule/__init__.py` owns the only caller of
# `handle_allreduce`, through `replace_allreduce` / `_early_allreduce` in
# `schedule/multi.py`. Nothing here imports either, and the gate fixtures are built
# standalone, so the three files in this directory meet only at the call site.
#

# the flags are parameters, and that is the one convention in this file.
#
# `RING`, `ALL2ALL`, `ALLREDUCE_CAST`, `ALLREDUCE_NODE_NDEVS` and
# `RING_ALLREDUCE_THRESHOLD` are `ContextVar`s (helpers.py) and Bend has no
# `Config` and no process environment. A `Flags` record would be the helpers.bend
# answer and it is P6, so here they are a `Cfg` PARAMETER of every def that reads
# one. The gate builds several `Cfg` values and the row set below is what says the
# three modes are actually distinguishable -- an all-True selection row would be
# worthless, since `NAIVE` is the answer for every small case.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F

# THE RECORDS. `Chk` is one `(start, end)` chunk bound and `Ch` is the chunking's
# three derived numbers, which is all `allreduce.py:36-38` computes before it starts
# building anything.

type Cfg is Data:
  Cfg{ring: U32, all2all: U32, thr: U32, hdev: U32, cast: Bool}

# `Sel` is `allreduce.py:13-15`'s three locals. They are kept SEPARATE rather than
# collapsed into a mode enum because Python keeps them separate and uses them
# separately: `use_ring`'s own expression reads `use_all2all`, and the `DEBUG >= 2`
# print at :16 asks which is true, not "what mode is this".
type Sel is Data:
  Sel{concrete: Bool, a2: Bool, ring: Bool}

type Ch is Data:
  Ch{factor: U32, base: U32, left: U32}

type Chk is Data:
  Chk{s: U32, e: U32}

def Cfg.ring(x: Cfg) -> U32:
  match x:
    case Cfg{ring, all2all, thr, hdev, cast}: ring

def Cfg.all2all(x: Cfg) -> U32:
  match x:
    case Cfg{ring, all2all, thr, hdev, cast}: all2all

def Cfg.thr(x: Cfg) -> U32:
  match x:
    case Cfg{ring, all2all, thr, hdev, cast}: thr

def Cfg.cast(x: Cfg) -> Bool:
  match x:
    case Cfg{ring, all2all, thr, hdev, cast}: cast

def Sel.concrete(s: Sel) -> Bool:
  match s:
    case Sel{concrete, a2, ring}: concrete

def Sel.a2(s: Sel) -> Bool:
  match s:
    case Sel{concrete, a2, ring}: a2

def Sel.ring(s: Sel) -> Bool:
  match s:
    case Sel{concrete, a2, ring}: ring

def Ch.base(c: Ch) -> U32:
  match c:
    case Ch{factor, base, left}: base

def Ch.left(c: Ch) -> U32:
  match c:
    case Ch{factor, base, left}: left

def Chk.s(x: Chk) -> U32:
  match x:
    case Chk{s, e}: s

def Chk.e(x: Chk) -> U32:
  match x:
    case Chk{s, e}: e

# THE MODE, as a number, because `main` prints numbers. 0 is NAIVE, 1 is RING,
# 2 is ALL2ALL -- and the ORDER IS PYTHON'S: `allreduce.py:16` prints
# `'ALL2ALL' if use_all2all else 'RING' if use_ring else 'NAIVE'`, so ALL2ALL is
# tested FIRST, and a configuration that somehow satisfied both flags would print
# ALL2ALL. `use_ring`'s own expression already excludes `use_all2all`
# (`and not use_all2all`), so the tie cannot arise -- and the gate row `sel_both`
# is what says so rather than leaving it to the reader.

def red_mode.ring(ring: Bool) -> U32:
  match ring:
    case True{}: 1
    case _: 0

def red_mode.of(a2: Bool, ring: Bool) -> U32:
  match a2:
    case True{}: 2
    case False{}: red_mode.ring(ring)

def red_mode(+s: Sel) -> U32:
  red_mode.of(Sel.a2(s), Sel.ring(s))

# `concrete = all_int(shape)` -- allreduce.py:13. Every dim of `buf.shape` must be a
# plain int; a symbolic dim makes the whole reduction NAIVE, because the chunk
# arithmetic below is integer division and would be meaningless otherwise.

def red_is_int(s: O.Sint) -> Bool:
  O.SInt.is_int(s)

def red_all_int.go(sh: List<&2, O.Sint>) -> Bool:
  match sh:
    case Nil{}: True{}
    case s <> t: Bool.and(red_is_int(s), red_all_int.go(t))

def red_all_int(+sh: List<&2, O.Sint>) -> Bool:
  red_all_int.go(sh)

# `numel = prod(buf.shape)` -- allreduce.py:8. `mixin/movement.py:55`'s `max_numel`
# is not this: this is `prod(shape)`, and a symbolic dim counts as 0 here exactly as
# `LAWS/spec.bend`'s `dim_of` counts `SS{..}` as `0n`. It does not matter for the
# verdict, because `concrete` is already False whenever a dim is symbolic.
def red_i64(i: H.I64) -> U32:
  H.lo32(i)

def red_dim.of(s: O.Sint) -> U32:
  match s:
    case O.SI{i}: red_i64(i)
    case _: O.SInt.u(s)

def red_dim(+s: O.Sint) -> U32:
  red_dim.of(s)

# a CONST dim is a non-negative Python int here: `shape` entries are element counts,
# and the only negative a `SInt` can carry is a symbolic marker, which `SI` is not.

def red_numel.go(+sh: List<&2, O.Sint>, acc: U32) -> U32:
  match sh:
    case Nil{}: acc
    case s <> t: red_numel.go(t, U32.mul(acc, red_dim(s)))

def red_numel(+sh: List<&2, O.Sint>) -> U32:
  red_numel.go(sh, 1)

# THE SELECTION -- allreduce.py:13-15, verbatim with the flags as parameters.
#
#     concrete = all_int(shape)
#     use_all2all = concrete and (ALL2ALL >= 2 or (ndev > 2 and numel > thr and ALL2ALL >= 1))
#     use_ring = concrete and not use_all2all and (RING >= 2 or (ndev > 2 and numel > thr and RING >= 1))
#
# THE COMMENT ABOVE IT IS THE REASON and it is kept because the three conditions are
# three separate empirical claims: "ring allreduce doesn't provide a benefit with only
# 2 nodes or where number of elements is less than 256k (empirically) ... fallback to
# naive allreduce to save on kernel dispatch, chunking and reassembling chunks." So
# `ndev > 2` and `numel > thr` are BOTH required, `RING >= 2` and `ALL2ALL >= 2` are
# the "force it" overrides, and `>= 1` is "on, subject to the empirical test".

def red_ge2(v: U32) -> Bool:
  U32.is_ge(v, 2)

def red_ge1(v: U32) -> Bool:
  U32.is_ge(v, 1)

# `ndev > 2 and numel > thr` -- the empirical test, factored out because
# `use_all2all` and `use_ring` both spell it and a divergence between the two copies
# would be a real bug.
def red_worth.of(many: Bool, big: Bool) -> Bool:
  Bool.and(many, big)

def red_worth(ndev: U32, numel: U32, thr: U32) -> Bool:
  red_worth.of(U32.is_gt(ndev, 2), U32.is_gt(numel, thr))
def red_and(a: Bool, b: Bool) -> Bool:
  Bool.and(a, b)

def red_a2(concrete: Bool, +ndev: U32, +numel: U32, +cfg: Cfg) -> Bool:
  red_and(concrete, Bool.or(red_ge2(Cfg.all2all(cfg)),
                            Bool.and(red_worth(ndev, numel, Cfg.thr(cfg)), red_ge1(Cfg.all2all(cfg)))))
def red_ring3(concrete: Bool, a2: Bool, ok: Bool) -> Bool:
  Bool.and(Bool.and(concrete, Bool.not(a2)), ok)

def red_ring(concrete: Bool, a2: Bool, +ndev: U32, +numel: U32, +cfg: Cfg) -> Bool:
  red_ring3(concrete, a2, Bool.or(red_ge2(Cfg.ring(cfg)),
                                  Bool.and(red_worth(ndev, numel, Cfg.thr(cfg)), red_ge1(Cfg.ring(cfg)))))
# `use_ring`'s own expression READS `use_all2all` (the `and not use_all2all`), so the
# two are computed in order and `red_sel.of` takes three inputs, not two. Computing
# `use_all2all` twice instead would be a def shorter and a second place for the two
# copies of `red_a2` to drift apart.
def red_sel.put(+concrete: Bool, +a2: Bool, +ndev: U32, +numel: U32, +cfg: Cfg) -> Sel:
  Sel{concrete, a2, red_ring(concrete, a2, ndev, numel, cfg)}

def red_sel.of(+concrete: Bool, +numel: U32, +ndev: U32, +cfg: Cfg) -> Sel:
  red_sel.put(concrete, red_a2(concrete, ndev, numel, cfg), ndev, numel, cfg)

def red_sel(+sh: List<&2, O.Sint>, +ndev: U32, +cfg: Cfg) -> Sel:
  red_sel.of(red_all_int(sh), red_numel(sh), ndev, cfg)

# THE CHUNKING -- allreduce.py:36-38.
#
#     factor = next((f for f in [32, 16, 8, 4, 2] if numel % f == 0), 1)
#     base, left = divmod(numel // factor, ndev)
#     chunks = pairwise(accumulate([(base+1)*factor]*left + [base*factor]*(ndev-left), initial=0))
#
# `factor` is the GRANULARITY: chunks are kept a multiple of it so the ring's
# transfers stay aligned, and it is the LARGEST of the five that divides `numel`, with
# 1 as the always-legal answer. `left` is the remainder: `left` chunks are one unit
# bigger than the rest, which is how `numel` is split exactly.
#
# the bounds walk the sizes forwards with a running start, which is the direct
# transcription of `accumulate(..., initial=0)` and needs no reversal at all.
# `List.append(a, A, xs, ys)` is `xs ++ ys` -- ys lands at the TAIL -- so the
# accumulator is already in order. (It reads like a prepend and it is not: this file
# one-line reproducer. See bend2-constraints.md section H.)

def red_divides(numel: U32, +f: U32) -> Bool:
  Bool.and(Bool.not(U32.is_zero(f)), U32.is_zero(U32.mod(numel, f)))

# `next((f for f in [32,16,8,4,2] if numel % f == 0), 1)` -- a first-match-wins scan
# down a fixed list, with 1 as the default that survives to the end.
# `red_head` -- `List.head` answers a `Maybe` and this file needs the head of a
# `U32` list all over. 0 is the file's spelling of the IndexError on an empty tuple,
# the same spelling `schedule/memory.bend` uses.
def red_head_of(m: Maybe<&2, U32>) -> U32:
  Maybe.default(&2, U32, m, 0)

def red_head(+xs: List<&2, U32>) -> U32:
  red_head_of(List.head(&2, U32, xs))

# `next((f for f in [32, 16, 8, 4, 2] if numel % f == 0), 1)`. FIRST match wins,
# and `found` is what makes that true: the five factors are nested by divisibility,
# so once 32 divides `numel` so do 16, 8, 4 and 2, and a fold that simply overwrote
# would answer 2 for every even `numel`. `f_100` (4, not 2) and `f_96` (32) in the
# gate are the two rows that say so.
#
# Both `found` and `acc` advance per step, so the two updates are two leaf defs and
# the self-call sits in the fuel arm -- the `mem_peaks` shape. Splitting it into a
# step def that called back is a forward reference.
def red_factor.take(found: Bool, ok: Bool) -> Bool:
  Bool.and(Bool.not(found), ok)
def red_factor.pick.of(take: Bool, acc: U32, x: U32) -> U32:
  match take:
    case True{}: x
    case _: acc

def red_factor.pick(found: Bool, ok: Bool, acc: U32, x: U32) -> U32:
  red_factor.pick.of(red_factor.take(found, ok), acc, x)

def red_factor(fuel: Nat, +numel: U32, +found: Bool, acc: U32, +fs: List<&2, U32>) -> U32:
  match fuel:
    case 0n: acc
    case 1n+p: red_factor(p, numel,
                         Bool.or(found, red_divides(numel, red_head(fs))),
                         red_factor.pick(found, red_divides(numel, red_head(fs)), acc, red_head(fs)),
                         List.tail(&2, U32, fs))

def red_factor_factors() -> List<&2, U32>:
  [32, 16, 8, 4, 2]

def red_factor_of(+numel: U32) -> U32:
  red_factor(6n, numel, False{}, 1, red_factor_factors())

# `divmod(numel // factor, ndev)`
def red_chunk.of(+per: U32, +ndev: U32, factor: U32) -> Ch:
  Ch{factor, U32.div(per, ndev), U32.mod(per, ndev)}

def red_chunk(+numel: U32, +ndev: U32) -> Ch:
  red_chunk.of(U32.div(numel, red_factor_of(numel)), ndev, red_factor_of(numel))

# one chunk's size: `(base + 1) * factor` for the first `left`, `base * factor` after
def red_bump.of(early: Bool) -> U32:
  match early:
    case True{}: 1
    case _: 0

def red_bump(+k: U32, +left: U32) -> U32:
  red_bump.of(U32.is_lt(k, left))

def red_size(+k: U32, +factor: U32, +base: U32, +left: U32) -> U32:
  U32.mul(factor, U32.add(base, red_bump(k, left)))

# the sizes, in order: chunk 0 first. Walking `k` up and APPENDING keeps that order,
# because `List.append` puts the new element at the tail.
def red_sizes(fuel: Nat, +k: U32, +factor: U32, +base: U32, +left: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n: acc
    case 1n+p: red_sizes(p, U32.add(k, 1), factor, base, left, List.append(&2, U32, acc, [red_size(k, factor, base, left)]))

def red_chunk_sizes(+numel: U32, +ndev: U32) -> List<&2, U32>:
  red_sizes(U32.to_nat(ndev), 0, red_factor_of(numel), Ch.base(red_chunk(numel, ndev)), Ch.left(red_chunk(numel, ndev)), Nil{})

# the bounds. `e` starts at `numel` and walks down; each step prepends `Chk{e - w, e}`
# and sets `e` to `e - w`. Prepending while walking the reversed sizes lands chunk 0
# at the head -- see the note above `red_chunk_sizes`.
# `e` is the running end and starts at `numel`; each step prepends `Chk{e - w, e}` and
# carries `e - w` forward. Prepending while walking the REVERSED sizes lands chunk 0
# at the head with no `List.reverse` anywhere -- see the note above `red_chunk_sizes`.
# the bounds: a running START, exactly `accumulate(..., initial=0)`, paired with each
# size. `List.append` keeps the accumulator in order, so nothing is reversed.
def red_bounds(fuel: Nat, +ws: List<&2, U32>, +st: U32, acc: List<&2, Chk>) -> List<&2, Chk>:
  match fuel:
    case 0n: acc
    case 1n+p: red_bounds(p, List.tail(&2, U32, ws), U32.add(st, red_head(ws)),
                          List.append(&2, Chk, acc, [Chk{st, U32.add(st, red_head(ws))}]))

def red_bounds_of(+numel: U32, +ndev: U32) -> List<&2, Chk>:
  red_bounds(U32.to_nat(ndev), red_chunk_sizes(numel, ndev), 0, Nil{})

# THE NODE-LOCAL BRANCH -- allreduce.py:22-28. It fires before the naive/ring choice
# and is a different algorithm: instead of one ring over `ndev` devices it splits the
# devices into `ndev/hdev` boxes of `hdev` each, reduces within a box, all-reduces
# across boxes, and gathers. Its ARITHMETIC is `ndev % hdev == 0` and the box cut
# points; its graph is `mselect`/`copy_to_device`/`mstack`/`usum`/`pad`/`reshape`.

def red_hdev_fires.of(on: Bool, divides: Bool) -> Bool:
  Bool.and(on, divides)

def red_hdev_fires(+ndev: U32, +hdev: U32) -> Bool:
  red_hdev_fires.of(U32.is_gt(hdev, 0), U32.is_eq(U32.mod(ndev, hdev), 0))

# `boxes = [range(b, b+hdev) for b in range(0, ndev, hdev)]` -- the COUNT is all the
# gate needs, and the count is `ndev // hdev`.
def red_boxes(+ndev: U32, +hdev: U32) -> U32:
  U32.div(ndev, hdev)

# `cs = [(numel*k // hdev, numel*(k+1) // hdev) for k in range(hdev)]`
def red_cs.k(+k: U32, +numel: U32, +hdev: U32) -> Chk:
  Chk{U32.div(U32.mul(numel, k), hdev), U32.div(U32.mul(numel, U32.add(k, 1)), hdev)}

def red_cs(fuel: Nat, +k: U32, +numel: U32, +hdev: U32, acc: List<&2, Chk>) -> List<&2, Chk>:
  match fuel:
    case 0n: acc
    case 1n+p: red_cs(p, U32.add(k, 1), numel, hdev, List.append(&2, Chk, acc, [red_cs.k(k, numel, hdev)]))

def red_cs_of(+numel: U32, +hdev: U32) -> List<&2, Chk>:
  red_cs(U32.to_nat(hdev), 0, numel, hdev, Nil{})

# THE GATE. Every number is CPython's: `.agents/slop/notes/sched-allreduce-truth.py`
# ran `allreduce.py:13-15` and `:36-38` verbatim and printed them, and the table at
# the foot of this file says which line fixes which row.
#
# the three modes are the point, so `sel_*` is a family and not one row. a single
# boolean for "did it pick ring" would be satisfied by a `use_ring` that was always
# True and a `use_all2all` that was always False, which is exactly the shape of the
# bug this fixture exists to catch.

def red_sh(n: U32) -> O.Sint: O.SI{H.i64_of_i32(n)}
def red_sym() -> O.Sint: O.SU{0}

def red_sh1(n: U32) -> List<&2, O.Sint>: [red_sh(n)]
def red_sh2(a: U32, b: U32) -> List<&2, O.Sint>: [red_sh(a), red_sh(b)]
def red_shsym(a: U32) -> List<&2, O.Sint>: [red_sh(a), red_sym()]

# the three flag settings the rows use, all with the default 256k threshold
def red_c_on() -> Cfg: Cfg{1, 0, 256000, 0, True{}}
def red_c_off() -> Cfg: Cfg{0, 0, 256000, 0, True{}}
def red_c_a2() -> Cfg: Cfg{0, 1, 256000, 0, True{}}
def red_c_a2f() -> Cfg: Cfg{0, 2, 256000, 0, True{}}
def red_c_r2() -> Cfg: Cfg{2, 0, 256000, 0, True{}}
def red_c_both() -> Cfg: Cfg{2, 2, 256000, 0, True{}}

def red_if(b: Bool) -> U32:
  match b:
    case True{}: 1
    case _: 0

def red_eq(a: U32, b: U32) -> U32:
  red_if(U32.is_eq(a, b))

def red_at(xs: List<&2, Chk>, n: U32) -> Chk:
  Maybe.default(&2, Chk, List.get(&2, Chk, xs, U32.to_nat(n)), Chk{9999, 9999})

# `DEBUG >= 2` -- allreduce.py:16. The THRESHOLD IS 2 AND NOT 1, and that is read out
# of the source rather than assumed: `.agents/slop/debug_oracle.py` LANE B pulls
# `re.search(r"DEBUG\s*>=\s*(\d+)", linecache.getline(path, 16))` out of the file
# and prints it as `thr_ar`, which is `2`, while `thr_mem` -- the one level-1 site --
# is `1`. Getting these two the wrong way round is invisible in a single-level gate,
# because a `>= 1` port passes every `>= 2` fixture.
#
#     if DEBUG >= 2: print(f"{'ALL2ALL' if use_all2all else 'RING' if use_ring else 'NAIVE'} ALLREDUCE {ndev}x{numel} | {buf.dtype}")
#
# THE MODE NAME IS `red_mode`'s NUMBER spelled out, and the order is Python's:
# ALL2ALL is tested FIRST, so a configuration that somehow satisfied both flags would
# print ALL2ALL -- which `sel_both` above already shows cannot arise, because
# `use_ring`'s own expression carries `and not use_all2all`.
#
# `{buf.dtype}` IS `f"dtypes.{name}"`. MEASURED, live CPython: `str(dtypes.f32)` is
# `'dtypes.f32'` and so are `bf16` and `i32`; it is `DType.__repr__`, and dtype.py
# changed it from the ALIAS to the NAME ("dtypes.float" -> "dtypes.f32") -- see
# `LAWS/spec.bend`'s header on that commit. So the port reads the `nm` FIELD of `Dt`
# and prefixes it, and does not go through `dtype.bend`'s aliases at all.

def red_mode_name(m: U32) -> String:
  match m:
    case 2: "ALL2ALL"
    case 1: "RING"
    case _: "NAIVE"

def red_dtype(dt: S.Dt) -> String:
  match dt:
    case S.Dt{pri, bits, cls, nm}: String.concat(["dtypes.", nm])

def red_dbg_text.of(m: U32, ndev: U32, numel: U32, dt: String) -> String:
  String.concat([red_mode_name(m), " ALLREDUCE ", U32.show(ndev), "x", U32.show(numel),
                 " | ", dt])

def red_dbg_text(+s: Sel, ndev: U32, numel: U32, dt: S.Dt) -> String:
  red_dbg_text.of(red_mode(s), ndev, numel, red_dtype(dt))

def red_dbg_text.gate(open: Bool, t: String) -> String:
  match open:
    case True{}: t
    case _: ""

# THE SITE. `dbg` is the THREADED level and `H.debug()` is the environment read
# behind it; see helpers.bend's `debug_print` for why the gate and the text are two
# defs rather than one `if`. `sel_both` and `sel_sym_a2` already exercise `Sel`, so
# the site adds no new selection logic -- it only SPELLS the answer.
def red_dbg(dbg: U32, +s: Sel, ndev: U32, numel: U32, dt: S.Dt) -> String:
  red_dbg_text.gate(H.debug_ge(dbg, 2), red_dbg_text(s, ndev, numel, dt))
