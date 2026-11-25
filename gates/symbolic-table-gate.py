#!/usr/bin/env python3
"""symbolic-table-gate.py -- is `symbolic.bend`'s rule TABLE still CPython's rule table?

    .venv/bin/python gates/symbolic-table-gate.py

A `PMEntry` is `{tag, ops, rej}`: the ops the root may be, and the ops that must appear among
its SOURCES. CPython derives both from the `UPat` itself -- `p.op` and `p.early_reject`
(`tinygrad/uop/ops.py:1554`, `entry=[p, None, p.early_reject]`) -- so the table is not a
transcription at all. It is a PROJECTION of `sym.patterns`, and this gate projects it.

THE POPULATION IS THE ORACLE'S OWN DECLARATION (doctrine 1a). Nothing here is typed: the
oracle side is `tinygrad.uop.symbolic`'s matcher objects, and the port side is PARSED out of
`tinybendygrad/uop/symbolic.bend`'s `*_table()` defs, with the macros expanded from that
file's own `def OP_*` bodies.

`sym` AND NOT `symbolic`, AND THE DIFFERENCE IS NOT COSMETIC: the file composes

    sym = symbolic + pm_simplify_valid + PatternMatcher([...]) + pm_clean_up_group_sink

so `symbolic` is only the FIRST of four matchers `sym` sums (119 of 133). A comparison
against `symbolic` reported the last 14 rows as unpaired when they are simply the next
matcher's, which is the shape of false positive this gate exists to avoid, committed here
once so the next reader does not repeat it.

THREE TABLES, THREE DIFFERENT CONTRACTS:

  sym_table     DISPATCHED, so its `rej` matters -- compared in full against `sym` minus
                `pm_simplify_valid`'s two rows, which the port routes elsewhere.
  rm_table      DISPATCHED (`rm_rewrite`), compared in full against `pm_remove_invalid`.
  valid_table   A LEDGER, NOT A DISPATCH. `symbolic.bend:5909` reads ONLY `valid_table()`'s
                LENGTH -- it is added to `sym_table`'s so the port can report CPython's 133
                while two rules are unported (`symbolic.py:450`, `:451`, and the comment at
                `symbolic.bend:5914` says so). A `rej` hazard there would be a FALSE POSITIVE:
                a table nobody consults cannot skip a rewrite. Ops only.

THREE WAYS A HAND-COPIED ROW GOES WRONG, AND THEY ARE NOT THE SAME SEVERITY:

  OPS      the row claims a different op set, so the rewrite fires on the wrong nodes.
  HAZARD   the row's `rej` demands an op upstream does not. `early_reject` is a NECESSARY
           condition (`ops.py:1564`, `if not early_reject.issubset(ler): continue`), so
           demanding MORE than upstream means the port SKIPS a rewrite CPython performs.
           This is the silent one: node counts do not move, the graph is just less rewritten.
  NARROW   the row's `rej` is a SUBSET of upstream's. Harmless by construction -- the body
           still answers `None` -- so it is COUNTED, not failed: dropping a fast path costs
           time, it does not change an answer.

`rej` is compared with `<=` and not `==` for exactly that reason. An `==` here reports 72
harmless rows as failures and buries the ones that matter.

THE THREE ROWS THIS GATE FOUND, ALL NOW FIXED (2026-11-25). Each was a `rej` that named
`CONST`, and each body's own guard is what said the row was wrong:

  tag 2  (`symbolic.py:91`, the Invalid-moves-inside-the-gate rule) demanded `CONST` while
         its `UPat` src is `invalid_gate`, a `WHERE`. `sym_84.pat` reads `p_where_gate(x,u,0)`
         -- the body wants a WHERE at src 0 -- so with `{CONST}` the entry could NEVER fire
         and the rule was dead. Now `[O.OpsWHERE{}]`.
  tag 12/13 (`:108`/`:110`, fold gated STORE/LOAD) demanded `CONST` while upstream requires
         nothing (`early_reject=[]`) and the test lives in the src pattern, `INDEX.or_casted()`,
         which a disjunction cannot put in `early_reject`. Bodies `sym_101`/`sym_103` carry
         that test in `p_index_bad_or_cast`. Now `Nil{}`.
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gatekit import DEAD, FAIL, PASS, REFUSED  # noqa: E402  (house vocabulary, never re-spelled)

ROOT = pathlib.Path(__file__).resolve().parents[1]
PORT = ROOT / "tinybendygrad/uop/symbolic.bend"
WINDOW = 12

# (port table, oracle matcher, matcher whose rows the port routes elsewhere, does `rej` bind?)
PAIRS = (("sym_table", "sym", "pm_simplify_valid", True),
         ("rm_table", "pm_remove_invalid", None, True),
         ("valid_table", "pm_simplify_valid", None, False))


def split_top(s: str) -> list[str]:
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
    """`def OP_X() -> List<&2, O.Op>:` bodies, by name -- the file's own spelling, expanded."""
    return {m.group(1): frozenset(re.findall(r"O\.Ops([A-Z0-9_]+)\{\}", m.group(2)))
            for m in re.finditer(r"^def (OP_\w+)\(\) -> List<&2, O\.Op>:(.*?)(?=^\S)",
                                 text, re.M | re.S)}


def opnames(expr: str, mac: dict[str, frozenset[str]]) -> frozenset[str]:
    """`Nil{}` | `OP_X()` | `O.OpsA{}` | `[O.OpsA{}, O.OpsB{}]` -> the set, never a list order."""
    expr = expr.strip()
    if expr == "Nil{}":
        return frozenset()
    m = re.fullmatch(r"(OP_\w+)\(\)", expr)
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
            raise SystemExit(f"symbolic-table-gate: REFUSED -- a PMEntry parsed into "
                             f"{len(parts)} fields, not 3: {line.strip()!r}")
        out.append((int(parts[0]), parts[1], parts[2]))
    return out


def compare(port, up, mac, rej_binds: bool) -> dict:
    """Pair ONE port table against ONE oracle list, positionally, admitting a permuted block."""
    def oset(p):
        return frozenset(o.name for o in up[p].op)

    rows, order, ops, hazard, narrow, paired = [], [], [], [], 0, 0
    i = j = 0
    while i < len(up) and j < len(port):
        if opnames(port[j][1], mac) != oset(i):
            for k in range(1, min(WINDOW, len(up) - i, len(port) - j)):
                a = sorted(tuple(sorted(opnames(port[j + m][1], mac))) for m in range(k + 1))
                b = sorted(tuple(sorted(oset(i + m))) for m in range(k + 1))
                if a == b:
                    order.append(f"pos={i}..{i + k} permuted; same {k + 1} op sets")
                    paired += k + 1
                    i, j = i + k + 1, j + k + 1
                    break
            else:
                ops.append(f"tag={port[j][0]} pos={i} port={sorted(opnames(port[j][1], mac))} "
                           f"up={sorted(oset(i))}")
                i, j = i + 1, j + 1
            continue
        if rej_binds:
            prej = opnames(port[j][2], mac)
            urej = frozenset(o.name for o in up[i].early_reject)
            if prej <= urej:
                narrow += prej != urej
            else:
                hazard.append(f"tag={port[j][0]} pos={i} ops={sorted(oset(i))} "
                              f"port={sorted(prej)} up={sorted(urej)}")
        rows.append(i)
        paired += 1
        i, j = i + 1, j + 1
    return {"rows": len(up), "port": len(port), "paired": paired, "narrow": narrow,
            "order": order, "ops": ops, "hazard": hazard}


def main() -> int:
    text = PORT.read_text()
    mac = macros(text)
    if not mac:
        print("== DEAD: symbolic-table-gate: no `OP_*` macro parsed -- every row would read as "
              "an empty op set and agree with nothing")
        return DEAD

    import tinygrad.uop.symbolic as sym

    bad = 0
    for tname, mname, ename, rej_binds in PAIRS:
        port = table(text, tname)
        matcher = getattr(sym, mname, None)
        if not port or matcher is None or not matcher.patterns:
            print(f"== DEAD: symbolic-table-gate: `{tname}` parsed {len(port)} rows and "
                  f"`{mname}` declares {len(getattr(matcher, 'patterns', []))} -- one side is "
                  "empty, so nothing was compared")
            return DEAD
        ex = {id(p) for p, _ in getattr(sym, ename).patterns} if ename else set()
        up = [p for p, _ in matcher.patterns if id(p) not in ex]
        # `sym` sums matchers whose `UPat` objects are shared, so the exclusion is by UPat
        # identity and not by tuple identity; `PatternMatcher.__init__` rebuilds the tuples.
        r = compare(port, up, mac, rej_binds)
        print(f"{tname}: oracle={mname}{'\\' + ename if ename else ''} rows={r['rows']} "
              f"port={r['port']} paired={r['paired']} "
              f"narrow={r['narrow']} hazard={len(r['hazard'])} ops={len(r['ops'])} "
              f"order={len(r['order'])}" + ("" if rej_binds else "  (rej not bound: ledger)"))
        for label in ("order", "ops", "hazard"):
            for line in r[label]:
                print(f"  {label.upper()} {line}")
        bad += len(r["ops"]) + len(r["hazard"]) + (r["port"] != r["rows"])

    if bad:
        print(f"== FAIL: symbolic-table-gate: {bad} row(s) disagree with CPython or are unpaired")
        return FAIL
    print("== PASS: symbolic-table-gate: every dispatched row carries CPython's op set, no row "
          "demands an early-reject op CPython does not, and no rule is unaccounted for")
    return PASS


if __name__ == "__main__":
    sys.exit(main())
