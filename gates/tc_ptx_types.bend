# tc_ptx_types.bend -- the PTX dtype tables, for every dtype a kernel can carry.
#
#   .venv/bin/python gates/tc_ptx_types-gate.py
#
# SIXTY ROWS, THREE LANES -- `types`, `mem_types` and `cast_types` (ptx.py:156-161) over
# all TWENTY dtypes, twelve of which are CPython's keys and eight of which are the ones
# CPython's dict does NOT have and therefore `KeyError`s on. The claim is per row and it
# is the claim the bug made false: **a dtype CPython refuses must never get a CONCRETE,
# COMPILABLE PTX type out of these tables**, because `pred` and `u8` are types `ptxas`
# accepts and the resulting kernel is silently corrupt -- strictly worse than the empty
# field, which it refuses.
#
# `EMPTY` is not a value any table returns. It is how this driver spells `""`, so a
# refusal is a TOKEN in the diff and not a line that quietly got shorter -- the same
# reason `tc_ptx.bend`'s `btab()` spells `\` + `t` and not a real TAB (M43).
#
# THE POPULATION IS 20 AND NOT 12 because `dtypes.all` (17) plus `DType.weaks` (2) plus
# `dtypes.void` is 20, and the eight misses are in it. Two of them -- `weakint` and
# `weakfloat` -- are the reachable ones: MEASURED, `UOp.range(4,0).dtype` is `weakint`
# and `UOp(ADD, (const(3.0), const(4.0))).dtype` is `weakfloat`, while CONSTs (the only
# other weak-dtype carriers) are skipped at ptx.py:187.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/renderer/tc.bend as T
import ./../tinybendygrad/renderer/tc_ptx.bend as P

def show(+s: String) -> String: Bool.pick(String, String.is_empty(s), "EMPTY", s)

# ONE TABLE, TWENTY DTYPES, and the table is a TAG rather than a function because Bend
# has no closures (rule 31). The three reads are pure and cheap, so all three are taken
# and the tag picks which one is printed.
def row1(+t: String, +d: S.Dt) -> String:
  +k = String.concat([t, "_", T.dt_name(d), "="])
  +a = show(P.types_of(d))
  +b = show(P.mem_types_of(d))
  +c = show(P.cast_types_of(d))
  Bool.pick(String, String.eq(t, "types"), String.concat([k, a, "\n"]),
    Bool.pick(String, String.eq(t, "mem_types"), String.concat([k, b, "\n"]), String.concat([k, c, "\n"])))

def go(+t: String, +ds: List<&2, S.Dt>) -> String:
  match ds:
    case Nil{}   : ""
    case d <> +r : String.concat([row1(t, d), go(t, r)])

def dtypes20() -> List<&2, S.Dt>:
  [S.void(), S.boolean(), S.int8(), S.uint8(), S.int16(), S.uint16(), S.int32(), S.uint32(), S.int64(),
   S.uint64(), S.weakint(), S.weakfloat(), S.fp8e4m3(), S.fp8e4m3fnuz(), S.fp8e5m2(), S.fp8e5m2fnuz(),
   S.half(), S.bfloat16(), S.single(), S.double()]

# BOTH LANES PRINT IN NAME ORDER, and neither lane is told the order. `gatekit` compares
# two ordered lists, so the two lanes have to agree on one, and the only order neither of
# them can get wrong is the one each derives from the dtype's own name -- which is also
# why the CPython lane sorts by `DType.name` and this one by `T.dt_name`. MEASURED: the
# two name functions agree on all twenty (`.agents/slop/tcptxweak/names.bend`).
def dt_le(a: S.Dt, b: S.Dt) -> Bool: String.is_le(T.dt_name(a), T.dt_name(b))

def main() -> IO(Unit):
  +ds = List.sort(S.Dt, dt_le, dtypes20())
  do IO<Unit>:
    IO.print(String.concat([go("types", ds), go("mem_types", ds), go("cast_types", ds)]))