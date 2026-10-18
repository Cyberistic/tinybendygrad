"""The rows `checks/differ.py` writes into `D0-run-summary.txt`, and where each denominator comes from.

READ-ONLY over the tree. `ast.parse` only; `differ.py` is NEVER imported (its module scope builds
`ENV`/`D` and its commands shell out to `bend`). Its five counting helpers ARE executed, extracted
by `ast` from their own source and exec'd over a fixture copy, so the `+1 member` readings below are
the writer's own predicates over a grown population rather than a re-implementation of them.

Usage: .venv/bin/python .agents/slop/pins34/enumerate.py
"""

import ast
import fnmatch
import re
from collections import Counter
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DIFFER = ROOT / "checks/differ.py"
RUN = ROOT / "runs/graphcmp/D"
HERE = Path(__file__).resolve().parent
FIXTURE = HERE / "fixture"
COPIED = ("D9-stability.txt", "D2-bytediff.txt", "D0-selfcheck.txt", "D0-coverage-census.txt")
COPIED_PREFIX = ("D1-graph-", "D3-control-", "D4-", "D5-plant-", "D7-conf")
HELPERS = ("text", "lines_with", "anchored", "files_with", "grep_line", "first_line", "last_line")


def assign(tree: ast.Module, name: str) -> ast.Assign:
    return next(n for n in tree.body if isinstance(n, ast.Assign)
                and getattr(n.targets[0], "id", "") == name)


def literal_or_source(node: ast.expr):
    """`literal_eval` where the assignment is a literal, its unparse where it is not
    (`ROW_KEYS` is `("dev",) + tuple(ROW_VALUES)`, so the keys are read from `ROW_VALUES`)."""
    try:
        return ast.literal_eval(node)
    except ValueError:
        return ast.unparse(node)


def declared_len(node: ast.expr) -> int:
    """How many members a declaration yields, STRUCTURALLY. `STAB` is
    `tuple(...) + ((...),)` and `PLANTS` is `tuple(...) + ((...),)`, so neither is a literal
    `eval` can read; this sums the halves and counts a generator by the length of the literal
    it walks. No `eval`, no hand copy of the member names."""
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        return declared_len(node.left) + declared_len(node.right)
    if isinstance(node, ast.Tuple):
        return len(node.elts)
    if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "tuple"
            and len(node.args) == 1 and isinstance(node.args[0], ast.GeneratorExp)):
        return declared_len(node.args[0].generators[0].iter)
    raise ValueError(ast.unparse(node))


def precondition_keys(tree: ast.Module, row_values: dict) -> list[str]:
    """`precondition_rows()`'s keys, read off its own return statement."""
    fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "precondition_rows")
    joined = next(n for n in fn.body if isinstance(n, ast.Return)).value
    if not isinstance(joined, ast.BinOp):
        sys.exit(f"REFUSED: precondition_rows is not a join this reader parses: {ast.unparse(joined)}")
    head = next(n for n in ast.walk(joined) if isinstance(n, ast.List))
    comp = next((n for n in ast.walk(joined) if isinstance(n, ast.ListComp)), None)
    if comp is None or ast.unparse(comp.generators[0].iter) != "ROW_VALUES":
        sys.exit(f"REFUSED: precondition_rows does not iterate ROW_VALUES: {ast.unparse(joined)}")
    (elem,) = head.elts
    return [elem.values[0].value.rpartition("=")[0], *row_values]


def helpers(d: Path) -> dict:
    """exec only `HELPERS` out of differ.py, bound to fixture dir `d`."""
    keep = [n for n in ast.parse(DIFFER.read_text()).body
            if isinstance(n, ast.FunctionDef) and n.name in HELPERS]
    if {n.name for n in keep} != set(HELPERS):
        sys.exit(f"REFUSED: {DIFFER} lacks {sorted(set(HELPERS) - {n.name for n in keep})}")
    scope = {"re": re, "D": d}
    exec(compile(ast.fix_missing_locations(ast.Module(body=keep, type_ignores=[])),
                 str(DIFFER), "exec"), scope)  # noqa: S102
    return scope


def summary_rows(tree: ast.Module) -> tuple[list[dict], list[str]]:
    """The `write("D0-run-summary.txt", "\\n".join([...]))` list, in source order."""
    for node in ast.walk(tree):
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "write"
                and isinstance(node.args[0], ast.Constant) and node.args[0].value == "D0-run-summary.txt"):
            lst = next(n for n in ast.walk(node.args[1]) if isinstance(n, ast.List))
            rows, starred = [], []
            for elt in lst.elts:
                if isinstance(elt, ast.Starred):
                    starred.append(ast.unparse(elt.value))
                elif isinstance(elt, ast.JoinedStr):
                    head, *rest = elt.values
                    rows.append({"key": head.value.rpartition("=")[0],
                                 "tail": "".join(v.value for v in rest if isinstance(v, ast.Constant)).strip(),
                                 "expr": ast.unparse(rest[0].value)})
                else:
                    sys.exit(f"REFUSED: {DIFFER} writes a row this reader does not parse: "
                             f"{ast.unparse(elt)}")
            return rows, starred
    sys.exit("REFUSED: no write('D0-run-summary.txt', ...) call")


def build_fixture() -> Path:
    if FIXTURE.exists():
        shutil.rmtree(FIXTURE)
    FIXTURE.mkdir(parents=True)
    for f in RUN.iterdir():
        if f.is_file() and (f.name in COPIED or f.name.startswith(COPIED_PREFIX)):
            shutil.copy2(f, FIXTURE / f.name)
    return FIXTURE


def write(d: Path, name: str, body: str) -> None:
    (d / name).write_text(body)


def append(d: Path, name: str, line: str) -> None:
    with (d / name).open("a") as fh:
        fh.write(line + "\n")


# ONE NEW MEMBER PER AXIS. `good` is the member the row COUNTS (a plant that disagrees, a control
# that agrees, a pair that is byte-identical); `bad` is the member the row exists to catch.
MEMBER = {
    "stab-identical": ("D9-stability.txt", "newsix: 2 runs BYTE-IDENTICAL"),
    "stab-differ": ("D9-stability.txt", "newsix: 2 runs DIFFER"),
    "stab-0row": ("D9-stability.txt", "newsix: ONE SIDE IS A 0-ROW FAILURE after a retry"),
    "plant-loadbearing": ("D5-plant-newsix.txt", "VERDICT: DISAGREE"),
    "plant-agrees": ("D5-plant-newsix.txt", "VERDICT: AGREE"),
    "control-ok": ("D3-control-newsix.txt", "CONTROL VERDICT: OK"),
    "control-fails": ("D3-control-newsix.txt", "CONTROL VERDICT: FAILED"),
    "conf-ok": ("D7-conf.txt", "VERDICT: OK"),
    "conf-disputed": ("D7-conf.txt", "VERDICT: DISPUTED"),
    "cross-ok": ("D4-cross-range.txt", "CROSS VERDICT: OK"),
    "cross-fails": ("D4-cross-range.txt", "CROSS VERDICT: FAILED"),
    "cross-new-file-fails": ("D4-cross-newsix.txt", "CROSS VERDICT: FAILED"),
}


def main() -> int:
    tree = ast.parse(DIFFER.read_text())
    PINS = ast.literal_eval(assign(tree, "PINS").value)
    row_values = ast.literal_eval(assign(tree, "ROW_VALUES").value)
    substrate_rows = ast.literal_eval(assign(tree, "SUBSTRATE_ROWS").value)
    row_keys = precondition_keys(tree, row_values)
    rows, starred = summary_rows(tree)
    lits = {n: declared_len(assign(tree, n).value) for n in ("STAB", "PLANTS", "CONTROLS")}
    cross_calls = sum(isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id == "run"
                      and any(isinstance(a, ast.Constant) and a.value == "cross" for a in n.args)
                      for n in ast.walk(tree))

    writer_keys = [r["key"] for r in rows] + list(row_keys) + list(substrate_rows)
    live_pairs = [ln.split("=", 1) for ln in (RUN / "D0-run-summary.txt").read_text().splitlines()
                  if "=" in ln]
    live_keys, live = [k for k, _ in live_pairs], dict(live_pairs)
    print("== THE CONTROL: WRITER'S KEYS vs THE LIVE FILE ==")
    print(f"writer rows in source: {len(rows)} + {len(row_keys)} precondition + "
          f"{len(substrate_rows)} substrate = {len(writer_keys)}")
    print(f"live keys:             {len(live_keys)}")
    print(f"same set:              {set(writer_keys) == set(live_keys)}")
    print(f"same order:            {writer_keys == live_keys}")
    print(f"only in writer:        {sorted(set(writer_keys) - set(live_keys)) or 'none'}")
    print(f"only in live file:     {sorted(set(live_keys) - set(writer_keys)) or 'none'}")
    print(f"starred rows:          {starred}")
    print()

    print("== EVERY ROW, ITS NUMERATOR EXPRESSION, ITS DENOMINATOR, AND WHERE THE DENOMINATOR LIVES ==")
    for r in rows:
        print(f"{r['key']:<18} numerator= {r['expr']:<58} denominator= {'1' if not r['tail'] else r['tail']}")
    print()

    code_resident = [r for r in rows if r["tail"]]
    print(f"code-resident `of N` denominators: {len(code_resident)} of {len(rows)} written rows -> "
          f"{sorted(r['key'] for r in code_resident)}")
    print()

    base = build_fixture()
    scope = helpers(base)
    now = {r["key"]: eval(r["expr"], scope) for r in code_resident}  # noqa: S307
    print("== THE CODE-RESIDENT ROWS, READ BY THE WRITER'S OWN PREDICATES OVER THE LIVE ARTIFACTS ==")
    for r in code_resident:
        key, lit = r["key"], int(r["tail"].split()[1])
        live_row = f"{now[key]} of {lit}"
        print(f"{key:<18} measured now={live_row:<10} live file={live[key]:<10} "
              f"pin={PINS[key]:<10} pin matches now: {PINS[key] == live_row}")
    print()

    print("== POPULATION SIZE AS THE WRITER'S OWN DECLARATIONS COUNT IT (code, not the literal) ==")
    print(f"len(STAB)={lits['STAB']} len(PLANTS)={lits['PLANTS']} len(CONTROLS)={lits['CONTROLS']} "
          f"run(...,'cross',...) call sites={cross_calls}")
    print(f"literal 'of 5' vs len(STAB)={lits['STAB']}; 'of 7' vs len(PLANTS)={lits['PLANTS']}; "
          f"'of 5' vs len(CONTROLS)={lits['CONTROLS']}; 'of 1' vs cross call sites={cross_calls}")
    print(f"conflations: no differ.py declaration names the population (the `conf` oracle does) -- "
          f"denominator 4 is typed in the f-string only")
    print()

    print("== +1 MEMBER, EACH VARIANT: WHAT THE ROW WOULD READ AND WHETHER THE PIN STILL FIRES ==")
    for r in code_resident:
        key, lit = r["key"], int(r["tail"].split()[1])
        print(f"-- {key} (pin {PINS[key]!r}, denominator literal {lit})")
        for label, (fname, body) in MEMBER.items():
            if not touches(label, key):
                continue
            if FIXTURE.exists():
                shutil.rmtree(FIXTURE)
            build_fixture()
            append(FIXTURE, fname, body)
            got = eval(r["expr"], helpers(FIXTURE))  # noqa: S307
            row = f"{got} of {lit}"
            print(f"   + {label:<22} row={row:<10} pin {'FIRES (red)' if PINS[key] != row else 'SILENT (green)'}"
                  f"{'   <-- FALSE AGREEMENT' if PINS[key] == row else ''}")
    print("== PINS: EVERY PINNED KEY IS A ROW THE WRITER WRITES ==")
    print(f"PINS keys: {len(PINS)};  pinned-but-unwritten: {sorted(set(PINS) - set(writer_keys)) or 'none'}")
    print(f"written-but-unpinned: {sorted(set(writer_keys) - set(PINS)) or 'none'}")
    print()

    print("== +1 MEMBER AS A PIN SET: DOES A SIBLING ROW CATCH WHAT ITS OWN DENOMINATOR HIDES? ==")
    trio = ("stable-pairs", "stable-failed", "stable-differ")
    for label in ("stab-identical", "stab-differ", "stab-0row"):
        shutil.rmtree(FIXTURE)
        build_fixture()
        append(FIXTURE, *MEMBER[label])
        sc = helpers(FIXTURE)
        rowsread = {k: f"{eval(nexpr[k], sc)} of 5" for k, nexpr in
                    ((r["key"], {r["key"]: r["expr"]}) for r in code_resident if r["key"] in trio)}
        red = [k for k, v in rowsread.items() if PINS[k] != v]
        print(f"   + {label:<16} trio reads {rowsread} -> "
              f"{'red on ' + ', '.join(red) if red else 'ALL THREE GREEN (set-level FALSE AGREEMENT)'}")
    print()

    print("== WHICH ROWS CAN SEE A GIVEN GROWTH AT ALL (artifact intersection, fnmatch over the exprs) ==")
    patterns = {r["key"]: re.findall(r"'([^']+)'", r["expr"]) for r in rows}
    for label, (fname, _) in MEMBER.items():
        seen = sorted(k for k, pats in patterns.items() if any(fnmatch.fnmatch(fname, p) for p in pats))
        print(f"   {label:<22} {fname:<26} seen only by: {seen}")
    print("== THE BARE-COUNT ROWS: A CORPUS THAT GREW BY ONE, READ BY THE WRITER'S PREDICATES ==")
    n_now = int(live["graphs"])
    bare = [r for r in rows if not r["tail"]]
    corpus_cases = {
        "as published (live run)": (n_now, int(live["graphs-unset"]), int(live["expect-moved"]),
                                    int(live["graphs-refused"]), None),
        "+1 graph, agrees": (n_now + 1, 0, 0, 1, "VERDICT: AGREE"),
        "+1 graph, disagrees": (n_now + 1, 0, 1, 1, "VERDICT: DISAGREE"),
        "+1 graph, no expectation": (n_now + 1, 1, 0, 1, None),
        "+1 graph, refused": (n_now + 1, 0, 0, 2, None),
    }
    base_rows = {}
    for case, (n, u, m, rf, verdict) in corpus_cases.items():
        shutil.rmtree(FIXTURE)
        build_fixture()
        if verdict:
            write(FIXTURE, "D1-graph-newsix.txt", f"{verdict}\n")
            append(FIXTURE, "D2-bytediff.txt", f"newsix CANONICAL BYTE-IDENTICAL\n")
        sc = helpers(FIXTURE)
        sc.update(graphs=[f"g{i}" for i in range(n)], unset=[0] * u, moved=[0] * m, refused=[0] * rf)
        got = {r["key"]: eval(r["expr"], sc) for r in bare}  # noqa: S307
        if case.startswith("as published"):
            base_rows = got
            drift = {r["key"]: (got[r["key"]], live[r["key"]]) for r in bare
                     if r["key"] in live and str(got[r["key"]]) != live[r["key"]]}
            print(f"-- {case}: reader vs live file disagree on {drift or 'no row'}")
        red = [r["key"] for r in bare if r["key"] in PINS and PINS[r["key"]] != str(got[r["key"]])]
        moved_rows = {r["key"]: str(got[r["key"]]) for r in bare if str(got[r["key"]]) != base_rows.get(r["key"])}
        print(f"-- {case:<26} pins red: {red or 'none'}\n   rows that moved: {moved_rows or 'none'}")
    print()
    print("== THE LIVE RUN AGAINST PINS, RIGHT NOW (no simulation) ==")
    for k, want in PINS.items():
        print(f"   {'OK  ' if live.get(k) == want else 'RED '} {k:<18} live={live.get(k)!r:<26} pin={want!r}")
    print("== THE SECOND WITNESS: derive.py RE-DERIVES THE ROWS, SO DOES IT RE-TYPE THE DENOMINATORS? ==")
    derive_src = (ROOT / ".agents/slop/pinindep/derive.py").read_text()
    dtree = ast.parse(derive_src)
    drow = next(n for n in ast.walk(dtree) if isinstance(n, ast.Assign)
                and getattr(n.targets[0], "id", "") == "rows" and isinstance(n.value, ast.List))
    dkeys = [e.elts[0].value for e in drow.value.elts if isinstance(e, ast.Tuple)]
    dfstrs = [n for n in ast.walk(dtree) if isinstance(n, ast.JoinedStr)]
    dlits = [v.value.strip() for n in dfstrs for v in n.values
                    if isinstance(v, ast.Constant) and v.value.startswith(" of ")]
    print(f"derive.py re-derives {len(dkeys)} named rows + precondition_rows(); writer writes "
          f"{len(writer_keys)}")
    print(f"keys the writer writes and derive.py does not: "
          f"{sorted(set(writer_keys) - set(dkeys) - set(row_keys) - set(substrate_rows))}")
    print(f"`of N` literals re-typed in derive.py: {dlits}")
    print(f"same multiset as the writer's: "
          f"{Counter(dlits) == Counter(r['tail'] for r in code_resident)} "
          f"-- writer {dict(Counter(r['tail'] for r in code_resident))}, "
          f"derive {dict(Counter(dlits))}")
    print(f"derive.py docstring claims the live summary carries: "
          f"{re.findall(r'live summary carries (\d+)', derive_src)}  writer writes {len(writer_keys)}")
    # The fixture is 100 COPIES OF `.txt` ARTIFACTS. `checks/no-txt.py` counts owned `.txt`, so a
    # left-behind fixture is 100 new rows in a census this tree is trying to drive to zero. It is
    # rebuilt from `runs/graphcmp/D` by `build_fixture()` on every run and is thrown away here.
    shutil.rmtree(FIXTURE)
    print(f"fixture removed: {not FIXTURE.exists()} (rebuilt by build_fixture() on every run)")
    return 0


def touches(label: str, key: str) -> bool:
    axis = {"stable-pairs": ("stab-",), "stable-failed": ("stab-",), "stable-differ": ("stab-",),
            "plants-disagree": ("plant-",), "controls": ("control-",), "conflations": ("conf-",),
            "cross": ("cross-",)}[key]
    return label.startswith(axis)


if __name__ == "__main__":
    sys.exit(main())