# .agents/slop/browser/ku2r.bend -- THE PORT's OWN KERNEL, IN THE SHAPE `wgsl_walk.bend` WALKS.
#
# `wgsl_walk.bend` walks `List<R>` and `wgsl.bend`'s `render_kernel` assembles the module, but every
# driver that fed it so far (`perf/gen_wgsl/*.bend`) got its `R`s from CPYTHON's uops through
# `dump_kernel.dump_uops`. So the WGSL lane had no path FROM the port's own kernel. This is that path:
# `C.KU` (the same list `cstyle` renders) -> `W.R`.
#
# TWO INDEXING FACTS, both read off the sources rather than assumed:
#   * `R.at` is 1-BASED (`wgsl_walk.bend:117`: `List.get(rs, k-1)`), and `R.srcs` are read through
#     `R.at`/`tx`, so a KU's 0-based src position becomes `src + 1`.
#   * `con_text` reads `R.f` for a FLOAT dtype (`FR.repr`) and `R.str` for everything else, and
#     `const_of` reads `R.idx` for a SPECIAL's `/* value */` comment -- so all three travel.
import Base
import ./../../../tinybendygrad/renderer/wgsl_walk.bend as W
import ./../../../tinybendygrad/renderer/cstyle.bend as C
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/helpers.bend as H
import ./../../../tinybendygrad/base.bend as FB

def plus1.go(+ss: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case h <> t: plus1.go(t, List.append(&2, U32, acc, [U32.add(h, 1)]))

def plus1(+ss: List<&2, U32>) -> List<&2, U32>: plus1.go(ss, Nil{})

def c_int(c: O.Const) -> U32:
  match c:
    case O.CInt{i}: H.lo32(i)
    case O.CBool{b}: Bool.to_u32(b)
    case _: 0

def c_f32(c: O.Const) -> F32:
  match c:
    case O.CFloat{f}: f
    case _: FB.F32.from_bits(0)

# `R.str`: the sink's name, the workitem's name, or the literal's integer text.
def r_str(a: C.KUArg) -> String:
  match a:
    case C.KASink{name}: name
    case C.KASpecial{axis, n, nm}: nm
    case C.KAConst{v}: U32.show(c_int(v))
    case C.KAParam{slot, name, volatile_, bytes}: "-"
    # `wgsl_walk.bend:322` names a range `axis_letter(R.str) ++ "idx" ++ CS.range_str(R.shape)`, so
    # the string is the AXIS's NAME (`"WEAK"`, not the letter `"L"`) and the shape is the RANGE's ids.
    case C.KARange{axis, ids}: O.AxisType.name(axis)
    case _: ""

# `R.idx`: the workitem's axis index, or the literal's value (`const_of`'s comment).
def r_idx(a: C.KUArg) -> U32:
  match a:
    case C.KASpecial{axis, n, nm}: n
    case C.KAConst{v}: c_int(v)
    case _: 0

def r_slot(a: C.KUArg) -> U32:
  match a:
    case C.KAParam{slot, name, volatile_, bytes}: slot
    case _: 0

def r_f(a: C.KUArg) -> F32:
  match a:
    case C.KAConst{v}: c_f32(v)
    case _: FB.F32.from_bits(0)

def r_shape(a: C.KUArg, +k: C.KU) -> List<&2, U32>:
  match a:
    case C.KARange{axis, ids}: ids
    case _: C.KU.shape(k)

def ku2r(+k: C.KU) -> W.R:
  W.R{C.KU.op(k), C.KU.dtype(k), C.KU.addr(k), C.KU.numel(k),
      r_str(C.KU.arg(k)), r_idx(C.KU.arg(k)), r_slot(C.KU.arg(k)),
      r_shape(C.KU.arg(k), k), plus1(C.KU.srcs(k)), r_f(C.KU.arg(k))}

def ku2r.go(+ks: List<&2, C.KU>, +acc: List<&2, W.R>) -> List<&2, W.R>:
  match ks:
    case Nil{}: acc
    case h <> t: ku2r.go(t, List.append(&2, W.R, acc, [ku2r(h)]))

def ku2r_l(+ks: List<&2, C.KU>) -> List<&2, W.R>: ku2r.go(ks, Nil{})
