#!/usr/bin/env python3
"""cstyle-reader-parity.py -- does cstyle-gate.py's green survive the SHARED reader?

    python3 .agents/slop/cstyle-reader-parity.py            # measure, print, verdict

THE QUESTION, AND WHY IT IS NOT ANSWERABLE BY READING cstyle-gate.py.

`cstyle-gate.py` printed a shred count by calling `rows_shipped`, whose docstring claimed to
be `rebase-gate.py`'s `rows()` "verbatim". MEASURED, it was not. It was the PRE-F2/PRE-F3 fork:

    shape                       the fork said            rows() said        agree
    "a=b"                       {'a': 'b'}               {'a': 'b'}         yes
    "alpha  1"        (F3)      {}                       {'alpha': '1'}     NO
    "kern=[*V]   py=[*W]" (F2)  {'kern': '[*V]   py=[*W]'} {'kern': '[*V]'}  NO
    "== SECTION =="             {'': '= SECTION =='}    {}                 NO
    "=v"                        {'': 'v'}               {}                 NO

The last two are the interesting ones: the fork MANUFACTURES the `""` phantom that `rows()`
excludes ON PURPOSE, because fourteen `== SECTION ==` banners all keyed on `""`.

The count is fixed by IMPORTING `rows()`, never by copying it. What this file answers is the
question the count was standing in for -- is cstyle-gate.py's OWN green still true when the
correct reader is the one in the file -- and it answers it three ways, because "the reader is
only used by a print" is a claim about the call graph, and this project's standing record is
that a comment and the call graph disagree:

  [1] THE VERDICT UNDER EACH READER. `judge()` is re-run with `rows_strict` REPLACED BY
      `rows()` on both lanes, and the whole result dict is compared. Not "does judge call
      rows_shipped" -- what judge returns when `rows()` IS the reader.
  [2] THE WHOLE GATE OUTPUT, byte for byte. One differing line is a cosmetic print; zero
      differing lines means the count was never load-bearing; a differing VERDICT means it was.
      This is measured by DIFFING A SAVED PRE-FIX RUN against the post-fix run, so the "before"
      reader is the file's own reader and is not re-typed here.
  [3] THE DENOMINATORS, because a count of agreements with no denominator is a number nobody
      can check, and "0 disagreeing" over an unwired lane is a zero, not a pass.

LANES. `--port-stdout`/`--oracle-stdout` name captured lane text. A verdict over a capture is
evidence about the CAPTURE and never about the tree; every line printed here carries the
capture's path and md5, and `--live` re-runs the lanes and prints their rc.
"""
import argparse, difflib, hashlib, importlib.util, io, contextlib, pathlib, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
BEFORE = ".agents/slop/cstyle-parity-before.txt"
ORACLE_STDERR = ".agents/slop/cstyle-parity/oracle.err"


def load(name):
  """`rebase-gate.py` and `cstyle-gate.py` both have a `-` in the name, so neither imports by
  name. ONE loader, the same shape rebase-scan-oracles.py uses."""
  spec = importlib.util.spec_from_file_location(name, str(HERE / f"{name}.py"))
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


RG, CG = load("rebase-gate"), load("cstyle-gate")


def md5(text):
  return hashlib.md5(text.encode()).hexdigest()[:12]


def lane(cmd, capture):
  if capture:
    t = (REPO / capture).read_text()
    return t, f"CAPTURE {capture} md5={md5(t)}"
  r = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True, timeout=3600)
  return r.stdout, f"LIVE {' '.join(cmd)} rc={r.returncode}"


def names_only(a, b):
  """Each way, because a count of DIFFERENCES is not a coverage statement."""
  return sorted(set(a) - set(b)), sorted(set(b) - set(a))


def shared_values(a, b):
  keys = set(a) & set(b)
  return sum(1 for n in keys if a[n] == b[n]), len(keys)


def verdict(res):
  return (f"{'BROKEN' if res['bad'] else 'AGREE'} port={len(res['port'])} "
          f"oracle={len(res['oracle'])} gated={len(res['gated'])} agree={len(res['agree'])} "
          f"disagree={len(res['disagree'])} stale={len(res['stale'])} bad={len(res['bad'])}")


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--port-stdout", default=".agents/slop/blobrows/CURRENT/tinybendygrad__renderer__cstyle.bend.txt")
  ap.add_argument("--oracle-stdout", default=".agents/slop/cstyle-parity/oracle.txt")
  ap.add_argument("--oracle-stderr", default=ORACLE_STDERR)
  ap.add_argument("--save-before", action="store_true",
                  help="record this run's whole output as the PRE-FIX baseline")
  a = ap.parse_args()
  pout, pprov = lane(["./bin/bend", CG.PORT], a.port_stdout)
  oout, oprov = lane([sys.executable] + CG.ORACLE.split(), a.oracle_stdout)
  print(f"port lane   {pprov}   {len(pout.splitlines())} physical lines")
  print(f"oracle lane {oprov}   {len(oout.splitlines())} physical lines")
  if not (pout.strip() and oout.strip()):
    print("a lane printed NOTHING, so nothing below is a verdict. This is not a pass.")
    return 1

  # ---------------------------------------------------------------- [1] the readers
  for nm, text in (("port", pout), ("oracle", oout)):
    sr, shreds, dups = CG.rows_strict(text)
    sh = RG.rows(text)
    oa, ob = names_only(sr, sh)
    print(f"\n[1] {nm} lane  rows_strict {len(sr)} names ({len(shreds)} shred(s), "
          f"{len(dups)} dup(s))   rows() {len(sh)} names   union {len(set(sr) | set(sh))}")
    print(f"    rows_strict-only {len(oa)}: {oa[:6]}")
    print(f"    rows()-only      {len(ob)}: {ob[:6]}")
    same, tot = shared_values(sr, sh)
    print(f"    same value on shared names: {same}/{tot}"
          + ("   <-- readers AGREE on every shared name" if same == tot else
             f"   <-- {tot - same} shared name(s) the two readers value DIFFERENTLY"))

  # ---------------------------------------------------------------- [1b] the verdict
  strict = CG.judge(pout, oout)
  saved = CG.rows_strict
  CG.rows_strict = lambda t: (RG.rows(t), [], [])
  try:
    shared_res = CG.judge(pout, oout)
  finally:
    CG.rows_strict = saved
  print(f"\n[1b] judge() with rows_strict: {verdict(strict)}")
  print(f"[1b] judge() with rows()     : {verdict(shared_res)}")
  print(f"[1b] -> {'IDENTICAL' if verdict(strict) == verdict(shared_res) else 'DIFFERENT'}"
        f"  (disagreeing rows are "
        f"{[d[0] for d in strict['disagree']] or 'none'} of {len(strict['gated'])} gated)")

  # ---------------------------------------------------------------- [2] whole output
  #
  # The pre-fix reader is taken FROM THE COMMITTED BLOB (`jj file show -r @-`), not re-typed:
  # a re-typed fork is a third reader, and this whole file exists because a reader was copied
  # once. So the ablation swaps the file's own old reader back in and diffs the WHOLE print.
  def committed_fork():
    blob = subprocess.run(["jj", "file", "show", "-r", "@-",
                           ".agents/slop/cstyle-gate.py"], cwd=REPO,
                          capture_output=True, text=True).stdout
    import ast
    for node in ast.parse(blob).body:
      if isinstance(node, ast.FunctionDef) and node.name == "rows_shipped":
        ns = {}
        exec(ast.get_source_segment(blob, node), ns)
        return ns["rows_shipped"], blob
    return None, blob

  def gate_once(reader=None):
    buf, old, saved = io.StringIO(), sys.argv, CG.rows_shipped
    if reader is not None:
      CG.rows_shipped = reader
    sys.argv = ["cstyle-gate.py", "--port-stdout", a.port_stdout,
                "--oracle-stdout", a.oracle_stdout, "--oracle-stderr", a.oracle_stderr]
    try:
      with contextlib.redirect_stdout(buf):
        rc = CG.main()
      return rc, buf.getvalue()
    finally:
      sys.argv, CG.rows_shipped = old, saved

  # ---- [2a] THE READER ABLATION. Same code, same lanes, old reader vs shared reader.
  fork, blob = committed_fork()
  rc_f, out_f = gate_once(fork)
  rc_s, out_s = gate_once()
  abl = list(difflib.unified_diff(out_f.splitlines(), out_s.splitlines(),
                                  "committed fork reader", "shared rebase-gate.py:rows()",
                                  lineterm="", n=0))
  print(f"\n[2a] READER ABLATION, same code and same two lane texts. "
        f"fork reader rc={rc_f}   shared reader rc={rc_s}")
  print(f"[2a] the fork is the file's OWN pre-fix reader, taken from `jj file show -r @-` "
        f"({len(blob.splitlines())} lines), not re-typed here")
  if not abl:
    print("[2a] IDENTICAL: not one printed line differs")
  for line in abl:
    print(f"    {line}")

  # ---- [2b] WHOLE OUTPUT against the SAVED pre-fix run.
  rc, out = gate_once()
  print(f"\n[2b] whole gate output rc={rc}")
  if a.save_before:
    (REPO / BEFORE).parent.mkdir(parents=True, exist_ok=True)
    (REPO / BEFORE).write_text(out)
    print(f"[2] SAVED pre-fix baseline {BEFORE} md5={md5(out)} ({len(out.splitlines())} lines)")
  elif (REPO / BEFORE).exists():
    was = (REPO / BEFORE).read_text()
    d = list(difflib.unified_diff(was.splitlines(), out.splitlines(),
                                  "pre-fix run (stale fork reader, stderr discarded)",
                                  "post-fix run (shared rows(), stderr kept)",
                                  lineterm="", n=0))
    print(f"[2b] pre-fix run {BEFORE} md5={md5(was)}  vs  this run md5={md5(out)}")
    print(f"[2b] -> "
          f"{'IDENTICAL: not one printed line differs' if not d else f'{len(d)} diff line(s)'}")
    for line in d:
      print(f"    {line}")
  else:
    print(f"[2b] no baseline at {BEFORE}; re-run with --save-before to create one")
  return 0


if __name__ == "__main__":
  sys.exit(main())