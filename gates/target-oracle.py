#!/usr/bin/env python3
"""gates/target-oracle.py -- THE CPYTHON LANE for `gates/target-gate.py`.

    .venv/bin/python gates/target-oracle.py

THE ORACLE IS CPython's OWN `Target.parse` and CPython's OWN `ProgramInfo`, from
the VENDORED `tinygrad/` at the declared pin -- called, never re-implemented. The
port's `Target` is upstream's record (`tinygrad/helpers.py:198`, `interface`
spelled `iface` here) and the port's `ProgramInfo` is upstream's
(`tinygrad/uop/ops.py:1343`), so the row this file prints is upstream's row and
the Bend lane's row is the port's, and the diff between them is the claim.

THE ROW IS A ROUND TRIP, NOT A PARSE. `<dev> => <before> -> <after>`, where
`before` is `Target.parse(s)` and `after` is `ProgramInfo(target=before).target`.
The two halves are the SAME five values when the round trip is lossless, and
they DIFFER when it is not -- a dropped field or a swapped pair. The names are
the same in both halves either way, so the ORDER of the values is the whole
claim, and a row that printed only the parsed target could not see it.

THE REFUSALS ARE UPSTREAM'S REFUSALS. Upstream raises `RuntimeError` for a third
`+` and for a fourth `:` in the device half; this file catches it and prints
`REFUSED`, because the port's `Maybe` is upstream's `RuntimeError` and the two
agree on the BOUNDARY (which strings are refused) and not on the message.

NO ROW IS TYPED FROM MEMORY. Every expectation is a CALL into the vendored
`tinygrad`, and the DEV string list is the same twenty the Bend lane walks, in
the same order.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from tinygrad.helpers import Target  # noqa: E402
from tinygrad.uop.ops import ProgramInfo  # noqa: E402

# THE SAME TWENTY, IN THE SAME ORDER, AS `gates/target-roundtrip.bend`.
DEVS = (
  "", "CPU", "CPU:CLANG", "AMD:LLVM:gfx1100", "AMD:LLVM:GFX1100", "cpu:clang",
  "USB+AMD", "USB:1+AMD", "AMD+CPU:CLANG", "A:B:C+AMD", "usb:1+amd:llvm:gfx1100",
  "A:B:C:D", "A+B+C", "A:B:C+D", "A+B:C:D", "A+B:C:D:E", ":", "A:", "::", "A::B",
)


def show(t: Target) -> str:
  return "|".join((t.device, t.renderer, t.arch, t.interface, t.indices))


def main() -> int:
  for s in DEVS:
    try:
      parsed = Target.parse(s)
    except RuntimeError:
      print(f"{s} => REFUSED")
      continue
    after = ProgramInfo(target=parsed).target
    print(f"{s} => {show(parsed)} -> {show(after)}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
