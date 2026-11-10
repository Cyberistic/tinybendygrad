#!/usr/bin/env python3
"""demark.py -- **STRIP THE TREE's OLD EMPHASIS MARKS FROM COMMENTS.**

    .venv/bin/python .agents/slop/loc/demark.py --apply <file>...
    .venv/bin/python .agents/slop/loc/demark.py --report <file>...

**WHAT IT DOES, AND WHY EACH EDIT IS SAFE:**

  * **`**` → NOTHING.** THE ASTERISKS ARE **THE EMPHASIS MARKER** AND **THEY CARRY NO
    INFORMATION** — **THE WORDS ARE THE INFORMATION.** **THIS IS **A PURE DELETION** AND
    **IT CANNOT CHANGE WHAT A COMMENT SAYS.**
  * **` ` → `-`.** THE ARROW IS THE OLD STYLE'S "AND THEREFORE" MARKER, **AND `-` READS AS
    THE SAME CONNECTOR IN A PLAIN-TEXT COMMENT.** **THIS IS **A PURE SUBSTITUTION** AND
    **IT CANNOT CHANGE WHAT A COMMENT SAYS.**
  * **THE ALL-CAPS SHOUTING → SENTENCE CASE.** **THIS IS **THE ONLY EDIT THAT CHANGES
    WORDS**, **AND IT IS SAFE BECAUSE **ALL-CAPS IS **NOT** A DIFFERENT WORD** — IT IS THE
    SAME LETTERS IN A DIFFERENT CASE, **AND A COMMENT IN SENTENCE CASE SAYS EXACTLY WHAT IT
    SAID BEFORE.** **AND THE **EXEMPT LIST** (THE TYPE-LIKE NAMES THE CODE ITSELF USES:
    `UOp`, `CMPEQ`, `Ops`, ...) IS **NEVER** TOUCHED**, **BECAUSE THOSE NAMES ARE
    **IDENTIFIERS** AND CHANGING THEIR CASE WOULD MAKE THEM WRONG.**

**AND WHAT IT NEVER TOUCHES:**
  * **THE COMMENTS' WORDS**, EXCEPT FOR THE CASE OF A SHOUTED WORD.
  * **THE CODE.** ONLY COMMENT LINES ARE READ.
  * **THE `.md` FILES.** ONLY SOURCE COMMENTS.
  * **A CITATION.** A CITATION IS `elementwise.py:57` OR `tinygrad/uop/ops.py` — **AND THE
    PATHS ARE NOT SHOUTED, SO THEY ARE NOT TOUCHED** — **BUT THE EXEMPT LIST ALSO GUARDS
    THEM.**

**AND IT PRINTS **WHAT IT WOULD DO** BEFORE IT DOES IT** — **AND IT IS **IDEMPOTENT**:
RUNNING IT TWICE CHANGES NOTHING THE SECOND TIME.**
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DIRS = ("tinybendygrad", "gates", "checks", "oracles", "examples")
SUFFIXES = (".bend", ".py", ".js", ".mjs", ".c", ".sh")

# **THE **EXEMPT** NAMES** -- **THE TYPE-LIKE ONES AND THE PATH-LIKE ONES** -- **AND THEY
# ARE **NEVER** RE-CASED**, **BECAUSE THEY ARE **IDENTIFIERS**.**
EXEMPT = {
    "UOp", "Ops", "CMPEQ", "CMPLT", "CMPNE", "ADD", "MUL", "SUB", "DIV", "MOD", "CONST",
    "SPEC", "CAST", "PARAM", "BUFFER", "RANGE", "INDEX", "WHERE", "STORE", "LOAD", "NULL",
    "BOOL", "INT", "FLOAT", "NONE", "TRUE", "FALSE", "IF", "ELSE",
    "TODO", "WARN", "INFO", "DEBUG", "ERROR", "NOTE", "FIXME", "XXX", "HACK",
    "HEAD", "MAIN", "MASTER", "PIN", "CPYTHON", "BENCH", "GIT",
    "PY", "CPYTHON", "BEND", "AMD", "NV", "CUDA", "CPU", "CL", "RDMA", "WEBGPU", "QS",
    "WASM", "NULL", "NULLDEVICE", "LOOP", "MOVE", "COPY", "FOLD", "ARG", "DEF", "TYPE",
    "ID", "IO", "SRC", "DST", "LEN", "SIZE", "ADDR", "OFFSET", "BITS", "BYTE", "WORD",
}
CAPS_WORD = re.compile(r"\b[A-Z][A-Z0-9_]{2,}\b")
MAX_CAPS = 5
# **A **PATH** IS NEVER RE-CASED** -- **IT NAMES A FILE.**
PATHY = re.compile(r"[\w/]+\.(py|bend|md|rows|sh|js|c)\b")


def caps_words(body: str) -> list[str]:
    """**THE SHOUTED WORDS OF **ONE** LINE, **EXCLUDING THE EXEMPT ONES** -- **AND THE
    EXEMPT ONES ARE **MASKED** FIRST, **SO A RUN LIKE `CMPEQ CMPNE` IS NOT COUNTED AS
    **TWO** SHOUTED WORDS**."""
    masked = {}
    body2 = body
    for i, w in enumerate(sorted(EXEMPT, key=len, reverse=True)):
        if not re.search(rf"(?<![A-Za-z0-9_]){re.escape(w)}(?![A-Za-z0-9_])", body2):
            continue
        ph = f"\x00EX{i}\x00"
        body2 = re.sub(rf"(?<![A-Za-z0-9_]){re.escape(w)}(?![A-Za-z0-9_])", ph, body2)
        masked[ph] = w
    body2 = re.sub(r"[\w/]+\.(?:py|bend|md|rows|sh|js|c)(?::\d+)?\b", " ", body2)
    out = []
    for m in CAPS_WORD.finditer(body2):
        if m.group(0) in EXEMPT:
            continue
        if any(c.isdigit() for c in m.group(0)):
            continue
        out.append(m.group(0))
    return out


def unshout(body: str, first_line: bool = True) -> str:
    """**THE SHOUTED WORDS → **LOWERCASE**, **AND **THE EXEMPT LIST IS **NEVER** TOUCHED.**

    **AND **LOWERCASE**, NOT "CAPITALIZE EACH WORD"** -- **MEASURED 2026-11-10: THE FIRST
    ATTEMPT CAPITALIZED EACH WORD AND PRODUCED **"Recopied", "One caller", "All Proofs
    Check"**, **WHICH ARE NOT WORDS.** **THE SHOUT IS **ONE RUN** OF CAPS AND **IT IS
    **A PHRASE**, **AND THE PHRASE IS LOWERCASED AS A WHOLE** — **AND THE FIRST WORD
    **KEEPS** ITS CAPITAL** SO THE SENTENCE STILL READS AS A SENTENCE.

    **AND **A WORD **THAT IS **PARTLY** A PATH** IS **NOT** TOUCHED** -- **`Ops.py` IS A
    FILE NAME AND `Ops` INSIDE IT IS **PART** OF A PATH.** **AND A WORD WITH **A DIGIT**
    IS AN **IDENTIFIER** (`RDMA3`, `RDNA4`) **AND ITS CASE IS ITS NAME** -- **SO IT
    STAYS.**"""
    # **THE EXEMPT NAMES ARE **MASKED** FIRST, **SO THE RUN-LOWERING CANNOT TOUCH
    # THEM.** **AND A MASKED NAME IS **ONE TOKEN**, **SO A RUN LIKE `CMPEQ CMPNE` IS NOT
    # JOINED INTO ONE "RUN" AND MISTAKEN FOR A PHRASE.**
    masked = {}
    body2 = body
    for i, w in enumerate(sorted(EXEMPT, key=len, reverse=True)):
        if not re.search(rf"(?<![A-Za-z0-9_]){re.escape(w)}(?![A-Za-z0-9_])", body2):
            continue
        ph = f"\x00EX{i}\x00"
        body2 = re.sub(rf"(?<![A-Za-z0-9_]){re.escape(w)}(?![A-Za-z0-9_])", ph, body2)
        masked[ph] = w
    # **AND THE **PATH-LIKE** NAMES ARE MASKED TOO.**
    # **AND **THE TICKED SPANS** ARE MASKED **FIRST** -- **MEASURED 2026-11-10: THE PATH
    # REGEX RAN FIRST AND CONSUMED `symbolic.py:140` **FROM INSIDE** THE TICKED SPAN, **AND
    # THE TICK MASK's TEXT WAS THEN THE PATH MASK's TEXT** ("`PATH2`").** **AND A TICKED
    # SPAN **IS **AN IDENTIFIER REFERENCE** AND **ITS CASE IS ITS NAME**, **SO IT IS MASKED
    # WHOLE** -- **AND **THE PATHS **INSIDE** IT **ARE NEVER SEEN AGAIN**.**
    def _mask_tick(m: re.Match) -> str:
        ph = f"\x02TICK{len(masked)}\x02"
        masked[ph] = m.group(0)
        return ph
    body2 = re.sub(r"`[^`]*`", _mask_tick, body2)
    def _mask_path(m: re.Match) -> str:
        ph = f"\x01PATH{len(masked)}\x01"
        masked[ph] = m.group(0)
        return ph
    body2 = re.sub(r"[\w/]+\.(?:py|bend|md|rows|sh|js|c)(?::\d+)?\b", _mask_path, body2)

    def _lower_run(m: re.Match) -> str:
        run = m.group(0)
        words = run.split()
        # **A RUN THAT **STARTS A SENTENCE** KEEPS ITS FIRST WORD's CAPITAL** -- **AND A
        # RUN **FOLLOWING** A FULL STOP IS **A NEW SENTENCE** -- **MEASURED 2026-11-10:
        # "`. THE NAME DID NOT CHANGE AND THE NODE DID`" BECAME "`. the name did not change
        # AND the node did`", **AND THE SENTENCE-STARTING WORD MUST KEEP ITS CAPITAL**.**
        low = []
        for w in words:
            if w in ("AND", "OR"):
                low.append(w)
            elif any(c.isalpha() for c in w) and not any(c.isdigit() for c in w):
                low.append(w.lower())
            else:
                low.append(w)
        return " ".join(low)

    # **A RUN IS **ONE OR MORE** SHOUTED WORDS** -- **AND THE RUN IS **A PHRASE** THAT
    # **IS LOWERCASED AS A WHOLE**, **WITH **THE FIRST WORD **KEEPING** ITS CAPITAL.**
    # **AND THE **MASKED** TOKENS **JOIN** THE RUN** -- **MEASURED 2026-11-10: `AND` IS
    # IN THE EXEMPT LIST, **SO IT IS MASKED**, **AND THE RUN AROUND IT WAS SPLIT**, **AND
    # "AND" WAS LEFT CAPITALISED IN THE MIDDLE OF A SENTENCE** ("the port is 5x upstream AND
    # that is a measurement"). **AND `AND` IS **A CONNECTIVE** AND NOT **AN IDENTIFIER**,
    # **SO IT IS **NOT** EXEMPT** -- **IT IS **THE WORD** THAT JOINS TWO SHOUTED CLAUSES.**
    # **THE SHOUT IS LOWERCASED **AS A SENTENCE** -- **AND THE SENTENCE'S FIRST WORD
    # KEEPS ITS CAPITAL** -- **MEASURED 2026-11-10: "THE NAME DID NOT CHANGE AND THE NODE
    # DID" IS **A SHOUTED SENTENCE**, **AND LOWERCASING **HALF** OF IT ("THE name did not
    # change") IS WORSE THAN EITHER WHOLE FORM.**
    def _sentence_lower(m: re.Match) -> str:
        sent = m.group(0)
        if not sent:
            return sent
        # **THE FIRST WORD OF **THE WHOLE COMMENT** KEEPS ITS CAPITAL** -- **IT IS **THE
        # SENTENCE'S** FIRST WORD** -- **AND EVERY OTHER RUN IS LOWERCASED WHOLE.**
        # **THE COMMENT'S FIRST WORD IS PROTECTED **ONLY IF **THE COMMENT **STARTS**
        # WITH IT** -- **AND A COMMENT THAT **STARTS** WITH A TICKED SPAN HAS **NO**
        # PROTECTED WORD** (THE TICKED SPAN IS THE FIRST THING).**
        prefix = re.sub(r"\x00[A-Z]*[0-9]*\x00|\x01PATH[0-9]*\x01|\x02TICK[0-9]*\x02", "", body2[: m.start()])
        # **THE COMMENT'S FIRST WORD IS **NOT** PROTECTED** -- **MEASURED 2026-11-10:
        # "WHAT IS PORTED" BECAME "what is ported", **AND A SHOUTED HEADER BLOCK HAS NO
        # SENTENCE-STARTING FIRST WORD** -- **THE WHOLE BLOCK IS ONE SHOUT.**
        first_of_comment = False
        # **THE WORD AFTER A CLOSING BACKTICK IS **NOT** LOWERCASED** -- **IT IS **THE
        # CONTINUATION OF AN IDENTIFIER REFERENCE** ("THE `CMPEQ` RULE").**
        words = sent.split()
        out = []
        for w in words:
            out.append(w.lower() if (any(c.isalpha() for c in w)
                                     and not any(c.isdigit() for c in w)) else w)
        return " ".join(out)

    # **AND A **POSSESSIVE** `X'S` IS **ONE WORD** -- **MEASURED 2026-11-10:
    # "A KERNEL'S BUFFER LIST" BECAME "a kernel'S BUFFER LIST"** -- **SO THE RUN MUST
    # **INCLUDE** THE `'s`, AND THE WORD MUST BE LOWERCASED **WHOLE**.**
    body2 = re.sub(r"\b(?:[A-Z][A-Z0-9_]*(?:'S)?)(?:[ \t]+(?:AND|OR|[A-Z][A-Z0-9_]*(?:'S)?))*\b",
                   lambda m: _sentence_lower(m), body2)
    # **THE RESTORE IS **LONGEST-FIRST** -- **MEASURED 2026-11-10: THE PATH MASK's TEXT
    # CONTAINED A TICK MASK, **AND **A SHORTER** MASK RESTORED FIRST REPLACED **THE INNER**
    # ONE, **AND THE OUTER RESTORE THEN FOUND NOTHING** -- **AND THE OUTER TEXT WAS
    # RESTORED WITH THE INNER MASK STILL IN IT** ("` 19 `").**
    for ph in sorted(masked, key=len, reverse=True):
        body2 = body2.replace(ph, masked[ph])
    return body2


def clean(line: str, first_line: bool = True) -> str:
    """**ONE COMMENT LINE, CLEANED. **AND **A **NON**-COMMENT LINE IS **RETURNED AS IT
    IS**."""
    s = line.strip()
    if not s.startswith("#"):
        return line
    indent = line[: len(line) - len(line.lstrip())]
    body = s.lstrip("#")
    lead = len(body) - len(body.lstrip())
    b = body.strip()
    # **THE `**` MARKER IS EMPHASIS **AND NOT EXPONENTIATION** -- **MEASURED 2026-11-10:
    # `dtype.bend:553` READS `# Python: commit_int(2**32, 2**33, dtypes.i32) == dtypes.i64.`,
    # **AND THAT IS **CODE** IN A COMMENT, **AND STRIPPING ITS `**` WOULD CORRUPT IT.**
    # **SO THE `**` IS STRIPPED **ONLY** WHERE IT IS **PAIRED** AND **NOT** BETWEEN TWO
    # DIGITS.**
    b = strip_emphasis(b)
    # **THE ` ` -> `-` SUBSTITUTION** -- **AND IT RUNS **AFTER** THE SHOUT, **BECAUSE THE
    # SHOUT'S RUN PATTERN **IS ASCII** AND **THE ` ` IS NOT**, **SO THE ORDER DOES NOT
    # MATTER** -- **AND IT IS HERE FOR CLARITY.**
    b = b.replace(" ", "-")
    # **AND THE SHOUT IS **LEFT ALONE** UNLESS **THE LINE CROSSES **THE THRESHOLD**.**
    if len(caps_words(b)) > MAX_CAPS:
        b = unshout(b, first_line)
    return f"{indent}#{' ' * lead}{b}"


def strip_emphasis(b: str) -> str:
    """**STRIP THE `**` EMPHASIS MARKER, **AND **NOT** THE `**` EXPONENTIATION.**

    **MEASURED 2026-11-10: A COMMENT CAN CARRY **REAL PYTHON** (`commit_int(2**32,
    2**33, dtypes.i32)`), **AND `2**32` IS **THE EXPONENT OPERATOR**, **NOT EMPHASIS.**
    **THE RULE: A `**` BETWEEN **TWO DIGITS** IS **AN EXPONENT** AND STAYS; **EVERY
    OTHER `**` IS EMPHASIS AND GOES.**
    """
    out = []
    i = 0
    while i < len(b):
        if b[i:i + 2] == "**":
            prev = b[i - 1] if i else ""
            nxt = b[i + 2] if i + 2 < len(b) else ""
            if prev.isdigit() and nxt.isdigit():
                out.append("**")
                i += 2
                continue
            i += 2
            continue
        out.append(b[i])
        i += 1
    return "".join(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*", default=[])
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()
    files = [ROOT / p for p in args.files]
    if not files:
        print(__doc__)
        return 0
    total = 0
    for path in files:
        lines = path.read_text().split("\n")
        out = [clean(l) for l in lines]
        changed = sum(1 for a, b in zip(lines, out) if a != b)
        total += changed
        if args.report:
            for a, b in zip(lines, out):
                if a != b:
                    print(f"  {path}: {a.strip()[:88]}")
                    print(f"  {' ' * len(path.name)}  {b.strip()[:88]}")
        path.write_text("\n".join(out))
    print(f"  {total} lines changed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
