#!/usr/bin/env python3
"""stage1_pins.py -- WHAT THE 12 PINNED WGSL DIVERGENCES ACTUALLY ARE, AND WHY NONE CAN BE TIMED.

    .venv/bin/python .agents/slop/perf/stage1_pins.py

The brief for this stage was "for each of the 12 pinned rows, render both texts, compile and
time BOTH". That presupposes each pin is a PAIR OF TEXT FRAGMENTS. It is not: the pins are
the census gate's LANE rows, and a LANE row is one expression's VALUE -- a refusal, or an
integer. `gates/wgsl_render_census-pins.rows` is the only writer's output, so this classifies
from THAT FILE rather than from a list typed here.

THE THREE KINDS, and only the third is even arguable:

  REFUSAL/REFUSAL  CPython raises (`KeyError`/`IndexError`) and the port spells a refusal
                   that cannot compile (`UNHANDLED(...)`, `""`). THERE IS NO SHADER ON
                   EITHER SIDE.
  VALUE            both sides compute an integer; the spellings differ (`255<<0^4294967295`
                   against `4294967040`) or agree numerically. NOT TEXT AT ALL.
  REFUSAL/ANSWER   the PORT ANSWERS WHERE CPYTHON RAISES (FDIV -> `(A/B)`). The port is more
                   permissive; "python to webgpu" has NO TEXT for that kernel, so "matches
                   speed" is UNDEFINED rather than equal, and timing the port's alone would
                   be a one-sided number wearing a comparison's clothes.
"""
from __future__ import annotations
import pathlib, re

PINS = pathlib.Path(__file__).resolve().parents[3] / "gates/wgsl_render_census-pins.rows"
OUT = pathlib.Path(__file__).resolve().parent / "stage1-pins.rows"
REFUSE = re.compile(r"^REFUSE:(KeyError|IndexError)$")


def kind(oracle: str, port: str) -> tuple[str, str]:
    o_ref, p_ref = bool(REFUSE.match(oracle)), port.startswith("UNHANDLED(") or port == ""
    if o_ref and p_ref:
        return "REFUSAL/REFUSAL", "no shader on either side"
    if o_ref and not p_ref:
        return "REFUSAL/ANSWER", "the port answers where CPython raises: no python-side text exists"
    if oracle.startswith("GRAPH:") or port.startswith("GRAPH:"):
        return "VALUE", "an integer expression's value, not text"
    return "OTHER", "unclassified"


def value_of(s: str) -> int | None:
    """`GRAPH:255<<0^4294967295` is an expression the census prints, not a number."""
    e = s[len("GRAPH:"):] if s.startswith("GRAPH:") else s
    m = re.fullmatch(r"(\d+)<<(\d+)\^(\d+)", e.strip())
    if m:
        v, sh, mask = (int(x) for x in m.groups())
        return (v << sh) ^ mask
    try:
        return int(e.strip())
    except ValueError:
        return None


def main() -> int:
    rows = []
    for ln in PINS.read_text().splitlines():
        if not ln or ln.startswith("#"):
            continue
        f = ln.split("\t")
        if len(f) < 4 or f[3] != "LANE":
            continue
        k, why = kind(f[1], f[2])
        # for a VALUE row the question is not "do the spellings match" but "do the VALUES",
        # and MEASURED they all do -- the oracle prints the expression and the port the decimal
        eq = ""
        if k == "VALUE":
            a, b = value_of(f[1]), value_of(f[2])
            eq = "equal" if a is not None and a == b else f"DIFFERS({a} vs {b})"
            why = why + (", and the numbers agree" if eq == "equal" else ", and the numbers DO NOT")
        rows.append((f[0], k, f[1][:44], f[2][:44], why, eq or "-"))
    OUT.write_text(
        "# stage1-pins.rows -- .agents/slop/perf/stage1_pins.py, classified from\n"
        "# gates/wgsl_render_census-pins.rows (its only writer's output).\n"
        "# 'compilable' is NO for every row: a refusal is not a shader and a value is not text.\n"
        "# row|kind|oracle|port|compilable|values|why\n"
        + "\n".join(f"{n}|{k}|{o}|{p}|no|{eq}|{w}" for n, k, o, p, w, eq in rows) + "\n")
    by = {}
    for _, k, *_ in rows:
        by[k] = by.get(k, 0) + 1
    print(f"pins={len(rows)} " + " ".join(f"{k}={v}" for k, v in sorted(by.items())))
    for n, k, o, p, _, _ in rows:
        print(f"  {k:<15} {n:<22} oracle={o:<30} port={p}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
