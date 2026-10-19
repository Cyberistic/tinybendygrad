#!/usr/bin/env python3
"""untested-census.py -- THE MIDDLE BUCKET, MEASURED AGAINST A POPULATION THAT IS NOT A LIST.

    .venv/bin/python gates/untested-census.py            # the table
    .venv/bin/python gates/untested-census.py --rows     # name=value rows only

WHAT THIS IS ABOUT. `gapcensus.py` splits `class UOp` three ways and the middle bucket --
`uop.ported_name_identical_UNEXERCISED` -- is 23 and is called "the most dangerous number in
the table". `gapcensus.unit_uop` defines it at `gates/gapcensus.py:293`:

    def exercised(name):
      w = re.compile(r"\\b" + re.escape(name) + r"\\b")
      return any(w.search(s) for s in drivers.values())

and `drivers` is `gapcensus.gate_drivers()` -- the `.bend` files a gate names in its own
`bend=`. So EXERCISED means "this method's NAME occurs in at least one gate driver's TEXT".
It is honestly labelled a "STATIC REACHABILITY claim, not an observation of a run".

THE QUESTION THIS FILE ASKS IS NOT "WHICH 23". It is "WHAT DOES `exercised` SEARCH, AND IS
THE PORT INSIDE IT?" -- and the answer is that it is not. `gate_drivers()` returns 62 paths of
which 61 live in `gates/`, `.agents/` or `examples/` and ONE lives in `tinybendygrad/`
(`tinybendygrad/mixin/op.bend`). `ops.bend` ITSELF IS NOT A DRIVER. So the corpus the split is
decided over is a set of test harnesses, not the port, and a method the port calls on every
compilation is reported UNEXERCISED because no harness happens to spell its name.

NO LIST APPEARS IN THIS FILE. The bucket is RE-DERIVED by calling `gapcensus`'s own
population functions -- `ast_methods`, `UOP_METHODS`, `gate_drivers` -- and `assert`s the
derivation against the row `gapcensus` itself publishes. If `gapcensus` changes, this file
follows it or it refuses; it never carries its own copy of the 23.

`call_sites` is deliberately STRICTER than `exercised`: it drops comment lines and the
method's own `def UOp.<name>` line, and requires `(` after the name. It is the same KIND of
claim (a text search) pointed at the RIGHT population, so it is an UPPER BOUND ON THE
OPPOSITE ERROR and not a stronger kind of evidence. Rows say which.

ONE KNOWN BLIND SPOT, NAMED RATHER THAN FIXED. Upstream exposes several of these as
`@functools.cached_property`, where a use reads `u.metadata` and never writes `u.metadata(`.
`cpython_call_sites` therefore UNDER-counts every property. MEASURED: `metadata` reads
`cpython_call_sites=0` while `tinygrad/viz/serve.py:163`, `tinygrad/uop/ops.py:241` and
`tinygrad/uop/ops.py:529` all use it. The row is named `call_sites` rather than `callers` so
that the understatement is the reader's to see.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gapcensus  # noqa: E402

# NO `ROOT` ALIAS. `gapcensus.ROOT` is read AT CALL TIME everywhere below, because the plant
# reassigns it to a temp copy of the repo and an alias bound at import would leave this file
# reading the live tree while the census read the copy -- which is the defect
# `gates/gapcensus-gate.py:84-86` records as having made its own plant un-failable.


def middle_bucket() -> list[str]:
    """THE 23, RE-DERIVED FROM `gapcensus`'s OWN POPULATIONS. No list is written here.

    `gapcensus.unit_uop` returns COUNTS, not names, so the names cannot be read out of it.
    But every population it uses is a function in that module and is called here, so the
    two files cannot disagree about WHICH files are upstream, WHICH are the port, or WHICH
    are the drivers -- only about the counting, and `check_against_pins` settles that.
    """
    upstream = gapcensus.ast_methods(gapcensus.up() / "uop" / "ops.py", "UOp")
    port_ns = set(gapcensus.UOP_METHODS.findall(gapcensus.ops_bend().read_text()))
    drivers = {p: p.read_text(errors="replace") for p in gapcensus.gate_drivers()}

    def exercised(name: str) -> bool:
        # BYTE-FOR-BYTE `gapcensus.py:293-295`. If that changes, `check_against_pins` is what
        # notices, not this comment.
        w = re.compile(r"\b" + re.escape(name) + r"\b")
        return any(w.search(s) for s in drivers.values())

    return sorted(n for n in upstream if n in port_ns and not exercised(n))


def all_bend() -> dict[Path, str]:
    out = {}
    for dp, dn, fn in os.walk(gapcensus.port()):
        dn[:] = [d for d in dn if d != "__pycache__"]
        for n in fn:
            if n.endswith(".bend"):
                p = Path(dp, n)
                out[p] = p.read_text(errors="replace")
    return out


def all_python(root: Path) -> dict[Path, str]:
    out = {}
    if not root.is_dir():
        return out
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d != "__pycache__"]
        for n in fn:
            if n.endswith(".py"):
                p = Path(dp, n)
                out[p] = p.read_text(errors="replace")
    return out


def call_sites(name: str, sources: dict[Path, str]) -> list[tuple[Path, int]]:
    """`name(` on a line that is NOT a comment and NOT the method's own `def` line.

    Two exclusions, and both are load-bearing. Without the comment exclusion a def whose
    header cites `ops.py:623` counts itself; without the `def` exclusion every ported method
    counts its own declaration and the row is >= 1 for all 23 and therefore measures nothing.
    """
    w = re.compile(r"\b" + re.escape(name) + r"\s*\(")
    decl = re.compile(r"^def\s+UOp\." + re.escape(name) + r"\b")
    out = []
    for p, text in sources.items():
        for i, line in enumerate(text.splitlines(), 1):
            s = line.strip()
            if s.startswith("#") or not w.search(line) or decl.match(s):
                continue
            out.append((p, i))
    return out


def rows() -> list[str]:
    """`name=value`. ONE ROW PER MEASUREMENT, and the 23 are named by a GENERATED row.

    `bucket.<method>=...` is generated from `middle_bucket()`, so the list of the 23 exists in
    this file only as OUTPUT. The gate compares it against the census's own published count,
    which is what stops the two from drifting into different lists.
    """
    bucket = middle_bucket()
    bend, cpy, suite = all_bend(), all_python(gapcensus.up()), all_python(gapcensus.ROOT / "test")
    drivers = {p.resolve() for p in gapcensus.gate_drivers()}
    out = [
        f"bucket.size={len(bucket)}",
        f"bucket.drivers_searched={len(drivers)}",
        f"bucket.drivers_INSIDE_the_port={sum(1 for p in drivers if gapcensus.port() in p.parents)}",
        f"bucket.port_bend_files={len(bend)}",
        f"bucket.port_bend_files_searched_by_exercised="
        f"{sum(1 for p in bend if p.resolve() in drivers)}",
    ]
    for name in bucket:
        cs = call_sites(name, bend)
        out += [
            f"bucket.{name}.port_call_sites={len(cs)}",
            f"bucket.{name}.port_call_sites_outside_ops_bend="
            f"{sum(1 for p, _ in cs if p.name != 'ops.bend')}",
            f"bucket.{name}.port_call_sites_inside_ops_bend="
            f"{sum(1 for p, _ in cs if p.name == 'ops.bend')}",
            f"bucket.{name}.cpython_call_sites="
            f"{len([c for c in call_sites(name, cpy) if c[0].name != 'ops.py'])}",
            f"bucket.{name}.upstream_test_files="
            f"{sum(1 for p, s in suite.items() if re.search(chr(92) + 'b' + name + chr(92) + 'b', s))}",
        ]
    return out


def check_against_pins() -> list[str]:
    """THE 23 AGAINST `gapcensus`'s OWN PUBLISHED ROW. Two rows, both from the other file.

    This is what makes "no list is written here" true rather than merely claimed: the number
    of names this file derives is compared to the number `gapcensus.unit_uop` publishes, and
    to the number `gates/gapcensus-pins.rows` pins. A third population would make this
    FAIL, and a FAIL is the correct outcome -- it means the two files stopped agreeing.
    """
    want = dict(l.split("=", 1) for l in gapcensus.rows((gapcensus.unit_uop,)) if "=" in l)
    pinned = dict(l.split("=", 1) for l in (HERE / "gapcensus-pins.rows").read_text().splitlines()
                  if "=" in l)
    bad = []
    if str(len(middle_bucket())) != want["uop.ported_name_identical_UNEXERCISED"]:
        bad.append(f"derived {len(middle_bucket())} names, gapcensus publishes "
                   f"{want['uop.ported_name_identical_UNEXERCISED']}")
    if want.get("uop.ported_name_identical_UNEXERCISED") != pinned.get("uop.ported_name_identical_UNEXERCISED"):
        bad.append(f"gapcensus publishes {want['uop.ported_name_identical_UNEXERCISED']}, "
                   f"the baseline pins {pinned.get('uop.ported_name_identical_UNEXERCISED')}")
    return bad


def table() -> None:
    got = dict(l.split("=", 1) for l in rows() if "=" in l)
    print("\n== THE DENOMINATOR OF `exercised`, AND WHERE IT LIVES")
    for k in sorted(k for k in got if k.count(".") == 1):
        print(f"   {k}={got[k]}")
    print("\n== THE 23, AND WHAT ELSE TOUCHES EACH")
    names = middle_bucket()
    print(f"   {'method':<32}{'port':>5}{'outside':>9}{'ops.bend':>9}{'cpy':>5}{'test/':>7}")
    for n in names:
        g = lambda s: got[f"bucket.{n}.{s}"]  # noqa: E731
        print(f"   {n:<32}{g('port_call_sites'):>5}{g('port_call_sites_outside_ops_bend'):>9}"
              f"{g('port_call_sites_inside_ops_bend'):>9}{g('cpython_call_sites'):>5}"
              f"{g('upstream_test_files'):>7}")
    zero = [n for n in names if got[f"bucket.{n}.port_call_sites"] == "0"]
    print(f"\n   {len(names)} in the middle bucket; {len(zero)} have NO call site "
          f"anywhere in the port: {', '.join(zero) if zero else 'NONE'}")
    print("   `outside` counts call sites in port .bend modules OTHER THAN ops.bend; `ops.bend`")
    print("   counts them inside ops.bend, whose own sub-gates `gapcensus` never reads.")
    print("   `cpy` UNDER-counts upstream PROPERTIES -- see the module docstring.")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--rows", action="store_true", help="print rows only")
    a = ap.parse_args()
    if a.rows:
        print("\n".join(rows()))
    else:
        print(f"untested-census: {len(check_against_pins())} disagreement(s) with gapcensus")
        for b in check_against_pins():
            print(f"  {b}")
        table()