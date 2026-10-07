#!/usr/bin/env python3
"""RE-DERIVE the zero-surface gates and the untested entry points. Do not inherit them.

    .venv/bin/python .agents/slop/zerogate/derive.py            # the two named lists
    .venv/bin/python .agents/slop/zerogate/derive.py --rows > .agents/slop/zerogate/derive.rows

DOCTRINE 1, APPLIED TO THE COWORKER'S OWN ARTIFACTS. `coindependent/surface.py:25` holds
`NEEDS_BEND` as a HAND LIST of 42 paths -- the exact class its own report names as the tree's
seventh failing member. So this file DISCOVERS both populations instead:

  * the ENTRY POINTS come from `coindependent/vocab.py:scan()`, which is `os.walk`, IMPORTED BY
    PATH. One implementation, two consumers. Not a second list of gate names.
  * the REACHED column comes from `coindependent/probe.rows` + `twostate.rows`, read by path.

WHAT IS EXECUTED, AND WHY THE RULE IS A RULE AND NOT A LIST. This unit may not start `bend`
(1.4 GB per file, and `AGENTS.md`'s parallelisation precondition is about the SUM). So
`starts_bend()` asks each gate's OWN SOURCE whether it can reach `bin/bend` -- by the two spellings
the tree uses (`gatekit.BEND` via `gatekit`, and a literal `./bin/bend` in a subprocess argv). A
gate that names neither cannot start the port compiler, and that is a property of the file, so it
is derived from the tree rather than asserted by a list. Gates that DO name it are reported
UNRUN and their reached column stays whatever the coworker observed; this unit claims nothing
about them.

WHAT IT ADDS THAT `coindependent` COULD NOT. That unit's `declared` column is a LOWER BOUND
(`vocab.py:26-30` says so: a computed `sys.exit(1 if bad else 0)` is invisible to an
integer-literal scan), and TWO OF ITS NINE were never run at all -- they carry `(none)` in the
reached column and the report nonetheless explained them FROM the declared column. So the
zero-surface list here is not read off a table: every candidate is EXECUTED and its refusal is
located with `file:line`.
"""
import ast
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CO = HERE.parent / "coindependent"

sys.path.insert(0, str(CO))
import vocab  # noqa: E402  -- the population generator, IMPORTED BY PATH, never copied

TOKENS = ("REFUSED", "AGREE", "BROKEN", "GREEN", "RED", "PASS", "FAIL", "DEAD", "SKIP",
          "SELFTEST", "Traceback")
# `bin/bend`, however spelled: gatekit's `BEND` constant, a literal path, or `BEND` imported by name.
BEND = re.compile(r"bin/bend|\bBEND\b|from\s+gatekit\s+import[^#]*\bBEND\b")


def starts_bend(src: str) -> bool:
    return bool(BEND.search(src))


def entry_points():
    """`vocab.scan()` is `os.walk`. That unit's generator, this unit's second consumer."""
    return [r for r in vocab.scan() if r["reason"] in ("py-main", "sh")]


def observed():
    """The reached column, read BY PATH from the coworker's two row files."""
    obs, stems = {}, {}
    for name in ("probe.rows", "twostate.rows"):
        p = CO / name
        if not p.is_file():
            continue
        for line in p.read_text().splitlines()[1:]:
            f = line.split("\t")
            if len(f) < 3 or not f[2].lstrip("-").isdigit():
                continue
            key = stems.setdefault(pathlib.Path(f[0]).stem, f[0])
            obs.setdefault(key, set()).add(int(f[2]))
    return obs


def run(rel, argv=(), timeout=120):
    """Run it. A timeout is recorded as TIMED-OUT, never as a verdict -- SKIP is not PASS."""
    try:
        p = subprocess.run([sys.executable, rel, *argv], cwd=ROOT, capture_output=True,
                           text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, "", ""
    toks = [t for t in TOKENS if t in p.stdout or t in p.stderr]
    return p.returncode, " ".join(toks) or "-", p.stderr


def refusal_site(src: str):
    """(line, is_module_scope) for the FIRST `refuse(` that is not a definition or a comment.

    MODULE SCOPE is the load-bearing half: a refusal above every `argparse` parse cannot be
    reached by ANY argv, so the gate has no argument that could have avoided it. That is a
    different defect from "invoked with an argument no caller passes", and it is why the cause
    vocabulary below has four members and not one.
    """
    lines = src.splitlines()
    first = None
    for n, line in enumerate(lines, 1):
        s = line.strip()
        if s.startswith("#") or s.startswith("def refuse"):
            continue
        if "refuse(" in line:
            first = n
            break
    if first is None:
        return None, False
    argp = 0
    try:
        for n in ast.walk(ast.parse(src)):
            if isinstance(n, ast.Call) and getattr(n.func, "attr", "") == "ArgumentParser":
                argp = n.lineno
    except SyntaxError:
        pass
    return first, bool(first and (not argp or first < argp))


def main(argv):
    entries = sorted(entry_points(), key=lambda r: r["path"])
    obs = observed()
    rows = []
    for e in entries:
        rel, src = e["path"], (ROOT / e["path"]).read_text(errors="replace")
        bend = starts_bend(src)
        # EXECUTION IS RESTRICTED TO CANDIDATES, BY RULE. Many gates here WRITE (artifacts, ledgers,
        # residue, a `.txt` sweep of the tree), so running the whole population to find out what a
        # handful of gates do is a side effect paid for a number. A gate is executed iff it CANNOT
        # start `bend` AND its declared surface is small enough that a single state at rest could
        # exhaust it -- `len(declared) <= 3` -- which is the only shape a zero surface can have.
        site, module_scope = refusal_site(src)
        # ⚠ THIS RULE WAS WRONG ON ITS FIRST RUNNING AND THE CORRECTION IS THE FINDING. It began
        # as "skip any gate whose source names `bin/bend`", which skipped `nl-gate.py`,
        # `nl-gate-noguard.py`, `rn-gate.py` and `hermetic-census.py` -- FOUR OF THE NINE -- and
        # reported a ZERO-SURFACE count of 4 where the answer is 9. It was wrong because a
        # `refuse()` at MODULE SCOPE calls `sys.exit(3)` at IMPORT, so every statement after it,
        # including the `subprocess` that would have started `bend`, is UNREACHABLE. "Names bend"
        # and "can reach bend" are different claims, and only the second one may gate an
        # execution: the same blind spot as `vocab.py`'s declared column, one level over.
        can_reach_bend = bend and not module_scope
        candidate = (not can_reach_bend) and len(set(e["exits"])) <= 3
        rc = toks = err = None
        if candidate:
            rc, toks, err = run(rel)
        rows.append({
            "path": rel, "decl": set(e["exits"]),
            "reach": obs.get(rel, set()) | ({rc} if rc is not None else set()),
            "rc": rc, "tok": toks or "-", "bend": bend, "reachbend": can_reach_bend,
            "site": site, "ms": module_scope,
            "err": err or "",
        })

    zero = [r for r in rows if r["rc"] == 3 and r["reach"] == {3}]
    untested = [r for r in rows if not r["reach"]]
    if "--rows" in argv:
        print("path\tdeclared\treached\trc_at_rest\ttoken\tstarts_bend\tcause")
        for r in rows:
            cause = (("INPUT-SWEPT" if r["ms"] else "REFUSED") if r["rc"] == 3
                     else "CRASH-NOT-REFUSAL" if r["rc"] not in (None, 0) and "Traceback" in r["err"]
                     else "UNRUN-BY-REFUSAL" if r["bend"] else "")
            print(f"{r['path']}\t{','.join(map(str,sorted(r['decl']))) or '-'}\t"
                  f"{','.join(map(str,sorted(r['reach']))) or '(none)'}\t"
                  f"{r['rc'] if r['rc'] is not None else '-'}\t{r['tok']}\t{int(r['reachbend'])}\t{cause}")
        print(f"\n# entry points DISCOVERED by vocab.scan() (os.walk): {len(entries)}")
        print(f"# REAL SURFACE OF ZERO: {len(zero)}")
        for r in zero:
            print(f"#   ZERO {r['path']}  refuse() at :{r['site'] or 0} "
                  f"({'MODULE-SCOPE' if r['ms'] else 'reachable from argv'})")
        print(f"# NEVER TESTED BY ANYONE: {len(untested)}")
        for r in untested:
            print(f"#   UNTESTED {r['path']}"
                  + ("  [starts bend; unrun by this unit]" if r["bend"] else ""))
        return 0

    print(f"# {len(entries)} entry points, DISCOVERED by os.walk (vocab.scan) -- not a hand list")
    print(f"# of those, {sum(1 for r in rows if r['bend'])} can reach `bin/bend` and were NOT run "
          f"by this unit; their reached column is the coworker's, not a claim here\n")
    print(f"# REAL SURFACE OF ZERO -- exit 3 at rest and NO other state ever reached: {len(zero)}")
    for r in zero:
        # `:0` is a real reading, not a missing value: it means the file spells NO `refuse(` call
        # at all and reached exit 3 some other way. Printing it as `-` would read as "not found".
        print(f"#   {r['path']:30}  refuse() at :{r['site'] or 0:<4} "
              f"{'MODULE-SCOPE (no argv reaches it)' if r['ms'] else 'reachable from argv'}")
    print(f"\n# NEVER TESTED AT ALL -- no state presented by anyone: {len(untested)}")
    for r in untested:
        print(f"#   {r['path']:30}  {'can reach bend' if r['reachbend'] else 'cannot reach bend'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))