#!/usr/bin/env python3
"""D11 -- IS `codegen/late/linearizer`'s 0.0% HIT RATE A THEOREM OR A FIXTURE DEFECT?

The census (`unobservable-report.md` §1c) swapped src[0]/src[1] at both `OpsADD{}`
construction sites in `codegen/late/linearizer.bend`, applied both patches, ran
both, and 0 of 69 rows moved. It reported that as a REQUEST: "the fixture
contains no commutative node, so the fixture is the defect."

This probe SETTLES IT, and settles it the only way that counts: by CALLING
CPython. For each candidate src-swap of the fixture graph it prints the SAME 128
rows `late-oracle.py` prints and the caller diffs the whole files.

    python3 .agents/slop/order-lin-probe.py               # baseline rows
    python3 .agents/slop/order-lin-probe.py --swap=add    # ADD srcs swapped
    python3 .agents/slop/order-lin-probe.py --swap=end    # END srcs swapped
    ...

A swap whose diff is EMPTY is a PROVEN-INVISIBLE swap: no row, now or ever, can
distinguish that graph from the one the port builds. A swap with a non-empty
diff is a LIVE ORDER READ, and the rows that moved are the ones that gate it.

Usage: --swap=NAME, and --all to run every swap in one process.
"""
import os
import sys

sys.path.insert(0, '.')

SWAPS = os.environ.get("ORDER_LIN_SWAP", "")
# The construction order IS the arena index order (`put` spends the same counter
# `ops.bend`'s `Arena.empty` does), so this list is the index the port prints.
BUILT = []


def lin_fixture(swap):
  """`late-oracle.py`'s `lin_fixture`, verbatim, plus the swap knobs.

  Every swap is applied to the SOURCE tuple of ONE construction site, so the
  graph is byte-identical to the unswapped one except for that src list's order.
  """
  from tinygrad.uop.ops import UOp, Ops, KernelInfo, ParamArg
  from tinygrad.dtype import dtypes, AddrSpace
  ix, n = {}, [0]
  del BUILT[:]
  def put(name, u):
    n[0] += 1
    ix[name] = n[0]
    BUILT.append(u)
    return u
  F32, I32 = dtypes.f32, dtypes.i32

  def parg(slot, dt, addr=AddrSpace.GLOBAL, name=""):
    return ParamArg(slot=slot, dtype=dt, name=name or None, addrspace=addr)

  c1a = put("C1a", UOp.const(1, I32))
  c1  = put("C1",  c1a)
  c4a = put("C4a", UOp.const(4, I32))
  c4  = put("C4",  c4a)
  c16a = put("C16a", UOp.const(16, I32))
  c16 = put("C16",  c16a)
  sp  = put("SP",   UOp(Ops.SPECIAL, (c1,), 0, I32))
  bufl = put("BUFL", UOp(Ops.BUFFER, (sp,), parg(7, F32, AddrSpace.LOCAL, "b")))
  prm = put("PRM",  UOp(Ops.PARAM, (), parg(0, F32)))
  r_u = put("R_U",  UOp(Ops.RANGE, (c4,), (0,)))
  ad_srcs = (c1, prm) if swap == "add" else (prm, c1)
  ad  = put("ADD",  UOp(Ops.ADD, ad_srcs))
  st  = put("ST",   UOp(Ops.STORE, (bufl, ad, sp)))
  al  = put("ALG",  UOp(Ops.ALLOC, (c1,), parg(0, F32, AddrSpace.GLOBAL, "a")))
  en_srcs = (r_u, st) if swap == "end" else (st, r_u)
  en  = put("EN",   UOp(Ops.END, en_srcs))
  rb_srcs = (en, c16) if swap == "range" else (c16, en)
  r_b = put("R_B",  UOp(Ops.RANGE, rb_srcs, (1,)))
  ad2_srcs = (c16, prm) if swap == "add2" else (prm, c16)
  ad2 = put("ADD2", UOp(Ops.ADD, ad2_srcs))
  st2 = put("ST2",  UOp(Ops.STORE, (bufl, ad2, sp)))
  en2 = put("EN2",  UOp(Ops.END, (st2, r_b)))
  sink_srcs = (st, st2, en2, al)
  if swap == "sink0":
    sink_srcs = (st2, st, en2, al)
  if swap == "sinkend":
    sink_srcs = (st, st2, al, en2)
  if swap == "sinkrev":
    sink_srcs = tuple(reversed(sink_srcs))
  sk  = put("SK",   UOp(Ops.SINK, arg=KernelInfo(), src=sink_srcs))
  cll = put("CALL", UOp(Ops.CALL, (st, ad), None))
  sk2 = put("SK2",  UOp(Ops.SINK, arg=KernelInfo(), src=(cll,)))
  return ix, sk, sk2, (r_u, r_b)


def main() -> int:
  swap = SWAPS
  # Reuse late-oracle.py's row printers VERBATIM -- a second transcription of the
  # rows would be a second chance to be wrong, and the whole question is whether
  # THIS lane can see the swap.
  import importlib.util
  spec = importlib.util.spec_from_file_location(
    "late_oracle", os.path.join(os.path.dirname(__file__), "late-oracle.py"))
  lo = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(lo)

  ix, sk, sk2, rngs = lin_fixture(swap)
  lo.row("ix_len", len(ix) + 1)
  lo.srow("ix", " ".join(str(i) for i in range(len(ix) + 1)))
  lo.po_rows()
  lo.rc_rows()
  lo.lin_rows("lin", sk)
  lo.lin_rows("linc", sk2)
  lo.cfg_rows("cfg", sk, rngs)
  lo.se_rows()
  lo.ra_rows(False)
  lo.ra_rows(True)
  lo.ra2_rows()
  lo.rw_rows()
  lo.gater_rows()
  print("\n".join(lo.out))
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
