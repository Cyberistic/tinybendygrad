# graphcmp-probe-optq.bend -- READ-ONLY PROBE for graphcmp.bend's three refusal atoms.
#
# IT LIVES HERE, next to graphcmp.bend, and not under `runs/graphcmp/probe/` with the other
# probes, because it is the one probe that has to IMPORT graphcmp.bend and MEASURED: bend
# rejects the path with
#     expected : an import path of plain names (letters, digits, _ and -)
#     observed : './../../../../.agents/slop/graphcmp.bend'
# because `.agents` has a DOT in it. Every other probe under runs/graphcmp/probe/ imports
# only `tinybendygrad/**`, which has no dotted directory, and gets away with it.
#
# WHY IT EXISTS. The differ's LEDGER has a row per refusal, and a row that is never
# exercised is a row nobody has tested. Three of them cannot appear in any graph the port
# can build -- no port file writes a non-empty `applied_opts` (MEASURED: the only writer is
# `KernelInfo.of()` -> `Nil{}`, and the only other reader is `engine/realize.bend:1200`
# passing it through), and no graph has ever carried a dead AxisType or a realized BUFFER
# in the pre-2026-10-03 fixtures. This probe calls the three emitters directly so their
# SPELLINGS are measured rather than assumed, and so a future rename that breaks one shows
# up here instead of in a run that silently reads 0.
import ./graphcmp.bend as G
import ./../../tinybendygrad/uop/ops.bend as O

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- IO.print(String.concat(["Q-KI-DEFAULT ", G.kernelinfo(O.KernelInfo.of())]))
    b : Unit <- IO.print(String.concat(["Q-KI-REFUSAL ", G.kernelinfo(O.KernelInfo{"plant", [7, 9], Some{[3]}, 2})]))
    c : Unit <- IO.print(String.concat(["Q-KI-OTA-None ", G.kernelinfo(O.KernelInfo{"probe", Nil{}, None{}, 0})]))
    d : Unit <- IO.print(String.concat(["Q-AXIS-LIVE   ", G.axis1(O.AXIS_WEAK{})]))
    e : Unit <- IO.print(String.concat(["Q-AXIS-DEAD   ", G.axis1(O.AXIS_REDUCE{})]))
    f : Unit <- IO.print(String.concat(["Q-AXIS-DEAD   ", G.axis1(O.AXIS_UNROLL{})]))
    g : Unit <- IO.print(String.concat(["Q-BUF-YES     ", G.bufo(Some{7})]))
    h : Unit <- IO.print(String.concat(["Q-BUF-NO      ", G.bufo(None{})]))
    i : Unit <- IO.print(String.concat(["Q-SHAPE-NONE  ", G.shape_str(None{})]))
    j : Unit <- IO.print(String.concat(["Q-SHAPE-NOSHAPE ", G.shape_str(Some{None{}})]))
    IO.pure(Unit, Unit{})
