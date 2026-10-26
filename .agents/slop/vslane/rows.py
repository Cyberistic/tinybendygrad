#!/usr/bin/env python3
"""THE 29 PINNED ROWS, EACH WITH ITS PACKET'S ALU OPS AND ITS TWO ANSWERS.

    .venv/bin/python .agents/slop/vslane/rows.py [name ...]

THE EXPECTATIONS ARE NEVER TYPED: the `py` column is UPSTREAM's own
`gates/ops_python_exec-gen.py` output and the `bd` column is THE PORT's own
`.agents/slop/execfix/census.py` output, both re-read from the files this unit
produced. THE BUFFERS ARE DECODED, so a difference is a NUMBER and not a hex
string.
"""
import pathlib
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent

PINS = ROOT / "gates" / "ops_python_exec-pins.rows"
FIXTURES = ROOT / "gates" / "ops_python_exec-fixtures.rows"

ALU = ("ADD", "SUB", "MUL", "NEG", "MAX", "CMPNE", "CMPEQ", "CMPLT", "XOR", "OR", "AND",
       "SHR", "SHL", "LOG2", "EXP2", "SQRT", "RECIPROCAL", "SIN", "TRUNC", "CMOD", "CDIV",
       "FLOORDIV", "FLOORMOD", "MULACC", "WHERE", "POW")


def rows(path):
    out = {}
    for ln in pathlib.Path(path).read_text().splitlines():
        if "=" in ln:
            k, v = ln.split("=", 1)
            out[k] = v
    return out


def fixtures():
    recs, cur = [], None
    for ln in FIXTURES.read_text().splitlines():
        if ln.startswith("@ "):
            cur = [ln.split()[1:], []]
            recs.append(cur)
        elif cur is not None and ln.strip():
            cur[1].append(ln)
    return recs


def decode(name, hx):
    b = bytes.fromhex(hx)
    n = len(b)
    if n == 0:
        return "<empty>"
    if n % 4 == 0:
        i = struct.unpack(f"<{n // 4}i", b)
        f = struct.unpack(f"<{n // 4}f", b)
        return f"i32={list(i)} f32={[round(x, 6) for x in f]}"
    return f"bytes={list(b)}"


def main():
    py = rows(HERE / "oracle.rows")
    bd = rows(HERE / "census-base.rows")
    pinned = [l.split()[0] for l in PINS.read_text().splitlines()
              if l.strip() and not l.startswith("#")]
    want = sys.argv[1:] or pinned
    fx = {h[0]: body for h, body in fixtures()}
    for p in want:
        name = p.rsplit(".b", 1)[0]
        print(f"== {p}")
        body = fx.get(name)
        if body:
            nu = int(body[0].split()[1])
            for ln in body[1:1 + nu]:
                op = ln.split()[1] if len(ln.split()) > 1 else "?"
                if op in ALU or "CAST" in op or "BITCAST" in op or "STORE" in op:
                    print(f"   {ln}")
            for ln in body[1 + nu:]:
                parts = ln.split()
                print(f"   BUF {parts[0]} {decode(name, parts[1])}")
        print(f"   py {decode(name, py.get(p, '<missing>'))}")
        print(f"   bd {decode(name, bd.get(p, '<missing>'))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
