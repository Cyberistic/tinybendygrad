#!/usr/bin/env python3
"""cstyle-gate.py -- the gate for tinybendygrad/renderer/cstyle.bend, and the CLOSE on
`rows()` shredding.

    python3 .agents/slop/cstyle-gate.py                      # the real port + real oracle
    python3 .agents/slop/cstyle-gate.py --selftest           # both colours, on the instrument
    python3 .agents/slop/cstyle-gate.py --plant NAME         # corrupt ONE captured value

WHY THIS EXISTS, in the order the measurements forced it.

1. `rebase-gate.py`'s `rows()` reads a row out of EVERY line containing `=`, so a lane that
   prints a MULTI-LINE value has that value shredded into one row per line. MEASURED on the
   real `renderer_oracle.py cstyle` output: 96 physical lines -> 33 row names, of which
   **15 are claims and 18 are line noise** -- `float val0`, `*(data1_4+0)`, `int g0`,
   `template <class T, class F> __device__ ... u.f`, and `for (int gidx0`. The noise is not
   hypothetical: 18 of the 33 oracle rows already recorded in
   `.agents/slop/rebase/baseline.json` under `cpython:renderer_oracle` are exactly these,
   including
       'for (weakint gidx0' = '0; gidx0 < ((weakint)(val0)); gidx0++) {'
       'template <class T, class F> __device__ __forceinline__ T tg_bitcast(F v) { ... u.f'
           = 'v; return u.t; }'
   so the recorded baseline already carries `weakint` as C output and a row split
   mid-identifier.

2. `renderer/cstyle.bend` does not have this problem and SAYS WHY, in its own source at
   `kern2_row`: "THE ONE ROW THAT SEES A NEWLINE ... this one's is five or nine, so
   `esc_row` is applied to BOTH sides ... and the multi-line hazard is the reason the very
   first version of these rows passed while dropping three devices' prefixes entirely."
   The PORT escapes its newlines; the ORACLE never got the same treatment. The asymmetry is
   the bug, and the fix belongs on the READER rather than in every lane author's memory.

3. `bend2-constraints.md` POSITION 9496 (rule 60) already ruled that "a differ must treat a
   duplicate row name as an error rather than as a redefinition", after `cstyle_oracle.py`
   emitted `rd BASE ` 7 times and `cfo BASE ` 20 times and a `{name: value}` dict discarded
   99 of 127 rows. `rows_strict` raises on a duplicate for the same reason.

WHAT IT REFUSES TO DO. It does not shred, and it does not paper over a lane that shares no
comparable claim. Both are BROKEN with the number that says so, and rc=1.

  usage: python3 .agents/slop/cstyle-gate.py [--selftest] [--plant ROW]
"""
import argparse, pathlib, subprocess, sys, tempfile

REPO = pathlib.Path(__file__).resolve().parents[2]
PORT = "tinybendygrad/renderer/cstyle.bend"
ORACLE = ".agents/slop/renderer_oracle.py cstyle"
ORACLE_KEY = "oracle"
ROW_OPEN = " = ["


# ---------------------------------------------------------------- the row reader
#
# A row is `NAME = [VALUE]` with VALUE's closing bracket ON THE SAME LINE. Anything else is
# not a row and this reader says so instead of inventing one. A continuation line of a
# multi-line value carries an `=` often enough -- `float val0 = ...`, `for (int i = 0; ...)`,
# `int x = f(y);` -- that treating it as a row MANUFACTURES a shared name out of line noise,
# and a shared name is the one thing a comparability guard reads as evidence.
def rows_strict(text):
  """(rows, shreds, dups). A duplicate is REPORTED, never silently overwritten."""
  rows, shreds, dups = {}, [], []
  for ln, line in enumerate(text.splitlines(), 1):
    if not line.strip():
      continue
    i = line.find(ROW_OPEN)
    if i < 0 or not line.rstrip().endswith("]"):
      shreds.append((ln, line))
      continue
    name, value = line[:i].strip(), line[i + len(ROW_OPEN):].rstrip()[:-1]
    if name in rows:
      dups.append(name)
    rows[name] = value
  return rows, shreds, dups


def rows_shipped(text):
  """rebase-gate.py's `rows()`, verbatim, so the shred count is a MEASUREMENT of the shipped
  reader rather than an argument about it."""
  out = {}
  for line in text.splitlines():
    if "=" in line:
      k, v = line.split("=", 1)
      out[k.strip()] = v.strip()
  return out


def py_col(row_value):
  """The port prints `NAME = [<its own dtype alphabet>]   py=[<CPython's C spelling>]`. Its
  VALUE column can never equal an oracle value -- `cstyle.bend` speaks f16/bf16/u8 and
  CPython speaks half/__bf16/unsigned char -- so the `py=` column is the only field on the
  port that is in CPython's alphabet and the only field a lane diff can compare.

  Takes a `rows_strict` value, which has already had the row's ONE closing bracket removed --
  and on this row shape that bracket is the `py=` field's, not the value field's."""
  k = row_value.rfind("   py=[")
  return row_value[k + len("   py=["):] if k >= 0 else None


# ---------------------------------------------------------------- the crosswalk
#
# DECLARED, NOT DERIVED, and deliberately EMPTY -- and the emptiness is the finding, not an
# oversight. MEASURED: 0 of the oracle's 15 claim names intersect the port's 225 row names,
# and no bijection repairs it, because the two sides are not asking the same question. The
# port's clause rows render SYMBOLIC operands (`B`, `X`, `R`, `S`, `V`), and its 30 `kern2`
# rows take the kernel BODY from a literal `List<&2, String>` (`g_kernel()` returns two
# hardcoded C strings), so no CPython call can produce those values at all.
CROSSWALK = {"tmap BASE": "tmap BASE"}
UNCOVERED = {
  "k1_load_store", "k1_load_store.clang", "k1_load_store.metal", "k1_load_store.cuda",
  "k2_alu", "k3_consts", "k4_smem", "k4_smem.clang", "k4_smem.metal", "k4_smem.cuda",
  "k6_range", "k7_cast", "k8_stack.clang", "k8_stack4.clang", "k5_special.ocl",
}

# ONE REAL CROSSWALK ENTRY, whose right-hand side is a LIVE CPython CALL and not a def of the
# thing under test. It exists so the gate can be seen seeing BOTH colours on the REAL port
# rather than only on the self-test pair, and it is expected to DISAGREE -- see LIVE_TMAP_BASE.
LIVE = {"tmap BASE": "live_tmap_base"}


def live_tmap_base():
  """`cstyle.bend`'s `tmap_row` walks `g_dtypes()` = `dtypes.all` and prints `rd_base_name`.
  Its `py=` column was generated by `.agents/slop/wip/gen_main.py:73`,
  `",".join(r.type_map.get(dt, dt.name) for dt in dtypes.all)`, against the PIN. This calls
  the SAME expression against the tree the gate actually runs on, and reports a crash as a
  crash rather than as a value -- a `KeyError` is CPython's answer here and pretending
  otherwise is how a broken cell becomes a green one."""
  import subprocess as sp
  probe = ("import sys; sys.path.insert(0,'.')\n"
           "from tinygrad.dtype import dtypes as D\n"
           "from tinygrad.helpers import Target\n"
           "from tinygrad.renderer.cstyle import CStyleLanguage\n"
           "cs = CStyleLanguage(Target('NULL'))\n"
           "print(','.join(cs.type_map.get(dt, dt.name) for dt in D.all))\n")
  with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
    f.write(probe)
    path = f.name
  try:
    r = sp.run([sys.executable, path], cwd=REPO, capture_output=True, text=True, timeout=300)
    return r.stdout.strip() if r.returncode == 0 else f"CPython raised: {r.stderr.strip()[-90:]}"
  finally:
    pathlib.Path(path).unlink(missing_ok=True)


def run(argv):
  return subprocess.run(argv, cwd=REPO, capture_output=True, text=True, timeout=3600)


def judge(porc, orc_out, plant=None, crosswalk=None, uncovered=None):
  """BROKEN wins over everything. Every reason carries the NUMBER that produced it, because
  "compared nothing" and "compared 15 things" print very similar bytes."""
  cw = CROSSWALK if crosswalk is None else crosswalk
  unc = UNCOVERED if uncovered is None else uncovered
  bad = []
  pr, psh, pdup = rows_strict(porc)
  orr, osh, odup = rows_strict(orc_out)
  if not pr:
    bad.append("the port lane produced ZERO rows")
  if not orr:
    bad.append("the oracle lane produced ZERO rows")
  for lane, shreds in (("port", psh), ("oracle", osh)):
    if shreds:
      bad.append(f"{lane} lane SHREDDED {len(shreds)} line(s) into fake rows; first is "
                 f"L{shreds[0][0]} {shreds[0][1].strip()[:64]!r}")
  for lane, dups in (("port", pdup), ("oracle", odup)):
    if dups:
      bad.append(f"{lane} lane repeats {len(dups)} row name(s): {sorted(set(dups))[:5]}")

  stray = sorted(set(orr) - set(cw) - set(unc))
  if stray:
    bad.append(f"oracle rows in no crosswalk and not declared UNCOVERED: {stray}")
  ghost = sorted(set(cw) - set(pr))
  if ghost:
    bad.append(f"crosswalk names port rows that DO NOT EXIST: {ghost}")

  if plant and plant in orr:
    orr[plant] = (orr[plant].replace("half", "halfx", 1) or orr[plant]) + "X"
  elif plant and plant in pr:      # plant a PORT row's py= column, in memory only
    pr[plant] = pr[plant].replace("   py=[", "   py=[PLANTED-", 1)

  compared, disagree = [], []
  for name in sorted(cw):
    if name not in pr:
      continue
    got = py_col(pr[name])
    if got is None:
      bad.append(f"port row `{name}` has no `py=` column, so it cannot be compared to CPython")
      continue
    compared.append(name)
    # A `LIVE` name is answered by a CPython CALL and needs no oracle row; any other
    # crosswalk entry names an oracle row, and a missing one is a crosswalk that lies.
    if name in LIVE:
      want = globals()[LIVE[name]]()
    elif name in orr:
      want = orr[name]
    else:
      bad.append(f"crosswalk names oracle row `{name}`, which the oracle did not emit")
      continue
    if got != want:
      disagree.append((name, got, want))
  if not compared:
    bad.append(f"0 comparable claims: none of the {len(cw)} crosswalked port row(s) carried a "
               f"`py=` column, so the two lanes agreed about NOTHING this run")
  if disagree:
    n, p, o = disagree[0]
    bad.append(f"{len(disagree)} crosswalked row(s) DISAGREE with CPython. First `{n}`:\n"
               f"        port py=  {p}\n        CPython   {o}")
  return bad, pr, orr, compared, disagree


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--selftest", action="store_true")
  ap.add_argument("--plant", default=None)
  ap.add_argument("--port-stdout", default=None,
                  help="judge this captured port stdout instead of re-running the lane, and SAY SO")
  ap.add_argument("--oracle-stdout", default=None,
                  help="judge this captured oracle stdout instead of re-running the lane, and SAY SO")
  a = ap.parse_args()
  if a.selftest:
    return selftest()
  if a.port_stdout or a.oracle_stdout:
    print("!! CAPTURED LANE INPUT. Not a live run: the live lanes are re-run and their rc is "
          "printed below, and a capture can be stale. A verdict over a capture is evidence "
          "about the CAPTURE, never about the tree as it is now.")
  p = (subprocess.CompletedProcess([], 0, pathlib.Path(a.port_stdout).read_text(), "")
       if a.port_stdout else run(["./bin/bend", PORT]))
  o = (subprocess.CompletedProcess([], 0, pathlib.Path(a.oracle_stdout).read_text(), "")
       if a.oracle_stdout else run([sys.executable] + ORACLE.split()))
  print(f"live port lane rc={p.returncode}   live oracle lane rc={o.returncode}")
  if (p.returncode or o.returncode) and not (a.port_stdout or a.oracle_stdout):
    print(f"lane failure: bend {' '.join(p.stderr.split())[-140:]} | "
          f"oracle {' '.join(o.stderr.split())[-140:]}")
    return 1
  if not (p.stdout.strip() and o.stdout.strip()):
    print("a lane printed NOTHING, so nothing was compared. This is GUARD 2's failure mode and "
          "it is NOT a pass")
    return 1
  bad, pr, orr, compared, disagree = judge(p.stdout, o.stdout, a.plant)
  if a.plant:
    print(f"[planted] `{a.plant}` corrupted in the CAPTURED OUTPUT ONLY; no file on disk was "
          f"touched")
  shipped = rows_shipped(o.stdout)
  print(f"port rows (rows_strict): {len(pr)}   oracle rows (rows_strict): {len(orr)}")
  print(f"the shipped rows() over the SAME oracle stdout: {len(shipped)} names "
        f"-- {len(shipped) - len(orr)} of them shredded out of multi-line values")
  print(f"comparable claims: {len(compared)}   disagreements: {[d[0] for d in disagree][:5]}")
  print(("BROKEN" if bad else "AGREE"), "\n".join("  - " + b for b in bad))
  return 1 if bad else 0


# ---------------------------------------------------------------- the self-test
#
# A self-test of the INSTRUMENT, over two REAL lanes: a real .bend file and a real CPython
# call. It is NOT a claim about cstyle.bend. It is the control that shows the gate reports
# BOTH colours, kept separate from the real run so the real run's BROKEN verdict can never
# be mistaken for the gate itself being broken.
SELFTEST_BEND = (
  "import Base\n"
  "\n"
  "def g_tmap() -> List<&2, String>:\n"
  "  [\"f16\", \"f32\"]\n"
  "\n"
  "def main() -> IO(Unit):\n"
  "  do IO<Unit>: IO.print(String.concat([\"st BASE = [\", String.join(g_tmap(), \",\"), "
  "\"]   py=[half,float]\"]))\n")

SELFTEST_ORACLE = (
  "from tinygrad.dtype import dtypes as D\n"
  "from tinygrad.helpers import Target\n"
  "from tinygrad.renderer.cstyle import CStyleLanguage\n"
  "cs = CStyleLanguage(Target('NULL'))\n"
  "print('st BASE = [' + ','.join(cs.type_map[d] for d in (D.f16, D.f32)) + ']')\n")


def selftest():
  bend = REPO / ".agents/slop/cstyle-selftest-probe.bend"
  with tempfile.TemporaryDirectory() as td:
    ora = pathlib.Path(td) / "o.py"
    ora.write_text(SELFTEST_ORACLE)
    bend.write_text(SELFTEST_BEND)
    try:
      chk = run(["./bin/bend", str(bend.relative_to(REPO)), "--check-only"])
      print(f"probe --check-only FIRST LINE: "
            f"{(chk.stdout.strip().splitlines() or [''])[0]!r}  rc={chk.returncode}  "
            f"(the exit status is NOT the verdict)")
      p, o = run(["./bin/bend", str(bend.relative_to(REPO))]), run([sys.executable, str(ora)])
      assert o.returncode == 0, o.stderr
      for label, plant in (("clean", None), ("planted", "st BASE")):
        bad, pr, orr, compared, dis = judge(p.stdout, o.stdout, plant,
                                            crosswalk={"st BASE": "st BASE"})
        verdict = "BROKEN" if bad else "AGREE"
        print(f"  {label:<8} -> {verdict:<7} shared={compared} "
              f"disagreements={[d[0] for d in dis]} "
              f"shreds={len(rows_strict(p.stdout)[1]) + len(rows_strict(o.stdout)[1])}")
        if label == "clean" and (bad or not compared or dis):
          print("    SELFTEST FAILED: the clean pair must share a name and agree")
          return 1
        if label == "planted" and (not dis or not bad):
          print("    SELFTEST FAILED: the planted disagreement was not seen")
          return 1
      print("SELFTEST OK: the SAME instrument reports AGREE on the clean pair and DISAGREE "
            "on the planted one")
      return 0
    finally:
      bend.unlink(missing_ok=True)


if __name__ == "__main__":
  sys.exit(main())