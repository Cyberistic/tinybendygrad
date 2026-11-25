#!/usr/bin/env python3
"""pmtable.py -- read a port `PMEntrys` TABLE and pair it with CPython's `PatternMatcher`.

A `PMEntry` is `{tag, ops, rej}`: the ops the root may be (`p.op`) and the ops that must
appear among its SOURCES (`p.early_reject`). CPython derives both from the `UPat`
(`tinygrad/uop/ops.py:1554`, `entry=[p, None, p.early_reject]`), so a port table is a
PROJECTION of a matcher and never a transcription. This module is that projection and the
pairing, so the per-file gates are only the part that differs.

NOTHING HERE IS A POPULATION. The caller names the port def and the matcher; the rows come
from the file and the oracle. A gate that typed its rows would be the defect it checks for.

THE PAIRING IS NOT ALWAYS 1:1, AND THAT IS THE POINT OF THE TWO MODES:

  `pair`      one port row per CPython pattern, in order. Used where the port transcribes.
  `cover`     a CPython pattern may be SPLIT across several port rows (`pm_long_decomp`
              splits `GroupOp.Defines` and the STORE rule), so the rows whose ops fall
              inside one pattern are UNIONED and the union must equal the pattern's ops.
              Splitting a rule must neither drop an op nor invent one.

A PERMUTED BLOCK is admitted in both modes: `symbolic.bend` reorders the commutative op
group, and one reordered block is one `ORDER` row rather than k "wrong op set" rows.

`rej` IS COMPARED WITH `<=` AND NEVER `==`. `early_reject` is a NECESSARY condition
(`ops.py:1564`, `if not early_reject.issubset(ler): continue`), so a port row that demands
LESS than CPython fires more often and the body still answers `None` -- a cost, not a defect.
A port row that demands MORE skips a rewrite CPython performs, which no node count moves.
"""
import re

WINDOW = 12


def split_top(s: str) -> list[str]:
    """Split on commas at bracket depth 0, so `[A, B]` stays one field."""
    out, depth, cur = [], 0, ""
    for ch in s:
        depth += ch in "[{("
        depth -= ch in "]})"
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    return [p for p in (x.strip() for x in out) if p] + ([cur.strip()] if cur.strip() else [])


def macros(text: str) -> dict[str, frozenset[str]]:
    """Every `def NAME() -> List<&2, O.Op>:` in the file, expanded to its op names."""
    return {m.group(1): frozenset(re.findall(r"O\.Ops([A-Z0-9_]+)\{\}", m.group(2)))
            for m in re.finditer(r"^def ([\w.]+)\(\) -> List<&2, O\.Op>:(.*?)(?=^\S)",
                                 text, re.M | re.S)}


def opnames(expr: str, mac: dict[str, frozenset[str]]) -> frozenset[str]:
    """`Nil{}` | `NAME()` | `O.OpsA{}` | `[O.OpsA{}, O.OpsB{}]` -> the set, not the order."""
    expr = expr.strip()
    if expr == "Nil{}":
        return frozenset()
    m = re.fullmatch(r"([\w.]+)\(\)", expr)
    return mac.get(m.group(1), frozenset()) if m else frozenset(re.findall(r"O\.Ops([A-Z0-9_]+)\{\}", expr))


def table(text: str, name: str) -> list[tuple[int, str, str]]:
    """The `(tag, ops, rej)` triples of ONE `*_table()` def, in file order."""
    body = re.search(rf"^def {name}\(\) -> O\.PMEntrys:\n(.*?)(?=^def |\Z)", text, re.M | re.S)
    if body is None:
        return []
    out = []
    for line in body.group(1).split("\n"):
        if "O.PMEntry{" not in line:
            continue
        tail = re.sub(r"[\s,]+$", "", line.split("O.PMEntry{", 1)[1].split("#")[0])
        parts = split_top(re.sub(r"[\]\}\)]+$", "", tail))
        if len(parts) != 3:
            raise SystemExit(f"pmtable: REFUSED -- a PMEntry parsed into {len(parts)} fields, "
                             f"not 3: {line.strip()!r}")
        out.append((int(parts[0]), parts[1], parts[2]))
    return out


def _opsets(up) -> list[frozenset[str]]:
    return [frozenset(o.name for o in p.op) for p in up]


def pair(port, up, mac, rej_binds: bool = True) -> dict:
    """One port row per CPython pattern, admitting a permuted block."""
    want = _opsets(up)
    rows, order, ops, hazard, narrow, paired = [], [], [], [], 0, 0
    i = j = 0
    while i < len(want) and j < len(port):
        if opnames(port[j][1], mac) != want[i]:
            for k in range(1, min(WINDOW, len(want) - i, len(port) - j)):
                a = sorted(tuple(sorted(opnames(port[j + m][1], mac))) for m in range(k + 1))
                b = sorted(tuple(sorted(want[i + m])) for m in range(k + 1))
                if a == b:
                    order.append(f"pos={i}..{i + k} permuted; same {k + 1} op sets")
                    paired += k + 1
                    i, j = i + k + 1, j + k + 1
                    break
            else:
                ops.append(f"tag={port[j][0]} pos={i} port={sorted(opnames(port[j][1], mac))} "
                           f"up={sorted(want[i])}")
                i, j = i + 1, j + 1
            continue
        if rej_binds:
            prej = opnames(port[j][2], mac)
            urej = frozenset(o.name for o in up[i].early_reject)
            if prej <= urej:
                narrow += prej != urej
            else:
                hazard.append(f"tag={port[j][0]} pos={i} ops={sorted(want[i])} "
                              f"port={sorted(prej)} up={sorted(urej)}")
        rows.append(i)
        paired += 1
        i, j = i + 1, j + 1
    return {"rows": len(want), "port": len(port), "paired": paired, "narrow": narrow,
            "order": order, "ops": ops, "hazard": hazard}


def cover(port, up, mac) -> dict:
    """CPython pattern -> the UNION of the port rows whose ops fall inside it.

    For a table the port SPLITS, the union must equal the pattern's ops: an op the port
    dropped is a pattern arm that can never fire, and an op it invented belongs to no rule.
    """
    want = _opsets(up)
    got = [opnames(p[1], mac) for p in port]
    ops, missing, orphan = [], [], []
    for i, s in enumerate(want):
        inside = [g for g in got if g and g <= s]
        if not inside:
            missing.append(f"pos={i} ops={sorted(s)} has no port row inside it")
            continue
        union = frozenset().union(*inside)
        if union != s:
            ops.append(f"pos={i} port={sorted(union)} up={sorted(s)} "
                       f"(dropped {sorted(s - union)}, invented {sorted(union - s)})")
    for tag, g, in zip((p[0] for p in port), got):
        if not any(g <= s for s in want):
            orphan.append(f"tag={tag} ops={sorted(g)} is inside no CPython pattern")
    return {"rows": len(want), "port": len(port), "narrow": 0,
            "order": [], "ops": ops + orphan, "hazard": missing}


MODES = {"pair": pair, "cover": cover}
