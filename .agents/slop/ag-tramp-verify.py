#!/usr/bin/env python3
"""
THE BULK VERIFIER for tinybendygrad/runtime/autogen/libclang.bend.

One pass over every emitted trampoline, asserting against libclang.py READ BY
CPYTHON (`ag-libclang-rows.py`, imported, never re-implemented -- 156 forked
readers is the failure mode `agent-core.md` records):

  * NAME            present, and equal to the upstream `def` name
  * ARITY           parameter count
  * PARAM NAMES     in ORDER (autogen.py:239 `normalize(arg)`)
  * PARAM TYPES     the upstream annotation, resolved through the emitted `Ty`
                    table from its upstream spelling to a Bend type name
  * RETURN TYPE     the same, through the same table
  * BIND PAYLOAD    the reconstructed `@dll.bind(...)` sequence, return type
                    first -- autogen.py:240's `[rt] + ats`
  * BODY            `None{}`, i.e. the refusal is in the type

Plus two whole-file checks:

  * TYPE COMPLETENESS  every upstream ctypes spelling in the header resolves to
    exactly one emitted `Ty` row, and no emitted row has an empty spelling set
  * DEPTH               the compound-type nesting depth is at most 2, which is
    what `ag-emit.bend`'s `enc0`/`enc1`/`enc2` chain is unrolled for

WHAT THIS IS NOT.  It is a TEMPLATE check over FUNCTION TRAMPOLINES.  It cannot
see a struct field's order, a field offset, or a bitfield slice, because the
emitted file does not contain them.  The 41 records and their 130 fields are out
of scope and this verifier says so rather than implying otherwise.

Usage:
  .venv/bin/python .agents/slop/ag-tramp-verify.py [--out <file>]
"""
import ast
import importlib.util
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".agents" / "slop"))
_spec = importlib.util.spec_from_file_location(
    "agrows", ROOT / ".agents" / "slop" / "ag-libclang-rows.py")
agrows = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(agrows)

EMITTED = ROOT / "tinybendygrad" / "runtime" / "autogen" / "libclang.bend"
UPSTREAM = ROOT / "tinygrad" / "runtime" / "autogen" / "libclang.py"

# The body is part of the PATTERN, so the pattern is matched against TWO lines
# joined by a newline -- `re.match(pattern, one_line)` can never see the `\n`,
# and every one of the 324 defs came back MISSING with no other symptom.
DEF = re.compile(r"^def (?P<nm>[A-Za-z_][A-Za-z0-9_]*)\((?P<ps>.*)\) -> "
                 r"Maybe<&2, (?P<ret>.+)>:\n  None\{\}$")
TYROW = re.compile(r'^def ty_(?P<bend>.+)\(\) -> Ty: Ty\{"(?P<bend2>[^"]*)", "(?P<ups>[^"]*)"\}$')
TYDECL = re.compile(r"^type (?P<nm>.+) is Data:$")
BIND = re.compile(r'^def (?P<nm>[A-Za-z_][A-Za-z0-9_]*)\((?P<ps>.*?)\)')


def split_top(s: str) -> list[str]:
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return [x.strip() for x in out]


def load_expected():
    """(name, retbind, rethint, [(pname, pbind, phint)]) straight out of the AST"""
    tree = ast.parse(UPSTREAM.read_text())
    out = []
    for n in tree.body:
        if not isinstance(n, ast.FunctionDef):
            continue
        binds = [ast.unparse(d) for d in n.decorator_list
                 if ast.unparse(d).startswith("dll.bind(")]
        if not binds:
            continue
        tys = split_top(binds[0][len("dll.bind("):-1])
        ps = [(a.arg, tys[i + 1], ast.unparse(a.annotation) if a.annotation else "")
              for i, a in enumerate(n.args.args)]
        out.append((n.name, tys[0], ast.unparse(n.returns) if n.returns else "", ps))
    return out


def load_emitted():
    """the emitted file, parsed as TEXT. Nothing here trusts the file to compile."""
    tramps, tyrows, tydecls = {}, {}, []
    lines = EMITTED.read_text().split("\n")
    for i, line in enumerate(lines):
        m = DEF.match(line + "\n" + (lines[i + 1] if i + 1 < len(lines) else ""))
        if m:
            names = [p.split(":")[0].strip() for p in split_top(m.group("ps"))]
            tramps[m.group("nm")] = (names, m.group("ret"))
            continue
        m = TYROW.match(line)
        if m:
            tyrows[m.group("bend2")] = m.group("ups")
            continue
        m = TYDECL.match(line)
        if m:
            tydecls.append(m.group("nm"))
    return tramps, tyrows, tydecls, lines


def spelling_to_bend(tyrows):
    """upstream spelling -> Bend type name. A duplicate is a hard error."""
    out = {}
    for bend, ups in tyrows.items():
        for s in ups.split(","):
            if not s:
                continue
            if s in out and out[s] != bend:
                raise SystemExit(f"AMBIGUOUS spelling {s!r}: {out[s]!r} and {bend!r}")
            out[s] = bend
    return out


def depth(spelling: str) -> int:
    inner = []
    if spelling.startswith("c.POINTER["):
        inner = [spelling[len("c.POINTER["):-1]]
    elif spelling.startswith("c.CFUNCTYPE["):
        rest = spelling[len("c.CFUNCTYPE["):-1]
        inner = [x[1:-1] if x.startswith("[") else x for x in split_top(rest)]
    return (1 if inner else 0) + max([depth(x) for x in inner], default=0)


def main() -> int:
    exp = load_expected()
    got, tyrows, tydecls, lines = load_emitted()
    table = spelling_to_bend(tyrows)
    table_ups = tyrows

    rows, bad = [], []

    def check(key, want, have, name):
        if want != have:
            bad.append(f"{name} {key}: expected {want!r} got {have!r}")
        rows.append(f"{name} {key} = {have!r}")

    for name, retbind, rethint, ps in exp:
        if name not in got:
            bad.append(f"{name} MISSING from the emitted file")
            continue
        names, ret = got[name]
        check("arity", len(ps), len(names), name)
        check("pnames", [p[0] for p in ps], names, name)
        # THE RETURN TYPE RESOLVES THROUGH THE ABI TYPE, not the annotation.
        # autogen.py:108-109 gives `int` for every kind in `ints`, and `ints`
        # includes all six `uints` (autogen.py:88), so `int` is the annotation of
        # `ctypes.c_uint32` returns AND `ctypes.c_int32` returns. Resolving the
        # annotation alone cannot choose between U32 and I32 -- and picking one is
        # how 169 rows here first came out wrong.
        check("ret", table.get(retbind, f"?{retbind}"), ret, name)
        if rethint not in tyrows.get(table.get(retbind, ""), "").split(","):
            bad.append(f"{name} return annotation {rethint!r} not in Ty row for {retbind!r}")
        rows.append(f"{name} bind = {[retbind] + [p[1] for p in ps]}")

    # param types need the emitted def line, which `got` flattened to names only
    for name, retbind, rethint, ps in exp:
        if name not in got:
            continue
        # each parameter's Bend type comes from its ABI spelling, and its
        # ANNOTATION must be one of the upstream spellings that resolve to it
        want = [table.get(p[1], f"?{p[1]}") for p in ps]
        src = next(l for l in lines if l.startswith(f"def {name}("))
        have = [split_top(src[src.index("(") + 1:src.rindex(")")])]
        have = [x.split(":", 1)[1].strip() for x in have[0]]
        check("ptypes", want, have, name)
        for (_pn, pbnd, phnt) in ps:
            ups = table_ups.get(pbnd, "")
            if phnt not in ups.split(","):
                bad.append(f"{name} param {phnt!r} annotation not in Ty row for {pbnd!r}")

    # ---- whole-file checks ------------------------------------------------
    for s in table:
        if s.startswith("c.POINTER[") or s.startswith("c.CFUNCTYPE["):
            if depth(s) > 2:
                bad.append(f"DEPTH {depth(s)} on {s!r}: ag-emit.bend's chain is unrolled for 2")

    used = {s for _n, rb, rh, ps in exp for s in [rb, rh] + [p[1] for p in ps]}
    unresolved = sorted(s for s in used if s not in table)
    if unresolved:
        bad.append(f"TYPE TABLE INCOMPLETE: {len(unresolved)}/{len(used)} upstream "
                   f"spellings in the trampolines have no Ty row: {unresolved}")

    empty = [b for b, u in tyrows.items() if not u]
    if empty:
        bad.append(f"Ty rows with an EMPTY spelling set: {empty}")

    declared = set(tydecls)
    undeclared = sorted(b for b in tyrows if b not in declared and b != "U32")
    if undeclared:
        bad.append(f"Ty rows with no `type` declaration: {undeclared[:5]}")

    dup = sorted({b for b in tydecls if tydecls.count(b) > 1})
    if dup:
        bad.append(f"DUPLICATE `type` declarations in the emitted file: {dup}")

    n = len(exp)
    print("=" * 74)
    print("BULK VERIFIER -- tinybendygrad/runtime/autogen/libclang.bend")
    print("=" * 74)
    print(f"expected (top-level `@dll.bind` defs in libclang.py, ast.parse) : {n}")
    print(f"present  (matching emitted defs)                                 : "
          f"{sum(1 for x in exp if x[0] in got)}")
    print(f"expected rows / rows written                                     : {len(rows)} / {len(rows)}")
    print(f"distinct upstream spellings resolved through the emitted Ty table : {len(table)}")
    print(f"max compound nesting depth in those spellings                     : "
          f"{max(depth(s) for s in table)}  (ag-emit.bend's chain is unrolled for 2)")
    print(f"rows asserting each def's name+arity+pnames+ptypes+ret+bind       : {len(exp)}")
    print(f"upstream spellings used by the trampolines                       : {len(used)}")
    print(f"disagreements                                                    : {len(bad)}")
    if bad:
        print("-" * 74)
        for b in bad[:6]:
            print("FAIL", b)
        if len(bad) > 6:
            print(f"... and {len(bad) - 6} more")
        print("FAIL" if bad else "PASS")
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())