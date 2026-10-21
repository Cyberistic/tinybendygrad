#!/usr/bin/env python3
"""indexshort-gate.py -- name a path the index and HEAD do not share.

    .venv/bin/python gates/indexshort-gate.py
    .venv/bin/python gates/indexshort-gate.py --plant

The population is two commands, not a remembered list of paths:

    git ls-tree -r HEAD --name-only
    git ls-files

`-z` is only the separator, so a quoted path stays one path. It is not a
third listing.

A path in the tree and not in the index is INDEX-SHORT, one path per line.
Exit FAIL while any remain. A path in the index and not in the tree is
INDEX-ARMED, named, and also FAIL. That second set is the other direction.
It is not called disarmed. Equal sets are INDEX-MATCH, exit 0.

Read-only on the index it measures. Every git call carries
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


def git(root: Path, *args: str) -> tuple[int, str, str]:
  try:
    p = subprocess.run(
      ("git", "--no-optional-locks", *args),
      cwd=root, capture_output=True, text=True, env=clean_env(), check=False,
    )
  except FileNotFoundError:
    return DEAD, "", "git not found"
  return p.returncode, p.stdout, p.stderr


def names(root: Path, *args: str) -> tuple[set[str] | None, str]:
  rc, out, err = git(root, *args)
  if rc != 0:
    return None, f"rc={rc} {err.strip()}"
  return {part for part in out.split("\0") if part}, ""


def classify(root: Path) -> tuple[int, list[str]]:
  """Path-set difference of the two commands. Neither listing is written."""
  tree, err = names(root, "ls-tree", "-r", "-z", "--name-only", "HEAD")
  if tree is None:
    return DEAD, [f"INDEX-UNREAD ls-tree {err}"]
  index, err = names(root, "ls-files", "-z")
  if index is None:
    return DEAD, [f"INDEX-UNREAD ls-files {err}"]
  short = sorted(tree - index)
  armed = sorted(index - tree)
  lines = [f"INDEX-SHORT {path}" for path in short]
  lines += [f"INDEX-ARMED {path}" for path in armed]
  counts = f"ls-tree={len(tree)} ls-files={len(index)}"
  if lines:
    return FAIL, lines + [counts]
  return PASS, ["INDEX-MATCH", counts]


def listed(root: Path) -> list[str] | None:
  """`git ls-files` lines. The control is this count, which is `wc -l`."""
  rc, out, _err = git(root, "ls-files")
  if rc != 0:
    return None
  return [ln for ln in out.splitlines() if ln]


def index_file(root: Path) -> Path | None:
  rc, out, _err = git(root, "rev-parse", "--git-path", "index")
  if rc != 0:
    return None
  path = Path(out.strip())
  return path if path.is_absolute() else root / path


def index_id(root: Path) -> tuple[int, int, int, str] | None:
  """inode, size, mtime, sha256. A rewrite the path count cannot see."""
  path = index_file(root)
  if path is None:
    return None
  try:
    st = path.stat()
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
  except OSError:
    return None
  return st.st_ino, st.st_size, st.st_mtime_ns, digest


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
  return [ln for ln in lines if ln.startswith("INDEX-")]


def must(root: Path, *args: str) -> str | None:
  rc, _out, err = git(root, *args)
  if rc != 0:
    return f"{' '.join(args)} rc={rc} {err.strip()}"
  return None


def _expect(label: str, code: int, lines: list[str], want_code: int, want: list[str],
            bad: list[str]) -> None:
  got = verdict_lines(lines)
  print(f"PLANT {label} exit={code} {' | '.join(got)}")
  if code != want_code or got != want:
    bad.append(f"{label} expected {want} exit {want_code}, got exit={code} {got}")
  if any("DISARMED" in ln for ln in lines):
    bad.append(f"{label} called a direction disarmed")


def plant() -> int:
  """Temp repo only. A decoy index is inherited so a missed scrub cannot pass."""
  before = listed(ROOT)
  before_id = index_id(ROOT)
  if before is None or before_id is None:
    print("PLANT DEAD: could not read the real index")
    return DEAD
  bad: list[str] = []
  with tempfile.TemporaryDirectory(prefix="indexshort-") as raw:
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
    decoy_match = tmp / "decoy-match"
    decoy_match.write_bytes((repo / ".git" / "index").read_bytes())
    decoy_empty = tmp / "decoy-empty"
    decoy_empty.write_bytes(b"")

    code, lines = invoke(repo, decoy_empty)
    _expect("MATCH", code, lines, PASS, ["INDEX-MATCH"], bad)

    err = must(repo, "rm", "--cached", "-q", "--", "kept.rows")
    if err:
      print(f"PLANT DEAD: {err}")
      return DEAD
    if not (repo / "kept.rows").is_file():
      print("PLANT DEAD: rm --cached removed the worktree file")
      return DEAD
    rc, _out, _err = git(repo, "cat-file", "-e", "HEAD:kept.rows")
    if rc != 0:
      print("PLANT DEAD: kept.rows left the tree")
      return DEAD
    code, lines = invoke(repo, decoy_match)
    _expect("SHORT", code, lines, FAIL, ["INDEX-SHORT kept.rows"], bad)

    err = must(repo, "read-tree", "HEAD")
    if err:
      print(f"PLANT DEAD: {err}")
      return DEAD
    (repo / "extra.rows").write_text("y\n")
    err = must(repo, "add", "--", "extra.rows")
    if err:
      print(f"PLANT DEAD: {err}")
      return DEAD
    rc, _out, _err = git(repo, "cat-file", "-e", "HEAD:extra.rows")
    if rc == 0:
      print("PLANT DEAD: extra.rows is in HEAD; that is not the armed shape")
      return DEAD
    code, lines = invoke(repo, decoy_match)
    _expect("ARMED", code, lines, FAIL, ["INDEX-ARMED extra.rows"], bad)

    # Both directions in one run, so a gate that prints only the first cannot pass.
    err = must(repo, "rm", "--cached", "-q", "--", "kept.rows")
    if err:
      print(f"PLANT DEAD: {err}")
      return DEAD
    code, lines = invoke(repo, decoy_match)
    _expect("BOTH", code, lines, FAIL,
            ["INDEX-SHORT kept.rows", "INDEX-ARMED extra.rows"], bad)

  after = listed(ROOT)
  after_id = index_id(ROOT)
  if after is None or after_id is None:
    print("PLANT DEAD: could not re-read the real index")
    return DEAD
  same = before_id == after_id
  print(f"CONTROL ls-files before={len(before)} after={len(after)} "
        f"index-bytes={'same' if same else 'MOVED'}")
  if before != after:
    bad.append(f"CONTROL ls-files changed {len(before)} -> {len(after)}")
  if not same:
    bad.append("CONTROL real index bytes moved")
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
  code, lines = classify(root)
  for line in lines:
    print(line)
  return code


if __name__ == "__main__":
  sys.exit(main(sys.argv[1:]))
