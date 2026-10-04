#!/usr/bin/env python3
"""cstyle-gate.py -- the gate for tinybendygrad/renderer/cstyle.bend.

    python3 .agents/slop/cstyle-gate.py                # the real port + the real oracle
    python3 .agents/slop/cstyle-gate.py --selftest     # both colours, on the instrument
    python3 .agents/slop/cstyle-gate.py --plant ROW     # corrupt ONE captured value
    python3 .agents/slop/cstyle-gate.py --explain       # the row budget, by family

A CAPTURE NEEDS BOTH HALVES OF THE ORACLE LANE. `--oracle-stdout` alone is REFUSED, because the
oracle's stderr is the only place a CPython refusal exists and a capture that drops it turns
nine sound rows into nine phantom disagreements.

WHY THIS REPLACED A CROSSWALK. The previous gate declared ONE crosswalk entry out
of 225 port rows -- `tmap BASE` -- and left the other 224 UNCOVERED, because
`renderer_oracle.py cstyle` printed 15 real C kernels under names the port does
not print and the intersection was ZERO. Measured, then: 0 of 227 shared.

The reason was never that the rows were incomparable. `CStyleLanguage` and its
five subclasses are INSTANTIABLE, every table `render_kernel` reads is a class
attribute or a dict, and `render_kernel` / `render_index` / `render_buffer` /
`_wmma_name` / `code_for_op` are all plain methods. `renderer_oracle.py
cstyle-rows` calls them with the port's own arguments. 224 of the port's 227 row
names are now produced, and every value on both sides is a live CALL.

THE ROW SHAPE, AND WHY THE COMPARISON IS NOT A LINE DIFF.

    NAME = [<the port's own answer>]   py=[<the pin's reading>]

Three columns, and they are three different claims:

  * the port's OWN column is compared against a LIVE CPYTHON CALL. That is the
    gate. The port's `py=` literal is a TRANSCRIPTION of the pin, so it is
    reported -- `STALE-LITERAL` -- when it disagrees with the live call and it is
    never the thing being compared. It was: at HEAD, 30 of 227 literals were
    stale and 89 port rows were wrong, and all 89 came from ONE bug.
  * a CPython cell that is an EXCEPTION is reported as `!KeyError`, and the port's
    documented marker for "this key is not in the dict" is `""`
    (cstyle.bend:1074, :1149). So `!KeyError` compares against `""`, PER CELL --
    an `rd` row is seven `|`-separated cells and six of them can refuse while the
    seventh does not.
  * a row CPython cannot answer at all is an EXCLUSION, named, counted and
    printed on every run. Three of them and the reasons are in `EXCLUDED`.

WHAT IT REFUSES TO DO. It does not shred (a multi-line value is escaped on BOTH
sides by `esc_row`), it does not accept a duplicate row name, and it does not
report a clean zero when a parser matched nothing -- GUARD 2 below exists because
three false zeros happened today.
"""
import argparse, importlib.util, pathlib, subprocess, sys, tempfile

REPO = pathlib.Path(__file__).resolve().parents[2]
PORT = "tinybendygrad/renderer/cstyle.bend"
ORACLE = ".agents/slop/renderer_oracle.py cstyle-rows"
KEYERROR = "!KeyError"          # renderer_oracle.py's marker for a CPython REFUSAL
PORT_KEYERROR = ""              # cstyle.bend's marker for the same fact
SEP = "]   py=["                 # the port's value/py= boundary
ROW_OPEN = " = ["
CELL_SEPS = ("|", " / ")

# THE THREE ROWS CPython CANNOT ANSWER, each with the measurement that says why.
# A named exclusion is not a silent one: `explain` and every run print them.
EXCLUDED = {
  "buft METAL": (
    "MetalRenderer.render_kernel calls super() with bufs=[] (cstyle.py:406), so "
    "`buftypes` is EMPTY on Metal and `var_prefix`/`var_suffix` are read by nothing "
    "in cstyle.py. The only way to see them is to evaluate upstream's comprehension "
    "with `self` bound, which is a def of the thing under test."),
  "idx BASE  regadd": (
    "`render_index`'s non-ALU arm is `strip_parens(self[idx]) if idx.arg == Ops.ADD "
    "else self[idx]` (cstyle.py:174). MEASURED at HEAD: `u.arg == Ops.ADD` is False "
    "for every UOp a caller can build -- INDEX's arg is None, RANGE's is "
    "(AxisType, id), REDUCE's is (Ops.ADD, n), CAST's is a DType, SPECIAL's is a "
    "str -- so the ADD arm is UNREACHABLE and the port's `AReduce{ADD, 0}` fixture "
    "is a shape `UOp.arg` does not have."),
  "idx HIP   regadd": "the same unreachable arm as `idx BASE  regadd`.",
  "under float": (
    "`under` IS `String.replace(\" \", \"_\")` -- an INLINE expression with no def in "
    "cstyle.py and no row of its own; its two callers are `_render_dtype` on the "
    "`sz > 1` branch and `_wmma_name`, unconditionally. MEASURED over all 20 named "
    "DTypes at HEAD: NOT ONE `.name` contains a space, so the replace is a no-op on "
    "every value upstream can produce and the fixture string is not reachable."),
  "under signed char": "see `under float`; this fixture's two-word name is the case "
                       "the replace was written for and it cannot arise at HEAD.",
  "under unsigned lon": "see `under float`; `unsigned long` is likewise unreachable.",
}

# `under` is `String.replace(" ", "_")` -- an inline expression with no def and no
# row of its own in cstyle.py. Its THREE fixtures are hand-written strings; MEASURED
# over all 20 named DTypes at HEAD, NOT ONE `.name` contains a space, so the replace
# is a no-op on every value upstream can produce. Those three rows are exclusions.

# THE FOUR ROWS WHERE CPython REFUSES AND THE PORT ANSWERS ANYWAY. `_render_dtype`
# does `self.type_map[dtype]` (cstyle.py:190-191) and `CStyleLanguage.type_map` has
# no fp8 entry above CUDA, so `type_map[dtypes.fp8e4m3]` is a `KeyError` on four of
# six devices -- MEASURED, not inferred, and the oracle reports each one on stderr.
# The port has no exception channel and answers `type_map.get(dtype, dtype.name)`,
# so `renderer_oracle.py cstyle-rows` answers those four rows by letting UPSTREAM'S
# OWN `_render_dtype` run against a renderer whose single `type_map` entry is
# patched. The row is gated; the refusal is printed every run. `count_refusals`
# re-reads the oracle's stderr so the gate cannot pass on a lane that stopped
# reporting its refusals.
REFUSED_ROWS = ("rd BASE  fp8e4m3", "rd CLANG fp8e4m3", "rd METAL fp8e4m3",
                "rd OPENCL fp8e4m3")
REFUSED_MARK = "REFUSED "

# THE FAMILIES, so `explain` can print a budget and a reader can see which half of
# the file is thin. Counts are MEASURED from the port's stdout, not declared.
FAMILY = ("tmap", "rd", "witem", "cfo", "kern", "kern2", "idx", "opt", "type",
          "ptr", "acc", "cast", "leg", "buf2", "buft", "wmma", "under", "img",
          "hipockl", "hipocml")


# ---------------------------------------------------------------- the row reader
#
# A row is `NAME = [VALUE]` with VALUE's closing bracket ON THE SAME LINE. Anything
# else is not a row and this reader says so instead of inventing one. A
# continuation line of a multi-line value carries an `=` often enough -- `float
# val0 = ...`, `for (int i = 0; ...)`, `int x = f(y);` -- that treating it as a row
# MANUFACTURES a shared name out of line noise, and a shared name is the one thing
# a comparability guard reads as evidence.
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


def load(name):
  """`rebase-gate.py` has a `-` in its name, so it does not import by name. ONE loader, the
  same shape rebase-scan-oracles.py uses, because two loaders is two chances to disagree about
  what got loaded."""
  spec = importlib.util.spec_from_file_location(name, str(pathlib.Path(__file__).parent / f"{name}.py"))
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


rows_shipped = load("rebase-gate").rows
"""THE PROJECT'S ONE ROW READER, IMPORTED. `rebase-gate.py`'s `rows()`, which is what
  `rebase-scan-oracles.py` already calls -- so scan and gate cannot disagree by construction.

  ⚠ THIS FUNCTION WAS A FORK, AND THE FORK WAS WRONG ON 4 OF ITS 6 SHAPES while its docstring
  claimed `rows()` "verbatim". MEASURED against the real `rows()`:

      "a=b"                       fork {'a': 'b'}                  rows() {'a': 'b'}          agree
      "alpha  1"       (F3)       fork {}                          rows() {'alpha': '1'}      NO
      "kern=[*V]   py=[*W]" (F2)   fork {'kern': '[*V]   py=[*W]'}  rows() {'kern': '[*V]'}    NO
      "== SECTION =="             fork {'': '= SECTION =='}       rows() {}                  NO
      "=v"                        fork {'': 'v'}                  rows() {}                  NO

  Three ways it was wrong, not one: it could not read F3 at all, it could not fold F2's `py=`
  column away, and it MANUFACTURED the `""` phantom `rows()` excludes on purpose. Over this
  tree's own oracle lane the fork's number was `222` against `rows_strict`'s `224`, so the
  print claimed **`-2` shredded rows** -- a negative shred count, which is not a measurement of
  anything. A copied reader is a second reader, and a second reader drifts silently because
  nothing compares the two.

  ⚠ AND IT IS NOT THE READER `judge()` USES, and it must not become one. `rows()` returns the
  producer's OWN answer (`left`) with the `py=` column already folded away, while `split_py()`
  reads that column back OUT of the value to report STALE-LITERAL. MEASURED: substituting
  `rows()` for `rows_strict` inside `judge()` turns the lane BROKEN on 225 of 227 rows with
  "carry no `py=` column" -- not a disagreement, an incompatibility between the two readers'
  contracts. So this name is a PARITY READER, used only to say whether the shared reader and
  this gate's own reader see the same rows. `.agents/slop/cstyle-reader-parity.py` measures
  that, and `.agents/slop/cstyle-shapes-selftest.py` proves both readers reach red."""


def split_py(value):
  """(the port's own answer, its `py=` literal). The port's row has TWO closing
  brackets and `rows_strict` removed one of them, so the LAST `]   py=[` is the
  boundary -- finding the first one would cut the value in half."""
  k = value.rfind(SEP)
  return (value[:k], value[k + len(SEP):]) if k >= 0 else (value, None)


def cells(value):
  """One row is sometimes SEVERAL claims: `rd` joins seven `_render_dtype` calls
  with `|`, `witem` joins two with ` / `, `buft` five with `|`, `tmap` sixteen with
  `,`. Splitting on the first separator that is present and comparing the lists
  cell by cell is what makes a partial disagreement report the CELL that
  disagrees instead of the whole row."""
  for s in CELL_SEPS:
    if s in value:
      return value.split(s)
  return [value]


def separator(value):
  """The separator a joined row uses, or None for a single-cell row. The
  expectation has to be re-joined with the SAME one: a `witem` row is `a / b` and
  re-joining it with `|` made all six of them read as STALE-LITERAL on the first
  run, which is the false positive this function exists to stop."""
  for s in CELL_SEPS:
    if s in value:
      return s
  return None


def expected(oracle_value):
  """The port's answer for an oracle row, PER CELL: a cell CPython refused maps to
  the port's documented `""` marker and nothing else does."""
  return [PORT_KEYERROR if c == KEYERROR else c for c in cells(oracle_value)]


def joined(oracle_value, want):
  s = separator(oracle_value)
  return "".join(want) if s is None else s.join(want)


def run(argv):
  return subprocess.run(argv, cwd=REPO, capture_output=True, text=True, timeout=3600)


def family(name):
  return name.split()[0] if name.split() else name


def judge(porc, orc_out, plant=None, exclusions=None, refused_on=()):
  """BROKEN wins over everything. Every reason carries the NUMBER that produced it,
  because "compared nothing" and "compared 224 things" print very similar bytes."""
  exc = EXCLUDED if exclusions is None else exclusions
  bad = []
  pr, psh, pdup = rows_strict(porc)
  orr, osh, odup = rows_strict(orc_out)

  # GUARD 1: an empty lane is not a pass.
  if not pr:
    bad.append("the port lane produced ZERO rows")
  if not orr:
    bad.append("the oracle lane produced ZERO rows")
  # GUARD 1b: a SHREDDED lane is not a pass, and the count is printed because the
  # shipped `rows()` turns 96 physical lines of C into 33 "rows", 18 of them noise.
  for lane, shreds in (("port", psh), ("oracle", osh)):
    if shreds:
      bad.append(f"{lane} lane SHREDDED {len(shreds)} line(s) into fake rows; first is "
                 f"L{shreds[0][0]} {shreds[0][1].strip()[:64]!r}")
  for lane, dups in (("port", pdup), ("oracle", odup)):
    if dups:
      bad.append(f"{lane} lane repeats {len(dups)} row name(s): {sorted(set(dups))[:5]}")

  # GUARD 2: THE LANE FORMAT. Row names here CONTAIN SPACES (`idx OPENCLsz1 k0 `,
  # and `PTX tensor_cores sm_75` in other units) and the two lanes print DIFFERENT
  # shapes -- `NAME = [v]` and `NAME = [v]   py=[w]`. A parser that insists on
  # `\s=\s`, or that splits on the FIRST `=`, matches nothing and reports a clean
  # zero; that produced three false zeros today, once at 19,252-row scale. So the
  # marker is required to be PRESENT in both lanes, and a lane that has rows but no
  # marker is BROKEN rather than empty.
  for lane, text, rows_ in (("port", porc, pr), ("oracle", orc_out, orr)):
    if rows_ and ROW_OPEN not in text:
      bad.append(f"{lane} lane produced {len(rows_)} row names but none carries the "
                 f"`{ROW_OPEN!r}` marker, so the reader and the writer disagree about "
                 f"the row shape")
  nop = [n for n, v in pr.items() if split_py(v)[1] is None]
  if nop:
    bad.append(f"{len(nop)} port row(s) carry no `py=` column, so they cannot be "
               f"reported against the pin: {sorted(nop)[:5]}")

  stray = sorted(set(orr) - set(pr))
  if stray:
    bad.append(f"oracle rows matching no port row: {stray[:8]}")
  ghost = sorted(set(pr) - set(orr) - set(exc))
  if ghost:
    bad.append(f"port rows the oracle did not answer and no exclusion names: {ghost[:8]}")

  if plant:
    if plant in orr:
      orr[plant] = (orr[plant] + "PLANTED") if orr[plant] else "PLANTED"
    elif plant in pr:
      pv, py = split_py(pr[plant])
      pr[plant] = pv + "PLANTED" + SEP + (py or "")
    else:
      bad.append(f"--plant {plant!r} names no row on either lane")

  agree, disagree, stale, gated = [], [], [], []
  for name in sorted(set(pr)):
    if name in exc or name not in orr:
      continue
    got = cells(split_py(pr[name])[0])
    want = expected(orr[name])
    gated.append(name)
    if got != want:
      disagree.append((name, got, want))
    else:
      agree.append(name)
    # The port's `py=` literal is a TRANSCRIPTION of the pin, so it is REPORTED
    # against the live call and never compared. It was 19 rows stale at HEAD.
    lit = split_py(pr[name])[1]
    if lit is not None and lit != joined(orr[name], want):
      stale.append((name, lit, joined(orr[name], want)))

  if not gated:
    bad.append("0 gated rows: the crosswalk and the two lanes share no row NAME. "
               "This is GUARD 2's failure mode and it is NOT a pass")
  if disagree:
    names = [n for n, _, _ in disagree]
    n, p, o = disagree[0]
    bad.append(f"{len(disagree)} gated row(s) DISAGREE with a live CPython call, and "
               f"every one is NAMED: {names}\n"
               f"        first `{n}`:\n        port {'|'.join(p)}\n        cpy  {'|'.join(o)}")
  return {"bad": bad, "port": pr, "oracle": orr, "gated": gated, "agree": agree,
          "disagree": disagree, "stale": stale,
          "refusals": [n for n, v in orr.items() if KEYERROR in v]}


def count_refusals(oracle_stderr):
  """THE ORACLE'S OWN REFUSAL REPORT, one LABEL per `REFUSED` line -- the text between the mark
  and the first colon, which is the row or the call, never the sentence after it.

  ⚠ THIS BECAME LOAD-BEARING; IT USED TO BE A PRINT. `renderer_oracle.py` used to put the
  `!KeyError` SENTINEL IN THE VALUE, so a refusal was visible in the very bytes the comparison
  read. It no longer does: the value carries the PORT's marker, because a sentinel no other lane
  can interpret put 9 of the 222 shared rows into disagreement and would have left the lane
  unwired at best and permanently red at worst (the measurement is in renderer_oracle.py's
  refusal comment). So this stderr report is now the ONLY place a refusal exists, and a printed
  count that nothing asserts is a comment. `unsilent_refusals()` is the assertion."""
  return [l.split(":")[0][len(REFUSED_MARK):].strip() for l in (oracle_stderr or "").splitlines()
          if l.startswith(REFUSED_MARK)]


def unsilent_refusals(port_rows, gated, stderr_labels):
  """GATED port rows whose own answer is the EMPTY marker and which the oracle did NOT report
  refusing.

  DERIVED, not typed. A refusal is exactly "every cell of the answer is empty", because the port
  has no exception channel and cstyle.bend:1074 and :1149 say what it prints when upstream raises
  -- so this list cannot fall out of date with the port the way a typed list of four row names
  would. A port that started printing a NAME where upstream raises stops appearing here, which is
  exactly the regression `--selftest`'s `refusal+` lane checks, and a port that grows a new
  empty-answer row is caught the day it is added.

  ⚠ RESTRICTED TO THE GATED ROWS, and that restriction is load-bearing in the safe direction. An
  EXCLUDED row is one CPython cannot answer at all -- `buft METAL`'s is empty for a reason that
  has nothing to do with `_render_dtype` -- so demanding a refusal report for one would ask the
  oracle to report an exception it never raised, and the assertion would be satisfied by a
  stderr line that lies. The question here is "of the rows WE COMPARED, did every one we compared
  by answering nothing get its refusal named", and an excluded row is not compared."""
  empty = sorted(n for n in gated
                 if all(not c.strip() for c in cells(split_py(port_rows[n])[0])))
  return [n for n in empty if not any(n in lab for lab in stderr_labels)]


def explain(res):
  """THE ROW BUDGET, BY FAMILY, WITH ITS DENOMINATOR. A gate that prints only a
  total cannot answer "which half of the file is thin", and a silently-ungated row
  is the failure this project keeps paying for."""
  pr, gated = res["port"], set(res["gated"])
  print(f"{'family':10} {'rows':>5} {'gated':>6} {'excluded':>9} {'uncovered':>10}")
  for f in FAMILY:
    rows = [n for n in pr if family(n) == f]
    if not rows:
      continue
    g = [n for n in rows if n in gated]
    e = [n for n in rows if n in EXCLUDED]
    u = [n for n in rows if n not in gated and n not in EXCLUDED]
    print(f"{f:10} {len(rows):5} {len(g):6} {len(e):9} {len(u):10}"
          + (f"   {u}" if u else ""))
  ref = [n for n in REFUSED_ROWS if n in pr]
  print(f"{'TOTAL':10} {len(pr):5} {len(res['gated']):6} {len(EXCLUDED):9} "
        f"{len(pr) - len(res['gated']) - len(EXCLUDED):10}")
  print(f"COVERAGE {len(res['agree'])}/{len(pr)} port rows compared to a live CPython "
        f"call, {len(res['disagree'])} disagreeing; {len(ref)} of those are rows where "
        f"`_render_dtype` REFUSES and the port answers the `.get` reading; "
        f"{len(EXCLUDED)} declared exclusions.")
  for n, why in EXCLUDED.items():
    print(f"  EXCLUDED `{n}`: {why}")


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--selftest", action="store_true")
  ap.add_argument("--plant", default=None)
  ap.add_argument("--explain", action="store_true")
  ap.add_argument("--port-stdout", default=None)
  ap.add_argument("--oracle-stdout", default=None)
  ap.add_argument("--oracle-stderr", default=None)
  a = ap.parse_args()
  if a.selftest:
    return selftest()
  if a.port_stdout or a.oracle_stdout:
    print("!! CAPTURED LANE INPUT. Not a live run. A verdict over a capture is evidence "
          "about the CAPTURE, never about the tree as it is now.")
  p = (subprocess.CompletedProcess([], 0, pathlib.Path(a.port_stdout).read_text(), "")
       if a.port_stdout else run(["./bin/bend", PORT]))
  o = (subprocess.CompletedProcess([], 0, pathlib.Path(a.oracle_stdout).read_text(),
                                   pathlib.Path(a.oracle_stderr).read_text()
                                   if a.oracle_stderr else "")
       if a.oracle_stdout else run([sys.executable] + ORACLE.split()))
  # ⚠ THIS LINE USED TO SAY "live" UNCONDITIONALLY AND PRINT THE CAPTURE'S rc. Both halves were
  # wrong in the same direction: a capture mode that never runs a lane reported `rc=0` beside the
  # word "live", which is an unexplained zero wearing a measurement's clothes. Now the rc comes
  # from the lane that actually ran, and a capture says so.
  print(f"{'CAPTURED' if a.port_stdout else 'live'} port lane rc={p.returncode}   "
        f"{'CAPTURED' if a.oracle_stdout else 'live'} oracle lane rc={o.returncode}")
  if (p.returncode or o.returncode) and not (a.port_stdout or a.oracle_stdout):
    print(f"lane failure: bend {' '.join(p.stderr.split())[-140:]} | "
          f"oracle {' '.join(o.stderr.split())[-140:]}")
    return 1
  if not (p.stdout.strip() and o.stdout.strip()):
    print("a lane printed NOTHING, so nothing was compared. This is GUARD 2's failure "
          "mode and it is NOT a pass")
    return 1
  # ⚠ A CAPTURE MUST CARRY ITS STDERR, or the refusal lane is DEAD and the gate reports that as
  # a disagreement rather than as a missing input. MEASURED: with `--oracle-stdout` and no
  # `--oracle-stderr`, `count_refusals("")` is 0 and `unsilent_refusals` fires on all nine rows
  # that answer the empty marker -- BROKEN, over lane text that is entirely sound, for a reason
  # that has nothing to do with either lane. A capture mode that can only ever be red is not a
  # capture mode. Refusing to guess is the honest answer, so a capture without one is refused.
  if a.oracle_stdout and not a.oracle_stderr:
    print("--oracle-stdout without --oracle-stderr discards the oracle's refusal report, which "
          "is the ONLY place a CPython KeyError exists. Refusing to run rather than reporting "
          "9 phantom disagreements")
    return 1
  res = judge(p.stdout, o.stdout, a.plant)
  if a.plant:
    print(f"[planted] `{a.plant}` corrupted in the CAPTURED OUTPUT ONLY; no file on "
          f"disk was touched")
  orc_rows = rows_strict(o.stdout)[0]
  print(f"port rows (rows_strict): {len(res['port'])}   oracle rows (rows_strict): "
        f"{len(orc_rows)}")
  # READER PARITY, NOT A SHRED COUNT. The old line subtracted one reader's name count from the
  # other's and called the difference "shredded rows"; with the fork in place it printed `-2`.
  # Two readers do not have a shred relationship -- they have a DISAGREEMENT SET, and it is
  # symmetric, so it is printed as one, with the names, because a count of differences is not a
  # coverage statement.
  shared = rows_shipped(o.stdout)
  only_shared, only_gate = sorted(set(shared) - set(orc_rows)), sorted(set(orc_rows) - set(shared))
  print(f"the SHARED reader (rebase-gate.py:rows()) over the SAME oracle stdout: "
        f"{len(shared)} names -- {len(only_shared)} only it finds, {len(only_gate)} only "
        f"rows_strict finds, {len(set(shared) & set(orc_rows))} in common")
  if only_shared or only_gate:
    print(f"  only the shared reader: {only_shared[:8]}")
    print(f"  only rows_strict     : {only_gate[:8]}")
  print(f"gated {len(res['gated'])}   agree {len(res['agree'])}   disagree "
        f"{[d[0] for d in res['disagree']][:6]}")
  print(f"STALE-LITERAL {len(res['stale'])} port `py=` literal(s) disagree with the live "
        f"call: {[s[0] for s in res['stale']][:8]}")
  ref = count_refusals(o.stderr)
  print(f"ORACLE-REFUSALS {len(ref)} CPython KeyError(s) the oracle reported on stderr: {ref}")
  # THE ASSERTION, and the reason the count above is not a comment. Since the value stopped
  # carrying the sentinel, this is the only place a refusal exists: a port row whose own answer
  # is the empty marker and which the oracle did NOT report refusing is a row that was compared
  # against a hand-written empty string and called agreement.
  silent = unsilent_refusals(res["port"], res["gated"], ref)
  bad = list(res["bad"]) + ([
    f"{len(silent)} port row(s) answer the empty marker and the oracle reported NO refusal for "
    f"them, so they were compared against an assertion rather than against CPython: {silent}"]
    if silent else [])
  print(f"UNREPORTED-REFUSALS {len(silent)}: every port row that answers `{PORT_KEYERROR}` and "
        f"the oracle did not name on stderr -- {silent or 'none'}")
  print(f"EXCLUDED {len(EXCLUDED)} port row(s) CPython cannot answer at all: "
        f"{sorted(EXCLUDED)}")
  print(("BROKEN" if bad else "AGREE"), *(["\n  - " + b for b in bad]))
  if a.explain or not bad:
    print()
    explain(res)
  return 1 if bad else 0


# ---------------------------------------------------------------- the self-test
#
# A self-test of the INSTRUMENT over two REAL lanes: a real .bend file and a real
# CPython call. It is NOT a claim about cstyle.bend. It is the control that shows
# the gate reports BOTH colours, kept separate from the real run so the real run's
# BROKEN verdict can never be mistaken for the gate itself being broken.
SELFTEST_BEND = (
  "import Base\n"
  "\n"
  "def main() -> IO(Unit):\n"
  "  do IO<Unit>: IO.print(String.concat([\"st BASE = [\", \"half,float\",\"]   py=[half,float]\"]))\n")

SELFTEST_ORACLE = (
  "from tinygrad.dtype import dtypes as D\n"
  "from tinygrad.helpers import Target\n"
  "from tinygrad.renderer.cstyle import CStyleLanguage\n"
  "cs = CStyleLanguage(Target('NULL'))\n"
  "print('st BASE = [' + ','.join(cs.type_map[d] for d in (D.f16, D.f32)) + ']')\n")

SELFTEST_BEND_REFUSED = (
  "import Base\n"
  "\n"
  "def main() -> IO(Unit):\n"
  "  do IO<Unit>: IO.print(String.concat([\"st FP8 = [\", \"\",\"]   py=[half]\"]))\n")

SELFTEST_REFUSED_ORACLE = (
  "import sys\n"
  "sys.path.insert(0, '.')\n"
  "from tinygrad.dtype import dtypes as D\n"
  "from tinygrad.helpers import Target\n"
  "from tinygrad.renderer.cstyle import CStyleLanguage\n"
  "cs = CStyleLanguage(Target('NULL'))\n"
  "try:\n"
  "  cs._render_dtype(D.fp8e4m3, 1)\n"
  "  print('st FP8 = [half]')\n"
  "except KeyError:\n"
  "  print('st FP8 = [KEYERROR]')\n".replace("KEYERROR", KEYERROR))


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
        r = judge(p.stdout, o.stdout, plant, exclusions={})
        bad = r["bad"]
        print(f"  {label:<8} -> {'BROKEN' if bad else 'AGREE':<7} "
              f"gated={r['gated']} agree={r['agree']} "
              f"disagree={[d[0] for d in r['disagree']]}")
        if label == "clean" and (bad or not r["agree"] or r["disagree"]):
          print("    SELFTEST FAILED: the clean pair must share a name and agree")
          return 1
        if label == "planted" and (not r["disagree"] or not bad):
          print("    SELFTEST FAILED: the planted disagreement was not seen")
          return 1
      # THE REFUSAL LANE. `!KeyError` must compare against the port's `""` marker and
      # must NOT compare against anything else -- this is the lane that turns an
      # exception into a gateable claim instead of a silent skip. The oracle side is
      # a LIVE `cs._render_dtype(dtypes.fp8e4m3, 1)`, and the `except` is the harness
      # reporting CPython's answer; nothing here restates cstyle.py.
      ref = pathlib.Path(td) / "r.py"
      ref.write_text(SELFTEST_REFUSED_ORACLE)
      ro = run([sys.executable, str(ref)])
      bend.write_text(SELFTEST_BEND_REFUSED)
      pr = run(["./bin/bend", str(bend.relative_to(REPO))])
      r = judge(pr.stdout, ro.stdout, None, exclusions={"st BASE": ""})
      ok = r["gated"] == ["st FP8"] and not r["disagree"]
      print(f"  refusal  -> {'AGREE' if ok else 'BROKEN':<7} gated={r['gated']} "
            f"disagree={[d[0] for d in r['disagree']]}  (!KeyError -> \"\")")
      if not ok:
        print(f"    SELFTEST FAILED: a CPython refusal did not compare against the port's "
              f"empty marker; oracle said {ro.stdout.strip()!r}")
        return 1
      # AND THE NEGATIVE: a port that answered the fp8 cell with a NAME instead of
      # the marker must be seen. A refusal lane that has never gone red is a lane
      # that may be accepting everything.
      bend.write_text(SELFTEST_BEND_REFUSED.replace('["st FP8 = [", "",',
                                                     '["st FP8 = [", "fp8e4m3",'))
      pr = run(["./bin/bend", str(bend.relative_to(REPO))])
      r = judge(pr.stdout, ro.stdout, None, exclusions={"st BASE": ""})
      print(f"  refusal+ -> {'BROKEN' if r['disagree'] else 'AGREE':<7} "
            f"disagree={[d[0] for d in r['disagree']]}  (a name where a refusal was)")
      if not r["disagree"]:
        print("    SELFTEST FAILED: a CPython refusal accepted a port answer that was not "
              "the marker")
        return 1
      print("SELFTEST OK: the SAME instrument reports AGREE on the clean pair, DISAGREE "
            "on the planted one, and maps a CPython refusal onto the port's marker")
      return 0
    finally:
      bend.unlink(missing_ok=True)


if __name__ == "__main__":
  sys.exit(main())