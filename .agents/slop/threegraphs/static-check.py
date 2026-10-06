#!/usr/bin/env python3
"""static-check.py -- WHAT CAN BE PROVEN ABOUT THE THREE ARMS WITHOUT `bend`.

`bend` is held by another unit, so the three new builders in `.agents/slop/graphcmp.bend`
(`g_allred`, `g_cdiv`, `g_late`) cannot be COMPILED here. This check answers the narrower
questions a compile would, over the SOURCE:

  1  each builder is defined exactly once;
  2  every `O.<Name>` / `S.<Name>` / `H.<Name>` token an arm NAMES resolves in
     `ops.bend` / `LAWS/spec.bend` / `helpers.bend`;
  3  every `O.UOp.<ctor>` call's arity equals the port's `def UOp.<ctor>` parameter count;
  4  `rows.pick3` has a rung for each name and appoints no OTHER arm to it;
  5  the arm's ordered `(op, child-count)` sequence equals the py fixture's own rows
     (read off `emit --side py --graph NAME`), EXPANDING the two port constructors that
     mint more than one node (`copy_to_device` -> CONST, RANGE, COPY; `allreduce` ->
     ALLREDUCE).

IT IS A STATIC CHECK, NOT A COMPILE. It does not typecheck bend's linearity/ownership
(`+` binder reuse), and it cannot prove the emitted BYTES equal the py rows -- the fold's
dtype/shape output is a `bend` fact. `bend` running the arm and `graphcmp.py diff` are
still owed; see REPORT.md.
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
BEND = ROOT / ".agents" / "slop" / "graphcmp.bend"
OPS = ROOT / "tinybendygrad" / "uop" / "ops.bend"
SPEC = ROOT / "tinybendygrad" / "LAWS" / "spec.bend"
HELPERS = ROOT / "tinybendygrad" / "helpers.bend"

NAMES = ("allred", "cdiv", "late")

# The py fixtures' own rows, MEASURED with `emit --side py --graph NAME` (see REPORT.md).
# The `id` column is a toposort position, so this sequence IS the construction order.
PY_STRUCT = {
    "allred": [("ALLOC", 0), ("CONST", 0), ("CONST", 0), ("STACK", 2), ("RESHAPE", 2),
               ("CONST", 0), ("RANGE", 1), ("COPY", 2), ("ALLREDUCE", 1)],
    "cdiv": [("ALLOC", 0), ("CONST", 0), ("CONST", 0), ("STACK", 2), ("RESHAPE", 2),
             ("ALLOC", 0), ("RESHAPE", 2), ("CMOD", 2), ("CDIV", 2), ("GROUP", 2)],
    "late": [("ALLOC", 0), ("CONST", 0), ("CONST", 0), ("STACK", 2), ("RESHAPE", 2),
             ("ALLOC", 0), ("RESHAPE", 2), ("SUB", 2), ("NEG", 1), ("CMPEQ", 2),
             ("FDIV", 2), ("GROUP", 4)],
}

DEF = re.compile(r"^def\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*(?:\(([^)]*)\))?", re.M)
CTOR = re.compile(r"^\s*([A-Za-z_]\w*)\{", re.M)


def symbols(path: pathlib.Path) -> tuple[set[str], dict[str, str]]:
    text = path.read_text()
    defs = {m.group(1): (m.group(2) or "") for m in DEF.finditer(text)}
    return set(defs) | {m.group(1) for m in CTOR.finditer(text)}, defs


def resolves(name: str, present: set[str], defs: dict[str, str]) -> bool:
    if name in present:
        return True
    for k in defs:
        if k == name or k.startswith(name + ".") or k.rsplit(".", 1)[-1] == name:
            return True
    return any(m.rsplit(".", 1)[-1] == name for m in present)


def arity(params: str) -> int:
    if not params.strip():
        return 0
    depth, n = 0, 1
    for ch in params:
        if ch in "([{<":
            depth += 1
        elif ch in ")]}>":
            depth -= 1
        elif ch == "," and depth == 0:
            n += 1
    return n


def block_of(lines: list[str], name: str) -> str | None:
    start = next((i for i, l in enumerate(lines) if l.startswith(f"def g_{name}(")), None)
    if start is None:
        return None
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("def ")), len(lines))
    return "\n".join(lines[start:end])


def children(line: str, at: int) -> int:
    """The `src` list head at `at` in `line`: count its top-level `O.Found.i(` calls.
    `range_end`/`range_shaped` pass a FLAT `[..]` of ids and mint ONE RANGE node."""
    j = line.find("[", at)
    if j == -1:
        return 0
    k, depth = j + 1, 1
    while depth and k < len(line):
        depth += {"[": 1, "]": -1}.get(line[k], 0)
        k += 1
    return line[j:k].count("O.Found.i(")


def structure(blk: str) -> list[tuple[str, int]]:
    out: list[tuple[str, int]] = []
    for line in blk.splitlines():
        for m in re.finditer(r"O\.UOp\.(\w+)\(", line):
            ctor = m.group(1)
            if ctor == "const":
                out.append(("CONST", 0))
            elif ctor in ("range_end", "range_shaped"):
                out.append(("RANGE", 1))
            elif ctor == "copy_to_device":
                # ops.bend: `device_range_src` mints CONST(len) + RANGE, then COPY.
                out += [("CONST", 0), ("RANGE", 1), ("COPY", 2)]
            elif ctor == "allreduce":
                out.append(("ALLREDUCE", 1))
            elif ctor == "new":
                op = re.search(r"O\.Ops(\w+)\{\}", line[m.end():])
                out.append((op.group(1) if op else "?", children(line, m.end())))
            else:
                out.append((f"?{ctor}", children(line, m.end())))
    return out


def main() -> int:
    fails: list[str] = []
    src = BEND.read_text()
    lines = src.splitlines()

    present_o, defs_o = symbols(OPS)
    present_s, defs_s = symbols(SPEC)
    present_h, defs_h = symbols(HELPERS)

    blocks: dict[str, str] = {}
    for name in NAMES:
        blk = block_of(lines, name)
        if blk is None:
            fails.append(f"MISSING builder g_{name}")
        else:
            blocks[name] = blk
            if len(re.findall(rf"^def g_{name}\(", src, re.M)) != 1:
                fails.append(f"g_{name} defined more than once")

    for name, blk in blocks.items():
        for owner, sym in re.findall(r"\b([OSH])\.([A-Za-z_]\w*)", blk):
            table = {"O": (present_o, defs_o, "ops.bend"), "S": (present_s, defs_s, "spec.bend"),
                     "H": (present_h, defs_h, "helpers.bend")}[owner]
            if not resolves(sym, table[0], table[1]):
                fails.append(f"{name}: {owner}.{sym} does not resolve in {table[2]}")

        for m in re.finditer(r"O\.UOp\.(\w+)\(", blk):
            ctor = m.group(1)
            sig = defs_o.get(f"UOp.{ctor}")
            if sig is None:
                fails.append(f"{name}: no `def UOp.{ctor}` in ops.bend")
                continue
            i, depth, args = m.end(), 1, ([] if blk[m.end()] == ")" else [""])
            while depth:
                ch = blk[i]
                if ch in "([{":
                    depth += 1
                elif ch in ")]}":
                    depth -= 1
                    if depth == 0:
                        break
                if ch == "," and depth == 1:
                    args.append("")
                elif depth >= 1:
                    args[-1] += ch
                i += 1
            if len(args) != arity(sig):
                fails.append(f"{name}: UOp.{ctor} called with {len(args)} args, def has {arity(sig)}")

        got = structure(blk)
        if got != PY_STRUCT[name]:
            fails.append(f"{name}: arm structure {got} != py rows {PY_STRUCT[name]}")
        else:
            print(f"  {name:6s}: {' '.join(o for o, _ in got)}")
            print(f"  {'':6s}  nodes={len(got)} == py {len(PY_STRUCT[name])}")

    # the dispatcher: one rung per name, and the name reaches THAT arm (not another).
    body = src[src.index("def rows.pick3"):src.index("def rows.pick(")]
    for name in NAMES:
        if f'String.eq(name, "{name}"), g_{name}()' not in body:
            fails.append(f"rows.pick3 has no rung wiring {name!r} to g_{name}()")
    if body.count("g_matmul()") != 1:
        fails.append("rows.pick3's default is not exactly one g_matmul()")
    if "def rows.pick3" not in src:
        fails.append("rows.pick3 is gone")

    if fails:
        print("STATIC-CHECK FAIL")
        for f in fails:
            print("  " + f)
        return 1
    print(f"STATIC-CHECK OK  arms={len(blocks)} O-symbols={len(present_o)} "
          f"pick3@line={next(i for i, l in enumerate(lines, 1) if l.startswith('def rows.pick3'))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
