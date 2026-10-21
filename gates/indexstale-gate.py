#!/usr/bin/env python3
"""indexstale-gate.py -- name a path the index and HEAD SHARE and DISAGREE about.

    .venv/bin/python gates/indexstale-gate.py
    .venv/bin/python gates/indexstale-gate.py --plant
    .venv/bin/python gates/indexstale-gate.py --root <path>

THE POPULATION IS TWO COMMANDS, NOT A REMEMBERED LIST OF PATHS:

    git ls-files -s -z          the INDEX: mode, blob, stage, path
    git ls-tree -r -z HEAD      the TREE:  mode, type, blob, path

`-z` is only the separator, so a quoted path stays one path. It is not a
third listing.

THE HAZARD THIS MEASURES. `gates/indexshort-gate.py` compares the two PATHSETS:
a path in one and not in the other. It cannot see a path in BOTH whose INDEXED
BLOB is not HEAD's blob. That shape is a STALE-BLOB, and it is how another
unit's work is reverted: a bare `git commit` writes the INDEX's content, so an
index holding the PRE-change blob over a HEAD that holds the POST-change blob
commits the old bytes and the new work is gone. `AGENTS.md`: "THE HAZARD IS
SILENT REVERSION, NOT AN EMPTY BLOB." Measured on this tree, a bare commit over
such an index would have written the OLD bytes of `gates/expectcopy-gate.py`
back over the new ones, and the PATH COUNT was equal on both sides.

THE CLASSES, AND ONLY ONE OF THEM IS A FAILURE.

    STALE-BLOB   the index and HEAD share the path and their BLOBS differ.
    INDEX-ARMED  the index has the path and HEAD does not -- an addition, a
                 different mechanism, and `gates/indexshort-gate.py`'s verdict.
    INDEX-SHORT  HEAD has the path and the index does not -- a deletion, likewise.
    INDEX-MODE   the blobs agree and the MODE does not -- a staged `chmod`,
                 which changes no content.
    INDEX-CONFLICT  the index carries stages 1/2/3 for a path, so its content
                 is not one blob and the comparison cannot be made for it.

PASS MEANS: for every path the index and HEAD share, the index's blob IS
HEAD's blob. A PATH-COUNT DIFFERENCE DOES NOT MAKE IT FAIL, because a path
count is not what this gate measures -- and the path-set verdict belongs to
`gates/indexshort-gate.py`, which FAILS on exactly that. The two gates' verdicts
differ on purpose, which is why this is a sibling and not an extension.

EQUAL COUNTS WITH A STALE BLOB MUST NOT READ AS HEALTHY, so the counts and the
stale set are printed together, and the exit is FAIL while any STALE-BLOB
remains.

READ-ONLY ON THE INDEX IT MEASURES. Every git call carries
`--no-optional-locks`, and GIT_INDEX_FILE is scrubbed, so a private commit
index is not this row and reading does not rewrite `.git/index`. The plant
writes only a temporary repository.
"""
from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED  # noqa: E402

# A private commit index must not become this row. Inheriting GIT_INDEX_FILE
# describes a different file, which is how a gate passes while the default
# index is short.
REDIRECTS = (
  "GIT_INDEX_FILE", "GIT_DIR", "GIT_WORK_TREE", "GIT_OBJECT_DIRECTORY",
  "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR", "GIT_NAMESPACE",
)
GATE = Path(__file__).resolve()


def clean_env() -> dict[str, str]:
  """The repository's own index. Never the caller's GIT_INDEX_FILE."""
  return {k: v for k, v in os.environ.items() if k not in REDIRECTS}


def git(root: Path, *args: str, stdin: str | None = None) -> tuple[int, str, str]:
  try:
    p = subprocess.run(
      ("git", "--no-optional-locks", *args),
      cwd=root, capture_output=True, text=True, env=clean_env(), check=False, input=stdin,
    )
  except FileNotFoundError:
    return DEAD, "", "git not found"
  return p.returncode, p.stdout, p.stderr


def index_entries(root: Path) -> tuple[dict[str, list[tuple[str, str, str]]] | None, str]:
  """path -> [(mode, blob, stage)]. `git ls-files -s -z`.

  A LIST and not a dict, because a conflicted path carries stages 1, 2 and 3 and
  a dict can hold only one of them. The same defect one level up is measured in
  `checks/index-arm-gate.py`: a tree naming a path twice had 252 of its entries
  silently dropped by a dict, and the gate that dropped them reported PASS.
  """
  rc, out, err = git(root, "ls-files", "-s", "-z")
  if rc != 0:
    return None, f"ls-files rc={rc} {err.strip()}"
  ent: dict[str, list[tuple[str, str, str]]] = {}
  for rec in out.split("\0"):
    if not rec:
      continue
    meta, _, path = rec.partition("\t")
    fields = meta.split()
    if len(fields) != 3:
      return None, f"ls-files: unparsable record {rec!r}"
    ent.setdefault(path, []).append((fields[0], fields[1], fields[2]))
  return ent, ""


def tree_entries(root: Path, rev: str) -> tuple[dict[str, list[tuple[str, str]]] | None, list[str], str]:
  """path -> [(mode, blob)]. `git ls-tree -r -z <rev>`. The second value is the
  paths the TREE names more than once, which no index can witness."""
  rc, out, err = git(root, "ls-tree", "-r", "-z", rev)
  if rc != 0:
    return None, [], f"ls-tree rc={rc} {err.strip()}"
  ent: dict[str, list[tuple[str, str]]] = {}
  dupes: list[str] = []
  for rec in out.split("\0"):
    if not rec:
      continue
    meta, _, path = rec.partition("\t")
    fields = meta.split()
    if len(fields) != 3:
      return None, [], f"ls-tree: unparsable record {rec!r}"
    if path in ent and path not in dupes:
      dupes.append(path)
    ent.setdefault(path, []).append((fields[0], fields[2]))
  return ent, dupes, ""


def classify(root: Path, rev: str) -> tuple[int, list[str]]:
  """The index's CONTENT against the tree's, one class per path."""
  idx, err = index_entries(root)
  if idx is None:
    return DEAD, [f"INDEX-STALE DEAD {err}"]
  tree, dupes, err = tree_entries(root, rev)
  if tree is None:
    return DEAD, [f"INDEX-STALE DEAD {err}"]

  stale: list[tuple[str, str, str, str, str]] = []
  armed: list[tuple[str, str, str]] = []
  mode: list[tuple[str, str, str]] = []
  conflict: list[tuple[str, list[str]]] = []
  for path, entries in idx.items():
    stages = sorted(e[2] for e in entries)
    if stages != ["0"]:
      conflict.append((path, stages))
      continue
    mode_i, sha_i, _stage = entries[0]
    if path not in tree:
      armed.append((path, sha_i, mode_i))
      continue
    mode_t, sha_t = tree[path][0]
    if sha_i != sha_t:
      stale.append((path, sha_i, sha_t, mode_i, mode_t))
    elif mode_i != mode_t:
      mode.append((path, mode_i, mode_t))
  short = sorted(set(tree) - set(idx))

  lines: list[str] = []
  for path, sha_i, sha_t, mode_i, mode_t in stale:
    extra = f" mode={mode_i}/{mode_t}" if mode_i != mode_t else ""
    lines.append(f"STALE-BLOB {path} index={sha_i} head={sha_t}{extra}")
  for path, sha_i, mode_i in armed:
    lines.append(f"INDEX-ARMED {path} index={sha_i} mode={mode_i}")
  for path in short:
    lines.append(f"INDEX-SHORT {path}")
  for path, mode_i, mode_t in mode:
    lines.append(f"INDEX-MODE {path} index={mode_i} head={mode_t}")
  for path, stages in sorted(conflict):
    lines.append(f"INDEX-CONFLICT {path} stages={','.join(stages)}")

  shared = len(set(idx) & set(tree))
  lines.append(f"INDEX-STALE COUNTS ls-tree={len(tree)} ls-files={len(idx)} shared={shared} "
               f"stale={len(stale)} armed={len(armed)} short={len(short)} mode={len(mode)} "
               f"conflict={len(conflict)}")

  # A TREE THAT NAMES A PATH TWICE IS A WRONG TREE, and the comparison above is
  # measured against it, so the counts on that line understate the tree.
  if dupes:
    lines.append(f"INDEX-STALE REFUSED, NOT A VERDICT: HEAD's tree names {len(dupes)} path(s) MORE "
                 f"THAN ONCE ({', '.join(dupes[:3])}), so `ls-tree -r` emits more entries than there "
                 f"are paths and the count above UNDERSTATES the tree. No index can witness this.")
    return REFUSED, lines
  if conflict:
    lines.append(f"INDEX-STALE REFUSED, NOT A VERDICT: {len(conflict)} path(s) carry stages 1/2/3, so "
                 f"the index's content is not a single blob there and the comparison cannot be made.")
    return REFUSED, lines
  if stale:
    lines.append(f"INDEX-STALE VERDICT FAIL: {len(stale)} path(s) the index and HEAD SHARE and "
                 f"DISAGREE about. A bare `git commit` writes the INDEX's blob, so it reverts HEAD's.")
    return FAIL, lines
  lines.append(f"INDEX-STALE VERDICT PASS: the index's blob is HEAD's blob on all {shared} shared "
               f"path(s); stale=0. The path-set verdict is `gates/indexshort-gate.py`'s, and it is a "
               f"DIFFERENT verdict: {len(short)} INDEX-SHORT and {len(armed)} INDEX-ARMED are named "
               f"above and are NOT a failure here.")
  return PASS, lines


def index_path(root: Path) -> Path | None:
  rc, out, _err = git(root, "rev-parse", "--git-path", "index")
  if rc != 0:
    return None
  path = Path(out.strip())
  return path if path.is_absolute() else root / path


def index_digest(root: Path) -> str | None:
  """sha256 of `.git/index`. The control: reading must not rewrite it."""
  path = index_path(root)
  if path is None:
    return None
  try:
    return hashlib.sha256(path.read_bytes()).hexdigest()
  except OSError:
    return None


def invoke(root: Path, decoy: Path) -> tuple[int, list[str]]:
  """Run this file. The decoy is inherited on purpose: failing to scrub reads it."""
  env = clean_env()
  env["GIT_INDEX_FILE"] = os.fspath(decoy)
  p = subprocess.run(
    [sys.executable, os.fspath(GATE), "--root", os.fspath(root)],
    cwd=ROOT, capture_output=True, text=True, env=env, check=False,
  )
  return p.returncode, [ln for ln in p.stdout.splitlines() if ln]


def verdict_lines(lines: list[str]) -> list[str]:
  """The per-path rows. The COUNTS line is not one: it is a summary of them."""
  return [ln for ln in lines if ln.split(" ", 1)[0] in
          ("STALE-BLOB", "INDEX-ARMED", "INDEX-SHORT", "INDEX-MODE", "INDEX-CONFLICT")]


def must(root: Path, *args: str) -> str | None:
  rc, _out, err = git(root, *args)
  if rc != 0:
    return f"{' '.join(args)} rc={rc} {err.strip()}"
  return None


def sha_of(root: Path, text: str) -> str:
  """git's blob sha of `text`, without writing a file."""
  rc, out, err = git(root, "hash-object", "-t", "blob", "--stdin", stdin=text)
  if rc != 0:
    raise RuntimeError(f"hash-object rc={rc} {err.strip()}")
  return out.strip()


def _expect(label: str, code: int, lines: list[str], want_code: int, want: list[str],
            bad: list[str]) -> None:
  got = verdict_lines(lines)
  print(f"PLANT {label} exit={code} {' | '.join(got) if got else '(no per-path row)'}")
  if code != want_code or got != want:
    bad.append(f"{label} expected {want} exit {want_code}, got exit={code} {got}")


def plant() -> int:
  """Temp repo only. A decoy index is inherited so a missed scrub cannot pass."""
  bad: list[str] = []
  real_before = index_digest(ROOT)
  if real_before is None:
    print("PLANT DEAD: could not read the real index")
    return DEAD

  with tempfile.TemporaryDirectory(prefix="indexstale-") as raw:
    tmp = Path(raw)
    repo = tmp / "repo"
    repo.mkdir()
    err = must(repo, "init", "-q", "-b", "master")
    if err:
      print(f"PLANT DEAD: {err}")
      return DEAD
    (repo / "kept.rows").write_text("x\n")
    err = must(repo, "add", "--", "kept.rows")
    if err is None:
      err = must(repo, "-c", "user.email=t@t", "-c", "user.name=t",
                 "commit", "-q", "-m", "seed")
    if err:
      print(f"PLANT DEAD: {err}")
      return DEAD
    head_sha = sha_of(repo, "x\n")

    # THE DECOY IS A COPY OF THE INDEX AS IT IS NOW. A gate that did not scrub
    # would read the copy and answer the MATCH state for every state below.
    decoy_copy = tmp / "decoy-copy"
    decoy_copy.write_bytes((repo / ".git" / "index").read_bytes())
    # ... and an EMPTY decoy for the first state, where the copy would be right.
    decoy_empty = tmp / "decoy-empty"
    decoy_empty.write_bytes(b"")

    # 1. EVERY BLOB MATCHES. The baseline the other three are measured against.
    code, lines = invoke(repo, decoy_empty)
    _expect("MATCH", code, lines, PASS, [], bad)

    # 2. STALE-BLOB. Committed, then edited in the worktree and re-added, so the
    #    index holds a blob that is not HEAD's.
    (repo / "kept.rows").write_text("y\n")
    err = must(repo, "add", "--", "kept.rows")
    if err:
      print(f"PLANT DEAD: {err}")
      return DEAD
    work_sha = sha_of(repo, "y\n")
    if work_sha == head_sha:
      print("PLANT DEAD: the edited blob is HEAD's; that is not the stale shape")
      return DEAD
    code, lines = invoke(repo, decoy_copy)
    _expect("STALE", code, lines, FAIL,
            [f"STALE-BLOB kept.rows index={work_sha} head={head_sha}"], bad)

    # 3. INDEX-ARMED. A file added to the index and not committed. The count
    #    differs and the blobs still agree, so this is NOT a failure here.
    err = must(repo, "read-tree", "HEAD")
    if err is None:
      (repo / "extra.rows").write_text("z\n")
      err = must(repo, "add", "--", "extra.rows")
    if err:
      print(f"PLANT DEAD: {err}")
      return DEAD
    extra_sha = sha_of(repo, "z\n")
    code, lines = invoke(repo, decoy_copy)
    _expect("ARMED", code, lines, PASS,
            [f"INDEX-ARMED extra.rows index={extra_sha} mode=100644"], bad)

    # 4. INDEX-SHORT. A file removed from the index. The count differs and the
    #    blobs still agree, so this is NOT a failure here either.
    err = must(repo, "read-tree", "HEAD")
    if err is None:
      err = must(repo, "rm", "--cached", "-q", "--", "kept.rows")
    if err:
      print(f"PLANT DEAD: {err}")
      return DEAD
    if not (repo / "kept.rows").is_file():
      print("PLANT DEAD: rm --cached removed the worktree file")
      return DEAD
    code, lines = invoke(repo, decoy_copy)
    _expect("SHORT", code, lines, PASS, ["INDEX-SHORT kept.rows"], bad)

  # THE CONTROL. The gate must not have moved the real repository's index.
  real_after = index_digest(ROOT)
  same = real_before == real_after
  print(f"CONTROL .git/index before={real_before} after={real_after} "
        f"{'same' if same else 'MOVED'}")
  if not same:
    bad.append("CONTROL the real index bytes moved")

  if bad:
    for line in bad:
      print(f"PLANT FAIL {line}")
    return FAIL
  print("PLANT OK")
  return PASS


def main(argv: list[str]) -> int:
  if "--plant" in argv:
    return plant()
  root = ROOT
  if "--root" in argv:
    i = argv.index("--root")
    if i + 1 >= len(argv):
      print("USAGE: --root <path>", file=sys.stderr)
      return REFUSED
    root = Path(argv[i + 1]).resolve()
  rc, _out, err = git(root, "rev-parse", "--verify", "HEAD")
  if rc != 0:
    print(f"INDEX-STALE DEAD: no HEAD here ({root}): {err.strip()}")
    return DEAD
  code, lines = classify(root, _out.strip())
  for line in lines:
    print(line)
  return code


if __name__ == "__main__":
  sys.exit(main(sys.argv[1:]))
