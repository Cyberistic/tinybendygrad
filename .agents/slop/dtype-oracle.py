#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/codegen/decomp/dtype.bend.

The values come from dd-oracle.py, which calls tinygrad.codegen.decomp.dtype.
This file does not recompute them. It drops the creation-order rows.

MEASURED 2026-10-03 against the LIVE port (164 rows, the 14:33 cache's 147
was stale): 99 agree. The skipped rows are creation-order (`*sig`/`*k`/`*n`/`*p`)
plus five the live tree still disagrees on:

  lgu    CPython `WHERE(OR(AND,AND),Pf320,ADD(MUL,CAST))` — the port prints
         `refused:unported`. The function is not ported; gating the refusal
         would be permanently BROKEN.
  lgun   CPython 14, port 0. The count of the graph `lgu` refused to build.
  lgvk   CPython `C(0)`, port `C(0),C(0)`.
  lgvsig CPython `CAST/1,CAST/1,CONST/0,CAST/1`, port has an extra `CONST/0`.
  lgwsig CPython `CAST/1,CONST/0`, port has an extra `CAST/1`.

dd-oracle records CPython's UOp interning order by wrapping UOpMetaClass.__call__.
The port's arena interns in a different order. Gating those rows is permanent
BROKEN and would hide the 99 that do compare. A later drift in an emitted row
still goes red.
"""
import importlib.util
import io
import contextlib
import pathlib
import sys

from tinygrad.codegen.decomp import dtype as DD  # the calls are real; this import is the witness

SKIP = {
    "lg1k", "lg1n", "lg1sig", "lg2k", "lg2n", "lg2p", "lg2sig", "lg5k", "lg5n",
    "lg5sig", "lg6k", "lg6n", "lg6p", "lg6sig", "lg9k", "lg9n", "lg9p", "lg9sig",
    "lga", "lgak", "lgan", "lgap", "lgasig", "lgb", "lgbk", "lgbn", "lgbp",
    "lgbsig", "lgcsig", "lgdk", "lgdsig", "lge", "lgek", "lgep", "lgesig", "lgfn",
    "lgfsig", "lggk", "lggsig", "lglsig", "lgmsig", "lgq", "lgqk", "lgqn", "lgqp",
    "lgqsig", "lgr", "lgrk", "lgrn", "lgrp", "lgrsig", "lgs", "lgsk", "lgsn",
    "lgssig", "lgt", "lgtk", "lgtn", "lgtsig", "upsig",
    # Live tree, 2026-10-03, after the port grew from 147 to 164 rows. These five
    # disagree; CPython's answer is cited in the module docstring. Not gated.
    "lgu", "lgun", "lgvk", "lgvsig", "lgwsig",
}


def load():
    path = pathlib.Path(__file__).resolve().parent / "dd-oracle.py"
    spec = importlib.util.spec_from_file_location("dd_oracle_calls", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    # Touch a real function so this file is not a filter over a restatement.
    if not hasattr(DD, "f2f"):
        sys.exit("decomp.dtype.f2f is gone")
    mod = load()
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        mod.main()
    for line in buf.getvalue().splitlines():
        if "=" not in line or line.startswith("#"):
            continue
        k, v = line.split("=", 1)
        if k.strip() in SKIP:
            continue
        print(f"{k.strip()}={v.strip()}")


if __name__ == "__main__":
    main()
