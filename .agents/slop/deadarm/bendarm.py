#!/usr/bin/env python3
r"""bendarm.py -- WHICH PORT DEFS DOES NO LANE EVER REACH?

    .venv/bin/python .agents/slop/deadarm/bendarm.py                 # the census, all entries
    .venv/bin/python .agents/slop/deadarm/bendarm.py --entry F.bend  # one entry, verbose
    .venv/bin/python .agents/slop/deadarm/bendarm.py --selftest      # the plant matrix

THE PORT SIDE OF THE LAW.  `.agents/slop/nvdup/NVDUP.md:62` calls the defect `D2` and says the
oracle half of it is invisible to every multiplicity census because a line that does not execute
has no output line to count.  The port half is worse, because a `.bend` file has no `sys.settrace`
and no `row()`:  a def nothing calls costs no row, costs no count, and costs no gate.  `agent-core`
already records one instance -- "Three mutations at `schedule/indexing.bend` found three functions
that were written, commented, and never called" -- and `.agents/slop/renderer/cstyle.bend:49`
records another that nothing has chased: `Ops.SHRINK` has no dtype in the fold, so there is no
`_render` and the kernel body is still a fixture.

HOW THE TRACE IS OBTAINED, and it is not instrumentation of the port at all -- it is the COMPILER.
`references/bend/bend2/comp.ts:3055` says, in a comment:

    // A def's JS name is its key between $s: each . a $, and any other non-word char a $ and its
    // three-digit code, so no two keys share one.

So `def fold(...)` compiles to `function $fold$(...)` in the JS emitter's output, ONE FUNCTION PER
DEF, with a reversible name.  `bend F.bend -o out.js` emits the whole program with `main` wired to
`io_exit`, and `bun out.js` prints the lane's rows in ~0.1s against ~2.5s for `bend F.bend` itself.
MEASURED on `renderer/cstyle.bend`: 227 rows out of the JS build, byte-identical to the bend run's
227, which is the CONTROL this tool asserts on every entry -- an instrumented program that prints
something other than the uninstrumented program prints is measuring a DIFFERENT program, and that
is the `py=`-column plant shape (`NVDUP.md:110`).

TWO KINDS OF ABSENCE, REPORTED SEPARATELY BECAUSE THEY ARE DIFFERENT CLAIMS:

  NOT-EMITTED   `comp.ts:3374` roots the emitted book at `main`, so a def the emitter did not
                write is a def nothing in this entry's call graph can reach.  Bend's own compiler
                says so, before any of my code runs.
  NOT-ENTERED   the def WAS emitted and the run never called it.  That can only be a dynamic path
                (a `match` arm no fixture reaches, a fuel loop that stops early, an argument a
                lane never supplies), and it needs the trace.

The `run-kernel.sh:22` LESSON IS BUILT IN.  Every artefact -- the `-o` target, the instrumented
copy, the lane text -- lands in `$TMPDIR`.  The port tree is read and never written, so the whole
census is plantable against a copy, which is the only reason a plant can be a control at all.
"""
import argparse, json, os, pathlib, re, subprocess, sys, tempfile, time

REPO = pathlib.Path(__file__).resolve().parents[3]
JS_TIMEOUT = float(os.environ.get("BENDARM_JS_TIMEOUT", "240"))
BEND = REPO / "bin/bend"
SLOP = REPO / ".agents/slop"

DEF = re.compile(r"^(\s*)def\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s*\(", re.M)
IMPORT = re.compile(r"^\s*import\s+(\S+)", re.M)
BEND_CALL = re.compile(r"(?:\./bin/bend|bin/bend|\bbend\b)\s+((?:[\w./-]+/)*[\w.-]+\.bend)\b")
FUN = re.compile(r"^function (\$[^\s(]*)\((.*)$", re.M)


def js_sat(k):
  """comp.ts:3055 `js_sat`, transcribed.  `$` + name with `.` -> `$` and every other non-word
  char -> `$` + three-digit code, + `$`.  Reversible, which is what makes the trace addressable."""
  return "$" + re.sub(r"\W",
                      lambda m: "$" if m.group(0) == "." else "$%03d" % ord(m.group(0)), k) + "$"


def js_un(sat):
  """`js_sat` inverted: `$047` first (it is a code, not a dot), THEN every remaining `$` is a dot.
  The order is load-bearing and the first version got it backwards, turning `../LAWS/spec.bfloat16`
  into `...047LAWS.047spec.bfloat16` -- a name that resolves to nothing and would have been
  reported as an unreachable def."""
  return re.sub(r"\$(\d{3})", lambda m: chr(int(m.group(1))), sat[1:-1]).replace("$", ".")


# ---------------------------------------------------------------- sources
def defs_of(path):
  """[(full_name, line, text)] for every `def` in one .bend file, comments excluded.

  The name is taken VERBATIM from the `def` line and is already fully qualified: Bend resolves
  `def BArg.name` in a file imported as `A` to `A.BArg.name`, and the emitter prints the
  unqualified `BArg.name`.  So no alias resolution is needed -- and NOT needing one is the point,
  because "a name is not a binding" has been wrong four times on this project."""
  out = []
  for i, line in enumerate(pathlib.Path(path).read_text(errors="replace").splitlines(), 1):
    m = re.match(r"^(\s*)def\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s*\(", line)
    if m:
      out.append((m.group(2), i, line.strip()[:88]))
  return out


def imports_of(path):
  out = []
  for m in IMPORT.finditer(pathlib.Path(path).read_text(errors="replace")):
    t = m.group(1)
    if t.endswith(".bend"):
      out.append((pathlib.Path(path).parent / t).resolve())
  return out


def closure(entry):
  """The entry plus its transitive `import` closure, as real paths.  Resolved relative to the
  IMPORTING file, because `LAWS/spec.bend` is imported as `../LAWS/spec.bend` from two directories
  and a flat name lookup resolves neither."""
  seen, stack, missing = [], [pathlib.Path(entry).resolve()], []
  while stack:
    p = stack.pop()
    if p in seen or not p.exists():
      if not p.exists():
        missing.append(p)
      continue
    seen.append(p)
    stack.extend(imports_of(p))
  return seen, missing


def entry_points():
  """Every `.bend` file some instrument in the tree actually RUNS, found by reading the
  instruments.  `agent-core.md` is explicit that "a name is not a binding": a `.bend` file existing
  is not a lane existing, so the population is derived from `./bin/bend <path>` occurrences and
  every path is checked to exist before it is called an entry."""
  found = {}
  for pat in ("*.py", "*.sh", "*/*.py", "*/*.sh", "*/*/*.py", "*/*/*.sh"):
    for p in sorted(SLOP.glob(pat)):
      try:
        text = p.read_text(errors="replace")
      except OSError:
        continue
      for m in BEND_CALL.finditer(text):
        rel = m.group(1)
        for cand in (REPO / rel, SLOP / rel, p.parent / rel):
          if cand.exists() and cand.suffix == ".bend":
            found.setdefault(str(cand.resolve()), set()).add(f"{p.relative_to(REPO)}:{_lineno(text, m)}")
            break
  # THE OTHER HALF OF THE POPULATION.  Most port lanes are run by naming the FILE
  # (`./bin/bend tinybendygrad/renderer/cstyle.bend`), which no instrument ever spells out, so a
  # population built only from `bend <path>` occurrences would miss the majority of the lanes.  A
  # file that DECLARES `def main` is runnable by definition, and the citation says exactly that
  # rather than pretending an instrument named it -- "a name is not a binding" cuts both ways.
  for p in sorted(REPO.glob("tinybendygrad/**/*.bend")) + sorted(SLOP.glob("**/*.bend")):
    try:
      if "def main(" not in p.read_text(errors="replace"):
        continue
    except OSError:
      continue
    # A `.bend` under `.agents/slop/` that sits INSIDE a nested `tinybendygrad/` is a WORKTREE
    # SNAPSHOT, not a lane: `proof-close/mut*/`, `dd-cone-wt/revert-*/`, `xd1/wt/`,
    # `ddcheck/tree/` hold eight near-copies of the port between them, and all 1300 of them have a
    # `def main`.  Counting them would have made this census report "1342 entries" and the
    # denominator would have been a pile of copies -- which is the `Bool.pick` failure in a new
    # costume: a number that cannot be wrong because nothing checks what it counts.
    # A `.bend` DEEPER than two levels under `.agents/slop/` is a WORKTREE SNAPSHOT, not a lane:
    # `proof-close/mut*/`, `dd-cone-wt/revert-*/`, `xd1/wt/`, `ddcheck/tree/` hold near-copies of
    # the port between them -- all of them with a `def main`, all of them counted, and none of them
    # a lane anybody runs.  The depth test is stated rather than tuned: a file at
    # `.agents/slop/<dir>/<name>.bend` is a probe a unit wrote; anything below that is a tree.
    if SLOP in p.parents and len(p.relative_to(SLOP).parts) > 2:
      continue
    found.setdefault(str(p.resolve()), set()).add("has `def main` (run directly by ./bin/bend)")
  return found


def _lineno(text, m):
  return text.count("\n", 0, m.start()) + 1


# ---------------------------------------------------------------- build
def build(entry, work):
  """`bend entry -o work/x.js`.  Returns (ok, stderr).  Nothing is written inside the repo."""
  out = work / (pathlib.Path(entry).stem + ".js")
  r = subprocess.run([str(BEND), str(entry), "-o", str(out)], cwd=str(REPO),
                     capture_output=True, text=True)
  return (r.returncode == 0 and out.exists()), (r.stderr or "")[-400:], out


TAGTEST = re.compile(r"([A-Za-z0-9_$]+)\.\$ === \"([^\"]+)\"")


def instrument(js_path, work, arms=False):
  r"""Insert one `__hit(<full name>)` at the head of every emitted def, and a dump on exit.

  `__hit` is a bare function call, so the instrumentation adds one call per def ENTRY and nothing
  else: no counter, no Set, no per-argument work.  The set lives in a plain object and the dump
  happens in a `process.on('exit')` handler, which bun runs for a normal exit.

  WITH `arms=True` it ALSO rewrites every constructor test the emitter wrote,

      _x.$ === "OpsADD"        ->     __arm("fold", "OpsADD", _x.$) === "OpsADD"

  which records `(enclosing def, constructor)` the first time that test is TRUE.  The key is
  `(def, tag)` and NOT a source line index, so no alignment between the emitted `if`s and the
  source `case`s has to be assumed -- a `case Tag{}` arm IS the predicate `(its def, Tag)`, and two
  arms of one def cannot share a constructor.  `__arm` returns its argument unchanged, so the
  comparison's value, and therefore every byte of the lane, is untouched -- which is what the
  byte-identity control on every entry checks."""
  src = pathlib.Path(js_path).read_text()
  names = []
  chunks = []
  bounds = [(m.start(), m) for m in re.finditer(r"^function (\$[^\s(]*)\(", src, re.M)]
  bounds.append((len(src), None))
  out, last = [], 0
  for start, m in bounds[:-1]:
    chunk_end = bounds[bounds.index((start, m)) + 1][0]
    nm = js_un(m.group(1))
    names.append(nm)
    brace = src.index("{", start)
    out.append(src[last:brace + 1])
    out.append(f'__hit({json.dumps(nm)});')
    body = src[brace + 1:chunk_end]
    if arms:
      body = TAGTEST.sub(
        lambda t: f'__arm({json.dumps(nm)}, {json.dumps(t.group(2))}, {t.group(1)}.$) === "{t.group(2)}"',
        body)
    out.append(body)
    last = chunk_end
  out.append(src[last:])
  body = "".join(out)
  head = ('const __H = Object.create(null);\n'
          'const __A = Object.create(null);\n'
          'function __hit(n) { __H[n] = 1; }\n'
          'function __arm(d, t, x) { if (x === t) __A[d + "|" + t] = 1; return x; }\n'
          'process.on("exit", () => {'
          ' process.stderr.write("__HITS__" + JSON.stringify(Object.keys(__H)) + "\\n");'
          ' process.stderr.write("__ARMS__" + JSON.stringify(Object.keys(__A)) + "\\n"); });\n')
  path = work / (pathlib.Path(js_path).stem + ".hit.js")
  path.write_text(head + body)
  return path, names


def run_js(path, cwd=REPO):
  r"""⚠ `subprocess.TimeoutExpired` IS CAUGHT, not propagated, and the first version let it out.
  `.agents/slop/ga-ins-wip.bend` emits JS that never returns -- a WIP probe with an unbounded fuel
  loop -- and the uncaught exception killed the whole 282-entry sweep at entry 63 with no TSV
  written at all.  **A census that dies on its slowest cell reports nothing**, so a lane that does
  not finish is a RESULT (`hang`) and the sweep carries on."""
  try:
    r = subprocess.run(["bun", str(path)], cwd=str(cwd), capture_output=True, text=True,
                       timeout=JS_TIMEOUT)
  except subprocess.TimeoutExpired as e:
    out = (e.stdout or b"").decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
    return None, out, [], [], f"hang: the JS lane did not finish in {JS_TIMEOUT}s"
  hits, arms = [], []
  for line in r.stderr.splitlines():
    if line.startswith("__HITS__"):
      hits = json.loads(line[len("__HITS__"):])
    elif line.startswith("__ARMS__"):
      arms = json.loads(line[len("__ARMS__"):])
  return r.returncode, r.stdout, hits, arms, ""


# ---------------------------------------------------------------- census
def census_entry(entry, work, keep_build=False):
  """Per-entry: which defs in the entry's import closure were NOT emitted, which were emitted and
  NOT entered, and -- the control -- whether the instrumented lane's stdout is byte-identical to
  the uninstrumented lane's.  `main` and the runtime's own defs are excluded from the verdict."""
  rec = {"entry": str(entry), "ok": False, "detail": "", "emitted": [], "entered": [],
         "not_emitted": [], "not_entered": [], "closure": [], "control": None,
         "rows": 0, "rc": None, "arms_seen": 0, "arms_total": 0, "arms_dead": [],
         "arms_unmeasured": 0}
  ok, err, js = build(entry, work)
  if not ok:
    rec["detail"] = f"bend -o failed: {err}"
    return rec
  plain_rc, plain_out, _, _, plain_note = run_js(js)
  hit_js, names = instrument(js, work, arms=True)
  rc, out, hits, armhits, note = run_js(hit_js)
  rec["ok"] = bool(plain_note == "" and note == "")
  rec["rc"] = rc
  rec["entered"] = sorted(hits)
  rec["emitted"] = sorted(names)
  rec["rows"] = out.count("\n")
  seen_arms = set(armhits)
  rec["arms_seen"] = len(seen_arms)
  # THE CONTROL.  Byte-identical, or the numbers below are about a program nobody ships.  A
  # mismatch is reported as a control failure and the cell's verdicts are withheld.
  rec["control"] = plain_note or note or (
      "byte-identical" if out == plain_out else
      f"CONTROL FAILED: instrumented {len(out)}B != plain {len(plain_out)}B")
  files, missing = closure(entry)
  rec["closure"] = [str(f) for f in files]
  have = set(rec["emitted"])
  entered = set(rec["entered"])
  for f in files:
    for nm, ln, txt in defs_of(f):
      if nm in ("main",) or nm.startswith("IO.") or nm.startswith("List.") or nm.startswith("String.") \
         or nm.startswith("Nat.") or nm.startswith("U32.") or nm.startswith("U64.") \
         or nm.startswith("Bool.") or nm.startswith("F64.") or nm.startswith("Dict.") \
         or nm.startswith("Maybe.") or nm.startswith("Option.") or nm.startswith("Array."):
        continue
      # `emitted`/`entered` hold UN-MANGLED names (js_un was applied when they were built), so the
      # comparison is on the Bend name.  The first version compared a mangled name against an
      # unmangled set and reported all 2302 def-sites of cstyle.bend's own closure as NOT-EMITTED
      # -- including `dev_base`, which the emitter demonstrably wrote.  A wrong key is a tool that
      # says everything is dead.
      where = f"{rel(f)}:{ln}"
      if nm not in have:
        rec["not_emitted"].append((where, nm, txt))
      elif nm not in entered:
        rec["not_entered"].append((where, nm, txt))
      # ---- ARMS.  An arm is `(def, constructor)`.  Two arms of one def cannot share a
      # constructor, so the pair is the identity and no source-line alignment is needed.
      if nm in entered:
        for aline, atag in arms_of(f, nm):
          rec["arms_total"] += 1
          if atag is None:
            rec["arms_unmeasured"] += 1          # a Nat/U32/Str pattern: no `.$ ===` test exists
          elif f"{nm}|{atag}" not in seen_arms:
            rec["arms_dead"].append((f"{where}", f"case {atag}", aline))
  return rec


# `case Tag{...}:` and `case Tag:` are CONSTRUCTOR arms -- the two forms the emitter turns into a
# `.$ === "Tag"` test.  Everything else (`case 0n:`, `case _:`, `case s if s == "x":`) is NOT
# MEASURED and is counted, because a census that quietly drops the arms it cannot see is the
# multiplicity census's mistake all over again.
ARMC = re.compile(r"^(\s*)case\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::|\{)")
# `case _:` matches ARMC with the tag `_`, and `_` is unreachable BY CONSTRUCTION -- so every def
# with a catch-all read as carrying a dead arm.  That is the tool inventing a finding out of its
# own selector, which is the `Bool.pick` failure wearing a grammar.  A catch-all is UNMEASURED.


def arms_of(path, want):
  """[(line, tag-or-None)] for every `case` arm of the def `want` in `path`."""
  out = []
  inside = False
  base = None
  for i, line in enumerate(pathlib.Path(path).read_text(errors="replace").splitlines(), 1):
    m = re.match(r"^(\s*)def\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s*\(", line)
    if m:
      inside = m.group(2) == want
      base = len(m.group(1))
      continue
    if not inside or line.lstrip().startswith("#"):
      continue
    cm = ARMC.match(line)
    if cm and len(cm.group(1)) > base and cm.group(2) != "_":
      out.append((i, cm.group(2)))
    elif re.match(r"^\s*case\b", line) and len(line) - len(line.lstrip()) > base:
      out.append((i, None))
  return out


def rel(f):
  try:
    return str(f.relative_to(REPO))
  except ValueError:
    return str(f)


def plant_root(work):
  """A `$TMPDIR` COPY of the port tree, imports and all.

  This is `run-kernel.sh:22` turned into a capability.  `ROOT=/Users/cyberistic/...` hard-coded at
  line 22 means a lane cannot be run against a copy, and a plant that cannot be planted is not a
  control -- it is a comment.  Copying `tinybendygrad/` WHOLE is also the only way a `.bend` plant
  can resolve its relative imports: a single file copied out of the tree fails on
  `import ./__init__.bend`, which is the recorded "$TMPDIR scratch copy cannot resolve a relative
  import" wall that cost one unit 22 phantom blind spots.  The live tree is never written."""
  dst = work / "plant"
  subprocess.run(["cp", "-R", str(REPO / "tinybendygrad"), str(dst)], check=True)
  return dst


PLANT_PROBE = '''import Base

type Probe is Data:
  Live0{}
  Live1{}
  Dead0{}

def probe_of(p: Probe) -> String:
  match p:
    case Live0{}: "L0"
    case Live1{}: "L1"
    case Dead0{}: "D0"

def probe_name(n: U32) -> String:
  match n:
    case 0: probe_of(Live0{})
    case 1: probe_of(Live1{})
    case _: probe_of(Dead0{})

def probe_rows() -> List<&2, String>:
  [probe_name(0), probe_name(1)]

def main() -> IO(Unit):
  IO.print(String.concat(List.append(&2, String, ["probe_rows="], probe_rows())))
'''

PLANTED_PROBE = '''import Base

type Probe is Data:
  Live0{}
  Live1{}
  Dead0{}
  Extra{}

def probe_unentered_of(p: Probe) -> String:
  match p:
    case Live0{}: "U0"
    case Live1{}: "U1"
    case Dead0{}: "U0"
    case Extra{}: "U0"

def probe_unentered(n: U32) -> String:
  match n:
    case 0: probe_unentered_of(Live0{})
    case 1: probe_unentered_of(Live1{})
    case _: probe_unentered_of(Dead0{})

def probe_of(p: Probe) -> String:
  match p:
    case Live0{}: "L0"
    case Live1{}: "L1"
    case Dead0{}: "D0"
    case Extra{}: "X0"

def probe_name(n: U32) -> String:
  match n:
    case 0: probe_of(Live0{})
    case 1: probe_of(Live1{})
    case _: probe_unentered(9)

def probe_rows() -> List<&2, String>:
  [probe_name(0), probe_name(1)]

def main() -> IO(Unit):
  IO.print(String.concat(List.append(&2, String, ["probe_rows="], probe_rows())))
'''


def selftest(entry):
  r"""SIX CELLS ON A SELF-CONTAINED PROBE, plus the real entry as the DISARM.

  ⚠ WHY THE PLANTS ARE NOT PLANTED INTO `cstyle.bend`.  They were, and both fired: at 16:47 on
  2026-10-04 the two cstyle plants read NOT-ENTERED 0 -> 1 and DEAD-ARM 75 -> 76 with the lane's
  227 rows byte-identical.  Then another unit began editing `renderer/cstyle.bend`, and by 17:37 it
  carried FIVE copies of `def BArg.name` (lines 159, 196, 233, 270, 307), so `bend -o` refuses it
  with "duplicate declaration: BArg.name" and every plant became unplantable.  **A control whose
  host is being rewritten is not a control**, so the plants moved to a probe that is generated,
  compiles in isolation (`import Base` only, so no relative import to break), and cannot be edited
  by anybody.  `agent-core.md` says to use a local reader rather than fighting a concurrent unit;
  this is the same move applied to a control.

  TWO PLANTS, ONE PER CENSUS, because they measure different things:

    DEF  `probe_unentered` / `probe_unentered_of` are declared and CALLED, but only from a `case _:`
         that `probe_rows` never reaches -- it passes 0 and 1.  Both are therefore EMITTED and NOT
         ENTERED.  This is the `case 6:` shape that worked in cstyle: a new arm on an existing
         `match` over a parameter, calling a def nothing else calls.
    ARM  `probe_unentered_of`'s `case Dead0{}` is an arm nothing builds.  Same shape as the cstyle
         plant, which extended cstyle's own two-variant `Kv` by one constructor.

  ⚠ AND THE PLANT THAT COULD NOT BE WRITTEN, which is a recorded trap rather than a new one.
  `Bool.pick(cond, a, b)` cannot make a value unevaluated: `base.bend:504` is
  `def Bool.pick(-A: Type, c: Bool, a: A, b: A) -> A: match c: ...` and Bend's arguments are
  STRICT, so both arms are evaluated before `pick` chooses.  The first plant wrapped the whole list
  in `Bool.pick(List<&2,String>, Bool.not(True{}), [probe_name(0)], Nil{})`, every `probe_name`
  call still ran, and the census read NOT-ENTERED 0 -> 0.  That is `agent-core.md`'s "`Bool.pick`
  **chooses** an arm; it does not **sequence** one", reached from a new angle: not even a dead
  arm's ARGUMENTS are skipped.  `match True{}:` and `match deadarm_flag():` are refused outright --
  "a match cannot scrutinize a computed value: give it its own def" -- so a dead arm has to hang
  off an existing `match` over a PARAMETER, which is why the probe's `probe_name` takes `n: U32`."""
  with tempfile.TemporaryDirectory() as td:
    work = pathlib.Path(td)
    print("[selftest] DISARM first: the REAL entry, instrumented only by __hit()/__arm().")
    base = census_entry(pathlib.Path(entry), work)
    _show(base)
    p0 = work / "probe.bend"
    p0.write_text(PLANT_PROBE)
    p1 = work / "probe.planted.bend"
    p1.write_text(PLANTED_PROBE)
    c0, c1 = census_entry(p0, work), census_entry(p1, work)
    print(f"  PROBE   {p0.name:<26} the unplanted probe: 2 called defs, 5 of its arms reachable")
    _show(c0)
    print(f"  PLANT   {p1.name:<26} two uncalled defs + one unbuilt `case Dead0{{}}` arm")
    _show(c1)
    b_ne, b_ad = len(c0["not_entered"]), len(c0["arms_dead"])
    checks = [
      ("DISARM: the real entry builds, prints rows, and its instrumented lane is BYTE-IDENTICAL "
       "to the plain one", base["ok"] and base["control"] == "byte-identical" and base["rows"] > 0),
      ("DISARM: the real entry's own census is non-trivial -- it has constructor arms to miss",
       base["arms_total"] > 0),
      ("PLANT: the base probe has NO uncalled def and exactly ONE dead arm -- `probe_of`'s own "
       "`case Dead0{}`, dead because nothing builds a `Dead0` -- so both deltas are attributable",
       c0["ok"] and c0["control"] == "byte-identical" and not c0["not_entered"]
       and len(c0["arms_dead"]) == 1),
      ("PLANT-DEF: two planted defs are EMITTED and NOT ENTERED -- emitted +2, not-entered 0 -> 2, "
       "so NOT-EMITTED and NOT-ENTERED are not the same column",
       c1["ok"] and c1["control"] == "byte-identical"
       and len(c1["emitted"]) == len(c0["emitted"]) + 2 and len(c1["not_entered"]) == b_ne + 2),
      ("PLANT-ARM: the dead arm is seen by the (def,tag) census and the lane's ROWS do not move "
       "-- which is the entire claim: a dead arm costs nothing to count",
       c1["ok"] and len(c1["arms_dead"]) == b_ad + 1 and c1["rows"] == c0["rows"]
       # The two cells live at DIFFERENT PATHS, so the sets are compared on the arm and not
       # on `where` -- comparing whole tuples made the delta 2 and the cell red for a reason
       # that had nothing to do with the defect.
       and {a for _, a, _ in c1["arms_dead"]} - {a for _, a, _ in c0["arms_dead"]}
       == {"case Extra"}),
      ("PLANT-ARM: the dead arm is INVISIBLE to the def-level census -- the two defs are the only "
       "thing that moved -- so neither census substitutes for the other",
       len(c1["not_entered"]) == b_ne + 2
       and all("probe_unentered" not in w for w, _, _ in c0["arms_dead"])),
    ]
    print()
    ok = True
    for desc, got in checks:
      print(f"  [{'PASS' if got else 'FAIL'}] {desc}: {got}")
      ok = ok and got
    print(f"BENDARM SELFTEST {'OK' if ok else 'FAILED'}")
    return ok

def _show(rec):
  print(f"  {pathlib.Path(rec['entry']).name:<28} ok={rec['ok']} rows={rec['rows']:>5} "
        f"emitted={len(rec['emitted']):>4} entered={len(rec['entered']):>4} "
        f"NOT-EMITTED={len(rec['not_emitted']):>4} NOT-ENTERED={len(rec['not_entered']):>4} "
        # `tags` counts EVERY distinct (def, constructor) the instrument SAW, including Base's own
        # `Nil`/`Some`/`Con` tests, so it is routinely LARGER than `arms`, which counts only the
        # `case` arms written in this entry's own SOURCE and only in defs the lane entered.  The
        # first label printed them the other way round and read `arms 251/59`, which looks like a
        # bug in the tool -- and it was a bug in the tool, in the label.
        f"tags-seen(incl Base)={rec['arms_seen']:>4} arms(source)={rec['arms_total']:>4} "
        f"DEAD-ARM={len(rec['arms_dead']):>4} unmeasured={rec['arms_unmeasured']:>4}  "
        f"{rec['control'] or rec['detail']}")


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--selftest", action="store_true")
  ap.add_argument("--entry", help="one .bend entry to census")
  ap.add_argument("--limit", type=int, default=0, help="cap the number of entries")
  ap.add_argument("--report", help="write the full table here (TSV)")
  ap.add_argument("--verbose", action="store_true")
  a = ap.parse_args()
  default_entry = REPO / "tinybendygrad/renderer/cstyle.bend"
  if a.selftest:
    return 0 if selftest(a.entry or default_entry) else 1
  with tempfile.TemporaryDirectory() as td:
    work = pathlib.Path(td)
    if a.entry:
      recs = [census_entry(pathlib.Path(a.entry), work)]
      for r in recs:
        _show(r)
    else:
      eps = entry_points()
      items = sorted(eps.items())
      if a.limit:
        items = items[:a.limit]
      print(f"BENDARM -- {len(items)} entry point(s) some instrument runs")
      recs = []
      for i, (e, cites) in enumerate(items):
        t0 = time.time()
        rec = census_entry(pathlib.Path(e), work)
        rec["cites"] = sorted(cites)
        rec["secs"] = round(time.time() - t0, 1)
        _show(rec)
        recs.append(rec)
    ok = [r for r in recs if r["ok"] and r["control"] == "byte-identical"]
    print(f"\n  entries examined            {len(recs)}")
    print(f"  entries whose lane is byte-identical instrumented vs plain  {len(ok)}")
    print(f"  NOT-EMITTED def-site pairs   {sum(len(r['not_emitted']) for r in ok)}")
    print(f"  NOT-ENTERED def-site pairs  {sum(len(r['not_entered']) for r in ok)}")
    if a.verbose:
      for r in recs:
        for kind in ("not_emitted", "not_entered"):
          for where, nm, txt in r[kind][:400]:
            print(f"  {kind.upper():<12} {where:<48} def {nm}")
        for where, arm, aline in r["arms_dead"][:400]:
          print(f"  DEAD-ARM     {where:<48} {arm}   (source line {aline})")
    if a.report:
      with open(a.report, "w") as fh:
        fh.write("entry\tkind\twhere\tname\ttext\n")
        for r in recs:
          for kind in ("not_emitted", "not_entered"):
            for where, nm, txt in r[kind]:
              fh.write(f"{r['entry']}\t{kind}\t{where}\t{nm}\t{txt}\n")
          for where, arm, aline in r["arms_dead"]:
            fh.write(f"{r['entry']}\tarm_dead\t{where}\t{arm}\tline {aline}\n")
      print(f"  wrote {a.report}")
  return 0


if __name__ == "__main__":
  sys.exit(main())