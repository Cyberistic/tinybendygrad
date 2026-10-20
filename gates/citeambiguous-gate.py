#!/usr/bin/env python3
"""Name every basename the header census left as ``ambiguous:N``.

    .venv/bin/python gates/citeambiguous-gate.py
    .venv/bin/python gates/citeambiguous-gate.py --plant

``gates/header-census-gate.py`` (``02527b5d6``) reported 103 citations
``ambiguous, not guessed`` and discarded the paths. A reader could not tell
whether ``helpers.py`` meant seven files or one. This gate imports that census
(the functions are public; the hyphenated name is loaded by path) and prints
each colliding basename with its candidate count and every candidate path.

THE DENOMINATOR IS THE RE-DERIVED AMBIGUOUS CITATION COUNT. 103 is the recorded
reading to compare against, not the count. A basename with one candidate is
RESOLVES and is not printed. A basename with zero is ABSENT, which the header
census already counts, and is not this population.

NO WINNER. ``prefer_dir`` is applied only where that census applies it. What
remains ambiguous is printed in full. This file does not pick a path.

POPULATION of headers: ``header_census_gate.walk_bend``, which is ``os.walk`` of
``tinybendygrad/`` plus ``endswith(".bend")``. This file does not call ``glob``.
Upstream is the local ref ``refs/remotes/upstream/master``. This file does not fetch.

EXITS are ``gatekit``'s. REFUSED when the census, the port tree, or the upstream
ref is absent, or when the path recovery disagrees with the census -- a
disagreement is not a guess. DEAD when the walk finds no ``.bend`` file. FAIL
while any citation is ambiguous: naming it is the measurement, resolving it is
not this gate. PASS only when the re-derived ambiguous set is empty.
"""
from __future__ import annotations

import collections
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import traceback
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

UPSTREAM_REF = "refs/remotes/upstream/master"
RECORDED_AT = "02527b5d6"
RECORDED_N = 103
SKIP_DIRS = {".git", ".venv", "__pycache__", "node_modules", "references"}
CENSUS_CLASS = {
  "AMBIGUOUS": "AMBIGUOUS",
  "ABSENT-FILE": "ABSENT",
  "RESOLVES": "RESOLVES",
  "DANGLING-LINE": "RESOLVES",
  "UNRESOLVED-BY-SHAPE": "UNRESOLVED",
}


def load_census():
  """The header census, by path. A hyphenated name cannot be an ``import``."""
  path = HERE / "header-census-gate.py"
  if not path.is_file():
    return None
  spec = importlib.util.spec_from_file_location("header_census_gate", path)
  if spec is None or spec.loader is None:
    return None
  mod = importlib.util.module_from_spec(spec)
  sys.modules["header_census_gate"] = mod
  spec.loader.exec_module(mod)
  needed = ("walk_bend", "header_block", "declared_target", "citation_claims",
            "resolve_citation", "Upstream", "Port", "UPSTREAM", "PORT_REL",
            "SUBJECT_PORT", "SUBJECT_NONE", "git_exists")
  if any(not hasattr(mod, name) for name in needed):
    return None
  return mod


def classify_hits(hits, prefer_dir=""):
  """``(verdict, candidates)`` for one index probe.

  Zero hits is ABSENT, not ambiguous. One hit is RESOLVES. Two or more are
  AMBIGUOUS and every path is returned, sorted for stable output, not by
  likelihood. ``prefer_dir`` is the census's own tie-break: a unique hit in
  that directory is RESOLVES, which is that census resolving, not this gate
  choosing. Anything still plural is not chosen among.
  """
  if not hits:
    return "ABSENT", []
  chosen = list(hits)
  if len(chosen) > 1 and prefer_dir:
    near = [h for h in chosen if h.rsplit("/", 1)[0] == prefer_dir]
    if len(near) == 1:
      return "RESOLVES", near
    if near:
      chosen = near
  if len(chosen) == 1:
    return "RESOLVES", list(chosen)
  return "AMBIGUOUS", sorted(chosen)


def classify_basename(subject, index, prefer_dir=""):
  """A cited basename against a ``{basename: [paths]}`` index discovered by walk."""
  return classify_hits(index.get(subject, []), prefer_dir)


def py_index(root):
  """``.py`` basenames under ``root``. ``os.walk``, never ``glob``."""
  found = collections.defaultdict(list)
  for dp, dn, fn in os.walk(root):
    dn[:] = [d for d in dn if d not in SKIP_DIRS]
    for name in sorted(fn):
      if name.endswith(".py"):
        found[name].append(str((Path(dp) / name).relative_to(root)))
  return found


def recover_port(hc, port, subject, prefer_dir):
  """``Port.resolve``, hits kept. Suffix ambiguity is returned before ``prefer_dir``.

  That order is the census's. Applying ``prefer_dir`` to a suffix collision
  would pick the file in the header's own directory, which is the winner this
  gate exists not to pick. ``ip.bend`` is that case.
  """
  if subject in port.paths:
    return "RESOLVES", [subject], "exact"
  rel = subject if subject.startswith(hc.PORT_REL + "/") else f"{hc.PORT_REL}/{subject}"
  if rel in port.paths:
    return "RESOLVES", [rel], "port-relative"
  hits = list(port.suffix.get("/" + subject, []))
  if len(hits) == 1:
    return "RESOLVES", hits, "suffix"
  if len(hits) > 1:
    return "AMBIGUOUS", sorted(hits), "suffix"
  verdict, kept = classify_basename(subject, port.base_name, prefer_dir)
  return verdict, kept, "basename"


def recover_upstream(hc, up, subject, prefer_dir):
  """``Upstream.resolve`` with ``history=False``, which is what a citation uses."""
  if subject.startswith("tinygrad/"):
    if hc.git_exists(f"{up.rev}:{subject}"):
      return "RESOLVES", [subject], "exact"
    return "ABSENT", [], "absent"
  verdict, kept = classify_basename(subject, up.files(), prefer_dir)
  if verdict != "ABSENT":
    return verdict, kept, "basename"
  verdict, kept = classify_hits(up.suffixes().get("/" + subject, []), prefer_dir)
  if verdict != "ABSENT":
    return verdict, kept, "suffix"
  return "ABSENT", [], "absent"


def recover(hc, up, port, claim):
  if claim["kind"] == hc.SUBJECT_NONE or not claim["subject"]:
    return "UNRESOLVED", [], "shape"
  if claim["kind"] == hc.SUBJECT_PORT:
    return recover_port(hc, port, claim["subject"], claim.get("prefer_port_dir", ""))
  return recover_upstream(hc, up, claim["subject"], claim.get("prefer_dir", ""))


def direct_how(hc, up, port, claim):
  """The census's own ``how`` string, so ``ambiguous:N`` is its number, not ours."""
  if claim["kind"] == hc.SUBJECT_PORT:
    _path, how = port.resolve(claim["subject"], prefer_dir=claim.get("prefer_port_dir", ""))
    return how
  _path, how = up.resolve(claim["subject"], prefer_dir=claim.get("prefer_dir", ""))
  return how


def collect(hc, up, port):
  """Every header citation, classed by the census, with candidates recovered.

  Returns ``(rows, disagreements)``. A disagreement means the recovery does not
  match the census, and the caller must not print those paths as fact.
  """
  rows = []
  bad = []
  for path in hc.walk_bend(hc.ROOT / hc.PORT_REL):
    rel = str(path.relative_to(hc.ROOT))
    body = path.read_text(encoding="utf-8", errors="replace").splitlines()
    first, _last, block = hc.header_block(body)
    target = hc.declared_target(block)
    up_dir = target.rsplit("/", 1)[0] if "/" in target else ""
    port_dir = rel.rsplit("/", 1)[0] if "/" in rel else ""
    for claim in hc.citation_claims(block, first, rel, target):
      claim["prefer_dir"] = up_dir
      claim["prefer_port_dir"] = port_dir
      verdict, _why = hc.resolve_citation(claim, up, port)
      mine, hits, how = recover(hc, up, port, claim)
      expect = CENSUS_CLASS.get(verdict)
      if expect != mine:
        bad.append(f"{rel}:{claim['at']} census={verdict} recovered={mine} "
                   f"subject={claim['subject']!r}")
        continue
      if verdict == "AMBIGUOUS":
        how_c = direct_how(hc, up, port, claim)
        n = int(how_c.removeprefix("ambiguous:")) if how_c.startswith("ambiguous:") else None
        if n != len(hits) or len(hits) < 2:
          bad.append(f"{rel}:{claim['at']} census {how_c} but recovered {len(hits)} paths "
                     f"for {claim['subject']!r}")
          continue
      rows.append({
        "rel": rel, "at": claim["at"], "subject": claim["subject"],
        "kind": claim["kind"], "verdict": verdict, "hits": hits, "how": how,
      })
  return rows, bad


def groups_of(rows):
  """Ambiguous citations grouped by the subject the header wrote and its candidates."""
  grouped = collections.defaultdict(list)
  for row in rows:
    if row["verdict"] != "AMBIGUOUS":
      continue
    key = (row["subject"], tuple(row["hits"]), row["kind"], row["how"])
    grouped[key].append((row["rel"], row["at"]))
  return grouped


def ambiguous_subjects(index, subjects):
  """Subjects whose basename has two or more candidates. ABSENT is not included."""
  out = []
  for subject in subjects:
    verdict, hits = classify_basename(subject, index)
    if verdict == "AMBIGUOUS":
      out.append((subject, hits))
  return out


def write_copy(root, files):
  for rel, data in files.items():
    dest = root / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)


def plant():
  """Four copies, and a deletion that must move the verdict.

  Two ``helpers.py`` in different directories are AMBIGUOUS. One is RESOLVES.
  Zero is ABSENT, and that cite is not counted as ambiguous. A byte-identical
  copy of the one-file tree is the unbroken control: ``unique_control.py`` stays
  RESOLVES. Deleting one of the two must move AMBIGUOUS to RESOLVES; a classifier
  that does not re-walk stays AMBIGUOUS and the plant fails.
  """
  try:
    return _plant()
  except Exception:
    print("citeambiguous PLANT FAILED: a crash is not a pass", file=sys.stderr)
    traceback.print_exc()
    return FAIL


def _plant():
  subjects = ("helpers.py", "unique_control.py", "no_such_citeambiguous.py")
  unique = b"unique-control\n"
  files_two = {
    "a/helpers.py": b"copy-a\n",
    "b/helpers.py": b"copy-b\n",
    "c/unique_control.py": unique,
  }
  files_one = {"a/helpers.py": b"copy-a\n", "c/unique_control.py": unique}
  bad = []
  with tempfile.TemporaryDirectory(prefix="citeambiguous-plant-") as raw:
    td = Path(raw)
    two, one, zero, control = td / "two", td / "one", td / "zero", td / "control"
    write_copy(two, files_two)
    write_copy(one, files_one)
    write_copy(zero, {"c/unique_control.py": unique})
    shutil.copytree(one, control)
    if (control / "c/unique_control.py").read_bytes() != (one / "c/unique_control.py").read_bytes():
      print("citeambiguous PLANT FAILED: the unbroken control is not a byte copy", file=sys.stderr)
      return FAIL
    idx = {name: py_index(tree) for name, tree in
           (("two", two), ("one", one), ("zero", zero), ("control", control))}
    judged = {name: {s: classify_basename(s, index) for s in subjects} for name, index in idx.items()}
    amb = {name: ambiguous_subjects(index, subjects) for name, index in idx.items()}

    def expect(tree, subject, verdict, n):
      got, hits = judged[tree][subject]
      if got != verdict or len(hits) != n:
        bad.append(f"{tree} {subject}: {got} x{len(hits)}, wanted {verdict} x{n}")
      return hits

    hits = expect("two", "helpers.py", "AMBIGUOUS", 2)
    if hits and len({p.rsplit('/', 1)[0] for p in hits}) != 2:
      bad.append(f"two helpers.py candidates are not in different directories: {hits}")
    if hits and set(hits) != {"a/helpers.py", "b/helpers.py"}:
      bad.append(f"two helpers.py candidates are not the copies written: {hits}")
    expect("two", "unique_control.py", "RESOLVES", 1)
    expect("two", "no_such_citeambiguous.py", "ABSENT", 0)
    if len(amb["two"]) != 1 or amb["two"][0][0] != "helpers.py":
      bad.append(f"two-file ambiguous count is not exactly the helpers.py cite: {amb['two']}")
    expect("one", "helpers.py", "RESOLVES", 1)
    expect("one", "unique_control.py", "RESOLVES", 1)
    if amb["one"]:
      bad.append(f"one candidate was counted ambiguous: {amb['one']}")
    expect("zero", "helpers.py", "ABSENT", 0)
    expect("zero", "unique_control.py", "RESOLVES", 1)
    if amb["zero"]:
      bad.append(f"ABSENT was counted ambiguous: {amb['zero']}")
    expect("control", "unique_control.py", "RESOLVES", 1)
    expect("control", "helpers.py", "RESOLVES", 1)
    if judged["control"]["unique_control.py"] != judged["one"]["unique_control.py"]:
      bad.append("unbroken control moved")

    falsify = td / "falsify"
    shutil.copytree(two, falsify)
    (falsify / "b/helpers.py").unlink()
    before = judged["two"]["helpers.py"][0]
    after, after_hits = classify_basename("helpers.py", py_index(falsify))
    print(f"citeambiguous PLANT FALSIFY helpers.py {before} -> {after} "
          f"candidates={after_hits}")
    if before != "AMBIGUOUS" or after != "RESOLVES" or after_hits != ["a/helpers.py"]:
      bad.append(f"deleting one copy did not move AMBIGUOUS to RESOLVES: {before} -> {after} {after_hits}")

    for name in ("two", "one", "zero", "control"):
      for subject in subjects:
        verdict, found = judged[name][subject]
        print(f"citeambiguous PLANT {name} {subject} {verdict} candidates={len(found)}"
              + (f" {found}" if found else ""))
    print(f"citeambiguous PLANT ambiguous-counts two={len(amb['two'])} one={len(amb['one'])} "
          f"zero={len(amb['zero'])} control={len(amb['control'])}")
  if bad:
    print("citeambiguous PLANT FAILED: " + "; ".join(bad), file=sys.stderr)
    return FAIL
  print("citeambiguous PLANT OK: two copies are AMBIGUOUS, one RESOLVES, zero is ABSENT "
        "and not counted, the byte copy stays RESOLVES, deleting one copy moves the verdict")
  return PASS


def git_sha(ref):
  proc = subprocess.run(["git", "rev-parse", "--verify", ref], cwd=ROOT,
                        capture_output=True, text=True)
  return proc.stdout.strip() if proc.returncode == 0 else ""


def emit(rows, bend_n):
  grouped = groups_of(rows)
  ambiguous = [r for r in rows if r["verdict"] == "AMBIGUOUS"]
  basenames = {r["subject"].rsplit("/", 1)[-1] for r in ambiguous}
  counts = collections.Counter(r["verdict"] for r in rows)
  now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
  head = git_sha("HEAD")
  up_sha = git_sha(UPSTREAM_REF)
  n = len(ambiguous)
  print(f"citeambiguous WHEN {now}")
  print(f"citeambiguous CMD {Path(sys.argv[0]).name} {' '.join(sys.argv[1:])}".rstrip())
  print(f"citeambiguous HEAD {head[:12]}")
  print(f"citeambiguous UPSTREAM {UPSTREAM_REF} {up_sha[:12]} local-ref not-fetched")
  print(f"citeambiguous POPULATION os.walk tinybendygrad/ endswith .bend = {bend_n}")
  print("citeambiguous IMPORT header-census-gate.py by path; functions are public. "
        "Candidate paths are recovered from its indexes because resolve returns "
        "ambiguous:N and drops the paths. No path is selected.")
  print(f"citeambiguous CENSUS ambiguous={counts['AMBIGUOUS']} absent={counts['ABSENT-FILE']} "
        f"resolves={counts['RESOLVES']} dangling={counts['DANGLING-LINE']} "
        f"unresolved={counts['UNRESOLVED-BY-SHAPE']}")
  print(f"citeambiguous DENOMINATOR ambiguous-citations={n} distinct-basenames={len(basenames)}")
  if n == RECORDED_N:
    print(f"citeambiguous RECORDED {RECORDED_AT} was {RECORDED_N}. UNMOVED.")
  else:
    print(f"citeambiguous RECORDED {RECORDED_AT} was {RECORDED_N}. MOVED {RECORDED_N}->{n}.")
  print("citeambiguous EXCLUDED one-candidate is RESOLVES and is not printed; "
        f"zero-candidate is ABSENT ({counts['ABSENT-FILE']}) and is not this population")
  print("citeambiguous CITED-BY xN is several citations on one line, not a duplicated row")
  ordered = sorted(grouped.items(),
                   key=lambda kv: (-len(kv[0][1]), -len(kv[1]), kv[0][0], kv[0][2]))
  for (subject, hits, kind, how), cites in ordered:
    base = subject.rsplit("/", 1)[-1]
    label = "BASENAME" if base == subject else "SUBJECT"
    print(f"citeambiguous {label} {subject} candidates={len(hits)} citations={len(cites)} "
          f"where={kind} how={how}")
    for hit in hits:
      print(f"citeambiguous   {hit}")
    for (rel, at), mult in sorted(collections.Counter(cites).items()):
      extra = f" x{mult}" if mult > 1 else ""
      print(f"citeambiguous   cited-by {rel}:{at}{extra}")
  if sum(len(cites) for _key, cites in ordered) != n:
    return None
  if any(len(hits) < 2 for (_s, hits, _k, _h), _c in ordered):
    return None
  return n


def main(argv):
  if "--plant" in argv:
    return plant()
  hc = load_census()
  if hc is None:
    print("citeambiguous REFUSED: header-census-gate.py is absent or its functions moved",
          file=sys.stderr)
    return REFUSED
  if hc.UPSTREAM != UPSTREAM_REF:
    print(f"citeambiguous REFUSED: census upstream is {hc.UPSTREAM!r}, not {UPSTREAM_REF}",
          file=sys.stderr)
    return REFUSED
  port_root = hc.ROOT / hc.PORT_REL
  if not port_root.is_dir():
    print(f"citeambiguous REFUSED: port tree {port_root} is absent", file=sys.stderr)
    return REFUSED
  if not git_sha(UPSTREAM_REF):
    print(f"citeambiguous REFUSED: {UPSTREAM_REF} is absent. This file does not fetch.",
          file=sys.stderr)
    return REFUSED
  bend = hc.walk_bend(port_root)
  if not bend:
    print("citeambiguous DEAD: the port walk found no .bend file", file=sys.stderr)
    return DEAD
  up = hc.Upstream(UPSTREAM_REF)
  port = hc.Port(hc.ROOT, port_root)
  rows, bad = collect(hc, up, port)
  if bad:
    print("citeambiguous REFUSED: path recovery disagrees with the census; "
          "not printing a guessed set", file=sys.stderr)
    for line in bad[:20]:
      print(f"citeambiguous   {line}", file=sys.stderr)
    return REFUSED
  if not rows:
    print("citeambiguous DEAD: citations were extracted and none were classed", file=sys.stderr)
    return DEAD
  n = emit(rows, len(bend))
  if n is None:
    print("citeambiguous REFUSED: the printed groups do not add up to the denominator",
          file=sys.stderr)
    return REFUSED
  code = FAIL if n else PASS
  why = (f"{n} ambiguous citations, named, not guessed" if n
         else "no ambiguous citation")
  print(f"citeambiguous VERDICT {VERDICT[code]} -- {why}")
  return code


if __name__ == "__main__":
  sys.exit(main(sys.argv[1:]))
