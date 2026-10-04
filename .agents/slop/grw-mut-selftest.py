#!/usr/bin/env python3
"""grw-mut-selftest.py -- show the mutation harness FAILING, three ways.

"A mutation number is only evidence if the harness has been shown to fail once"
(agent-core.md).  `grw-mut.py` checks four things before it prints a number, and
this script feeds it three deliberately broken mutations to show each check
firing.  Without this, "9 mutations, 0 blind spots" is a claim about a harness
nobody has watched reject anything.

  D1  a pattern that is NOT IN THE FILE       -> FATAL PATTERN NOT PRESENT
  D2  a replacement that does NOT TYPECHECK    -> FATAL MUTANT DOES NOT TYPECHECK
  D3  a replacement that RENAMES THE ROWS      -> FATAL DIFFERENT SET OF ROW NAMES

D2 IS A CHECK THIS HARNESS WAS MISSING, and finding it is the point of the
exercise: the first version gated on the mutant's `--check-only` output
CONTAINING this file's name, and a mutant with an undefined callee reported the
error somewhere else, so the check passed and the mutant's EMPTY output was
reported as "moved 0 rows" -- a blind spot where the truth was "did not run".
The gate is now on `ALL PROOFS CHECK` being PRINTED, and this script is what
keeps that honest.

Run:  python3 .agents/slop/grw-mut-selftest.py
Exit 0 only if all three were rejected AND the file was restored.
"""
import contextlib
import io
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
ROOT = HERE.parent.parent
TARGET = ROOT / "tinybendygrad" / "codegen" / "__init__.bend"

import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location("grwmut", HERE / "grw-mut.py")
grwmut = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(grwmut)

DEMOS = [
    ("D1", "a pattern that is not in the file", False,
     "def unified_rewrite.same(+prev: U32, w: Rewritten) -> Bool: <NOT IN THE FILE>",
     "def unified_rewrite.same(+prev: U32, w: Rewritten) -> Bool: U32.is_eq(prev, Rewritten.index(w, prev))",
     "PATTERN NOT PRESENT"),
    ("D2", "a replacement that does not typecheck", True,
     "def Rewritten.capped(w: Rewritten) -> Bool: match w: case Rewritten{ar, sink, repl, passes, capped}: capped",
     "def Rewritten.capped(w: Rewritten) -> Bool: match w: case Rewritten{ar, sink, repl, passes, capped}: NoSuchDef(1)",
     "MUTANT DOES NOT TYPECHECK"),
    ("D3", "a replacement that renames the rows, so the mutant prints a different set", True,
     'def grw_row.nm(pfx: String, arm: String, field: String) -> String: String.concat(["grw_", pfx, "_", arm, "_", field])',
     'def grw_row.nm(pfx: String, arm: String, field: String) -> String: String.concat(["renamed_", pfx, "_", arm, "_", field])',
     "DIFFERENT SET OF ROW NAMES"),
]


def run_demo(mid, pat, rep):
  """Run grwmut.main() over a one-entry MUTS and capture BOTH streams."""
  grwmut.MUTS[:] = [(mid, "selftest", pat, rep)]
  buf = io.StringIO()
  with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
    rc = grwmut.main()
  return rc, buf.getvalue()


def main():
  ok = True
  orig = TARGET.read_text()
  print(f"baseline: {len(grwmut.rows_of(grwmut.run_bend()))} rows")
  for did, what, pat_must_exist, pat, rep, expect in DEMOS:
    if pat_must_exist and pat not in orig:
      print(f"{did} SETUP ERROR: the demo pattern is not in the file", file=sys.stderr)
      ok = False
      continue
    rc, out = run_demo(did, pat, rep)
    TARGET.write_text(orig)
    restored = TARGET.read_text() == orig
    rejected = expect in out and rc != 0
    print(f"{did} {'REJECTED' if rejected else 'NOT REJECTED'} rc={rc} "
          f"restored={restored} -- expected {expect!r}")
    if not rejected:
      ok = False
      for ln in out.splitlines():
        print(f"      | {ln}")
    if not restored:
      print(f"{did} DID NOT RESTORE THE FILE", file=sys.stderr)
      ok = False
  TARGET.write_text(orig)
  print("SELFTEST", "PASS -- the harness rejects all three and restored the file"
        if ok else "FAIL -- the harness accepted a broken mutation")
  return 0 if ok else 1


if __name__ == "__main__":
  sys.exit(main())