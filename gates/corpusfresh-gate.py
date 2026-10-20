#!/usr/bin/env python3
r"""corpusfresh-gate.py -- NOT "IS THE CORPUS STALE?" BUT "WOULD ANYBODY BE TOLD?"

    .venv/bin/python gates/corpusfresh-gate.py            # charge: rc=1 when nobody is told
    .venv/bin/python gates/corpusfresh-gate.py --report   # the census, rc=0
    .venv/bin/python gates/corpusfresh-gate.py --plant    # the control, three directions

THE QUESTION, AND WHY IT IS NOT THE OTHER ONE. Three instruments already answer "is the recorded
corpus verdict current?" correctly and cheaply -- `gates/corpusverdict-gate.py`,
`gates/corpuswitness-gate.py` and `differ.repro_bad()`. MEASURED 2026-10-20T00:56Z, two of them
reported STALE for the re-vendor `77e6c2bec` and one reported 0 complaints. **Every one of them
had to be ASKED.** This gate measures the OTHER half, which is the half that decides whether the
first half is worth having: **is there any surface in this tree that would have announced the
staleness to somebody who did not go looking?**

THE MEASUREMENT THAT MAKES IT NECESSARY. On 2026-10-20 the re-vendor `tinygrad/ 62319c8a ->
6c91e897` landed at `00:53:51Z` (MEASURED: `git log -1 --format=%ad --date=iso tinygrad/`).
MEASURED, this tree:

    .git/hooks/            13 files, ALL `*.sample`   -> 0 non-sample   (`ls | grep -vc '\.sample$'`)
    git config --get core.hooksPath                     -> rc=1, unset
    .github/workflows/     11 tracked files, all upstream tinygrad's; 0 name any gate
    tracked files under gates/artifacts/                -> 0   (`git ls-tree -r HEAD`)

**0 surfaces. 0 of 3 freshness instruments is reachable from any of them.** And the corpus came
back CURRENT at `00:56:48Z` -- **2 minutes 57 seconds after the re-vendor** -- NOT because an
instrument noticed, and NOT because anything in this tree fired, but because the unit that made
the move also ran `checks/differ.py repro` by hand at `00:53:53Z`, **two seconds later**
(MEASURED: `ps -Ao lstart` on pid 14253). **THE COUPLING IS IN AN AGENT'S HANDS, NOT IN THE TREE,
AND A COUPLING THAT IS ONLY IN SOMEONE'S HEAD IS NOT A MECHANISM.** That is this gate's finding
and it is the honest answer to "nobody asked" vs "nobody was told": both produce zero rows, but
only one of them leaves a trace, and this tree keeps **no trace of an invocation at all** -- every
gate's output goes to `gates/artifacts/`, which `.gitignore:214` ignores (MEASURED:
`git check-ignore -v`, rc=0, naming `.gitignore:214`), so from a fresh clone "was this gate ever
run?" and "does this gate exist?" have the same answer: nothing.

WHY IT IS AN AUDITOR AND NOT A GATE, AND WHY `--report` EXISTS. Redness here IS the finding, so a
gate that must go green would have to report the absence of a surface as a PASS -- which is the
defect this file exists to name. The precedent is measured and local: `gates/gate-surface.py`
already ships `--report` for exactly this reason (`.agents/slop/hooks/REPORT.md` §5:
`--report` rc=0, bare rc=1), and that report's own rule applies here unedited -- **the runner's
verdict is about THE RUN, never about the tree.**

DOCTRINE 1 -- BOTH POPULATIONS ARE DISCOVERIES, NOT LISTS.
  * the INSTRUMENTS: a regex over the tree's own gate SOURCES, declared in `FRESH_TOKENS` below,
    read as TEXT and never imported (importing a gate RUNS it; `gates/mixin-op-gate.py` exits 2 at
    module scope -- `.agents/slop/hooks/REPORT.md` §6). This is doctrine 1(c), a regex over the
    tree's own write sites, with the list admitted in a comment, which is why it is admissible at
    all. The gate population itself is `gates/gates-pop.py:discover(root)`, loaded BY PATH.
  * the SURFACES: `os.walk`, never a glob, for the same reason `artefacts_ok()` moved off
    `D.glob("*.txt")` -- a glob is a set of names this file chooses.
"""

from __future__ import annotations

import argparse
import importlib.util
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
ART = HERE / "artifacts" / "corpusfresh-gate"

#: ADMITTED IN A COMMENT, per doctrine 1(c). A gate is a *freshness instrument* iff its own source
#: mentions one of these -- which is what `corpusverdict-gate.py` does (it calls
#: `differ.substrate_digest()`), what `corpuswitness-gate.py` does (it reads
#: `differ.REPRO_PINS + REPRO_SUBSTRATE` and an `mtime_ns` ordering), and what `differ.repro_bad()`
#: does (the `REPRO_SUBSTRATE` arm). A gate can be BOTH a freshness instrument and its own
#: discriminator here; that overlap is the point, not a duplicate.
#:
#: **THIS IS A DELIBERATE SUPERSET, AND THE DIRECTION IS THE POINT.** MEASURED 2026-10-20T00:59Z
#: it names 13 of the 277 entries `discover()` returns, and several of the 13 (`substrate-id.py`,
#: `substrate-manifest.py`, `gendirs.py`) merely COMPUTE a digest rather than judging one, and this
#: file names itself because its own docstring contains the tokens. The imprecision is left in
#: because a superset can only make `told` LARGER: a false positive here can turn a finding into a
#: false alarm, while a false negative would turn `told=0` into a number it is not. **A classifier
#: tuned until its count looks right is the `kind()` defect this project has already paid for
#: (`AGENTS.md`: 16 instruments, 2 of them classifier errors).** It is called a SUPERSET in the
#: rows and the tally names it as such.
FRESH_TOKENS = ("substrate_digest", "REPRO_SUBSTRATE", "substrate-start", "st_mtime_ns")

#: The four verdicts this gate's census can reach. Not the five-exit vocabulary -- a *hit* is not a
#: verdict about the tree, it is an observation about a file, and inventing an exit for it would be
#: the "sixth verdict" the hooks report warns against.
HIT, MISS, UNKNOWN, NOHOOKDIR = "HIT", "MISS", "UNKNOWN", "NO-SURFACE"


def load(path: pathlib.Path, name: str):
  """BY PATH. `gates-pop` declares the gate population, so it is imported rather than re-typed."""
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  sys.modules[name] = mod
  spec.loader.exec_module(mod)
  return mod


def gates(root: pathlib.Path = ROOT) -> list[pathlib.Path]:
  """`discover()`'s entries, ABSOLUTE `pathlib.Path`s (MEASURED: 277, and it sweeps `.tmp-*`
  scratch, which is the population's business and not this file's). Returned as-is -- no name
  string is rebuilt here, because rebuilding one is how a path and a name stop agreeing."""
  pop = load(root / "gates" / "gates-pop.py", "corpusfresh_gatespop")
  entries, _ = pop.discover(root)
  return [p for p in entries if p.is_file()]


def is_freshness_instrument(path: pathlib.Path) -> str | None:
  """The token that qualifies this gate, or None. READ AS TEXT: importing a gate RUNS it."""
  try:
    src = path.read_text()
  except OSError:
    return None
  for tok in FRESH_TOKENS:
    if tok in src:
      return tok
  return None


def hook_dirs(root: pathlib.Path) -> list[tuple[str, pathlib.Path]]:
  """`(label, dir)` for every directory git would read a hook FROM. Two, and both are real:
  `.git/hooks/` always exists, and `core.hooksPath` OVERRIDES it when set. A census that reads
  only the first one reports NO-SURFACE on a tree whose hooks are installed one level over."""
  out = [(".git/hooks", root / ".git" / "hooks")]
  q = subprocess.run(["git", "config", "--get", "core.hooksPath"], cwd=root,
                     capture_output=True, text=True)
  hp = q.stdout.strip()
  if q.returncode == 0 and hp:
    d = pathlib.Path(hp)
    out.append(("core.hooksPath", d if d.is_absolute() else root / d))
  return out


def live_hooks(root: pathlib.Path) -> list[pathlib.Path]:
  """Every non-`.sample` hook file, by DIRECTORY WALK in every hooks dir."""
  out = []
  for _, d in hook_dirs(root):
    if not d.is_dir():
      continue
    for p in sorted(d.rglob("*")):
      if p.is_file() and not p.name.endswith(".sample"):
        out.append(p)
  return out


def workflow_files(root: pathlib.Path) -> list[pathlib.Path]:
  """`.github/workflows/**`, walked. Untracked ones still count: a workflow that is not committed
  does not run, so they are counted separately rather than silently trusted or silently dropped."""
  base = root / ".github" / "workflows"
  return sorted(p for p in base.rglob("*") if p.is_file()) if base.is_dir() else []


def census(root: pathlib.Path, hooks: list[pathlib.Path], flows: list[pathlib.Path],
           names: set[str]) -> dict[str, list[tuple[str, str]]]:
  """name -> the surfaces naming it. `HIT` needs the gate's OWN name in a surface's bytes."""
  surfaces = [(p, p.read_text(errors="replace")) for p in (*hooks, *flows)]
  out: dict[str, list[tuple[str, str]]] = {}
  for n in sorted(names):
    stem = pathlib.Path(n).name
    out[n] = [str(p.relative_to(root)) if root in p.parents or p.parent == root else str(p)
              for p, body in surfaces if stem in body]
  return out


def name_class(surfaces: list[tuple[str, str]], probe: str, known: set[str]) -> str:
  """HIT / MISS / UNKNOWN for a string a caller chose. The UNKNOWN arm is what makes this a
  control rather than a demo: a surface naming a gate that is NOT in the population must not be a
  HIT, so a comparator that is really just `if True` is caught here instead of scoring a HIT."""
  return HIT if any(probe in b for _, b in surfaces) else (UNKNOWN if probe not in known else MISS)


def emit(name: str, **kv) -> str:
  return "\t".join([name] + [f"{k}={v}" for k, v in kv.items()])


# ---- the plant: FIVE DIRECTIONS, IN A THROWAWAY TREE, NEVER IN .git/hooks/ -------------------
# The live `.git/hooks/` is SHARED by every concurrent unit (`.agents/slop/hooks/REPORT.md` §4
# gives that as the reason its own install was declined), so the control builds its own repo in a
# temp dir and drives THE SAME `census()`/`live_hooks()` the live path uses. A control that
# exercised a copy of the comparator would prove the copy works.
#
# **THE FIRST VERSION OF THIS PLANT HAD FOUR DIRECTIONS AND TWO MUTANTS SURVIVED IT** -- MEASURED
# 2026-10-20T00:58Z, by mutating the comparator: `if stem in body` -> `if "g" in body` and
# `if True` both still scored 4 of 4, rc=0. The reason is that every one of those four directions
# asked the comparator about a tree with **ZERO** surfaces, where "matches the name" and "matches
# everything" are indistinguishable. DIRECTION 3 IS THE ONE THAT KILLS BOTH, and it could not
# exist until the plant had a surface that names SOMETHING ELSE. **A control that only ever runs
# against an empty tree is a control that cannot fail**, which is the same defect as a plant that
# compares a number to itself.
def plant() -> int:
  rows: list[str] = []
  with tempfile.TemporaryDirectory(prefix="corpusfresh-plant-") as td:
    root = pathlib.Path(td)
    subprocess.run(["git", "init", "-q", str(root)], check=True, capture_output=True)
    (root / "gates").mkdir()
    real, other, absent = "corpusverdict-gate.py", "unrelated-gate.py", "no-such-gate.py"
    for n in (real, other):
      (root / "gates" / n).write_text("x\n")
    names = {real, other}
    hk = root / ".git" / "hooks"
    hk.mkdir(exist_ok=True)
    (hk / "pre-commit.sample").write_text(f"{real}\n")   # a sample must NEVER count
    hook = hk / "pre-commit"

    def verdict_of(target: str) -> str:
      c = census(root, live_hooks(root), workflow_files(root), names)
      return HIT if c.get(target) else MISS

    def check(label: str, got: str, want: str) -> None:
      rows.append(emit(f"plant.{label}", state="OK" if got == want else "REFUSED",
                       verdict=got, wanted=want))

    hook.write_text(f"exec {real} $@\n")                       # 1: names the real gate
    check("finds-a-named-gate", verdict_of(real), HIT)
    hook.unlink()                                              # 2: nothing left to name it
    check("stops-when-removed", verdict_of(real), MISS)
    hook.write_text(f"exec {other} $@\n")                      # 3: A SURFACE, naming another
    check("unrelated-surface-is-not-a-hit", verdict_of(real), MISS)
    check("unrelated-surface-hits-its-own", verdict_of(other), HIT)
    got = name_class([(str(p), p.read_text()) for p in live_hooks(root)], absent, names)
    check("unknown-is-not-a-hit", got, UNKNOWN)                # 4: names nobody in the population
    hook.unlink()                                               # 5: only the `.sample` remains
    rows.append(emit("plant.sample-is-not-a-hook",
                     state="OK" if not live_hooks(root) else "REFUSED",
                     live=len(live_hooks(root)), wanted=0))

  ok = sum(r.split("\t")[1] == "state=OK" for r in rows)
  print("\n".join(rows))
  print(f"corpusfresh-gate --plant: {'OK' if ok == len(rows) else 'REFUSED'} ({ok} of {len(rows)})")
  return 0 if ok == len(rows) else 3


def main(argv=None) -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--report", action="store_true", help="print the census and rc=0")
  ap.add_argument("--plant", action="store_true", help="run the control in a throwaway tree")
  a = ap.parse_args(argv)
  if a.plant:
    return plant()

  rows: list[str] = []
  gs = gates(ROOT)
  instr = {}
  for p in gs:
    tok = is_freshness_instrument(p)
    if tok:
      instr[str(p.relative_to(ROOT))] = tok
  names = set(instr)

  hooks, flows = live_hooks(ROOT), workflow_files(ROOT)
  rows.append(emit("population", gates=len(gs), freshness=len(instr), klass="SUPERSET",
                   declared_by="gates-pop.discover() + FRESH_TOKENS regex over gate sources"))
  rows.append(emit("surfaces", hooks=len(hooks), workflows=len(flows),
                   hookdirs=",".join(lbl for lbl, _ in hook_dirs(ROOT))))
  if not hooks and not flows:
    rows.append(emit("surface", state=NOHOOKDIR, hooks=0, workflows=0))

  c = census(ROOT, hooks, flows, names)
  for n in sorted(c):
    rows.append(emit("told", state="OK" if c[n] else "REFUSED", instrument=n,
                     surfaces=len(c[n]), where=";".join(c[n]) or "-"))
  told = sum(1 for n in c if c[n])
  rows.append(emit("tally", instruments=len(instr), told=told, untold=len(instr) - told))

  # THE INVOCATION RECORD. Every gate's output lands in gates/artifacts/, which is ignored, so a
  # fresh clone cannot distinguish "never ran" from "does not exist". This is the second half of
  # "nobody was told": not only was nothing said, nothing was RECORDED.
  q = subprocess.run(["git", "check-ignore", "-q", str(ART)], cwd=ROOT)
  tracked = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"], cwd=ROOT,
                           capture_output=True, text=True).stdout
  n_tracked = sum(1 for ln in tracked.splitlines() if ln.startswith("gates/artifacts/"))
  rows.append(emit("record", state="FAIL" if (q.returncode == 0 and n_tracked == 0) else "OK",
                   artifacts_ignored=q.returncode == 0, artifacts_tracked=n_tracked))

  body = ("# corpusfresh.rows -- GENERATED by `gates/corpusfresh-gate.py`, its ONLY writer.\n"
          "# The census of surfaces that could ANNOUNCE a stale corpus verdict.\n"
          + "\n".join(rows) + "\n")
  ART.mkdir(parents=True, exist_ok=True)
  (ART / "corpusfresh.rows").write_text(body)
  print("\n".join(rows))

  if not rows:
    print("corpusfresh-gate: DEAD -- no rows")
    return 5
  if told:
    print(f"corpusfresh-gate: PASS -- {told} of {len(instr)} freshness instruments are reachable "
          f"from a surface that fires without being asked")
    return 0
  msg = (f"corpusfresh-gate: RED -- {len(instr)} of {len(instr)} freshness instruments are "
         f"correct, and NONE is reachable from any surface. A re-vendor is silent until a human "
         f"asks; this tree has no place that tells anybody.")
  print(msg if a.report is False else msg)
  return 0 if a.report else 1


if __name__ == "__main__":
  sys.exit(main())