#!/usr/bin/env python3
"""Classify each GONE ledger path: tombstone, or a rename the ledger cannot see.

The population is ``ledgerdue.movement()["gone"]``, loaded by path from
``gates/ledgerdue-gate.py``. The five paths named when this file was written are a
comparison. If the set has moved, the new set is printed and classified. Nothing here
is dropped to keep the five.

History is ``git log --all --name-only -- <path>``. Never ``git rev-list --all``.
A successor is a living path named by an ``R`` record, or a living file with the
same basename and a different suffix. ``name.py.m.out`` is a captured stream, not
that rename.

A file pathspec hides the other side of a rename, so ``git log -M --diff-filter=R
-- <path>`` and ``--follow`` on the gone path do not name a forward successor
(measured: both print ``D``, while ``git show -M`` of that same commit prints
``R100``). The ``R`` ask is ``git log -1 -M --diff-filter=R`` of each commit the
path log already named, with no pathspec. ``--follow`` is still asked.

This gate does not write the ledger, does not retire a row, and does not delete a
``.m.out``.

    .venv/bin/python gates/ledgergone-gate.py
    .venv/bin/python gates/ledgergone-gate.py --plant
"""
import argparse
import importlib.util
import inspect
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
LEDGER = HERE / "gates-pop.ledger.tsv"
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

# A recorded reading. Not the population: ``movement()["gone"]`` is.
RECORDED = (
  "gates/.wgsl-mut-oracle.py",
  "gates/amd-mut-gate.py",
  "gates/amd-mut-oracle.py",
  "gates/cstyle-mut-oracle.py",
  "gates/realize-mut-oracle.py",
)
NEVER = "NEVER-COMMITTED"
NO_SUCCESSOR = "GONE-NO-SUCCESSOR"
RENAME = "RENAME-LEDGER-CANNOT-SEE"
TOMBSTONE = "TOMBSTONE"
SKIP_WALK = {".git", "__pycache__"}


def load_due():
  """``gates/ledgerdue-gate.py`` by path. The hyphen is why ``import`` cannot name it."""
  path = HERE / "ledgerdue-gate.py"
  if not path.is_file():
    return None
  spec = importlib.util.spec_from_file_location("ledgerdue_gate_gone", path)
  if spec is None or spec.loader is None:
    return None
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  if not callable(getattr(mod, "load_pop", None)) or not callable(getattr(mod, "movement", None)):
    return None
  if not callable(getattr(mod, "rows_of", None)):
    return None
  return mod


def git(args, cwd, env=None):
  """``git -C cwd``. ``GIT_INDEX_FILE`` is dropped unless the caller passes one.

  A plant's ``git commit`` must not inherit a private index pointed at the real
  repository. History asks do not use the index; dropping it is what keeps a
  throwaway commit inside the throwaway.
  """
  run_env = os.environ.copy()
  run_env.pop("GIT_INDEX_FILE", None)
  if env:
    run_env.update(env)
  try:
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True,
                          env=run_env, timeout=120)
  except subprocess.TimeoutExpired:
    return subprocess.CompletedProcess(args, 1, "", "TIMED-OUT")


def gone_of(due, pop, root, ledger):
  """The live GONE set. Re-derived. Not ``RECORDED``."""
  diff = due.movement(pop, due.rows_of(pop, root), ledger)
  if diff.get("no_ledger"):
    return None
  return diff["gone"]


def touches(path, cwd):
  """Commits that touch ``path``, newest first, from ``git log --all --name-only -- <path>``.

  ``None`` is an unanswered log. An empty list is an empty history. A quoted path is
  unanswered: parsing it would be a guess.
  """
  r = git(["log", "--all", "--format=%x01%H%x09%ci%x09%s", "--name-only", "--", path], cwd)
  if r.returncode != 0:
    return None
  out, seen, meta = [], set(), None
  for line in r.stdout.splitlines():
    if line.startswith("\x01"):
      body = line[1:]
      sha, _, rest = body.partition("\t")
      when, _, subject = rest.partition("\t")
      meta = (sha, when, subject)
      continue
    if not line or meta is None:
      continue
    if line[:1] in "\"'":
      return None
    if line == path and meta[0] not in seen:
      seen.add(meta[0])
      out.append(meta)
  return out


def contains(path, sha, cwd):
  return git(["cat-file", "-e", f"{sha}:{path}"], cwd).returncode == 0


def last_had(path, touched, cwd):
  """The newest commit whose tree contains ``path``, or None if none does."""
  for sha, when, subject in touched:
    if contains(path, sha, cwd):
      return sha, when, subject
  if not touched:
    return None
  parent = git(["rev-parse", "--verify", f"{touched[0][0]}^"], cwd)
  if parent.returncode != 0:
    return None
  sha = parent.stdout.strip()
  if not contains(path, sha, cwd):
    return None
  shown = git(["log", "-1", "--format=%ci%x09%s", sha], cwd)
  when, _, subject = shown.stdout.strip().partition("\t")
  return sha, when, subject


def deletions(path, cwd):
  """Deletion commits, or None if the ask did not answer. Empty is 'never deleted'."""
  r = git(["log", "--all", "--diff-filter=D", "--format=%H", "--", path], cwd)
  if r.returncode != 0:
    return None
  return [ln.strip() for ln in r.stdout.splitlines() if ln.strip()]


def _rename_ask(args, path, cwd):
  """Destinations of ``R`` records whose source is ``path``. None if the ask is unreadable."""
  r = git(args, cwd)
  if r.returncode != 0:
    return None
  dests = set()
  for line in r.stdout.splitlines():
    if not line or line.startswith("\x01"):
      continue
    if line[:1] in "\"'":
      return None
    parts = line.split("\t")
    if len(parts) == 3 and len(parts[0]) > 1 and parts[0][0] == "R" and parts[0][1].isdigit():
      if parts[1] == path and parts[2] != path:
        dests.add(parts[2])
      continue
    status = parts[0] if parts else ""
    if status[:1] in "AMDRCTUXB":
      continue
    return None
  return dests


def rename_destinations(path, touched, cwd):
  """Destinations of ``R`` records whose source is ``path``.

  ``--follow`` walks backward, and a file pathspec hides the destination, so neither
  by-path ask names a forward rename. Each commit the path log named is therefore
  asked again with ``git log -1 -M --diff-filter=R`` and no pathspec. A predecessor
  renamed onto this path is not a successor: the source field has to be ``path``.
  """
  found = {}
  by_path = ["log", "--all", "-M", "--diff-filter=R", "--name-status", "--format=%x01%H", "--", path]
  asks = [("pathspec-R", by_path), ("follow", by_path[:3] + ["--follow"] + by_path[3:])]
  asks += [("R", ["log", "-1", "-M", "--diff-filter=R", "--name-status", "--format=%x01%H", sha])
           for sha, _when, _subject in touched]
  for via, args in asks:
    dests = _rename_ask(args, path, cwd)
    if dests is None:
      return None
    for dest in dests:
      found.setdefault(dest, set()).add(via)
  return found


def stream_not_program(candidate, gone):
  """``gone + '.m.out'`` is a captured stream. So is any other ``.m.out``. Not the program."""
  return candidate == gone + ".m.out" or candidate.endswith(".m.out")


def stem_hits(path, names):
  """Same basename, different suffix, among ``names``. A stream is not a hit."""
  stem, suffix = Path(path).stem, Path(path).suffix
  if not suffix:
    return []
  hits = []
  for name in names:
    other = Path(name)
    if other.stem != stem or other.suffix == suffix or name == path:
      continue
    if stream_not_program(name, path):
      continue
    hits.append(name)
  return hits


def head_index(cwd):
  """``path -> blob`` and the name list, from one ``ls-tree`` of HEAD. Not ``rev-list``."""
  return head_index_of("HEAD", cwd)


def disk_names(root, rel_dir):
  """Filenames under ``rel_dir``, relative to ``root``. ``os.walk``, not ``glob``."""
  base = Path(root) / rel_dir if rel_dir else Path(root)
  if not base.is_dir():
    return []
  out = []
  for dirpath, dirnames, filenames in os.walk(base):
    dirnames[:] = [d for d in dirnames if d not in SKIP_WALK]
    rel = Path(dirpath).relative_to(root)
    for fn in filenames:
      out.append((rel / fn).as_posix())
  return out


def names_for(paths, root):
  """Committed names (whole HEAD) plus on-disk names in each gone path's parent."""
  head = head_index(root)
  if head is None:
    return None
  blobs, committed = head
  disk = []
  seen = set()
  for path in paths:
    parent = path.rsplit("/", 1)[0] if "/" in path else ""
    if parent in seen:
      continue
    seen.add(parent)
    disk.extend(disk_names(root, parent))
  return blobs, set(committed) | set(disk)


def same_blob_in(path, sha, cwd):
  """Other paths in ``sha`` carrying ``path``'s blob. One ``ls-tree``, not ``rev-list``."""
  listed = head_index_of(sha, cwd)
  if listed is None:
    return None
  blobs, _names = listed
  blob = blobs.get(path)
  if blob is None:
    return []
  return [other for other, other_blob in blobs.items()
          if other != path and other_blob == blob and not stream_not_program(other, path)]


def head_index_of(sha, cwd):
  """``path -> blob`` from ``git ls-tree -r <sha>``. Not ``rev-list``."""
  r = git(["ls-tree", "-r", sha], cwd)
  if r.returncode != 0:
    return None
  blobs, names = {}, []
  for line in r.stdout.splitlines():
    meta, tab, rel = line.partition("\t")
    if not tab:
      continue
    fields = meta.split()
    if len(fields) < 3:
      continue
    blobs[rel] = fields[2]
    names.append(rel)
  return blobs, names


def copy_notes(path, sha, cwd, blobs):
  """A different living path with the same blob. A copy, unless a successor rule names it.

  Co-presence in ``sha`` is the distinction: both paths in the commit that last had
  ``path`` means the other file was not a rename target of this one.
  """
  if sha is None:
    return []
  got = git(["rev-parse", f"{sha}:{path}"], cwd)
  if got.returncode != 0:
    return []
  blob = got.stdout.strip()
  notes = []
  for other, other_blob in blobs.items():
    if other == path or other_blob != blob or stream_not_program(other, path):
      continue
    notes.append((other, contains(other, sha, cwd)))
  return notes


def classify(path, root, blobs, names):
  """One gone path. None if an ask did not answer — that is not an empty history."""
  touched = touches(path, root)
  if touched is None:
    return None
  deleted = deletions(path, root)
  renamed = rename_destinations(path, touched, root)
  if deleted is None or renamed is None:
    return None
  last = last_had(path, touched, root)
  if touched and last is None:
    return None
  living, historical = {}, []
  for dest, vias in renamed.items():
    if dest in names and not stream_not_program(dest, path):
      living.setdefault(dest, set()).update(vias)
    else:
      historical.append(dest)
  for dest in stem_hits(path, names):
    living.setdefault(dest, set()).add("stem")
  if living:
    klass, disposition = RENAME, RENAME
  else:
    klass, disposition = NO_SUCCESSOR, TOMBSTONE
  last_copies = [] if last is None else same_blob_in(path, last[0], root)
  if last_copies is None:
    return None
  ancestor = None
  name_rev = ""
  if last is not None:
    anc = git(["merge-base", "--is-ancestor", last[0], "HEAD"], root)
    if anc.returncode == 0:
      ancestor = True
    elif anc.returncode == 1:
      ancestor = False
    name_rev = git(["name-rev", "--name-only", last[0]], root).stdout.strip()
  return {
    "path": path,
    "history": NEVER if last is None else last[0],
    "when": "" if last is None else last[1],
    "subject": "" if last is None else last[2],
    "ancestor": ancestor,
    "name_rev": name_rev,
    "deleted": deleted,
    "successors": {k: sorted(v) for k, v in sorted(living.items())},
    "historical": historical,
    "copies": copy_notes(path, None if last is None else last[0], root, blobs),
    "last_copies": last_copies,
    "stream": path + ".m.out" if (path + ".m.out") in names else "",
    "on_disk": (Path(root) / path).exists(),
    "klass": klass,
    "disposition": disposition,
  }


def _succ_text(row):
  if not row["successors"]:
    return "none"
  return " ".join(f"{dest} via {','.join(vias)}" for dest, vias in row["successors"].items())


def print_row(row, removal):
  print(f"ledgergone PATH {row['path']}")
  if row["history"] == NEVER:
    print(f"ledgergone   HISTORY {NEVER}")
  else:
    subject = row["subject"] or "(no subject)"
    print(f"ledgergone   HISTORY LAST {row['history']} {row['when']} {subject}")
  if row["ancestor"] is None:
    print("ledgergone   ANCESTOR unanswered")
  else:
    print(f"ledgergone   ANCESTOR {'yes' if row['ancestor'] else 'no'} name-rev={row['name_rev'] or '-'}")
  print(f"ledgergone   DELETED {'none' if not row['deleted'] else row['deleted'][0]}")
  print(f"ledgergone   EVENTS-REMOVAL {removal or 'NO-OWNER'}")
  print(f"ledgergone   SUCCESSOR {_succ_text(row)}")
  if row["historical"]:
    print("ledgergone   HISTORICAL-R " + " ".join(row["historical"]))
  if not row["copies"]:
    print("ledgergone   COPY-NOT-RENAME none")
  for other, co in row["copies"]:
    print(f"ledgergone   COPY-NOT-RENAME {other} co-present={'yes' if co else 'no'}")
  last_copies = row["last_copies"]
  print("ledgergone   SAME-BLOB-IN-LAST " + ("none" if not last_copies else " ".join(last_copies)))
  if row["stream"]:
    print(f"ledgergone   STREAM-NOT-SUCCESSOR {row['stream']}")
  print(f"ledgergone   ON-DISK {'yes' if row['on_disk'] else 'no'}")
  print(f"ledgergone   CLASS {row['klass']}")
  print(f"ledgergone   DISPOSITION {row['disposition']}")


def run(due, pop):
  now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
  print(f"ledgergone WHEN {now}")
  print(f"ledgergone CMD {Path(sys.argv[0]).name} {' '.join(sys.argv[1:])}".rstrip())
  print("ledgergone ASK git log --all --name-only -- <path>")
  print("ledgergone ASK git log --all -M --diff-filter=R --name-status -- <path>")
  print("ledgergone ASK git log --all -M --follow --diff-filter=R --name-status -- <path>")
  print("ledgergone ASK git log -1 -M --diff-filter=R --name-status <commit-from-that-log>")
  if not LEDGER.is_file():
    print(f"ledgergone REFUSED: no ledger at {LEDGER.name}")
    return REFUSED
  head = git(["rev-parse", "--short=9", "HEAD"], ROOT)
  print(f"ledgergone HEAD {head.stdout.strip() if head.returncode == 0 else 'NO-HEAD'}")
  blob = git(["hash-object", str(LEDGER)], ROOT)
  committed = git(["rev-parse", f"HEAD:{LEDGER.relative_to(ROOT)}"], ROOT)
  print(f"ledgergone LEDGER git-blob={blob.stdout.strip()} "
        f"HEAD:={committed.stdout.strip()} write=not-a-mode")
  print("ledgergone DENOMINATOR movement()[gone] re-derived from gates/ledgerdue-gate.py by path")
  gone = gone_of(due, pop, ROOT, LEDGER)
  if gone is None:
    print("ledgergone DEAD: ledger read returned nothing — compared nothing")
    return DEAD
  recorded = set(RECORDED)
  derived = set(gone)
  print(f"ledgergone RECORDED {len(recorded)} (comparison, not the population)")
  print(f"ledgergone DERIVED {len(derived)}")
  if derived == recorded:
    print("ledgergone UNMOVED")
  else:
    print("ledgergone MOVED — the new set follows; no path was dropped to keep the recorded five")
    for path in sorted(derived):
      print(f"ledgergone NEW-SET {path}")
    for path in sorted(recorded - derived):
      print(f"ledgergone LEFT-RECORDED {path}")
    for path in sorted(derived - recorded):
      print(f"ledgergone ENTERED {path}")
  if not gone:
    print("ledgergone GONE 0")
    print(f"ledgergone VERDICT {VERDICT[PASS]}")
    return PASS
  indexed = names_for(gone, ROOT)
  if indexed is None:
    print("ledgergone REFUSED: git ls-tree HEAD did not answer")
    return REFUSED
  blobs, names = indexed
  sees_all = "--all" in inspect.getsource(pop.events)
  print(f"ledgergone EVENTS-SOURCE --all={'yes' if sees_all else 'no'}")
  events = pop.events(ROOT, pop._homes(ROOT))
  print(f"ledgergone EVENTS {len(events)} path(s) attributed by ledgerdue's loader")
  rows = []
  for path in gone:
    row = classify(path, ROOT, blobs, names)
    if row is None:
      print(f"ledgergone REFUSED: git log --all -- {path} did not answer")
      return REFUSED
    removal = events.get(path, (None, None))[1]
    print_row(row, removal)
    rows.append(row)
  renames = [r["path"] for r in rows if r["klass"] == RENAME]
  on_disk = [r["path"] for r in rows if r["on_disk"]]
  print(f"ledgergone {RENAME} {len(renames)}")
  print(f"ledgergone {NO_SUCCESSOR} {sum(r['klass'] == NO_SUCCESSOR for r in rows)}")
  print(f"ledgergone {TOMBSTONE} {sum(r['disposition'] == TOMBSTONE for r in rows)}")
  code = FAIL if renames or on_disk else PASS
  if renames:
    print("ledgergone FINDING a rename the ledger calls GONE: " + " ".join(renames))
  if on_disk:
    print("ledgergone FINDING an existing path is in the gone list: " + " ".join(on_disk))
  print(f"ledgergone VERDICT {VERDICT[code]}")
  return code


def _plant_commit(root, paths, msg):
  added = git(["add", "--", *paths], root)
  if added.returncode != 0:
    return added
  return git(["-c", "user.email=plant@example", "-c", "user.name=plant", "commit", "-qm", msg], root)


def _init(root):
  (root / "gates").mkdir(parents=True)
  return git(["init", "-q"], root)


def _classifier_plants():
  """Three classifier claims, each on its own throwaway repository. Not this tree."""
  checks = []
  with tempfile.TemporaryDirectory(prefix="ledgergone-plant.") as tmp:
    base = Path(tmp)

    deleted = base / "deleted"
    setup = _init(deleted)
    victim = "gates/deleted-nosucc.py"
    (deleted / victim).write_text("print('deleted')\n")
    c1 = _plant_commit(deleted, [victim], "add")
    rm = git(["rm", "--", victim], deleted)
    c2 = git(["-c", "user.email=plant@example", "-c", "user.name=plant", "commit", "-qm", "drop"],
             deleted)
    indexed = names_for([victim], deleted) if c2.returncode == 0 else None
    row = classify(victim, deleted, *indexed) if indexed else None
    ok = (setup.returncode == 0 and c1.returncode == 0 and rm.returncode == 0
          and c2.returncode == 0 and row is not None
          and row["klass"] == NO_SUCCESSOR and row["disposition"] == TOMBSTONE
          and not row["successors"] and row["deleted"] and row["history"] != NEVER
          and not row["on_disk"])
    checks.append(("PLANT a path deleted with no successor is GONE-NO-SUCCESSOR", ok,
                   f"class={None if row is None else row['klass']} "
                   f"deleted={None if row is None else bool(row['deleted'])}"))

    streamed = base / "stream"
    _init(streamed)
    program = "gates/streamed.py"
    mout = program + ".m.out"
    (streamed / program).write_text("print('program')\n")
    (streamed / mout).write_text("captured stream\n")
    s1 = _plant_commit(streamed, [program, mout], "add")
    srm = git(["rm", "--", program], streamed)
    s2 = git(["-c", "user.email=plant@example", "-c", "user.name=plant", "commit", "-qm", "drop"],
             streamed)
    indexed = names_for([program], streamed) if s2.returncode == 0 else None
    row = classify(program, streamed, *indexed) if indexed else None
    named = [] if row is None else list(row["successors"])
    ok = (s1.returncode == 0 and srm.returncode == 0 and s2.returncode == 0 and row is not None
          and mout not in named and row["klass"] == NO_SUCCESSOR
          and (streamed / mout).is_file() and not (streamed / program).exists())
    checks.append(("FALSIFY name.py.m.out is not a rename of the program", ok,
                   f"class={None if row is None else row['klass']} successors={named} mout={mout}"))

    renamed = base / "renamed"
    _init(renamed)
    old, new = "gates/renamed.py", "gates/renamed.bend"
    (renamed / old).write_text("print('renamed')\n")
    r1 = _plant_commit(renamed, [old], "add")
    mv = git(["mv", old, new], renamed)
    r2 = git(["-c", "user.email=plant@example", "-c", "user.name=plant", "commit", "-qm", "mv"],
             renamed)
    indexed = names_for([old], renamed) if r2.returncode == 0 else None
    row = classify(old, renamed, *indexed) if indexed else None
    vias = {} if row is None else row["successors"].get(new, [])
    ok = (r1.returncode == 0 and mv.returncode == 0 and r2.returncode == 0 and row is not None
          and row["klass"] == RENAME and "R" in vias and "stem" in vias
          and (renamed / new).is_file() and not (renamed / old).exists())
    checks.append(("FALSIFY a rename to the same stem and a different suffix is seen", ok,
                   f"class={None if row is None else row['klass']} vias={vias}"))

    copied = base / "copied"
    _init(copied)
    kept, copy = "gates/kept.py", "gates/copied.py"
    body = "print('same')\n"
    (copied / kept).write_text(body)
    (copied / copy).write_text(body)
    k1 = _plant_commit(copied, [kept, copy], "add")
    krm = git(["rm", "--", copy], copied)
    k2 = git(["-c", "user.email=plant@example", "-c", "user.name=plant", "commit", "-qm", "drop"],
             copied)
    indexed = names_for([copy], copied) if k2.returncode == 0 else None
    row = classify(copy, copied, *indexed) if indexed else None
    named = [] if row is None else list(row["successors"])
    copies = [] if row is None else [other for other, _co in row["copies"]]
    ok = (k1.returncode == 0 and krm.returncode == 0 and k2.returncode == 0 and row is not None
          and kept not in named and row["klass"] == NO_SUCCESSOR and kept in copies
          and (copied / kept).is_file())
    checks.append(("FALSIFY the same blob under a different basename is not a rename", ok,
                   f"class={None if row is None else row['klass']} successors={named} copies={copies}"))
  return checks


def _control_plant(due, pop):
  """An existing path is not in the gone list. The gone list is ``movement()``, on a copy."""
  saved = os.environ.pop("GIT_INDEX_FILE", None)
  try:
    with tempfile.TemporaryDirectory(prefix="ledgergone-control.") as tmp:
      root = Path(tmp) / "tree"
      root.mkdir()
      pop._tree(root, "gates")
      witness = "gates/home-witness.py"
      phantom = "gates/phantom-gone.py"
      init = git(["init", "-q"], root)
      committed = _plant_commit(root, ["pyproject.toml", witness], "plant")
      pop._MEASURED.clear()
      rows = due.rows_of(pop, root)
      live = {row[0] for row in rows}
      if witness not in live or init.returncode != 0 or committed.returncode != 0:
        return ("CONTROL a path that exists is not in the gone list", False,
                f"init={init.returncode} commit={committed.returncode} discovered={witness in live}")
      ledger = Path(tmp) / "ledger.tsv"
      due.write_copy(pop, [*rows, (phantom, "py-main", "-", False, True)], ledger)
      diff = due.movement(pop, rows, ledger)
      exists = (root / witness).is_file() and not (root / phantom).exists()
      ok = (exists and witness not in diff["gone"] and phantom in diff["gone"]
            and witness not in diff["new"])
      return ("CONTROL a path that exists is not in the gone list", ok,
              f"exists={exists} witness_gone={witness in diff['gone']} "
              f"phantom_gone={phantom in diff['gone']}")
  finally:
    if saved is not None:
      os.environ["GIT_INDEX_FILE"] = saved


def _ledger_hash():
  return git(["hash-object", str(LEDGER)], ROOT).stdout.strip()


def run_plants(due, pop):
  before = _ledger_hash()
  saved = os.environ.pop("GIT_INDEX_FILE", None)
  try:
    checks = _classifier_plants()
  finally:
    if saved is not None:
      os.environ["GIT_INDEX_FILE"] = saved
  checks.append(_control_plant(due, pop))
  refused = main(["--write-ledger"])
  after = _ledger_hash()
  checks.append(("write against the real ledger is refused and writes nothing",
                 refused == REFUSED and before == after and before != "",
                 f"rc={refused} hash_same={before == after}"))
  failed = 0
  for name, ok, detail in checks:
    print(f"ledgergone PLANT {'PASS' if ok else 'FAIL'} {name}\n          observed: {detail}")
    failed += not ok
  code = PASS if failed == 0 else FAIL
  print(f"ledgergone PLANTS: {'GREEN' if code == PASS else 'RED'} ({len(checks) - failed}/{len(checks)})")
  return code


def main(argv=None):
  ap = argparse.ArgumentParser(prog="gates/ledgergone-gate.py", description=__doc__)
  ap.add_argument("--plant", action="store_true",
                  help="assert the plants on copies; never writes the live ledger")
  ap.add_argument("--write-ledger", action="store_true",
                  help="refused: this gate does not write the shared ledger")
  args = ap.parse_args(argv)
  if args.write_ledger:
    print("ledgergone REFUSED: this gate does not write the ledger and does not retire a row")
    return REFUSED
  due = load_due()
  if due is None:
    print("ledgergone REFUSED: gates/ledgerdue-gate.py did not load movement()")
    return REFUSED
  pop = due.load_pop()
  if pop is None:
    print("ledgergone REFUSED: gates/gates-pop.py did not load")
    return REFUSED
  return run_plants(due, pop) if args.plant else run(due, pop)


if __name__ == "__main__":
  sys.exit(main())
