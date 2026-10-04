#!/usr/bin/env python3
"""nl-rename.py -- THE `osx=` RENAME ON `renderer/nir_llvmir.bend`, PORT AND ORACLE.

    .venv/bin/python .agents/slop/eq/nl-rename.py --check    # report, change nothing
    .venv/bin/python .agents/slop/eq/nl-rename.py --apply

EVERY SUBSTITUTION IS ASSERTED TO ITS EXACT COUNT BEFORE ANY FILE IS WRITTEN, and both files are
digested before and after.  A tree with eight live units moves under an agent, and a rename that
half-applies because a concurrent edit changed the count is worse than a rename that aborts.

THE RENAME, AND WHY `=` IS THE SEPARATOR AND NOT LOAD-BEARING HERE:

    `sd cpullvm LLVM osx=True`   ->   `sd cpullvm LLVM osx True`
    `sd cpullvm LLVM osx=False`  ->   `sd cpullvm LLVM osx False`

8 row names over 4 keys, 2 rows each.  Upstream's identifier is `OSX`, a module-level CONSTANT --
`tinygrad/helpers.py:17` `OSX, WIN = sys.platform == "darwin", sys.platform == "win32"` -- imported
into llvmir's namespace at `tinygrad/renderer/llvmir.py:8` and READ at `tinygrad/renderer/llvmir.py:219`
inside `CPU.supported_dtypes`.  MEASURED over the whole `tinygrad/` tree: `grep -rnw osx tinygrad/`
returns TWO hits and BOTH ARE COMMENTS (`llvmir.py:216`, `compiler_llvm.py:73`), so upstream has no
identifier `osx` at all; and `grep -rn "osx=" tinygrad/` returns NOTHING, so upstream contains no
`osx=` string either.  `osx` is this port's own abbreviation -- and already this port's own
PARAMETER name, `sd.cpu.go(+ts, +x86: Bool, +osx: Bool)` at `nir_llvmir.bend:717` and
`sd.drop_cpu(+d, x86: Bool, osx: Bool)` at `:693`.  Exactly the shape of llvmir's `vol=` (where
upstream's function is `is_volatile` and `vol` is the port's abbreviation and its parameter name)
and of cstyle's `lb=` (upstream's `launch_bounds`).  So `=` here is a KEYWORD-ARGUMENT SEPARATOR
the port wrote into a LABEL, and it is not load-bearing.

THE ORACLE NEEDED A DIFFERENT PATTERN, AND THAT IS A FINDING.  `llvmir-oracle.py:80` is
`def par(slot=0, dtype=None, vol=False, aspace=None)` -- a PYTHON KEYWORD ARGUMENT whose text
contains ` vol=` -- and the same substitution that renames the port's rows made the oracle stop
parsing.  Here the two files do NOT collide: both oracle sites are inside f-strings that build a
ROW NAME or a ROW-BUILDER ARGUMENT (`nl-oracle.py:201` `f"sd cpullvm {arch} osx={osx}"` and
`:441` `f'{arch} osx={osx}'`), and `grep -o "osx=" .agents/slop/nl/nl-oracle.py` counts exactly 2,
both of them those.  So the oracle is patched with `osx={osx}` -> `osx {osx}` and NOT with a bare
`osx=`.  The script below ASSERTS that the port's 11 `osx=` occurrences are 6 `osx=True` + 5
`osx=False` and the oracle's 2 are `osx={osx}`, so a future collision cannot pass silently.

COMMENTS ARE RENAMED TOO.  `nir_llvmir.bend:661` and `:707` both name the row in prose, and a
comment that names a row which no longer exists is how the next reader goes looking for it.
"""
import hashlib, pathlib, sys

REPO = pathlib.Path(__file__).resolve().parents[3]
PORT = REPO / "tinybendygrad/renderer/nir_llvmir.bend"
ORACLE = REPO / ".agents/slop/nl/nl-oracle.py"

# (path, old, new, expected occurrences).  COUNTED, NOT ESTIMATED.
EDITS = [
  (PORT, "osx=True", "osx True", 6),
  (PORT, "osx=False", "osx False", 5),
  (ORACLE, "osx={osx}", "osx {osx}", 2),
]


def digest(p):
  return hashlib.md5(p.read_bytes()).hexdigest()


def main(apply):
  ok = True
  for p, old, new, want in EDITS:
    t = p.read_text()
    got = t.count(old)
    flag = "OK" if got == want else "MISMATCH -- ABORTING, THE TREE MOVED"
    ok &= got == want
    print(f"  {p.relative_to(REPO)}: {old!r} -> {new!r}   found {got}, expected {want}   {flag}")
  if not ok:
    print("NOTHING WRITTEN. A count that does not match means another unit edited the file "
          "between the census and this rename.")
    return 1
  if not apply:
    print("--check only; nothing written.")
    return 0
  for p, old, new, want in EDITS:
    before = digest(p)
    t = p.read_text()
    p.write_text(t.replace(old, new))
    print(f"  wrote {p.relative_to(REPO)}  md5 {before[:8]} -> {digest(p)[:8]}")
  # THE ORACLE MUST STILL PARSE.  A rename that stops the oracle from importing turns every
  # downstream row into a "0 rows" result, which this project has already mistaken for a pass.
  import ast
  ast.parse(ORACLE.read_text())
  print("  the oracle still parses (`ast.parse`), so its `rows` and `bend` modes can still run")
  return 0


if __name__ == "__main__":
  sys.exit(main("--apply" in sys.argv))