# memory.bend -- tinygrad/schedule/memory.py, the memory planner.
#
# WHAT THIS FILE IS. `memory.py` is 62 lines and one function. It takes a LINEAR
# of kernels, works out how long each internal buffer is live, packs the
# non-overlapping ones into one shared arena per (device, copy/compute) lane,
# and returns the linear with every buffer replaced by a BITCAST into that
# arena. There is no PatternMatcher here and no rule table: this is a straight
# fold over the kernels, so it is a straight fold over the kernels.
#
# DEPENDENCY ON A SIBLING. `schedule/__init__.py` is owned by another agent and
# is the only caller of `memory_plan_rewrite`. Nothing here imports it, and the
# gate fixtures are built standalone, so the two files meet only at the CALL
# SITE -- see WHAT schedule/__init__.py NEEDS at the foot of this file.
#
# ---------------------------------------------------------------------------
# THE TWO WALLS, both stated where they bite.
#
# 1. THE ALLOCATOR. `offsets` come from `TLSFAllocator` (memory.py:48,50,51),
#    which is `tinygrad/runtime/support/memory.py:23` -- a different file, not
#    ported. It is also a MUTABLE Python object: `self.blocks` is a dict of
#    linked-list tuples and `alloc` splits and coalesces in place. Bend has no
#    mutable state and no first-class functions, so a TLSF allocator could only
#    become a fold threading a `Data` state through every event -- and it would
#    be a port of a file that is not this unit's, whose offsets this file does
#    not compute. So the OFFSETS ARE A PARAMETER (`mem_offs`), which is the same
#    treatment `RING`/`ALL2ALL` get in `allreduce.bend`, and everything the
#    planner does with them -- the peak fold, the arena sizes, the lane count --
#    is ported and gated. `mem_offs` carries the allocator's answers for the
#    fixture, and the gate feeds it CPython's.
# 2. `UOp.max_numel` is `prod(to_max_shape(shape))` and `to_max_shape`
#    (ops.py:1886) is not ported. `_collect_bufs` returns BUFFERS and nothing
#    else, and a BUFFER's max_numel IS `arg.size` -- the shape is `(size,)` and
#    it is concrete by construction -- so `mem_numel` reads `ParamArg.size` and
#    is exact for every node this file can see. `mem_raw` is the honest spelling
#    of the product and is what the peak fold uses.
# 3. The return, `linear.substitute(replace_map, name="memory plan", walk=True)`
#    (memory.py:62), needs `UOp.substitute` (ops.py:532) and `UOp.new_buffer`
#    (ops.py:853, a P6 device). `mem_replace_map` builds the map and the count of
#    arenas is gated; the substitute is the wall. See the TODO block at the foot.
# ---------------------------------------------------------------------------

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F

# ===========================================================================
# THE RECORDS. Python's dicts keyed by a UOp, a lane key and a buffer, and Bend's
# `Map` is string-keyed only, so each dict is a LIST OF RECORDS with a linear
# scan. The lists are tiny -- one entry per live buffer, one per lane -- so the
# scan is not the cost the linear graph is.
#
# `Bf` is `first_appearance` and `last_appearance` FUSED. Python keeps two dicts
# over the same keys; keeping them in one record is what lets the lifetime scan
# be a single fold with one accumulator instead of two, and it is the reason a
# buffer appears at most once here where `si_bufs` may repeat it (an MSTACK of
# two MSELECTs of one buffer collects it twice).
# ===========================================================================
type Bf is Data:
  Bf{b: U32, f: U32, l: U32}

# `LaneKey = tuple[str, int]` (memory.py:18) -- the device and `1` for a copy
# buffer, `0` for a compute buffer. `cp` is a U32 because `Bool` will not sort
# and will not compare, and the event sort wants the flag.
type Lane is Data:
  Lane{dev: S.Dev, cp: U32}

# one entry of the sorted `events` list (memory.py:43). `o` is `1` for an open
# and `0` for a close, because the sort key is `(x[0], x[1])` over Python
# BOOLEANS and `False < True`: at one index the CLOSE runs FIRST. Storing `0` for
# close and `1` for open reproduces that, and `mem_ev_o_of` gives the Bool back.
#
# `(i, o)` IS NOT A TOTAL ORDER -- two buffers at one index tie -- so the order
# WITHIN a tie rests entirely on the sort being STABLE, in both languages. That
# is MEASURED here rather than assumed, because it is the one property of
# `List.sort` this file's correctness hangs on, and an unstable sort would
# silently permute the allocs and change every arena size:
#   * `List.merge.step` (base.bend:1015-1023) takes the FIRST run's head whenever
#     `le(x, y)` holds, and `le` here is a `<=`, so a tie keeps `x`. That is a
#     stable merge.
#   * MEASURED on bend 2.0.34 with `probe_sort.bend`: tied runs of 2, 4 and 6
#     came back in input order, and `[k2,k1,k2,k1,k1,k2]` came back
#     `[k1,k1,k1,k2,k2,k2]` with each class in input order.
# So no rank field is carried here, and the list is built opens-first-then-closes
# with each half already in `first_appearance` order, which is what CPython's
# stable `sorted` over the same concatenation produces. `ev_tie*` in the gate are
# the rows that would move if any of this stopped being true.
type Ev is Data:
  Ev{i: U32, o: U32, b: U32}

# the allocator's answer for one buffer, and the running peak for one lane
type Off is Data:
  Off{b: U32, o: U32}

type Peak is Data:
  Peak{ln: Lane, p: U32}

# one lane's arena size -- `arena_sizes` (memory.py:53)
type Asz is Data:
  Asz{ln: Lane, sz: U32}

# What a scan step carries forward. `tc` is the flat TOUCH LIST -- one `{b, i}` per
# (buffer, kernel) pair, in scan order -- and `bs` is the DISTINCT buffer list in
# first-insertion order, which is Python's `dict` order. `first_appearance[b]` is
# then the FIRST touch of `b` and `last_appearance[b]` its LAST, both read out of
# `tc`; nothing is written in place.
#
# THIS IS AN ENCODING CHOICE, and it is not a rewrite. Python mutates one dict
# entry twice; the in-place version of that -- rebuild the whole table on every
# touch, hit re-emitted with a new `l`, miss appended at the end -- needs a
# `List.reverse` INSIDE a fuel fold, and measured against bend 2.0.34 that reverse
# silently stops reversing once the fold is two steps deep (`.agents/slop/notes/
# probe-put.bend`: a two-entry table comes back `3,4` and a three-entry one comes
# back `4,3,5`). Reading `f` and `l` off the touch list is the same table with one
# reverse at the end of the scan instead of one per touch, and `f`/`l` are then
# pure searches -- which is also a def shorter.
type Scan is Data:
  Scan{tc: List<&2, Bf>, bs: List<&2, U32>, cp: List<&2, U32>}

def Scan.tc(s: Scan) -> List<&2, Bf>:
  match s:
    case Scan{tc, bs, cp}: tc

def Scan.bs(s: Scan) -> List<&2, U32>:
  match s:
    case Scan{tc, bs, cp}: bs

def Scan.cp(s: Scan) -> List<&2, U32>:
  match s:
    case Scan{tc, bs, cp}: cp

# ===========================================================================
# `_collect_bufs` -- memory.py:7-10. BUFFER is itself, MSELECT/MSTACK recurse
# over every src, and everything else contributes nothing.
#
# THE FUEL IS THE ONLY `match` IN THE RECURSIVE DEF, and the descent is a
# separate `step`. That is `ops.bend`'s `toposort` shape, and it is forced:
#   * a def may only call defs declared ABOVE it, so a wrapper/step pair that
#     calls each other is MUTUAL recursion and is refused;
#   * a self-call must be DECREASING with its fuel the FIRST parameter, and the
#     fuel may not feed two self-calls in one arm.
# So the worklist and the accumulator ride along as parameters and `step` is a
# pure function of them: pop the head, and either keep it (a BUFFER) or push its
# srcs back (an MSELECT/MSTACK). The fuel is `Arena.budget(ar)` -- the same bound
# `UOp.toposort` takes, one visit per edge into a node.
# ===========================================================================
def mem_collect.is_buf(op: O.Op) -> Bool:
  match op:
    case O.OpsBUFFER{}: True{}
    case _: False{}

def mem_collect.is_multi(op: O.Op) -> Bool:
  match op:
    case O.OpsMSELECT{}: True{}
    case O.OpsMSTACK{}: True{}
    case _: False{}

def mem_collect.of(b: Bool, u: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match b:
    case True{}: List.append(&2, U32, acc, [u])
    case False{}: acc

def mem_collect.push.of(multi: Bool, srcs: List<&2, U32>, t: List<&2, U32>) -> List<&2, U32>:
  match multi:
    case True{}: List.append(&2, U32, srcs, t)
    case _: t

def mem_collect.push(+ar: O.Arena, +u: U32, t: List<&2, U32>) -> List<&2, U32>:
  mem_collect.push.of(mem_collect.is_multi(O.Arena.op(ar, u)), O.Arena.srcs(ar, u), t)

def mem_collect.wl(+ar: O.Arena, todo: List<&2, U32>) -> List<&2, U32>:
  match todo:
    case Nil{}: todo
    case u <> t: mem_collect.push(ar, u, t)

def mem_collect.hit(+ar: O.Arena, todo: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match todo:
    case Nil{}: acc
    case +u <> t: mem_collect.of(mem_collect.is_buf(O.Arena.op(ar, u)), u, acc)

def mem_collect(fuel: Nat, +ar: O.Arena, +todo: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n: acc
    case 1n+p: mem_collect(p, ar, mem_collect.wl(ar, todo), mem_collect.hit(ar, todo, acc))

# the seed: `_collect_bufs(u)` with a one-element worklist
def mem_collect_of(fuel: Nat, ar: O.Arena, u: U32) -> List<&2, U32>:
  mem_collect(fuel, ar, [u], Nil{})

# ===========================================================================
# `_can_plan` -- memory.py:12-16. Two tests: not held, and no device that starts
# with DISK, CL or WEBGPU (see the note on `contiguous_view_offset`).
#
# THE DEVICE NAME TEST IS A WALL AND IT IS THE INTERESTING ONE. Python tests
# `d.startswith(("DISK", "CL", "WEBGPU"))` on a device NAME. Here a device is
# `S.Dev` -- a `U32` tag per name, interned by the runtime -- so there is no
# string to test and this file cannot ask the question. The unplannable TAGS are
# therefore a PARAMETER (`unpl`), and the caller is the device table, which is
# P6: `Device.tag` is exactly where the names live. This is not a shortcut, it is
# the only shape a name-prefix test has once the name is gone, and it is the same
# treatment the RING/ALL2ALL flags get in `allreduce.bend`.
#
# `devs = (b.device,) if isinstance(b.device, str) else b.device` -- `D1` is the
# one-name case and `Dn` the tuple case, and `fold.device` already answers in
# exactly those two shapes, so the `isinstance` test is the `match` itself.
# ===========================================================================
def mem_ok_tag(unpl: List<&2, U32>, t: U32) -> Bool:
  Bool.not(List.contains(U32, U32.is_eq, unpl, t))

def mem_ok_tags.go(+unpl: List<&2, U32>, tags: List<&2, U32>) -> Bool:
  match tags:
    case Nil{}: True{}
    case t <> r: Bool.and(mem_ok_tag(unpl, t), mem_ok_tags.go(unpl, r))

def mem_ok_tags(unpl: List<&2, U32>, tags: List<&2, U32>) -> Bool:
  mem_ok_tags.go(unpl, tags)

def mem_ok_dev.go(unpl: List<&2, U32>, m: Maybe<&2, S.Dev>) -> Bool:
  match m:
    case Some{dev}:
      match dev:
        case S.D1{tag}: mem_ok_tag(unpl, tag)
        case S.Dn{tags}: mem_ok_tags(unpl, tags)
    # a buffer with no device is not `devs` at all -- Python raises on
    # `for d in None`. Here it is simply not plannable.
    case _: False{}

def mem_ok_dev(unpl: List<&2, U32>, m: Maybe<&2, S.Dev>) -> Bool:
  mem_ok_dev.go(unpl, m)

def mem_inner(m: Maybe<&2, Maybe<&2, S.Dev>>) -> Maybe<&2, S.Dev>:
  match m:
    case Some{d}: d
    case _: None{}

def mem_dev(+fx: F.Folded, +self: U32) -> Maybe<&2, S.Dev>:
  mem_inner(F.fold.device(F.Folded.ar(fx), F.Folded.t(fx), self))

def mem_can_plan(+fx: F.Folded, +self: U32, held: List<&2, U32>, unpl: List<&2, U32>) -> Bool:
  Bool.and(Bool.not(List.contains(U32, U32.is_eq, held, self)),
           mem_ok_dev(unpl, mem_dev(fx, self)))

# ===========================================================================
# `mem_numel` / `mem_itemsize` / `mem_raw` -- `b.max_numel() * b.dtype.itemsize`.
#
# `max_numel` is `prod(to_max_shape(shape))` and `to_max_shape` (ops.py:1886) is
# not ported. It does not bite here and the reason is worth stating rather than
# hiding: `_collect_bufs` returns BUFFERS AND NOTHING ELSE, a BUFFER's shape is
# literally `(arg.size,)` and that size is concrete by construction, so
# `max_numel` IS `arg.size` for every node this file can see. `mem_numel`
# therefore reads the size, and a buffer with no size is not plannable here --
# which is also what Python does, since `prod(())` is 1 and the buffer would be a
# scalar and would not have been collected.
# ===========================================================================
def mem_size_of(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{n}: n
    case _: 0

def mem_arg.of(a: O.Arg) -> Maybe<&2, O.ParamArg>:
  match a:
    case O.AParam{+pa}: Some{pa}
    case _: None{}

def mem_arg(+fx: F.Folded, +self: U32) -> Maybe<&2, O.ParamArg>:
  mem_arg.of(O.Arena.arg(F.Folded.ar(fx), self))

def mem_numel_of(m: Maybe<&2, O.ParamArg>) -> U32:
  match m:
    case Some{+pa}: mem_size_of(O.ParamArg.size(pa))
    case _: 0

def mem_numel(+fx: F.Folded, +self: U32) -> U32:
  mem_numel_of(mem_arg(fx, self))

def mem_dt(+fx: F.Folded, +self: U32) -> S.Dt:
  Maybe.default(&2, S.Dt, F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), self), S.void())

def mem_raw(+fx: F.Folded, +self: U32) -> U32:
  U32.mul(mem_numel(fx, self), S.Dt.itemsize(mem_dt(fx, self)))

# `nbytes = {b: round_up(b.max_numel() * b.dtype.itemsize, block_size)}` (memory.py:42)
# and `block_size = 256` (memory.py:41). The raw size is `mem_raw`; the rounded
# one is what the allocator is asked for. `H.round_up_u32` is helpers.py:1084.
def mem_block_size() -> U32: 256

def mem_nbytes(+fx: F.Folded, +self: U32) -> U32:
  H.round_up_u32(mem_raw(fx, self), mem_block_size())

# ===========================================================================
# `_key` -- memory.py:37. `return (b.device, 1 if b in copy_bufs else 0)`.
# The comment above it is load-bearing and kept: "separate copy and compute
# buffers into different lanes to avoid introducing dependencies
# (copy->compute->copy)".
# ===========================================================================
def mem_key.cp.of(copy: Bool) -> U32:
  match copy:
    case True{}: 1
    case _: 0

def mem_key.cp(copy: Bool) -> U32:
  mem_key.cp.of(copy)

def mem_key_of(dev: Maybe<&2, S.Dev>, copy: Bool) -> Lane:
  match dev:
    case Some{d}: Lane{d, mem_key.cp(copy)}
    case _: Lane{S.D1{0}, mem_key.cp(copy)}
def mem_is_copy(cp: List<&2, U32>, b: U32) -> Bool:
  List.contains(U32, U32.is_eq, cp, b)


def mem_key(+fx: F.Folded, +self: U32, cp: List<&2, U32>) -> Lane:
  mem_key_of(mem_dev(fx, self), mem_is_copy(cp, self))
def mem_eq_ln.of(same: Bool, cp: Bool) -> Bool:
  match same:
    case True{}: cp
    case _: False{}
def Lane.dev(x: Lane) -> S.Dev:
  match x:
    case Lane{dev, cp}: dev
def Lane.cp(x: Lane) -> U32:
  match x:
    case Lane{dev, cp}: cp





def mem_eq_ln(+a: Lane, +b: Lane) -> Bool:
  mem_eq_ln.of(O.eq_dev(Lane.dev(a), Lane.dev(b)), U32.is_eq(Lane.cp(a), Lane.cp(b)))




# ===========================================================================
# `buf_hold` -- memory.py:38. `{b: last_appearance[b] - first_appearance[b] + 1
# for b in first_appearance if b in copy_bufs}`, so a COPY buffer stays allocated
# for one extra span past its last use.
# ===========================================================================
def mem_hold_of(copy: Bool, d: U32) -> U32:
  match copy:
    case True{}: U32.add(d, 1)
    case _: 0
def Bf.l(x: Bf) -> U32:
  match x:
    case Bf{b, f, l}: l
def Bf.f(x: Bf) -> U32:
  match x:
    case Bf{b, f, l}: f



def mem_hold(+b: Bf, copy: Bool) -> U32:
  mem_hold_of(copy, U32.sub(Bf.l(b), Bf.f(b)))
def Bf.b(x: Bf) -> U32:
  match x:
    case Bf{b, f, l}: b

# ===========================================================================
# THE LIFETIME SCAN -- memory.py:28-33.
#
#     for i, si in enumerate(linear.src):
#       si_bufs = [b for src in si.src[1:] for b in _collect_bufs(src) if _can_plan(b, held_bufs)]
#       for b in si_bufs:
#         if b not in first_appearance: first_appearance[b] = i
#         last_appearance[b] = i
#       if si.src[0].op is Ops.STORE: copy_bufs.update(si_bufs)
#
# `si.src[1:]` is the load-bearing part: a kernel SINK's src[0] is its BODY, so
# the STORE destination is never collected -- only the kernel ARGUMENTS are. That
# is why the fixture's store destinations (A2) never appear in `first_appearance`.
#
# `si_bufs` MAY REPEAT a buffer -- an MSTACK of two MSELECTs of one buffer
# collects it twice -- so `mem_bf_touch` is an UPSERT, not an append: `f` is set
# once and `l` on every visit, which is exactly what the Python does with
# `if b not in first_appearance` and the unconditional `last_appearance[b] = i`.
# ===========================================================================
# what the scan needs from the caller: the fold, the held set and the unplannable
# device tags. One record because three of them ride through every step and the
# step already has a fuel, a node index and a kernel index.
type Plan is Data:
  Plan{fx: F.Folded, held: List<&2, U32>, unpl: List<&2, U32>}

def Plan.fx(p: Plan) -> F.Folded:
  match p:
    case Plan{fx, held, unpl}: fx

def Plan.held(p: Plan) -> List<&2, U32>:
  match p:
    case Plan{fx, held, unpl}: held

def Plan.unpl(p: Plan) -> List<&2, U32>:
  match p:
    case Plan{fx, held, unpl}: unpl

def mem_is_store(op: O.Op) -> Bool:
  match op:
    case O.OpsSTORE{}: True{}
    case _: False{}

# `bf_find(b)` -- `b not in first_appearance`.
#
# `Maybe.bind` IS the search. A `match` that asks "found or keep looking" and then
# recurses on the miss arm is two mutually recursive defs, which Bend refuses;
# `Maybe.bind` short-circuits on the hit and the closure supplies the miss arm,
# so the whole search is the ONE def `mem_bf_find.go` -- fold.bend's
# `bcast.pair.of` shape, and the reason that def reads the way it does.
#
# `mem_some` is `Maybe.bind`'s ELEMENT, hoisted because all three keyed lookups
# below want exactly it and there is nothing to close over in it.
def mem_some(a, -A: Kind(a), ok: Bool, x: A) -> Maybe<a, A>:
  match ok:
    case True{}: Some{x}
    case _: None{}

def mem_bf_find.go(bs: List<&2, Bf>, +b: U32) -> Maybe<&2, Bf>:
  match bs:
    case Nil{}: None{}
    case +e <> t: Maybe.bind(&2, Bf, Bf, mem_some(&2, Bf, U32.is_eq(Bf.b(e), b), e), _ => mem_bf_find.go(t, b))

def mem_bf_find(+bs: List<&2, Bf>, b: U32) -> Maybe<&2, Bf>:
  mem_bf_find.go(bs, b)

# `mem_head` -- `List.head` answers a `Maybe`, and 0 is this file's spelling of
# both Python's `None` UOp and the IndexError on an empty tuple (ops.bend says so
# at its own `Arena.src`). Every fold runs a fixed fuel and reaches `Nil{}` at the
# end, so the default is only ever read on a step that would have done nothing.
def mem_head_of(m: Maybe<&2, U32>) -> U32:
  Maybe.default(&2, U32, m, 0)

def mem_head(+xs: List<&2, U32>) -> U32:
  mem_head_of(List.head(&2, U32, xs))

# THE DISTINCT LIST. `if b not in first_appearance` is an append-IF-ABSENT, which
# is a pure fold -- no write, no rebuild -- and it puts each buffer in the table
# once, at its FIRST kernel, which is exactly Python's dict insertion order.
def mem_cp_one.of(seen: Bool, cp: List<&2, U32>, b: U32) -> List<&2, U32>:
  match seen:
    case True{}: cp
    case _: List.append(&2, U32, cp, [b])

def mem_cp_one(+cp: List<&2, U32>, +b: U32) -> List<&2, U32>:
  mem_cp_one.of(List.contains(U32, U32.is_eq, cp, b), cp, b)

def mem_bs_add(b: U32, bs: List<&2, U32>) -> List<&2, U32>:
  mem_cp_one(bs, b)

# THE TOUCH. `first_appearance[b] = i` and `last_appearance[b] = i` together are
# "record that `b` is live at kernel `i`", and every question about `f` and `l` is
# then a read of this list -- see `mem_first_i` and `mem_last_i`.
def mem_tc_add(+i: U32, b: U32, tc: List<&2, Bf>) -> List<&2, Bf>:
  List.append(&2, Bf, tc, [Bf{b, i, i}])

# `copy_bufs.update(si_bufs)` -- a SET, so a repeat leaves it alone.
#
# THE FUEL MATCH IS THE ONLY `match`, and the self-call is IN ITS ARM, with the
# head and the tail read by `mem_head`/`List.tail` -- `mem_collect`'s shape. A
# step def that recursed would have to live BELOW this one to be callable and
# would then be a forward reference, which is why the step lives in the arm.


def mem_cp_add(fuel: Nat, +bs: List<&2, U32>, +cp: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n: cp
    case 1n+p: mem_cp_add(p, List.tail(&2, U32, bs), mem_cp_one(cp, mem_head(bs)))

def mem_cp_add.of(cp: List<&2, U32>, +bs: List<&2, U32>) -> List<&2, U32>:
  mem_cp_add((List.length(&2, U32, bs)), bs, cp)

# `if _can_plan(b, held_bufs)` -- the filter the list comprehension applies.
def mem_kept.one(ok: Bool, b: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match ok:
    case True{}: List.append(&2, U32, acc, [b])
    case _: acc

def mem_kept(fuel: Nat, +pl: Plan, +bs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n: acc
    case 1n+p: mem_kept(p, pl, List.tail(&2, U32, bs),
                        mem_kept.one(mem_can_plan(Plan.fx(pl), mem_head(bs), Plan.held(pl), Plan.unpl(pl)),
                                     mem_head(bs), acc))

def mem_kept.of(+pl: Plan, +bs: List<&2, U32>) -> List<&2, U32>:
  mem_kept((List.length(&2, U32, bs)), pl, bs, Nil{})

def Plan.ar(p: Plan) -> O.Arena:
  F.Folded.ar(Plan.fx(p))

# `si_bufs` -- `_collect_bufs` over `si.src[1:]`, then the `_can_plan` filter.
# `mem_args.one` is a leaf: it only calls `mem_kept` and `mem_collect`, both of
# which return, which is what lets the recursion stay in `mem_args`'s own arm.
def mem_args.one(+pl: Plan, rest: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match rest:
    case Nil{}: acc
    case s <> _: List.append(&2, U32, acc, mem_kept.of(pl, mem_collect_of(O.Arena.budget(Plan.ar(pl)), Plan.ar(pl), s)))

def mem_args(fuel: Nat, +pl: Plan, +rest: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n: acc
    case 1n+p: mem_args(p, pl, List.tail(&2, U32, rest), mem_args.one(pl, rest, acc))

def mem_args.of(+pl: Plan, si: U32) -> List<&2, U32>:
  mem_args(O.Arena.budget(Plan.ar(pl)), pl, O.Arena.src_from(Plan.ar(pl), si, 1), Nil{})

# ===========================================================================# THE KERNEL INDEX. It rides as a `U32` counter beside the `Nat` fuel rather than
# BEING the fuel: a `U32` cannot be matched with `0n`, and the index is data the
# lifetime upsert needs, not a bound.
def mem_i_next(i: U32) -> U32:
  U32.add(i, 1)

# ===========================================================================
# THE KERNEL SCAN. One kernel per step, and the step is the whole loop body of
# memory.py:28-33: collect this kernel's plannable buffers, upsert their
# lifetimes at index `i`, and if the kernel BODY is a STORE then every one of
# them is a copy buffer.
#
# `si.src[1:]` is the load-bearing slice: a kernel SINK's src[0] is its BODY, so
# the STORE destination is never collected -- only the kernel ARGUMENTS are. That
# is why the fixture's store destinations never reach `first_appearance`.
# ===========================================================================
# one touch per buffer in this kernel's arg list: record it, and add the buffer to
# the distinct list the first time it is seen.
# the touch list is PREPENDED, so it is built newest-first; `mem_scan_done` reverses
# it once. One reverse at the top level, where it is measurable (see `Scan`).
def mem_touch.one(+i: U32, +b: U32, +s: Scan) -> Scan:
  Scan{mem_tc_add(i, b, Scan.tc(s)), mem_bs_add(b, Scan.bs(s)), Scan.cp(s)}

def mem_touch(fuel: Nat, +rest: List<&2, U32>, +s: Scan, +i: U32) -> Scan:
  match fuel:
    case 0n: s
    case 1n+p: mem_touch(p, List.tail(&2, U32, rest), mem_touch.one(i, mem_head(rest), s), i)

def mem_touch.of(fuel: Nat, rest: List<&2, U32>, i: U32, s: Scan) -> Scan:
  mem_touch(fuel, rest, s, i)

# ...and they join `copy_bufs` iff `si.src[0].op is Ops.STORE`
def mem_kern_cp3(store: Bool, bufs: List<&2, U32>, cp: List<&2, U32>) -> List<&2, U32>:
  match store:
    case True{}: mem_cp_add.of(cp, bufs)
    case _: cp

def mem_kern_cp(+ar: O.Arena, si: U32, bufs: List<&2, U32>, cp: List<&2, U32>) -> List<&2, U32>:
  mem_kern_cp3(mem_is_store(O.Arena.op(ar, O.Arena.src0(ar, si))), bufs, cp)

def mem_scan_cp2(+s: Scan, cp: List<&2, U32>) -> Scan:
  Scan{Scan.tc(s), Scan.bs(s), cp}

# the touch loop returns a `Scan` whose `cp` is not this kernel's business, so the
# copy half is applied after it rather than inside it
def mem_kern_cp2(+ar: O.Arena, si: U32, bufs: List<&2, U32>, +s: Scan) -> Scan:
  mem_scan_cp2(s, mem_kern_cp(ar, si, bufs, Scan.cp(s)))

# one kernel: every `si_bufs` entry is touched at index `i`...
def mem_kern(+ar: O.Arena, +pl: Plan, +i: U32, si: U32, +bufs: List<&2, U32>, s: Scan) -> Scan:
  mem_kern_cp2(ar, si, bufs, mem_touch.of(List.length(&2, U32, bufs), bufs, i, s))

# no `List.reverse` here -- see `mem_first_i`, which says why the touch list is
# read newest-first instead.
def mem_scan_done(+s: Scan) -> Scan:
  s

# the fold PREPENDS, so the touch list is built newest-first and reversed ONCE at
# the end -- one reverse, at the top level, where it is measurable (see `Scan`).
def mem_scan(fuel: Nat, +i: U32, +ar: O.Arena, +pl: Plan, +rest: List<&2, U32>, +s: Scan) -> Scan:
  match fuel:
    case 0n: mem_scan_done(s)
    case 1n+p: mem_scan(p, mem_i_next(i), ar, pl, List.tail(&2, U32, rest),
                        mem_kern(ar, pl, i, mem_head(rest), mem_args.of(pl, mem_head(rest)), s))

# `memory_plan_rewrite`'s first loop, from an empty table. `if not first_appearance:
# return linear` (memory.py:34) is checked by the CALLER on the returned table, and
# that is the honest place for it: the early return is about whether to go on to
# the allocator at all, not about the scan.
def mem_scan.of(+ar: O.Arena, +pl: Plan, +linear: U32) -> Scan:
  mem_scan((List.length(&2, U32, O.Arena.srcs(ar, linear))), 0, ar, pl,
           O.Arena.srcs(ar, linear), Scan{Nil{}, Nil{}, Nil{}})

# ===========================================================================
# THE EVENTS -- memory.py:43-44.
#
#     events = sorted([(first_appearance[b], True, b) for b in first_appearance] +
#                     [(last_appearance[b] + 1 + buf_hold.get(b, 0), False, b) for b in first_appearance],
#                     key=lambda x: (x[0], x[1]))
#
# THE SORT KEY IS `(index, is_open)` OVER PYTHON BOOLEANS and `False < True`, so AT
# ONE INDEX EVERY CLOSE RUNS BEFORE EVERY OPEN. That is load-bearing: a copy
# buffer's free must be able to precede the next buffer's alloc at the same index,
# and a port that sorted opens first would reuse memory it just handed back and
# would change every arena size. `Ev.o` is `1` for an open and `0` for a close
# precisely so this port's `U32` order IS Python's `bool` order -- the two agree
# only because `False` is mapped to the SMALLER number.
#
# The list is built opens-first-then-closes and `List.sort` is stable, so the order
# WITHIN one index matches CPython's. The gate pins that with a three-way tie.
def mem_ev_o_of(open: Bool) -> U32:
  match open:
    case True{}: 1
    case _: 0

def Ev.i(e: Ev) -> U32:
  match e:
    case Ev{i, o, b}: i

def Ev.o(e: Ev) -> U32:
  match e:
    case Ev{i, o, b}: o

def Ev.b(e: Ev) -> U32:
  match e:
    case Ev{i, o, b}: b

# `le` HAS TO BE A REAL `<=` ON THE WHOLE KEY. An earlier version of this file
# returned `False` for every differing index -- "only ties are comparable" -- and
# `List.sort` dutifully produced the events in REVERSE key order, because a
# comparator that says False in BOTH directions makes every merge take the second
# run's head. `p_ev*` is the row set that caught it: the COUNT was right and ten
# order rows moved together.
def mem_ev_cmp(same: Bool, ai: U32, ao: U32, bi: U32, bo: U32) -> Bool:
  match same:
    case True{}: U32.is_le(ao, bo)
    case _: U32.is_le(ai, bi)

def mem_ev_le(a: Ev, b: Ev) -> Bool:
  match a b:
    case Ev{+ai, ao, ab} Ev{+bi, bo, bb}: mem_ev_cmp(U32.is_eq(ai, bi), ai, ao, bi, bo)

def mem_head_bf(xs: List<&2, Bf>) -> Bf:
  Maybe.default(&2, Bf, List.head(&2, Bf, xs), Bf{0, 0, 0})

# `first_appearance[b]` and `last_appearance[b]`, both as PLAIN FOLDS over the
# touch list. Two facts about that list make both one-liners and kill the need for
# anything cleverer:
#
#   * it is built by PREPENDING, so it is ordered NEWEST-FIRST. `f` is therefore
#     the LAST match and `l` the FIRST -- the two folds differ only in whether
#     they overwrite.
#   * it stays that way. A `List.reverse` at the end of the scan LOOKED right and
#     was not: on bend 2.0.34 `List.reverse` reverses a list built directly
#     (`.agents/slop/notes/probe-list2.bend`) and does NOT reverse one threaded
#     through a fuel fold's accumulator (`probe-put.bend`), where a three-entry
#     table comes back `4,3,5` instead of `3,4,5`. Rather than depend on which,
#     this file reads the list in the order the fold produced. REPORTED, not
#     worked around silently -- see the notes file.
#
# NEITHER fold uses `Maybe.bind`. A keyed search written as
# `Maybe.bind(.., some_if(hit, e), _ => recurse)` measured as ALWAYS `None` on this
# compiler, which is why every `f` came back 0; a fold has no such failure mode and
# is one def shorter.
def mem_first_i.seen(seen: Bool, v: U32, acc: U32) -> U32:
  match seen:
    case True{}: acc
    case _: v

def mem_first_i.of(hit: Bool, seen: Bool, v: U32, acc: U32) -> U32:
  match hit:
    case True{}: mem_first_i.seen(seen, v, acc)
    case _: acc

def mem_first_i(fuel: Nat, +b: U32, +tc: List<&2, Bf>, acc: U32, +seen: Bool) -> U32:
  match fuel:
    case 0n: acc
    case 1n+p: mem_first_i(p, b, List.tail(&2, Bf, tc),
                           mem_first_i.of(U32.is_eq(Bf.b(mem_head_bf(tc)), b), seen, Bf.l(mem_head_bf(tc)), acc),
                           Bool.or(seen, U32.is_eq(Bf.b(mem_head_bf(tc)), b)))

def mem_first_i.of2(+b: U32, +tc: List<&2, Bf>) -> U32:
  mem_first_i(List.length(&2, Bf, tc), b, tc, 0, False{})

# `l` overwrites on every match, which over a newest-first list leaves the EARLIEST
# touch -- exactly what `last_appearance[b] = i` leaves behind.
def mem_last_one(hit: Bool, v: U32, acc: U32) -> U32:
  match hit:
    case True{}: v
    case _: acc

def mem_last_i(fuel: Nat, +b: U32, +tc: List<&2, Bf>, acc: U32) -> U32:
  match fuel:
    case 0n: acc
    case 1n+p: mem_last_i(p, b, List.tail(&2, Bf, tc),
                          mem_last_one(U32.is_eq(Bf.b(mem_head_bf(tc)), b), Bf.l(mem_head_bf(tc)), acc))

def mem_last_i.of2(+b: U32, +tc: List<&2, Bf>) -> U32:
  mem_last_i(List.length(&2, Bf, tc), b, tc, 0)

# `buf_hold = last_appearance[b] - first_appearance[b] + 1` for a COPY buffer only
def mem_hold.of(copy: Bool, d: U32) -> U32:
  match copy:
    case True{}: U32.add(d, 1)
    case _: 0

def mem_hold2(+b: U32, +tc: List<&2, Bf>, cp: List<&2, U32>) -> U32:
  mem_hold.of(mem_is_copy(cp, b), U32.sub(mem_last_i.of2(b, tc), mem_first_i.of2(b, tc)))

# the close index: `last_appearance[b] + 1 + buf_hold.get(b, 0)`
def mem_ev_close(+b: U32, +tc: List<&2, Bf>, cp: List<&2, U32>) -> Ev:
  Ev{U32.add(U32.add(mem_last_i.of2(b, tc), 1), mem_hold2(b, tc, cp)), 0, b}

def mem_ev_open(+b: U32, +tc: List<&2, Bf>) -> Ev:
  Ev{mem_first_i.of2(b, tc), 1, b}

def mem_ev_opens(fuel: Nat, +rest: List<&2, U32>, +tc: List<&2, Bf>, acc: List<&2, Ev>) -> List<&2, Ev>:
  match fuel:
    case 0n: acc
    case 1n+p: mem_ev_opens(p, List.tail(&2, U32, rest), tc,
                            List.append(&2, Ev, acc, [mem_ev_open(mem_head(rest), tc)]))

def mem_ev_closes(fuel: Nat, +rest: List<&2, U32>, +tc: List<&2, Bf>, +cp: List<&2, U32>, acc: List<&2, Ev>) -> List<&2, Ev>:
  match fuel:
    case 0n: acc
    case 1n+p: mem_ev_closes(p, List.tail(&2, U32, rest), tc, cp,
                             List.append(&2, Ev, acc, [mem_ev_close(mem_head(rest), tc, cp)]))

# The opens run over the DISTINCT list, not the touch list: Python iterates
# `first_appearance`, which has one entry per buffer, so a buffer read by four
# kernels contributes ONE open and not four. Iterating the touch list here would
# give four opens and eight events for a five-buffer linear.
def mem_ev_open2(+bs: List<&2, U32>, +tc: List<&2, Bf>) -> List<&2, Ev>:
  mem_ev_opens(List.length(&2, U32, bs), bs, tc, Nil{})

def mem_ev_close2(+bs: List<&2, U32>, +tc: List<&2, Bf>, +cp: List<&2, U32>, +opens: List<&2, Ev>) -> List<&2, Ev>:
  mem_ev_closes(List.length(&2, U32, bs), bs, tc, cp, opens)

def mem_events(+bs: List<&2, U32>, +tc: List<&2, Bf>, cp: List<&2, U32>) -> List<&2, Ev>:
  List.sort(Ev, mem_ev_le, mem_ev_close2(bs, tc, cp, mem_ev_open2(bs, tc)))

# `total_memory = sum(nbytes.values()) * 2` (memory.py:45) -- the size handed to
# the allocator, which is why a lane can always hold the sum of its buffers.
def mem_sum_nb(fuel: Nat, +rest: List<&2, U32>, +fx: F.Folded, acc: U32) -> U32:
  match fuel:
    case 0n: acc
    case 1n+p: mem_sum_nb(p, List.tail(&2, U32, rest), fx, U32.add(acc, mem_nbytes(fx, mem_head(rest))))

def mem_total_memory(+fx: F.Folded, +bs: List<&2, U32>) -> U32:
  U32.mul(mem_sum_nb((List.length(&2, U32, bs) : Nat), bs, fx, 0), 2)

# ===========================================================================
# THE ALLOCATOR SEAM. `offsets`, `peaks` and `arena_sizes` are ONE loop over the
# events with a `TLSFAllocator` per lane (memory.py:48-53), and that allocator is
# `tinygrad/runtime/support/memory.py:23` -- a MUTABLE Python object, a dict of
# linked-list tuples whose `alloc` splits and `free` coalesces in place. Bend has
# no mutable state and no first-class functions, so it could only be a fold
# threading a `Data` state, and it is a port of a file that is not this unit's.
#
# So the split is drawn where the wall is: `mem_offs` carries the allocator's
# ANSWERS, and everything the planner derives from them is here and gated -- the
# lane of every event, the high-water mark, the block rounding, the lane COUNT.
# `mem_total_memory` above is the other half of the seam: the budget this file
# asks the allocator for. The gate feeds it CPython's own `TLSFAllocator`.
# ===========================================================================
def Off.b(d: Off) -> U32:
  match d:
    case Off{b, o}: b

def Off.o(d: Off) -> U32:
  match d:
    case Off{b, o}: o

def Peak.ln(x: Peak) -> Lane:
  match x:
    case Peak{ln, p}: ln

def Peak.p(x: Peak) -> U32:
  match x:
    case Peak{ln, p}: p

def Asz.sz(x: Asz) -> U32:
  match x:
    case Asz{ln, sz}: sz

# `offsets[buf]` (memory.py:50-51). A miss is 0, which is the offset such a buffer
# would have anyway: every event's buffer has an entry by the time it is read.
# A keyed lookup as a FOLD, for the same reason `mem_first_i` is one: the
# `Maybe.bind` spelling measured as always-`None` on this compiler, so `offsets[buf]`
# read 0 for every buffer and every high-water mark came back as the raw size.
# The fold keeps the LAST match, which is what a dict lookup is.
def mem_off_head(offs: List<&2, Off>) -> Off:
  Maybe.default(&2, Off, List.head(&2, Off, offs), Off{0, 0})

def mem_off_step(hit: Bool, d: Off, acc: U32) -> U32:
  match hit:
    case True{}: Off.o(d)
    case _: acc

def mem_off.go(fuel: Nat, +b: U32, +offs: List<&2, Off>, acc: U32) -> U32:
  match fuel:
    case 0n: acc
    case 1n+p: mem_off.go(p, b, List.tail(&2, Off, offs),
                          mem_off_step(U32.is_eq(Off.b(mem_off_head(offs)), b), mem_off_head(offs), acc))

def mem_off(+offs: List<&2, Off>, b: U32) -> U32:
  mem_off.go(List.length(&2, Off, offs), b, offs, 0)

# `peaks[_key(buf)]` (memory.py:48-52). Python's `defaultdict` CREATES the key on
# the first event and every later event overwrites it with a running max. That is
# split here into two pure folds, because the keyed-upsert version needed the
# `Maybe.bind` search that measures as always-`None` (see `mem_first_i`):
#
#   * the LANES are the distinct `_key(buf)` values, appended the first time each
#     is seen -- which is the dict's key order, and it is the order `arena_sizes`
#     iterates;
#   * a lane's PEAK is then a fold over the events that keeps the max of
#     `offsets[buf] + max_numel * itemsize` for that lane.
#
# Same table, same order, no in-place write.
def mem_lane_eq(+a: Lane, +b: Lane) -> Bool:
  mem_eq_ln(a, b)

# membership, as a PLAIN self-recursive fold. The keyed-search spelling with
# `Maybe.bind` measured as always-`False` on this compiler (see `mem_first_i`), and
# the point of this fold is that its answer is the answer.
def mem_lane_head(ls: List<&2, Lane>) -> Lane:
  Maybe.default(&2, Lane, List.head(&2, Lane, ls), Lane{S.D1{999}, 9})

def mem_lane_in(fuel: Nat, +ls: List<&2, Lane>, +ln: Lane, found: Bool) -> Bool:
  match fuel:
    case 0n: found
    case 1n+p: mem_lane_in(p, List.tail(&2, Lane, ls), ln, Bool.or(found, mem_lane_eq(mem_lane_head(ls), ln)))

def mem_lane_in.of(+ls: List<&2, Lane>, +ln: Lane) -> Bool:
  mem_lane_in(List.length(&2, Lane, ls), ls, ln, False{})
def mem_lane_add.of(seen: Bool, ls: List<&2, Lane>, ln: Lane) -> List<&2, Lane>:
  match seen:
    case True{}: ls
    case _: List.append(&2, Lane, ls, [ln])


def mem_lane_add(+ln: Lane, +ls: List<&2, Lane>) -> List<&2, Lane>:
  mem_lane_add.of(mem_lane_in.of(ls, ln), ls, ln)


# THE HIGH-WATER MARK ONE EVENT TOUCHES: `offsets[buf] + buf.max_numel() *
# buf.dtype.itemsize`. Both of a buffer's events carry the same value, which is
# why Python can compute it on the open and on the close alike.
def mem_top(+fx: F.Folded, +offs: List<&2, Off>, +e: Ev) -> U32:
  U32.add(mem_off(offs, Ev.b(e)), mem_raw(fx, Ev.b(e)))

def mem_ev_lane(+pl: Plan, cp: List<&2, U32>, +e: Ev) -> Lane:
  mem_key(Plan.fx(pl), Ev.b(e), cp)

# `mem_peaks` used to be ONE fold doing the upsert. It is now the two folds above
# plus `mem_peak`, and the fuel lives in `mem_lanes` and `mem_peak` alone.
def mem_ev_head(evs: List<&2, Ev>) -> Ev:
  Maybe.default(&2, Ev, List.head(&2, Ev, evs), Ev{99, 9, 99})

def mem_lane_ln(fuel: Nat, +rest: List<&2, Ev>, +pl: Plan, +cp: List<&2, U32>, +ls: List<&2, Lane>) -> List<&2, Lane>:
  match fuel:
    case 0n: ls
    case 1n+p: mem_lane_ln(p, List.tail(&2, Ev, rest), pl, cp,
                          mem_lane_add(mem_ev_lane(pl, cp, mem_ev_head(rest)), ls))


# The lane order comes from walking the EVENTS, which is the same order
# `peaks[_key(buf)]` gets from a `defaultdict` fed one key per event.
def mem_lanes(+pl: Plan, cp: List<&2, U32>, +evs: List<&2, Ev>) -> List<&2, Lane>:
  mem_lane_ln(List.length(&2, Ev, evs), evs, pl, cp, Nil{})

# one lane's peak: the max `mem_top` over the events that are on it
def mem_peak_one(hit: Bool, v: U32, acc: U32) -> U32:
  match hit:
    case True{}: U32.max(acc, v)
    case _: acc

def mem_peak_go(fuel: Nat, +ln: Lane, +pl: Plan, +cp: List<&2, U32>, +offs: List<&2, Off>, +rest: List<&2, Ev>, acc: U32) -> U32:
  match fuel:
    case 0n: acc
    case 1n+p: mem_peak_go(p, ln, pl, cp, offs, List.tail(&2, Ev, rest),
                           mem_peak_one(mem_lane_eq(mem_ev_lane(pl, cp, mem_ev_head(rest)), ln),
                                        mem_top(Plan.fx(pl), offs, mem_ev_head(rest)), acc))
def mem_peak(+pl: Plan, +cp: List<&2, U32>, +offs: List<&2, Off>, +evs: List<&2, Ev>, +ln: Lane) -> Peak:
  Peak{ln, mem_peak_go(List.length(&2, Ev, evs), ln, pl, cp, offs, evs, 0)}


def mem_peak_list(fuel: Nat, +ls: List<&2, Lane>, +pl: Plan, +cp: List<&2, U32>, +offs: List<&2, Off>, +evs: List<&2, Ev>, acc: List<&2, Peak>) -> List<&2, Peak>:
  match fuel:
    case 0n: acc
    case 1n+p: mem_peak_list(p, List.tail(&2, Lane, ls), pl, cp, offs, evs,
                             List.append(&2, Peak, acc, [mem_peak(pl, cp, offs, evs, mem_lane_head(ls))]))

def mem_peaks.of(+ls: List<&2, Lane>, +pl: Plan, +cp: List<&2, U32>, +offs: List<&2, Off>, +evs: List<&2, Ev>) -> List<&2, Peak>:
  mem_peak_list(List.length(&2, Lane, ls), ls, pl, cp, offs, evs, Nil{})

def mem_peaks(+pl: Plan, +cp: List<&2, U32>, +offs: List<&2, Off>, +evs: List<&2, Ev>) -> List<&2, Peak>:
  mem_peaks.of(mem_lanes(pl, cp, evs), pl, cp, offs, evs)

# ===========================================================================
# `arena_sizes` (memory.py:53) and `arenas` (memory.py:56): ONE ARENA PER LANE, so
# the length of this list is the second number of memory.py:60's row and the first
# is `len(first_appearance)` -- the naive plan, one buffer to itself.
# ===========================================================================
def mem_ps_head(ps: List<&2, Peak>) -> Peak:
  Maybe.default(&2, Peak, List.head(&2, Peak, ps), Peak{Lane{S.D1{0}, 0}, 0})

def mem_ps_tail(ps: List<&2, Peak>) -> List<&2, Peak>:
  List.tail(&2, Peak, ps)

def mem_asz_one(+p: Peak, acc: List<&2, Asz>) -> List<&2, Asz>:
  List.append(&2, Asz, acc, [Asz{Peak.ln(p), H.round_up_u32(Peak.p(p), mem_block_size())}])

def mem_asz(fuel: Nat, +ps: List<&2, Peak>, acc: List<&2, Asz>) -> List<&2, Asz>:
  match fuel:
    case 0n: acc
    case 1n+p: mem_asz(p, mem_ps_tail(ps), mem_asz_one(mem_ps_head(ps), acc))

def mem_arenas(+ps: List<&2, Peak>) -> List<&2, Asz>:
  mem_asz((List.length(&2, Peak, ps) : Nat), ps, Nil{})

# ===========================================================================
# WHAT `memory_plan_rewrite` COMPUTES. `linear.substitute(replace_map, ...)`
# (memory.py:62) is the WALL -- it needs `UOp.substitute` (ops.py:532) and
# `UOp.new_buffer` (ops.py:853, a P6 device call) -- so what comes back is the
# WHOLE plan a caller needs to carry it out: the lifetimes, the sorted event
# stream and the budget handed to the allocator, and one arena size per lane.
# `bs` empty IS memory.py:34's `if not first_appearance: return linear`.
# ===========================================================================
type Planned is Data:
  Planned{tc: List<&2, Bf>, bs: List<&2, U32>, evs: List<&2, Ev>, tot: U32, azs: List<&2, Asz>}

def memory_plan_rewrite(+pl: Plan, +linear: U32, +offs: List<&2, Off>) -> Planned:
  +s = mem_scan.of(Plan.ar(pl), pl, linear)
  +evs = mem_events(Scan.bs(s), Scan.tc(s), Scan.cp(s))
  Planned{Scan.tc(s), Scan.bs(s), evs, mem_total_memory(Plan.fx(pl), Scan.bs(s)),
          mem_arenas(mem_peaks(pl, Scan.cp(s), offs, evs))}

# ===========================================================================
# THE GATE. Two fixtures, and every number below is CPython's: it is what
# sched-mem-truth.py printed for the SAME graph, and the fixture is rebuilt here
# node for node from that output.
#
# FIXTURE 1, `walk`: the collect/can_plan graph. 0 bottom, 1 CONST(1), 2 BUFFER
# `A`(int32, 16, CPU), 3 MSELECT(A, [0]), 4 MSTACK(3, 3), 5 CONST(1), 6 STORE.
# CPython on the identical graph: `_collect_bufs(A)` = [A],
# `_collect_bufs(A.mselect(0))` = [A], `_collect_bufs(MSTACK(MSEL,MSEL))` = [A,A],
# `_collect_bufs(STORE)` = [], `_collect_bufs(CONST)` = []; `_can_plan(A, set())`
# True, `_can_plan(A, {A})` False, DISK False, `("CPU","METAL")` True and
# `("CPU","CL:1")` False.
#
# FIXTURE 2, `plan`: memory.py's own example. A kernel SINK's src[0] is its BODY
# and src[1:] its ARGS, so only the args are collected.
#   0 bottom
#   1 CONST(1)        the BUFFER range stand-in
#   2 A2 BUFFER 1024  k0 and k1 STORE DEST -- never collected
#   3 B2 BUFFER 2048  k0 arg
#   4 C2 BUFFER  512  k1 arg
#   5 D2 BUFFER  256  k2 and k3 arg
#   6 E2 BUFFER  128  k2 arg
#   7 F2 BUFFER   64  k3 arg
#   8 DK BUFFER 4096 on DISK, tag 1 -- never planned
#   9 k0  SINK(STORE(2, 3), 3)
#  10 k1  SINK(STORE(2, 4), 4)
#  11 k2  SINK(ADD(5, 6), 5, 6)
#  12 k3  SINK(MUL(5, 7), 5, 7)
#  13     LINEAR(9, 10, 11, 12)
# CPython on that graph:
#   first_appearance  B2=0 C2=1 D2=2 E2=2 F2=3   (5 buffers, 2 copy)
#   last_appearance   B2=0 C2=1 D2=3 E2=2 F2=3
#   nbytes  B2=8192 C2=2048 D2=1024 E2=512 F2=256     sum 12032
#   buf_hold {B2: 1, C2: 1}
#   events  (0,T,3) (1,T,4) (2,F,3) (2,T,5) (2,T,6)
#           (3,F,4) (3,F,6) (3,T,7) (4,F,5) (4,F,7)
#   total_memory 24064
#   offsets  B2=0 C2=8192 D2=0 E2=1024 F2=1024   (CPython's TLSFAllocator)
#   peaks / arena_sizes  (CPU,0)=1536   (CPU,1)=10240     2 arenas
#   rewrite: 5 BITCASTs, 2 arenas
# ===========================================================================
type Walk is Data:
  Walk{fx: F.Folded, a: U32, msel: U32, mstack: U32, st: U32, k: U32, md: U32, mc: U32}

def Walk.fx(w: Walk) -> F.Folded:
  match w:
    case Walk{fx, a, msel, mstack, st, k, md, mc}: fx

def Walk.a(w: Walk) -> U32:
  match w:
    case Walk{fx, a, msel, mstack, st, k, md, mc}: a

def Walk.msel(w: Walk) -> U32:
  match w:
    case Walk{fx, a, msel, mstack, st, k, md, mc}: msel

def Walk.mstack(w: Walk) -> U32:
  match w:
    case Walk{fx, a, msel, mstack, st, k, md, mc}: mstack

def Walk.st(w: Walk) -> U32:
  match w:
    case Walk{fx, a, msel, mstack, st, k, md, mc}: st

def Walk.md(w: Walk) -> U32:
  match w:
    case Walk{fx, a, msel, mstack, st, k, md, mc}: md

def Walk.mc(w: Walk) -> U32:
  match w:
    case Walk{fx, a, msel, mstack, st, k, md, mc}: mc

def Walk.k(w: Walk) -> U32:
  match w:
    case Walk{fx, a, msel, mstack, st, k, md, mc}: k

def mem_buf(+slot: U32, size: U32, dev: S.Dev) -> O.ParamArg:
  O.ParamArg{slot, S.int32(), Some{size}, None{}, None{}, None{}, S.AGlobal{}, Some{dev},
             False{}, None{}, Some{slot}, False{}, None{}}

def cpu() -> S.Dev: S.D1{0}
def disk() -> S.Dev: S.D1{1}
def mdev() -> S.Dev: S.Dn{[2, 3]}
def mdev_cl() -> S.Dev: S.Dn{[2, 4]}
def unpl() -> List<&2, U32>: [1, 4]

def walk_of() -> Walk:
  +n1 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  +n2 = O.UOp.new(O.Found.ar(n1), O.OpsBUFFER{}, [O.Found.i(n1)], O.AParam{mem_buf(0, 16, cpu())}, O.TNone{})
  +n3 = O.UOp.new(O.Found.ar(n2), O.OpsMSELECT{}, [O.Found.i(n2)], O.ATuple{[0]}, O.TNone{})
  +n4 = O.UOp.new(O.Found.ar(n3), O.OpsMSTACK{}, [O.Found.i(n3), O.Found.i(n3)], O.ANone{}, O.TNone{})
  +n5 = O.UOp.new(O.Found.ar(n4), O.OpsCONST{}, Nil{}, O.APy{O.CInt{H.i64_of_i32(1)}}, O.TNone{})
  +n6 = O.UOp.new(O.Found.ar(n5), O.OpsSTORE{}, [O.Found.i(n2), O.Found.i(n5)], O.ANone{}, O.TNone{})
  +n7 = O.UOp.new(O.Found.ar(n6), O.OpsBUFFER{}, [O.Found.i(n1)], O.AParam{mem_buf(9, 32, mdev())}, O.TNone{})
  +n8 = O.UOp.new(O.Found.ar(n7), O.OpsBUFFER{}, [O.Found.i(n1)], O.AParam{mem_buf(8, 32, mdev_cl())}, O.TNone{})
  Walk{F.folded(O.Found.ar(n8)), O.Found.i(n2), O.Found.i(n3), O.Found.i(n4), O.Found.i(n6),
       O.Found.i(n5), O.Found.i(n7), O.Found.i(n8)}

type Proj is Data:
  Proj{fx: F.Folded, lin: U32, a2: U32, b2: U32, c2: U32, d2: U32, e2: U32, f2: U32, dk: U32}

def Proj.fx(p: Proj) -> F.Folded:
  match p:
    case Proj{fx, lin, a2, b2, c2, d2, e2, f2, dk}: fx

def Proj.lin(p: Proj) -> U32:
  match p:
    case Proj{fx, lin, a2, b2, c2, d2, e2, f2, dk}: lin

def mem_sel(k: U32, xs: List<&2, U32>) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, U32.to_nat(k)), 0)

def Proj.at(+p: Proj, k: U32) -> U32:
  match p:
    case Proj{fx, lin, a2, b2, c2, d2, e2, f2, dk}:
      mem_sel(k, [a2, b2, c2, d2, e2, f2, dk])

# CPython's own `TLSFAllocator` answers, keyed by the buffer's arena index. This
# is the ONE seam in the file and the gate pins every number derived from it.
def mem_offs() -> List<&2, Off>:
  [Off{3, 0}, Off{4, 8192}, Off{5, 0}, Off{6, 1024}, Off{7, 1024}]

def plan_plan(fx: F.Folded) -> Plan:
  Plan{fx, Nil{}, unpl()}

def proj_of() -> Proj:
  +n1 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  +n2 = O.UOp.new(O.Found.ar(n1), O.OpsBUFFER{}, [O.Found.i(n1)], O.AParam{mem_buf(0, 1024, cpu())}, O.TNone{})
  +n3 = O.UOp.new(O.Found.ar(n2), O.OpsBUFFER{}, [O.Found.i(n1)], O.AParam{mem_buf(1, 2048, cpu())}, O.TNone{})
  +n4 = O.UOp.new(O.Found.ar(n3), O.OpsBUFFER{}, [O.Found.i(n1)], O.AParam{mem_buf(2, 512, cpu())}, O.TNone{})
  +n5 = O.UOp.new(O.Found.ar(n4), O.OpsBUFFER{}, [O.Found.i(n1)], O.AParam{mem_buf(3, 256, cpu())}, O.TNone{})
  +n6 = O.UOp.new(O.Found.ar(n5), O.OpsBUFFER{}, [O.Found.i(n1)], O.AParam{mem_buf(4, 128, cpu())}, O.TNone{})
  +n7 = O.UOp.new(O.Found.ar(n6), O.OpsBUFFER{}, [O.Found.i(n1)], O.AParam{mem_buf(5, 64, cpu())}, O.TNone{})
  +n8 = O.UOp.new(O.Found.ar(n7), O.OpsBUFFER{}, [O.Found.i(n1)], O.AParam{mem_buf(6, 4096, disk())}, O.TNone{})
  +n9 = O.UOp.new(O.Found.ar(n8), O.OpsSTORE{}, [O.Found.i(n2), O.Found.i(n3)], O.ANone{}, O.TNone{})
  +n10 = O.UOp.sink(O.Found.ar(n9), [O.Found.i(n9), O.Found.i(n3)])
  +n11 = O.UOp.new(O.Found.ar(n10), O.OpsSTORE{}, [O.Found.i(n2), O.Found.i(n4)], O.ANone{}, O.TNone{})
  +n12 = O.UOp.sink(O.Found.ar(n11), [O.Found.i(n11), O.Found.i(n4)])
  +n13 = O.UOp.alu(O.Found.ar(n12), O.OpsADD{}, [O.Found.i(n5), O.Found.i(n6)])
  +n14 = O.UOp.sink(O.Found.ar(n13), [O.Found.i(n13), O.Found.i(n5), O.Found.i(n6)])
  +n15 = O.UOp.alu(O.Found.ar(n14), O.OpsMUL{}, [O.Found.i(n5), O.Found.i(n7)])
  +n16 = O.UOp.sink(O.Found.ar(n15), [O.Found.i(n15), O.Found.i(n5), O.Found.i(n7)])
  +n17 = O.UOp.new(O.Found.ar(n16), O.OpsLINEAR{},
                  [O.Found.i(n10), O.Found.i(n12), O.Found.i(n14), O.Found.i(n16)], O.ANone{}, O.TNone{})
  Proj{F.folded(O.Found.ar(n17)), O.Found.i(n17), O.Found.i(n2), O.Found.i(n3), O.Found.i(n4),
       O.Found.i(n5), O.Found.i(n6), O.Found.i(n7), O.Found.i(n8)}

# ---------------------------------------------------------------------------
# THE ROWS. `main` prints one per line; `1` is True and `0` is False, and a COUNT
# row prints the count itself. Every value is CPython's, and the reason each row
# exists is on the row.
# ---------------------------------------------------------------------------
def mem_len(+xs: List<&2, U32>) -> U32:
  U32.from_nat(List.length(&2, U32, xs))

def mem_len2(+xs: List<&2, Asz>) -> U32:
  U32.from_nat(List.length(&2, Asz, xs))

def mem_nb_f(+b: U32, tc: List<&2, Bf>) -> U32:
  mem_first_i.of2(b, tc)

def mem_nb_l(+b: U32, +tc: List<&2, Bf>) -> U32:
  mem_last_i.of2(b, tc)

def mem_nev(+xs: List<&2, Ev>) -> U32:
  U32.from_nat(List.length(&2, Ev, xs))

def mem_npk(+xs: List<&2, Peak>) -> U32:
  U32.from_nat(List.length(&2, Peak, xs))

def mem_naz(+xs: List<&2, Asz>) -> U32:
  U32.from_nat(List.length(&2, Asz, xs))

def mem_col_of(+w: Walk, u: U32) -> List<&2, U32>:
  mem_collect_of(O.Arena.budget(F.Folded.ar(Walk.fx(w))), F.Folded.ar(Walk.fx(w)), u)

def mem_col(+w: Walk, u: U32) -> U32:
  mem_len(mem_col_of(w, u))

def mem_if(b: Bool) -> U32:
  match b:
    case True{}: 1
    case _: 0

def mem_eq(a: U32, b: U32) -> U32:
  mem_if(U32.is_eq(a, b))

# "every element is `want`", as a fold over the whole list. `List.get` at 0 and a
# count of 1 together say the same thing for the one-element case this row has,
# and saying THAT is why the row is one line instead of a fold.
def mem_all.of(h: U32, n: U32, want: U32) -> U32:
  mem_if(Bool.and(U32.is_eq(h, want), U32.is_eq(n, 1)))

def mem_all(+xs: List<&2, U32>, want: U32) -> U32:
  mem_all.of(mem_head(xs), mem_len(xs), want)

def mem_ev_at(evs: List<&2, Ev>, n: U32) -> Ev:
  Maybe.default(&2, Ev, List.get(&2, Ev, evs, U32.to_nat(n)), Ev{999, 999, 999})

def mem_asz_at(azs: List<&2, Asz>, n: U32) -> Asz:
  Maybe.default(&2, Asz, List.get(&2, Asz, azs, U32.to_nat(n)), Asz{Lane{S.D1{999}, 9}, 999})

def mem_pk_at(+ps: List<&2, Peak>, n: U32) -> Peak:
  Maybe.default(&2, Peak, List.get(&2, Peak, ps, U32.to_nat(n)), Peak{Lane{S.D1{999}, 9}, 999})

def mem_plan(+p: Proj) -> Planned:
  memory_plan_rewrite(plan_plan(Proj.fx(p)), Proj.lin(p), mem_offs())

def mem_scan_of(+p: Proj) -> Scan:
  mem_scan.of(F.Folded.ar(Proj.fx(p)), plan_plan(Proj.fx(p)), Proj.lin(p))

def mem_scan_bs(+p: Proj) -> List<&2, U32>:
  Scan.bs(mem_scan_of(p))

def mem_scan_tc(+p: Proj) -> List<&2, Bf>:
  Scan.tc(mem_scan_of(p))

def Planned.bs(r: Planned) -> List<&2, U32>:
  match r:
    case Planned{tc, bs, evs, tot, azs}: bs

def Planned.evs(r: Planned) -> List<&2, Ev>:
  match r:
    case Planned{tc, bs, evs, tot, azs}: evs

def Planned.tot(r: Planned) -> U32:
  match r:
    case Planned{tc, bs, evs, tot, azs}: tot

def Planned.azs(r: Planned) -> List<&2, Asz>:
  match r:
    case Planned{tc, bs, evs, tot, azs}: azs

def mem_row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

# memory.py:59-60, the row `DEBUG >= 1` prints, as ONE row: the naive plan is one
# arena per buffer and the planned one is one arena per LANE. CPython on this
# fixture: `{len(first_appearance)} -> {len(arenas)} bufs` = 5 -> 2, and
# `omem`/`nmem` = 12032/11776 bytes, so the DEBUG line fires. The byte pair is
# `p_nb_*` (12032 summed) and `p_azs0`/`p_azs1` (10240 + 1536 = 11776) above.
def p_count() -> String:
  +r = mem_plan(proj_of())
  String.concat(["COUNT bufs=", U32.show(mem_len(Planned.bs(r))),
                 " arenas=", U32.show(mem_len2(Planned.azs(r)))])

# --- the collect walk, memory.py:7-10 ---------------------------------------
# A BUFFER collects itself: CPython `_collect_bufs(A)` == [A].
def w_buf() -> U32:
  mem_eq(mem_col(walk_of(), Walk.a(walk_of())), 1)

# ...and it is the BUFFER, not the MSELECT it is wrapped in.
def w_buf_is() -> U32:
  mem_all(mem_col_of(walk_of(), Walk.a(walk_of())), Walk.a(walk_of()))

# MSELECT recurses: `_collect_bufs(A.mselect(0))` == [A], still the buffer.
def w_msel() -> U32:
  mem_eq(mem_col(walk_of(), Walk.msel(walk_of())), 1)

# MSTACK recurses over EVERY src and does NOT dedupe: CPython printed [A, A]
# for MSTACK(MSEL, MSEL) of one buffer. A dedupe here would be a real difference,
# because `si_bufs` flows into `copy_bufs.update` and into the lifetime upsert.
def w_mstack() -> U32:
  mem_eq(mem_col(walk_of(), Walk.mstack(walk_of())), 2)

# a STORE is not a buffer and does not recurse: [] in CPython.
def w_store() -> U32:
  mem_eq(mem_col(walk_of(), Walk.st(walk_of())), 0)

# a CONST is not a buffer either: [] in CPython.
def w_const() -> U32:
  mem_eq(mem_col(walk_of(), Walk.k(walk_of())), 0)

# a BUFFER on the tuple device ("CPU","METAL") = tags 2 and 3, which is the
# fixture CPython's `cp_mdev` (True) and `cp_mdev_cl` (False) were run against.
# --- `_can_plan`, memory.py:12-16 -------------------------------------------
def w_cp_plain() -> U32:
  mem_if(mem_can_plan(Walk.fx(walk_of()), Walk.a(walk_of()), Nil{}, unpl()))

# held: `if b in held_bufs: return False`
def w_cp_held() -> U32:
  mem_if(Bool.not(mem_can_plan(Walk.fx(walk_of()), Walk.a(walk_of()), [Walk.a(walk_of())], unpl())))

# the DISK/CL/WEBGPU prefix test, as a tag set. CPython: DISK False.
def w_cp_disk() -> U32:
  mem_if(Bool.not(mem_can_plan(Walk.fx(walk_of()), Proj.at(proj_of(), 6), Nil{}, unpl())))

# a TUPLE device whose members are both fine: ("CPU","METAL") was True.
def w_cp_mdev() -> U32:
  mem_if(mem_can_plan(Walk.fx(walk_of()), Walk.md(walk_of()), Nil{}, unpl()))

# a tuple device whose SECOND member is CL: ("CPU","CL:1") was False, so `all`
# is over every member and not just the first. Tags 2 and 3, tag 3 is in `unpl`.
def w_cp_mdev_cl() -> U32:
  mem_if(Bool.not(mem_can_plan(Walk.fx(walk_of()), Walk.mc(walk_of()), Nil{}, unpl())))

# --- the lifetime scan, memory.py:28-33 -------------------------------------
# the COUNT: five buffers are plannable. Seven exist; A2 is a STORE dest and DK is
# on DISK, so both are out. A count is the row that catches a MISSING filter.
def p_nbufs() -> U32:
  mem_len(mem_scan_bs(proj_of()))

# the copy-buffer COUNT is 2 (B2, C2): only kernels whose BODY is a STORE.
def p_ncopy() -> U32:
  mem_len(Scan.cp(mem_scan_of(proj_of())))

# `for i, si in enumerate(linear.src)` -- first appearance index per buffer
def p_b2_f() -> U32: mem_eq(mem_nb_f(Proj.at(proj_of(), 1), mem_scan_tc(proj_of())), 0)
def p_c2_f() -> U32: mem_eq(mem_nb_f(Proj.at(proj_of(), 2), mem_scan_tc(proj_of())), 1)
def p_d2_f() -> U32: mem_eq(mem_nb_f(Proj.at(proj_of(), 3), mem_scan_tc(proj_of())), 2)
def p_e2_f() -> U32: mem_eq(mem_nb_f(Proj.at(proj_of(), 4), mem_scan_tc(proj_of())), 2)
def p_f2_f() -> U32: mem_eq(mem_nb_f(Proj.at(proj_of(), 5), mem_scan_tc(proj_of())), 3)

# `last_appearance[b] = i` is unconditional, so D2 -- read by BOTH k2 and k3 --
# ends at 3 while E2, read only by k2, ends at 2. This pair is the whole reason
# `last_appearance` is not just the last `first`.
def p_d2_l() -> U32: mem_eq(mem_nb_l(Proj.at(proj_of(), 3), mem_scan_tc(proj_of())), 3)
def p_e2_l() -> U32: mem_eq(mem_nb_l(Proj.at(proj_of(), 4), mem_scan_tc(proj_of())), 2)

# A2 is never collected: it is a kernel SINK's src[0], and only src[1:] is walked.
def mem_absent2(found: Bool) -> U32:
  match found:
    case True{}: 0
    case _: 1

def mem_absent.of(b: U32, bs: List<&2, U32>) -> U32:
  mem_absent2(List.contains(U32, U32.is_eq, bs, b))


def mem_absent(bs: List<&2, U32>, b: U32) -> U32:
  mem_absent.of(b, bs)

def p_a2_absent() -> U32:
  mem_absent(mem_scan_bs(proj_of()), Proj.at(proj_of(), 0))

# --- `nbytes` and `buf_hold`, memory.py:38 and :42 --------------------------
# `round_up(max_numel() * itemsize, 256)`, and int32 is 4 bytes. These four are
# the sizes; they differ from each other so a shared constant cannot pass them.
def p_nb_b2() -> U32: mem_eq(mem_nbytes(Proj.fx(proj_of()), Proj.at(proj_of(), 1)), 8192)
def p_nb_c2() -> U32: mem_eq(mem_nbytes(Proj.fx(proj_of()), Proj.at(proj_of(), 2)), 2048)
def p_nb_d2() -> U32: mem_eq(mem_nbytes(Proj.fx(proj_of()), Proj.at(proj_of(), 3)), 1024)
def p_nb_e2() -> U32: mem_eq(mem_nbytes(Proj.fx(proj_of()), Proj.at(proj_of(), 4)), 512)

# `buf_hold = last - first + 1` for a COPY buffer only. B2 is 0..0 so it is 1, and
# D2 is not a copy buffer so it is 0 -- two rows for the same conditional.
def p_hold_b2() -> U32:
  mem_eq(mem_hold2(Proj.at(proj_of(), 1), mem_scan_tc(proj_of()), Scan.cp(mem_scan_of(proj_of()))), 1)
def p_hold_d2() -> U32:
  mem_eq(mem_hold2(Proj.at(proj_of(), 3), mem_scan_tc(proj_of()), Scan.cp(mem_scan_of(proj_of()))), 0)

# --- the events, memory.py:43-44 --------------------------------------------
# the COUNT: two per buffer, no more and no fewer.
def p_nev() -> U32: mem_nev(Planned.evs(mem_plan(proj_of())))

# THE ORDER AT ONE INDEX. CPython: (3,F,C2) (3,F,E2) (3,T,F2). Two closes and one
# open all at index 3, and the CLOSES COME FIRST because the key is (i, is_open)
# with False < True. A port that sorted opens first would free after the next
# alloc and change every arena size. The two closes then keep C2 before E2, which
# is the sort's STABILITY and not the key -- and `ev3` is a THREE-WAY tie, so a
# first-wins-vs-conjunction bug in the comparator moves all three of these rows.
def p_ev3_i() -> U32: mem_eq(Ev.i(mem_ev_at(Planned.evs(mem_plan(proj_of())), 5)), 3)
def p_ev3_o0() -> U32: mem_eq(Ev.o(mem_ev_at(Planned.evs(mem_plan(proj_of())), 5)), 0)
def p_ev3_b0() -> U32: mem_eq(Ev.b(mem_ev_at(Planned.evs(mem_plan(proj_of())), 5)), 4)
def p_ev3_o1() -> U32: mem_eq(Ev.o(mem_ev_at(Planned.evs(mem_plan(proj_of())), 6)), 0)
def p_ev3_b1() -> U32: mem_eq(Ev.b(mem_ev_at(Planned.evs(mem_plan(proj_of())), 6)), 6)
def p_ev3_o2() -> U32: mem_eq(Ev.o(mem_ev_at(Planned.evs(mem_plan(proj_of())), 7)), 1)
def p_ev3_b2() -> U32: mem_eq(Ev.b(mem_ev_at(Planned.evs(mem_plan(proj_of())), 7)), 7)

# THE SAME AT INDEX 2, where a copy buffer's close (B2, whose hold pushed it to
# `last + 1 + 1 = 2`) meets two compute opens. `ev2` is the row that pins
# `buf_hold`: without the hold B2's close would land at index 1 and move.
def p_ev2_o0() -> U32: mem_eq(Ev.o(mem_ev_at(Planned.evs(mem_plan(proj_of())), 2)), 0)
def p_ev2_b0() -> U32: mem_eq(Ev.b(mem_ev_at(Planned.evs(mem_plan(proj_of())), 2)), 3)
def p_ev2_o1() -> U32: mem_eq(Ev.o(mem_ev_at(Planned.evs(mem_plan(proj_of())), 3)), 1)
def p_ev2_b1() -> U32: mem_eq(Ev.b(mem_ev_at(Planned.evs(mem_plan(proj_of())), 3)), 5)

# the first and last events overall: an open at 0 and a close at 4.
def p_ev_first() -> U32: mem_eq(Ev.i(mem_ev_at(Planned.evs(mem_plan(proj_of())), 0)), 0)
def p_ev_last() -> U32: mem_eq(Ev.i(mem_ev_at(Planned.evs(mem_plan(proj_of())), 9)), 4)

# --- the allocator seam, memory.py:45 and :48-53 ----------------------------
# `total_memory = sum(nbytes.values()) * 2` -- 12032 doubled.
def p_tot() -> U32: mem_eq(Planned.tot(mem_plan(proj_of())), 24064)

# ONE ARENA PER LANE, and the lane COUNT is 2 here: ("CPU", 0) for the compute
# buffers and ("CPU", 1) for the copy buffers. The split is the whole point of
# the `_key` comment on avoiding copy->compute->copy, so the count is the row.
def p_nlanes() -> U32: mem_npk(mem_peaks(plan_plan(Proj.fx(proj_of())), Scan.cp(mem_scan_of(proj_of())), mem_offs(), Planned.evs(mem_plan(proj_of()))))

# THE LANE ORDER IS THE EVENT ORDER, and the FIRST event belongs to a COPY
# buffer (B2), so lane 0 is ("CPU", 1) and lane 1 is ("CPU", 0). Python's
# `defaultdict` creates `peaks[_key(buf)]` on the first event and `dict` keeps that
# insertion order, and `arena_sizes` iterates it -- so this file's lane 0 is the
# copy lane. Getting the two the other way round is the mistake a reader makes and
# `p_lane*cp` is the row that says so.
#
# lane 0, the COPY lane: B2 at offset 0 (8192 raw) and C2 at 8192 (2048 raw), and
# `buf_hold` keeps them apart, so the peak is their SUM: 10240.
def p_peak0() -> U32: mem_eq(Peak.p(mem_pk_at(mem_peaks(plan_plan(Proj.fx(proj_of())), Scan.cp(mem_scan_of(proj_of())), mem_offs(), Planned.evs(mem_plan(proj_of()))), 0)), 10240)

# lane 1, the COMPUTE lane: 1536, and NOT the sum of 1024 + 512 + 256. F2 reuses
# E2's freed block at 1024, so the high-water mark is the larger of the two
# overlapping pairs and this row is the only thing in the gate that says the
# allocator's answer was used rather than re-derived.
def p_peak1() -> U32: mem_eq(Peak.p(mem_pk_at(mem_peaks(plan_plan(Proj.fx(proj_of())), Scan.cp(mem_scan_of(proj_of())), mem_offs(), Planned.evs(mem_plan(proj_of()))), 1)), 1536)

# the lane keys themselves: (CPU,1) then (CPU,0). Without `cp` both lanes would
# collide and `mem_lanes` would answer ONE lane with the sum of both -- so these
# two rows and `p_nlanes` are the whole `_key` contract.
def p_lane0cp() -> U32: mem_eq(Lane.cp(Peak.ln(mem_pk_at(mem_peaks(plan_plan(Proj.fx(proj_of())), Scan.cp(mem_scan_of(proj_of())), mem_offs(), Planned.evs(mem_plan(proj_of()))), 0))), 1)
def p_lane1cp() -> U32: mem_eq(Lane.cp(Peak.ln(mem_pk_at(mem_peaks(plan_plan(Proj.fx(proj_of())), Scan.cp(mem_scan_of(proj_of())), mem_offs(), Planned.evs(mem_plan(proj_of()))), 1))), 0)

# `arena_sizes = {key: round_up(peak, block_size)}` -- 10240 and 1536 are already
# multiples of 256 here, so this pair pins the LANE COUNT and the ordering, and
# `p_peak*` pins the arithmetic underneath.
def p_azs_n() -> U32: mem_naz(Planned.azs(mem_plan(proj_of())))
def p_azs0() -> U32: mem_eq(Asz.sz(mem_asz_at(Planned.azs(mem_plan(proj_of())), 0)), 10240)
def p_azs1() -> U32: mem_eq(Asz.sz(mem_asz_at(Planned.azs(mem_plan(proj_of())), 1)), 1536)

# CPython's rewrite of this same graph produced 5 BITCASTs (one per plannable
# buffer) and 2 arenas. The Bend port cannot build the BITCASTs -- `new_buffer`
# and `substitute` are the wall -- so this row pins the plan's OWN count, which is
# the number the caller needs in order to build them.
def p_nplan() -> U32: mem_len(Planned.bs(mem_plan(proj_of())))

def empty_of() -> Proj:
  +n1 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  +n2 = O.UOp.new(O.Found.ar(n1), O.OpsBUFFER{}, [O.Found.i(n1)], O.AParam{mem_buf(0, 4096, disk())}, O.TNone{})
  +n3 = O.UOp.new(O.Found.ar(n2), O.OpsCUSTOMI{}, Nil{}, O.AStr{"x"}, O.TNone{})
  +n4 = O.UOp.sink(O.Found.ar(n3), [O.Found.i(n3)])
  +n5 = O.UOp.new(O.Found.ar(n4), O.OpsLINEAR{}, [O.Found.i(n4)], O.ANone{}, O.TNone{})
  Proj{F.folded(O.Found.ar(n5)), O.Found.i(n5), O.Found.i(n2), O.Found.i(n2), O.Found.i(n2),
       O.Found.i(n2), O.Found.i(n2), O.Found.i(n2), O.Found.i(n2)}

# A BUFFER whose raw size is NOT a multiple of 256. Every buffer in `proj_of` has a
# power-of-two size, so `raw` is already 256-aligned for all of them and
# `round_up` is the IDENTITY on this fixture -- measured: mutating
# `mem_nbytes` to return the raw size moves NO row. This one buffer exists so that
# mutation has somewhere to land: int32 of 100 elements is 400 bytes raw, which
# rounds to 512.
def unaligned_of() -> Proj:
  +n1 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  +n2 = O.UOp.new(O.Found.ar(n1), O.OpsBUFFER{}, [O.Found.i(n1)], O.AParam{mem_buf(0, 100, cpu())}, O.TNone{})
  +n3 = O.UOp.new(O.Found.ar(n2), O.OpsADD{}, [O.Found.i(n2), O.Found.i(n2)], O.ANone{}, O.TNone{})
  +n4 = O.UOp.sink(O.Found.ar(n3), [O.Found.i(n3), O.Found.i(n2)])
  +n5 = O.UOp.new(O.Found.ar(n4), O.OpsLINEAR{}, [O.Found.i(n4)], O.ANone{}, O.TNone{})
  Proj{F.folded(O.Found.ar(n5)), O.Found.i(n5), O.Found.i(n2), O.Found.i(n2), O.Found.i(n2),
       O.Found.i(n2), O.Found.i(n2), O.Found.i(n2), O.Found.i(n2)}

# 400 = 100 int32 elements. The control row: it says what is being rounded, so a
# mutation of `mem_raw` cannot hide behind a coincidence.
def u_raw() -> U32: mem_eq(mem_raw(Proj.fx(unaligned_of()), Proj.at(unaligned_of(), 0)), 400)

# 512 = round_up(400, 256). THE row for `block_size`.
def u_nb() -> U32: mem_eq(mem_nbytes(Proj.fx(unaligned_of()), Proj.at(unaligned_of(), 0)), 512)

# and the planner agrees: this linear's whole budget is 512 and it is one arena.
def u_tot() -> U32: mem_eq(Planned.tot(mem_plan(unaligned_of())), 1024)

def u_nlanes() -> U32: mem_npk(mem_peaks(plan_plan(Proj.fx(unaligned_of())), Scan.cp(mem_scan_of(unaligned_of())), mem_offs(), Planned.evs(mem_plan(unaligned_of()))))

# --- the EMPTY plan, memory.py:34 ------------------------------------------
# `if not first_appearance: return linear`. A LINEAR whose one kernel has no
# plannable args leaves the table empty, and that empty table IS the early
# return. Without this row every fixture above is all-True and says nothing about
# the branch.
def e_nbufs() -> U32: mem_len(mem_scan_bs(empty_of()))

# ===========================================================================
# THE GATE DOCUMENT. `1` is True, `0` is False, and a COUNT row prints the count.
# Every value is CPython's: `.agents/slop/notes/sched-mem-truth.py` printed them
# for the SAME two graphs and this file's fixtures are rebuilt from that output.
#
#   w_buf=1 w_buf_is=1 w_msel=1 w_mstack=1 w_store=1 w_const=1
#     `_collect_bufs`: a BUFFER collects ITSELF and nothing else does; an MSTACK
#     of two MSELECTs of ONE buffer collects it TWICE, which is the row a dedupe
#     would fail and CPython's `['A','A']` is the oracle for.
#   w_cp_plain=1 w_cp_held=1 w_cp_disk=1 w_cp_mdev=1 w_cp_mdev_cl=1
#     `_can_plan`: not held, and no device in the unplannable tag set. `w_cp_mdev_cl`
#     is the row that `all` runs over EVERY member of a tuple device and not just
#     the first -- Python's `("CPU","CL:1")` was False.
#   p_nbufs=5 p_ncopy=2
#     the two COUNTS. Five plannable buffers out of seven (A2 is a STORE dest,
#     DK is on DISK), two of them copy buffers.
#   p_b2_f=1 p_c2_f=1 p_d2_f=1 p_e2_f=1 p_f2_f=1
#     `first_appearance` = 0,1,2,2,3.
#   p_d2_l=1 p_e2_l=1
#     `last_appearance` = 3 for D2 and 2 for E2. THE PAIR: D2 is read by both k2
#     and k3 and E2 by k2 only, so `last` is not a copy of `first` and the two
#     rows are what say the scan visits a buffer more than once.
#   p_a2_absent=1
#     the STORE dest never reaches `first_appearance`.
#   p_nb_b2=1 p_nb_c2=1 p_nb_d2=1 p_nb_e2=1
#     `round_up(max_numel * itemsize, 256)` = 8192, 2048, 1024, 512.
#   p_hold_b2=1 p_hold_d2=1
#     `buf_hold` = 1 for a COPY buffer and 0 for a compute buffer.
#   p_nev=10
#     the event COUNT: two per buffer. A buffer read by four kernels contributes
#     TWO events, not eight -- that is the opens-over-the-distinct-list row.
#   p_ev3_i=1 p_ev3_o0=1 p_ev3_b0=1 p_ev3_o1=1 p_ev3_b1=1 p_ev3_o2=1 p_ev3_b2=1
#   p_ev2_o0=1 p_ev2_b0=1 p_ev2_o1=1 p_ev2_b1=1
#   p_ev_first=1 p_ev_last=1
#     THE ORDER, which is the part a count cannot see. Index 3 holds three events
#     -- two closes and one open -- so it is BOTH the close-before-open row AND a
#     three-way tie, and it is where a broken comparator and an unstable sort
#     would both show. Index 2 is the `buf_hold` row: B2's close is pushed to
#     index 2 by its hold of 1, where it meets two compute opens.
#   p_tot=1
#     `total_memory = sum(nbytes) * 2` = 24064.
#   p_nlanes=2 p_lane0cp=1 p_lane1cp=1
#     ONE ARENA PER LANE, and the lane ORDER is the event order -- the first event
#     belongs to a copy buffer, so lane 0 is ("CPU",1) and lane 1 is ("CPU",0).
#   p_peak0=1 p_peak1=1
#     10240 for the copy lane (two buffers that do not overlap: their SUM) and
#     1536 for the compute lane (F2 reuses E2's freed block, so it is NOT the
#     sum). `p_peak1` is the only row that says the ALLOCATOR's answer was used
#     rather than re-derived.
#   p_azs_n=2 p_azs0=1 p_azs1=1
#     `arena_sizes`, same order.
#   p_nplan=5
#     the plan's own buffer count -- what CPython's rewrite turned into 5 BITCASTs.
#   u_raw=1 u_nb=1 u_tot=1 u_nlanes=1
#     the UNALIGNED fixture: 100 int32 = 400 bytes raw, 512 after `round_up`.
#   e_nbufs=0
#     `if not first_appearance: return linear` (memory.py:34). Every other fixture
#     is all-True and says nothing about this branch.
# ===========================================================================
#
# MUTATIONS, all re-run against this file. This is not one row per bug: several
# rows are load-bearing TOGETHER, and one row is LOCALISED.
#
# | mutation | rows that moved | how many |
# | --- | --- | --- |
# | `mem_ev_cmp`'s differing-index arm `is_le(ai,bi)` -> `F... | p_ev3_o0, p_ev3_b0, p_ev3_o1, p_ev3_b1, p_ev3_b2, p_ev2_b0, p_ev2_o1, p_ev2_b1, p_ev_first, p_ev_last, p_peak0, p_peak1, p_lane0cp, p_lane1cp, p_azs0, p_azs1 | 16 |
# | the open's `o` 1 -> 0, i.e. OPEN and CLOSE share a key ... | p_ev3_b0, p_ev3_b1, p_ev3_o2, p_ev3_b2, p_ev2_b0, p_ev2_o1, p_ev2_b1 | 7 |
# | `mem_hold.of`'s copy arm `add(d,1)` -> `d` (buf_hold of... | p_hold_b2, p_ev3_i, p_ev3_o0, p_ev3_b0, p_ev2_o0, p_ev2_b0, p_ev2_o1, p_ev2_b1 | 8 |
# | `mem_hold.of`'s non-copy arm 0 -> `d` (every buffer get... | p_hold_d2, p_ev_last | 2 |
# | `mem_key.cp.of`'s copy arm 1 -> 0 (the two lanes collid... | p_nlanes, p_peak1, p_lane0cp, p_lane1cp, p_azs_n, p_azs1, COUNT bufs | 7 |
# | `mem_collect.is_multi`'s MSTACK arm -> False{} (MSTACK ... | w_mstack | 1 |
# | `mem_collect.is_buf`'s True -> False{} (a BUFFER no lon... | w_buf, w_buf_is, w_msel, w_mstack, p_nbufs, p_ncopy, p_c2_f, p_d2_f, p_e2_f, p_f2_f, p_d2_l, p_e2_l, p_hold_b2, p_nev, p_ev3_i, p_ev3_o0, p_ev3_b0, p_ev3_o1, p_ev3_b1, p_ev3_o2, p_ev3_b2, p_ev2_o0, p_ev2_b0, p_ev2_o1, p_ev2_b1, p_ev_first, p_ev_last, p_tot, p_nlanes, p_peak0, p_peak1, p_lane0cp, p_lane1cp, p_azs_n, p_azs0, p_azs1, p_nplan, u_tot, u_nlanes, COUNT bufs | 40 |
# | `mem_kern_cp3`'s STORE arm `mem_cp_add` -> `cp` (no buf... | p_ncopy, p_hold_b2, p_ev3_i, p_ev3_o0, p_ev3_b0, p_ev2_o0, p_ev2_b0, p_ev2_o1, p_ev2_b1, p_nlanes, p_peak1, p_lane0cp, p_lane1cp, p_azs_n, p_azs1, COUNT bufs | 16 |
# | `mem_kept.one`'s keep arm -> acc (the `_can_plan` filte... | p_nbufs, p_ncopy, p_c2_f, p_d2_f, p_e2_f, p_f2_f, p_d2_l, p_e2_l, p_hold_b2, p_nev, p_ev3_i, p_ev3_o0, p_ev3_b0, p_ev3_o1, p_ev3_b1, p_ev3_o2, p_ev3_b2, p_ev2_o0, p_ev2_b0, p_ev2_o1, p_ev2_b1, p_ev_first, p_ev_last, p_tot, p_nlanes, p_peak0, p_peak1, p_lane0cp, p_lane1cp, p_azs_n, p_azs0, p_azs1, p_nplan, u_tot, u_nlanes, COUNT bufs | 36 |
# | `mem_args.of`'s `src_from(.., si, 1)` -> `.., si, 0` (t... | NONE | 0 |
# | `mem_off.go`'s hit arm -> acc (every offset reads 0, so... | p_peak0, p_peak1, p_azs0, p_azs1 | 4 |
# | `mem_nbytes`'s `round_up(..)` -> the raw size (block ro... | u_nb, u_tot | 2 |
# | `mem_nbytes`'s block_size 256 -> 512 (the round is stil... | p_tot | 1 |
# | `mem_raw`'s `U32.mul` -> `U32.add` (itemsize applied as... | p_nb_b2, p_nb_c2, p_nb_d2, p_nb_e2, p_tot, p_peak0, p_peak1, p_azs0, p_azs1, u_raw, u_nb, u_tot | 12 |
# | `mem_peak_one`'s hit arm `max(acc,v)` -> `v` (the peak ... | p_peak1, p_azs1 | 2 |
# | `mem_lane_in.of`'s seed `False{}` -> `True{}` (every la... | p_nlanes, p_peak0, p_peak1, p_lane0cp, p_lane1cp, p_azs_n, p_azs0, p_azs1, u_nlanes, COUNT bufs | 10 |
# | `mem_last_one`'s hit arm `v` -> `acc` (last_appearance ... | p_d2_l, p_e2_l, p_ev3_i, p_ev3_o0, p_ev3_b1, p_ev3_b2, p_ev2_b0, p_ev2_o1, p_ev2_b1, p_ev_last | 10 |
# | `mem_first_i.seen`'s keep-first arm `acc` -> `v` (first... | p_d2_f, p_ev3_b0, p_ev3_o1, p_ev3_b1, p_ev2_b1 | 5 |
# | `mem_touch.one`'s `mem_bs_add` -> append unconditionall... | p_nbufs, p_nev, p_ev3_i, p_ev3_o0, p_ev3_b0, p_ev3_b1, p_ev3_o2, p_ev3_b2, p_tot, p_nplan, COUNT bufs | 11 |
# | `mem_scan`'s kernel fuel -> `+ 1n` (one step past the e... | NONE | 0 |
#
# THE TWO THAT MOVE NOTHING ARE BOTH WORTH READING.
#
# `mem_args.one`'s `src_from(ar, si, 1)` -> `src_from(ar, si, 0)` moves NOTHING, and
# that is an EQUIVALENCE rather than a gap: `si.src[0]` is a kernel SINK's BODY and
# a body is never a BUFFER, so `_collect_bufs` answers `[]` for it either way and
# the two slices collect the same buffers. Python's `si.src[1:]` is therefore not
# observable in this file, and the port keeps it because it is the line.
#
# `mem_scan`'s fuel `len` -> `len + 1` moves NOTHING, and that is a SAFETY PROPERTY
# rather than a gap: one step past the end pops the arena's BOTTOM node, a NOOP with
# no srcs, so `mem_args.of` collects nothing and the step is a no-op. `fuel = len` is
# therefore the correct choice AND the forgiving one.
#
# `mem_collect.is_multi`'s MSTACK arm is the one LOCALISED row in the table:
# `w_mstack` and nothing else moves, because `w_mstack` is the only fixture with
# an MSTACK. That is the honest cost of one fixture per shape, and it is why the
# collect rows are a family and not a single row.
# ===========================================================================
# NOT PORTED, one line each, and the WALL each one is behind.
#
# `TLSFAllocator` -- `tinygrad/runtime/support/memory.py:23`, imported at
#   memory.py:5. A mutable Python object: `self.blocks` is a dict of linked-list
#   tuples whose `alloc` splits and `free` coalesces IN PLACE, with two levels of
#   buckets keyed by `size.bit_length()`. Bend has no mutable state and no
#   first-class functions, so it could only be a fold threading a `Data` state
#   through every event -- roughly 300 lines, of a file that is not this unit's,
#   whose output is an INPUT here. The seam is drawn where the wall is: `mem_offs`
#   carries the allocator's ANSWERS (and `mem_total_memory` is the budget this
#   file asks it for), and the gate feeds it CPython's own `TLSFAllocator`. So the
#   lane of every event, the high-water marks, the block rounding, the lane count
#   and the arena sizes are all here and gated; the OFFSETS are not computed here.
#   P6/runtime owns the allocator.
# `linear.substitute(replace_map, name="memory plan", walk=True)` -- memory.py:62.
#   Needs `UOp.substitute` (ops.py:532) and `UOp.new_buffer` (ops.py:853, a P6
#   device call). `mem_offs` plus `Planned.azs` is everything the caller needs to
#   build the map: one arena per lane and one offset per buffer. P3.
# `NO_MEMORY_PLANNER` -- memory.py:21, a `ContextVar`. WALL: no `Config` in Bend;
#   it is a `helpers.bend` P6 flag. The caller returns its input unchanged when it
#   is set, which is what the early return on an empty plan already does.
# `DEBUG >= 1` print -- memory.py:59-60. WALL: `DEBUG` is a `ContextVar`, P6, and
#   Bend has no `Config`; the two numbers it would print (`sum(nbytes.values())`
#   and `Planned.tot`'s halves) are `p_nb_*` and `p_tot` in this gate already.
# `held_bufs: set[UOp] | None` -- memory.py:20. PORTED, as a `List<&2, U32>` and a
#   `List.contains`, because Bend's `Map` is string-keyed. The `None` default is
#   the `Nil{}` the caller passes.
# `LaneKey = tuple[str, int]` -- memory.py:18. PORTED as `Lane{dev: S.Dev, cp:
#   U32}`, which is the same pair with the device as the `U32` tag the runtime
#   interns; `mem_eq_ln` is the `==` and `mem_lanes` is the `set`.
# ===========================================================================
# WHAT `schedule/__init__.py` NEEDS FROM THIS FILE. It is the only caller, and
# nothing here imports it -- the two files meet at the CALL SITE and nowhere else.
#
#   Plan{fx, held, unpl}
#     `fx` is `F.folded(ar)`; `held` and `unpl` are the two lists of device-tag
#     indices. `unpl` IS the P6 device table's answer to "which device names start
#     with DISK / CL / WEBGPU" -- that test cannot be done here because a device is
#     a tag, not a name.
#   memory_plan_rewrite(pl, linear, offs) -> Planned{tc, bs, evs, tot, azs}
#     `tc` the flat touch list `{b, i}` newest-first, `bs` the distinct buffers in
#     first-insertion order (= Python's `first_appearance` key order), `evs` the
#     SORTED event stream (two per buffer, closes before opens at one index), `tot`
#     the allocator budget, `azs` one arena size per lane in lane order.
#   THE CALLER OWNS THE ALLOCATOR. It runs the events, calls its allocator's
#   `alloc`/`free` per event, and hands the offsets back. `offs` is
#   `List<&2, Off>{b, offset}`.
#   THE CALLER OWNS THE SUBSTITUTE. With `offs` and `azs` it can build
#   `arenas = {lane: new_buffer(lane.dev, lane.size, int8)}` and
#   `replace_map = {b: arenas[bs[lane(b)]][off:off+b.nbytes()].bitcast(b.dtype)}`
#   and call `linear.substitute(replace_map, name="memory plan", walk=True)`.
#   `bs` EMPTY is `if not first_appearance: return linear` -- return the linear
#   unchanged and do not allocate.
#   NOTHING ELSE IS PUBLIC. `mem_ok_dev` (the DISK/CL/WEBGPU test) is useful to the
#   other two files in this directory and is worth calling directly.
# ===========================================================================
def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- mem_row("w_buf", w_buf())
    _ : Unit <- mem_row("w_buf_is", w_buf_is())
    _ : Unit <- mem_row("w_msel", w_msel())
    _ : Unit <- mem_row("w_mstack", w_mstack())
    _ : Unit <- mem_row("w_store", w_store())
    _ : Unit <- mem_row("w_const", w_const())
    _ : Unit <- mem_row("w_cp_plain", w_cp_plain())
    _ : Unit <- mem_row("w_cp_held", w_cp_held())
    _ : Unit <- mem_row("w_cp_disk", w_cp_disk())
    _ : Unit <- mem_row("w_cp_mdev", w_cp_mdev())
    _ : Unit <- mem_row("w_cp_mdev_cl", w_cp_mdev_cl())
    _ : Unit <- mem_row("p_nbufs", p_nbufs())
    _ : Unit <- mem_row("p_ncopy", p_ncopy())
    _ : Unit <- mem_row("p_b2_f", p_b2_f())
    _ : Unit <- mem_row("p_c2_f", p_c2_f())
    _ : Unit <- mem_row("p_d2_f", p_d2_f())
    _ : Unit <- mem_row("p_e2_f", p_e2_f())
    _ : Unit <- mem_row("p_f2_f", p_f2_f())
    _ : Unit <- mem_row("p_d2_l", p_d2_l())
    _ : Unit <- mem_row("p_e2_l", p_e2_l())
    _ : Unit <- mem_row("p_a2_absent", p_a2_absent())
    _ : Unit <- mem_row("p_nb_b2", p_nb_b2())
    _ : Unit <- mem_row("p_nb_c2", p_nb_c2())
    _ : Unit <- mem_row("p_nb_d2", p_nb_d2())
    _ : Unit <- mem_row("p_nb_e2", p_nb_e2())
    _ : Unit <- mem_row("p_hold_b2", p_hold_b2())
    _ : Unit <- mem_row("p_hold_d2", p_hold_d2())
    _ : Unit <- mem_row("p_nev", p_nev())
    _ : Unit <- mem_row("p_ev3_i", p_ev3_i())
    _ : Unit <- mem_row("p_ev3_o0", p_ev3_o0())
    _ : Unit <- mem_row("p_ev3_b0", p_ev3_b0())
    _ : Unit <- mem_row("p_ev3_o1", p_ev3_o1())
    _ : Unit <- mem_row("p_ev3_b1", p_ev3_b1())
    _ : Unit <- mem_row("p_ev3_o2", p_ev3_o2())
    _ : Unit <- mem_row("p_ev3_b2", p_ev3_b2())
    _ : Unit <- mem_row("p_ev2_o0", p_ev2_o0())
    _ : Unit <- mem_row("p_ev2_b0", p_ev2_b0())
    _ : Unit <- mem_row("p_ev2_o1", p_ev2_o1())
    _ : Unit <- mem_row("p_ev2_b1", p_ev2_b1())
    _ : Unit <- mem_row("p_ev_first", p_ev_first())
    _ : Unit <- mem_row("p_ev_last", p_ev_last())
    _ : Unit <- mem_row("p_tot", p_tot())
    _ : Unit <- mem_row("p_nlanes", p_nlanes())
    _ : Unit <- mem_row("p_peak0", p_peak0())
    _ : Unit <- mem_row("p_peak1", p_peak1())
    _ : Unit <- mem_row("p_lane0cp", p_lane0cp())
    _ : Unit <- mem_row("p_lane1cp", p_lane1cp())
    _ : Unit <- mem_row("p_azs_n", p_azs_n())
    _ : Unit <- mem_row("p_azs0", p_azs0())
    _ : Unit <- mem_row("p_azs1", p_azs1())
    _ : Unit <- mem_row("p_nplan", p_nplan())
    _ : Unit <- mem_row("u_raw", u_raw())
    _ : Unit <- mem_row("u_nb", u_nb())
    _ : Unit <- mem_row("u_tot", u_tot())
    _ : Unit <- mem_row("u_nlanes", u_nlanes())
    _ : Unit <- mem_row("e_nbufs", e_nbufs())
    IO.print(p_count())
