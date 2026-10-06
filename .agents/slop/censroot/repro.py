#!/usr/bin/env python3
"""repro.py -- two plants and TWO METHODS THAT SHARE NO REGEX, for the `parents[N]` depth
in `checks/census.py` and `checks/hermetic-census.py`.

WHY TWO PLANTS AND NOT ONE.  A plant that cannot move is a plant that passes.  A single
plant proves nothing, because an assertion that ALWAYS fires is also a gate that always
fails.  So: the correct root must still PASS after the assertion landed, and a moved tree
must go RED NAMING THE DIRECTORY IT REACHED.

WHY TWO METHODS.  Self-consistency is not independence.  The shell unit's own classifier
had three faults, each caught by DISAGREEING with the evidence -- and one of them was a
tokenizer (`[A-Za-z0-9_.-]*`) that ate a full stop, so its own belt MISSED what the belt
existed to catch.  Two mechanisms that cannot share that fault:

  M1  RUNTIME.  Execute the moved file.  Shares no text processing with M2 at all: it
      decides on the process's exit status and on the bytes the process printed.
  M2  AST.  `ast.parse`, then walk for `Subscript(Attribute(..., "parents"), Constant(int))`.
      A PARSER, not a tokenizer: no character class, no regex, nothing to swallow a `.`.
      AST cannot see comments, which is why M3 exists and why M2 alone is not the belt.

M3  SUBSTRING + `Path.exists()`.  Plain `in` containment over comment text plus a
      filesystem probe -- the one thing neither the parser nor the runtime can observe.
      A third mechanism, and deliberately the crudest: it is here to be disagreed with.

TWO FAULTS THIS BELT HAS ALREADY HAD, KEPT BECAUSE A BELT THAT HAS NEVER FAILED WAS NEVER
TESTED.  Both were the belt's, not the gate's:

  * It compared `/var/folders/...` (what `tempfile` hands back) against
    `/private/var/folders/...` (what `Path.resolve()` returns -- `/var` is a symlink).  Two
    SPELLINGS of one directory, so the belt reported "the refusal did not name the directory
    it reached" while the gate had named it correctly.  A self-consistent belt, wrong.
  * It read `parents[2]` in a COMMENT as an assertion about the CURRENT root, and failed on
    prose that deliberately records that `parents[2]` WAS correct at the old home.  A belt
    judging English it cannot parse.

`Path.exists()` follows symlinks, so the resolution is done with `Path.resolve()` and
compared in ONE spelling, never two.

Reproduce (from the repo root):
    python3 .agents/slop/censroot/repro.py
"""
from __future__ import annotations

import ast
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
TARGETS = ("checks/census.py", "checks/hermetic-census.py")


# ------------------------------------------------------------------ M2: the AST belt.
def ast_depths(path: pathlib.Path) -> list[int]:
  """Every `parents[N]` depth N that appears in EXECUTABLE code.  Parser, not regex."""
  depths: list[int] = []
  for node in ast.walk(ast.parse(path.read_text())):
    if (isinstance(node, ast.Subscript) and isinstance(node.value, ast.Attribute)
            and node.value.attr == "parents" and isinstance(node.slice, ast.Constant)
            and isinstance(node.slice.value, int) and not isinstance(node.slice.value, bool)):
      depths.append(node.slice.value)
  return depths


# ---------------------------------------------------------------- M3: the substring belt.
def cited_arith_row_caches(path: pathlib.Path) -> list[str]:
  """Comment claims that a `rows-*.txt` cache lives under `.agents/slop/arith/`.  Decidable
  by containment, unlike the prose it used to try to judge."""
  out = []
  for ln in path.read_text().splitlines():
    if "rows-" in ln and ".txt" in ln and "arith" in ln:
      out.append(ln.strip())
  return out


def arith_row_cache_count() -> int:
  d = REPO / ".agents" / "slop" / "arith"
  return len(list(d.glob("rows-*.txt"))) if d.is_dir() else 0


# ---------------------------------------------------------------- M1: the runtime belt.
def run(rel: str, argv: list[str]) -> tuple[int, str]:
  p = subprocess.run([sys.executable, str(REPO / rel), *argv],
                     capture_output=True, text=True, cwd="/")
  return p.returncode, (p.stdout + p.stderr)


def moved_copy(name: str, depth: int, tmp: pathlib.Path) -> pathlib.Path:
  """Copy a gate `depth` levels deep under a scratch dir.  A COPY IS NOT A MOVE: this is
  the case the original defect could not survive, because `parents[N]` is how a file knows
  where it is.  `cwd='/'` so the CWD cannot supply a root by accident."""
  d = tmp
  for _ in range(depth - 1):
    d = d / "x"
  d.mkdir(parents=True, exist_ok=True)
  dest = d / name
  shutil.copy2(REPO / "checks" / name, dest)
  return dest


def main() -> int:
  fails: list[str] = []

  # ---- PLANT A: the correct root still PASSES.  Without this, "always fires" is unfalsified.
  rc, out = run("checks/census.py", ["--only", "alu"])
  print(f"[A] correct root checks/census.py --only alu -> rc {rc}")
  if rc != 0:
    fails.append(f"PLANT A: correct root rc={rc}, expected 0 (assertion always fires?)")
  if "denominator : " not in out:
    fails.append("PLANT A: no denominator line -- a refusal, not a census")

  # ---- PLANT B: a moved tree goes RED, NAMING the directory it reached.
  with tempfile.TemporaryDirectory(prefix="censroot") as td:
    tmp = pathlib.Path(td).resolve()          # ONE spelling, or the belt disagrees with
    for name, depth in (("census.py", 1), ("census.py", 3), ("hermetic-census.py", 1)):
      dest = moved_copy(name, depth, tmp)
      p = subprocess.run([sys.executable, str(dest), "--only", "alu"],
                         capture_output=True, text=True, cwd="/")
      # REPO as the gate computes it: `HERE` is the directory HOLDING the file, so the depth
      # claim is `HERE.parents[0]` -- one level above the directory, at every depth.  The
      # earlier version of this belt said `dest.parent` and was wrong at BOTH depths, which
      # is why it "caught" a refusal that had in fact named the directory correctly.
      reached = dest.parent.parent
      print(f"[B] {name} copied {depth} deep -> rc {p.returncode}; reached {reached}")
      if p.returncode == 0:
        fails.append(f"PLANT B: {name} at depth {depth} EXITED 0 on the wrong tree")
      elif p.returncode != 3:
        fails.append(f"PLANT B: {name} at depth {depth} rc={p.returncode}, expected 3 "
                    f"(an exception is not a refusal)")
      elif str(reached) not in p.stderr:
        fails.append(f"PLANT B: {name} at depth {depth} refused WITHOUT naming {reached}; "
                    f"got: {p.stderr.strip()[:160]}")
      elif "REFUSED, NOT A VERDICT" not in p.stderr:
        fails.append(f"PLANT B: {name} at depth {depth} refused in an unrecognisable shape")

  # ---- PLANT C: the TWO MARKERS ARE INDEPENDENT.  A scratch tree that SATISFIES the root
  # markers (pyproject.toml + tinybendygrad/) but holds no `graphcmp.py` must be refused for
  # the ABSENT INPUT, naming that input -- not for the root.  Without this, "it refused" could
  # mean one check did all the work, and the root assertion would be unfalsified.
  with tempfile.TemporaryDirectory(prefix="censroot") as td:
    fake = pathlib.Path(td).resolve() / "fake-repo"
    (fake / "tinybendygrad").mkdir(parents=True)
    (fake / "pyproject.toml").write_text("[project]\n")
    dest = moved_copy("census.py", 2, fake)      # in `fake/x/`, so parents[0] IS `fake`
    p = subprocess.run([sys.executable, str(dest)], capture_output=True, text=True, cwd="/")
    print(f"[C] root markers PRESENT, graphcmp absent -> rc {p.returncode}; "
          f"{p.stderr.strip()[:110]}")
    if p.returncode != 3:
      fails.append(f"PLANT C: rc={p.returncode}, expected 3 with both markers present")
    elif "not the repo root" in p.stderr:
      fails.append("PLANT C: blamed the ROOT though the root markers are present -- the two "
                   "markers are not independent")
    elif "graphcmp" not in p.stderr:
      fails.append("PLANT C: refused without naming the absent input")

  # ---- M2: no `parents[N]` with N != 0 in executable code, in either gate.
  for rel in TARGETS:
    depths = ast_depths(REPO / rel)
    bad = [d for d in depths if d != 0]
    print(f"[M2] {rel}: parents[N] depths in code = {depths or '[]'}")
    if bad:
      fails.append(f"M2: {rel} still computes {bad} -- outside the repo is parents[0] here")

  # ---- M3: neither gate may still point a `rows-*.txt` cache at `.agents/slop/arith/`.
  # MEASURED: that directory holds no `rows-*.txt` at all (the sweep took them), so any such
  # citation is a fossil of the pre-move layout -- the item another unit named on line 5.
  live = arith_row_cache_count()
  print(f"[M3] .agents/slop/arith holds {live} rows-*.txt")
  for rel in TARGETS:
    claims = cited_arith_row_caches(REPO / rel)
    print(f"[M3] {rel}: {len(claims)} citation(s) of a rows-*.txt cache under arith")
    if claims:
      fails.append(f"M3: {rel} still cites a rows-*.txt cache under .agents/slop/arith "
                   f"({live} exist there): {claims[0][:90]}")

  print()
  if fails:
    for f in fails:
      print(f"FAIL {f}")
    return 1
  print("PASS: correct root green, both depths moved red naming the reached directory, "
        "and no executable `parents[N]` with N != 0")
  return 0


if __name__ == "__main__":
  sys.exit(main())