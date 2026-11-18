#!/usr/bin/env python3
"""**THE **APPLIER** -- **THE **TRIM **PLAN**'s **RULE**, **APPLIED **AT **SECTION
**GRANULARITY**, **WITHOUT **LEAVING **A **DANGLING **HEADER** OR **A **HALF **SENTENCE**.

**⇒⇒† AND **THE **TWO **DEFECTS **THE **FIRST **APPLIER **HIT**, **BOTH **MEASURED**:

1. **THE **BLOCK **WAS **TOO **COARSE**. **A **RUN **OF **`#` **LINES **IN **A **`.bend`
   **FILE **IS **ONE **BLOCK**, **⇒⇒† AND **A **FILE's **HEADER **IS **ONE **RUN **OF
   **170+ **LINES**, **⇒⇒† AND **THE **PLAN's **`keep_count` **ON **IT **KEPT **THE
   **FIRST **MARKER's **PARAGRAPH **AND **CUT **THE **OTHER **150 **LINES**, **⇒⇒† AND
   **THOSE **150 **LINES **WERE **A **LIST **OF **SEVEN **SEPARATE **DIFFERENCES**, **EACH
   **WITH **ITS **OWN **UPSTREAM **CITATION**. **⇒⇒† AND **THE **CURE**: **SPLIT **THE **RUN
   **AT **BLANK **`#` **LINES**, **⇒⇒† AND **JUDGE **EACH **SECTION **BY **ITSELF**.

2. **THE **MARKER **LINE **IS **OFTEN **THE **CITATION **ON **THE **SECOND **LINE **OF **A
   **SENTENCE**, **⇒⇒† AND **SO **CUTTING **AT **THE **MARKER **LINE **CUTS **MID-SENTENCE**
   ("`THE **COMPILE.** Upstream's `CPUProgram.__init__` step 1 (`ops_cpu.py:29-34`) is"
   **AND **NOTHING **ELSE**). **⇒⇒† AND **THE **CURE**: **KEEP **THE **WHOLE **PARAGRAPH**
   **THAT **CONTAINS **THE **MARKER**.

**⇒⇒† AND **THE **SAFETY **PROPERTY**: **A **KEPT **SECTION **IS **A **PREFIX **OF **THE
**ORIGINAL **RUN **OF **`#` **LINES**, **⇒⇒† AND **SO **A **KEPT **LINE **IS **NEVER
**REWRITTEN**, **⇒⇒† AND **ONLY **WHOLE **TRAILING **COMMENT **LINES **ARE **DELETED**.
"""

import importlib.util
import pathlib
import re
import sys

_here = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("trim_plan", _here / "trim-plan.py")
_plan = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_plan)
_cspec = importlib.util.spec_from_file_location("comment_census", _here / "comment-census.py")
_census = importlib.util.module_from_spec(_cspec)
_cspec.loader.exec_module(_census)
# **⇒⇒† AND **THE **CITATION** -- **⇒⇒† AND **THE **FIRST **APPLIER's **`CITE` **WAS
# **THE **PLAN's**, **⇒⇒† AND **IT **IS **`(?:tinygrad/)?[A-Za-z_][\w/]*\.py:\d+`**, **⇒⇒†
# **AND **IT **MISSED **`references/bend/bend2/effs/process_run.c:277`** **AND
# **`renderer/cstyle.bend:49-54`** -- **⇒⇒† AND **THE **RESULT **WAS **THAT **A **PARAGRAPH
# **THAT **NAMED **A **WALL **WAS **CUT**, **⇒⇒† AND **A **CITATION **IS **ANY **`path:NN`**.
CITE = re.compile(r"[A-Za-z_][\w/.-]*\.(?:py|bend|c|h|md|sh|mjs):\d+")

# **AND **THE **BARE **LINE **REFERENCE** -- **AND **`runtime/ops_metal.bend` **NAMES **ITS
# **UPSTREAM **LINES **AS **`:256`** **AND **`:136`**, **AND **THOSE **ARE **THE **UPSTREAM
# **CITATIONS**, **AND **AND **THE **FIRST **CITE **REGEX **DID **NOT **MATCH **THEM**, **AND
# **SO **THE **CUT **DROPPED **A **NUMBERED **LIST **OF **CITED **DIFFERENCES**.
CITE = re.compile(r"(?:[A-Za-z_][\w/.-]*\.(?:py|bend|c|h|md|sh|mjs):\d+)|(?<!\w):\d{2,}\b")

# **⇒⇒† AND **THE **MEASUREMENT's **KEYWORDS **ARE **LOWERCASE **IN **THE **SOURCE**, **⇒⇒†
# **AND **THE **PLAN's **`MEASURED` **WAS **CASE-SENSITIVE**, **⇒⇒† AND **SO **A **PARAGRAPH
# **THAT **SAID **"the base is `0`, and that is measured" **WAS **CUT**. **⇒⇒† AND **THE
# **CURE **IS **A **CASE-INSENSITIVE **MARKER**.
MEASURED = re.compile(r"\b(measured|observed|counted|verdict|ratio|the count)\b", re.IGNORECASE)
MEASURED = re.compile(
  MEASURED.pattern + r"|\d+(\.\d+)?\s+(cons|cells|calls|turns|rows|lines|percent|%)", re.IGNORECASE)
# **AND **A **NUMBERED **REPLY **OR **A **NAMED **TUPLE** -- **AND **`reply[8:16]` **IS
# **`(104, 0)`**, **AND **THAT **IS **A **MEASUREMENT**, **AND **AND **THE **MEASURED
# **REGEX **NEEDS **A **UNIT **WORD**, **AND **SO **IT **DID **NOT **MATCH**.
MEASURED = re.compile(
  MEASURED.pattern + r"|\(\s*\d+\s*,\s*\d+\s*\)|\b\d+\s*BYTES\b|\b\d+\s*OF \d+",
  re.IGNORECASE)

# **AND **THE **CENSUS's **OWN **WEIRD **MARKERS**, **AND **THE **CENSUS **ALREADY
# **CLASSIFIES **WEIRD **AS **A **KEEP **CLASS** ("**why **something **looks **wrong **but
# **is **not**"), **AND **SO **A **SECTION **CARRYING **ONE **IS **KEPT** -- **AND **WITHOUT
# **THIS **THE **APPLIER **CUT **THE **SUBSTRATE **NOTES**, **AND **THOSE **ARE **THE
# **SUBSTRATE **RULES **THE **FILE **IS **WRITTEN **AGAINST**.
WEIRD = _census.WEIRD

# **AND **THE **PORT's **OWN **SUBSTRATE **VOCABULARY**, **AND **THE **CENSUS's **WEIRD
# **REGEX **MISSES **IT**, **AND **MEASURED**: **THE **SIX **BEND **SUBSTRATE **NOTES **IN
# **`runtime/ops_python.bend`** **MATCHED **NO **MARKER **AT **ALL**, **AND **THEY **ARE
# **THE **SUBSTRATE **RULES **THE **FILE **IS **WRITTEN **AGAINST**, **AND **THEY **ARE
# **THE **WEIRD **CLASS** -- **AND **SO **THE **CUT **KEPT **ONLY **THE **HEADER **OF
# **THEIR **LIST **AND **DROPPED **ALL **SIX**.
# **AND **THE **RULE **THAT **NO **TRIM **MAY **BREAK**, **AND **MEASURED**: **ANOTHER
# **UNIT's **COMMIT **`8e3596ac8`** **IS **TITLED **"REPAIR **elf.bend: **A **TRIM **LEFT
# **DANGLING **SENTENCES **AND **DELETED **BUG **RECORDS"**, **AND **IT **RESTORED **A
# **RECORD **OF **A **REAL **PORT **BUG**, **AND **ITS **RULE **IS **"NEVER **DELETE **A
# **COMMENT **THAT **RECORDS **A **BUG **THAT **WAS **FOUND"**, **AND **AND **THE **PORT's
# **HISTORY **IS **LOAD-BEARING**.
BUG = re.compile(
  r"\b(SAW NOTHING|A COUNT SAW|WAS A BUG|IS A BUG|FOUND THE BUG|CAUGHT THE BUG|"
  r"THREE BUGS|BOTH WERE BUGS|SAME BUG|NOT ONE OF THE TASKS RUNS|"
  r"THE BUG|THAT BUG|THIS BUG|A REAL BUG|BUGS GOT THIS FILE|"
  r"ANSWERED WRONG|ANSWERED `None`|ANSWERS THE WRONG|WRONG ANSWER|"
  r"WAS WRONG ON|GETS WRONG|DID NOT RUN|DID NOT MATCH|REGRESSION|"
  r"WALL, NOT A|WAS THE CAUSE|ROOT CAUSE|CAUSE OF|"
  r"THE FIRST REVISION|THE FIRST VERSION|THE FIRST ATTEMPT|THE ORIGINAL|THE FIRST BUG|"
  r"IN ITSELF|FIND IN ITSELF|FOUND IN ITSELF|"
  r"IS MUTUAL RECURSION|MUTUAL RECURSION|"
  r"AN EARLIER|A PREVIOUS (VERSION|REVISION|ATTEMPT)|"
  r"FELL OFF THE END|ANSWERED 8|IS WHAT CAUGHT IT|WHAT CAUGHT IT|"
  r"IS WRONG AT THE PIN|WAS WRONG AT THE PIN|"
  r"THE BOTTOM VALUE|IS A REAL PYTHON BUG|"
  r"THE OLD CLAIM|IS FALSE AT THE PIN)\b", re.IGNORECASE)

# **AND **THE **QUOTED **UPSTREAM **LINE** -- **AND **THE **PORT **QUOTES **UPSTREAM's
# **OWN **COMMENT **AS **THE **RULE's **NAME**, **AND **THE **QUOTE **IS **THE
# **DIFFERENCE** (**WHAT **UPSTREAM **SAYS **AT **THAT **LINE**), **AND **AND **A **QUOTE
# **LOOKS **LIKE **A **NARRATION **SECTION** **AND **SO **THE **CUT **TOOK **THE **QUOTE
# **AND **LEFT **THE **EXPLANATION**, **AND **AND **THE **EXPLANATION **IS **THE **REASON
# **THE **RULE **IS **WHAT **IT **IS**.
QUOTED = re.compile(r"^\s*#\s*\"")
# **AND **A **QUOTE **MAY **SPAN **TWO **LINES** ("the quote opens on one line and
# **closes **on **the **next**, **AND **THEN **THE **LINE **NUMBER **IS **ON **THE
# **CLOSING **LINE**), **AND **SO **THE **CLOSING **LINE **IS **THE **ONE **THAT
# **CARRIES **THE **UPSTREAM **LINE **NUMBER**.
QUOTED_CLOSE = re.compile(r"^\s*#\s*[^\"]*\"\s*\(\d+")

SUBSTRATE = re.compile(
  r"\b(MUST BE|MUST ONLY|ONLY\s+\S+\s+MAY|IS REFUSED|ARE REFUSED|REFUSES|REFUSED|"
  r"CANNOT|CAN NOT|NEEDS A|NEED A|IS NOT A|ARE NOT|IS AFFINE|AFFINE|ONE USE|"
  r"ANSWERS A PAIR|ONLY SCRUTINEES|SCRUTINEE|IS A ONE|MAY ONLY|ONLY IF|"
  r"THE SUBSTRATE|SUBSTRATE|IS AN ERROR|IS A WALL|WALL\b)\b")
DIFFERENCE = _plan.DIFFERENCE
NARRATION = _plan.NARRATION

# **⇒⇒† AND **THE **APPLIER's **OWN **ENTRYPOINT **WALKS **`PORT`**, **⇒⇒† AND **THE **NAME
# **WAS **ONLY **BOUND **IN **THE **TWO **MODULES **IT **LOADS**, **⇒⇒† AND **SO **THE
# **`__main__` **LOOP **RAISED **`NameError`**. **⇒⇒† AND **THE **ROOT **IS **THE **TREE's**.
PORT = _plan.PORT


# **A **NEW **ITEM **OF **THE **SAME **LIST** -- **A **BULLET, **OR **A **NUMBERED **ENTRY**.
ITEM = re.compile(r"^\s*#\s*(?:[-*+]\s+|\d+[.)]\s+|[`\"']?[A-Za-z_][\w]*`?\s\s)")


def is_marker(line: str) -> bool:
  return bool(DIFFERENCE.search(line) or CITE.search(line) or MEASURED.search(line)
              or WEIRD.search(line) or SUBSTRATE.search(line) or BUG.search(line)
              or QUOTED.search(line) or QUOTED_CLOSE.search(line))


def sections(blk):
  """**THE **SECTIONS **OF **ONE **COMMENT **RUN**, **SPLIT **AT **THE **BLANK **COMMENT
  **LINES**.

  **AND **A **NUMBERED **OR **BULLETED **LIST **IS **ONE **SECTION**, **AND **NOT **ONE
  **SECTION **PER **ITEM**, **AND **BECAUSE **THE **ITEMS **OF **A **LIST **ARE **THE
  **CLAIMS **OF **ONE **LIST**, **AND **CUTTING **ITEM **3 **OF **6 **LEAVES **A **LIST
  **THAT **LIES **BY **OMISSION**.
  """
  out = []
  cur = []
  for line in blk:
    if line.strip() == "#" and cur:
      out.append(cur)
      cur = [line]
    else:
      cur.append(line)
  if cur:
    out.append(cur)
  return out


def paragraph_end(blk, start: int) -> int:
  """**THE **INDEX **OF **THE **LAST **LINE **OF **THE **CLAIM **THAT **CONTAINS
  **`start`**.

  **AND **A **CLAIM **THAT **OPENS **A **LIST **EXTENDS **THROUGH **THE **ITEMS **OF **THAT
  **LIST**, **AND **BECAUSE **THE **ITEMS **ARE **THE **CLAIMS **OF **ONE **LIST**, **AND
  **CUTTING **ITEM **3 **OF **6 **LEAVES **A **LIST **THAT **LIES **BY **OMISSION**.

  **AND **AND **IT **EXTENDS **TO **THE **END **OF **THE **SENTENCE**, **AND **BECAUSE **A
  **MARKER **LINE **IS **OFTEN **THE **CITATION **ON **THE **SECOND **LINE **OF **A
  **SENTENCE**, **AND **SO **STOPPING **AT **THE **MARKER **LEAVES **A **FRAGMENT**.
  """
  j = start + 1
  while j < len(blk):
    if blk[j].strip() == "#":
      break
    j += 1
  # **AND **NOW **EXTEND **THROUGH **THE **FOLLOWING **ITEMS **OF **THE **SAME **LIST**.
  while j < len(blk):
    if not ITEM.match(blk[j]):
      break
    k = j + 1
    while k < len(blk) and blk[k].strip() != "#" and not ITEM.match(blk[k]):
      k += 1
    if k >= len(blk) or blk[k].strip() == "#":
      break
    j = k
  # **AND **AND **THROUGH **THE **END **OF **THE **SENTENCE **THE **MARKER **IS **IN**.
  end = sentence_end(blk[:j], start)
  if end > j:
    j = end
  while j > start and blk[j - 1].strip() == "#":
    j -= 1
  return j


def sentence_end(body, start: int) -> int:
  """**THE **INDEX **OF **THE **LAST **LINE **OF **THE **FIRST **SENTENCE **OF **THE
  **SECTION**, **AND **A **SENTENCE **ENDS **AT **A **LINE **THAT **ENDS **WITH **`.`,
  **`!` **OR **`?`**, **AND **AND **A **LINE **THAT **ENDS **WITH **A **COMMA **OR **WITH
  **"AND" **IS **THE **MIDDLE **OF **ONE**.

  **AND **THIS **IS **THE **CURE **FOR **THE **DEFECT **THE **FIRST **APPLIER **HAD**:
  **AND **IT **KEPT **THE **FIRST **LINE **OF **A **PURE-NARRATION **SECTION**, **AND **AND
  **THAT **FIRST **LINE **WAS **THE **MIDDLE **OF **A **SENTENCE**, **⇒⇒† AND **SO **THE
  **CUT **LEFT **"THE **NODE **BUILDERS. **Every **one **is **a **`UOp(...)` **call **in
  **Python's **rule **bodies, **and **every"** **AND **NOTHING**, **⇒⇒† AND **A **FRAGMENT
  **IS **WORSE **THAN **THE **ESSAY**.
  """
  j = start + 1
  while j < len(body):
    b = body[j].strip().lstrip("#").strip()
    if b.endswith((".", "!", "?", ":")):
      return j + 1
    j += 1
  return len(body)


def keep_count(sec, bug_run=False):
  """**HOW **MANY **LINES **THE **SECTION **KEEPS**, **AND **WHY**.

  **AND **A **SECTION **THAT **OPENS **WITH **A **BLANK **COMMENT **LINE** **IS **JUDGED
  **ON **THE **CONTENT **AFTER **IT**, **AND **THE **BLANK **IS **KEPT** -- **AND **OTHERWISE
  **THE **CUT **WOULD **LEAVE **A **BLANK **LINE **WHERE **THE **TEXT **WAS**.

  **AND **A **SECTION **THAT **IS **A **LIST **IS **KEPT **WHOLE **IF **ANY **OF **ITS
  **ITEMS **CARRIES **A **MARKER**, **AND **BECAUSE **THE **ITEMS **OF **A **LIST **ARE
  **THE **CLAIMS **OF **ONE **LIST**, **AND **CUTTING **ITEM **3 **OF **6 **LEAVES **A
  **LIST **THAT **LIES **BY **OMISSION**.
  """
  lead = 0
  while lead < len(sec) and sec[lead].strip() == "#":
    lead += 1
  body = sec[lead:]
  if not body:
    return len(sec), "a blank separator"
  text = " ".join(body)
  if (NARRATION.search(text) and not DIFFERENCE.search(text) and not MEASURED.search(text)
      and not WEIRD.search(text) and not SUBSTRATE.search(text) and not BUG.search(text)):
    # **AND **A **PURE-NARRATION **SECTION **IS **KEPT **WHOLE **IF **IT **IS **SHORT**,
    # **AND **OTHERWISE **IT **IS **KEPT **THROUGH **THE **END **OF **ITS **FIRST
    # **SENTENCE**, **AND **AND **A **SECTION **THAT **IS **ALL **ONE **SENTENCE **IS **KEPT
    # **WHOLE**, **AND **AND **A **SECTION **THAT **IS **A **LEAD-IN **AND **A **BODY** **IS
    # **KEPT **THROUGH **THE **BODY's **END**.
    return lead + sentence_end(body, 0), "PURE NARRATION -> the first sentence"
  # **AND **A **LIST **IS **KEPT **WHOLE** -- **AND **ITS **ITEMS **ARE **THE **CLAIMS
  # **OF **ONE **LIST**, **AND **CUTTING **ONE **OF **THEM **LEAVES **A **LIST **THAT
  # **LIES **BY **OMISSION**.
  if any(ITEM.match(l) for l in body) and any(is_marker(l) for l in body):
    return len(sec), "a list with a marker -> the whole list"
  # **AND **A **SECTION **THAT **RECORDS **A **BUG **IS **KEPT **WHOLE**, **AND **BECAUSE
  # **THE **RECORD **MAY **BEGIN **A **LINE **OR **TWO **BEFORE **THE **MARKER**, **AND
  # **AND **CUTTING **THE **HEAD **OF **THE **RECORD **LEAVES **THE **REST **OF **IT
  # **POINTING **AT **NOTHING**, **AND **AND **ANOTHER **UNIT's **COMMIT
  # **`8e3596ac8`** **IS **THE **REPAIR **OF **EXACTLY **THIS**.
  if BUG.search(text):
    return len(sec), "a bug record -> the whole section"
  if bug_run:
    return len(sec), "a run that records a bug -> the whole section"
  for i, l in enumerate(body):
    if is_marker(l):
      return lead + paragraph_end(body, i), "the marker's paragraph"
  # **AND **A **SECTION **WITH **NO **MARKER **AT **ALL** **IS **KEPT **THROUGH **THE **END
  # **OF **ITS **FIRST **SENTENCE**, **AND **NOT **THROUGH **ITS **FIRST **LINE**, **AND
  # **BECAUSE **THE **FIRST **LINE **IS **OFTEN **THE **MIDDLE **OF **A **SENTENCE**, **AND
  # **AND **A **FRAGMENT **IS **WORSE **THAN **THE **ESSAY**.
  return lead + sentence_end(body, 0), "no marker -> the first sentence"


def apply_file(f: pathlib.Path, lim: int, dry: bool):
  """**⇒⇒† AND **IT **WALKS **THE **FILE's **LINES**, **⇒⇒† AND **A **NON-COMMENT **LINE
  **IS **EMITTED **VERBATIM**, **⇒⇒† AND **SO **THE **CODE **CANNOT **MOVE**."""
  lines = f.read_text().split("\n")
  out = []
  cut = 0
  i = 0
  while i < len(lines):
    if not lines[i].strip().startswith("#"):
      out.append(lines[i])
      i += 1
      continue
    j = i
    while j < len(lines) and lines[j].strip().startswith("#"):
      j += 1
    blk = lines[i:j]
    run_text = " ".join(blk)
    bug_run = bool(BUG.search(run_text))
    for sec in sections(blk):
      # **⇒⇒† AND **A **SECTION **THAT **IS **ONLY **BLANK **`#` **LINES** **IS **A
      # **SEPARATOR**, **⇒⇒† AND **IT **CARRIES **NO **CONTENT**, **⇒⇒† AND **SO **IT **IS
      # **DROPPED **WHEN **THE **PRECEDING **SECTION **ALREADY **ENDS **WITH **ONE**.
      if all(l.strip() == "#" for l in sec):
        if out and out[-1].strip() == "#":
          continue
        out.extend(sec)
        continue
      if len(sec) <= lim:
        out.extend(sec)
        continue
      keep, _why = keep_count(sec, bug_run)
      if keep >= len(sec):
        out.extend(sec)
        continue
      # **⇒⇒† AND **A **KEPT **SECTION **MUST **NOT **LEAVE **A **BLANK **`#` **THAT **THE
      # **NEXT **ONE **REPEATS**, **⇒⇒† AND **SO **THE **BLANK **IS **DROPPED **WHEN **THE
      # **KEPT **TAIL **IS **ALREADY **BLANK**.
      kept = sec[:keep]
      while kept and kept[-1].strip() == "#" and out and out[-1].strip() == "#":
        kept = kept[:-1]
      out.extend(kept)
      cut += len(sec) - keep
    i = j
  if cut and not dry:
    f.write_text("\n".join(out))
  return cut


if __name__ == "__main__":
  lim = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 4
  only = sys.argv[2] if len(sys.argv) > 2 else ""
  dry = "--dry" in sys.argv
  total = 0
  for f in sorted(PORT.rglob("*.bend")):
    rel = str(f.relative_to(PORT))
    if only and not rel.startswith(only):
      continue
    c = apply_file(f, lim, dry)
    if c:
      print(f"{c:7d}  {rel}")
      total += c
  print(f"THE LINES CUT: {total}")
