#!/usr/bin/env python3
"""nul-census-gate.py -- HOW MANY COMMITTED FILES CONTAIN A NUL, AND WHY DOES ONE OF
THEM KILL `prose()`?

THE QUESTION.  A brief reported "243 committed files contain NUL bytes".  That number is
a MEASUREMENT OF THE WRONG BYTES, and the instrument that makes the difference is the
finding:

  * a census that walks the tree with `open(path)` READS A SYMLINK'S TARGET, while the
    committed bytes of a symlink (mode `120000`) are its TARGET PATH -- a short ASCII
    string that cannot contain a NUL.  `git cat-file` reads the committed bytes.
    **196 of the 243 are mode `120000`.**  A population declared by "has a NUL" over a
    `os.walk` that follows links therefore counts 10 copies of a 145 MB `node` binary
    once each and calls them committed content.
  * of the 47 that are real committed blobs, **46 are binaries** -- `.pkl`, `.png`,
    `.jpg`, `.pdf`, `.wav`, `.npy`, `.ttf`, `.woff2`, `.gz`, and two Mach-O executables.
    A binary is CORRECT here.  A gate that went red on them would be a false alarm.
  * **1 is a TEXT file**, `tinybendygrad/runtime/ops_dsp.bend`, holding exactly ONE NUL
    -- and that file is the only thing in the tree that kills `prose()`.

AND THE SECOND QUESTION, WHICH IS THE HARD ONE.  Isolated, a synthetic NUL gives a
CAUGHT `tokenize.TokenError`, which `prose()` catches.  The real file gives an UNCAUGHT
`SystemError`.  The difference is NOT the byte and NOT its position:

    'a\\n<NUL line>\\n'      -> TokenError   CAUGHT    (no INDENT emitted)
    '    a\\n<NUL line>\\n'  -> SystemError  ESCAPES   (INDENT emitted)

**THE DISCRIMINATOR IS AN `INDENT` TOKEN.**  `tokenize.py:586-590` converts the C
tokenizer's `SyntaxError` into a `TokenError`, but ONLY if a `SyntaxError` reaches that
frame.  Once an `INDENT` has been emitted, the pending error surfaces inside
`TokenInfo._make(info)` at `tokenize.py:585` -- a `tuple.__new__` -- and CPython launders
it into `SystemError: <built-in method __new__ ...> returned a result with an exception
set`.  That is not a `SyntaxError`, so the conversion never fires, and `prose()`, which
catches `(tokenize.TokenError, IndentationError)`, lets it out.  The real diagnostic is
NOT lost: it is the `__cause__`, a `SyntaxError: source code cannot contain null bytes`.

FIVE CLAUSES, EACH WITH ITS OWN DENOMINATOR.  NONE IS A VERDICT ABOUT A BINARY:

  I    THE ARITHMETIC  disk-follows-links vs committed blobs, and the exact subtraction.
  II   THE DISTRIBUTION  by extension, by directory, and the NUL-COUNT BUCKETS.  The mean
                    is meaningless across 46 binaries and one 1-NUL source file.
  III  THE EXPOSURE SET  the files that can actually kill a text extractor, as a fraction
                    of the tracked TEXT population.
  IV   THE DISCRIMINATOR  the INDENT law, on the live file AND on the minimal two-line
                    plant, so the escape can never again be attributed to "the byte".
  V    THE EXPLANATION   whether the file documents its own byte.  A byte nobody can
                    explain is a stray character; a byte the file explains four times is
                    a decision, and the remedy for a decision is not to delete it.

READ-ONLY.  It writes nothing but its own scratch under `mkdtemp()`.  It loads
`checks/cites-census.py` BY PATH -- `gates/` is not a package, and putting it on
`sys.path` would make `cites_census` a name any file in the tree could shadow.

EXIT: PASS 0, FAIL 1, REFUSED 3, SKIP 4, DEAD 5.
"""

from __future__ import annotations

import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import tokenize
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PASS, FAIL, REFUSED, SKIP, DEAD = "PASS", "FAIL", "REFUSED", "SKIP", "DEAD"
EXITS = {PASS: 0, FAIL: 1, REFUSED: 3, SKIP: 4, DEAD: 5}

DECLARED_SOURCE = ROOT / "checks/cites-census.py"

# THE ONE FILE THAT MATTERS IS NAMED, NOT DISCOVERED BY SUFFIX.  A population declared by
# `*.bend` is Doctrine 1's suffix set; a census of NULs is a census of BYTES and every
# byte in HEAD is in it.  This constant names the SUBJECT of clause V, not its population.
WITNESS = "tinybendygrad/runtime/ops_dsp.bend"

# WHAT COUNTS AS "BLOB BYTES": the C0 control range minus TAB, LF, CR, FF and VT, plus
# DEL.  A LONGEST-RUN over this class separates a text file carrying a pasted binary blob
# from a text file carrying a stray control character -- two different problems with two
# different remedies.
BLOB = re.compile(rb"[\x00-\x08\x0b\x0e-\x1f\x7f]+")


def load_census():
  """`checks/cites-census.py` BY PATH.  Absent -> the caller REFUSES, naming the file."""
  spec = importlib.util.spec_from_file_location("cites_census_by_path", DECLARED_SOURCE)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def head_tree() -> dict[str, tuple[str, str]]:
  """{path: (mode, sha)} from `git ls-tree -r HEAD`.  NOT `git ls-files`, which reads the
  INDEX, and this repo arms that index with intent-to-add placeholders by design
  (`jj git colocation`): it answers for hundreds of paths HEAD does not contain while
  `git diff --cached` names 0.  The MODE is kept because mode `120000` IS the finding."""
  r = subprocess.run(["git", "ls-tree", "-r", "HEAD"], cwd=ROOT,
                     capture_output=True, text=True)
  if r.returncode != 0:
    raise RuntimeError(f"git ls-tree rc={r.returncode}: {r.stderr.strip()}")
  out = {}
  for line in r.stdout.splitlines():
    meta, _sep, path = line.partition("\t")
    mode, _typ, sha = meta.split()
    out[path] = (mode, sha)
  return out


def blob_nuls(shas: list[str]) -> dict[str, int]:
  """{path: NUL count} over the COMMITTED BYTES of `shas`, via ONE `git cat-file --batch`.

  The bytes come from stdin and go to stdout as FILES.  Piping both ways from one
  process deadlocks the moment git's stdout buffer fills -- measured here, 300 s to
  timeout, before it was a file."""
  if not shas:
    return {}
  tree = head_tree()
  by_sha = {sha: path for path, (_m, sha) in tree.items()}
  with tempfile.TemporaryDirectory(prefix="nulcensus-") as tmp:
    sin, sout = Path(tmp) / "shas", Path(tmp) / "batch"
    sin.write_text("".join(s + "\n" for s in shas))
    with sin.open("rb") as i, sout.open("wb") as o:
      subprocess.run(["git", "cat-file", "--batch"], cwd=ROOT, stdin=i, stdout=o, check=True)
    got, f = {}, sout.open("rb")
    while (hdr := f.readline()):
      parts = hdr.split()
      if len(parts) < 3:
        continue
      sha, size = parts[0].decode(), int(parts[2])
      n = f.read(size).count(b"\x00")
      f.read(1)
      if n and sha in by_sha:
        got[by_sha[sha]] = n
    f.close()
    return got


def classify(raw: bytes) -> tuple[bool, int]:
  """(is UTF-8 text, longest run of blob bytes).  THE THREE-WAY SPLIT:

    not UTF-8                                  -> A, a BINARY.  Correct to be here.
    UTF-8 with a run of >= 8 blob bytes        -> B, TEXT WITH A BINARY CHUNK.
    UTF-8 with scattered blob bytes            -> C, TEXT WITH A STRAY CONTROL CHARACTER.

  Three problems, three remedies: exclude the extension, quarantine the file, strip the
  byte.  Which remedy is right is a question ABOUT THE CLASS, so the class is measured
  before anything is proposed."""
  try:
    raw.decode("utf-8")
    utf8 = True
  except UnicodeDecodeError:
    utf8 = False
  return utf8, max((len(m.group()) for m in BLOB.finditer(raw)), default=0)


def extname(path: str) -> str:
  """The extension of the LAST segment, or `""`.  A dot in a DIRECTORY is not one."""
  base = path.rsplit("/", 1)[-1]
  return base.rsplit(".", 1)[-1] if "." in base else "(none)"


def walk_nuls() -> tuple[dict[str, int], int]:
  """({relpath: NUL count}, symlinks skipped) over the WORKING TREE.

  `os.walk` + `endswith`, never `glob` -- `glob('*.bend')` returns `[]` with `.bend`
  files on disk, tracked, 1,890 lines.  Symlinks are SKIPPED, not followed: following
  them is the defect this gate exists to name, and a census that cannot measure the
  defect it is about is not a census."""
  got, links = {}, 0
  for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d != ".git"]
    for fn in filenames:
      fp = Path(dirpath) / fn
      if fp.is_symlink():
        links += 1
        continue
      try:
        raw = fp.read_bytes()
      except OSError:
        continue
      n = raw.count(b"\x00")
      if n:
        got[str(fp.relative_to(ROOT))] = n
  return got, links


# ------------------------------------------------------------------ the discriminator

def raises(text: str) -> tuple[str, bool, str]:
  """(exception name, whether an INDENT was emitted, the `__cause__` message).

  MEASURED, NOT ASSUMED.  `prose()` is the extractor under audit, but the discriminator
  lives in `tokenize`, so it is measured against `tokenize` directly -- a probe that went
  through `prose()` could not tell `prose()`'s narrow `except` from the tokenizer's
  laundering, which is the whole point."""
  indented = False
  try:
    for tok in tokenize.generate_tokens(iter(text.splitlines(True)).__next__):
      if tok.type == tokenize.INDENT:
        indented = True
  except BaseException as e:  # noqa: BLE001 -- the point is that it ESCAPES
    cause = e.__cause__
    return type(e).__name__, indented, (str(cause) if cause is not None else "")
  return "no-exception", indented, ""


# THE PLANT.  TWO LINES.  THE SAME NUL, THE SAME LINE, THE SAME BYTES -- the ONLY
# difference is whether the PRECEDING line opens an indented block.  Written as a law
# (`SystemError` iff `INDENT`) rather than as a transcribed pair of exception names, so it
# keeps its teeth on an interpreter that launders the error differently: it FAILS, loudly,
# instead of silently reporting that the trap is gone.
def indent_law() -> list[tuple[str, str]]:
  nul_line = 'x = "b\x00"\n'
  arms = []
  for label, head in [("no INDENT  ", "a\n"), ("INDENT    ", "    a\n")]:
    name, indented, cause = raises(head + nul_line)
    arms.append((label, name, indented, cause))
  return arms


def selftest() -> int:  # noqa: C901 -- five plants, each written to be able to fail
  """THE HARNESS COMES FIRST.  A plant that cannot fail reports success while measuring
  nothing, which is how a prior plant 'made the lane emit nothing while the check scored
  it as a successful plant'."""
  cases = []
  with tempfile.TemporaryDirectory(prefix="nulselftest-") as tmp:
    d = Path(tmp)

    # P1 FORWARD -- A SYMLINK IS NOT ITS TARGET.  Build the exact shape that produced
    # 243-from-47: a link into a NUL-bearing binary.  If `open()` and the committed blob
    # agreed, this reports 1 and 1 and the gate's whole first clause is void.
    (d / "big.bin").write_bytes(b"\x7fELF" + b"\x00" * 4096)
    (d / "link").symlink_to(d / "big.bin")
    followed = sum(1 for p in d.iterdir()
                   if not p.is_symlink() and b"\x00" in p.read_bytes())
    linked = sum(1 for p in d.iterdir()
                 if p.is_symlink() and b"\x00" in p.read_bytes())
    cases.append(("P1 FORWARD : following a link reads the TARGET's NULs; the blob is a PATH",
                  (followed, linked), (1, 1)))

    # P2 REVERSE -- A REAL TEXT FILE WITH A NUL IS NOT DISMISSED BY P1.  The gate must
    # keep the honest case after explaining away the artefact, or the explanation becomes
    # the excuse.  Longest-run decides the class, so both classes are planted.  The
    # assertion is a PROPERTY of each class -- "at or above the chunk threshold" against
    # "below it" -- because a transcribed run length is a number copied from the shape of
    # the fixture, and an earlier revision of this block copied one and FAILED.
    (d / "chunk.txt").write_bytes(b"text\n" + b"\x00" * 8 + b"more\n")
    (d / "stray.txt").write_bytes(b"text\none\n" + b"\x00" + b"\n")
    chunk = classify((d / "chunk.txt").read_bytes())
    stray = classify((d / "stray.txt").read_bytes())
    cases.append(("P2 REVERSE : both are TEXT, only one is a BINARY CHUNK",
                  (chunk[0], stray[0], chunk[1] >= 8, stray[1] < 8),
                  (True, True, True, True)))

    # P3 THE DISCRIMINATOR -- the plant that can fail.  Asserts the LAW and that the two
    # arms DISAGREE, so a CPython that stops laundering turns this into a FAIL ("re-
    # measure") rather than a silent pass.
    arms = indent_law()
    law = all((name == "SystemError") == indented for _l, name, indented, _c in arms)
    differ = arms[0][1] != arms[1][1]
    cases.append(("P3 LAW : SystemError iff an INDENT was emitted", law, True))
    cases.append(("P3 CONTROL : the two arms DISAGREE (the trap is still open here)",
                  differ, True))
    # THE ARMS ARE NOT SYMMETRIC IN WHAT THEY KEEP, and asserting symmetry was this
    # block's first FAIL.  `tokenize.py:590` raises the `TokenError` `from None`, so the
    # CAUGHT arm DISCARDS the message and answers `('source code cannot contain null
    # bytes', (1, 0))` with a position that is not the NUL's.  The ESCAPING arm keeps it,
    # because the `SystemError` is raised by `tuple.__new__` and chains to the original
    # `SyntaxError`.  So the one arm nobody catches is the only arm that says WHERE.
    by_label = {l: (n, c) for l, n, _i, c in arms}
    cases.append(("P3 CONTROL : the CAUGHT arm DISCARDS the position, the ESCAPING arm KEEPS it",
                  (by_label["no INDENT  "][1], "null bytes" in by_label["INDENT    "][1]),
                  ("", True)))

    # P4 THE LIVE FILE -- the real subject, read from the WORKING TREE and cross-checked
    # against HEAD's blob, so a dirty working copy cannot quietly turn a FAIL into a pass.
    if not (ROOT / WITNESS).is_file():
      cases.append((f"P4 LIVE : {WITNESS} is present", False, True))
    else:
      body = (ROOT / WITNESS).read_text(errors="replace")
      name, indented, cause = raises(body)
      raised = name != "no-exception"
      says_why = "null bytes" in cause
      in_head = blob_nuls([head_tree()[WITNESS][1]]) if WITNESS in head_tree() else {}
      cases.append((f"P4 LIVE : the real file raises and says WHY ({WITNESS})",
                    (raised, indented, says_why, bool(in_head)), (True, True, True, True)))

    # P5 THE EXPLANATION -- a byte the file explains four times is a DECISION.  Assert the
    # file still carries its own account, so "strip it" can never be proposed by someone
    # who has not read it.  Fails the moment the notes and the byte disagree.  GUARDED,
    # because a plant that raises FileNotFoundError is a DEAD lane, and a DEAD lane is a
    # verdict nobody writes down: found by running this file from outside the repo.
    if (ROOT / WITNESS).is_file():
      notes = (ROOT / WITNESS).read_text(errors="replace")
      said = notes.count("NUL") + notes.count("\x00")
      cases.append(("P5 EXPLANATION : the file accounts for its own NUL byte", said >= 5, True))
    else:
      cases.append((f"P5 EXPLANATION : {WITNESS} is present to explain itself", False, True))

  fails = 0
  for why, got, want in cases:
    ok = got == want
    fails += not ok
    print(f"[{'   PASS' if ok else '   FAIL'}] {why}\n          got {got!r}, want {want!r}")
  print(f"\n=== selftest {'PASS' if not fails else 'FAIL'}: {len(cases)} case(s) run, "
        f"{fails} failed ===")
  return EXITS[PASS if not fails else FAIL]


def main() -> int:  # noqa: C901 -- five clauses, one pass each
  print(" ".join(__doc__.split("\n\n")[0].split()))
  if "--selftest" in sys.argv:
    return selftest()
  try:
    cites = load_census()
  except FileNotFoundError:
    print(f"{REFUSED}: {DECLARED_SOURCE.relative_to(ROOT)} is gone -- it IS the extractor "
          "under audit, and a gate cannot measure an extractor it cannot load")
    return EXITS[REFUSED]

  tree = head_tree()
  head = subprocess.run(["git", "rev-parse", "--short=12", "HEAD"], cwd=ROOT,
                        capture_output=True, text=True).stdout.strip()
  on_disk, links_skipped = walk_nuls()
  in_head = blob_nuls([sha for _m, sha in tree.values()])

  # ---- I. THE ARITHMETIC ----------------------------------------------------
  print(f"\nHEAD : {head}")
  print("\n--- I. THE ARITHMETIC: the SAME paths, read two ways ---")
  # ONE POPULATION, TWO READS.  Both sides start from `git ls-tree -r HEAD`, so the only
  # variable is HOW A PATH IS READ: `open()` follows a symlink to its TARGET, while
  # `git cat-file` reads the committed BLOB, which for mode `120000` is the target PATH.
  followed, memo = {}, {}
  for rel, (mode, _sha) in tree.items():
    fp = ROOT / rel
    if mode == "120000":
      try:
        real = str(fp.resolve())
      except OSError:
        continue
      if real not in memo:                       # 10 links -> ONE 145 MB read
        try:
          memo[real] = (ROOT / rel).read_bytes().count(b"\x00")
        except OSError:
          memo[real] = 0
      n = memo[real]
    else:
      try:
        n = fp.read_bytes().count(b"\x00")
      except OSError:
        continue
    if n:
      followed[rel] = n
  links = [p for p in followed if tree[p][0] == "120000"]
  print(f"  committed entries                    : {len(tree)}")
  print(f"  A. same paths, read with `open()`    : {len(followed)}"
        f"   ({len(followed) - len(links)} files + {len(links)} links)")
  print(f"  B. same paths, read as committed blobs: {len(in_head)}")
  exact = len(followed) - len(links) == len(in_head)
  print(f"  A - {len(links)} = {len(followed) - len(links)}   vs   B = {len(in_head)}"
        + ("   <- IDENTICAL" if exact else "   <- DIVERGES"))
  print(f"  links skipped by this gate's own walk : {links_skipped}"
        f"   (whole-disk walk, incl. untracked: {len(on_disk)} files with a NUL)")
  print("  -> THE 243 IS A READ BUG, NOT A TREE FACT.  `open()` FOLLOWS A LINK; a")
  print("     symlink's COMMITTED BYTES are its target PATH, which cannot hold a NUL.")

  # ---- II. THE DISTRIBUTION ------------------------------------------------
  print("\n--- II. THE DISTRIBUTION: buckets, not a mean ---")
  buckets = [("==1", lambda n: n == 1), ("2..99", lambda n: 2 <= n <= 99),
             ("100..9999", lambda n: 100 <= n <= 9999),
             ("10k..999,999", lambda n: 10_000 <= n <= 999_999),
             (">=1,000,000", lambda n: n >= 1_000_000)]
  for label, pred in buckets:
    print(f"  {label:>12s} : {sum(1 for n in in_head.values() if pred(n)):5d} file(s)")
  print("  BY EXTENSION  : " + ", ".join(
    f"{e}={n}" for e, n in Counter(extname(p) for p in in_head).most_common(12)))
  print("  BY DIRECTORY  : " + ", ".join(
    f"{d}={n}" for d, n in Counter(p.split("/", 1)[0] for p in in_head).most_common(8)))
  print(f"  TOTAL NUL BYTES in blobs: {sum(in_head.values()):,}")

  # ---- III. THE EXPOSURE SET -----------------------------------------------
  print("\n--- III. THE EXPOSURE SET: which of them can kill a TEXT extractor? ---")
  kinds, exposure = Counter(), []
  for rel in sorted(in_head):
    raw = subprocess.run(["git", "cat-file", "blob", f"HEAD:{rel}"], cwd=ROOT,
                         capture_output=True).stdout
    utf8, run = classify(raw)
    kind = "A-binary" if not utf8 else ("B-text+binary-chunk" if run >= 8 else "C-text+stray-control")
    kinds[kind] += 1
    if utf8:
      exposure.append((rel, in_head[rel], run))
  tracked = len(tree)
  print(f"  A binary, NOT UTF-8                  : {kinds['A-binary']:5d}   -> exclude the EXTENSION")
  print(f"  B text carrying a binary chunk       : {kinds['B-text+binary-chunk']:5d}   -> QUARANTINE the file")
  print(f"  C text carrying a stray control char : {kinds['C-text+stray-control']:5d}   -> strip the BYTE (or do not)")
  print(f"  EXPOSURE SET (B+C) = {len(exposure)} of {tracked} committed entries")
  for rel, n, run in exposure:
    print(f"      {n:,} NUL, longest run {run}  {rel}")
  print("  -> A BINARY WITH A NUL IS CORRECT AND IS NOT A FINDING.")

  # ---- IV. THE DISCRIMINATOR ------------------------------------------------
  print("\n--- IV. THE DISCRIMINATOR: not the byte -- an INDENT token ---")
  arms = indent_law()
  for label, name, indented, cause in arms:
    print(f"  {label} -> {name:12s} INDENT={str(indented):5s} cause={cause or '-'}")
  print(f"  live {WITNESS}: ", end="")
  live_name, live_ind, live_cause = raises((ROOT / WITNESS).read_text(errors="replace"))
  print(f"{live_name}  INDENT={live_ind}  cause={live_cause or '-'}")
  print("  `tokenize.py:586-590` turns the C tokenizer's `SyntaxError` into a `TokenError`")
  print("  ONLY if a `SyntaxError` reaches that frame.  With an INDENT emitted the pending")
  print("  error surfaces inside `TokenInfo._make(info)` at `tokenize.py:585` -- a")
  print("  `tuple.__new__` -- and is laundered to `SystemError`, so the conversion never")
  print("  fires and `prose()`, catching `(TokenError, IndentationError)`, lets it out.")
  print("  IS `prose()` REACHED, AND DOES IT ACTUALLY DIE?  MEASURED, NOT ASSUMED:")
  try:
    cites.prose(WITNESS, (ROOT / WITNESS).read_text(errors="replace"))
    escaped = "no-exception"
  except (tokenize.TokenError, IndentationError) as e:
    escaped = f"CAUGHT {type(e).__name__}"
  except BaseException as e:  # noqa: BLE001 -- the point is that it ESCAPES `prose()`
    escaped = f"ESCAPED {type(e).__name__}"
  print(f"    prose({WITNESS}) -> {escaped}")

  # ---- V. THE EXPLANATION ---------------------------------------------------
  print("\n--- V. THE EXPLANATION: is the byte explained where it lives? ---")
  if not exposure:
    print("  no committed text file carries a NUL: nothing to explain")
  else:
    body = (ROOT / exposure[0][0]).read_text(errors="replace")
    said = [ln.strip() for ln in body.splitlines() if "NUL" in ln or "\x00" in ln]
    print(f"  {exposure[0][0]} accounts for it {len(said)} time(s), e.g.:")
    for ln in said[:3]:
      print(f"      {ln[:110]}")

  # ---- VERDICT -------------------------------------------------------------
  killed = escaped.startswith("ESCAPED") if exposure else False
  print(f"\nVERDICT: {FAIL if killed else PASS} -- {len(exposure)} committed TEXT file(s) "
        f"carry a NUL; {escaped} from `prose()` on {'; '.join(r for r, _n, _u in exposure) or 'none'}")
  print("  A BINARY CARRYING A NUL IS NOT COUNTED AGAINST THIS TREE.  THE VERDICT IS")
  print("  ABOUT THE EXTRACTOR DYING, NOT ABOUT THE BYTES BEING THERE.")
  return EXITS[FAIL if killed else PASS]


if __name__ == "__main__":
  sys.exit(main())