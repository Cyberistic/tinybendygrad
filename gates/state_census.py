# state_census.py -- THE SHARED CENSUS MACHINERY for the three gates that census the
# layers nothing had gated: `nn/onnx`, `nn/state` and `mixin/rand`.
#
#   .venv/bin/python gates/state_census-gate.py     # the first consumer
#   .venv/bin/python gates/onnx_census-gate.py      # imports this
#   .venv/bin/python gates/rand_census-gate.py      # imports this
#
# WHY IT IS HERE AND NOT IN `gatekit.py`, WHICH IS WHERE IT BELONGS. The three gates share
# three pieces -- the ROW POPULATION census, the CLASS census and the population PLANT -- and
# duplicating eighty lines three times is the copy-paste `AGENTS.md` forbids. The unit that
# owns `gates/gatekit.py` was out of scope, so the machinery lands in the FIRST of the three
# gates' files and the other two import it. THE NAME IS A WART AND IT IS NAMED RATHER THAN
# HIDDEN: this module has nothing to do with `nn/state`, and a reader who greps for
# "state" and finds a dtype census will be misled. THE FOLLOW-UP IS ONE MOVE -- these four
# functions into `gatekit.py` next to `Gate`, with the three gates importing them from there
# -- and until then the wart is the smaller cost. It is here rather than in
# `.agents/slop/` because `.agents/slop/` is being pruned and `mixin/rand`'s CPython lane
# living there is ALREADY GONE (`gates/rand_census-gate.py`'s docstring).
#
# WHAT IS IN HERE, AND WHY IT IS ONE IMPLEMENTATION RATHER THAN THREE.
#
#   declared_rows(driver, port, DECL, PORT_DECL) -- a GENERATOR'S OWN DECLARATION, loaded by
#     path. `AGENTS.md`'s rule 1 lists three admissible populations and this is (a): the rows
#     a driver declares are the rows it emits, and a census that cannot compare the two is a
#     census that found 4 of 10 and printed 4.
#   verdict_population / why_refused -- FIVE refusals, each its OWN reason, order-fixed. A
#     handler that refuses everything for whichever check it runs first is not a refusal, it
#     is a coincidence with the order of the checks; `checks/sweep.py`'s LIVE_UNITS lesson.
#   class_census -- the per-class counts AND, for each class, the claim it CANNOT make. A
#     census that reports counts without reporting the blindness is reporting the easy half.
#   plant -- seven synthetic populations, no `bend`, no CPython, and NO dependency on a live
#     lane: the first draft of this plant read the real lane and therefore reported three
#     spurious failures on a DEAD run, which is a plant that is a function of the thing it
#     is testing.
import re

KEY = re.compile(r"^([^=]+)=")
BOOLS = ("True", "False")

# THE CLASSES, AND WHAT EACH ONE CANNOT DISTINGUISH. A class is a SHAPE of row value, and the
# blindness is a property of the shape, so this table is the answer to "what does this gate
# not see" for as long as the lane holds rows of these shapes. `CANNOT` is printed verbatim on
# every run, green or red.
CANNOT = {
  "C-BOOL": "port-agrees-with-CPython from both-agree-with-a-wrong-transcription: the "
            "expected value is a literal in EACH lane, so a shared literal is invisible",
  "C-VALUE": "nothing structural -- it prints the subject, so a wrong answer is visible",
  "C-CTRL": "anything about its SUBJECT; its only claim is that the lane is deterministic",
  "C-CONST": "that its group RAN correctly: the value is a literal on both sides, so it says "
             "the group was entered and nothing about what it produced",
  "C-EMPTY": "a wrong empty answer from a row that was never emitted -- a transcript renders "
             "both as `row=`",
  "C-NEG": "that the POSITIVE arm is right; a negative fixture only says the absent case is "
           "absent",
  "C-SPACE": "that a value containing a SPACE survived: the key is split at the first `=` and "
             "the value is taken whole, but a reader counting fields will not",
}
CLASSES = ("C-BOOL", "C-VALUE", "C-CTRL", "C-CONST", "C-EMPTY", "C-NEG")


def lanes(text):
  """A lane's rows as `(key, value)` pairs, blanks dropped."""
  return [(m.group(1), l.split("=", 1)[1])
          for l in text.splitlines() if l.strip() for m in [KEY.match(l)] if m]


def declared_rows(driver_path, port_path, decl_re, port_decl_res):
  """The row names the GENERATORS declare, from the two files that generate them.

  `driver_path` is the `.bend` driver and `port_path` the port file whose own `t_*`/`onx_*`
  helpers print some of the rows. Loading BOTH rather than one is the point: a row the driver
  dropped is still declared by the port, and so arrives as an emitted-but-undeclared row
  rather than as a silently missing comparison.

  `port_decl_res` is a LIST of patterns because a port file declares rows in more than one
  SHAPE -- `onx_row("name", ...)` in `nn/onnx.bend` and `IO.print(String.concat(["name=",
  ...]))` in the five group helpers beside it -- and the first version of `onnx_census-gate`
  passed ONE pattern for both. The consequence was measured, not theorised: the census
  reported `emitted=167 declared=49` and FAILED, and the 118 unaccounted rows were exactly
  the group rows. A population census that cannot see a second declaration SHAPE cannot be
  wrong about the rows it is missing.
  """
  res = [port_decl_res] if hasattr(port_decl_res, "finditer") else list(port_decl_res)
  names = set(decl_re.findall(driver_path.read_text()))
  names |= {m.group(1) for r in res for m in r.finditer(port_path.read_text())}
  return names


def why_refused(declared, emitted):
  """WHY this population is refused, in a FIXED order -- so a caller can ask WHICH.

  ORDER IS THE CLAIM: `["a","a"]` against `{a,b}` is a DUPLICATE and not a missing `b`, and
  `[]` against a non-empty declaration is `missing`, which is the honest reading of a lane
  that printed nothing at all.
  """
  e, d = list(emitted), set(declared)
  if len(set(e)) != len(e):
    return "duplicate"
  if any(" " in k for k in e):
    return "space"
  if any(k not in d for k in e):
    return "undeclared"
  if sorted(d - set(e)):
    return "missing"
  return "accepted"


def verdict_population(declared, emitted):
  """`emitted == declared`, BOTH WAYS. The whole census in one Bool."""
  e, d = list(emitted), set(declared)
  return (len(set(e)) == len(e)
          and all(" " not in k for k in e)
          and all(k in d for k in e)
          and sorted(d - set(e)) == [])


def row_population(declared, emitted, label=""):
  """Print every number, then answer. A count nothing reads is how six truncations happened."""
  why = why_refused(declared, emitted)
  print(f"-- POPULATION {label}  emitted={len(emitted)}  declared={len(declared)}  "
        f"verdict={why.upper()}")
  if why != "accepted":
    print(f"-- POPULATION FAIL{label}: {why} -- see the five refusals in state_census.py")
    return False
  return True


def classify(rows, neg=(), const=()):
  """The rows by class. `neg`/`const` name the rows that are negative fixtures and rows whose
  value is a LITERAL on both lanes -- neither is decidable from the value alone, which is why
  they are parameters and not a rule."""
  neg, const = set(neg), set(const)
  return {
    "C-BOOL": [k for k, v in rows if v in BOOLS],
    "C-VALUE": [k for k, v in rows if v not in BOOLS],
    "C-CTRL": [k for k, _ in rows if k.startswith("ctrl_")],
    "C-CONST": [k for k, _ in rows if k in const],
    "C-EMPTY": [k for k, v in rows if v == ""],
    "C-NEG": [k for k, _ in rows if k in neg],
  }


def class_census(rows, neg=(), const=(), floors=None):
  """THE CLASSES, COUNTED FROM THE LANE, and what each cannot distinguish.

  `floors` is a `{class: minimum}` map. A floor is a REFUSAL: this tree's recorded lesson
  (wgsl's `M8`, which moved 0 of 358 rows because the fix had made the branch unreached) is
  that a class with no row able to fail is a class with no gate in it, and `rand.bend`'s own
  M7 is the same shape -- a mutation on live code that moved NOTHING because both its
  fixtures were on the vacuous side of the branch. So a floor here is the population's
  statement that it is big enough to be falsifiable.
  """
  cls = classify(rows, neg, const)
  bad = []
  for name in CLASSES:
    print(f"-- CLASS {name:<8} n={len(cls[name]):<3} cannot-distinguish={CANNOT[name]}")
  # C-BOOL + C-VALUE IS A TRUE PARTITION and the rest are REFINEMENTS OF IT, not peers of it.
  # The first version added C-CONST into the sum as if it were a peer and the onnx lane
  # refused: 35 + 132 + 6 = 173 against a 167-row lane, because all six C-CONST rows are
  # `True` and were already counted as C-BOOL. The subset claims below are the stronger and
  # the CORRECT form of the same check -- a class that claims a refinement must PROVE it is
  # one. AND A REFINEMENT MAY NOT BE ASSUMED TO LIVE IN C-BOOL SPECIFICALLY: the rand lane's
  # three C-CONST rows are the ordinals `0`, `1` and `2`, which are C-VALUE, and a first draft
  # of the rule here asserted `C-CONST <= C-BOOL` and refused a correct lane for it.
  if len(cls["C-BOOL"]) + len(cls["C-VALUE"]) != len(rows):
    bad.append("C-BOOL + C-VALUE is not the row count, so the partition leaked")
  universe = set(cls["C-BOOL"]) | set(cls["C-VALUE"])
  for sub in ("C-CONST", "C-CTRL", "C-EMPTY", "C-NEG"):
    if not set(cls[sub]) <= universe:
      bad.append(f"{sub} names rows that are in no class at all")
  # **A DECLARED NEGATIVE FIXTURE WHOSE VALUE IS NOT `False` HAS STOPPED BEING NEGATIVE, AND
  # THE CENSUS WAS COUNTING IT AS IF IT STILL WERE.** `CANNOT["C-NEG"]` SAYS WHAT A NEGATIVE
  # FIXTURE CLAIMS: *"A NEGATIVE FIXTURE ONLY SAYS THE ABSENT CASE IS ABSENT"* -- SO ITS VALUE
  # **IS** THE CLAIM, AND A VALUE OF `True` SAYS THE ABSENT CASE IS **PRESENT**. THE CLASS WAS
  # POPULATED **BY NAME** (`[k for k, _ in rows if k in neg]`), SO A FIXTURE WHOSE CLAIM HAD
  # EXPIRED SAT IN THE CLASS, AND THE ONLY CLAIM THE CLASS MAKES IS ABOUT WHAT IT CANNOT
  # DISTINGUISH -- **SO THE EXPIRY WAS INVISIBLE AND THE CENSUS STAYED GREEN.**
  # MEASURED 2026-10-25: `gates/rand_census-gate.py`'s `fold_np` AND `fold5_np` ANSWERED `True`
  # AFTER THE `mixin/rand.bend` FIX MADE THE FOLD ANSWER THEM, WHILE BOTH WERE STILL DECLARED
  # NEGATIVE -- **AND THE GATE WAS GREEN.** TAKING THEM OUT OF `NEG` IS THE PROGRESS; **THIS IS
  # THE CHECK THAT MAKES THE NEXT ONE IMPOSSIBLE TO MISS.**
  # **=> AND THE CLASSIFICATION IS NOT AFFECTED: `classify`'s DOCSTRING SAYS THE CLASSES ARE NOT
  # *DECIDABLE FROM THE VALUE ALONE*, WHICH IS TRUE OF *WHICH* ROWS ARE NEGATIVE -- BUT A ROW
  # **ALREADY** DECLARED NEGATIVE IS CHECKED, NOT CLASSIFIED.**
  # **=> AND THE SPELLING THAT MATTERS IS `True` AND ONLY `True`, BECAUSE IT IS THE ONE THAT
  # SAYS *THE ABSENT CASE IS PRESENT*.** **THE OTHER SPELLINGS ARE PER-GATE AND THE GATES'
  # OWN DATA PROVED IT: `rand_census-gate.py`'s NEGATIVE FIXTURES PRINT `False`, WHILE
  # `state_census-gate.py`'s PRINT `-` AND `onnx_census-gate.py`'s PRINT `-` OR AN EMPTY
  # STRING. **⇒ A FIRST DRAFT OF THIS CHECK DEMANDED THE VALUE BE `False`, AND IT TURNED TWO
  # GATES RED ON FIXTURES THAT ARE PERFECTLY GOOD -- WHICH IS HOW A CORRECTION FOUNDS OUT
  # WHAT IT GOT WRONG.**
  emitted = dict(rows)
  for k in sorted(neg):
    v = emitted.get(k)
    if v == "True":
      bad.append(f"C-NEG names {k}, whose value is 'True', so the negative "
                 f"fixture's claim (the absent case is absent) HAS EXPIRED -- it is no longer a "
                 f"negative fixture and must leave the class")
  for name, want in (floors or {}).items():
    if len(cls[name]) < want:
      bad.append(f"{name} has {len(cls[name])} rows and needs {want}; a class with too few "
                 f"rows cannot be shown to do its only job")
  for b in bad:
    print(f"-- CLASS FAIL: {b}")
  return not bad


def plant(verdict=None, why=None, label="POPULATION"):
  """SEVEN synthetic populations, no `bend`, no CPython, no live lane.

  A census that can only be exercised by a green run cannot say what it does when a
  population is malformed. Each malformed shape must be refused FOR ITS OWN REASON, and the
  `wanted` column is the cross-check: a handler that refused everything for the first reason
  it happens to check would pass the "was it refused?" column and fail this one.
  """
  verdict = verdict or verdict_population
  why = why or why_refused
  D = {"a", "b", "c"}
  cases = [("the declared population", D, ["a", "b", "c"], "accepted"),
           ("a DUPLICATE key", D, ["a", "b", "c", "a"], "duplicate"),
           ("a key holding a space", D, ["a", "b", "c", "a b"], "space"),
           ("emitted but undeclared", D, ["a", "b", "c", "ghost"], "undeclared"),
           ("declared but not emitted", D, ["a", "b"], "missing"),
           ("an EMPTY lane", D, [], "missing"),
           ("an EMPTY declaration", set(), [], "accepted")]
  bad = []
  for nm, declared, e, want in cases:
    got, ok = why(declared, e), verdict(declared, e)
    print(f"  {nm:<27} declared={len(declared):<3} emitted={len(e):<3} "
          f"{'ACCEPTED' if ok else 'REFUSED':<8} refused-for={got:<11} wanted={want}")
    if got != want or ok != (want == "accepted"):
      bad.append(f"{nm}: refused-for={got}, wanted {want}")
  print(f"--plant: {'all seven states OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
  return 1 if bad else 0
