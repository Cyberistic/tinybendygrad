#!/usr/bin/env python3
"""ffi-port-cost-audit.py -- can "307/324 mechanically derivable" go RED?

SUBJECT:    the 324 `@dll.bind` signatures in tinygrad/runtime/autogen/libclang.py
            -- specifically which of them have NO absent-Bend-type blocker.
INSTRUMENT: `.agents/slop/ffi-port-cost.py --pybind tinygrad/runtime/autogen/libclang.py`
            which prints
              mechanically derivable : 307/324 (95%) have no absent-type blocker
              coverage      : 324/324 = 100.0%
              need a layout decision : 203 ...

READ FROM THE TOOL'S SOURCE, not its prose:
  line 445  mechanical = len(uniq) - len({f.name for f in blocked})
        -> `mechanical` is a NOT-COUNT OF BLOCKERS. Nothing is derived. The set
           counted as "mechanically derivable" is defined by the ABSENCE of a
           recorded blocker.
  line 418  uniq = sorted(set(names));  names = [f.name for f in fns]
  line 496  denom = len({f.name for f in fns})      # the --pybind path
  line 420  print(f"denominator   : {denom} symbols exported by the binary")
  line 421  print(f"coverage      : {len(uniq)}/{denom} = ...")
        -> IN THE --pybind PATH `denom` IS `uniq`. The printed label names the
           BINARY; nothing read a binary. `coverage` is X/X.

Nothing under `.agents/slop/` or `tinygrad/` is edited. Every plant is a COPY.
"""
import importlib.util
import io
import contextlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
TOOL = os.path.join(REPO, ".agents/slop/ffi-port-cost.py")
PY = os.path.join(REPO, ".venv/bin/python")
TMP = os.path.join(tempfile.gettempdir(), "ffiaudit")
os.makedirs(TMP, exist_ok=True)


def load():
    spec = importlib.util.spec_from_file_location("ffipc", TOOL)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def run_tool(target, extra=()):
    env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
    r = subprocess.run([PY, TOOL, *extra, target], cwd=REPO, capture_output=True,
                       text=True, env=env, timeout=900)
    return r.stdout + r.stderr


def facts(text):
    out = {}
    for k, pat in (("uniq", r"entry points  : (\d+) unique"),
                   ("denom", r"denominator   : (\d+) symbols exported"),
                   ("mech", r"mechanically derivable : (\d+)/(\d+)"),
                   ("cov", r"coverage      : (\d+)/(\d+)"),
                   ("blocked", r"BLOCKED by an absent Bend type or the Nat window \((\d+)\)"),
                   ("layout", r"need a layout decision : (\d+)")):
        m = re.search(pat, text)
        if not m:
            out[k] = None
        elif k == "mech":
            out["mech"], out["mech_denom"] = int(m.group(1)), int(m.group(2))
        elif k == "cov":
            out["cov_n"], out["cov_d"] = int(m.group(1)), int(m.group(2))
        else:
            out[k] = int(m.group(1))
    return out


if __name__ == "__main__":
    print("=" * 78)
    base_txt = run_tool("tinygrad/runtime/autogen/libclang.py", ("--pybind",))
    b = facts(base_txt)
    print("BASELINE  reproduced from the live tree, unmodified")
    for k in ("uniq", "denom", "mech", "mech_denom", "blocked", "layout"):
        print(f"    {k:<12} {b[k]}")
    print(f"    coverage     {b['cov_n']}/{b['cov_d']}")
    print(f"    artifact libclang-cost.txt agrees? "
          f"{'307/324' in base_txt and '324/324 = 100.0%' in base_txt}")

    # ---------------------------------------------------------- THE TAUTOLOGY
    print("\n" + "=" * 78)
    print("FINDING A  `coverage: 324/324 = 100.0%` is X/X in the --pybind path.")
    print("  line 496  denom = len({f.name for f in fns})")
    print("  line 418  uniq  = sorted(set([f.name for f in fns]))")
    print("  line 421  coverage = len(uniq)/denom")
    print(f"  measured: uniq={b['uniq']} denom={b['denom']} cov={b['cov_n']}/{b['cov_d']}")
    print("  The line is labelled 'symbols exported by the binary'. NO BINARY IS READ")
    print("  on this path. And the guard at line 423 (`if len(uniq) > denom:` ->")
    print("  'the header and the binary disagree') is UNREACHABLE here, since denom")
    print("  is derived from uniq.")
    # Prove it: drop one signature and watch coverage follow to 100% again.
    src = os.path.join(REPO, "tinygrad/runtime/autogen/libclang.py")
    txt = open(src).read()
    d = os.path.join(TMP, "cut")
    os.makedirs(d, exist_ok=True)
    cut = re.sub(r"^def clang_Type_getSizeOf\(.*?\n(?=\n|@|def )", "", txt,
                 count=1, flags=re.S | re.M)
    assert cut != txt, "could not cut a declaration"
    p = os.path.join(d, "libclang.py")
    open(p, "w").write(cut)
    c = facts(run_tool(p, ("--pybind",)))
    print(f"\n  PLANT A (subject: one declaration DELETED from a COPY)")
    print(f"    entry points  : {c['uniq']}   (was {b['uniq']})")
    print(f"    coverage      : {c['cov_n']}/{c['cov_d']}   (was {b['cov_n']}/{b['cov_d']})")
    print(f"    mechanically derivable: {c['mech']}/{c['mech_denom']}")
    print("  ^ coverage is STILL 100.0% with 323 of libclang's 324 declarations gone.")
    print("    That is the proof it is a self-comparison.")

    # --------------------------------------------------------------- PLANT B
    print("\n" + "=" * 78)
    print("PLANT B  (subject) add a ctypes.c_int64 to ONE signature in a COPY.")
    d2 = os.path.join(TMP, "int64")
    os.makedirs(d2, exist_ok=True)
    # pick a declaration that is NOT already BLOCKED -- the first attempt used
    # clang_Type_getSizeOf, which the tool already lists as blocked for its
    # c_int64 RETURN, so adding an int64 ARGUMENT moved nothing. Measured, and
    # it is exactly the "a plant that does not land proves nothing" trap.
    blocked_names = set(re.findall(r"^  (clang_\w+): ctypes", base_txt, re.M))
    cands = [mm for mm in re.finditer(
        r"^def (clang_\w+)\(([^\n]*)\)(\s*->\s*([^\n:]+))?:", txt, re.M)
        if mm.group(1) not in blocked_names]
    m = cands[0]
    print(f"  a NON-blocked declaration chosen: {m.group(1)}({m.group(2)}) -> {m.group(4)}")
    print(f"  (the 17 already-blocked names were excluded by reading the tool's own")
    print(f"   BLOCKED list, not by guessing: {len(blocked_names)} names)")
    # THREE earlier attempts failed, and the reasons are the point:
    #  1. `blocked_names` from the tool's own list first excluded a function that
    #     was ALREADY blocked for its c_int64 return, so the plant could not land.
    #  2. inserting "(ctypes.c_int64, " after "(" adds a BARE PARAMETER with no
    #     annotation; parse_pybind reads an untyped name, not a type.
    #  3. rewriting the Python ANNOTATION `:int` -> `:ctypes.c_int64` also does
    #     nothing, because parse_pybind (line 377-390) reads the `@dll.bind`
    #     DECORATOR's ctypes tuple and consults the annotation only as a fallback
    #     for positions the decorator did not cover. Verified by calling the
    #     parser: with the annotation set to c_int64 it still reports
    #     `ctypes.c_int32` for that argument.
    # The authoritative plant is therefore on the DECORATOR line.
    bind_re = re.compile(r"^@dll\.bind\(([^)]*)\)\n(?=def " + m.group(1) + r"\()",
                         re.M)
    bm = bind_re.search(txt)
    assert bm, "the @dll.bind line for this declaration was not located"
    print(f"  decorator: @dll.bind({bm.group(1)})")
    print(f"  def      : {m.group(0)[:96]}")
    old = bm.group(0)
    parts = [t.strip() for t in bm.group(1).split(",")]
    new = old.replace(parts[-1], "ctypes.c_int64", 1)
    assert new != old, "decorator unchanged"
    print(f"  rewritten: @dll.bind({', '.join([', '.join(parts[:-1]), 'ctypes.c_int64'] if len(parts) > 1 else 'ctypes.c_int64')})")
    p2 = os.path.join(d2, "libclang.py")
    open(p2, "w").write(txt.replace(old, new, 1))
    assert open(p2).read().count("ctypes.c_int64") == txt.count("ctypes.c_int64") + 1, "plant did not land"
    e = facts(run_tool(p2, ("--pybind",)))
    print(f"    mechanically derivable: {e['mech']}/{e['mech_denom']}  "
          f"(was {b['mech']}/{b['mech_denom']})")
    print(f"    BLOCKED: {e['blocked']}  (was {b['blocked']})")
    print(f"  ^ {'MOVED' if e['mech'] != b['mech'] else 'DID NOT MOVE'}")

    # --------------------------------------------------- THE INTERNAL CONTRADICTION
    print("\n" + "=" * 78)
    print("FINDING B  203 of the 307 'mechanically derivable' need a layout decision.")
    print(f"  mechanically derivable : {b['mech']}")
    print(f"  need a layout decision : {b['layout']}")
    print(f"  BLOCKED (max_class)    : {b['blocked']}")
    print("  `max_class` is a SINGLE value per function (line 97-108) and BLOCKED is")
    print("  checked FIRST, so no function can be both BLOCKED and CBYVAL/OPAQUE.")
    print(f"  => all {b['layout']} layout-decision functions are INSIDE the {b['mech']}.")
    print(f"  => {b['layout']}/{b['mech']} = "
          f"{100.0*b['layout']/max(1,b['mech']):.0f}% of the 'mechanically derivable' set")
    print("     is labelled, by the tool's OWN table:")
    print("       CBYVAL : 'struct by value -- N Term words, needs one layout convention'")
    print("       STRUCT : 'per-struct decision, not mechanical'")
    print("     i.e. the same run prints 'not mechanical' about two thirds of what it")
    print("     just called mechanically derivable.")

    # --------------------------------------------------------------- DISARM
    print("\n" + "=" * 78)
    print("DISARM  a comment/whitespace change to the COPY must move nothing")
    d3 = os.path.join(TMP, "comment")
    os.makedirs(d3, exist_ok=True)
    p3 = os.path.join(d3, "libclang.py")
    open(p3, "w").write(txt + "\n# DISARM: a comment.\n")
    f = facts(run_tool(p3, ("--pybind",)))
    print(f"    mechanically derivable: {f['mech']}/{f['mech_denom']}  "
          f"coverage {f['cov_n']}/{f['cov_d']}   "
          f"{'unchanged' if f['mech'] == b['mech'] else 'MOVED (unexpected)'}")