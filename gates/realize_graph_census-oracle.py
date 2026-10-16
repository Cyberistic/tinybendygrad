#!/usr/bin/env python3
"""realize_graph_census-oracle.py -- CPython's answer for every (driver, node) pair of
`tinybendygrad/engine/realize.bend`, taken from the REAL `tinygrad/engine/realize.py`.

    .venv/bin/python gates/realize_graph_census-oracle.py

THE ORACLE CALLS THE REAL THING. Every row is a call into the module `realize.py`
itself -- `get_call_arg_uops`, `get_call_outs_ins`, `get_call_written_bufs`,
`get_call_kernels`, `get_call_name`, `estimate_uop`, `resolve_params`,
`_get_call_to_compile`, `pm_flatten_linear.rewrite`, `pm_validate.rewrite`,
`pm_beam.rewrite` -- on a fixture that MIRRORS the port's `main_arena` node for node,
index for index, PLUS the nodes the port's own fixture lacks and that its dispatch
arms need. Nothing here reimplements a dispatch, a filter or a rule body.

THE `tn_bitwise_not` POST-MORTEM APPLIES. `gates/tn_bitwise_not-oracle.py`'s docstring
records an oracle that hand-built `cast.ne(true_)` instead of calling
`Tensor.bitwise_not()`, so driver and oracle both minted the CAST CPython folds and
seven rows agreed on a graph CPython does not build. `gates/decomp_graph_census-oracle.py`
records the same failure a SECOND time, in `f2f`'s fixture dtype. Here the discipline is
narrower and it is the only thing that matters for realize: **the port's three tables are
driven through CPython's OWN `PatternMatcher.rewrite`** (`realize.py:213,218,264`) and
`resolve_params`/`_get_call_bufs` are `realize.py`'s own module-scope functions.

`has_dnum` IS AN EXPRESSION, not a function -- `realize.py:139` spells it inline inside
`unwrap_multi` -- so this lane writes the SAME `any(...)` over `call.body.toposort()` and
says so in the driver name (`dnum`). That is the one row whose predicate is transcribed
rather than called, and `classes_hold` pins its answer on a node that reaches each of the
two arms.

`estimate_uop` RETURNS `Estimates` (`renderer/__init__.py:16`), a P5 type, so the
`est` row is the DISPATCH ANSWER and the `nb` row is the BYTE COUNT it is computed from:
`est` asks "does this call take the copy arm" and `nb` asks `prod(src[1].shape) *
src[1].dtype.itemsize`, which is `realize.py:60` written out. Both are values `realize.py`
really produces (`nb` is the very expression `realize.py:60` evaluates) rather than a
field the port cannot read.

THE SIGNATURE IS A CONE OR A LIST, NEVER A COUNT, because a count cannot see a swapped
node. `gates/rng_graph_census-gate.py` names the failure it has: `Rng.sig` prints a
3-op PREFIX and no ARG, and `gr_10` printed identically on both sides until a deep
printer was used. So `cone()` here is the FULL DFS PRE-ORDER over the answer, deduped by
identity, parent before child, and every row carries `OP/arity` and -- for the two
drivers whose subject is a bound value (`var`, `res`) -- the CONST's VALUE, because
`realize.py:18`'s `UOp.const(s.arg.val)` is the whole point of `get_call_var_uops` and a
`CONST/0` printing identically for every constant is how `decomp`'s `f2f_dt[fr]` fixture
defect survived as a finding for a session.

`littlegrad/engine/realize.py` HAS DRIFTED SINCE THE PIN `ad117c928^`. MEASURED:
`git diff --stat 'ad117c928^' HEAD -- tinygrad/engine/realize.py` is `15 insertions(+),
14 deletions(-)`, the working-tree blob hashes to `16d0d413a494153a794cf4033992909563c44c50`
and that equals `git rev-parse 'ad117c928:tinygrad/engine/realize.py'`, NOT the pin's
`54610743bfa50c532cf87b27cfedf596087a994d`. So HEAD is this project's own re-vendor and
`ad117c928^` is the pin. **THE ONE PIECE OF THAT DRIFT THAT TOUCHES A PORTED ARM IS
`_resolve`'s `Ops.GETADDR`**, and it is the gate's one FINDING: HEAD's `realize.py:129`
is `if b.op in (Ops.MSELECT, Ops.SHRINK, Ops.BITCAST, Ops.GETADDR)` and the port's
`rz_arm` (realize.bend:1048) has NO `OpsGETADDR` arm, so the port answers a GETADDR
argument UNCHANGED where HEAD resolves through it. UNDER THE PIN THAT ARM DOES NOT EXIST
(`git show 'ad117c928^:tinygrad/engine/realize.py'` line 129 reads
`if b.op in (Ops.MSELECT, Ops.SHRINK, Ops.BITCAST):`), so the port's five arms are exactly
CPython's five arms under the pin. The gate therefore declares the GETADDR rows and says
IN THE REPORT that the pin is where they vanish.
"""

from tinygrad.dtype import dtypes, AddrSpace, DType
from tinygrad.uop.ops import (UOp, Ops, ParamArg, KernelInfo, ProgramInfo, CallInfo,
                              CustomFunction, AxisType)
from tinygrad.helpers import prod
import tinygrad.engine.realize as RZ

# ============================================================ THE FIXTURE
# `main_arena` (realize.bend:1701-1744) index for index, then 22 nodes the port's own
# fixture LACKS and that its dispatch arms need -- each named by the arm it exists for.
# Slot 0 is `Arena.bottom()` on the port and has NO CPython counterpart, so the lane
# emits `bottom` there and the gate declares those 15 rows as one class.
def _buf(slot, nm):
    # realize.bend:1552 `buf_arg`. `buffer=Some{0}` is the port's index into a device
    # buffer table and CPython's `ParamArg.buffer` is a REALIZED `Buffer`; nothing in
    # realize.py's readers reads it, so this lane leaves it None and the gate says so.
    return _buf_dev(slot, nm, "CPU")


def _buf_dev(slot, nm, dev):
    """`device` IS THE ONE FIELD `_buf` CANNOT HARD-CODE, because `rs_x64` needs a TUPLE
    and a tuple of device NAMES is data: `ParamArg.device` is `str | tuple[str, ...]`
    (`ops.py:611`), so `("DISK","CPU")` opens nothing. MEASURED, calling `realize.py`'s own
    `get_call_kernels` on such a `ParamArg`: n=2, first fields `('DISK','CPU')`."""
    return ParamArg(slot, dtypes.int32, 16, name=nm, addrspace=AddrSpace.GLOBAL, device=dev)


def _var(slot, nm):
    return ParamArg(slot, dtypes.int32, None, vmin_vmax=(0, 4), multiple_of=1, name=nm,
                    addrspace=AddrSpace.ALU)


def _bnd(slot, nm):
    return ParamArg(slot, dtypes.int32, None, vmin_vmax=(0, 4), multiple_of=1, name=nm,
                    addrspace=AddrSpace.ALU, val=4)


def _ki(nm, beam):
    # `KernelInfo` is FIVE fields (`ops.py:1342-1347`: name, applied_opts, opts_to_apply,
    # estimates, beam) and `realize.bend:1525` records the port as carrying FOUR, because
    # `Estimates` is `renderer/__init__.py:16` -- P5. MEASURED: `KernelInfo(nm, (), None,
    # beam)` POSITIONALLY puts the beam into `estimates` and leaves `beam` at 0, so
    # `pm_beam`'s `sink.arg.beam == 0` guard fired on node 24 whose sink carries beam 2,
    # and `beam_24` read as a PORT divergence when it was the ORACLE's fixture. That is
    # `tn_bitwise_not`'s post-mortem a third time, and the keyword is the whole repair.
    return KernelInfo(nm, (), None, None, beam)


def _pi(vs, gs, os_, is_):
    return ProgramInfo((4, 1, 1), (1, 1, 1), tuple(vs), tuple(gs), tuple(os_), tuple(is_))


def _call(nm, *s):
    return UOp(Ops.CALL, src=s, arg=CallInfo(None, nm, False, False, None))


# `B[i]` is the node at arena slot i. THE INDEX IS THE ARENA'S, NOT THE LIST'S: Bend's
# `Arena.empty` spends slot 0 on `bottom()`, so a node minted Nth here sits at slot N.
# **THIS PARAGRAPH USED TO SAY `_add` RETURNS THE SLOT AND THE DOCSTRING BELOW SAYS IT
# RETURNS THE NODE, AND THE CODE RETURNS THE NODE** -- the same shape as the SRC_BODY
# header, which listed a fix at two sites when only one of them had a row behind it. The
# slot is `len(B)-1` AFTER the append, so a later node is named by the LOCAL it was bound
# to and never by a subscript: `B[26]` does not exist yet when `B[27]`'s own `src` is
# evaluated, which is why every reference below is a local.
B = [None]


def _add(u):
    """APPEND AND RETURN THE NODE. The slot is `len(B)-1` after the call and is named in
    the comment on each line; returning the node is what makes `src=(p0, g0, g1)` mean
    what it says -- an earlier draft returned the SLOT and every CALL came out carrying
    the integers `11, 2, 3` as its `src`, which `get_call_arg_uops` reported as
    `AttributeError: 'int' object has no attribute 'is_bound_var'` on all 18 CALL nodes.
    A fixture that silently built the wrong graph is not a fixture, so this is written
    down rather than just fixed."""
    B.append(u)
    return u


c3 = _add(UOp.const(3))                                                       # 1
g0 = _add(UOp(Ops.PARAM, src=(), arg=_buf(0, "g0")))                          # 2
g1 = _add(UOp(Ops.PARAM, src=(), arg=_buf(1, "g1")))                          # 3
vn = _add(UOp(Ops.PARAM, src=(), arg=_var(2, "n")))                           # 4
bn = _add(UOp(Ops.PARAM, src=(), arg=_bnd(2, "n")))                           # 5
vm = _add(UOp(Ops.PARAM, src=(), arg=_var(3, "m")))                           # 6
k1 = _add(UOp(Ops.SINK, src=(), arg=_ki("k1", 0)))                            # 7
k2 = _add(UOp(Ops.SINK, src=(), arg=_ki("k2", 2)))                            # 8
b0 = _add(UOp(Ops.BUFFER, src=(c3,), arg=_buf(0, "g0")))                      # 9
b1 = _add(UOp(Ops.BUFFER, src=(c3,), arg=_buf(1, "g1")))                      # 10
p0 = _add(UOp(Ops.PROGRAM, src=(k1,), arg=_pi((), (0, 1), (0,), (1,))))       # 11
pv = _add(UOp(Ops.PROGRAM, src=(k1,), arg=_pi((vn,), (0, 1), (0,), (1,))))    # 12
pm_ = _add(UOp(Ops.PROGRAM, src=(k1,), arg=_pi((vm,), (0, 1), (0,), (1,))))   # 13
st = _add(UOp(Ops.STORE, src=(g0, g1), arg=_pi((), (0,), (0,), (1,))))       # 14
cfv = _add(UOp.custom_function("validate", k1))                              # 15
cfe = _add(UOp.custom_function("encdec", k1))                                # 16
cP = _add(_call("f", p0, g0, g1))                                            # 17
cS = _add(_call("g", st, g0, g1))                                            # 18
cH = _add(_call("h", pv, g0, bn))                                            # 19
cM = _add(_call("i", pm_, g0, vm))                                           # 20
cV = _add(_call("j", cfv, g0, g1))                                           # 21 validate
cE = _add(_call("k", cfe, g0, g1, vn))                                       # 22 encdec
cK0 = _add(_call("l", k1, g0))                                               # 23 beam 0
cK2 = _add(_call("m", k2, g0))                                               # 24 beam 2
cB = _add(_call("o", p0, b0, b1))                                            # 25 BUFFER args
l1 = _add(UOp(Ops.LINEAR, src=(cP,), arg=None))                              # 26
l2 = _add(UOp(Ops.LINEAR, src=(l1, cS), arg=None))                           # 27 nested
rg = _add(UOp.range(4, (0,), AxisType.DEVICE))                             # 28
kd = _add(UOp(Ops.SINK, src=(rg,), arg=_ki("kd", 0)))                        # 29
pD = _add(UOp(Ops.PROGRAM, src=(kd,), arg=_pi((), (0, 1), (0,), (1,))))      # 30
cD = _add(_call("z", pD, g0, g1))                                            # 31 DEVICE axis
dn = _add(UOp(Ops.PARAM, src=(), arg=_var(9, "_device_num")))                 # 32
kp = _add(UOp(Ops.SINK, src=(dn,), arg=_ki("kp", 0)))                        # 33
pN = _add(UOp(Ops.PROGRAM, src=(kp,), arg=_pi((), (0, 1), (0,), (1,))))      # 34
cN = _add(_call("y", pN, g0, g1))                                            # 35 _device_num
l3 = _add(UOp(Ops.LINEAR, src=(k1,), arg=None))                              # 36
sy = _add(UOp(Ops.SOURCE, src=(), arg="y"))                                  # 37
by = _add(UOp(Ops.BINARY, src=(), arg=b"a"))                                 # 38
pK = _add(UOp(Ops.PROGRAM, src=(k1, l3, sy, by), arg=_pi((), (0, 1), (0,), (1,))))  # 39
cK = _add(_call("p", pK, g0, g1))                                            # 40 compiled
bc = _add(UOp(Ops.BITCAST, src=(g1,), arg=dtypes.int32))                     # 41
# ---- the 22 nodes `main_arena` lacks, each named by the arm it exists for ----
c1 = _add(UOp.const(1))                                                          # 42
c0 = _add(UOp.const(0))                                                          # 43
c2 = _add(UOp.const(2))                                                          # 44
sh = _add(UOp(Ops.SHRINK, src=(b0, c0, c2), arg=None))                           # 45 rz_arm SHRINK
ms = _add(UOp(Ops.MSELECT, src=(b0,), arg=0))                                    # 46 rz_arm MSELECT
ga = _add(UOp(Ops.GETADDR, src=(b0,), arg="CPU"))                                # 47 HEAD's GETADDR
msk = _add(UOp(Ops.MSTACK, src=(g0, g1), arg=None))                              # 48 rz_arm MSTACK
cVs = _add(_call("vs", k1, g1, sh))                                              # 49 SHRINK as arg
cVm = _add(_call("vm", k1, g1, ms))                                              # 50 MSELECT as arg
cVg = _add(_call("vg", k1, g1, ga))                                              # 51 GETADDR as arg
cVk = _add(_call("vk", k1, g1, msk))                                             # 52 MSTACK as arg
_ss = _add(_call("ss", k1, k1))                                                  # 53 two SINK args
kn = _add(UOp(Ops.SINK, src=(), arg=None))                                       # 54 SINK w/o KernelInfo
cNk = _add(_call("nk", kn, g0))                                                  # 55 gcc default arm
pN2 = _add(UOp(Ops.PROGRAM, src=(kn,), arg=_pi((), (0, 1), (0,), (1,))))         # 56 PROG w/o KI
cNb = _add(_call("nb", pN2, b0, b1))                                             # 57 name default arm
l4 = _add(UOp(Ops.LINEAR, src=(cVk, cVs), arg=None))                             # 58 nested LINEAR
pM = _add(UOp(Ops.PROGRAM, src=(k1,), arg=_pi((), (0, 1, 2), (2,), (1,))))       # 59 outs -> MSELECT
cMb = _add(_call("mb", pM, b0, b1, ms))                                          # 60 wbuf MSELECT wall
cVb = _add(_call("vb", k1, g0, bc))                                              # 61 BITCAST as arg
# THE GETADDR OVER A **PARAM**, AND IT IS THE POINT OF THE NODE. `ops.py:844` builds
# `UOp(Ops.GETADDR, src=(self,), ...)` and `self` is a PARAM as often as a BUFFER. A
# GETADDR over a BUFFER is INVISIBLE to this census on purpose-shaped nodes: HEAD
# `_resolve` recurses into `src[0]`, `_resolve(BUFFER)` returns it unchanged, the
# rebuilt GETADDR is content-identical and hash-conses -- MEASURED: with only node 47 in
# the fixture, `res_51` AGREES on both sides. Over a PARAM, `inputs[b.arg.slot]` fires
# and the two sides part. So without this pair the vendored-drift answer would be a
# claim about a diff rather than a measurement.
gv = _add(UOp(Ops.GETADDR, src=(g0,), arg="CPU"))                               # 62 GETADDR over PARAM
# AND THE CALL CARRIES THE THIRD CONSTANT TOO, so that NO SLOT IN THIS ARENA IS
# UNREFERENCED. MEASURED before this line: the census fixture had ONE dead node,
# slot 42's `CONST 1`, which nothing referenced -- a root-walking printer cannot see
# that, and this lane ROWS EVERY SLOT BY INDEX rather than walking from a root, so it
# could: `res_42` was a row answering a node nothing in the graph points at. Every
# (`run_linear` iterates `linear.src`, `lower_and_compile` walks `linear.toposort()`),
# so "unreferenced" is a fact about roots and not about garbage.
cVv = _add(_call("vv", k1, g1, gv, c1))                                         # 63 GETADDR as arg
# THE MULTI-DEVICE BUFFER AND THE CALL WHOSE `src[1]` IS IT -- the answer `kern` had no row
# for. `realize.py:41` is `[(d, call, None) for d in to_tuple(call.src[1].device)]` and
# `to_tuple` (`helpers.py:52`) is `x if isinstance(x, tuple) else (x,)`, so a device that is
# a TUPLE puts more than one kernel in the answer. Every device above is the scalar "CPU",
# so all 22 `kern_*` rows were lists of length 0 or 1 and the COUNT that both lanes print
# was only ever tested on a list that could not surprise it. `Port: S.Dn{[6, 0]}` -- DISK
# and not-DISK, per `device.bend:344`'s `tag_of` -- so a dropped or a duplicated device
# moves the count, and the two tags are distinct on purpose. NOTHING IS OPENED.
g2 = _add(UOp(Ops.BUFFER, src=(c3,), arg=_buf_dev(3, "g2", ("DISK", "CPU"))))       # 64
cDm = _add(_call("dm", p0, g2))                                                    # 65 two devices

NODES = len(B) - 1     # 65 real nodes, slots 1..65; slot 0 is the port's bottom
assert NODES == 65, NODES

# THE DRIVER AXIS, DECLARED ONCE, IN THE ORDER `gatekit` DIFFS THE LANES BY. It was
# written out FOUR times -- the two `__main__` loops and the `drive` ladder, plus the
# gate's own `DRV` -- and `gates/realize_graph_census-gate.py` read NONE of them back, so a
# driver that existed on one side only was a population the instrument could not see. The
# gate now LOADS THIS TUPLE BY PATH and checks it against all three of the bend lane's own
# dispatch tables (`axis_hold`). ONE declaration, four readers.
DRIVERS = ("arg", "nb", "res", "flat", "val", "beam", "bea0", "oi", "wbuf", "kern",
           "name", "est", "var", "gcc", "dnum")

# THE 15 OP TAGS THE PORT DISPATCHES ON, one row each: `arm_<OP>` is the NUMBER OF
# FIXTURE NODES whose op is that tag. It is the population's own coverage row -- the
# claim that every arm the port spells has a node that reaches it -- and both lanes
# measure it from their own nodes, so a fixture that lost an op moves it.
ARMS = ("PROGRAM", "STORE", "CUSTOM_FUNCTION", "RANGE", "PARAM", "SINK", "LINEAR",
        "MSELECT", "SHRINK", "BITCAST", "MSTACK", "GETADDR")

# THE CALL-ONLY RULE IS CPYTHON'S AND IT IS A FROZENSET OF `DRIVERS`, not a second list:
# a member that was not in `DRIVERS` would be a driver nobody drives, and `axis_hold`
# checks the set against the bend lane's own `rs_call_only` table.
CALL_ONLY = frozenset(d for d in DRIVERS if d in
                      ("oi", "wbuf", "kern", "name", "est", "var", "gcc", "dnum", "nb"))


# ============================================================ THE SIGNATURES
# THE PARAM/BUFFER SLOT IS THE `@<slot>` SUFFIX, AND IT IS NOT COSMETIC. `realize.py:131`
# is `inputs[b.arg.slot]`, so the SLOT is the mechanism every `res` row exercises and it
# is in NO node shape: `PARAM/0` and `PARAM/1` print alike, and this fixture's `inputs`
# are `(b1, b0)` -- two BUFFERs, slot 1 and slot 0 -- which print ALIKE too. MEASURED on
# the lane this replaces: a port reading `slot`, `slot+1` or a literal `0` would answer
# `BUFFER/1` on every `res` row and agree with CPython on all 63 of them.
def _ids(xs) -> str:
    """`a,b,c`, and `-` for empty -- the SAME token `oi_sig` prints for an empty index list
    (`realize.py:24-27` answers `()`), so an absent list and an empty one are one row on
    both lanes rather than two spellings of one answer."""
    return ",".join(str(x) for x in xs) if xs else "-"


# ============================================================ THE `arg` PAYLOAD
# `[...]` ON EVERY NODE WHOSE `arg` IS NOT `None`, AND IT IS NOT COSMETIC.
#
# THE HOLE, MEASURED, NOT ASSERTED: over this fixture's own 65 nodes the previous token
# spelled **32 DISTINCT TOKENS FOR 65 NODES**, so 147 of the 2080 node pairs printed
# IDENTICALLY -- fifteen CALLs as `CALL/3`, seven PROGRAMs as `PROGRAM/1`, three SINKs as
# `SINK/0`, two PARAMs as `PARAM/0@2` (`.agents/slop/realizegaps/collide.py`). Two nodes
# that print alike are two nodes a reader can confuse, in every row that carries either.
#
# THE SPELLING IS THE SIBLING'S, NOT A NEW ONE. `gates/crp_graph_census-oracle.py`'s `tok`
# and `gates/decomp_graph_census-oracle.py`'s print `OP/NSRC[TARGET]` -- the payload INSIDE
# the token -- and `gates/md_graph_census.bend` appends ` arg=`; the bracket is the one that
# travels PER NODE rather than on a root, and this census's token is per node. The test is
# ON THE ARG and not on the op, so a fourth op that ever grows a `ParamArg` is printed by
# this and not by a list of ops that would rot beside it.
#
# `UOp.arg` IS `Any` AND THE PORT'S IS A 24-CONSTRUCTOR SUM (`ops.bend:1190`), so this side
# needs `u.op is Ops.CONST` where the port needs nothing: a CONST's arg is a BARE `int` at
# HEAD and an MSELECT's shard index is a bare `int` too (`ops.py:769`), and only the op
# separates them. That asymmetry is the price of CPython's `Any` and is named here rather
# than papered over with a table.
def apay(u) -> str:
    """THE ARG'S PAYLOAD IN BRACKETS, or `""` when the arg IS `None` -- there is nothing to
    print and `s1` used to print nothing for it either."""
    a = u.arg
    if u.op is Ops.CONST:
        return "[%d]" % a
    if isinstance(a, ParamArg):
        # NAME : VAL, AND NOT THE OTHER ELEVEN FIELDS. `slot` is `@<slot>` above, `val` is
        # `is_bound_var` (`ops.py:1023`) AND `UOp.const(s.arg.val)` (`realize.py:18`), and
        # `name` is `s.expr` (`ops.py`) AND `has_dnum`'s `_device_num` test (`realize.py`:
        # 139). The nine omitted: `device` has NO SHARED SPELLING (a CPython NAME against a
        # port TAG -- `Device.tag` does not exist in this tree, see `kern_blind_holds`),
        # and `dtype`, `size`, `vmin_vmax`, `multiple_of`, `addrspace`, `volatile`, `image`
        # and `buffer` are constant or unread across all nineteen of this fixture's
        # `ParamArg`s -- MEASURED, every one is `dtypes.i32`, `addrspace` is GLOBAL on the
        # eleven buffer args and ALU on the four var args, and `size` is `16` or absent.
        return "[%s:%s]" % ("-" if a.name is None else a.name,
                         "-" if a.val is None else a.val)
    if isinstance(a, KernelInfo):
        # NAME : BEAM, and the BEAM is why this arm exists: `rz_kernel_beam` reads it and
        # `pm_beam` writes it, so `k1` (beam 0) and `k2` (beam 2) printed `SINK/0` ALIKE in
        # every cone, and `gates/realize_graph_census-mutate.py`'s `X5` -- `k2`'s beam 2 ->
        # 5, on BOTH fixtures -- was declared VACUOUS for exactly that reason.
        # `estimates` IS DELIBERATELY ABSENT: `ops.bend` DROPS the field (`Estimates` is
        # `renderer/__init__.py:16`, P5), so there is nothing on the port side to print and
        # a value there would be this lane's fixture talking to itself.
        return "[%s:%d]" % (a.name, a.beam)
    if isinstance(a, ProgramInfo):
        # VARS ; GLOBALS ; OUTS ; INS -- the four fields `realize.py` reads
        # (`get_call_outs_ins` :24-27 and `get_call_var_uops` :18) plus `globals`, which is
        # `realize.py:139`'s walk over `prg.arg.globals`. A var is printed by its NAME and
        # not by its slot, because `get_call_var_uops` keys `bound` on `s.expr` -- THE NAME
        # -- and `vars` is in no node shape at all, so a program holding the wrong variable
        # used to print identically. `global_size`/`local_size` are `4,1,1`/`1,1,1` on all
        # nine and no `realize.py` reader touches them.
        return "[%s;%s;%s;%s]" % (_ids([v.arg.name for v in a.vars]), _ids(a.globals),
                                  _ids(a.outs), _ids(a.ins))
    if isinstance(a, CallInfo):
        # `-` FOR AN ABSENT NAME, NOT `None`, AND THE PORT SPELLS THE ABSENCE THE SAME WAY:
        # `rs_opt_str` prints `-` for a `Maybe<&2, String>`'s `None`, and the two sides
        # differing on an ABSENCE would be a divergence manufactured by the printer.
        # MEASURED WHY IT MATTERS HERE: CPython's OWN `_validate` body mints unnamed calls
        # (`CallInfo(None, None, ...)`), so `val_*`'s py cones carry `CALL/3[None]` --
        # thirteen occurrences on the CPython lane and none on the port's, because the port
        # answers the claim bit (VAL_BODY) and builds no cone at all.
        return "[%s]" % ("-" if a.name is None else a.name)
    if isinstance(a, CustomFunction):
        return "[%s]" % a.name
    if isinstance(a, DType):
        # crp's arm, verbatim: `Ops.BITCAST`'s arg IS the target dtype (`ops.py:846`).
        return "[%s]" % a.name
    if isinstance(a, tuple):
        # `Ops.RANGE`: `(axis_type, *dims)` (`ops.py:201`'s key). `d` or `-` for the axis
        # and the dimension ids after it; crp's `addrstr` is the same one-Bool-per-choice
        # shape for `AddrSpace`. RESIDUAL, STATED: the other seven CPython axes and the
        # port's two bend-only ones (`AXIS_REDUCE`, `AXIS_UNROLL`) all print `-`, and this
        # fixture has exactly ONE RANGE, so nothing here can be wrong.
        return "[%s%s]" % ("d" if a[0] is AxisType.DEVICE else "-", _ids(a[1]))
    if isinstance(a, str):
        # `Ops.GETADDR`'s arg is a DEVICE NAME and `Ops.SOURCE`'s is TEXT, and the port's
        # GETADDR arg is `ADev{S.D1{tag}}` -- a TAG (`ops.bend:7815`) with no CPython
        # counterpart, because `Device.tag` does not exist in this tree (`kern_blind_holds`
        # measures that). So this is the ONE arm that needs an op test, and printing it
        # anyway takes five rows red: `arg_51`, `arg_63`, `beam_51`, `beam_63`, `res_51`.
        # It is Box 1's blindness inside the payload rather than beside it.
        return "" if u.op is Ops.GETADDR else "[%s]" % a
    if isinstance(a, bytes):
        return "[%s]" % _ids(a)
    if isinstance(a, int):
        return "[%d]" % a
    if a is None:
        return ""
    # AN ARG KIND NEITHER LANE SPELLS. It is bracketed as `?` and
    # `gates/realize_graph_census-gate.py`'s `argkinds_hold` requires that no promoted lane
    # contains one -- so a fixture node carrying an unspelled kind is a RED RUN and not a
    # silently degenerate token.
    return "[?]"


def s1(u) -> str:
    """`OP/arity`, `@<slot>` for a PARAM or a BUFFER, and `[<the Arg payload>]`."""
    base = "%s/%d" % (u.op.name, len(u.src))
    if isinstance(u.arg, ParamArg):
        base += "@%d" % u.arg.slot
    return base + apay(u)


# THE FIVE `_resolve` VIEW OPS (realize.py:129-131 plus HEAD's `Ops.GETADDR`). A view
# op's answer is a REBUILD, so `s1` alone cannot see the swap: `SHRINK(resolved, 0, 2)`
# and `SHRINK(b0, 0, 2)` are both `SHRINK/3`. ONE more level -- the rebuilt `src[0]` --
# is what makes `inputs[b.arg.slot]` vs `b` visible, which is the whole measurement of
# `realize.py:131`. `rng_graph_census-gate.py` names the failure this is the repair of:
# `gr_10` printed identically on both sides until a deep printer was used.
VIEWS = (Ops.MSELECT, Ops.SHRINK, Ops.BITCAST, Ops.MSTACK, Ops.GETADDR)


def s2(u) -> str:
    return s1(u) + "<-" + s1(u.src[0]) if u.op in VIEWS else s1(u)


def lst(xs) -> str:
    return "+".join(s2(x) for x in xs) if xs else "none"


def cone(roots) -> str:
    """DFS PRE-ORDER over every root, each node ONCE by identity, parent before child.
    THE WHOLE CONE, never a prefix -- `rng_graph_census-gate.py` records the node-swap
    this instrument would otherwise miss."""
    out, seen = [], set()

    def go(v):
        if id(v) in seen:
            return
        seen.add(id(v))
        out.append(v)
        for s in v.src:
            go(s)
    for r in roots:
        go(r)
    return ",".join(s1(u) for u in out)


def pair(xs) -> str:
    return ",".join(str(x) for x in xs) if xs else "-"


def oi_sig(o, i) -> str:
    return "o=%s;i=%s" % (pair(o), pair(i))


def rewrite_sig(pm, u, ctx=None) -> str:
    """`PatternMatcher.rewrite` with the engine's OWN two excusions: `None` (and the
    `ret is uop` identity of `ops.py:1618`) both mean "no rewrite", and anything else is
    an answer CPython could not give."""
    try:
        r = pm.rewrite(u, ctx) if ctx is not None else pm.rewrite(u)
    except Exception as e:                                   # noqa: BLE001 -- a raise IS the answer
        return "raise=%s" % type(e).__name__
    return "0" if r is None or r is u else "1:" + cone([r])


# `pm_beam`'s COMPILED BODY, i.e. `realize.py:218`'s lambda as CPython's own matcher built
# it. `PatternMatcher` has no public "did the rule claim" entry point -- `rewrite`
# (`ops.py:1613-1619`) is `if (ret:=match(uop, ctx)) is not None and ret is not uop:
# return ret`, which collapses "did not claim" and "claimed and the answer IS the input"
# into the same `None`. `pdict[Ops.CALL][0][1]` is that same `match`, one call up, so
# asking it is CPython's own code answering and NOT a transcribed predicate: the second
# transcription this lane would otherwise have needed (`dnum_sig`) stays the only one.
# MEASURED, `.venv/bin/python`, over every fixture shape: a non-CALL answers `None`
# without raising, a SINK carrying beam 2 answers `None`, a CALL over a bodyless SINK
# raises `AttributeError`, and at ctx 0 over a zero-beam SINK it returns the node itself.
BEAM_BODY = RZ.pm_beam.pdict[Ops.CALL][0][1]


def beam_sig(u, ctx) -> str:
    """`pm_beam`'s answer as TWO BITS -- `<claim><fired>` -- plus the BEAM, because a cone
    cannot see it. `realize.py:219` is `sink.replace(arg=replace(sink.arg, beam=ctx))` and
    `KernelInfo.beam` is in NO node shape, so `beam_2 -> beam_7` rewrites a cone that
    prints identically -- MEASURED: with `beam` printed nowhere, `beam_24` read as a port
    divergence on a graph the two sides agreed about node for node.

    `00` the rule did not claim · `10` it claimed and the rewrite was the identity, which
    is what `ret is not uop` drops and what the port's `M.hop_self` turns into index 0 ·
    `11` it claimed and produced a new node. THE SINGLE `"0"` this lane used to print for
    both `00` and `10` is what made mutation `V2` (`rz_kernel_beam`'s no-`KernelInfo`
    default `0` -> `1`) move zero rows at rc=0: the default is read only by the CLAIM, and
    the only node that reads it is the one whose rewrite is the identity."""
    try:
        claim = BEAM_BODY(u, ctx) is not None
        r = RZ.pm_beam.rewrite(u, ctx)
    except Exception as e:                                   # noqa: BLE001
        return "raise=%s" % type(e).__name__
    if not claim:
        return "00"
    if r is None or r is u:
        return "10"
    return "11:%s:b=%d" % (cone([r]), r.src[0].arg.beam)


def dnum_sig(call) -> str:
    """`realize.py:139` written out -- the ONE transcribed predicate in this lane, and
    the one thing here that is not a call into the module. `has_dnum` is an inline
    `any(...)`, so there is no function to call; the expression is COPIED and
    `classes_hold` pins its answer on a node that reaches each of the two arms."""
    try:
        hit = any((x.op is Ops.RANGE and x.axis_type is AxisType.DEVICE) or
                  (x.op is Ops.PARAM and x.arg.name == '_device_num')
                  for x in call.body.toposort())
    except Exception as e:                                   # noqa: BLE001
        return "raise=%s" % type(e).__name__
    return "1" if hit else "0"


def nb_sig(call) -> str:
    """`realize.py:60` written out: `prod(call.src[1].shape) * call.src[1].dtype.itemsize`."""
    try:
        s = call.src[1]
        return str(prod(s.shape) * s.dtype.itemsize)
    except Exception as e:                                   # noqa: BLE001
        return "raise=%s" % type(e).__name__


# ============================================================ THE DRIVERS
def drive(drv: str, u):
    """One driver, one node, one SIGNATURE. Every refusal is a row."""
    if drv in CALL_ONLY and u.op is not Ops.CALL:
        return "notacall"
    try:
        if drv == "arg":
            return lst(RZ.get_call_arg_uops(u))
        if drv == "var":
            return lst(RZ.get_call_var_uops(u, u.body))
        if drv == "oi":
            o, i = RZ.get_call_outs_ins(u)
            return oi_sig(o, i)
        if drv == "wbuf":
            return lst(RZ.get_call_written_bufs(u))
        if drv == "kern":
            # THE COUNT, AND NOT THE LIST, FOR THE REASON `rs_d_kern` GIVES AT LENGTH: the
            # answer's `d` is a device NAME (or a tuple of them, or `None`) and the port's
            # is a TAG, and there is no table to convert between them -- `Device.tag` does
            # not exist in this tree (`hasattr(Device, 'tag')` is False) and the port's only
            # tag/name function is `device.bend:344`'s three-valued sentinel. So this lane
            # prints the LENGTH, the port prints the LENGTH, and `gates/realize_graph_census-gate.py`'s
            # `kern_blind_holds` measures the residual rather than asserting it away.
            # `dm` (node 65) is a CALL whose `src[1]` is a TWO-device BUFFER, so `len` is
            # finally tested on a list of length 2 rather than only 0 and 1.
            return str(len(RZ.get_call_kernels(u)))
        # THE NAME IS CPython's, ANSI INCLUDED -- `get_call_name` wraps the STORE and
        # `encdec` arms in `colored(...)` (realize.py:49-50) and the port has no
        # `colored`. Those arms are declared divergences and the escape codes are part of
        # their pinned content, so nothing is stripped: a gate that normalised the colour
        # would be comparing a lane against a lane it had itself edited.
        if drv == "name":
            a = RZ.get_call_name(u, [])
            return "none" if a is None else a
        if drv == "est":
            e = RZ.estimate_uop(u)
            return "1" if e.mem else "0"
        if drv == "gcc":
            return "0" if RZ._get_call_to_compile(u) is None else "1"
        if drv == "dnum":
            return dnum_sig(u)
        if drv == "nb":
            return nb_sig(u)
        if drv == "res":
            # `inputs` ARE THE TWO BUFFERS, IN REVERSE, and that is a PRINTER decision and not a
            # convenience: both `g0` and `g1` are `PARAM/0`, so a slot lookup of either one
            # prints `PARAM/0` and `inputs[b.arg.slot]` becomes invisible -- MEASURED: with
            # `inputs=(g1, g0)` the GETADDR row `res_63` AGREED on both sides and the whole
            # vendored-drift answer hid inside it. Over two BUFFERs, slot 0 answers one
            # BUFFER and the port's un-resolved GETADDR answers a PARAM, and the two part.
            return lst(RZ.resolve_params(u, (b1, b0)))
        if drv == "flat":
            return rewrite_sig(RZ.pm_flatten_linear, u)
        if drv == "val":
            return rewrite_sig(RZ.pm_validate, u)
        if drv == "beam":
            return beam_sig(u, 7)
        if drv == "bea0":
            return beam_sig(u, 0)
    except Exception as e:                                   # noqa: BLE001 -- a raise IS an answer
        return "raise=%s" % type(e).__name__
    return "raise=NoDriver"


# ============================================================ THE ROWS
if __name__ == "__main__":
    # THE COUNT, PRINTED, so a lane that stopped emitting a row cannot pass unnoticed.
    # `arena_n` is the fixture's SIZE and `rows` is what this lane is about to print:
    # 2 header + 15 bottoms + 12 arm-coverage + 15 drivers x NODES.
    print("arena_n=%d" % (NODES + 1))
    print("rows=%d" % (2 + len(DRIVERS) + len(ARMS) + len(DRIVERS) * NODES))
    # THE BOTTOM, once per driver. Slot 0 is `Arena.bottom()` (`Arena.empty` spends it),
    # and CPython's UOp metaclass has no such node, so there is nothing to compare and the
    # row exists to say so rather than to hide it.
    for drv in DRIVERS:
        print("b_%s=bottom" % drv)
    # THE ARM COVERAGE, one row per op tag the port dispatches on: the number of fixture
    # nodes carrying it. A tag with no node is an arm no row can reach.
    for tag in ARMS:
        print("arm_%s=%d" % (tag, sum(1 for n in range(1, NODES + 1) if B[n].op.name == tag)))
    # EVERY (DRIVER, NODE) PAIR IS EMITTED, refusals included, so the two lanes carry the
    # same row count BY CONSTRUCTION and no exclusion list is needed to make them meet.
    for drv in DRIVERS:
        for n in range(1, NODES + 1):
            print("%s_%d=%s" % (drv, n, drive(drv, B[n])))