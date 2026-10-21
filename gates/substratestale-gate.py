#!/usr/bin/env python3
"""substratestale-gate.py -- does the recorded substrate-end still name this tree?

    .venv/bin/python gates/substratestale-gate.py
    .venv/bin/python gates/substratestale-gate.py --plant

The verdict is the digest, not the commit. A commit that does not change the
hashed trees leaves HEAD ahead of substrate-head while the imported
substrate_digest() still equals substrate-end. That is CURRENT. HEAD is
printed so the ahead-ness is visible; it is not the verdict.

CURRENT   digest == substrate-end                         exit 0
STALE     digest != substrate-end                         exit 1
REFUSED   summary absent, row absent, or a process is
          executing differ.py                             exit 3

Does not run differ.py. A stale result names both digests and stops.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import NamedTuple

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SUMMARY = ROOT / "runs" / "graphcmp" / "D" / "D0-run-summary.txt"
RUN_DIR = ROOT / "runs" / "graphcmp"
DIFFER = ROOT / "checks" / "differ.py"
INJECTED = "ab" * 32

sys.path.insert(0, str(HERE))
from gatekit import FAIL, PASS, REFUSED  # noqa: E402


class Answer(NamedTuple):
  word: str
  code: int
  why: str
  lines: tuple[str, ...]


def under_run(path: Path) -> bool:
  try:
    path.resolve().relative_to(RUN_DIR.resolve())
  except ValueError:
    return False
  return True


def _script_of(argv: list[str]) -> str | None:
  """The file an interpreter was asked to run, or None for -c / -m."""
  takes = {"-W", "-X"}
  i = 1
  while i < len(argv):
    tok = argv[i]
    if tok in {"-c", "-m"}:
      return None
    if tok == "--":
      return argv[i + 1] if i + 1 < len(argv) else None
    if tok in takes:
      i += 2
      continue
    if tok.startswith("-"):
      i += 1
      continue
    return tok
  return None


def differ_executing() -> tuple[str | None, str | None]:
  """(ps line, error). A hit is a process executing differ.py, not one naming it.

  `ps | grep differ.py` matches `wc checks/differ.py` and `git log -- checks/differ.py`.
  Those are not corpus runs and they are not writing runs/graphcmp/.
  """
  try:
    proc = subprocess.run(["ps", "-Ao", "pid=,args="], capture_output=True, text=True, check=False)
  except OSError as exc:
    return None, f"ps:{exc}"
  if proc.returncode != 0:
    return None, f"ps:rc={proc.returncode}"
  me = os.getpid()
  for raw in proc.stdout.splitlines():
    line = raw.strip()
    if not line:
      continue
    pid_s, _, cmd = line.partition(" ")
    try:
      pid = int(pid_s)
    except ValueError:
      continue
    if pid == me:
      continue
    argv = cmd.split()
    if not argv:
      continue
    head = Path(argv[0]).name
    if head == "differ.py" or argv[0].endswith("/differ.py"):
      return line, None
    if head.startswith("python"):
      script = _script_of(argv)
      if script is not None and Path(script).name == "differ.py":
        return line, None
  return None, None


def guard(path: Path) -> str | None:
  """Why `path` must not be opened, or None. Checked before any read of the artifact."""
  if not under_run(path):
    return None
  hit, err = differ_executing()
  if err:
    return f"differ-unknown:{err}"
  return hit


def rows_of(text: str) -> dict[str, str]:
  out: dict[str, str] = {}
  for line in text.splitlines():
    key, sep, val = line.partition("=")
    if sep and re.fullmatch(r"[A-Za-z0-9-]+", key):
      out[key] = val
  return out


def judge(summary: Path, live: str, *, running: bool) -> Answer:
  """Compare `live` to the copy's substrate-end. `running` is checked first and reads nothing."""
  if running:
    return Answer("REFUSED", REFUSED, "differ-running", ())
  if not summary.is_file():
    return Answer("REFUSED", REFUSED, "artifact-absent", (f"path={summary}",))
  try:
    text = summary.read_text()
  except OSError as exc:
    return Answer("REFUSED", REFUSED, "unreadable", (f"path={summary}", f"err={exc}"))
  recorded = rows_of(text).get("substrate-end")
  if recorded is None:
    return Answer("REFUSED", REFUSED, "substrate-end-absent", (f"path={summary}",))
  lines = (f"live={live}", f"substrate-end={recorded}")
  if recorded == live:
    return Answer("CURRENT", PASS, "", lines)
  return Answer("STALE", FAIL, "", lines)


def load_differ():
  """The tree's own substrate_digest, by path. The hash is not reimplemented here."""
  spec = importlib.util.spec_from_file_location("substratestale_differ", DIFFER)
  if spec is None or spec.loader is None:
    return None
  mod = importlib.util.module_from_spec(spec)
  sys.modules[spec.name] = mod
  spec.loader.exec_module(mod)
  return mod


def fingerprint(path: Path) -> str:
  if not path.is_file():
    return "ABSENT"
  return hashlib.sha256(path.read_bytes()).hexdigest()


def flip_hex_digit(digest: str) -> str:
  alphabet = "0123456789abcdef"
  nxt = alphabet[(alphabet.index(digest[0]) + 1) % 16]
  return nxt + digest[1:]


def with_end(base: str | None, digest: str) -> str:
  if base is None:
    return f"substrate-end={digest}\nsubstrate-head=plant\n"
  out: list[str] = []
  seen = False
  for line in base.splitlines():
    if line.startswith("substrate-end="):
      out.append(f"substrate-end={digest}")
      seen = True
    else:
      out.append(line)
  if not seen:
    out.append(f"substrate-end={digest}")
  return "\n".join(out) + "\n"


def expect(judge_fn, base: str | None, root: Path) -> list[str]:
  """The three file directions, plus the running-guard. One function, so a mutant cannot pass a copy."""
  injected = INJECTED
  flipped = flip_hex_digit(injected)
  current = root / "current.txt"
  stale = root / "stale.txt"
  current.write_text(with_end(base, injected))
  stale.write_text(with_end(base, flipped))
  missing = root / "no-such-summary.txt"
  bad: list[str] = []
  got = judge_fn(current, injected, running=False)
  if (got.word, got.code) != ("CURRENT", PASS):
    bad.append(f"current read {got.word} exit={got.code}")
  elif injected not in " ".join(got.lines):
    bad.append("current omitted digests")
  got = judge_fn(stale, injected, running=False)
  stale_lines = " ".join(got.lines)
  if (got.word, got.code) != ("STALE", FAIL):
    bad.append(f"stale read {got.word} exit={got.code}")
  elif injected not in stale_lines or flipped not in stale_lines:
    bad.append("stale omitted digests")
  got = judge_fn(missing, injected, running=False)
  if (got.word, got.code, got.why) != ("REFUSED", REFUSED, "artifact-absent"):
    bad.append(f"missing read {got.word} exit={got.code} why={got.why}")
  # The file would be CURRENT if read. REFUSED/differ-running is the proof it was not.
  got = judge_fn(current, injected, running=True)
  if (got.word, got.code, got.why) != ("REFUSED", REFUSED, "differ-running"):
    bad.append(f"running read {got.word} exit={got.code} why={got.why}")
  return bad


def _stuck(word: str, code: int):
  def _judge(summary: Path, live: str, *, running: bool) -> Answer:
    return Answer(word, code, "", ())
  return _judge


def _ignore_running(summary: Path, live: str, *, running: bool) -> Answer:
  return judge(summary, live, running=False)


def head_fact(recorded: str, head: str) -> str:
  """Printed only. Never consulted by the exit."""
  if not recorded or recorded == "ABSENT":
    return "unrecorded"
  if recorded == head:
    return "equal"
  ahead = subprocess.run(
    ["git", "merge-base", "--is-ancestor", recorded, head],
    cwd=ROOT, capture_output=True, text=True, check=False)
  if ahead.returncode == 0:
    return "HEAD-ahead"
  behind = subprocess.run(
    ["git", "merge-base", "--is-ancestor", head, recorded],
    cwd=ROOT, capture_output=True, text=True, check=False)
  if behind.returncode == 0:
    return "HEAD-behind"
  return "not-ancestor"


def plant(summary: Path, *, speak: bool) -> int:
  """Copies only. Does not load differ.py and does not write the live artifact."""
  if "substratestale_differ" in sys.modules:
    print("plant: FAIL -- differ.py already loaded")
    return FAIL
  blocked = guard(summary)
  if blocked:
    print("substratestale: REFUSED")
    print("why=differ-running" if not blocked.startswith("differ-unknown") else f"why={blocked}")
    if not blocked.startswith("differ-unknown"):
      print(f"process={blocked}")
    return REFUSED
  before = fingerprint(summary)
  base = summary.read_text() if summary.is_file() else None
  flipped = flip_hex_digit(INJECTED)
  flip_digits = sum(a != b for a, b in zip(INJECTED, flipped, strict=True))
  mutants = (
    ("always-CURRENT", _stuck("CURRENT", PASS)),
    ("always-STALE", _stuck("STALE", FAIL)),
    ("always-REFUSED", _stuck("REFUSED", REFUSED)),
    ("ignore-running", _ignore_running),
  )
  with tempfile.TemporaryDirectory(prefix="substratestale-") as tmp:
    root = Path(tmp)
    real = expect(judge, base, root)
    caught = [(name, expect(fn, base, root)) for name, fn in mutants]
  after = fingerprint(summary)
  unbroken = before == after
  invoked = "substratestale_differ" in sys.modules
  if speak:
    print(f"plant\tinjected={INJECTED}")
    print(f"plant\tflipped={flipped}\tflip-digits={flip_digits}")
    print(f"plant\tcase=current-stale-missing-running\tfailures={len(real)}")
    for item in real:
      print(f"plant\tFAIL\t{item}")
    print(f"control\tbefore={before}\tafter={after}\tverdict={'UNBROKEN' if unbroken else 'MOVED'}")
    for name, bad in caught:
      print(f"falsify\tmutant={name}\tcaught={'yes' if bad else 'no'}\tby={' | '.join(bad) if bad else '-'}")
    print(f"differ-invoked={'yes' if invoked else 'no'}")
  held = (
    not real and unbroken and not invoked and flip_digits == 1
    and all(bad for _, bad in caught)
  )
  if not held:
    if not speak:
      print(f"plant: FAIL failures={len(real)} unbroken={unbroken} differ-invoked={invoked} flip-digits={flip_digits}")
      for item in real:
        print(f"plant\tFAIL\t{item}")
    print("substratestale-plant: FAIL")
    return FAIL
  if not speak:
    print("plant=OK")
  else:
    print("substratestale-plant: PASS")
  return PASS


def emit_blocked(reason: str) -> None:
  print("substratestale: REFUSED")
  if reason.startswith("differ-unknown"):
    print(f"why={reason}")
    return
  print("why=differ-running")
  print(f"process={reason}")


def live(summary: Path) -> int:
  blocked = guard(summary)
  if blocked:
    emit_blocked(blocked)
    return REFUSED
  if not summary.is_file():
    print("substratestale: REFUSED")
    print("why=artifact-absent")
    print(f"path={summary}")
    return REFUSED
  differ = load_differ()
  digest_fn = getattr(differ, "substrate_digest", None) if differ is not None else None
  if digest_fn is None:
    print("substratestale: REFUSED")
    print("why=substrate_digest-unloadable")
    print(f"path={DIFFER}")
    return REFUSED
  try:
    text = summary.read_text()
  except OSError as exc:
    print("substratestale: REFUSED")
    print("why=unreadable")
    print(f"path={summary}")
    print(f"err={exc}")
    return REFUSED
  parsed = rows_of(text)
  if "substrate-end" not in parsed:
    print("substratestale: REFUSED")
    print("why=substrate-end-absent")
    print(f"path={summary}")
    return REFUSED
  live_digest = digest_fn()
  ans = judge(summary, live_digest, running=False)
  head = differ.substrate_head()
  recorded_head = parsed.get("substrate-head", "ABSENT")
  print(f"substratestale: {ans.word}")
  for line in ans.lines:
    print(line)
  print(f"HEAD={head}")
  print(f"substrate-head={recorded_head}")
  print(f"head-fact={head_fact(recorded_head, head)}")
  print("walks=" + ",".join(differ.SUBSTRATE_WALKS))
  print("inputs=" + ",".join(differ.SUBSTRATE_INPUTS))
  print(f"digest-fn={differ.__file__}:substrate_digest")
  return ans.code


def main(argv: list[str] | None = None) -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--plant", action="store_true", help="plant on copies; do not judge the live artifact")
  ap.add_argument("--summary", type=Path, default=SUMMARY)
  args = ap.parse_args(argv)
  summary = args.summary if args.summary.is_absolute() else ROOT / args.summary
  if args.plant:
    return plant(summary, speak=True)
  if plant(summary, speak=False) != PASS:
    print("substratestale: REFUSED")
    print("why=plant-failed")
    return REFUSED
  return live(summary)


if __name__ == "__main__":
  sys.exit(main())
