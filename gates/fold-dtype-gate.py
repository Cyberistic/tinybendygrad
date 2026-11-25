#!/usr/bin/env python3
"""fold-dtype-gate.py -- `fold.bend`'s CONSTANT-DTYPE table against CPython's own arms.

    .venv/bin/python gates/fold-dtype-gate.py

`fold.bend` is not a `PMEntry` table: it is a topological property fold, `dtype` and `shape`
answered together as one `DtShape`, one arm per op in `dt_shape`. So it cannot be projected
the way `symbolic.bend`'s and `dtype.bend`'s rule tables are -- but ELEVEN of `dtype_from_uop`'s
twenty arms (`tinygrad/uop/ops.py:115`) return a LITERAL dtype regardless of their sources,
and that is a table: op -> dtype, stated twice, once per side. This gate compares the two.

THE INDIRECTION IS ONE LEVEL AND IT IS MEASURED, NOT ASSUMED. Seven of the eleven are not
spelled inline on the port's arm -- `GETADDR` is `addr_ds()`, `BINARY` is `binary_ds(arg)`,
`SINK`/`PROGRAM`/`SOURCE`/`LINEAR`/`STORE` are `late()`/`store_ds(ss)` -- so the gate follows
ONE call into a `def` whose body names exactly one `S.<dtype>()`. Deeper than that and the
dtype is computed rather than declared, which is not this claim; the gate reports such a row
`UNRESOLVED` and FAILS rather than guessing.

WHAT IT FOUND: nothing. All eleven agree (2026-11-25). That is a result worth stating because
the same check on `dtype.bend`'s groups found two missing members and on `symbolic.bend`'s
rule table found three dead rows -- the fold's constant arms were the part of the tables work
that was already right, and now it stays observable.

`ALIAS` IS A NAME MAP AND NOTHING ELSE: tinygrad spells `dtypes.bool`, the port `S.boolean()`.
A dtype this map does not know is `REFUSED`, because a name the gate cannot translate is a row
it cannot compare -- and silently skipping it is how a table check becomes a table check of
the rows it happens to understand.
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gatekit import DEAD, FAIL, PASS, REFUSED  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[1]
PORT = ROOT / "tinybendygrad/uop/fold.bend"
ORACLE = ROOT / "tinygrad/uop/ops.py"

ALIAS = {"bool": "boolean"}


def block(text: str, name: str) -> str:
    """One top-level def's body -- a def starts at column 0, which is what bounds it here."""
    m = re.search(rf"^def {name}\(.*?(?=^\S)", text, re.M | re.S)
    if m is None:
        raise SystemExit(f"fold-dtype-gate: REFUSED -- no top-level `def {name}` in its file")
    return m.group(0)


def upstream_arms(text: str) -> dict[str, str]:
    """`case Ops.A | Ops.B: return dtypes.X` -- the arms that name a literal dtype."""
    out, cur = {}, None
    for line in block(text, "dtype_from_uop").split("\n"):
        if line.startswith("    case "):
            cur = re.findall(r"Ops\.([A-Z_0-9]+)", line.split(":")[0])
        elif cur:
            m = re.fullmatch(r"\s*return dtypes\.(\w+)\s*", line)
            if m:
                for op in cur:
                    out[op] = m.group(1)
                cur = None
    return out


def port_arms(text: str, helpers: dict[str, str]) -> dict[str, str]:
    """`case O.OpsX{}: <expr>` in `dt_shape`, resolved inline or ONE call deep."""
    out = {}
    for line in block(text, "dt_shape").split("\n"):
        m = re.match(r"\s*case O\.Ops([A-Z_0-9]+)\{\}:\s*(.+?)\s*$", line)
        if not m or m.group(1) in out:
            continue
        expr = m.group(2)
        dts = set(re.findall(r"S\.([a-z0-9_]+)\(\)", expr))
        if len(dts) == 1:
            out[m.group(1)] = dts.pop()
            continue
        call = re.fullmatch(r"([\w.]+)\(.*\)", expr)
        out[m.group(1)] = helpers.get(call.group(1)) if call else None
    return out


def helpers(text: str) -> dict[str, str]:
    """`def <name>(...):` bodies whose ONLY `S.<dt>()` names one dtype -- one level, no more."""
    out = {}
    for m in re.finditer(r"^def ([\w.]+)\((.*?)(?=^\S)", text, re.M | re.S):
        dts = set(re.findall(r"S\.([a-z0-9_]+)\(\)", m.group(2)))
        if len(dts) == 1:
            out[m.group(1)] = dts.pop()
    return out


def main() -> int:
    up = upstream_arms(ORACLE.read_text())
    if not up:
        print("== DEAD: fold-dtype-gate: `dtype_from_uop` yielded 0 literal-dtype arms -- the "
              "shape changed, so nothing would be compared")
        return DEAD
    port = port_arms(PORT.read_text(), helpers(PORT.read_text()))
    if not port:
        print("== DEAD: fold-dtype-gate: `dt_shape` yielded 0 arms -- the shape changed")
        return DEAD

    unknown = sorted({d for d in up.values() if d not in ALIAS and d not in
                      {"void", "uint8", "uint16", "uint32", "uint64", "int8", "int16", "int32",
                       "int64", "float", "half", "double", "boolean"}})
    if unknown:
        print(f"== REFUSED: fold-dtype-gate: dtype name(s) {unknown} are in neither ALIAS nor the "
              "known vocabulary, so those rows cannot be translated")
        return REFUSED

    rows, bad, unresolved = 0, 0, []
    for op in sorted(up):
        want = ALIAS.get(up[op], up[op])
        got = port.get(op)
        got = ALIAS.get(got, got) if got else got
        if got is None:
            unresolved.append(op)
            continue
        rows += 1
        if got != want:
            bad += 1
            print(f"  DIFF {op:10} up={want:8} port={got}")
        else:
            print(f"  ok   {op:10} {want}")

    if unresolved:
        bad += len(unresolved)
        print(f"  UNRESOLVED {','.join(unresolved)} -- no arm, or a dtype computed rather than "
              "declared; this gate follows one call and no further")
    if bad:
        print(f"== FAIL: fold-dtype-gate: {bad} of CPython's {len(up)} literal-dtype arms are "
              f"not stated the same way by `dt_shape`")
        return FAIL
    print(f"== PASS: fold-dtype-gate: all {rows} of CPython's literal-dtype arms are stated the "
          "same way by `dt_shape`")
    return PASS


if __name__ == "__main__":
    sys.exit(main())
