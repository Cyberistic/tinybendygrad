# target-roundtrip.bend -- the .bend driver for `gates/target-gate.py`.
#
#   .venv/bin/python gates/target-gate.py
#
# WHAT THIS FILE SETTLES, AND IT IS THE TEST THAT WAS IMPOSSIBLE BEFORE.
# Upstream has ONE `Target` (`tinygrad/helpers.py:198`) and upstream's
# `uop/ops.py:13` and `runtime/ops_python.py:9` both IMPORT it from there. The
# port had TWO, with the same five fields and DIFFERENT identities, so a parsed
# `Target` could not go into a `ProgramInfo` at all. So the question this file
# asks is not "does the parser parse" -- that was measured, and it is in
# `helpers.bend`'s own header -- it is:
#
#   DOES A PARSED `Target` GO INTO A `ProgramInfo` AND COME BACK UNCHANGED?
#
# THE ROW IS A ROUND TRIP, NOT A PARSE. `<dev> => <before> -> <after>`, where
# `before` is the parsed record and `after` is the record read back out of a
# `ProgramInfo`. A conversion that DROPS a field shows as `a|b|c|d| -> a|b|c||`
# and a conversion that SWAPS `arch` and `iface` shows as
# `AMD|LLVM|gfx1100|usb|1 -> AMD|LLVM|usb|gfx1100|1`. Both are SILENT without
# the `->`: the five field names are the same in both halves, and only the
# ORDER of the values differs. That is why the row carries both halves.
#
# EVERYTHING IS REACHED THROUGH `H.` and `O.`, so a mutation of `helpers.bend`
# or of `uop/ops.bend` moves these rows. This file defines no `Target` of its
# own, no parser of its own and no `ProgramInfo` of its own: `rg '^def (Target|'
# over this file must find nothing, and `rg 'type Target' must find nothing.
import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O

def show(+t: H.Target) -> String:
  String.concat([H.Target.device(t), "|", H.Target.renderer(t), "|", H.Target.arch(t), "|",
    H.Target.iface(t), "|", H.Target.indices(t)])

# The `ProgramInfo` under test. Upstream's `ProgramInfo` (`ops.py:1343`) has
# seven fields and the seventh is `target: Target = Target()`; the port spells
# the global size as `H.I64` and the rest as `U32` lists, and the target is
# the parsed record.
def prog(+t: H.Target) -> O.ProgramInfo:
  O.ProgramInfo{[H.i64_of_i32(1), H.i64_of_i32(1), H.i64_of_i32(1)],
                [H.i64_of_i32(1), H.i64_of_i32(1), H.i64_of_i32(1)],
                Nil{}, Nil{}, Nil{}, Nil{}, t}

def one_of(s: String, m: Maybe<&2, H.Target>) -> IO(Unit):
  match m:
    case Some{+t}:
      IO.print(String.concat([s, " => ", show(t), " -> ", show(O.ProgramInfo.target(prog(t)))]))
    case None{}: IO.print(String.concat([s, " => REFUSED"]))

def one(+s: String) -> IO(Unit):
  one_of(s, H.Target.parse(s))

# THE DEV STRINGS. Twenty of them, and they are not a sample: between them
# they are the cases `helpers.bend`'s own header enumerates -- the `+` cut, the
# interface half's own ':', the two uppercased fields, the two refusals, the
# empty string, and the arch that is NOT uppercased. `A:B:C+AMD` is the row
# that separates the interface half from the device half, and `A::B` is the row
# that separates an empty middle field from a shifted one.
def main() -> IO(Unit):
  do IO<Unit>:
    one("")
    one("CPU")
    one("CPU:CLANG")
    one("AMD:LLVM:gfx1100")
    one("AMD:LLVM:GFX1100")
    one("cpu:clang")
    one("USB+AMD")
    one("USB:1+AMD")
    one("AMD+CPU:CLANG")
    one("A:B:C+AMD")
    one("usb:1+amd:llvm:gfx1100")
    one("A:B:C:D")
    one("A+B+C")
    one("A:B:C+D")
    one("A+B:C:D")
    one("A+B:C:D:E")
    one(":")
    one("A:")
    one("::")
    one("A::B")
