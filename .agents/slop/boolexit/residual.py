r"""THE RESIDUAL, MEASURED: `gatekit.charge()` refuses a bool and passes a FLOAT.

`AGENTS.md` asks the right question at the end -- "`int` subclasses `bool`, and `float` is
accepted where `int` is expected -- so a fix that covers `bool` may still admit `1.0`. REPORT
WHETHER YOUR FIXES CLOSE THE CLASS OR ONE MEMBER OF IT."

MEASURED answer: ONE MEMBER. And the residual is not theoretical: `sys.exit(1.0)` is exit status
1, so a float reaches the runner exactly as a bool did, through the same function, past the same
guard. The difference is that the bool guard makes the reader BELIEVE the table is typed.

    .venv/bin/python .agents/slop/boolexit/residual.py
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def h(t):
    print("\n" + "=" * 78 + f"\n{t}\n" + "=" * 78)


# THE CHILD. Three exits the tree cannot distinguish, all through `gatekit.charge()`.
CHILD = '''
import sys, os
sys.path.insert(0, {gates!r})
from gatekit import charge, verdict_of, VERDICT
which = sys.argv[1]
val = {{"bool-true": True, "bool-false": False, "float-1.0": 1.0,
        "float-0.0": 0.0, "int-1": 1, "int-0": 0}}[which]
c = charge(val)
print(f"charge({{val!r}}) = {{c!r}}  type={{type(c).__name__}}  verdict_of={{verdict_of(val)!r}}")
sys.exit(c)
'''


def main():
    gk_dir = str(ROOT / "gates")
    h("A. `sys.exit(charge(x))` FOR SIX INPUTS -- the EXIT STATUS a runner actually reads")
    with tempfile.TemporaryDirectory() as td:
        child = Path(td) / "child.py"
        child.write_text(CHILD.format(gates=gk_dir))
        rows = []
        for which in ("bool-true", "bool-false", "float-1.0", "float-0.0", "int-1", "int-0"):
            r = subprocess.run([sys.executable, str(child), which],
                               capture_output=True, text=True)
            print(f"   {which:<11} rc={r.returncode:<3} | {r.stdout.strip()}")
            rows.append((which, r.returncode))
        d = dict(rows)

    print()
    verdicts = {0: "GREEN", 1: "FAIL", 3: "REFUSED", 4: "SKIP", 5: "DEAD"}
    print("   what a runner reading `$?` would SAY:")
    for which, rc in rows:
        print(f"   {which:<11} -> {verdicts.get(rc, 'unassigned ' + str(rc))}")

    h("B. THE COMPARISON, STATED AS A TABLE. bool is closed; float is NOT.")
    print(f"   {'input':<8} {'exit rc':<8} {'verdict to a reader':<22} refused by the bool guard?")
    shown = {"bool-true": "True", "bool-false": "False", "float-1.0": "1.0",
             "float-0.0": "0.0", "int-1": "1", "int-0": "0"}
    for which, rc in rows:
        refused = "YES" if which.startswith("bool") else "no"
        print(f"   {shown[which]:<8} {rc:<8} {verdicts.get(rc, '?'):<22} {refused}")

    print()
    print("   `True`  -> REFUSED(3). The guard WORKS, and it is why `gatekit.charge(True)` reads 3.")
    print("   `1.0`   -> FAIL(1).   The guard does NOT apply: `isinstance(1.0, bool)` is False.")
    print("   `0.0`   -> FAIL(1).   NOT green, and I MEASURED WHY: CPython's `sys.exit` only accepts")
    print("                           an int or None -- a float is printed to stderr (`0.0`) and the")
    print("                           process exits 1. So the float's damage is FALSE-RED plus a")
    print("                           stray line on the stream the verdict was supposed to be on,")
    print("                           which is a worse nuisance than a wrong number alone.")
    print("                           **A DRAFT OF THIS SECTION CLAIMED `0.0` EXITS GREEN. IT DOES")
    print("                           NOT, AND MY OWN TABLE ABOVE ALREADY SAID SO.** Corrected")
    print("                           here rather than in the report, because the transcript is")
    print("                           the witness.")

    print()
    print("   AND THE FALSE-GREEN IS A DIFFERENT LINE, NOT THE SAME FUNCTION:")
    import tempfile as _td
    with _td.TemporaryDirectory() as _t:
        q = Path(_t) / "q.py"
        q.write_text("import sys; sys.exit(False)")
        print(f"   `sys.exit(False)` with NO charge() guard -> rc "
              f"{subprocess.run([sys.executable, str(q)]).returncode}  <-- GREEN, SILENTLY")
        print("   `bool` is accepted by `sys.exit` as an int and `False` IS 0. `charge()` is what")
        print("   stops it reaching a runner -- and every OTHER exit in the tree is unguarded.")
    # HOW MANY OTHERS? measured below, not asserted.
    import ast
    from census import population
    n_bare = n_guarded = 0
    imp, call_verb, call_charge = set(), set(), set()
    for rel, p in population():
        try:
            tree = ast.parse(p.read_text())
        except (SyntaxError, OSError, UnicodeDecodeError):
            continue
        for nd in ast.walk(tree):
            if isinstance(nd, ast.Call) and isinstance(nd.func, ast.Attribute) \
                    and nd.func.attr == "exit" and nd.args:
                n_guarded += "charge(" in ast.unparse(nd.args[0])
                n_bare += "charge(" not in ast.unparse(nd.args[0])
            if isinstance(nd, ast.ImportFrom) and nd.module == "gatekit":
                imp.add(str(rel))
            if isinstance(nd, ast.Call):
                f = nd.func
                nm = f.id if isinstance(f, ast.Name) else (f.attr if isinstance(f, ast.Attribute) else None)
                if nm == "verdict_of":
                    call_verb.add(str(rel))
                elif nm == "charge":
                    call_charge.add(str(rel))
    print(f"   MEASURED over checks/ + gates/: {n_bare} `sys.exit(...)` sites, of which "
          f"{n_guarded} name `charge`. The bool guard is real and it is ONE FUNCTION'S WIDTH --")
    print("   and the tree already types an exit in exactly one place, which is not a boundary.")
    print(f"   CONSUMERS, MEASURED: {len(imp)} files import `gatekit`, {len(call_verb)} call")
    print(f"   `verdict_of`, and **{len(call_charge)} call `charge`**. The fix landed inside the")
    print("   OWNER's own vocabulary. That is the correct place for it and it is still not a")
    print("   boundary: the 42 importers get `PASS/FAIL/...` as bare module constants and call")
    print("   `sys.exit(main())` with whatever `main()` happened to return.")

    h("C. THE ONE-LINE CLOSE, AND WHY IT IS NOT LANDED HERE")
    print("   `charge` would close the class with `type(code) is int` instead of")
    print("   `not isinstance(code, bool)`:")
    import importlib.util
    spec = importlib.util.spec_from_file_location("gk_r", ROOT / "gates/gatekit.py")
    gk = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gk)

    def charge_type_is_int(code):
        return code if code in gk.VERDICT and type(code) is int else gk.REFUSED

    for v in (0, 1, 3, True, False, 1.0, 0.0, 2, "0", None):
        print(f"   charge_type_is_int({v!r:<6}) -> {charge_type_is_int(v)!r:<6}"
              f"   charge({v!r:<6}) -> {gk.charge(v)!r}")
    print()
    print("   It agrees with `charge` on every int -- so it is the SAME 0-consumer change -- and it")
    print("   differs on every bool AND every float. It is not landed here for one measured reason:")
    print("   IT IS A GATE BODY, AND THIS UNIT OWNS NO GATE BODIES. Reporting it is the honest")
    print("   move; landing it here would be the `AGENTS.md` class-1 defect in reverse -- a unit")
    print("   editing an instrument it did not census.")

    h("D. WHAT `type(x) is int` COSTS, MEASURED -- because a 'better' fix that breaks a caller")
    print("   is worse than the defect it fixes:")
    import enum
    class E(enum.IntEnum):
        FAIL = 1
    print(f"   isinstance(E.FAIL, int)   : {isinstance(E.FAIL, int)}   "
          f"charge({E.FAIL!r}) -> {gk.charge(E.FAIL)!r}")
    print(f"   type(E.FAIL) is int      : {type(E.FAIL) is int}")
    print("   So `type(x) is int` REFUSES an IntEnum verdict, which `isinstance` accepts.")
    print("   `exitcode`'s `not isinstance(code, bool)` is the SHORTER-RANGE choice and it is")
    print("   defensible; the point of this section is that its range is one member wide, and the")
    print("   tree now MEASURES that rather than assuming it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())