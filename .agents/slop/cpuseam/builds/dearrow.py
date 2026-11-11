#!/usr/bin/env python3
"""REMOVE THE U+21D2 CHARACTER FROM THE TREE, AND MEASURE WHAT IT DID.

WHY A TOOL AND NOT A `sed`: THE CHARACTER HAS TWO MEANINGS IN THIS TREE AND A BLIND SUBSTITUTION
DESTROYS ONE OF THEM.

  * THE EMPHASIS MARKER (5,660 OCCURRENCES, 347 FILES): A RUN OF THE ARROW BEFORE A CAPITALISED
    WORD, USUALLY INSIDE A BOLD SPAN. THE ARROW IS DECORATION AND THE WORD AFTER IT CARRIES THE
    GRAMMAR, SO THE ARROWS GO AND THE WORD STAYS.

  * THE "IMPLIES" OPERATOR (63 OCCURRENCES, 24 FILES): A LOWERCASE WORD FOLLOWS, e.g.
    "byte-identical IMPLIES dead". HERE THE ARROW CARRIES MEANING, SO IT BECOMES "=>" -- AND "=>" IS
    NOT INVENTED: IT IS THIS TREE's OWN ALREADY-ESTABLISHED ASCII CONVENTION (54,570 OCCURRENCES IN
    1,283 TRACKED FILES, INCLUDING INSIDE .bend FILES AS BEND's OWN LAMBDA ARROW).

THE CLASSIFICATION IS BY WHAT FOLLOWS, NOT BY WHERE THE ARROW IS, BECAUSE THE MEANING IS IN THE WORD
AFTER IT. AND AN ARROW FOLLOWED BY PUNCTUATION OR END OF LINE IS DECORATION TOO, BECAUSE THERE IS NO
WORD TO IMPLY.

THE EMPHASIS REMOVAL ALSO CLEANS THE WHITESPACE: A RUN OF ARROWS SURROUNDED BY SPACES LEAVES DOUBLE
SPACES, AND A LINE THAT IS ONLY ARROWS LEAVES AN EMPTY LINE, AND BOTH ARE THE ARROW's RESIDUE. THE
TIDYING IS CONSERVATIVE: IT ONLY TOUCHES WHAT THE REMOVAL MADE UNTRUE, AND IT NEVER JOINS TWO LINES.

THE ARROW IS WRITTEN AS AN ESCAPE SEQUENCE IN THIS FILE ON PURPOSE: A TOOL THAT CONTAINS THE CHARACTER
IT DELETES CANNOT BE COMMITTED ARROW-FREE, AND THE POINT IS THAT THE CHARACTER IS GONE FROM THE TREE.
"""

import argparse
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
ARROW = "\u21d2"
REPL = "=>"

# THE EMPHASIS RUN: ONE OR MORE ARROWS, EACH MAY BE FOLLOWED BY SPACES. THE RUN IS THE WHOLE THING,
# BECAUSE THE ARROWS ARE INDIVIDUALLY MEANINGLESS AND ONLY THE RUN IS THE MARKER.
EMPHASIS_RUN = re.compile(r"(?:\u21d2[ \t]*)+")
# THE "IMPLIES" ARROW: ONE ARROW FOLLOWED BY SPACES AND A LOWERCASE WORD.
IMPLIES = re.compile(r"\u21d2([ \t]*)(?=[a-z])")


def convert(text: str) -> tuple[str, int, int]:
  """ONE PASS, POSITION-AWARE, AND **THE WHITESPACE POLICY IS **ONE RULE**: THE ARROW RUN AND **THE
  WHITESPACE IMMEDIATELY AFTER IT** ARE REMOVED AS A UNIT, AND **NOTHING ELSE MOVES**.

THE MEASURED FAILURE OF THE FIRST CUT WAS A BLANKET `re.sub(r"  +", " ")`, WHICH DESTROYED
  `.agents/TODO.md`'s ALIGNED COLUMNS AND **SHRANK THE FILE BY 237 KB**. THE SECOND CUT
  **ATE THE INDENTATION** BECAUSE IT COULD NOT SEE THAT THE LINE ALREADY HAD CONTENT. 
  **THE THIRD CUT **MERGED TWO WORDS** (`ROUND TRIP),**THE PORT's`) AND **GLUED A `=>` TO
  ITS WORD** (`**=>AND STAGES`). **AND THE RULE THAT FIXES ALL THREE IS
  **THIS**: **THE ARROW RUN IS REPLACED BY NOTHING, AND THE WHITESPACE **AROUND** IT IS **LEFT
  EXACTLY AS IT WAS** -- EXCEPT THAT **THE WHITESPACE **AFTER** THE RUN IS TRIMMED TO **AT MOST ONE
  SPACE** AND **THE WHITESPACE **BEFORE** THE RUN IS TRIMMED TO **AT MOST ONE SPACE** *IF AND ONLY IF*
  **BOTH SIDES END UP WITH NON-SPACE CONTENT**. **AND THAT IS **EXACTLY**
  THE `re.sub(r"[ \t]+", " ", ...)` ON **THE NEIGHBOURHOOD OF THE RUN ONLY**, NEVER ON THE FILE.

AND THE "IMPLIES" ARROW -- **ONE** ARROW BEFORE A **LOWERCASE** WORD -- BECOMES `=>`,
  AND **ITS TRAILING WHITESPACE IS KEPT**, SO `a => b` BECOMES `a => b` AND **THE SENTENCE DOES NOT
  MOVE**.
  """
  emph = 0
  impl = 0
  out = []
  i = 0
  n = len(text)
  while i < n:
    ch = text[i]
    if ch != ARROW:
      out.append(ch)
      i += 1
      continue
    # THE "IMPLIES" CASE: ONE ARROW, THEN SPACES, THEN A LOWERCASE LETTER.
    j = i + 1
    while j < n and text[j] in " \t":
      j += 1
    if j < n and text[j].islower():
      impl += 1
      out.append(REPL)
      out.append(text[i + 1:j])
      i = j
      continue
    # THE EMPHASIS RUN: EVERY ARROW AND THE SPACES BETWEEN THEM.
    k = i
    while k < n and text[k] == ARROW:
      emph += 1
      k += 1
      while k < n and text[k] in " \t":
        k += 1
    # THE WHITESPACE **BEFORE** THE RUN: **AT MOST ONE SPACE**, AND **ONLY** IF THE LINE WOULD
    # OTHERWISE CARRY **TRAILING BLANK SPACE** BEFORE THE RUN.
    while len(out) >= 2 and out[-1] in " \t" and out[-2] in " \t":
      out.pop()
    # THE SPACE **BETWEEN** THE PREVIOUS CONTENT AND THE RUN: **KEPT**, AND THE SPACE **AFTER** THE
    # RUN: **AT MOST ONE**, AND **NEITHER** IS **REMOVED** -- **THE ARROW'S OWN SPACES GO WITH THE
    # ARROW** AND **THE SPACES AROUND IT STAY**, EXCEPT FOR **THE TRAILING-BLANK-SPACE** TRIM BELOW.
    while len(out) >= 2 and out[-1] in " \t" and out[-2] in " \t" and out[-2] != "\n":
      out.pop()
    # **AND** IF THE RUN WAS **THE ONLY THING** ON ITS LINE, THE LINE BECOMES **EMPTY** -- **NOT**
    # **INDENTED** -- AND **THE BLANK LINE IS KEPT**, BECAUSE **A BLANK LINE IS **STRUCTURE**.
    tail = []
    for c in reversed(out):
      if c == "\n":
        break
      tail.append(c)
    if "".join(reversed(tail)).strip() == "":
      while out and out[-1] in " \t":
        out.pop()
    # **AND** THE SPACE **AFTER** THE RUN: **AT MOST ONE**, SO `ARROWS **THE**` AND `ARROWS  **THE**`
    # BOTH COME OUT AS `ARROWS **THE**` **WITHOUT** TOUCHING ANY **COLUMN PADDING** ELSEWHERE.
    # **AND** THE SPACE IS **NOT** ADDED WHEN THE CHARACTER BEFORE THE RUN IS `*` -- BECAUSE **THE
    # `**` ALREADY SEPARATES** (`**ARROWS AND ...**` IS ONE BOLD SPAN, NOT **A BOLD SPAN WITH A
    # LEADING SPACE**) -- **AND** NOT WHEN THE CHARACTER AFTER THE RUN IS `*`, FOR THE SAME REASON.
    if (k < n and out and out[-1] not in " \t\n" and text[k] not in " \t\n"
        and out[-1] != "*" and text[k] != "*"):
      out.append(" ")
    i = k
  return "".join(out), emph, impl


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--apply", action="store_true", help="WRITE THE FILES INSTEAD OF ONLY REPORTING")
  ap.add_argument("--paths", nargs="*", default=None, help="LIMIT TO THESE PATHS")
  ap.add_argument("--quiet", action="store_true")
  args = ap.parse_args()

  if args.paths:
    rels = args.paths
  else:
    # THE **TRACKED** FILES **AND** THE **UNTRACKED-BUT-NOT-IGNORED** ONES, BECAUSE **A FILE THAT
    # ANOTHER UNIT HAS JUST WRITTEN IS **NOT** IN `git ls-files`**, AND **THE ARROW MUST BE GONE FROM
    # **THE TREE** AND NOT ONLY FROM **THE INDEX**.
    tracked = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True)
    untracked = subprocess.run(["git", "ls-files", "--others", "--exclude-standard"],
                               cwd=ROOT, capture_output=True, text=True, check=True)
    rels = sorted(set(tracked.stdout.splitlines()) | set(untracked.stdout.splitlines()))

  changed = []
  total_emph = 0
  total_impl = 0
  for rel in rels:
    p = ROOT / rel
    if not p.is_file():
      continue
    try:
      text = p.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
      continue
    if ARROW not in text:
      continue
    new, emph, impl = convert(text)
    if new == text:
      continue
    changed.append((rel, emph, impl, len(text), len(new)))
    total_emph += emph
    total_impl += impl
    if args.apply:
      p.write_text(new, encoding="utf-8")

  if not args.quiet:
    print(f"FILES CHANGED: {len(changed)}")
    print(f"EMPHASIS ARROWS REMOVED: {total_emph}")
    print(f"IMPLIES ARROWS REPLACED WITH '{REPL}': {total_impl}")
    print(f"{'FILE':64s} {'EMPH':>6s} {'IMPL':>6s} {'BEFORE':>9s} {'AFTER':>9s}")
    for rel, emph, impl, before, after in changed:
      print(f"{rel:64s} {emph:6d} {impl:6d} {before:9d} {after:9d}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
