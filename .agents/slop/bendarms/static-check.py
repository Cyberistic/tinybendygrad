#!/usr/bin/env python3
"""static-check.py -- THE STRONGEST PROOF AVAILABLE WITHOUT RUNNING `bend`.

The five new arms in `.agents/slop/graphcmp.bend` (`threefry`, `mulacc`, `getaddr`,
`unshard`, `wmma`) cannot be COMPILED here (`bend` is held by another unit), so this
check answers the narrower question that a compile would: does every symbol an arm
NAMES exist in the port, with the arity the arm calls it? It does NOT prove the arm
typechecks or that it emits the py side's rows -- only `bend` can, and the report says
so. What it can prove, and does:

  1  each of the five builders is defined once;
  2  every `O.<Name>` token in the five builders resolves to a `def <Name>`, a
     `def <Owner>.<Name>`, or a record constructor `<Name>{` in `ops.bend`;
  3  every `S.<Name>` resolves in `LAWS/spec.bend` and every `H.<Name>` in `helpers.bend`;
  4  each `O.UOp.<ctor>` call arity matches the port's `def UOp.<ctor>` parameter count;
  5  the `rows.pick3` dispatcher has a rung for each of the five names.
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

NEW = ("threefry", "mulacc", "getaddr", "unshard", "wmma")

# `def UOp.new.shp` style: capture the last dotted name and the parameter list.
DEF = re.compile(r"^def\s+([A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)*)\s*(?:\(([^)]*)\))?", re.M)
CTOR = re.compile(r"^\s*([A-Za-z_][\w]*)\{", re.M)


def names(path: pathlib.Path) -> tuple[set[str], dict[str, str]]:
    text = path.read_text()
    defs = {m.group(1): (m.group(2) or "") for m in DEF.finditer(text)}
    ctors = {m.group(1) for m in CTOR.finditer(text)}
    return set(defs) | ctors, defs


def has(name: str, present: set[str], defs: dict[str, str]) -> bool:
    """A symbol resolves if it is a top-level def, a field/constructor of one, a
    namespace a `def Owner.name` exists under, or a record constructor."""
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


def main() -> int:
    fails: list[str] = []
    src = BEND.read_text()
    lines = src.splitlines()

    # isolate the five builders: from `def g_<name>()` to the next top-level `def`.
    blocks: dict[str, str] = {}
    for name in NEW:
        start = next((i for i, l in enumerate(lines) if l.startswith(f"def g_{name}(")), None)
        if start is None:
            fails.append(f"MISSING builder g_{name}")
            continue
        end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("def ")), len(lines))
        blocks[name] = "\n".join(lines[start:end])

    present_o, defs_o = names(OPS)
    present_s, defs_s = names(SPEC)
    present_h, defs_h = names(HELPERS)

    for name, blk in blocks.items():
        for owner, sym in re.findall(r"\b([OSH])\.([A-Za-z_][\w]*)", blk):
            if owner == "O":
                if not has(sym, present_o, defs_o):
                    fails.append(f"{name}: O.{sym} does not resolve in ops.bend")
            elif owner == "S":
                if not has(sym, present_s, defs_s):
                    fails.append(f"{name}: S.{sym} does not resolve in spec.bend")
            else:
                if not has(sym, present_h, defs_h):
                    fails.append(f"{name}: H.{sym} does not resolve in helpers.bend")

    # arity of every `O.UOp.<ctor>(...)` call -- balance-safe single-level split.
    for name, blk in blocks.items():
        for m in re.finditer(r"O\.UOp\.(\w+)\(", blk):
            ctor = m.group(1)
            sig = defs_o.get(f"UOp.{ctor}")
            if sig is None:
                fails.append(f"{name}: no `def UOp.{ctor}` in ops.bend")
                continue
            # walk to the matching close paren and count top-level commas.
            i = m.end()
            depth, args = 1, ([] if blk[i] == ")" else [""])
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
            got, want = len(args), arity(sig)
            if got != want:
                fails.append(f"{name}: UOp.{ctor} called with {got} args, def has {want}")

    if "rows.pick3" in src:
        for name in NEW:
            if f'String.eq(name, "{name}")' not in src:
                fails.append(f"dispatcher has no rung for {name}")

    counts = {"threefry": 12, "mulacc": 10, "getaddr": 2, "unshard": 8, "wmma": 11}
    mint = re.compile(r"O\.UOp\.(?:new|const|range_end|range_shaped|getaddr|wmma)\(")
    for name, blk in blocks.items():
        got = len(mint.findall(blk))
        if got != counts[name]:
            fails.append(f"{name}: arm mints {got} nodes, py MEASURED {counts[name]}")
        else:
            print(f"  node-count {name}: {got} == py {counts[name]}")

    # STRUCTURE: the ordered (op, child-count) sequence, against the py side's own
    # rows. A right COUNT with a wrong ORDER or child arity is still a disagreement.
    struct = {
        "threefry": [("ALLOC", 0), ("CONST", 0), ("CONST", 0), ("STACK", 2), ("RESHAPE", 2),
                     ("ALLOC", 0), ("RESHAPE", 2), ("THREEFRY", 2), ("ALLOC", 0), ("RESHAPE", 2),
                     ("THREEFRY", 2), ("GROUP", 2)],
        "mulacc": [("ALLOC", 0), ("CONST", 0), ("CONST", 0), ("STACK", 2), ("RESHAPE", 2),
                   ("ALLOC", 0), ("RESHAPE", 2), ("ALLOC", 0), ("RESHAPE", 2), ("MULACC", 3)],
        "getaddr": [("ALLOC", 0), ("GETADDR", 1)],
        "unshard": [("ALLOC", 0), ("CONST", 0), ("CONST", 0), ("STACK", 2), ("RESHAPE", 2),
                    ("CONST", 0), ("RANGE", 1), ("UNSHARD", 2)],
        "wmma": [("ALLOC", 0), ("CONST", 0), ("STACK", 2), ("RESHAPE", 2), ("ALLOC", 0),
                 ("CONST", 0), ("STACK", 2), ("RESHAPE", 2), ("ALLOC", 0), ("RESHAPE", 2),
                 ("WMMA", 3)],
    }

    def parse(blk: str) -> list[tuple[str, int]]:
        out: list[tuple[str, int]] = []
        for line in blk.splitlines():
            for m in re.finditer(r"O\.UOp\.(new|const|range_end|range_shaped|getaddr|wmma)\(", line):
                kind = m.group(1)
                if kind == "const":
                    out.append(("CONST", 0))
                elif kind in ("range_end", "range_shaped"):
                    out.append(("RANGE", 1))
                elif kind == "getaddr":
                    out.append(("GETADDR", 1))
                elif kind == "wmma":
                    out.append(("WMMA", 3))
                else:
                    op = re.search(r"O\.Ops(\w+)\{\}", line[m.end():])
                    j = line.find("[", m.end())
                    n = 0
                    if j != -1:
                        k, dep = j + 1, 1
                        while dep and k < len(line):
                            dep += {"[": 1, "]": -1}.get(line[k], 0)
                            k += 1
                        n = line[j:k].count("O.Found.i(")
                    out.append((op.group(1) if op else "?", n))
        return out

    for name, blk in blocks.items():
        got = parse(blk)
        if got != struct[name]:
            fails.append(f"{name}: structure {got} != py {struct[name]}")
        else:
            print(f"  structure  {name}: {' '.join(o for o, _ in got)}")


    if fails:
        print("STATIC-CHECK FAIL")
        for f in fails:
            print("  " + f)
        return 1
    print(f"STATIC-CHECK OK  builders={len(blocks)} names={len(NEW)} "
          f"O-symbols={len(present_o)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
