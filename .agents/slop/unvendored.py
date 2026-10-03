#!/usr/bin/env python3
"""unvendored.py -- WHICH UPSTREAM FILES HAVE WE NEVER VENDORED?

The drift tooling in this repo answers "how far behind are the files we HAVE"
(`upstream-delta.py`, 230 vendored blobs). It has no answer for the other
question: which upstream files are absent entirely.

TWO MEASUREMENTS, because the first is not sufficient and this repo has been
fooled by exactly that. The version of this file that hand-rolled relative
import resolution reported 1,700 "missing modules" that were all stdlib --
in Python 3 `import os` is ABSOLUTE, so it is a resolver bug, not a gap.
Resolution is therefore delegated to CPython itself and never re-implemented.

  1. SET DIFFERENCE (static, from git). Every `.py` under upstream
     `tinygrad/` at the pin and at HEAD, minus every `.py` in our vendored
     `tinygrad/`. This is the enumeration proper.

  2. REACHABLE MODULE SURFACE (dynamic, via CPython). Every `tinygrad.*`
     module the vendored tree can be asked to import is really imported, and
     every name bound by a `from tinygrad.X import a, b` is really checked.
     Plus every DYNAMIC import target, which no static diff can close.

WHY (1) ALONE IS NOT THE ANSWER, AND THIS IS MEASURED HERE
    `DEV=MOCK` fails with `ModuleNotFoundError: No module named
    'tinygrad.runtime.ops_mock'` because `device.py:37` builds the module name
    dynamically as `ops_{x}`. There is no `ops_mock.py` upstream and never
    was -- so the set difference is EMPTY for it. A path-set difference can
    only find a missing FILE; the MOCK failure is a missing NAME. The name
    space is strictly larger than the file space and only (2) measures it.

USAGE
    python3 .agents/slop/unvendored.py
    python3 .agents/slop/unvendored.py --json
    python3 .agents/slop/unvendored.py --dynamic
    python3 .agents/slop/unvendored.py --dynamic --expand
"""

import argparse
import ast
import json
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO))
UPSTREAM = "upstream/master"
PIN = "6c3d401cf324"  # .agents/UPSTREAM-PIN.md; the pin is NOT advanced while drift is open

# Out of scope by owner ruling (.agents/UPSTREAM-PIN.md step 3, outcome 4).
OUT_OF_SCOPE_PREFIXES = (
    "tinygrad/viz/",
    "tinygrad/llm/",
    "tinygrad/runtime/autogen/",  # generated output
    "tinygrad/test/",
    "tinygrad/examples/",
    "tinygrad/extra/",
    "tinygrad/docs/",
)


def git(*a):
    return subprocess.run(["git", "-C", str(REPO), *a],
                          capture_output=True, text=True, check=True).stdout


def _load_delta():
    """`upstream-delta.py` as a module, so the provenance classification is ONE
    implementation. Two tools answering the same question differently is how
    `renderer/cstyle.py` got called a hand edit by one and clean by the other."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "_upstream_delta", REPO / ".agents/slop/upstream-delta.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def upstream(rev):
    return [p for p in git("ls-tree", "-r", "--name-only", rev, "--", "tinygrad/").splitlines() if p]


def ours(suffix=".py"):
    out = []
    for dp, dn, fn in os.walk(REPO / "tinygrad"):
        dn[:] = [d for d in dn if d != "__pycache__"]
        out += [os.path.relpath(os.path.join(dp, f), REPO) for f in fn
                if not suffix or f.endswith(suffix)]
    return sorted(out)


# ---------------------------------------------------------------- names ----

def site_imports(rel):
    """Every tinygrad module + every tinygrad name this file binds.

    Only ABSOLUTE tinygrad targets count. A level-0 `import os` is stdlib in
    Python 3, not a sibling module -- that mistake produced 1,700 phantom
    "missing modules" in the first draft of this file.
    """
    tree = ast.parse((REPO / rel).read_text(encoding="utf-8", errors="replace"), filename=rel)
    mods, names = set(), set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            mods |= {a.name for a in n.names if a.name.split(".")[0] == "tinygrad"}
        elif isinstance(n, ast.ImportFrom):
            if n.level == 0 and n.module and n.module.split(".")[0] == "tinygrad":
                mods.add(n.module)
                names |= {(n.module, a.name) for a in n.names if a.name != "*"}
    return mods, names


def dynamic_sites():
    """Every importlib.import_module() whose target is not a literal."""
    out = []
    for rel in ours(".py"):
        tree = ast.parse((REPO / rel).read_text(encoding="utf-8", errors="replace"), filename=rel)
        for n in ast.walk(tree):
            if not (isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
                    and n.func.attr == "import_module"):
                continue
            a = n.args[0] if n.args else None
            if isinstance(a, ast.Constant):
                continue
            tmpl = ""
            try:
                body = ast.parse(ast.unparse(a), mode="eval").body
                if isinstance(body, ast.JoinedStr):
                    tmpl = "".join(str(v.value) if isinstance(v, ast.Constant)
                                   else "<" + ast.unparse(v) + ">" for v in body.values)
            except SyntaxError:
                pass
            out.append({"file": rel, "line": n.lineno, "template": tmpl or ast.unparse(a)})
    return out


def live_surface():
    """Really import every tinygrad module and really check every bound name."""
    import importlib

    mods, names = set(), set()
    for rel in ours(".py"):
        m, n = site_imports(rel)
        mods |= m
        names |= n
    # Every vendored file is itself a reachable module.
    for rel in ours(".py"):
        m = "tinygrad" + rel[len("tinygrad"):-len(".py")].replace("/", ".")
        mods.add(m[:-len(".__init__")] if m.endswith(".__init__") else m)

    unimportable, missing_mod, missing_name, conditional = [], [], [], []
    for m in sorted(mods):
        try:
            mod = importlib.import_module(m)
        except BaseException as e:  # a platform FFI load failure is NOT a gap
            unimportable.append({"module": m, "error": f"{type(e).__name__}: {e}"[:160]})
            continue
        for mm, name in sorted(n for n in names if n[0] == m):
            # `hasattr` alone is WRONG here: `from pkg import sub` works
            # because Python falls back to importing the submodule, which
            # `hasattr` cannot see. That reported tinygrad.renderer's four
            # renderers as missing; they are modules and they import fine.
            if hasattr(mod, name):
                continue
            sub = f"{mm}.{name}"
            try:
                importlib.import_module(sub)
            except BaseException:
                # Not an attribute, not a submodule. Is it bound UNDER A
                # GUARD? `launch_viz` is defined inside
                # `if TRACK_MATCH_STATS or PROFILE:` (uop/ops.py:1737), so
                # hasattr is False by default and True under PROFILE=1. That
                # is upstream's own conditional binding, not a gap -- and
                # reporting it as missing would be a false alarm of exactly
                # the kind this tool already produced twice.
                src = (REPO / f"{mm.replace('.', '/')}.py")
                cond = False
                if src.exists():
                    cond = any(
                        isinstance(n, (ast.FunctionDef, ast.ClassDef)) and n.name == name
                        and n.col_offset > 0
                        for n in ast.walk(ast.parse(src.read_text(errors="replace")))
                    )
                (conditional if cond else missing_name).append(
                    {"module": mm, "name": name})
    for mm, name in sorted(names):
        if mm not in mods:
            missing_mod.append({"module": mm, "name": name})
    return len(mods), unimportable, missing_mod, missing_name, conditional


def ops_backends():
    """Every `ops_<x>` the tree can be ASKED for, vs the ops_<x> that EXIST.

    This is the MOCK measurement, closed. `device.py:37` is the only site that
    constructs a backend module name, and its input space is `DEV=`.
    """
    exist = {Path(p).stem[len("ops_"):] for p in ours(".py")
             if Path(p).parent.name == "runtime" and Path(p).stem.startswith("ops_")}
    asked = set()
    for rel in ours(".py"):
        if Path(rel).name != "device.py":
            continue
        for m in re.finditer(r"ALL_DEVICES\s*=\s*\[([^\]]*)\]", (REPO / rel).read_text()):
            asked |= {s.strip().strip('"\'').lower() for s in m.group(1).split(",") if s.strip()}
    return sorted(exist), sorted(asked), sorted(asked - exist), sorted(exist - asked)


import re  # noqa: E402  (used by ops_backends)


def provenance(up_pin, py_head, ours_py):
    """Which of OUR files equal HEAD, equal the pin, equal SOME OTHER upstream commit, or none.

    This is the section that found the one real problem, and it is a
    DIFFERENT question from the set difference. A file we never vendored is
    a missing module. A file we vendored and then EDITED is worse in one
    specific way: every CPython oracle in the tree measures against it, and
    if the edit is not upstream's then the oracle is measuring a program
    nobody wrote. Nothing raises, so it must be a measured set.

    It used to compare each blob against exactly TWO revisions -- HEAD and the
    pin -- and report everything else as "equals NEITHER". That is not a hand
    edit; it is a file re-vendored to an INTERMEDIATE upstream commit, which is
    exactly what landing a batch does. `renderer/cstyle.py` was reported as a
    hand edit because of it and was byte-identical to upstream `87a4311b3c3` all
    along. So the middle bucket now resolves against each path's FULL upstream
    history, using the same code as `upstream-delta.py` rather than a second
    implementation of the same idea.

    "Neither" is only a CANDIDATE hand edit -- an upstream commit may have
    simply been missed. Deciding whether an edit is acceptable is an owner
    call (.agents/UPSTREAM-PIN.md, "SCOPE DECISION"), not this tool's.
    """
    ud = _load_delta()
    head, pin, intermediate, neither, localonly = 0, 0, [], [], []
    for rel in sorted(py_head):
        ours = REPO / rel
        if not ours.exists():
            continue
        h = subprocess.run(["git", "-C", str(REPO), "hash-object", str(ours)],
                           capture_output=True, text=True, check=True).stdout.strip()
        def blob(rev):
            p = subprocess.run(["git", "-C", str(REPO), "rev-parse", f"{rev}:{rel}"],
                               capture_output=True, text=True)
            return p.stdout.strip() or None
        if h == blob(UPSTREAM):
            head += 1
        elif h == blob(PIN):
            pin += 1
        else:
            blobs, owners, _ = ud.upstream_blob_history(rel)
            if not blobs:
                localonly.append(rel)            # upstream has never had this path
            elif h in blobs:
                intermediate.append((rel, owners[h]))
            else:
                neither.append(rel)
    return head, pin, intermediate, neither, localonly


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--dynamic", action="store_true")
    ap.add_argument("--expand", action="store_true")
    a = ap.parse_args()

    py_pin = {p for p in upstream(PIN) if p.endswith(".py")}
    py_head = {p for p in upstream(UPSTREAM) if p.endswith(".py")}
    ours_py = set(ours(".py"))
    ours_all = set(ours(""))

    miss_pin, miss_head = sorted(py_pin - ours_py), sorted(py_head - ours_py)
    extra = sorted(ours_py - py_head)
    retained = sorted((ours_py & py_pin) - py_head)          # upstream deleted it
    miss_nonpy = sorted((set(upstream(UPSTREAM)) - ours_all) - py_head)

    dyn = dynamic_sites()
    n_mod, unimp, mm, mn, cond = live_surface()
    exist, asked, mock_gap, dead = ops_backends()
    n_head, n_pin, intermediate, neither, localonly = provenance(py_pin, py_head, ours_py)

    if a.json:
        print(json.dumps({
            "counts": {
                "upstream_py_at_pin": len(py_pin), "upstream_py_at_head": len(py_head),
                "our_vendored_py": len(ours_py),
                "MISSING_at_pin": len(miss_pin), "MISSING_at_head": len(miss_head),
                "extra": len(extra), "retained": len(retained), "missing_nonpy": len(miss_nonpy),
                "reachable_modules": n_mod, "unimportable": len(unimp),
                "missing_modules": len(mm), "missing_names": len(mn),
                "conditionally_bound": len(cond),
                "dynamic_templates": len(dyn),
                "dev_targets_asked": len(asked), "dev_targets_missing": len(mock_gap),
                "equals_head": n_head, "equals_pin": n_pin,
                "equals_intermediate_upstream_commit": len(intermediate),
                "local_only_paths": localonly,
            },
            "matches_neither_upstream_nor_pin": neither,
            "intermediate_upstream_commit": {p: c for p, c in intermediate},
            "missing_at_pin": miss_pin, "missing_at_head": miss_head,
            "extra": extra, "retained": retained, "missing_nonpy": miss_nonpy,
            "unimportable": unimp, "missing_modules": mm, "missing_names": mn,
            "conditionally_bound": cond,
            "dynamic": dyn,
            "ops_exist": exist, "dev_asked": asked,
            "dev_missing_file": mock_gap, "dev_never_asked": dead,
        }, indent=2))
        return

    if a.dynamic:
        for d in dyn:
            print(f"{d['file']}:{d['line']}  {d['template']}")
        if a.expand:
            print("\n-- ops_<x> template, space closed against the files that exist --")
            print("   exist:", " ".join(exist))
            print("   DEV=  :", " ".join(asked))
            print("   MISSING ops file for DEV=:", mock_gap or "none")
            print("   ops file never reachable from DEV= (disk/python/rdma/npy):", dead)
        return

    W = 74
    print(f"{'1. SET DIFFERENCE -- the enumeration'.center(W, '=')}\n")
    print(f"  upstream .py at PIN  {PIN[:12]}          {len(py_pin):>4}")
    print(f"  upstream .py at HEAD {UPSTREAM[:12]}         {len(py_head):>4}")
    print(f"  our vendored .py                         {len(ours_py):>4}")
    print(f"  ===> MISSING at pin                     {len(miss_pin):>4}   <-- the count")
    print(f"  ===> MISSING at head                    {len(miss_head):>4}")
    print(f"      extra (ours, not upstream)          {len(extra):>4}   {extra}")
    print(f"      retained (upstream deleted)         {len(retained):>4}   {retained}")
    print(f"      missing NON-.py blobs               {len(miss_nonpy):>4}   {miss_nonpy}")
    for rel in miss_pin + miss_head:
        print(f"      MISSING: {rel}")

    print(f"\n{'2. REACHABLE SURFACE -- the MOCK class'.center(W, '=')}\n")
    print(f"  tinygrad modules really imported        {n_mod:>4}")
    print(f"  unimportable (platform FFI, NOT a gap) {len(unimp):>4}")
    print(f"  ===> missing MODULES                   {len(mm):>4}")
    for d in mm:
        print(f"      {d}")
    print(f"  ===> missing NAMES (from X import a)   {len(mn):>4}")
    for d in mn:
        print(f"      {d}")
    print(f"      (conditionally bound, NOT gaps) {len(cond):>4}")
    for d in cond:
        print(f"      {d}")
    print(f"  dynamic import templates (silent)      {len(dyn):>4}")
    for d in dyn:
        print(f"      {d['file']}:{d['line']}  {d['template']}")
    print(f"\n{'3. DEV= SPACE vs ops_<x> FILES'.center(W, '=')}\n")
    print(f"  ops_<x> files that exist                {len(exist):>4}   {' '.join(exist)}")
    print(f"  backends named by ALL_DEVICES           {len(asked):>4}   {' '.join(asked)}")
    print(f"  ===> DEV= with NO ops_<x> file         {len(mock_gap):>4}   {mock_gap}")
    print(f"      ops file no DEV= reaches           {len(dead):>4}   {dead}")

    print(f"\n{'4. PROVENANCE -- vendored, but is it OURS or UPSTREAMS?'.center(W, '=')}\n")
    print(f"  equals upstream HEAD                  {n_head:>4}")
    print(f"  equals the PIN (behind, correct)      {n_pin:>4}")
    print(f"  equals ANOTHER upstream commit        {len(intermediate):>4}   "
          f"a batch landed mid-window; these are correct, not edits")
    for p, c in intermediate:
        print(f"      {p}  <- {c[:12]}")
    print(f"  upstream has NEVER had the path       {len(localonly):>4}   {localonly}")
    print(f"  ===> equals NEITHER (hand-edit CANDIDATE) {len(neither):>3}   {neither}")
    print("      a file here is in the reference tree but matches no upstream")
    print("      commit, so every CPython oracle measures it. That is a CANDIDATE:")
    print("      a missed commit reads the same. Deciding is an owner call.")
    print("      NOTE: 'neither' used to include the row above it -- comparing against")
    print("      HEAD and the pin alone cannot see an INTERMEDIATE upstream commit,")
    print("      which is what landing a batch produces.")

    if a.expand:
        print("\n  unimportable detail:")
        for d in unimp:
            print(f"      {d['module']}  {d['error']}")


if __name__ == "__main__":
    main()
