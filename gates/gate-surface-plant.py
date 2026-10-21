#!/usr/bin/env python3
"""gate-surface-plant.py -- THE PLANT OF `gates/gate-surface.py`, AND OF THE MARKER IT READS.

    .venv/bin/python gates/gate-surface-plant.py            # the plant: rc 0 GREEN, rc 1 RED
    .venv/bin/python gates/gate-surface-plant.py --patch    # the candidate reader fix, as a diff

WHAT THIS FILE IS FOR. `gates/gate-surface.py` reads each gate's declared exit surface from a
MODULE-LEVEL MARKER, and this wave moved that marker from `VERDICTS` to `EXIT_SURFACE` because
`VERDICTS` means four other things in four other files. `gates/gate-surface.py` is OWNED BY
ANOTHER UNIT, so this file does not edit it -- and a rename that leaves its reader blind is a
broken tree, not a migration. So the migration lands as a CHAINED ASSIGNMENT (ONE literal, TWO
names, and `ast.literal_eval` reads the value once for every target of the assignment), and the
reader's own flip is left as a PATCH, which this file PROVES on a COPY.

THE FOUR PROPERTIES, AND WHO OWNS EACH.

  a documented `RED_IS` is recognised as declaring that class     READER  (candidate patch)
  a class that is NOT one of the three is still MALFORMED         BOTH    (asserted, both ways)
  a file the census cannot parse is not a malformed declaration    READER  (candidate patch)
  a gate with a clean declaration is still read as declaring one  BOTH    (the unbroken control)

WHY A PATCH AND NOT A SECOND CENSUS. A copy of `gates/gate-surface.py` that nobody runs is a
second census, and two censuses answer the same question two ways. A patch is a DIFF: it is the
census itself, once the owner applies it, and until then it is a claim this file tests. The
owner runs `--patch` and applies what it prints.

WHY THE PLANT IS GREEN BEFORE THE PATCH IS APPLIED. The candidate is the census WITH the patch,
so the three reader-side properties are asserted against IT and hold today. The live census's
standing on the same three is PRINTED, not asserted: asserting a defect is present is a
statement that a fix must later un-state, and a plant that must be edited when the fix lands is
a plant that rots. What IS asserted against the live census is the seam -- that the migration
did not cost the census a single declaration -- because that is this wave's own change and it
is the one that can silently break.

THE SEAM IS A CHAINED ASSIGNMENT, AND IT IS LOAD-BEARING. `gates/gate-surface.py` reads
`VERDICTS`; the 21 migrated gates bind `EXIT_SURFACE` and `VERDICTS` to the SAME literal; a
gate that binds only `EXIT_SURFACE` is INVISIBLE to the un-patched reader. So the alias is not
decoration, and the patch's first hunk is what retires it.
"""
import argparse
import ast
import contextlib
import difflib
import importlib.util
import io
import sys
import tempfile
import types
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
CENSUS = HERE / "gate-surface.py"
FINDING, UNTAKEN, FAILURE = "FINDING", "UNTAKEN", "FAILURE"

# ---- THE CANDIDATE READER, AS PATCH DATA.  A diff, not a copy of the census. ----------------
PATCH = (
    # 1. THE MARKER: which names carry a declaration.
    ('DECL = ("VERDICTS", "PLANTS", "RED_IS")',
     'DECL = ("EXIT_SURFACE", "PLANTS", "RED_IS")'),
    # 2. THE MARKER: the test that a file declares a surface at all, and the shape of it.
    ('    if "VERDICTS" not in found:\n'
     '        return None, None, None, ""\n'
     '    if not isinstance(found["VERDICTS"], dict):\n'
     '        return None, None, None, "VERDICTS is not a mapping"\n',
     '    if "EXIT_SURFACE" not in found:\n'
     '        return None, None, None, ""\n'
     '    if not isinstance(found["EXIT_SURFACE"], dict):\n'
     '        return None, None, None, "EXIT_SURFACE is not a mapping"\n'),
    # 3. THE CLASS: the first token is the class, the rest is documentation.
    ('    if "RED_IS" in found and found["RED_IS"] not in (FINDING, FAILURE, UNTAKEN):\n'
     '        return None, None, None, f"RED_IS is {found[\'RED_IS\']!r}, not one of the three classes"\n'
     '    return found["VERDICTS"], found.get("PLANTS"), found.get("RED_IS"), ""\n',
     '    if "RED_IS" in found:\n'
     '        # THE CLASS IS THE FIRST TOKEN AND THE REST IS DOCUMENTATION. A gate that says\n'
     '        # `RED_IS = "FINDING -- because ..."` is DECLARING the class FINDING, and a reader\n'
     '        # that compares the whole string to a class name cannot see that.\n'
     '        raw = found["RED_IS"]\n'
     '        klass = raw.split(maxsplit=1)[0] if isinstance(raw, str) and raw.strip() else None\n'
     '        if klass not in (FINDING, FAILURE, UNTAKEN):\n'
     '            return None, None, None, f"RED_IS is {found[\'RED_IS\']!r}, not one of the three classes"\n'
     '        found["RED_IS"] = klass\n'
     '    return found["EXIT_SURFACE"], found.get("PLANTS"), found.get("RED_IS"), ""\n'),
    # 4. THE FILE THE CENSUS CANNOT READ: a file in another language is not a malformed
    #    declaration, it is a file this census does not understand.
    ("    shell, noshebang, arms = [], [], {}\n",
     "    shell, noshebang, unread, arms = [], [], [], {}\n"),
    ('        if kind == "SHELL":\n'
     '            shell.append(p)\n'
     '            continue\n'
     '        if kind != "PYTHON":\n'
     '            noshebang.append(p)\n',
     '        if kind == "SHELL":\n'
     '            shell.append(p)\n'
     '            continue\n'
     '        if gpop.entry_reason(p) in ("js-main", "js-lib"):\n'
     '            unread.append(p)\n'
     '            continue\n'
     '        if kind != "PYTHON":\n'
     '            noshebang.append(p)\n'),
    ('              + ", ".join(sorted(str(p.relative_to(root)) for p in shell)))\n'
     '    if noshebang:\n',
     '              + ", ".join(sorted(str(p.relative_to(root)) for p in shell)))\n'
     '    if unread:\n'
     '        print(f"II NOT READ BY THIS CENSUS: {len(unread)} entry point(s) are in a language this "\n'
     '              f"file cannot read a\\n   declaration from. A file this census does not UNDERSTAND "\n'
     '              f"is not a file with a MALFORMED\\n   declaration, and charging it as one is a false "\n'
     '              f"charge:\\n     "\n'
     '              + ", ".join(sorted(str(p.relative_to(root)) for p in unread)))\n'
     '    if noshebang:\n'),
    # 5. THE CENSUS'S OWN DECLARATION: the reader has to declare itself under the same name.
    ('VERDICTS = {0: "OK", 1: "RED", 2: "REFUSED"}\n',
     'EXIT_SURFACE = VERDICTS = {0: "OK", 1: "RED", 2: "REFUSED"}\n'),
)

# ---- THE SYNTHETIC GATES.  They are COPIES of a shape, written to a temporary tree. ---------
# EVERY ONE OF THEM DECLARES THE SURFACE UNDER BOTH NAMES, because the ALIAS form is what the
# live census reads and what the candidate reads, and a fixture that only the patched reader can
# see would prove the patch and not the seam.
GATE = ("import sys\n"
        "EXIT_SURFACE = VERDICTS = {{0: 'PASS', 1: 'RED'}}\n"
        "PLANTS = {{0: [], 1: ['--red']}}\n"
        "{red}if __name__ == '__main__':\n"
        "    sys.exit(1 if '--red' in sys.argv else 0)\n")
CLEAN = GATE.format(red="")
DOCUMENTED = GATE.format(red="RED_IS = 'FINDING -- because the tree says so'\n")
WRONG = GATE.format(red="RED_IS = 'BOGUS'\n")
WRONG_DOCUMENTED = GATE.format(red="RED_IS = 'BOGUS -- and it explains itself'\n")
# THE OLD SHAPE ALONE: a gate that has not been migrated yet, and one the live census must
# still read.  The candidate does NOT read it, and that is the difference the patch closes.
LEGACY = GATE.format(red="").replace("EXIT_SURFACE = VERDICTS = ", "VERDICTS = ")

CHECKS = []


def check(name, ok, got):
    CHECKS.append((name, bool(ok), got))


def load(path, name):
    """a module, LOADED BY PATH. Importing a gate RUNS it."""
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_candidate(src):
    """the census WITH the patch, compiled in place. `__file__` stays the census's own path, so
    `vocabulary()` finds the real `gates/gatekit.py` and `gates_pop()` the real `gates-pop.py`."""
    mod = types.ModuleType("gate_surface_candidate")
    mod.__file__ = str(CENSUS)
    exec(compile(src, str(CENSUS), "exec"), mod.__dict__)     # noqa: S102 -- the patched census
    return mod


def apply_patch(src):
    """`(patched, applied)` -- a hunk whose ANCHOR HAS ROTTED refuses the plant rather than
    passing it, and a hunk already applied is skipped, so the plant is GREEN in both worlds."""
    out = src
    applied = 0
    for old, new in PATCH:
        if old in out:
            if out.count(old) != 1:
                raise SystemExit(f"REFUSED: the anchor is not unique:\n{old}")
            out = out.replace(old, new, 1)
            applied += 1
        elif new not in out:
            raise SystemExit(f"REFUSED: the anchor has rotted, so the candidate is not the census:\n{old}")
    return out, applied


def population():
    """the entry points, DISCOVERED. `gates/gates-pop.py` is loaded BY PATH, never by name."""
    return load(HERE / "gates-pop.py", "gates_pop").discover(ROOT)[0]


def marker_files(entries):
    """`(path, value)` for every entry that binds a marker NAME to a MAPPING -- the population of
    gates that declare a surface, found by the same AST walk the census does."""
    out = []
    for p in entries:
        try:
            tree = ast.parse(p.read_text(errors="replace"))
        except (SyntaxError, ValueError):
            continue
        for node in tree.body:
            if not isinstance(node, ast.Assign):
                continue
            names = [t.id for t in node.targets if isinstance(t, ast.Name)]
            if not ({"EXIT_SURFACE", "VERDICTS"} & set(names)):
                continue
            try:
                value = ast.literal_eval(node.value)
            except (ValueError, SyntaxError, TypeError):
                continue
            if isinstance(value, dict):
                out.append((p, value))
                break
    return out


def synth(tmp, name, source):
    """a synthetic gate, written into a temporary tree. The LIVE tree is never written."""
    p = Path(tmp) / "checks" / name
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(source)
    return p


def report_over(mod, root):
    """the census's transcript over `root`, captured. `charge=False` so a red is not a verdict."""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        mod.report(root, charge=False)
    return buf.getvalue()


def main():
    ap = argparse.ArgumentParser(prog="gates/gate-surface-plant.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--patch", action="store_true",
                    help="print the candidate reader fix as a unified diff, and exit")
    a = ap.parse_args()

    src = CENSUS.read_text()
    patched, applied = apply_patch(src)
    if a.patch:
        sys.stdout.writelines(difflib.unified_diff(src.splitlines(True), patched.splitlines(True),
                                                   fromfile="a/gates/gate-surface.py",
                                                   tofile="b/gates/gate-surface.py"))
        return 0

    live = load(CENSUS, "gate_surface_live")
    cand = load_candidate(patched)
    entries = population()

    # ---- 1. THE SEAM, AGAINST THE LIVE CENSUS.  This wave's own change, and the one that can
    #         silently cost the census a declaration.
    with tempfile.TemporaryDirectory() as td:
        v, _p, red, note = live.declaration(synth(td, "g.py", CLEAN))
        check("1a: the ALIAS form is read -- one literal, two names, and the un-patched census "
              "still sees the surface", note == "" and v == {0: "PASS", 1: "RED"},
              f"verdicts={v!r} note={note!r}")

    v, _p, red, note = live.declaration(CENSUS)
    check("1b: the census's OWN declaration is still read -- a reader that has declared itself "
          "under the new name and lost it is a reader with no surface",
          note == "" and isinstance(v, dict), f"verdicts={v!r} note={note!r}")

    for rel in ("gates/upstream-pow-dtype-gate.py", "gates/upstream-promo-lattice-gate.py"):
        v, _p, red, note = live.declaration(ROOT / rel)
        check(f"1c: {rel} declares its class in the class field, and is read as declaring it",
              note == "" and red == FINDING, f"red_is={red!r} note={note!r}")

    with tempfile.TemporaryDirectory() as td:
        v, _p, red, note = live.declaration(synth(td, "g.py", WRONG))
        check("1d: a class that is NOT one of the three is still MALFORMED -- the detection is not "
              "a rubber stamp", note != "" and v is None, f"note={note!r}")

    with tempfile.TemporaryDirectory() as td:
        v, _p, red, note = live.declaration(synth(td, "g.py", LEGACY))
        check("1e: a gate that declares the surface under the OLD name alone is still read as "
              "declaring one -- the migration did not strand a gate that has not moved yet",
              note == "" and isinstance(v, dict), f"verdicts={v!r} note={note!r}")

    markers = marker_files(entries)
    lost = [str(p.relative_to(ROOT)) for p, _v in markers
            if live.declaration(p)[0] is None]
    check(f"1f: every one of the {len(markers)} gate(s) that binds the marker to a MAPPING is still "
          f"read as declaring one -- the migration cost the census no declaration",
          not lost, f"lost={lost}")

    # ---- 2. THE CANDIDATE READER, ON A COPY.  The three reader-side properties.
    with tempfile.TemporaryDirectory() as td:
        v, _p, red, note = cand.declaration(synth(td, "g.py", DOCUMENTED))
        check("2a: a DOCUMENTED `RED_IS` is recognised as declaring that class -- the class is the "
              "first token and the rest is documentation",
              note == "" and red == FINDING, f"red_is={red!r} note={note!r}")

    with tempfile.TemporaryDirectory() as td:
        v, _p, red, note = cand.declaration(synth(td, "g.py", WRONG))
        check("2b: a class that is NOT one of the three is still MALFORMED, on the CANDIDATE too",
              note != "" and v is None, f"note={note!r}")

    with tempfile.TemporaryDirectory() as td:
        v, _p, red, note = cand.declaration(synth(td, "g.py", WRONG_DOCUMENTED))
        check("2c: a DOCUMENTED class that is NOT one of the three is still MALFORMED -- reading a "
              "class out of a sentence must not become a rubber stamp",
              note != "" and v is None, f"note={note!r}")

    with tempfile.TemporaryDirectory() as td:
        v, _p, red, note = cand.declaration(synth(td, "g.py", CLEAN))
        check("2d: a gate with a clean declaration is still read as declaring one, on the CANDIDATE",
              note == "" and isinstance(v, dict), f"verdicts={v!r} note={note!r}")

    coincidences = ("gates/citations-census-gate.py", "gates/vendordep-census-gate.py",
                    "gates/verdictcopy-gate.py", "gates/e2estage8-stage-selftest.py")
    still = [rel for rel in coincidences
             if cand.declaration(ROOT / rel)[3] != "" or cand.declaration(ROOT / rel)[0] is not None]
    check(f"2e: the {len(coincidences)} file(s) that mean something ELSE by `VERDICTS` are not "
          f"charged a malformed declaration -- the marker moved, and they did not",
          not still, f"still_charged={still}")

    # ---- 3. THE FILE THE CENSUS CANNOT READ.  A COPY of the tree's own JavaScript census, in a
    #         synthetic tree, so the claim is about a real file and not about a fixture.
    js_rel = "checks/nan_census.mjs"
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        cand._tree(root)
        (root / "checks" / "nan_census.mjs").write_text((ROOT / js_rel).read_text())
        reason = load(HERE / "gates-pop.py", "gates_pop").entry_reason(root / "checks" / "nan_census.mjs")
        said = report_over(cand, root)
        check("3a: a file the census cannot read is NOT charged a malformed declaration -- it is a "
              "file this census does not UNDERSTAND",
              f"{js_rel}: MALFORMED" not in said and js_rel in said,
              f"classified={reason!r} charged={f'{js_rel}: MALFORMED' in said} counted={js_rel in said}")
        live_said = report_over(live, root)
        print(f"I  THE LIVE CENSUS, on the same tree: {js_rel}: MALFORMED = "
              f"{f'{js_rel}: MALFORMED' in live_said} -- the false charge the candidate removes.")

    print("PLANTS -- the seam against the live census, the candidate reader on a copy, and the "
          "controls\nthat must not move.")
    rc = 0
    for name, ok, got in CHECKS:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}\n          observed: {got}")
        rc |= 0 if ok else 1
    print(f"PLANTS: {'GREEN' if rc == 0 else 'RED'} ({sum(1 for c in CHECKS if c[1])}/{len(CHECKS)})"
          f" -- candidate hunks applied: {applied}/{len(PATCH)}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
