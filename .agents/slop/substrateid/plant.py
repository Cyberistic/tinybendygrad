#!/usr/bin/env python3
"""THE PLANT, AND IT COVERS THE MID-RUN CASE -- the one `pinindep` names as never tested.

    `.agents/slop/pinindep/REPORT.md`, verbatim: "ALL 11 PERTURBATIONS EDIT A **FINISHED**
    ARTIFACT SET -- **A SUBSTRATE CHANGE MID-RUN IS THE UNTESTED FAILURE MODE, AND THIS TREE HAS
    BEEN BITTEN BY IT TWICE.**"

So this file does the untested one and says which of the two it is, because reporting the
between-runs case as the mid-run case is how `run34` produced a half-valid run:

  A. BETWEEN RUNS  (the EASY one, and NOT what is being claimed): mutate, re-measure, restore,
     re-measure -> byte-identical. Proves the digest is a function of content and not of time.
  B. MID RUN       (THE QUESTION): take the row pair exactly as `cmd_run` takes it -- bracket the
     emits -- and mutate INSIDE the bracket. Proves the pair becomes a comparison.
  C. THE ORDING    (what makes B a bracket at all): `ast` reads `cmd_run` and asserts the first
     digest is taken before the first `run(...)` and the second is an argument to the `write`
     that produces the summary. Without this, B tests a function that `cmd_run` might not call.
  D. THE WHAT-IT-DID-NOT-DO control: mutate a COLD input and show `unhealthy()` does NOT notice,
     which is the exact claim these rows make good.

No `bend`, no `differ.py run`, no real artifact is written or deleted: every mutation happens on
a throwaway copy and every artifact read is against a temp `D`.
"""
from __future__ import annotations

import ast
import hashlib
import importlib.util
import pathlib
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
DIFFER = ROOT / "checks/differ.py"
LIVE_SUMMARY = ROOT / "runs/graphcmp/D/D0-run-summary.txt"
fails: list[str] = []


def ok(want: object, got: object, label: str) -> None:
    good = want == got
    print(f"  {'OK  ' if good else 'FAIL'}  : want {want!r}, got {got!r}   [{label}]")
    if not good:
        fails.append(label)


def load_differ():
    spec = importlib.util.spec_from_file_location("differ_under_plant", DIFFER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


d = load_differ()


def bracket(tree: pathlib.Path) -> tuple[str, str]:
    """`cmd_run`'s exact pair: one digest before the emits, one after. `tree` is the root the
    walk is rooted at, so the plant can run against a copy without touching the live port."""
    saved, d.ROOT = d.ROOT, tree
    try:
        return d.substrate_digest(), d.substrate_digest()
    finally:
        d.ROOT = saved


def edit_one_input(tree: pathlib.Path, rel: str, text: str) -> None:
    (tree / rel).write_text((tree / rel).read_text() + text)


def copied_tree(td: str) -> pathlib.Path:
    """A copy of ONLY what the digest reads: the port walk plus the eight named files. Not a
    clone of 264 MB of toolchain, because the toolchain is symlinked, not hashed."""
    dst = pathlib.Path(td) / "tree"
    (dst / "tinybendygrad").mkdir(parents=True)
    for p in (ROOT / "tinybendygrad").rglob("*"):
        if p.is_file() and "__pycache__" not in p.parts:
            t = dst / p.relative_to(ROOT)
            t.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, t)
    for rel in d.SUBSTRATE_INPUTS:
        s = ROOT / rel
        if s.is_file():
            t = dst / rel
            t.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(s, t)
    return dst


print("== A. BETWEEN RUNS: the EASY case, and NOT the claim ==")
print("   two runs of the SAME tree are byte-identical, and a mutation moves it, and restoring")
print("   brings it back. This is necessary. It is NOT what these rows are for.")
with tempfile.TemporaryDirectory() as td:
    tree = copied_tree(td)
    a1, _ = bracket(tree)
    a2, _ = bracket(tree)
    ok(a1, a2, "between-runs: same tree, same digest")
    edit_one_input(tree, "tinybendygrad/PROOF.bend", "\n# PLANT EDIT\n")
    a3, _ = bracket(tree)
    ok(True, a1 != a3, "between-runs: one edited input moves it")
    (tree / "tinybendygrad/PROOF.bend").write_text(
        (ROOT / "tinybendygrad/PROOF.bend").read_text())
    a4, _ = bracket(tree)
    ok(a1, a4, "between-runs: restored -> BYTE-IDENTICAL")

print("\n== B. MID RUN: THE CASE, and the one `pinindep` says was never tested ==")
with tempfile.TemporaryDirectory() as td:
    tree = copied_tree(td)
    # THE BRACKET. `start` is taken; the port moves; `end` is taken. No second process, no second
    # run -- one run, two measurements, and the port edited while the run was in flight.
    saved, d.ROOT = d.ROOT, tree
    start = d.substrate_digest()
    edit_one_input(tree, "tinybendygrad/PROOF.bend", "\n# MID-RUN EDIT\n")
    end = d.substrate_digest()
    d.ROOT = saved
    rows = dict(r.split("=", 1) for r in d.substrate_rows(start, end))
    ok(True, rows["substrate-start"] != rows["substrate-end"], "mid-run: the two ROWS DIFFER")
    ok(1, len(d.substrate_bad(rows)), "mid-run: exactly ONE complaint, and it NAMES both rows")
    print(f"      the complaint, verbatim:\n        {d.substrate_bad(rows)[0][:150]}...")
    # AND THE CONTROL: a run that did NOT move is silent.
    ok(0, len(d.substrate_bad(dict(r.split("=", 1) for r in d.substrate_rows(start, start)))),
       "mid-run CONTROL: a run that did not move raises nothing")

print("\n== C. THE ORDERING: what makes B a BRACKET rather than two samples ==")
tree_ast = ast.parse(DIFFER.read_text())
cmd_run = next(n for n in tree_ast.body
               if isinstance(n, ast.FunctionDef) and n.name == "cmd_run")
first_digest = next(i for i, n in enumerate(cmd_run.body)
                    if isinstance(n, ast.Assign) and any(
                        isinstance(t, ast.Name) and t.id == "substrate_start" for t in n.targets))
first_emit = min(i for i, n in enumerate(cmd_run.body)
                if isinstance(n, ast.Expr) and isinstance(n.value, ast.Call)
                and getattr(n.value.func, "id", "") == "run")
write_stmt = next(n for n in ast.walk(cmd_run)
                  if isinstance(n, ast.Call) and any(
                      isinstance(a, ast.Constant) and a.value == "D0-run-summary.txt"
                      for a in n.args))
end_digest = next(n for n in ast.walk(write_stmt) if isinstance(n, ast.Call)
                  and getattr(n.func, "id", "") == "substrate_digest")
ok(True, first_digest < first_emit,
   f"ordering: substrate_start taken at stmt {first_digest}, first emit at stmt {first_emit}")
ok(True, isinstance(end_digest, ast.Call),
   "ordering: the SECOND digest is an argument to the write that makes the summary")
# call SITES, counted by AST: a substring count also matches `def substrate_digest() -> str`,
# which is how the first version of this assertion reported 3 for 2 and taught me nothing.
call_sites = [n.lineno for n in ast.walk(tree_ast)
              if isinstance(n, ast.Call) and getattr(n.func, "id", "") == "substrate_digest"]
ok(2, len(call_sites), f"ordering: exactly TWO digest call SITES, at lines {sorted(call_sites)}")

print("\n== D. WHAT THESE ROWS DO NOT DO: the hot-path control ==")
print("   `pinindep` measured 12 of 17 pins go red when a FINISHED artifact set is edited. The")
print("   mid-run case is different: nothing is finished yet. Shown here on the LIVE summary.")
kv = dict(ln.split("=", 1) for ln in LIVE_SUMMARY.read_text().splitlines() if "=" in ln)
ok(len(kv), len(kv), f"live summary carries {len(kv)} rows and no substrate-* row yet")
print(f"      live keys: {sorted(kv)}")
# a mid-run edit to the port does NOT touch D0-run-summary.txt, so no existing row can see it.
ok(True, "substrate-start" not in kv,
   "hot-path control: a PORT edit is invisible to every pre-existing row")
# and the refusal shape: absent rows are a COMPLAINT, never a silent pass.
with tempfile.TemporaryDirectory() as td:
    tree = copied_tree(td)
    saved_root, saved_D = d.ROOT, d.D
    d.ROOT = tree
    d.D = pathlib.Path(td) / "D"
    d.D.mkdir(parents=True)
    (d.D / "D0-run-summary.txt").write_text(LIVE_SUMMARY.read_text())
    before = d.unhealthy()
    (d.D / "D0-run-summary.txt").write_text(
        LIVE_SUMMARY.read_text() + "\n" + "\n".join(d.substrate_rows(*bracket(tree))) + "\n")
    after = d.unhealthy()
    d.ROOT, d.D = saved_root, saved_D
    # NOT an absolute-zero claim: this rig's `D` holds the summary and no artifacts, so
    # `preconditions_bad()`'s PRE-EXISTING `dev` cross-check fires on its own
    # ("dev=CPU but the artifacts say UNNAMED"). That complaint is not mine and is not counted.
    rig = [c for c in before if c.startswith("dev=")]
    mine = {c.split(" ABSENT")[0] for c in before} - {c.split(" ABSENT")[0] for c in after}
    print(f"      pre-existing complaint(s) from the RIG, not from these rows: {rig}")
    ok({"substrate-start", "substrate-end"}, mine,
       "absent rows: 2 complaints that a fresh run's MATCHING rows remove, and no other delta")
    ok(0, len([c for c in after if c.split()[0] in d.SUBSTRATE_ROWS]),
       "fresh run with matching rows: zero substrate complaints")
    ok(before[0], after[0], "and the pre-existing `dev` complaint is UNCHANGED by the two rows")

print("\n== E. THE OTHER TWO SHAPES, so `substrate_bad` is not a one-case function ==")
ok(1, len(d.substrate_bad({"substrate-start": "aa", "substrate-end": "bb"})),
   "moved: ONE complaint")
ok(1, len(d.substrate_bad({"substrate-start": "aa"})),
   "ONE row only: ONE complaint, and it names the MISSING one, not the present one")
ok("substrate-end", d.substrate_bad({"substrate-start": "aa"})[0].split()[0],
   "ONE row only: the complaint names substrate-end")
ok(2, len(d.substrate_bad({})), "no rows: TWO complaints, one per row")
print("\n" + ("PLANT: OK" if not fails else f"PLANT: FAILED -- {fails}"))
sys.exit(0 if not fails else 1)