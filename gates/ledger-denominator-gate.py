#!/usr/bin/env python3
"""ledger-denominator-gate.py -- IS THE TOOLS.md LEDGER'S DENOMINATOR A FUNCTION OF THE COMMIT?

    .venv/bin/python gates/ledger-denominator-gate.py

THE SUBJECT IS ONE QUESTION, ASKED TWICE. `.agents/slop/toolsledger/extract.py` answers "is this
path PRESENT?" for the 408 backtick tokens in `.agents/TOOLS.md`. Its denominator is a set of
tracked paths. If that set comes from `git ls-files` the answer inherits GIT_INDEX_FILE, so a
staged deletion, a `jj` snapshot, or a co-located unit's commit changes the ledger's published
counts without changing a byte of the tree. This gate runs the REAL extractor on the REAL tree
twice -- once against the default index, once against a private index verified byte-equal to
`git ls-tree -r --name-only HEAD` -- and FAILS if the two disagree.

WHY THIS IS NOT `gates/indexread-gate.py`. That gate is LEXICAL: EXACT_FORMS = ("ls-files",
"--cached", "read-tree", "--porcelain"). It finds an instrument that spells the index read. It
structurally cannot see one that reaches the index another way -- `git status --short`,
`git diff --cached -q`, a bare `git commit`, or any `subprocess` that shells out to a wrapper.
This gate is BEHAVIOURAL: it varies GIT_INDEX_FILE and reads the answer. The two populations are
different, so neither is a second copy of the other.

THE PLANT, AND WHY IT IS THE POINT. A comparison that has never been shown to differ is
indistinguishable from a comparison that cannot differ ('0 disagreements' over '0 comparisons').
So this gate builds a THROWAWAY repo in a temp dir -- never this repo's `.git` -- where the index
and the commit genuinely disagree about two paths the ledger names, and asserts BOTH halves:

  * the MUTANT (the real extractor with its commit read rewritten back to `git ls-files`) MUST
    answer differently armed vs disarmed -- otherwise this harness measures nothing;
  * the REAL extractor MUST answer identically armed vs disarmed.

The mutant is synthesised by rewriting ONE substring in a COPY. If that rewrite is a no-op -- the
subject no longer reads the commit -- the plant is UNAVAILABLE and this gate REFUSES (3) rather
than reporting an agreement it could no longer corroborate. That coupling is the price of using
the real pre-fix instrument as the mutant instead of a synthetic one, and it is paid in the honest
direction: an unavailable plant can only ever make this gate quieter, never greener.

VERDICTS are `gatekit`'s five, not a sixth: PASS, FAIL, REFUSED, DEAD. DEAD is returned when the
extractor produced no population at all, which is what a broken `git ls-tree` looks like.
"""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402  (the five, not a sixth)

ROOT = Path(__file__).resolve().parent.parent
EXTRACT = ".agents/slop/toolsledger/extract.py"
PY = str(ROOT / ".venv/bin/python")

COMMIT_READ = "['git','ls-tree','-r','--name-only','HEAD']"
INDEX_READ = "['git','ls-files']"


def git(cwd, *a, index=None):
  env = dict(os.environ)
  if index:
    env["GIT_INDEX_FILE"] = index
  r = subprocess.run(["git", *a], cwd=cwd, capture_output=True, text=True, env=env)
  return r.returncode, r.stdout, r.stderr


def disarmed_index(repo, dest):
  """A private index at `dest`, verified byte-equal to the commit tree. NEVER this repo's index."""
  rc, _, err = git(repo, "read-tree", "HEAD", index=dest)
  if rc != 0:
    return None, err
  rc, idx, _ = git(repo, "ls-files", index=dest)
  rc2, tree, _ = git(repo, "ls-tree", "-r", "--name-only", "HEAD")
  if sorted(idx.split()) != sorted(tree.split()):
    return None, f"refusing: private index is not disarmed ({len(idx.split())} vs {len(tree.split())})"
  return dest, ""


def run_extract(repo, index=None):
  """Run the extractor in `repo`, return (rc, stdout, sha256 of the paths.tsv it wrote)."""
  env = dict(os.environ)
  if index:
    env["GIT_INDEX_FILE"] = index
  r = subprocess.run([PY, EXTRACT], cwd=repo, capture_output=True, text=True, env=env)
  tsv = Path(repo) / ".agents/slop/toolsledger/paths.tsv"
  sha = hashlib.sha256(tsv.read_bytes()).hexdigest() if tsv.exists() else "NO-ROWS-WRITTEN"
  return r.returncode, r.stdout, sha


def plant(tmp):
  """A throwaway repo whose index and commit disagree about two ledger-named paths."""
  repo = Path(tmp) / "repo"
  (repo / ".agents/slop/toolsledger").mkdir(parents=True)
  (repo / "ghost").mkdir()
  shutil.copy(ROOT / EXTRACT, repo / EXTRACT)

  (repo / ".agents/TOOLS.md").write_text("names both: `ghost/in-index.py` `ghost/in-commit.py`\n")
  (repo / "ghost/in-commit.py").write_text("committed, then untracked and unfiled\n")
  git(repo, "init", "-q")
  git(repo, "add", "-A")
  git(repo, "-c", "user.email=g@g", "-c", "user.name=g", "commit", "-qm", "base")

  # in the INDEX, not in the COMMIT, not on disk.
  (repo / "ghost/in-index.py").write_text("staged then deleted\n")
  git(repo, "add", "ghost/in-index.py")
  os.remove(repo / "ghost/in-index.py")
  # in the COMMIT, not in the INDEX, not on disk.
  os.remove(repo / "ghost/in-commit.py")
  git(repo, "rm", "--cached", "-q", "ghost/in-commit.py")

  rc, idx, _ = git(repo, "ls-files")
  rc2, tree, _ = git(repo, "ls-tree", "-r", "--name-only", "HEAD")
  idx, tree = set(idx.split()), set(tree.split())
  if not ({"ghost/in-index.py"} <= idx - tree and {"ghost/in-commit.py"} <= tree - idx):
    return None, "plant did not arm: the index and the commit do not disagree about both ghost paths"
  if (repo / "ghost/in-index.py").exists() or (repo / "ghost/in-commit.py").exists():
    return None, "plant did not arm: a ghost path is on disk, so os.path.exists would decide instead"

  real = (repo / EXTRACT).read_text()
  mutant_src = real.replace(COMMIT_READ, INDEX_READ)
  if mutant_src == real:
    return None, (f"the plant needs a subject that reads the COMMIT to mutate into an index read, "
                  f"and {EXTRACT} does not contain {COMMIT_READ}")

  out = {}
  for label, src in (("real", real), ("mutant", mutant_src)):
    (repo / EXTRACT).write_text(src)
    priv = os.path.join(tmp, f"idx-{label}")
    armed_rc, armed_out, armed_sha = run_extract(repo)
    armed_idx = set(git(repo, "ls-files")[1].split())
    d, err = disarmed_index(repo, priv)
    if not d:
      return None, err
    dis_rc, dis_out, dis_sha = run_extract(repo, index=d)
    out[label] = dict(armed=(armed_rc, armed_out, armed_sha, len(armed_idx)),
                      disarmed=(dis_rc, dis_out, dis_sha), differs=armed_sha != dis_sha)
  (repo / EXTRACT).write_text(real)
  return out, ""


def main(argv):
  if len(argv) > 1:
    print(f"usage: {Path(argv[0]).name}  (no arguments)", file=sys.stderr)
    return REFUSED
  if not (ROOT / EXTRACT).exists():
    print(f"LEDGER {VERDICT[REFUSED]}: {EXTRACT} is absent; nothing to measure")
    return REFUSED

  print(f"LEDGER HEAD {git(ROOT, 'rev-parse', '--short=12', 'HEAD')[1].strip()}")
  rc, idx, _ = git(ROOT, "ls-files")
  rc2, tree, _ = git(ROOT, "ls-tree", "-r", "--name-only", "HEAD")
  print(f"LEDGER TREE-COMMITTED {len(tree.split())}  INDEX {len(idx.split())}")

  with tempfile.TemporaryDirectory() as tmp:
    p, err = plant(tmp)
    if p is None:
      print(f"LEDGER PLANT UNAVAILABLE: {err}")
      print(f"LEDGER {VERDICT[REFUSED]}: without the plant this gate cannot show its own comparison "
            "can see a difference, so its agreement would be indistinguishable from its blindness")
      return REFUSED
    m, r = p["mutant"], p["real"]
    print(f"LEDGER PLANT mutant armed idx={m['armed'][3]} differs={m['differs']} "
          f"(sha {m['armed'][2][:12]} vs {m['disarmed'][2][:12]})")
    print(f"LEDGER PLANT real   armed differs={r['differs']} "
          f"(sha {r['armed'][2][:12]} vs {r['disarmed'][2][:12]})")
    if not m["differs"]:
      print(f"LEDGER {VERDICT[DEAD]}: the mutant did not move under GIT_INDEX_FILE, so this "
            "harness cannot detect the defect it exists to detect")
      return DEAD

  priv = os.path.join(tempfile.gettempdir(), f"ledger-denominator-{os.getpid()}.index")
  d, err = disarmed_index(ROOT, priv)
  if not d:
    print(f"LEDGER {VERDICT[REFUSED]}: {err}")
    return REFUSED
  try:
    armed_rc, armed_out, armed_sha = run_extract(ROOT)
    dis_rc, dis_out, dis_sha = run_extract(ROOT, index=d)
  finally:
    if os.path.exists(priv):
      os.remove(priv)  # ours, in a temp dir, created seconds ago

  for name, o in (("ARMED", armed_out), ("DISARMED", dis_out)):
    print(f"LEDGER LIVE {name} rc={armed_rc if name == 'ARMED' else dis_rc}")
    for line in o.splitlines():
      print(f"  {line}")
  if armed_sha == "NO-ROWS-WRITTEN" or dis_sha == "NO-ROWS-WRITTEN":
    print(f"LEDGER {VERDICT[DEAD]}: the extractor wrote no population")
    return DEAD
  if armed_rc != 0 or dis_rc != 0:
    print(f"LEDGER {VERDICT[FAIL]}: extractor rc armed={armed_rc} disarmed={dis_rc}")
    return FAIL
  if armed_sha != dis_sha or armed_out != dis_out:
    print(f"LEDGER {VERDICT[FAIL]}: the ledger's answer MOVED with GIT_INDEX_FILE "
          f"({armed_sha[:12]} vs {dis_sha[:12]}) -- its denominator is the INDEX, not the COMMIT")
    return FAIL
  print(f"LEDGER {VERDICT[PASS]}: identical answer armed and disarmed (sha {armed_sha[:12]}), "
        f"and the plant proved this comparison can see a difference")
  return PASS


if __name__ == "__main__":
  sys.exit(main(sys.argv))
