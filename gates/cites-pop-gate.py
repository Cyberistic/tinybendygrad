#!/usr/bin/env python3
"""cites-pop-gate.py -- IS THE CITATION POPULATION OF `checks/cites-census.py` A POPULATION?

THE QUESTION.  A census is only as good as the set of files it reads.  `cites-census.py`
declares its population in one line, `EXTS = (".md", ".py")`, and filters
`git ls-tree -r HEAD` with it.  Doctrine 1 in `AGENTS.md`: a suffix set is not a
population.  This gate measures what that line costs, and plants the failure in both
directions -- a file the population CANNOT SEE, and a file it SHOULD NOT COUNT.

SIX CLAUSES, EACH WITH ITS OWN DENOMINATOR.  NONE IS A VERDICT ABOUT THE TREE:

  I    COVERAGE    committed text the census does not read, by extension.
  II   YIELD       claims inside that text, read with the rule the census ALREADY applies
                   to `.py` (COMMENTS ONLY) widened by language.
  III  ACCIDENT    `#` languages are ALIVE BY ACCIDENT -- Python's `tokenize` also calls
                   `#` a comment -- so adding `.bend` LOOKS like it works.  `//` and
                   data languages stay DEAD.  Widening the suffix is not the fix.
  IV   THE REPAIR  widening `EXTS` to include `.bend` NO LONGER DIES.  `9b1f5ac00` taught
                   `prose()` to REFUSE -- `Unproseable`, named with the line it stopped at --
                   and `Unproseable` IS a `tokenize.TokenError`, so every live caller's
                   `except (TokenError, IndentationError)` covers it.  The file still yields
                   ZERO claims, so the suffix is still not the fix; the REASON changed, and a
                   clause that cannot say which reason it holds is holding none.
  V    B vs C      of the subjects the hidden text cites and cannot resolve: RENAMED (the
                   path is in some commit of this repo) vs NEVER-EXISTED (in none).
  VI   OVERCOUNT   files that MATCH the suffix and should not be counted: `.agents/slop/`
                   scratch, and the basename collisions with live gates.

READ-ONLY ON THE TREE.  It writes nothing but its own scratch under `mkdtemp()`, and it
loads `checks/cites-census.py` BY PATH -- `gates/` is not a package, and putting it on
`sys.path` would make `cites_census` a name any file in the tree could shadow
(`gates/gates-pop.py:150-161` says this and is right).

EXIT: PASS 0, FAIL 1, REFUSED 3, SKIP 4, DEAD 5.  A CLAUSE THAT CANNOT RUN IS `REFUSED`,
NEVER A ZERO: `0` and `DEAD` are different findings and the token is the only witness.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import tokenize
import warnings
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PASS, FAIL, REFUSED, SKIP, DEAD = "PASS", "FAIL", "REFUSED", "SKIP", "DEAD"
EXITS = {PASS: 0, FAIL: 1, REFUSED: 3, SKIP: 4, DEAD: 5}

# THE POPULATION IS LOADED FROM THE CENSUS, NEVER RETYPED.  A SECOND COPY OF A CONSTANT IS
# A CONTRACT WITH NO GENERATOR, AND A GATE THAT HARDCODES WHAT IT IS AUDITING CANNOT
# AUDIT A CHANGE TO IT.
DECLARED_SOURCE = ROOT / "checks/cites-census.py"

# A CAPTURED ARTEFACT IS NOT PROSE.  `AGENTS.md` fixes these three extensions' MEANING:
# "`.rows` for expected values and row dumps, `.out`/`.err` for captured streams".  A
# captured stream HOLDS a transcript, it does not MAKE claims about the tree.  This is the
# one filter here, and it is named rather than silent.
ARTEFACTS = (".rows", ".out", ".err")

# WHAT A LINE-COMMENT LANGUAGE CALLS A COMMENT.  `prose()` already reads a `.py` by its
# comments and docstrings; this is the same rule widened, and it is what makes `//` and
# data languages measurable rather than invisible.
COMMENT_MARKS = ("#", "//", "*", "/*")

# THE FILE THAT CARRIES THE NUL.  Named, not discovered by glob, because a plant whose
# fixture can silently stop existing is a plant that stops failing.  It was named
# `CRASH_WITNESS` while the extractor died on it; `9b1f5ac00` taught `prose()` to refuse
# instead, and a name that says CRASH of a file that no longer crashes is a name that will
# be believed after it stops being true.  What the file IS has not changed: the one
# committed text file holding a NUL byte.
NUL_WITNESS = "tinybendygrad/runtime/ops_dsp.bend"

# THE ARM `9b1f5ac00` ADDED, VERBATIM AS TEXT.  The falsification arm deletes it FROM A COPY
# of the census and loads that copy by path, so `checks/cites-census.py` is never touched.  If
# this string stops matching the census the mutation silently applies to nothing and the arm
# would assert a property of an UNMUTATED file, which is a vacuous pass -- so the arm asserts
# that the mutation changed the bytes rather than trusting that it did.
SYSTEMERROR_ARM = """  if isinstance(exc, SystemError) and isinstance(exc.__cause__, SyntaxError):
    return (exc.__cause__.lineno, f"SystemError<-{type(exc.__cause__).__name__}")
"""


def load_census(source: Path = DECLARED_SOURCE):
  """`checks/cites-census.py` BY PATH.  Absent -> the caller REFUSES, naming the file.
  `source` is a parameter for the falsification arm only, which loads a COPY carrying the
  pre-fix arm; the default is the census itself, so the population is never a second copy
  of a constant."""
  spec = importlib.util.spec_from_file_location("cites_census_by_path", source)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def committed() -> list[str]:
  """`git ls-tree -r HEAD` IS the tree's own declaration of itself.  NOT `git ls-files`,
  which reads the INDEX, and this repo arms that index with intent-to-add placeholders by
  design (`jj git colocation`), so it answers hundreds of paths HEAD does not contain while
  `git diff --cached` names 0 (`checks/cites-census.py:66-74` measures that and is right).
  `references/` is excluded HERE because it is GITIGNORED and therefore not in HEAD; every
  claim about it is answered against the DISK in clause VII instead."""
  r = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"], cwd=ROOT,
                     capture_output=True, text=True)
  if r.returncode != 0:
    raise RuntimeError(f"git ls-tree rc={r.returncode}: {r.stderr.strip()}")
  return sorted(p for p in r.stdout.splitlines() if p)


def ever_committed(wanted: set[str]) -> set[str]:
  """Which of `wanted` appear in SOME commit of this repo.  One pass, then a set test:
  asking `git log` per path is one process per path."""
  r = subprocess.run(["git", "log", "--all", "--name-only", "--format=%H"], cwd=ROOT,
                     capture_output=True, text=True)
  if r.returncode != 0:
    raise RuntimeError(f"git log rc={r.returncode}: {r.stderr.strip()}")
  return {ln for ln in r.stdout.splitlines() if ln in wanted}


def extname(path: str) -> str:
  """The extension of the LAST path segment, or `""` for an extensionless file.
  `path.rsplit(".", 1)[-1]` on `agents/slop/.../launch-ones-000/wall` returns
  `000/wall` -- a directory crossed as if it were an extension, which is how a census
  prints 75 invented languages.  A dot in a DIRECTORY is not an extension."""
  base = path.rsplit("/", 1)[-1]
  return base.rsplit(".", 1)[-1] if "." in base else ""


def comments_of(text: str) -> list[tuple[int, str]]:
  return [(i, l) for i, l in enumerate(text.splitlines(), 1)
          if l.lstrip().startswith(COMMENT_MARKS)]


def selftest() -> int:
  """THE HARNESS COMES FIRST.  Four plants, and each one is written so it can FAIL:
  a plant that cannot fail is a plant that reports success while measuring nothing.

  P1 FORWARD  a file whose extension the population CANNOT NAME is invisible.
  P2 REVERSE  a SCRATCH copy is counted exactly like the live gate it copies.
  P3 THE REPAIR a NUL is REFUSED rather than swallowed, the refusal is NAMED and stops ON
              the NUL, and a copy of the census with the `SystemError` arm deleted makes the
              SAME assertion go red.  This plant used to assert the opposite -- that the real
              file ESCAPES `prose()` -- and the fix that made that false is what it now
              asserts.  Inverting a plant is not deleting one; the falsification arm is why.
  P4 THE ROOT  a citation into `references/` resolves on DISK even though the tree is
              gitignored and the file is in no commit -- the brief's reading (D) is a
              checkout property, not a citation defect."""
  cites = load_census()
  ex = tuple(cites.EXTS)
  cases = []
  with tempfile.TemporaryDirectory(prefix="citespop-plant-") as tmp:
    d = Path(tmp)
    live = d / "live.py"
    live.write_text("# the rule lives at checks/cites-census.py:214\n")
    fresh = d / "fresh.bend"
    fresh.write_text("# the rule lives at checks/cites-census.py:214\n")
    scratch = d / "scratch.md"
    scratch.write_text("# a scratch COPY of live.py, citing checks/cites-census.py:214\n")

    # P1 -- forward.  The population is `endswith(EXTS)`, so an extension the census does
    # not name is not a smaller contribution; it is NO contribution.
    pop = lambda p: p.endswith(ex)                                    # noqa: E731
    cases.append(("P1 FORWARD : a `.bend` file the declared suffix set cannot name",
                  (pop("fresh.bend"), cites.lane_bcd("fresh.bend",
                                                     cites.prose("fresh.bend",
                                                                 fresh.read_text()))[0] != []),
                  (False, True)))
    # THE CONTROL ASSERTS A PROPERTY, NOT A COUNT.  An earlier revision wrote `2` here --
    # a number copied from the shape of the fixture rather than read off it -- and it
    # FAILED, because a one-line fixture makes one claim.  A transcribed expected value is
    # the defect this tree keeps re-finding; the property "the file's own extractor sees
    # what the population refuses to read" survives the fixture changing.
    seen = cites.lane_bcd("fresh.bend", comments_of(fresh.read_text()))[0]
    cases.append(("P1 CONTROL : the population EXCLUDES it, its extractor still SEES it",
                  (pop("fresh.bend"), len(seen) > 0), (False, True)))

    # P2 -- reverse.  A scratch copy is admitted on the SAME rule as the live gate, so the
    # same citation is counted twice and the denominator is inflated.
    got = cites.lane_bcd("scratch.md", cites.prose("scratch.md", scratch.read_text()))[0]
    cases.append(("P2 REVERSE : a scratch `.md` copy is counted like the live gate",
                  (pop("scratch.md"), pop("live.py"), len(got) > 0), (True, True, True)))
    cases.append(("P2 CONTROL : the copy and the original yield the SAME claim count",
                  len(cites.lane_bcd("live.py", cites.prose("live.py",
                                                            live.read_text()))[0]), len(got)))

    # ---- P3 -- THE REPAIR, ASSERTED.  NOT DELETED. ------------------------------------
    # THIS PLANT USED TO ASSERT THE DEFECT.  It wanted the real file to ESCAPE `prose()` as
    # a raw `SystemError` while a synthetic NUL passed in silence, and it went red when
    # `9b1f5ac00` landed: `tokenizer_fault` gained the `SystemError` arm that reads
    # `e.__cause__.lineno`, and `prose()` now raises `Unproseable` instead of passing.  Both
    # halves of that expectation are false, so THE PLANT WAS THE STALE THING.
    #
    # A PLANT IS A CLAIM THAT A DEFECT IS GUARDED, AND IT IS PROVED BY GOING RED WHEN THE
    # GUARD IS REMOVED -- never by naming the defect's symptom.  So the expectation is
    # inverted, not the expectation's job: what is asserted now is the REPAIR, and the arm
    # below proves it is load-bearing by deleting the arm FROM A COPY and showing red.
    def refusal(mod, rel, body):
      """(name, inside the family every live caller catches, line it stopped at, kind) for
      a caller that passes NO `fault` list -- the caller that has nowhere to record one.
      SILENCE RETURNS `("no-exception", ...)`, which is the value no refusal may carry, so a
      `prose()` that swallowed the NUL again cannot be mistaken for one that named it."""
      try:
        mod.prose(rel, body)
        return ("no-exception", False, None, None)
      except BaseException as e:  # noqa: BLE001 -- the point is WHAT escapes, not that one does
        return (type(e).__name__, isinstance(e, tokenize.TokenError),
                getattr(e, "lineno", None), getattr(e, "kind", None))

    def guarded(mod, rel, body):
      """Is the refusal (a) NAMED, (b) a `tokenize.TokenError` -- so `checks/cites-census.py`'s
      own reason for the base class holds and every existing handler still covers it -- and
      (c) stopped ON the NUL rather than at a fiction?  The expected line is READ OFF THE
      FIXTURE'S OWN BYTES, never transcribed, so the plant follows the file if it moves and
      a hand-copied 5401 would have quietly become a change-detector."""
      name, in_family, at, kind = refusal(mod, rel, body)
      nuls = [i for i, l in enumerate(body.splitlines(), 1) if "\x00" in l]
      return (name, in_family, at == (nuls[0] if len(nuls) == 1 else None), bool(kind))

    # THE ONE PREDICATE, NAMED.  It is evaluated on the census and on the reverted copy, so
    # "the plant goes red" is this exact expression returning False -- not a second, weaker
    # restatement of the same idea that would pass while the first one rotted.
    GUARDED = ("Unproseable", True, True, True)  # named, in-family, stopped ON the NUL, kinded

    nul = d / "tiny.bend"
    nul.write_bytes(b"# a citation\n\x00\n")
    tiny = nul.read_text(errors="replace")
    # AN UNBROKEN CONTROL.  Without it every refusal row above is also satisfied by a
    # `prose()` that refuses EVERYTHING, which is not a guard but a different crash.
    clean = d / "clean.bend"
    clean.write_bytes(b"# a citation\nx = 1\n")
    cases.append(("P3 CONTROL : a file that DOES tokenize refuses nothing",
                  refusal(cites, "clean.bend", clean.read_text())[0], "no-exception"))
    cases.append(("P3 THE REPAIR : a synthetic NUL is REFUSED, in-family, stopped ON it",
                  guarded(cites, "tiny.bend", tiny), GUARDED))
    # A MISSING WITNESS IS A FAILURE AND NOT A MATCHED PAIR OF SENTINELS.  The original
    # guarded this with `else ("no-exception", "no-exception")`, which PASSED when the
    # fixture was gone -- a plant that reports success having measured nothing.
    real = (ROOT / NUL_WITNESS).read_text(errors="replace") if (ROOT / NUL_WITNESS).is_file() else None
    cases.append((f"P3 THE REPAIR : the live {NUL_WITNESS} is REFUSED at its own NUL",
                  guarded(cites, NUL_WITNESS, real) if real is not None else ("WITNESS-GONE",),
                  GUARDED))

    # ---- P3 FALSIFICATION -- A PLANT THAT CANNOT GO RED IS NOT A PLANT -----------------
    # MEASURED 2026-10-20T00:20:06Z: deleting `SYSTEMERROR_ARM` from a copy and re-running
    # the SAME `guarded()` takes the live file from ('Unproseable', True, 5401,
    # 'SystemError<-SyntaxError') to ('SystemError', False, None, None) -- red on the name,
    # on the family, AND on the position -- while leaving the synthetic fixture at
    # ('Unproseable', True, 2, 'TokenError'), UNCHANGED.
    #
    # THAT LAST FACT IS THE HARMONISATION OF THE TWO THINGS THAT LOOKED LIKE A CONFLICT.
    # The old clause IV said "a synthetic minimal NUL plant scores TokenError (CAUGHT) -- so
    # the plant must be the REAL FILE".  Its REASON died with the crash: both fixtures now
    # score TokenError (CAUGHT).  Its CONCLUSION did not, and the reason it survives is
    # sharper: the synthetic fixture never REACHES the `SystemError` arm at all, so it is
    # IMMUNE to the revert and could never have detected it.  So the sentence is not deleted
    # and the real file is not dropped -- both would trade a true conclusion for a false one.
    census_src = DECLARED_SOURCE.read_text()
    mutated_src = census_src.replace(SYSTEMERROR_ARM, "")
    cases.append(("P3 MUTANT APPLIES : the reverted copy is NOT byte-identical to the census",
                  mutated_src != census_src, True))
    with tempfile.TemporaryDirectory(prefix="citespop-arm-reverted-") as mt:
      reverted_path = Path(mt) / "cites-census-arm-reverted.py"
      reverted_path.write_text(mutated_src)
      reverted = load_census(reverted_path)
      cases.append(("P3 FALSIFIED : with the SystemError arm gone the live file leaves "
                    "`prose()` raw and UNPOSITIONED, so the repair is load-bearing",
                    guarded(reverted, NUL_WITNESS, real) == GUARDED
                    if real is not None else True, False))
      cases.append(("P3 ARM, NOT ESCAPE : the synthetic fixture is UNREACHABLE for that arm, "
                    "which is why the REAL FILE stays in the harness",
                    guarded(reverted, "tiny.bend", tiny), guarded(cites, "tiny.bend", tiny)))

    # P4 -- the root.  A citation into a gitignored, untracked reference tree RESOLVES on
    # disk.  If the checkout ever loses `references/`, this plant flips, and the flip is
    # information about the CHECKOUT rather than about the citation.
    ref = ROOT / "references" / "bend" / "bend2" / "main.ts"
    cases.append(("P4 THE ROOT : a `references/` citation resolves ON DISK, in no commit",
                  cites.read("references/bend/bend2/main.ts") is not None, ref.is_file()))

  fails = 0
  for why, got, want in cases:
    ok = got == want
    fails += not ok
    print(f"[{'   PASS' if ok else '   FAIL'}] {why}\n          got {got}, want {want}")
  print(f"\n=== selftest {'PASS' if not fails else 'FAIL'}: {len(cases)} case(s) run, "
        f"{fails} failed ===")
  return EXITS[PASS if not fails else FAIL]


def main() -> int:  # noqa: C901 -- six clauses, one pass each
  print(__doc__.split("\n")[1])
  if "--selftest" in sys.argv:
    return selftest()
  try:
    cites = load_census()
  except FileNotFoundError:
    print(f"{REFUSED}: {DECLARED_SOURCE.relative_to(ROOT)} is gone -- it IS the citation "
          "population, and a gate cannot measure a population it cannot load")
    return EXITS[REFUSED]
  declared = tuple(cites.EXTS)
  paths = committed()
  text = [p for p in paths if not p.endswith(ARTEFACTS)]
  base = [p for p in paths if p.endswith(declared)]
  hidden = [p for p in text if not p.endswith(declared)]
  head = subprocess.run(["git", "rev-parse", "--short=12", "HEAD"], cwd=ROOT,
                        capture_output=True, text=True).stdout.strip()
  exts = set(e for e in (extname(p) for p in text) if e)

  print(f"HEAD               : {head}")
  print(f"DECLARED BY census : EXTS = {declared!r}  -- {len(declared)} of {len(exts)} "
        f"committed text extensions")
  print(f"COMMITTED PATHS    : {len(paths)}")
  print(f"  text, no artefact: {len(text)}   ({len(paths) - len(text)} captured artefacts excluded)")
  print(f"CENSUS POPULATION  : {len(base)}")
  print(f"HIDDEN FROM IT     : {len(hidden)}")

  # ---- I. COVERAGE ------------------------------------------------------------
  print("\n--- I. COVERAGE: the census reads none of these ---")
  ext = Counter(e for e in (extname(p) for p in hidden) if e)
  nonext = [p for p in hidden if not extname(p)]
  live = [p for p in hidden if not p.startswith(".agents/")]
  print("  by extension : " + ", ".join(f"{k}={v}" for k, v in ext.most_common(10)))
  print(f"  EXTENSIONLESS: {len(nonext)} committed files with no extension at all "
        f"(e.g. {nonext[0].rsplit('/', 1)[-1] if nonext else 'n/a'})")
  print(f"  LIVE (outside .agents/) : {len(live)}")

  # ---- II. YIELD --------------------------------------------------------------
  claims, unc = [], Counter()
  lanes = Counter()
  with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    for rel in hidden:
      try:
        raw = (ROOT / rel).read_bytes()
      except OSError:
        continue
      if b"\x00" in raw:                 # clause IV -- skipped here, judged there
        continue
      body = raw.decode(errors="replace")
      got, u = cites.lane_bcd(rel, comments_of(body))
      claims += got
      unc += u
      lanes[extname(rel) or "(none)"] += len(got)
  sub = [c for c in claims if c["lane"] != "E"]
  print("\n--- II. YIELD: claims inside that hidden text ---")
  print(f"  all lanes    : {len(claims)}  by lane {dict(Counter(c['lane'] for c in claims))}")
  print(f"  SUBSTANTIVE  : {len(sub)}  by lane {dict(Counter(c['lane'] for c in sub))}")
  print(f"  UNCLASSIFIED : {sum(unc.values())}")
  if sub:
    print(f"  verdicts     : {dict(Counter(cites.judge(c).get('verdict') for c in sub))}")
  print(f"  YIELD        : {len(sub)} claims against its own {len(base)}-file population")

  # ---- III. ACCIDENT ----------------------------------------------------------
  print("\n--- III. ACCIDENT: `#` languages are alive FOR THE WRONG REASON ---")
  alive = sorted(((n, e) for e, n in lanes.items()), reverse=True)[:6]
  dead = sorted(e for e, n in lanes.items() if n == 0)
  print("  alive by the census's own extractor: " +
        ", ".join(f"{e}={n}" for n, e in alive))
  print(f"  DEAD (file read, ZERO claims emitted): {len(dead)} extensions "
        f"e.g. {', '.join(dead[:5])}")
  print("  `prose()` has TWO branches: `.md` in full, and EVERYTHING ELSE through")
  print("  `tokenize`+`ast`. `tokenize` is a PYTHON lexer, and it too calls `#` a")
  print("  comment -- so `.bend`/`.sh`/`.cuh` WOULD be read, by coincidence. `//` and")
  print("  data languages have no such accident, and stay invisible. Adding the suffixes")
  print("  is therefore NOT the fix, and the coincidence is unverified by the census.")

  # ---- IV. THE REPAIR ----------------------------------------------------------
  print("\n--- IV. THE REPAIR: widening EXTS no longer kills the census ---")
  wit = ROOT / NUL_WITNESS
  if not wit.is_file():
    print(f"  {REFUSED}: {NUL_WITNESS} is gone -- this clause cannot be measured")
  else:
    body = wit.read_text(errors="replace")
    try:
      cites.prose(NUL_WITNESS, body)
      print("  prose() returned -- REPORTED AS A FACT, not as a pass")
    except (tokenize.TokenError, IndentationError) as e:
      # `9b1f5ac00` MOVED THIS RUN OUT OF `except BaseException`.  `Unproseable` is a
      # `tokenize.TokenError`, so it is caught HERE, which means the branch below is now
      # UNREACHABLE for this file -- its prose was DEAD text describing a crash that no
      # longer happens, and dead text is the verdict nobody writes down.
      nuls = [i for i, l in enumerate(body.splitlines(), 1) if "\x00" in l]
      print(f"  prose() REFUSED, and the refusal is CAUGHT here: {type(e).__name__} "
            f"stopped at line {getattr(e, 'lineno', None)!r} "
            f"(kind {getattr(e, 'kind', None)!r}); the file's NUL reads "
            f"line {nuls[0] if len(nuls) == 1 else nuls}")
      print("  So the widening does not DIE, and the reason this clause used to give has")
      print("  expired: it is no longer pinned by an ACCIDENT of the exception, it is")
      print("  pinned by ZERO YIELD -- the file is read and contributes 0 claims, which is")
      print("  not agreement. Adding `.bend` still is NOT the fix, for a different reason,")
      print("  and `gates/nul-refusal-gate.py` owns what the census EMITS for it (clause I).")
      print("  THE PLANT MUST STILL BE THE REAL FILE: the synthetic NUL never REACHES the")
      print("  `SystemError` arm, so it cannot detect that arm going away. See the PLANT")
      print("  section's falsification arm, which deletes the arm FROM A COPY and measures it.")
    except BaseException as e:  # noqa: BLE001 -- prose() did NOT catch this, and that is news
      print(f"  prose() on a LIVE {NUL_WITNESS} raised {type(e).__name__}, and prose()")
      print("  catches only (tokenize.TokenError, IndentationError), so it PROPAGATES")
      print("  out of census() and out of main(): the run DIES. A SystemError from")
      print("  anywhere OTHER than the tokenizer has no `__cause__` and is re-raised as")
      print("  ITSELF, which is what the arm below is for.")

  # ---- V. B vs C --------------------------------------------------------------
  print("\n--- V. RENAMED (B) vs NEVER-EXISTED (C) ---")
  subjects = set()
  for c in sub:
    j = cites.judge(c)
    if j.get("verdict") == REFUSED and str(j.get("evidence", "")).startswith("unreadable or absent"):
      subjects.add(c["subject"])
  if not subjects:
    print(f"  0 unresolvable subjects among {len(sub)} new claims")
  else:
    known = ever_committed(subjects)
    renamed = sorted(s for s in subjects if s in known)
    never = sorted(s for s in subjects if s not in known)
    print(f"  unresolvable subjects among the NEW claims : {len(subjects)} distinct")
    print(f"  B RENAMED       (in some commit of this repo): {len(renamed)}")
    print(f"  C NEVER-EXISTED (in no commit at all)       : {len(never)}")
    for s in renamed[:4]:
      print(f"    B {s}")
    for s in never[:4]:
      print(f"    C {s}")

  # ---- VI. OVERCOUNT ---------------------------------------------------------
  print("\n--- VI. THE OTHER DIRECTION: matches the suffix, should not be counted ---")
  slop = [p for p in base if p.startswith(".agents/slop/")]
  livebase = [p for p in base if not p.startswith(".agents/")]
  names = {p.rsplit("/", 1)[-1] for p in livebase}
  collide = sorted({p.rsplit("/", 1)[-1] for p in slop if p.rsplit("/", 1)[-1] in names})
  print(f"  census population        : {len(base)}")
  print(f"    .agents/slop/ (SCRATCH): {len(slop)}  ({len(slop) / max(1, len(base)) * 100:.1f}%)")
  print(f"    outside .agents/       : {len(livebase)}  ({len(livebase) / max(1, len(base)) * 100:.1f}%)")
  print(f"    slop basenames that also name a LIVE file: {len(collide)}"
        + (f"  e.g. {', '.join(collide[:4])}" if collide else ""))
  print("  -> a scratch copy is counted as if it were the gate, so one citation is")
  print("     counted once per copy and the denominator is MAJORITY SCRATCH.")

  # ---- VII. references/ ------------------------------------------------------
  print("\n--- VII. references/ IS ON DISK; ITS CITATIONS RESOLVE ---")
  ref = ROOT / "references"
  dangling = [p.name for p in ref.iterdir() if p.is_symlink() and not p.exists()] if ref.is_dir() else []
  print(f"  present : {ref.is_dir()}   tracked at HEAD : "
        f"{len([p for p in paths if p.startswith('references/')])} (gitignored)")
  if ref.is_dir():
    print(f"  entries : {sorted(p.name for p in ref.iterdir())}")
    print(f"  DANGLING SYMLINKS : {len(dangling)}" + (f"  e.g. {dangling[0]}" if dangling else ""))
  print("  -> reading (D) of the brief -- 'the target is a reference tree that is not")
  print("     present' -- IS FALSIFIED HERE: references/bend and references/tinyquery")
  print("     are real directories. Its citations PASS because read() tries ROOT first.")

  print(f"\nVERDICT: {FAIL} -- the declared population is a {len(declared)}-element suffix "
        f"set over a tree carrying {len(exts)} text extensions")
  return EXITS[FAIL]


if __name__ == "__main__":
  sys.exit(main())