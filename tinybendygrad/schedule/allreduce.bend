# allreduce.bend -- tinygrad/schedule/allreduce.py, the ring / all2all / naive
# allreduce lowering.
#
# WHAT THIS FILE IS, AND WHAT IT IS NOT. `allreduce.py` is 75 lines and two defs:
# `handle_allreduce` and `create_allreduce_function`. Almost all of
# `handle_allreduce` is BUILDING A GRAPH -- `mselect`, `copy_to_device`, `shrink`,
# `pad`, `mstack`, `usum`, `reshape`, `allreduce` -- and not one of those builders is
# ported (each is a `TODO(p3)` in `ops.bend`, ops.py:680 through :853). So what is
# here is the part that is ARITHMETIC AND DECISION, and that part is the whole
# algorithm: which of the three reductions runs, and with what chunk boundaries. The
# graph each one assembles is the wall, and it is named where it bites.
#
# DEPENDENCY ON A SIBLING. `schedule/__init__.py` owns the only caller of
# `handle_allreduce`, through `replace_allreduce` / `_early_allreduce` in
# `schedule/multi.py`. Nothing here imports either, and the gate fixtures are built
# standalone, so the three files in this directory meet only at the call site.
#
# ---------------------------------------------------------------------------
# THE FLAGS ARE PARAMETERS, AND THAT IS THE ONE CONVENTION IN THIS FILE.
#
# `RING`, `ALL2ALL`, `ALLREDUCE_CAST`, `ALLREDUCE_NODE_NDEVS` and
# `RING_ALLREDUCE_THRESHOLD` are `ContextVar`s (helpers.py) and Bend has no
# `Config` and no process environment. A `Flags` record would be the helpers.bend
# answer and it is P6, so here they are a `Cfg` PARAMETER of every def that reads
# one. The gate builds several `Cfg` values and the row set below is what says the
# three modes are actually distinguishable -- an all-True selection row would be
# worthless, since `NAIVE` is the answer for every small case.
# ---------------------------------------------------------------------------

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F

# ===========================================================================
# THE RECORDS. `Chk` is one `(start, end)` chunk bound and `Ch` is the chunking's
# three derived numbers, which is all `allreduce.py:36-38` computes before it starts
# building anything.
# ===========================================================================
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

# ===========================================================================
# THE MODE, as a number, because `main` prints numbers. 0 is NAIVE, 1 is RING,
# 2 is ALL2ALL -- and the ORDER IS PYTHON'S: `allreduce.py:16` prints
# `'ALL2ALL' if use_all2all else 'RING' if use_ring else 'NAIVE'`, so ALL2ALL is
# tested FIRST, and a configuration that somehow satisfied both flags would print
# ALL2ALL. `use_ring`'s own expression already excludes `use_all2all`
# (`and not use_all2all`), so the tie cannot arise -- and the gate row `sel_both`
# is what says so rather than leaving it to the reader.
# ===========================================================================
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

# ===========================================================================
# `concrete = all_int(shape)` -- allreduce.py:13. Every dim of `buf.shape` must be a
# plain int; a symbolic dim makes the whole reduction NAIVE, because the chunk
# arithmetic below is integer division and would be meaningless otherwise.
# ===========================================================================
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

# ===========================================================================
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
# ===========================================================================
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


# ===========================================================================
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
# THE BOUNDS WALK THE SIZES FORWARDS WITH A RUNNING START, which is the direct
# transcription of `accumulate(..., initial=0)` and needs no reversal at all.
# `List.append(a, A, xs, ys)` is `xs ++ ys` -- ys lands at the TAIL -- so the
# accumulator is already in order. (It reads like a prepend and it is not: this file
# was wrong about that for a while and `.agents/slop/notes/probe-list.bend` is the
# one-line reproducer. See bend2-constraints.md section H.)
# ===========================================================================
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

# ===========================================================================
# THE NODE-LOCAL BRANCH -- allreduce.py:22-28. It fires before the naive/ring choice
# and is a different algorithm: instead of one ring over `ndev` devices it splits the
# devices into `ndev/hdev` boxes of `hdev` each, reduces within a box, all-reduces
# across boxes, and gathers. Its ARITHMETIC is `ndev % hdev == 0` and the box cut
# points; its graph is `mselect`/`copy_to_device`/`mstack`/`usum`/`pad`/`reshape`.
# ===========================================================================
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
# ===========================================================================
# THE GATE. Every number is CPython's: `.agents/slop/notes/sched-allreduce-truth.py`
# ran `allreduce.py:13-15` and `:36-38` verbatim and printed them, and the table at
# the foot of this file says which line fixes which row.
#
# THE THREE MODES ARE THE POINT, so `sel_*` is a family and not one row. A single
# boolean for "did it pick ring" would be satisfied by a `use_ring` that was always
# True and a `use_all2all` that was always False, which is exactly the shape of the
# bug this fixture exists to catch.
# ===========================================================================
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

def red_row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

# --- the selection, allreduce.py:13-16 --------------------------------------
# ndev=2 is the empirical "only 2 nodes" arm and RING is ON: NAIVE. This is the row
# that says `ndev > 2` is really tested.
def sel_two() -> U32:
  red_eq(red_mode(red_sel(red_sh1(100), 2, red_c_on())), 0)

# ndev=4, 300k elements, RING on: RING. And `ndev=3` is also RING, so the test is
# `> 2` and not `>= 4`.
def sel_big() -> U32:
  red_eq(red_mode(red_sel(red_sh1(300000), 4, red_c_on())), 1)

def sel_three() -> U32:
  red_eq(red_mode(red_sel(red_sh1(300000), 3, red_c_on())), 1)

# under the threshold with RING on: NAIVE. Together with `sel_big` this is the
# `numel > 256000` half of the empirical claim.
def sel_small() -> U32:
  red_eq(red_mode(red_sel(red_sh1(100), 4, red_c_on())), 0)

# RING off and ALL2ALL 1 with a big numel: ALL2ALL. `>= 1` is "on, subject to the
# empirical test", and this is the row that says ALL2ALL 1 is enough.
def sel_a2_1() -> U32:
  red_eq(red_mode(red_sel(red_sh1(300000), 4, red_c_a2())), 2)

# RING off, ALL2ALL 0, big: NAIVE. With `sel_a2_1` this is the `>= 1` boundary.
def sel_a2_0() -> U32:
  red_eq(red_mode(red_sel(red_sh1(300000), 4, red_c_off())), 0)

# ALL2ALL 2 FORCES it, under the threshold and at ndev=2. The override ignores both
# empirical conditions, which is the whole point of `>= 2`.
def sel_a2_force() -> U32:
  red_eq(red_mode(red_sel(red_sh1(100), 2, red_c_a2f())), 2)

# RING 2 FORCES ring. And RING 2 with ALL2ALL 2 is ALL2ALL, because `use_ring`'s own
# expression carries `and not use_all2all` -- the row for that `not`.
def sel_r2_force() -> U32:
  red_eq(red_mode(red_sel(red_sh1(100), 2, red_c_r2())), 1)

def sel_both() -> U32:
  red_eq(red_mode(red_sel(red_sh1(300000), 4, red_c_both())), 2)

# a SYMBOLIC dim is not concrete, so even a forced RING falls back to NAIVE. The
# `concrete and` in both expressions, which is the row for it.
def sel_sym() -> U32:
  red_eq(red_mode(red_sel(red_shsym(300000), 4, red_c_r2())), 0)

# and `concrete` itself, so the reason above is the test and not the threshold.
def sel_sym_c() -> U32:
  red_if(Sel.concrete(red_sel(red_shsym(300000), 4, red_c_r2())))

# a symbolic dim also zeroes `numel`, because `dim_of` counts `SS{..}` as 0.
def sel_sym_n() -> U32:
  red_eq(red_numel(red_shsym(300000)), 0)

def sel_numel() -> U32:
  red_eq(red_numel(red_sh2(1000, 2)), 2000)

# THE `> 2` ROW. `sel_two` uses a SMALL numel, so it cannot tell `ndev > 2` from
# `ndev >= 2` -- both are NAIVE there because the size test fails anyway. This one
# is ndev=2 at a size where ring WOULD fire, and it is the row that says the "only
# 2 nodes" arm is a device-count test and not a side effect of the size test.
def sel_two_big() -> U32:
  red_eq(red_mode(red_sel(red_sh1(300000), 2, red_c_on())), 0)

# THE `>` ROW. Exactly `RING_ALLREDUCE_THRESHOLD` is NOT greater than it, so a large
# linear right at 256000 is still NAIVE. Measured: mutating `numel > thr` to
# `numel >= thr` moved NOTHING until this row existed.
def sel_thr() -> U32:
  red_eq(red_mode(red_sel(red_sh1(256000), 4, red_c_on())), 0)

# THE SAME ROW, one element above the threshold, which IS ring. Together with
# `sel_thr` this pins the comparison and not just its result.
def sel_thr1() -> U32:
  red_eq(red_mode(red_sel(red_sh1(256001), 4, red_c_on())), 1)

# `concrete and` IN `use_all2all`, not only in `use_ring`. `sel_sym` uses RING=2 and
# ALL2ALL=0, so it says nothing about the all2all expression -- measured: dropping
# `concrete` from `red_a2` moved nothing until this row existed. A symbolic shape
# with ALL2ALL FORCED is still NAIVE.
def sel_sym_a2() -> U32:
  red_eq(red_mode(red_sel(red_shsym(300000), 4, red_c_a2f())), 0)

# --- the chunking, allreduce.py:36-38 ---------------------------------------
# `factor` is the LARGEST of [32,16,8,4,2] dividing numel. 100 is divisible by 4 and
# not by 8, so 4 -- and the five factors are nested, so a last-match fold would say 2.
def f_100() -> U32: red_eq(red_factor_of(100), 4)
def f_128() -> U32: red_eq(red_factor_of(128), 32)
def f_96() -> U32: red_eq(red_factor_of(96), 32)
def f_odd() -> U32: red_eq(red_factor_of(101), 1)

# `base, left = divmod(numel // factor, ndev)`
def ch_100() -> U32: red_eq(Ch.base(red_chunk(100, 4)), 6)
def ch_100_l() -> U32: red_eq(Ch.left(red_chunk(100, 4)), 1)
def ch_128_l() -> U32: red_eq(Ch.left(red_chunk(128, 4)), 0)
def ch_96_l() -> U32: red_eq(Ch.left(red_chunk(96, 4)), 3)

# THE BOUNDS. numel=100 ndev=4 factor=4 base=6 left=1 -> one 28-byte chunk and three
# 24s. `k_100_n` is the COUNT and `k_100_*` the four bounds in order; a chunking that
# lost the `left` remainder would still produce four chunks, so only the bounds say it.
def k_100_n() -> U32: U32.from_nat(List.length(&2, Chk, red_bounds_of(100, 4)))
def k_100_s0() -> U32: red_eq(Chk.s(red_at(red_bounds_of(100, 4), 0)), 0)
def k_100_e0() -> U32: red_eq(Chk.e(red_at(red_bounds_of(100, 4), 0)), 28)
def k_100_s1() -> U32: red_eq(Chk.s(red_at(red_bounds_of(100, 4), 1)), 28)
def k_100_e1() -> U32: red_eq(Chk.e(red_at(red_bounds_of(100, 4), 1)), 52)
def k_100_e3() -> U32: red_eq(Chk.e(red_at(red_bounds_of(100, 4), 3)), 100)

# numel=96 ndev=4 factor=32 base=0 left=3 -> THREE 32s and a zero-length fourth.
# The degenerate bound is the row: a chunking that "fixed" it would change the ring.
def k_96_n() -> U32: U32.from_nat(List.length(&2, Chk, red_bounds_of(96, 4)))
def k_96_s3() -> U32: red_eq(Chk.s(red_at(red_bounds_of(96, 4), 3)), 96)
def k_96_e3() -> U32: red_eq(Chk.e(red_at(red_bounds_of(96, 4), 3)), 96)

# ndev=7, which does not divide numel evenly even after the factor: 4 chunks of 16
# and 3 of 12. The row for `ndev` not being a power of two.
def k_7_n() -> U32: U32.from_nat(List.length(&2, Chk, red_bounds_of(100, 7)))
def k_7_e6() -> U32: red_eq(Chk.e(red_at(red_bounds_of(100, 7), 6)), 100)

# ndev=8 and ndev=3, for the same reason on the other side.
def k_8_n() -> U32: U32.from_nat(List.length(&2, Chk, red_bounds_of(320, 8)))
def k_3_n() -> U32: U32.from_nat(List.length(&2, Chk, red_bounds_of(1000, 3)))

# --- the node-local branch, allreduce.py:22-28 ------------------------------
# `concrete and hdev > 0 and ndev % hdev == 0` -- and hdev=3 on ndev=8 is the row
# that says the modulus is tested.
def hv_4() -> U32: red_if(red_hdev_fires(8, 4))
def hv_3() -> U32: red_if(Bool.not(red_hdev_fires(8, 3)))
def hv_0() -> U32: red_if(Bool.not(red_hdev_fires(8, 0)))

# `boxes = [range(b, b+hdev) for b in range(0, ndev, hdev)]` -- the count only.
def hv_boxes4() -> U32: red_eq(red_boxes(8, 4), 2)
def hv_boxes2() -> U32: red_eq(red_boxes(8, 2), 4)

# `cs = [(numel*k // hdev, numel*(k+1) // hdev) for k in range(hdev)]`
def hv_cs_n() -> U32: U32.from_nat(List.length(&2, Chk, red_cs_of(1000, 4)))
def hv_cs_s0() -> U32: red_eq(Chk.s(red_at(red_cs_of(1000, 4), 0)), 0)
def hv_cs_e0() -> U32: red_eq(Chk.e(red_at(red_cs_of(1000, 4), 0)), 250)
def hv_cs_e3() -> U32: red_eq(Chk.e(red_at(red_cs_of(1000, 4), 3)), 1000)
def hv_cs2_n() -> U32: U32.from_nat(List.length(&2, Chk, red_cs_of(1000, 2)))

# ===========================================================================
# THE GATE DOCUMENT. `1` is True, `0` is False, and a COUNT row prints the count.
# Every value is CPython's: `.agents/slop/notes/sched-allreduce-truth.py` ran
# `allreduce.py:13-15`, `:22-28` and `:36-38` verbatim and printed them.
#
#   sel_two=1 sel_big=1 sel_three=1 sel_small=1
#     the four corners of the empirical claim at allreduce.py:11-15. ndev=2 is NAIVE,
#     ndev=3 and ndev=4 at 300k are RING, and 100 elements at ndev=4 is NAIVE.
#   sel_a2_1=1 sel_a2_0=1
#     ALL2ALL 1 is enough ("on, subject to the empirical test") and ALL2ALL 0 is not.
#   sel_a2_force=1 sel_r2_force=1
#     `>= 2` forces, under the threshold AND at ndev=2. Both overrides ignore both
#     empirical conditions, which is what the `>= 2` is for.
#   sel_both=1
#     RING 2 with ALL2ALL 2 is ALL2ALL: the `and not use_all2all` inside `use_ring`.
#   sel_sym=1 sel_sym_c=0 sel_sym_n=1
#     a SYMBOLIC dim is not concrete, so a FORCED ring still falls back to NAIVE;
#     `sel_sym_c` is the reason (0 = not concrete) and `sel_sym_n` says `numel` is 0.
#   sel_two_big=1
#     ndev=2 at 300k with RING on: still NAIVE. This is the ONLY row that tells
#     `ndev > 2` from `ndev >= 2` -- `sel_two` cannot, because its size test fails
#     anyway and both readings give NAIVE. Measured: that mutation moved nothing until
#     this row existed.
#   sel_thr=1 sel_thr1=1
#     exactly 256000 is NAIVE and 256001 is RING, so the comparison is `>` and not
#     `>=`. Same story: the mutation moved nothing until `sel_thr` existed.
#   sel_sym_a2=1
#     a symbolic shape with ALL2ALL FORCED is NAIVE. `sel_sym` uses RING=2 and
#     ALL2ALL=0, so it says nothing about `use_all2all`'s own `concrete and`.
#   sel_numel=1  `prod(shape)` over two dims.
#   f_100=1 f_128=1 f_96=1 f_odd=1
#     `factor`, the LARGEST of [32,16,8,4,2] dividing numel, else 1. 100 is the row
#     that matters: the five factors are NESTED, so a last-match fold answers 2.
#   ch_100=1 ch_100_l=1 ch_128_l=1 ch_96_l=1
#     `base, left = divmod(numel // factor, ndev)`. `ch_96_l` is the big remainder.
#   k_*_n and k_*_s/_e
#     the chunk BOUNDS, in order, for numel=100/ndev=4 (28 then three 24s), numel=96
#     (three 32s and a ZERO-LENGTH fourth -- the degenerate bound is a row) and
#     ndev=7 and ndev=8 and ndev=3, which are not powers of two.
#   hv_4=1 hv_3=1 hv_0=1
#     `hdev > 0 and ndev % hdev == 0`, with hdev=3 on ndev=8 as the divisor row.
#   hv_boxes4=1 hv_boxes2=1  `len(boxes) == ndev // hdev`.
#   hv_cs_* hv_cs2_n
#     `cs = [(numel*k // hdev, numel*(k+1) // hdev) for k in range(hdev)]`.
# ===========================================================================
#
# MUTATIONS, all re-run against this file. Reproduce with
# `.agents/slop/tools/mutate-allreduce.py`. Not one row per bug: several rows are
# load-bearing TOGETHER, and three of these mutations moved NOTHING until a fixture
# was added for them, which is the point of running the table at all.
#
# | mutation | rows that moved | how many |
# | --- | --- | --- |
# | `red_worth`'s `and` -> `or` (either the device count or... | sel_small, sel_two_big, sel_thr | 3 |
# | `red_worth`'s `numel > thr` -> `numel >= thr` (the thre... | sel_thr | 1 |
# | `red_worth`'s `ndev > 2` -> `ndev >= 2` (the two-node e... | sel_two_big | 1 |
# | `red_ge2`/`red_ge1`'s `2` -> `1` (the force overrides b... | sel_two, sel_small, sel_two_big, sel_thr | 4 |
# | `red_ring3`'s `not a2` -> `a2` (ring and all2all can bo... | sel_big, sel_three, sel_r2_force, sel_thr1 | 4 |
# | `red_a2` drops the `concrete and` (a symbolic shape sti... | sel_sym_a2 | 1 |
# | `red_all_int`'s `and` -> `or` (one int dim is enough to... | sel_sym, sel_sym_c, sel_sym_a2 | 3 |
# | `red_mode`'s ALL2ALL arm 2 -> 1 (all2all and ring print... | sel_a2_1, sel_a2_force, sel_both | 3 |
# | `red_factor`'s keep-first `Bool.not(found)` -> `True{}`... | f_100, f_128, f_96, f_odd, ch_100, ch_100_l, ch_96_l, k_100_e0, k_100_s1, k_96_s3 | 10 |
# | `red_factor_factors`'s 32 -> 8 (the granularity ladder ... | f_128, f_96, ch_96_l, k_96_s3 | 4 |
# | `red_bump`'s `is_lt(k, left)` -> `is_lt(k, left+1)` (on... | k_100_e1, k_100_e3, k_96_e3, k_7_e6 | 4 |
# | `red_bounds`'s running start `add` -> `sub` (the bounds... | k_100_s0, k_100_e0, k_100_s1, k_100_e1, k_100_e3, k_7_e6 | 6 |
# | `red_bounds`'s start 0 -> `numel` (the accumulate start... | k_100_s0, k_100_e0, k_100_s1, k_100_e1, k_100_e3, k_96_s3, k_96_e3, k_7_e6 | 8 |
# | `red_hdev_fires` drops `hdev > 0` (a zero hdev divides ... | hv_3 | 1 |
# | `red_boxes`'s `div` -> `mod` (the box count is the rema... | hv_boxes4, hv_boxes2 | 2 |
# | `red_cs.k`'s `k+1` -> `k` (every cs bound pair collapse... | hv_cs_e0, hv_cs_e3 | 2 |
#
# THE THREE THAT MOVED NOTHING, AND WHAT THEY COST. Each is now a row.
#   * `ndev > 2` -> `ndev >= 2`: `sel_two` alone cannot see it, because its size test
#     already fails. `sel_two_big` exists for this and only this.
#   * `numel > thr` -> `numel >= thr`: no fixture sat ON the threshold. `sel_thr` and
#     `sel_thr1` sit either side of it.
#   * `red_a2` dropping `concrete and`: every symbolic fixture had ALL2ALL off, so
#     the expression was unobservable. `sel_sym_a2` forces ALL2ALL on a symbolic
#     shape.
# An all-True gate says which cases you covered and nothing about the rest; three of
# the sixteen mutations here were invisible to the fixture set as first written, and
# none of them was a false alarm.
# ===========================================================================
# NOT PORTED, one line each, and the WALL each one is behind.
#
# THE THREE REDUCTION GRAPHS -- every one of `allreduce.py:18-66`. `buf.pad_to`,
# `buf.contiguous`, `buf.reshape`, `.mselect`, `.copy_to_device`, `.shrink`, `.pad`,
# `UOp.mstack`, `UOp.usum`, `.alu`, `.allreduce` and `.reshape` are ops.py:614 through
# :853 and every one is a `TODO(p3)` in `ops.bend`. What IS here is the decision that
# picks between them (`red_sel`), the chunk boundaries each one is built from
# (`red_bounds_of`), the node-local branch's boxes and cut points (`red_boxes`,
# `red_cs_of`) and the two flags that change the shape rather than the choice. The
# WALL is not one thing but thirteen: graph construction is not ported at all, so
# this file can say WHICH reduction and HOW it is cut and not WHAT it is made of.
# `schedule/multi.py`'s `copy_multi` needs the same builders for the same reasons.
# `create_allreduce_function` -- allreduce.py:68-75. `UOp.unique_num`, `ParamArg`,
# `UOp.device_range_src`, `UOp.call`, `.param_like`, `.sink`, `.after` and
# `UOp.new_buffer` (ops.py:853, a P6 device). P3/P6.
# `ALLREDUCE_CAST` -- `multi.py:116`, and `Cfg.cast` carries the flag so the caller
#   can read it; the cast it guards is `local.cast(orig).allreduce(op, ...)` and
#   `allreduce` is the wall above.
# `DEBUG >= 2` print -- allreduce.py:16. WALL: `DEBUG` is a `ContextVar`, P6, and
#   `red_mode` already answers the question it would print.
# `assert isinstance(numel, int)` -- allreduce.py:35. Asserted by construction: the
#   chunking is only reached when `concrete` is True, which is `red_sel`'s first
#   term.
# `assert not remaining` in `multi.py:114` is `multi.py`'s, not this file's.
# ===========================================================================
# WHAT THE OTHER FILES NEED FROM HERE.
#   * `schedule/multi.py`'s `replace_allreduce` / `_early_allreduce` call
#     `handle_allreduce`, and `_early_allreduce` is exactly
#     `(UPat(Ops.ALLREDUCE, src=(UPat.var("buf"),), name="red"), handle_allreduce)`.
#     The BUFFER side is the thing multi.py cannot build, so that one rule's body is
#     the wall above. Its `red.arg` is the `AAllred{rop, dev}` arg.
#   * `schedule/__init__.py` owns the allocator-shaped side of nothing here -- all of
#     `schedule/memory.bend` -- but both files are read by the SAME planner pass, so
#     the caller must run `memory_plan_rewrite` and then `red_sel`: a planned buffer
#     is not yet a plannable one until it knows which reduction its buffer will take.
#   * NOTHING ELSE IS PUBLIC. `red_head` is duplicated in `schedule/memory.bend` as
#     `mem_head`; hoisting it into `helpers.bend` is the right home and is not this
#     unit's file.
# ===========================================================================
def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- red_row("sel_two", sel_two())
    _ : Unit <- red_row("sel_big", sel_big())
    _ : Unit <- red_row("sel_three", sel_three())
    _ : Unit <- red_row("sel_small", sel_small())
    _ : Unit <- red_row("sel_a2_1", sel_a2_1())
    _ : Unit <- red_row("sel_a2_0", sel_a2_0())
    _ : Unit <- red_row("sel_a2_force", sel_a2_force())
    _ : Unit <- red_row("sel_r2_force", sel_r2_force())
    _ : Unit <- red_row("sel_both", sel_both())
    _ : Unit <- red_row("sel_sym", sel_sym())
    _ : Unit <- red_row("sel_sym_c", sel_sym_c())
    _ : Unit <- red_row("sel_sym_n", sel_sym_n())
    _ : Unit <- red_row("sel_numel", sel_numel())
    _ : Unit <- red_row("sel_two_big", sel_two_big())
    _ : Unit <- red_row("sel_thr", sel_thr())
    _ : Unit <- red_row("sel_thr1", sel_thr1())
    _ : Unit <- red_row("sel_sym_a2", sel_sym_a2())
    _ : Unit <- red_row("f_100", f_100())
    _ : Unit <- red_row("f_128", f_128())
    _ : Unit <- red_row("f_96", f_96())
    _ : Unit <- red_row("f_odd", f_odd())
    _ : Unit <- red_row("ch_100", ch_100())
    _ : Unit <- red_row("ch_100_l", ch_100_l())
    _ : Unit <- red_row("ch_128_l", ch_128_l())
    _ : Unit <- red_row("ch_96_l", ch_96_l())
    _ : Unit <- red_row("k_100_n", k_100_n())
    _ : Unit <- red_row("k_100_s0", k_100_s0())
    _ : Unit <- red_row("k_100_e0", k_100_e0())
    _ : Unit <- red_row("k_100_s1", k_100_s1())
    _ : Unit <- red_row("k_100_e1", k_100_e1())
    _ : Unit <- red_row("k_100_e3", k_100_e3())
    _ : Unit <- red_row("k_96_n", k_96_n())
    _ : Unit <- red_row("k_96_s3", k_96_s3())
    _ : Unit <- red_row("k_96_e3", k_96_e3())
    _ : Unit <- red_row("k_7_n", k_7_n())
    _ : Unit <- red_row("k_7_e6", k_7_e6())
    _ : Unit <- red_row("k_8_n", k_8_n())
    _ : Unit <- red_row("k_3_n", k_3_n())
    _ : Unit <- red_row("hv_4", hv_4())
    _ : Unit <- red_row("hv_3", hv_3())
    _ : Unit <- red_row("hv_0", hv_0())
    _ : Unit <- red_row("hv_boxes4", hv_boxes4())
    _ : Unit <- red_row("hv_boxes2", hv_boxes2())
    _ : Unit <- red_row("hv_cs_n", hv_cs_n())
    _ : Unit <- red_row("hv_cs_s0", hv_cs_s0())
    _ : Unit <- red_row("hv_cs_e0", hv_cs_e0())
    _ : Unit <- red_row("hv_cs_e3", hv_cs_e3())
    _ : Unit <- red_row("hv_cs2_n", hv_cs2_n())
    IO.print("")
    IO.print("")
