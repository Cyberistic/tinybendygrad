#!/usr/bin/env python3
"""Name the commit that owes each unpaid gates-pop ledger movement.

The denominator is the live diff, re-derived from ``gates/gates-pop.py`` by path.
``cd450ea61``'s 70/5 is a recorded reading to compare against, not the count.
This gate does not write ``gates/gates-pop.ledger.tsv``. A write attempt is REFUSED.

THE POPULATION IS ``gates/gates-pop.py``'s, and that file excludes a mutation harness's STAGED
REVISION by its NAME (``is_scratch``): a copy is not a gate, and a copy the ledger admitted is a
row no commit can owe -- which is what the five UNOWNED rows were.

    .venv/bin/python gates/ledgerdue-gate.py
    .venv/bin/python gates/ledgerdue-gate.py --plant
"""
import argparse
import hashlib
import importlib.util
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

# A recorded reading, so a later run can say the diff moved. Not the denominator.
RECORDED_AT = "cd450ea61"
RECORDED = {"new": 70, "gone": 5, "changed": 0, "returned": 0, "ledger": 224, "live": 289}
DIFF_KEYS = ("new", "gone", "changed", "returned", "ledger", "live")
SYNTHETIC = "gates/synthetic-new.py"
NEVER = "gates/never.py"


def load_pop():
  """``gates/gates-pop.py`` by path. The hyphen is why ``import`` cannot name it."""
  path = HERE / "gates-pop.py"
  if not path.is_file():
    return None
  spec = importlib.util.spec_from_file_location("gates_pop", path)
  mod = importlib.util.module_from_spec(spec)
  sys.modules["gates_pop"] = mod
  spec.loader.exec_module(mod)
  return mod


def git_blob(path):
  """The git object hash, which is what ``git hash-object`` and ``HEAD:<path>`` name.

  A raw sha256 of the bytes is a different number for the same file, and quoting it
  as the ledger hash would say the file moved when it had not.
  """
  data = Path(path).read_bytes()
  return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def rows_of(pop, root):
  """The rows ``report`` diffs, asked of the loaded module. Not a second population."""
  root = Path(root).resolve()
  entries, _libs = pop.discover(root)
  rows = []
  for path in entries:
    const, asserts, onroot = pop.root_facts(path, root)
    rows.append((str(path.relative_to(root)), pop.entry_reason(path), const, asserts, onroot))
  return rows


def movement(pop, rows, ledger):
  """The set difference ``report`` computes, over this module's own predicates."""
  prev = pop.read_ledger(Path(ledger))
  live = {row[0]: row[1:] for row in rows}
  if prev is None:
    return {"new": sorted(live), "gone": [], "changed": [], "returned": [],
            "ledger": 0, "live": len(rows), "no_ledger": True}
  old = {row[0]: row[1:] for row in prev}
  retired = {path for path, tail in old.items() if tail[0] == pop.RETIRED}
  return {
    "new": sorted(set(live) - set(old)),
    "gone": sorted(set(old) - set(live) - retired),
    "changed": sorted(path for path in set(live) & set(old)
                      if pop.DECIDED(live[path]) != pop.DECIDED(old[path])),
    "returned": sorted(retired & set(live)),
    "ledger": len(prev),
    "live": len(rows),
    "no_ledger": False,
  }


def due_rows(diff, events):
  """Every NEW and GONE path, with the commit ``events()`` says owes it.

  A missing commit is a row whose owner is None. It is not dropped.
  """
  rows = [("NEW", path, events.get(path, (None, None))[0]) for path in diff["new"]]
  rows += [("GONE", path, events.get(path, (None, None))[1]) for path in diff["gone"]]
  return rows


def due_line(kind, path, owner):
  return f"DUE {kind} {path} OWES {owner or 'NO-OWNER'}"


def counts(diff):
  return {key: len(diff[key]) if key in ("new", "gone", "changed", "returned") else diff[key]
          for key in DIFF_KEYS}


def write_copy(pop, rows, path):
  """``write_ledger`` on a copy. The real ledger is not a legal target."""
  dest = Path(path).resolve()
  if dest == LEDGER.resolve() or dest == pop.LEDGER.resolve():
    print("plant refused: write target is the real ledger", file=sys.stderr)
    raise SystemExit(3)
  return pop.write_ledger(rows, dest)


def scratch_plants(pop):
  """A mutation harness's STAGED REVISION is excluded BY ITS NAME, and a name that merely
  CONTAINS `mut` is not.

  **THE FIVE UNOWNED ROWS THIS GATE REPORTS ARE FIVE OF THESE.** `gates/gates-pop.py`'s
  `is_scratch` is the rule; this is the plant that says the rule is BOUNDED, in both directions:
  a copy the COMMIT TREE carries is still excluded (so the exclusion is not the commit tree's
  rule wearing a new hat), and a real name that happens to contain `mut` is still counted (so the
  exclusion is not "everything with mut in it").
  """
  os.environ.pop("GIT_INDEX_FILE", None)
  checks = []
  with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp) / "tree"
    root.mkdir()
    pop._tree(root, "gates")
    copies = ("gates/stage-mut-gate.py", "gates/stage-mut-oracle.py")
    keeps = ("gates/keep-mutate.py", "gates/keep-mut-keeper.py", "gates/commutative-gate.py")
    for rel in (*copies, *keeps):
      (root / rel).write_text(pop.GOOD_ROOT)
    committed = pop._commit(root) == 0
    pop._MEASURED.clear()
    rows = {row[0] for row in rows_of(pop, root)}
    carried = set(pop._measure(root)[1]["paths"])
    excluded = [rel for rel in copies if rel not in rows]
    counted = [rel for rel in keeps if rel in rows]
    checks.append((
      "a mutation harness's staged revision is NOT a gate, and the commit tree CARRIES it",
      committed and all(rel in carried for rel in copies) and len(excluded) == len(copies),
      f"committed={committed} carried={sorted(rel for rel in copies if rel in carried)} "
      f"excluded={excluded}",
    ))
    checks.append((
      "a real name that merely CONTAINS `mut` is still counted",
      len(counted) == len(keeps),
      f"counted={counted} of {list(keeps)}",
    ))
  return checks


def copy_plants(pop):
  """A synthetic new path is due; the unmutated ledger does not gain that row."""
  os.environ.pop("GIT_INDEX_FILE", None)
  checks = []
  with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp) / "tree"
    root.mkdir()
    pop._tree(root, "gates")
    (root / "gates" / "synthetic-new.py").write_text(pop.GOOD_ROOT)
    committed = pop._commit(root) == 0
    pop._MEASURED.clear()
    rows = rows_of(pop, root)
    present = SYNTHETIC in {row[0] for row in rows}
    control = Path(tmp) / "control.tsv"
    mutated = Path(tmp) / "mutated.tsv"
    never = Path(tmp) / "never.tsv"
    write_copy(pop, rows, control)
    write_copy(pop, [row for row in rows if row[0] != SYNTHETIC], mutated)
    write_copy(pop, [*rows, (NEVER, "py-main", "-", False, True)], never)
    events = pop.events(root, pop._homes(root))
    control_diff = movement(pop, rows, control)
    mutated_due = due_rows(movement(pop, rows, mutated), events)
    never_due = due_rows(movement(pop, rows, never), events)
    owner = events.get(SYNTHETIC, (None, None))[0]
    synth = due_line("NEW", SYNTHETIC, owner)
    mutated_text = [due_line(*row) for row in mutated_due]
    control_text = [due_line(*row) for row in due_rows(control_diff, events)]
    never_text = [due_line(*row) for row in never_due]
    checks.append((
      "synthetic new path appears in the due list",
      committed and present and owner is not None and synth in mutated_text,
      f"committed={committed} present={present} owner={owner!r} line={synth in mutated_text}",
    ))
    checks.append((
      "unmutated control does not gain a due row",
      SYNTHETIC not in control_diff["new"] and SYNTHETIC not in control_diff["gone"]
      and not control_text and not control_diff["changed"] and not control_diff["returned"],
      f"control_due={len(control_text)} changed={len(control_diff['changed'])}",
    ))
    never_line = due_line("GONE", NEVER, None)
    checks.append((
      "a path with no owning commit is its own row",
      never_line in never_text and events.get(NEVER, (None, None))[1] is None,
      f"found={never_line in never_text}",
    ))
  return checks


def write_plant():
  """A write of the real ledger is a failure of this plant, not a mode of the gate."""
  if not LEDGER.is_file():
    return ("write against the real ledger is a FAIL of the plant, not a feature",
            False, "real ledger absent")
  before = git_blob(LEDGER)
  try:
    ran = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--write-ledger"],
                         capture_output=True, text=True, timeout=30)
    rc, out = ran.returncode, ran.stdout + ran.stderr
  except subprocess.TimeoutExpired:
    rc, out = None, "TIMED-OUT"
  after = git_blob(LEDGER)
  ok = rc == REFUSED and "REFUSED" in out and before == after and "WROTE" not in out
  return ("write against the real ledger is a FAIL of the plant, not a feature",
          ok, f"rc={rc} hash_same={before == after} said_refused={'REFUSED' in out}")


def run_plants(pop):
  before = git_blob(LEDGER) if LEDGER.is_file() else None
  checks = copy_plants(pop)
  checks += scratch_plants(pop)
  checks.append(write_plant())
  after = git_blob(LEDGER) if LEDGER.is_file() else None
  checks.append(("real ledger hash unchanged by the plant", before == after,
                 f"{(before or '')[:12]}->{(after or '')[:12]}"))
  failed = 0
  for name, ok, detail in checks:
    print(f"ledgerdue PLANT {'PASS' if ok else 'FAIL'} {name}\n          observed: {detail}")
    failed += not ok
  code = PASS if failed == 0 else FAIL
  print(f"ledgerdue PLANTS: {'GREEN' if code == PASS else 'RED'} ({len(checks) - failed}/{len(checks)})")
  return code


def run(pop):
  now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
  print(f"ledgerdue WHEN {now}")
  print(f"ledgerdue CMD {Path(sys.argv[0]).name} {' '.join(sys.argv[1:])}".rstrip())
  if not LEDGER.is_file():
    print(f"ledgerdue REFUSED: no ledger at {LEDGER.name}")
    return REFUSED
  head = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short=9", "HEAD"],
                        capture_output=True, text=True)
  head = head.stdout.strip() if head.returncode == 0 else "NO-HEAD"
  print(f"ledgerdue HEAD {head}")
  if not head.startswith(RECORDED_AT):
    print(f"ledgerdue HEAD-MOVED since {RECORDED_AT}")
  print(f"ledgerdue LEDGER git-blob={git_blob(LEDGER)} write=not-a-mode")
  print("ledgerdue DENOMINATOR live-diff re-derived "
        f"(recorded {RECORDED_AT} is a comparison, not the count)")
  diff = movement(pop, rows_of(pop, ROOT), LEDGER)
  if diff["no_ledger"]:
    print("ledgerdue DEAD: ledger read returned nothing — compared nothing")
    return DEAD
  live = counts(diff)
  print("ledgerdue DIFF " + " ".join(f"{key}={live[key]}" for key in DIFF_KEYS))
  print("ledgerdue RECORDED " + RECORDED_AT + " "
        + " ".join(f"{key}={RECORDED[key]}" for key in DIFF_KEYS))
  deltas = [key for key in DIFF_KEYS if live[key] != RECORDED[key]]
  if deltas:
    print("ledgerdue MOVED since " + RECORDED_AT + ": "
          + " ".join(f"{key} {RECORDED[key]}->{live[key]}" for key in deltas))
  else:
    print(f"ledgerdue UNMOVED since {RECORDED_AT}")
  events = pop.events(ROOT, pop._homes(ROOT))
  due = due_rows(diff, events)
  if not events and due:
    print("ledgerdue EVENTS empty: attribution unavailable; each due path is still a row")
  else:
    print(f"ledgerdue EVENTS {len(events)} path(s) attributed")
  for kind, path, owner in due:
    print(f"ledgerdue {due_line(kind, path, owner)}")
  for path in diff["changed"]:
    print(f"ledgerdue DIFF CHANGED {path}")
  for path in diff["returned"]:
    print(f"ledgerdue DIFF RETURNED {path}")
  owned = sum(owner is not None for _kind, _path, owner in due)
  print(f"ledgerdue OWNED {owned} UNOWNED {len(due) - owned} DUE {len(due)}")
  code = FAIL if any(diff[key] for key in ("new", "gone", "changed", "returned")) else PASS
  print(f"ledgerdue VERDICT {VERDICT[code]}")
  return code


def main(argv=None):
  ap = argparse.ArgumentParser(prog="gates/ledgerdue-gate.py", description=__doc__)
  ap.add_argument("--plant", action="store_true",
                  help="assert the plants on copies; never writes the live ledger")
  ap.add_argument("--write-ledger", action="store_true",
                  help="refused: this gate does not write the shared ledger")
  ap.add_argument("--only", action="append", default=None, metavar="PATH",
                  help="refused: this gate takes no pathspec")
  args = ap.parse_args(argv)
  if args.write_ledger or args.only:
    print(f"ledgerdue REFUSED: this gate does not write {LEDGER.name}")
    return REFUSED
  pop = load_pop()
  if pop is None:
    print("ledgerdue REFUSED: gates/gates-pop.py is absent")
    return REFUSED
  return run_plants(pop) if args.plant else run(pop)


if __name__ == "__main__":
  sys.exit(main())
