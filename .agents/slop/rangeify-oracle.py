#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/schedule/rangeify.bend.

Values come from rf-rows.py, which calls tinygrad.schedule.rangeify. rf-rows.py
has neither "oracle" nor "gate" in its name, so rebase-scan-oracles.py's
filename filter cannot see it.

MEASURED 2026-10-03: 34 shared names, 3 disagreements. The three are encoding,
not a second answer:

  ren_arg0 / ren7_arg0
      CPython's Range arg[0] is AxisType.WEAK (rf-rows prints that). The port
      prints the axis index 0 and 7. Different fields of the same node.
  aprt_pglob
      rf-rows appends repr(tag) (`1 ()`). The port prints the rewrite hit `1`.

Those three are not emitted. The other shared rows are.
"""
import contextlib
import importlib.util
import io
import pathlib

from tinygrad.schedule import rangeify as R  # witness: the calls live in rf-rows

SKIP = {"ren_arg0", "ren7_arg0", "aprt_pglob"}


def main():
    if not hasattr(R, "renumber_range"):
        raise SystemExit("rangeify.renumber_range is gone")
    path = pathlib.Path(__file__).resolve().parent / "rf-rows.py"
    spec = importlib.util.spec_from_file_location("rf_rows_calls", path)
    mod = importlib.util.module_from_spec(spec)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        spec.loader.exec_module(mod)
    for line in buf.getvalue().splitlines():
        if "=" not in line or line.lstrip().startswith("#"):
            continue
        k, v = line.split("=", 1)
        if k.strip() in SKIP:
            continue
        print(f"{k.strip()}={v.strip()}")


if __name__ == "__main__":
    main()
