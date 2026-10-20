#!/usr/bin/env python3
"""noblob-census -- the subjects recover() was asked for and did not answer.

    .venv/bin/python gates/noblob-census.py
    .venv/bin/python gates/noblob-census.py --plant

`gates/oracle-dangling-gate.py` is LOADED BY PATH. `census()` and `recover()` are the
generator. A no-blob subject is a dangling subject of a kind `census()` passes to
`recover()`, absent from `recover()`'s answer. The prior reading was 40. The count is
re-derived; if it is not 40 the tree moved, and a path is not dropped to keep 40.

TWO CLAIMS, AND THEY ARE NOT THE SAME. `git log --all -- <path>` empty is
NEVER-IN-HISTORY: no commit has ever carried the path. That is not "the blob was
garbage-collected". A non-empty log whose blob `recover()` did not return is
BLOB-GONE-BUT-LOGGED. The question is asked by path. `git rev-list --all` is not a
path index and is not used.

CITERS ARE DISCOVERED from the same namer bodies, through the same `tokens()`, at
file:line. Not a hand list.

THE FINDING IS REPORTED, NOT CHARGED. PASS is every no-blob subject carrying exactly
one history class and at least one discovered citer. The plant is what can fail: a
never-committed citation is NEVER-IN-HISTORY; a citation whose blob was removed from
a copy of the index, but which `git log` still has, is not; an existing file is not
in the no-blob list.

`recover()` claims a grandparent walk. This file reads that claim and does not fix it.
"""
from __future__ import annotations

import argparse
import importlib.util
import inspect
import os
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

DANGLING = HERE / "oracle-dangling-gate.py"
# The reading this gate was asked to chase. A comparison, not a population: the count
# below is re-derived, and a path is never dropped to keep this number.
PRIOR = 40
# The filter `census()` applies before it calls `recover()`. Loaded from that source
# at run time (`filter_loaded`); this tuple is the expected text, not a second rule.
FILTER = ("ORACLE", "EV", "SWEPT")
NEVER = "NEVER-IN-HISTORY"
LOGGED = "BLOB-GONE-BUT-LOGGED"
CLASSES = (NEVER, LOGGED)


def git(args: list[str], env: dict | None = None, stdin: str | None = None) -> subprocess.CompletedProcess:
  """`git` in ROOT. `env` is merged over the process environment so a plant can point
  `GIT_INDEX_FILE` at a copy index without the caller exporting it."""
  run_env = os.environ.copy()
  if env:
    run_env.update(env)
  return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, input=stdin, env=run_env)


def load_dangling():
  """Import the generator by path. `gates/` is not a package."""
  if not DANGLING.is_file():
    return None
  spec = importlib.util.spec_from_file_location("oracle_dangling_noblob", DANGLING)
  if spec is None or spec.loader is None:
    return None
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  if not callable(getattr(mod, "census", None)) or not callable(getattr(mod, "recover", None)):
    return None
  if not callable(getattr(mod, "kind_of", None)) or not callable(getattr(mod, "tokens", None)):
    return None
  if not callable(getattr(mod, "namer_population", None)):
    return None
  return mod


def filter_loaded(mod) -> bool:
  """The asked-kinds rule is `census()`'s own text. A missing string is a REFUSAL, not a guess.

  The source spells the tuple with double quotes. `FILTER!r` would look for single quotes
  and refuse a rule that is there.
  """
  src = inspect.getsource(mod.census)
  return 'in ("ORACLE", "EV", "SWEPT")' in src and "recover(" in src


def walk_claim(mod) -> str:
  """What `recover()`'s source does, against what its comment claims. Not a fix."""
  src = inspect.getsource(mod.recover)
  claims = "grandparent" in src
  wipes = "cur_parents = []" in src
  one_parent = "chain.append(cur_parents[0])" in src
  if claims and wipes and one_parent:
    return ("CONFIRMED, not fixed: recover() claims a grandparent walk and assigns "
            "cur_parents = [] after appending one parent, so the chain is the touching "
            "commit and its parent")
  return "NOT CONFIRMED: recover()'s source no longer has the grandparent-wipe shape"


def touching(paths: list[str], env: dict | None = None) -> dict[str, list[str]] | None:
  """`path -> commits` from `git log --all -- <paths>`, newest first.

  A path absent from the output has an empty log. One walk, pathspec-limited:
  `--name-only` under a pathspec names only the paths that matched (measured: a 3-file
  commit named only the pathspec). Not `git rev-list --all`. A non-zero git status is
  `None` -- an unanswered log is not an empty history.
  """
  out = {p: [] for p in paths}
  if not paths:
    return out
  p = git(["log", "--all", "--format=%x01%H", "--name-only", "--", *paths], env=env)
  if p.returncode != 0:
    return None
  wanted = set(paths)
  sha = ""
  for line in p.stdout.splitlines():
    if line.startswith("\x01"):
      sha = line[1:].strip()
      continue
    if not line or not sha:
      continue
    if line[:1] in "\"'":
      return None
    if line in wanted and sha not in out[line]:
      out[line].append(sha)
  return out


def citers_of(paths: set[str], bodies: list[tuple[str, str]], tokens) -> dict[str, list[str]]:
  """`path -> ['file:line', ...]` discovered by the generator's own tokenizer. Not a hand list."""
  out = {p: [] for p in paths}
  if not paths:
    return out
  for rel, body in bodies:
    for n, line in enumerate(body.splitlines(), 1):
      seen: set[str] = set()
      for tok in tokens(line):
        if tok in out and tok not in seen:
          seen.add(tok)
          out[tok].append(f"{rel}:{n}")
  return out


def derive(mod, surveyed: dict, fs: Path) -> dict:
  """The no-blob set, re-derived, and one history class per path."""
  roles = surveyed["roles"]
  asked = [t for t in surveyed["dangling"] if mod.kind_of(t, roles) in FILTER]
  recovery = surveyed["recovery"]
  missing = [t for t in asked if t not in recovery]
  witness = sorted(mod.recover(missing))
  commits = touching(missing)
  if commits is None:
    raise RuntimeError("git log --all -- <paths> did not answer")
  bodies, _deriv = mod.namer_population(fs)
  cites = citers_of(set(missing), bodies, mod.tokens)
  rows = []
  for path in missing:
    touched = commits.get(path, [])
    rows.append({
      "path": path,
      "kind": mod.kind_of(path, roles),
      "class": NEVER if not touched else LOGGED,
      "commits": touched,
      "citers": cites.get(path, []),
    })
  return {"asked": asked, "recovered": len(recovery), "rows": rows,
          "witness": witness, "walk": walk_claim(mod),
          "stamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}


def probe_beyond(rows: list[dict]) -> list[str]:
  """Grandparents `recover()` does not ask, that still name a blob. By path. Nothing is written back."""
  logged = [r for r in rows if r["class"] == LOGGED and r["commits"]]
  specs: list[tuple[str, str]] = []
  for r in logged:
    for sha in r["commits"][:4]:
      parent = git(["rev-parse", "--verify", f"{sha}^"])
      if parent.returncode != 0:
        continue
      grand = git(["rev-parse", "--verify", f"{parent.stdout.strip()}^"])
      if grand.returncode != 0:
        continue
      specs.append((r["path"], f"{grand.stdout.strip()}:{r['path']}"))
  if not specs:
    return []
  chk = git(["cat-file", "--batch-check"], stdin="\n".join(s for _, s in specs) + "\n")
  found = []
  for (path, spec), line in zip(specs, chk.stdout.splitlines()):
    fields = line.split()
    if len(fields) >= 3 and fields[1] == "blob":
      found.append(f"{path}  blob at grandparent {spec}  {fields[2]} B")
  return found


def _cite_preview(citers: list[str], n: int = 6) -> str:
  if len(citers) <= n:
    return ", ".join(citers)
  return ", ".join(citers[:n]) + f"  (+{len(citers) - n})"


def report(got: dict) -> None:
  rows = got["rows"]
  n = len(rows)
  by = {k: [r for r in rows if r["class"] == k] for k in CLASSES}
  head = git(["rev-parse", "HEAD"]).stdout.strip()
  print(f"noblob-census   HEAD {head}   {got['stamp']}")
  print("  COMMAND        .venv/bin/python gates/noblob-census.py")
  print("  DERIVED        census() dangling, kind in census()'s recover() filter, absent from recover()")
  print(f"  ASKED          {len(got['asked'])}   RECOVERED {got['recovered']}   NO-BLOB {n}")
  if n == PRIOR:
    print(f"  TREE           unmoved from the prior reading {PRIOR}")
  else:
    print(f"  TREE MOVED     prior reading {PRIOR}, this reading {n}. No path was dropped to keep {PRIOR}.")
  print(f"  {NEVER:<22} {len(by[NEVER])}")
  print(f"  {LOGGED:<22} {len(by[LOGGED])}")
  print(f"  WALK           {got['walk']}")
  if got["witness"]:
    print(f"  WITNESS        a second recover() found {len(got['witness'])} blob(s); paths kept: "
          + ", ".join(got["witness"][:8]))
  else:
    print(f"  WITNESS        recover() on the {n} agreed: still no blob")
  print("  PATHS")
  for r in rows:
    tip = r["commits"][0][:12] if r["commits"] else "-"
    print(f"    {r['class']:<22} {r['kind']:<10} log={len(r['commits']):<4} tip={tip}  {r['path']}")
    print(f"      citers {len(r['citers'])}: {_cite_preview(r['citers'])}")
  never = by[NEVER]
  print(f"  {NEVER} NAMED  {len(never)}")
  for r in never:
    print(f"    {r['path']}")
  if len(never) > 60:
    print("    (list is long; the lines above are the count's members, not a sample)")
  files = Counter(c.rsplit(":", 1)[0] for r in never for c in r["citers"])
  print(f"  TOP CITERS of {NEVER}  {len(files)} file(s)")
  for rel, k in files.most_common(8):
    print(f"    {k:>4}  {rel}")
  beyond = probe_beyond(rows)
  print(f"  BEYOND RECOVER()  {len(beyond)} grandparent blob(s) asked by path, not written back")
  for line in beyond[:12]:
    print(f"    {line}")
  if len(beyond) > 12:
    print(f"    ... and {len(beyond) - 12} more")


def check(got: dict) -> tuple[int, str]:
  """Coverage only. The finding is printed above and is not an exit."""
  rows = got["rows"]
  if len(got["asked"]) != got["recovered"] + len(rows):
    return FAIL, (f"asked {len(got['asked'])} != recovered {got['recovered']} + no-blob {len(rows)}")
  bad = [r["path"] for r in rows if r["class"] not in CLASSES]
  if bad:
    return FAIL, f"{len(bad)} subject(s) carry no history class: {bad[:5]}"
  tally = Counter(r["class"] for r in rows)
  if sum(tally.values()) != len(rows):
    return FAIL, f"class counts sum to {sum(tally.values())} over {len(rows)}"
  silent = [r["path"] for r in rows if not r["citers"]]
  if silent:
    return FAIL, f"{len(silent)} no-blob subject(s) have no discovered citer: {silent[:5]}"
  return PASS, (f"{len(rows)} no-blob, " + " ".join(f"{k}={tally[k]}" for k in CLASSES))


def _never_path() -> str:
  """A path this source must not cite as one token. `.agents` is dropped by `tokens()`
  (dot at index 0); the remainder is not a top-level name of the commit tree."""
  return ".agents" + "/" + "slop/noblob-plant/never-existed.rows"


def _existing(surveyed: dict, mod, skip: set[str]) -> str | None:
  roles = surveyed["roles"]
  for p in sorted(surveyed["head"]):
    if p in skip or not (ROOT / p).is_file():
      continue
    if mod.kind_of(p, roles) in FILTER:
      return p
  for p in sorted(surveyed["head"]):
    if p not in skip and (ROOT / p).is_file():
      return p
  return None


def plant(mod, surveyed: dict, real: dict) -> int:
  """Three checks, on a copy of one namer and a private index. The real index is not written.

  PLANT     a citation of a path that has never existed appears as NEVER-IN-HISTORY.
  FALSIFY   a citation of a path whose blob is deleted from the copy's index, but which
            `git log --all -- <path>` still has, does not become NEVER-IN-HISTORY.
  CONTROL   an existing file is not in the no-blob list.
  """
  import tempfile
  never = _never_path()
  own = (HERE / "noblob-census.py").read_text()
  if never in mod.tokens(own):
    print("PLANT REFUSED: this file cites the never-path as a whole token")
    return REFUSED
  real_missing = {r["path"] for r in real["rows"]}
  if never in real_missing or never in surveyed["subjects"]:
    print(f"PLANT REFUSED: {never} is already a subject")
    return REFUSED
  writers = sorted({n for ns in surveyed["subjects"].values() for n in ns
                    if n.endswith(".py") and n.startswith("gates/") and (ROOT / n).is_file()})
  if not writers:
    print("PLANT REFUSED: no discovered gates/*.py namer to cite from")
    return REFUSED
  writer = writers[0]
  control = _existing(surveyed, mod, set())
  victim = _existing(surveyed, mod, {control} if control else set())
  if control is None or victim is None or victim == writer:
    print(f"PLANT REFUSED: control={control} victim={victim} writer={writer}")
    return REFUSED
  pre = touching([victim])
  if not pre or not pre.get(victim):
    print(f"PLANT REFUSED: {victim} has an empty git log; it cannot falsify NEVER-IN-HISTORY")
    return REFUSED
  real_index = ROOT / ".git" / "index"
  index_mtime = real_index.stat().st_mtime_ns if real_index.exists() else None
  with tempfile.TemporaryDirectory(prefix="noblob-plant.") as tmp:
    copy = Path(tmp) / "repo"
    dest = copy / writer
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text((ROOT / writer).read_text()
                    + f"\nPLANT_NEVER = {never!r}\nPLANT_LOGGED = {victim!r}\n")
    index = copy / "plant-index"
    env = {"GIT_INDEX_FILE": str(index)}
    rt = git(["read-tree", "HEAD"], env=env)
    rm = git(["update-index", "--force-remove", "--", victim], env=env)
    listed = git(["ls-files", "--", victim], env=env)
    if rt.returncode != 0 or rm.returncode != 0 or listed.stdout.strip():
      print("PLANT REFUSED: the copy index did not lose the blob")
      print(f"  read-tree rc={rt.returncode} update-index rc={rm.returncode} ls-files={listed.stdout.strip()!r}")
      return REFUSED
    after_log = touching([victim], env=env)
    if after_log is None:
      print("PLANT REFUSED: git log did not answer under the stripped index")
      return REFUSED
    after = mod.census(copy)
    got = derive(mod, after, copy)
  if real_index.exists() and real_index.stat().st_mtime_ns != index_mtime:
    print("PLANT REFUSED: the real index mtime moved")
    return REFUSED
  copy_rows = {r["path"]: r for r in got["rows"]}
  never_row = copy_rows.get(never)
  victim_row = copy_rows.get(victim)
  victim_class = NEVER if not after_log.get(victim) else LOGGED
  checks = [
    ("PLANT never-existed citation is NEVER-IN-HISTORY",
     never_row is not None and never_row["class"] == NEVER
     and any(c.startswith(writer + ":") for c in never_row["citers"])
     and never not in real_missing,
     f"class={None if never_row is None else never_row['class']} "
     f"citers={0 if never_row is None else len(never_row['citers'])} writer={writer}"),
    ("FALSIFY index-deleted blob that git log has is not NEVER-IN-HISTORY",
     victim_class != NEVER and (victim_row is None or victim_row["class"] != NEVER),
     f"git-log={'empty' if victim_class == NEVER else 'non-empty'} "
     f"in-noblob={victim in copy_rows} path={victim}"),
    ("CONTROL an existing file is not in the no-blob list",
     control not in real_missing and control not in copy_rows,
     f"real={control in real_missing} copy={control in copy_rows} path={control}"),
  ]
  for name, ok, detail in checks:
    print(f"  {'OK  ' if ok else 'FAIL'}  {name}")
    print(f"        {detail}")
  bad = [n for n, ok, _d in checks if not ok]
  print(f"  VERDICT {'PASS' if not bad else 'FAIL: ' + '; '.join(bad)}")
  return PASS if not bad else FAIL


def main(argv: list[str] | None = None) -> int:
  ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
  ap.add_argument("--report", action="store_true", help="census only, rc never charged")
  ap.add_argument("--plant", action="store_true", help="the self-test, on a copy")
  args = ap.parse_args(argv)
  mod = load_dangling()
  if mod is None:
    print("REFUSED: gates/oracle-dangling-gate.py did not load census() and recover(); "
          "the 40 were not re-derived by copying the generator", file=sys.stderr)
    return REFUSED
  if not filter_loaded(mod):
    print("REFUSED: census() no longer asks recover() for the ORACLE/EV/SWEPT filter; "
          "the rule was not copied", file=sys.stderr)
    return REFUSED
  try:
    surveyed = mod.census(ROOT)
    got = derive(mod, surveyed, ROOT)
  except Exception as exc:  # noqa: BLE001 -- reported, not hidden
    print(f"REFUSED: the census could not be taken: {type(exc).__name__}: {exc}", file=sys.stderr)
    return REFUSED
  if not surveyed.get("subjects"):
    print("DEAD: census() named no subjects")
    return DEAD
  report(got)
  code, why = check(got)
  print(f"  {why}")
  if args.report:
    print(f"  --report: rc never charged ({VERDICT[code]})")
    return PASS
  if args.plant:
    return plant(mod, surveyed, got)
  return code


if __name__ == "__main__":
  sys.exit(main())
