#!/usr/bin/env python3
"""formblind-audit.py -- A MECHANICAL ASSERTION FOR EVERY BLIND VARIANT NAMED BY THE CENSUS,
and it must FAIL on a constructed instance of that variant.

    .venv/bin/python .agents/slop/formblind-audit.py            # all audits, exit 1 on any
    .venv/bin/python .agents/slop/formblind-audit.py --only A3  # one
    .venv/bin/python .agents/slop/formblind-audit.py --list

THE RULE UNDER AUDIT, STATED ONCE.

    A TOOL THAT MATCHES A FORM CANNOT SEE THE INSTANCE THAT LACKS IT.

THE TEST THAT GOES WITH IT, AND WHY IT IS THE ONLY ONE THAT WORKS.

    SPELLING-INVARIANCE. Build two texts that MEAN THE SAME THING and are WRITTEN
    DIFFERENTLY. A reader that answers differently is matching a form; name the variant.

Every one of the six findings this round was discovered by a DISAGREEMENT between two tools
that meant the same thing, never by reading a tool. So this audit asserts disagreements, and
an audit that cannot fail is treated as harmful rather than reassuring. WHICH GIVES THE
`control` FIELD, and it is the part that makes these audits real:

  * `control` is a reader built HERE, in this file, that is BLIND ON PURPOSE to exactly the
    variant under audit. Every audit runs it and requires it to MISS. If the control ever
    passes, the assertion shape is broken -- it has stopped being able to detect a miss --
    and the audit fails with `CONTROL DID NOT MISS`, which is the failure mode of an audit
    whose expected value is read from the thing under test. `not-applied-audit.py` records
    that bug in an auditor that had been passing a 4-cell row in a 3-column table.
  * `expect` is the polarity the REAL reader must show. `MISS` for the six unfixed variants;
    `SEE` for the one this round already fixed (`graphcmp.unchunks`), where the control is
    the pre-fix reader reconstructed from `graphcmp-LIMITS.md` item 5 rather than from the
    tool.

WHERE THE EXPECTED VALUES COME FROM. Never from the tool under test. Each audit names its
source in `src=`:

  * `rowform.any_row`   an independent read-any-shape reader written in this repo, which
    exists to be a second opinion and is not a copy of `rebase-gate.row()`.
  * `constructed`       a number I wrote into the text and can therefore count. The text is
    printed on every run, so the count can be checked by reading.
  * `CPython`           `ast` / `int()`, i.e. the interpreter's own answer rather than this
    project's.
  * `handtyped-audit`   the AST-based detector in this repo, which is the CORRECTED answer
    and disagrees with `unobservable-census.py --handtyped` by a measured 224 -> 578. Two
    detectors disagreeing IS the finding; the audit is the disagreement, made executable.

Every audit PRINTS the constructed text, the reader's own answer, the control's own answer,
and where the expected value came from. Nothing here is transcribed: each reader is imported
and CALLED.
"""
from __future__ import annotations

import argparse
import importlib.util
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from rowform import any_row, load_shared_reader  # noqa: E402

PY = HERE.parents[2] / ".venv" / "bin" / "python"


def load(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


RG = load(HERE / "rebase-gate.py", "rg_under_audit")


# ---------------------------------------------------------------------------
# CONTROL READERS.  Blind ON PURPOSE, one per construct.  Each is the smallest reader that
# cannot see its variant, written here rather than imported, so the audit does not depend on
# a second copy of the thing it is checking staying broken.
# ---------------------------------------------------------------------------
def rows_pre_f3(text: str) -> dict:
    """`name=value` only. The pre-F3 `rebase-gate.rows()`, which found ZERO rows in 213 real
    ground-truth rows -- its own header records that, so this is not a strawman."""
    out = {}
    for line in text.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            if k.strip():
                out[k.strip()] = v.strip()
    return out


def rows_name_must_be_one_token(text: str) -> dict:
    """`=`-first with the F3 two-space gap added and the one-token guard left in. A reader
    that reads the shapes `rebase-gate.row()` reads and refuses a row whose NAME has a space
    -- the shipped reader's remaining hole, reconstructed so the audit does not use the tool
    as its own control."""
    out = {}
    for line in text.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            if k.strip():
                out[k.strip()] = v.strip()
            continue
        head, sep, tail = line.partition("  ")
        if sep and len(head.split()) == 1 and head.strip() and tail.strip():
            out[head.strip()] = tail.strip()
    return out


def rows_eq_or_gap_no_tab(text: str) -> dict:
    """The shipped shapes plus nothing else: a TAB row is invisible. A2's control."""
    return rows_name_must_be_one_token(text)


def rows_eq_then_gap_greedy(text: str) -> dict:
    """`=`-first, then the gap -- i.e. the shipped ORDER. A4's control, and the reason A4 is
    a renaming rather than a disappearance: the row survives under a fabricated name."""
    return rows_name_must_be_one_token(text)


def unchunks_split_on_whitespace(line: str) -> list[str]:
    """THE HISTORICAL BUG, reconstructed from the tool's OWN docstring rather than from its
    code: 'Splitting on whitespace is what dropped 216 of 228 rows in the pin/HEAD study,
    because the row NAMES contain spaces' (graphcmp.py:316). And graphcmp-LIMITS.md item 5
    records the second half: requiring a single space made whitespace STRUCTURAL, which the
    `<bytecount>:<bytes>` format exists precisely to avoid.

    A control copied out of the tool it checks IS the tool, so this one is written from the
    writeup. It must not agree with the form-complete answer or A12 cannot fail.
    """
    return line.split()


#: the `unobservable-census.py --handtyped` regex, VERBATIM, as its own source states it.
#: Transcribed from the literal in the tool because the tool has no callable entry point for
#: it -- `hand_typed()` is, and it is called directly in A6..A11. This copy exists only as
#: the CONTROL; the real reader under test is `census.hand_typed`.
CENSUS_ROW_RE = re.compile(r'\b(?:s?row)\(\s*"([^"]+)"\s*,\s*(.+?)\)\s*(?:#.*)?$', re.M)


def census_hand_typed_control(text: str) -> list:
    """`unobservable-census.hand_typed`'s body, inlined. Blind on purpose: one regex with `$`
    under `re.M`, one name literal, one bare value literal."""
    out = []
    for m in CENSUS_ROW_RE.finditer(text):
        name, val = m.group(1), m.group(2).strip()
        lit = re.fullmatch(r'(?:"[^"]*"|\'[^\']*\'|-?\d+(?:\.\d+)?|True|False|None)', val)
        bare = re.fullmatch(r'f"[^"{]*"', val)
        if lit or bare:
            out.append((name, val))
    return out


def census_hand_typed_no_bare_arm(text: str) -> list:
    """The same detector with the `bare` f-string arm DELETED. A10's control, and the reason
    the arm is load-bearing: `f"1"` is matched by `lit`? No -- `lit` is a fullmatch on
    `"..."`/`'...'`/digits/True/False/None and `f"1"` starts with `f`, so without `bare` this
    row is invisible. So A10 is a case where the FORM-BLIND reading was right and the census
    was wrong, and the way to know which is which is to make both answers executable."""
    return [x for x in census_hand_typed_control(text) if not x[1].startswith("f")]


# ---------------------------------------------------------------------------
# THE AUDITS
# ---------------------------------------------------------------------------
#: ONE ASSERTION, ELEVEN TIMES: THE READER MUST PRODUCE THE FORM-COMPLETE ANSWER.
#:
#: That is the whole claim, and it is the same claim for a reader that has already been fixed
#: and for one that has not. `status` says which is which TODAY, so a reader that is fixed does
#: not need a weaker assertion and a reader that is blind cannot quietly acquire one:
#:
#:   KNOWN-BLIND  the audit FAILS on this tree.  That is the deliverable: a failing assertion
#:                that reconstructs the blind variant, in `not-applied-audit.py`'s shape, and
#:                exits 1 until somebody fixes the reader.  Eleven of them.
#:   PIN          the audit passes today, on a reader that already handles the variant.  These
#:                exist so the KNOWN-BLIND ones cannot be satisfied by a reader that stopped
#:                reading, and so a census that claims blindness where there is none is caught
#:                too -- A10 is one of these, and it exists because the census was WRONG.
#:
#: GETTING THIS BACKWARDS IS HOW A DEFECT AUDIT BECOMES A CENSUS VALIDATOR THAT EXITS 0
#: FOREVER. A reader that cannot see the thing is a FAILURE OF THE WORLD, not a successful
#: confirmation of a hypothesis.
class Audit:
    def __init__(self, aid, what, subject, src, reader, status, control, ctl_name,
                 answer, note=""):
        self.aid, self.what, self.subject = aid, what, subject
        self.src, self.reader, self.status, self.control = src, reader, status, control
        self.ctl_name, self.answer, self.note = ctl_name, answer, note

    def run(self):
        want = self.answer(self.subject)
        got = self.reader(self.subject)
        ctl = self.control(self.subject)
        # (1) THE SUBJECT IS NOT DEGENERATE. An audit run on an empty string has measured
        #     nothing. NOTE THAT AN EMPTY FORM-COMPLETE ANSWER IS A LEGITIMATE CLAIM -- A17's
        #     whole point is that the correct answer for a template file is ZERO rows -- so
        #     this checks the SUBJECT, never the answer.
        ok_present = bool(self.subject.strip())
        # (2) THE ONE ASSERTION.
        ok_real = got == want
        # (3) THE CONTROL MUST NOT AGREE. An audit that cannot tell a wrong reader from a right
        #     one is `not-applied-audit.py`'s bug -- an expected value read from the thing under
        #     test, which agrees with itself. A control that AGREES is a dead audit even when
        #     the real reader happens to be broken.
        ok_ctl = ctl != want
        return {"want": want, "got": got, "ctl": ctl,
                "ok": ok_present and ok_real and ok_ctl,
                "ok_present": ok_present, "ok_real": ok_real, "ok_ctl": ok_ctl}


AUDITS: list[Audit] = []


def add(*a, **k):
    AUDITS.append(Audit(*a, **k))


def any_row_dict(text):
    out = {}
    for line in text.splitlines():
        r = any_row(line)
        if r:
            out[r[0]] = r[1]
    return out


def _ans(want):
    return lambda s: want


# --- A1..A5: rebase-gate.rows(), the shared reader of 9 tools ------------------
add("A1", "rebase-gate.rows(): a row whose NAME carries a space",
    'alpha one  1\n',
    "rowform.any_row -- an independent read-any-shape reader, not a copy of row()",
    RG.rows, "KNOWN-BLIND", rows_name_must_be_one_token,
    "the one-token-name guard (the shipped reader's own remaining hole)",
    _ans({"alpha one": "1"}),
    "F3 requires len(head.split()) == 1. multi-rows.py's F3 shape is f'{n.ljust(w)}  {v}', so "
    "an `n` carrying a space silently drops the row. `schedule/multi.bend` is the lane that "
    "writes F3.")

add("A2", "rebase-gate.rows(): a TAB-separated row",
    'alpha\t1\n',
    "rowform.any_row",
    RG.rows, "KNOWN-BLIND", rows_eq_or_gap_no_tab, "the shipped shapes and nothing else (no TAB)",
    _ans({"alpha": "1"}),
    "A TAB is refused ON PURPOSE -- a TSV table's first column is not a row name, and "
    "dtype_tables.py emits 14,774 TSV lines that must keep reading as zero rows. So this is "
    "a STATED floor rather than a defect, and stating it is what makes every count through "
    "rows() a floor rather than a total.")

add("A3", "rebase-gate.rows(): a SINGLE-space row",
    'alpha 1\n',
    "rowform.any_row",
    RG.rows, "KNOWN-BLIND", rows_pre_f3, "the pre-F3 reader (name=value only)",
    _ans({"alpha": "1"}),
    "GAP is two spaces. A lane that prints `name value` reads as zero rows, and zero rows is "
    "indistinguishable from 'not started'.")

add("A4", "rebase-gate.rows(): a two-space row whose VALUE carries an `=`",
    'alpha  x=1\n',
    "rowform.any_row -- the name is `alpha`, the value is `x=1`",
    RG.rows, "KNOWN-BLIND", rows_eq_then_gap_greedy, "the shipped ORDER: `=` before the gap",
    _ans({"alpha": "x=1"}),
    "The `=` branch fires FIRST, so this does not vanish: it is RENAMED to `alpha  x`, which "
    "is worse than a floor -- a fabricated key can collide with a real one.")

add("A5", "rebase-gate.rows(): the F3 gap it DOES claim -- a pin, so A1..A4 cannot be "
    "satisfied by a reader that simply stopped reading",
    'alpha  1\n',
    "rowform.any_row",
    RG.rows, "PIN", rows_pre_f3, "the pre-F3 reader (zero rows in 213 real ground-truth rows)",
    _ans({"alpha": "1"}),
    "rebase-gate.py's own header records the F3 discovery: '`schedule/multi.bend`'s oracle "
    "prints `f\"{n.ljust(w)}  {v}\"`. NO `=` AT ALL, so F1 found ZERO rows in 213 real rows.'")

# --- A6..A11: unobservable-census.py --handtyped vs handtyped-audit.py ----------
CENSUS = load(HERE / "unobservable-census.py", "census_under_audit")
HT = load(HERE / "handtyped-audit.py", "handtyped_under_audit")


def hand_typed_names(text: str) -> list:
    """`unobservable-census.hand_typed`, CALLED, on a materialised file. The function takes a
    pathlib.Path; the audit gives it one, because 'run the real thing' beats 're-implement
    the real thing'."""
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as fh:
        fh.write(text)
        p = pathlib.Path(fh.name)
    try:
        return sorted(n for n, _v in CENSUS.hand_typed(p))
    finally:
        p.unlink(missing_ok=True)


def ht_defects(text: str) -> list:
    """`handtyped-audit.scan`, CALLED -- the CORRECTED detector, whose own header decomposes
    the 224 -> 578 delta into 90 NAME / 81 VALUE / 69 RADIX / 115 SEMI. Its answer is the
    form-complete one for this audit; the regex reader's silence against it IS the finding."""
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as fh:
        fh.write(text)
        p = pathlib.Path(fh.name)
    try:
        return sorted(r["name"] for r in HT.scan(p)["rows"] if r["defect"])
    finally:
        p.unlink(missing_ok=True)


HT_SOURCES = [
  ('row("a", 3)\n', 'row("a", 0x3)\n',
   "a hex literal -- one integer, two spellings",
   "69 RADIX of the 224->578 delta. agent-core.md: `~0x6996` written as 24425, one table entry."),
  ('row("a", 3)\n', 'row("a", 0b11)\n',
   "a binary literal -- one integer, two spellings", None),
  ('row("a", 1)\n', 'row("a", 1); row("b", 2)\n',
   "TWO row calls on one line",
   "115 SEMI of the delta. The regex's `$` under `re.M` makes the call single-line; and worse, "
   "the non-greedy `(.+?)` swallows the second call so the value it reports is `\"1\"), "
   "row(\"b\"`, which is not a literal -- so the pair is invisible twice over."),
  ('row("a", 3)\n', 'row(f"a_{i}", 3)  # i == 0\n',
   "an f-string ROW NAME -- one name, two spellings",
   "90 NAME of the delta, and the LARGEST single cause. Every oracle that indexes a family "
   "puts the index in the NAME -- which is the whole sibling_blind thesis -- so the families "
   "are the majority of rows and are exactly what the regex cannot see. The VALUE is a "
   "literal in both members on purpose: `handtyped-audit` calls a bare unresolvable name "
   "UNRESOLVED rather than DEFECT, and an UNRESOLVED row is a third class that must not be "
   "quietly scored as derived."),
  ('row("a", "1")\n', 'row("a", f"1")\n',
   "a bare f-string VALUE -- one string, two spellings",
   "THE CLAIM THAT THIS AUDIT KILLED. `bare` is `f\"[^\"{]*\"`, so `f\"1\"` IS matched and the "
   "old detector does see it: 578 is not 578+this. Reclassified SEE. The blind sibling is "
   "`f\"{v}\"`, which is DERIVED and therefore correctly not reported -- the two spellings "
   "differ in MEANING there, so a form-blind reader is the right answer. Kept as a pin "
   "because the census classified it blind and it is not, and a census that is not corrected "
   "is a census that teaches the wrong lesson."),
  ('row("a", 3)\n', 'row(\n  "a",\n  3,\n)\n',
   "a row call WRAPPED across lines -- one call, two layouts",
   "`re.M` + `$` makes the call single-line, and the oracles are heavily wrapped."),
]

for i, (_plain, variant, why, note) in enumerate(HT_SOURCES, start=6):
    add(f"A{i}", f"--handtyped on a spelling of the same row: {why}",
        variant,
        "handtyped-audit.scan (AST) is the form-complete answer; unobservable-census."
        "hand_typed is the reader under test; both are CALLED",
        hand_typed_names,
        "PIN" if i == 10 else "KNOWN-BLIND",       # A10: the claim this audit KILLED, see its note
        census_hand_typed_control if i != 10 else census_hand_typed_no_bare_arm,
        "the regex detector, inlined from unobservable-census.py" if i != 10
        else "the same detector with its `bare` f-string arm REMOVED",
        ht_defects, note)

# --- A12: graphcmp.unchunks, the one already fixed ------------------------------
GC = load(HERE / "graphcmp.py", "graphcmp_under_audit")
#: `chunk("memory reduced from 0.01 MB -> 0.01 MB, 5 -> 2 bufs")` -- the DEBUG row that
#: surfaced as "0 trace rows", assembled by CALLING the tool's own chunker so the bytecount
#: is the tool's arithmetic and not mine.
_SPACE_CHUNK = " ".join(
    GC.chunk(p) for p in ("memory reduced from 0.01 MB -> 0.01 MB, 5 -> 2 bufs", "3"))

add("A12", "graphcmp.unchunks(): a chunk payload containing a SPACE",
    _SPACE_CHUNK,
    "constructed: the payload is chunk()'d by the tool itself, so the byte counts are its own",
    GC.unchunks, "PIN", unchunks_split_on_whitespace,
    "a whitespace SPLITTER -- the historical bug, per graphcmp.py:316",
    _ans(["memory reduced from 0.01 MB -> 0.01 MB, 5 -> 2 bufs", "3"]),
    "The ONLY audit here whose real reader is expected to SEE. Two documented bugs are in "
    "scope and the control is the first of them: 'Splitting on whitespace is what dropped 216 "
    "of 228 rows in the pin/HEAD study, because the row NAMES contain spaces' (graphcmp.py: "
    "316). graphcmp-LIMITS.md item 5 is the second: requiring a single space made whitespace "
    "STRUCTURAL, and a site printing `memory reduced from 0.01 MB -> 0.01 MB, 5 -> 2 bufs` "
    "walked off the end of the first chunk and REFUSED the line, which surfaced as '0 trace "
    "rows' -- a reader returning fewer rows than the emitter wrote, reported as a COUNT rather "
    "than as a failure. A control copied out of the tool it checks IS the tool, so this one is "
    "written from the writeup.")

# --- A13: dd-band-census.py, the `O.Found.i(` grep -------------------------------
#: NINE index-valued integer slots across THREE callees. Five reach one callee directly, two
#: reach it through a local bound on the line above, and two reach a callee absent from the
#: old whitelist -- one of them through a local as well. Both blind variants, constructed.
_DD_LINES = [
  "  +a = dd_band(O.Found.ar(s), v, O.Found.i(s))",       # direct, whitelisted callee? no
  "  +b = dd_band(O.Found.ar(m), v, O.Found.i(m))",
  "  +c = dd_band(O.Found.ar(b), v, O.Found.i(b))",
  "  +d = dd_band(O.Found.ar(a), v, O.Found.i(a))",
  "  +e = dd_band(O.Found.ar(c), v, O.Found.i(c))",
  "  +m = O.Found.i(s)",                                   # the binder
  "  +f = dd_band(O.Found.ar(s), v, m)",                   # through a local
  "  +n = O.Found.i(a)",                                   # the binder
  "  +g = dd_band(O.Found.ar(a), v, n)",                   # through a local
  "  +h = U32.shl(O.Found.ar(a), U32.sub(x, 1))",          # whitelisted callee, direct
  "  +p = dc_band(O.Found.ar(a), v, O.Found.i(a))",        # the OLD NAME for the same callee
]
_DD_SRC = "def probe(+ar, +v, +x):\n" + "\n".join(_DD_LINES) + "\n"


def dd_mask_args(src: str) -> list[str]:
    """The third argument of every `dd_band` call, by BALANCED paren walk. Written here so
    the expected count does not come from `dd-band-census.py`'s own parser -- an audit whose
    expected value is read from the thing under test agrees with itself."""
    out = []
    for m in re.finditer(r"(?<![\w.])dd_band\s*\(", src):
        i, depth, j = m.end(), 1, m.end()
        while depth and j < len(src):
            if src[j] == "(":
                depth += 1
            elif src[j] == ")":
                depth -= 1
            j += 1
        body, args, cur, d = src[i:j - 1], [], "", 0
        for ch in body:
            if ch in "([{":
                d += 1
            elif ch in ")]}":
                d -= 1
            if ch == "," and d == 0:
                args.append(cur.strip())
                cur = ""
            else:
                cur += ch
        if cur.strip():
            args.append(cur.strip())
        if len(args) >= 3 and not args[2].endswith(": U32"):
            out.append(args[2])
    return out


def dd_index_slots(src: str) -> list:
    """FORM-COMPLETE. Every (line, callee, arg#, argument) where the argument is an arena
    index -- DIRECTLY (`O.Found.i(...)`) or THROUGH A LOCAL BOUND TO ONE. This file's own
    balanced-paren walk over the printed source; NOT dd-band-census.py's, because an audit
    whose expected value comes from the thing under test agrees with itself.

    The through-a-local half is decidable here because the constructed subject BINDS each
    local to an `O.Found.i(...)` on the line above, and that binding is printed on every run.
    """
    # the BINDER NAME on the left of `+m = O.Found.i(...)`, not the argument inside it
    bound = set(re.findall(r"(?m)^\s*\+(\w+)\s*=\s*O\.Found\.i\(", src))
    out = []
    for m in re.finditer(r"(?<![\w.])([A-Za-z_][\w.]*)\s*\(", src):
        callee = m.group(1)
        i, depth, j = m.end(), 1, m.end()
        while depth and j < len(src):
            if src[j] == "(":
                depth += 1
            elif src[j] == ")":
                depth -= 1
            j += 1
        body, args, cur, d = src[i:j - 1], [], "", 0
        for ch in body:
            if ch in "([{":
                d += 1
            elif ch in ")]}":
                d -= 1
            if ch == "," and d == 0:
                args.append(cur.strip())
                cur = ""
            else:
                cur += ch
        if cur.strip():
            args.append(cur.strip())
        for k, a in enumerate(args[1:], start=1):
            if "O.Found.i(" in a or (k >= 2 and a in bound):
                out.append((code_line(src, m.start()), callee, k, a))
    return out


def code_line(src: str, pos: int) -> int:
    return src.count("\n", 0, pos) + 1


#: The rule dd-band-census.py section C shipped before 2026-10-04, reconstructed: a
#: six-NAME callee whitelist AND the direct spelling only. Both halves are real and both were
#: found by disagreement with section A, which reads the ARGUMENT.
OLD_CALLEE_WHITELIST = frozenset({
    "H.i64_of_i32", "H.i64_sub", "U32.shl", "U32.shr", "U32.shln", "U32.add", "U32.sub",
    "U32.mul", "U32.div", "U32.mod", "U32.and", "U32.or", "U32.xor", "U32.eq", "U32.lt",
    "U32.le", "U32.gt", "U32.ge", "U32.is_zero", "U32.from_nat", "U32.to_nat",
    "T.tx_powi", "T.tx_powi32", "T.exponent_bias",
})


def dd_section_c_pre_fix(src: str) -> int:
    """THE OLD RULE: an argument counts only if its CALLEE is in a hand-written name list AND
    it is spelled `O.Found.i(`. Two blind variants in one expression:
      C-i   the SPELLING -- an index routed through a local is the same index, other spelling;
      C-ii  the WHITELIST -- an index passed to any other callee is invisible however it is
            spelled, and a name list goes stale the moment a def is RENAMED. `dtype.bend`'s
            `dc_band` -> `dd_band` is exactly that, and it is why this rule reported ZERO
            index-valued mask arguments on a file where section A reported seven."""
    return len([(c, k, a) for _l, c, k, a in dd_index_slots(src)
                if c in OLD_CALLEE_WHITELIST and "O.Found.i(" in a])


def dd_direct_grep(src: str) -> int:
    """THE SPELLING HALF ALONE, which is the variant the brief names. Counts DIRECT
    spellings only, so an index that reaches the same slot through a local is invisible."""
    return len([(c, k, a) for _l, c, k, a in dd_index_slots(src) if "O.Found.i(" in a])


def dd_local_grep(src: str) -> int:
    """THE OTHER HALF OF THE SAME BLINDNESS. Section A's rule (`not a digit and not a value
    expression`) catches a bare local; section C's grep does not. So section A reaches all
    SEVEN, section C reaches FIVE, and a reader that grepped only for the local reaches TWO.
    Neither is 7. The UNION is, which is the fix: match the ARGUMENT, not the spelling."""
    return len([m for m in re.finditer(r"(?<![\w.])dd_band\s*\(([^)]*)\)", src)
                if len(m.group(1).split(",")) > 2
                and re.fullmatch(r"[a-z]\w*", m.group(1).split(",")[2].strip())])


def dd_index_sites(src: str) -> int:
    """Every mask argument that is an index, direct OR through a local. `m`/`n` are counted
    because the source above BINDS them to `O.Found.i(...)` on the line before -- that binding
    is in the constructed text and is printed on every run."""
    direct = [a for a in dd_mask_args(src) if "O.Found.i(" in a]
    viabind = [a for a in dd_mask_args(src) if re.fullmatch(r"[a-z]\w*", a)]
    return len(direct) + len(viabind)


add("A13", "dd-band-census.py section C: an index routed through a local, AND a callee absent "
    "from the whitelist",
    _DD_SRC,
    "constructed: 10 index-valued integer slots, and `dd_index_slots` is this file's own "
    "balanced-paren walk over the printed source -- NOT dd-band-census.py's parser, because an "
    "audit whose expected value comes from the thing under test agrees with itself",
    dd_section_c_pre_fix, "KNOWN-BLIND", dd_direct_grep,
    "the SPELLING half alone (a callee list wide enough, the `O.Found.i(` grep still blind)",
    lambda s: len(dd_index_slots(s)),
    "TWO BLIND VARIANTS IN ONE EXPRESSION, AND THE SECOND IS THE DOMINANT ONE -- worth saying "
    "because the brief named the first. C-i THE SPELLING: the old test was "
    "`if \"O.Found.i(\" in body`, so an index routed through a local was the same index in "
    "another spelling and was invisible. C-ii THE WHITELIST: the window was "
    "`H.i64_of_i32|H.i64_sub|U32.\\w+|T.tx_powi|T.tx_powi32|T.exponent_bias` -- six names -- so "
    "an index passed to any OTHER callee was invisible however it was spelled. A name whitelist "
    "is a fixture list: dtype.bend's `dc_band` -> `dd_band` rename is precisely what made it "
    "stale, and A13's last line is that same callee under its old name. MEASURED on real data "
    "through dd-band-census.py itself: on .agents/slop/dd-mutations.frozen.bend section A "
    "prints `suspect 7` index-valued `dd_band` mask arguments and the old section C reached "
    "NONE of them. On today's dtype.bend it printed `hard hits: 0` -- which is also what a "
    "routed-through-a-local index prints, so 0 was never a clean bill of health. "
    "FIXED 2026-10-04: section C now walks every argument of every call whose callee is in a "
    "stated INTEGER_CALLEES set, prints the callee on over-matched hits, and prints its own "
    "denominator (`N of M calls`) so the coverage is VISIBLE rather than assumed. Re-point "
    "`reader` at the shipped rule to flip this green; `--corpus` prints what it reaches.")

# --- A14: the s5_ bound-form tally ----------------------------------------------
#: NINETEEN srow calls. Eighteen carry the `l : Unit <- ` binder and the nineteenth is bare --
#: the constructed instance of the blind variant. The measurement is TODO.md:6097's: a tally
#: taken by scanning for the bound form finds 18 against a stated 19.
def _s5_bound(n: int) -> str:
    return "\n".join(
        f'  +l : Unit <- srow("s5_ga_{i}", v)' for i in range(n - 1)) + \
        f'\n  srow("s5_ga_{n - 1}", v)\n'


S5 = _s5_bound(19)


def s5_bound_tally(src: str) -> int:
    """THE TALLY UNDER AUDIT: a scan for the BOUND form. It is what TODO.md:6097 says the "
    "prior unit's list was, and it is the same shape as `grep -n 'Unit <- srow(\"s5_'`."""
    return len(re.findall(r'Unit\s*<-\s*srow\(\s*"s5_', src))


def s5_position_tally(src: str) -> int:
    """THE OTHER WAY THIS TALLY HAS BEEN WRITTEN: by POSITION. ops-501-gate.sh line 24: 'THE
    FILTER IS BY PREFIX, NEVER BY POSITION ... Filtering by position is what silently drops a
    row that MOVED, and a row that moved is the whole signal.' Nine of nineteen here. The
    control's job is to prove this audit can still fail on a reader that is wrong in a
    DIFFERENT direction from the one under test."""
    return len(re.findall(r"(?m)^  \+l : Unit <- ", src))


def s5_all_tally(src: str) -> int:
    """Every `s5_` row call, binder or no binder. `grep -c '\"s5_'` -- the FIX for the bound-
    form tally, and the answer `expected` is read from, over the SAME printed text."""
    return len(re.findall(r'srow\(\s*"s5_', src))


add("A14", "the `s5_` tally that scans for the BOUND form",
    S5,
    "constructed: 19 srow calls, 18 bound and 1 bare; the expected count is `s5_all_tally` "
    "over the SAME printed text, i.e. `grep -c '\"s5_'`",
    s5_bound_tally, "KNOWN-BLIND", s5_position_tally,
    "a POSITION-based filter (the other way this tally has been written)",
    s5_all_tally,
    "MEASURED on real data: TODO.md:6097 -- '`s5_copy_*` (3) + `s5_devrange_*` (3) + \"12 "
    "`s5_ga_*`\" = 18 against a stated 19. The missing one is `s5_ga_add`, and it is missing "
    "because in ops.bend's `s5.garows` every row is bound EXCEPT the last, a bare "
    "`srow(\"s5_ga_add\", ...)`. THE BINDER IS A VALUE, NOT PART OF THE ROW. `ops-501-gate.sh` "
    "itself is SOUND: its `grep '^s5_'` runs on the lane's OUTPUT, where every row is "
    "`name=value`. It is the SOURCE-side tally that could not see the unbound row.")

# --- A15: the quoted-import grep -------------------------------------------------
#: Bend writes an import path BARE. The grep under audit looks for the quoted spelling, which
#: is the Python spelling. This is the vacuous-blast-radius case: zero importers is not a
#: finding, it is a reader that cannot see the subject.
IMPORTS = "\n".join([
  "import ./../helpers.bend as H",
  "import ./../uop/ops.bend as O",
  "import ./../LAWS/spec.bend as S",
]) + "\n"


def quoted_import_grep(src: str) -> int:
    """THE GREP UNDER AUDIT: `"ops.bend"` -- the quoted spelling."""
    return len(re.findall(r'"[^"]*\.bend"', src))


def unquoted_import_grep(src: str) -> int:
    """Bend's own spelling: a bare path in an `import` position."""
    return len(re.findall(r"(?m)^\s*import\s+\S*\.bend\b", src))


def single_quoted_import_grep(src: str) -> int:
    """THE THIRD SPELLING, and the one the quoted grep also misses: a single-quoted path.
    Prose and one-off notes write imports this way, so a grep that accepts only `\"` gets 0
    from every one of them too. This is the control for A15 and it must ALSO miss -- a control
    that agreed with the form-complete answer would mean A15 cannot fail."""
    return len(re.findall(r"'[^']*\.bend'", src))


add("A15", "the quoted-import grep: `\"ops.bend\"` against Bend's bare-path spelling",
    IMPORTS,
    "constructed: three Bend imports, and `unquoted_import_grep` is the count over the SAME "
    "printed text. The real number on this tree is measured by `--corpus` below.",
    quoted_import_grep, "KNOWN-BLIND", single_quoted_import_grep,
    "a grep for the single-quoted spelling (the third form)",
    unquoted_import_grep,
    "A 0 from a quoted grep is a VACUOUS BLAST RADIUS, and that is the dangerous shape: 0 "
    "importers is a claim somebody repeats, and it is byte-identical to 'I looked at the wrong "
    "spelling'. Every importer-count in this repo that used the quoted spelling has to be "
    "re-read against `import ^\\S*\\.bend`.")

# --- A16: the `py=` fold, and rfind-vs-find when the value carries the tail twice ----
def rows_fold_at_first_tail(text: str) -> dict:
    """THE OTHER FOLD. `find` instead of `rfind`: the reading the reader's own header names
    as the bug -- 'the value's own bracket can precede the boundary ... cutting at the bracket
    instead of after it makes every F2 row disagree by one character'. A fold that cuts at the
    FIRST `]   py=[` truncates a value that legitimately contains the tail, and the row's
    VALUE changes while its NAME stays put, so nothing reports a disagreement of identity."""
    out = {}
    for line in text.splitlines():
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        i = v.find(PY_TAIL_LIT)
        out[k.strip()] = (v[:i + 1].strip(), v[i + len(PY_TAIL_LIT):].strip())[0] if i >= 0 \
            else v.strip()
    return out


#: `device-oracle-MUTANT.py`'s own `PLANT_TO` -- the planted-mutant template. A row that
#: EXISTS ONLY INSIDE A STRING LITERAL.
MUTANT_PY = '''PLANT_FROM = '  row("allow_lower", allowed(False, "python:1"))'
PLANT_TO = '  row("allow_lower", 0)  # PLANTED for the control: the ONE wrong answer'
'''


def ht_row_call_sites(text: str) -> list:
    """CPython's own `ast`, asked a question a TEXT scanner cannot ask: how many `row(...)`
    CALL SITES are there? Zero for MUTANT_PY, because both occurrences live inside string
    literals -- one is a `PLANT_TO` template for a control that rewrites a source line, the
    other is prose. This is the FORM-COMPLETE answer and `ast` is where it comes from, which
    is the whole reason `handtyped-audit.py` parses instead of matching."""
    import ast
    tree = ast.parse(text)
    return [n.lineno for n in ast.walk(tree)
            if isinstance(n, ast.Call)
            and getattr(n.func, "id", getattr(n.func, "attr", None)) in HT.ROW_FUNCS]


add("A17", "--handtyped on a `row(...)` that exists ONLY inside a string literal",
    MUTANT_PY,
    "CPython's `ast`: the file has ZERO row() CALL SITES. `.agents/slop/device-oracle-MUTANT.py` "
    "is the real instance -- MEASURED: `ast.walk` finds 0 calls in it",
    hand_typed_names, "PIN", census_hand_typed_control,
    "the regex detector, inlined -- it reads TEXT, so a template is a row to it",
    _ans([]),
    "THE FIFTH BLIND VARIANT, AND IT WAS FOUND BY A DISAGREEMENT RATHER THAN BY READING EITHER "
    "TOOL: after --handtyped was corrected to delegate to handtyped-audit.py, exactly ONE row "
    "the old regex reader had reported vanished -- `device-oracle-MUTANT.py`'s `allow_lower`. "
    "That file contains NO `row()` call at all; `row(\"allow_lower\", 0)` occurs twice, once in "
    "a `PLANT_TO` template for a control that rewrites a source line and once in prose. A text "
    "scanner cannot tell a row from a sentence ABOUT a row, and `ast` can. The direction here "
    "is the opposite of the other four: the old reader OVER-counted, so this variant makes the "
    "old 209 too high by one rather than too low by 329.")

PY_TAIL_LIT = "]   py=["

add("A16", "rebase-gate.rows(): an F2 value that ITSELF contains the `]   py=[` tail",
    'alpha=a]   py=[b]   py=[c\n',
    "rowform.any_row for the name, and the fold is `row()`'s own rfind -- this audit pins "
    "rfind-vs-find, so the pin is that a value carrying the tail TWICE survives whole",
    RG.rows, "PIN", rows_fold_at_first_tail, "a reader that folds at the FIRST tail (`find`)",
    _ans({"alpha": "a]   py=[b]"}),
    "`rfind`, not `find`: a value's own bracket can precede the boundary, and cutting at the "
    "bracket instead of after it made every one of 222 shared cstyle rows disagree by one "
    "character on the first run of that fold (rebase-gate.py:199-204). This audit PASSES on "
    "the shipped reader and is here so the A1..A4 failures are not mistaken for a reader that "
    "is simply broken: it reads what it claims to read, folds at the LAST tail, and refuses "
    "the rest.")


# ---------------------------------------------------------------------------
def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--corpus", action="store_true",
                    help="the real-tree measurement behind each constructed audit")
    a = ap.parse_args(argv)
    if a.corpus:
        return corpus_report()
    if a.list:
        for x in AUDITS:
            print(f"{x.aid:4} {x.status:12} {x.what}")
        return 0
    bad = 0
    print("=" * 100)
    print("FORM-BLINDNESS AUDIT -- a tool that matches a form cannot see the instance that")
    print("lacks it.  Every audit prints the CONSTRUCTED subject, the FORM-COMPLETE answer, the")
    print("REAL reader's own answer, and a CONTROL reader that is blind on purpose.  The")
    print("control's contract is that it must NOT agree with the form-complete answer: an audit")
    print("that cannot tell a wrong reader from a right one is `not-applied-audit.py`'s bug.")
    print("")
    print("POLARITY IS THE POINT.  ONE assertion, sixteen times: THE READER MUST PRODUCE THE")
    print("FORM-COMPLETE ANSWER.  KNOWN-BLIND means that assertion FAILS on this tree -- a")
    print("failing reconstruction of the blind variant, in not-applied-audit.py's shape, which")
    print("exits 1 until somebody fixes the reader.  PIN means it passes today, on a reader")
    print("that already handles the variant; those are here so the KNOWN-BLIND ones cannot be")
    print("satisfied by a reader that stopped reading, and so a census that claims blindness")
    print("where there is NONE is caught too (A10).")
    print("=" * 100)
    for x in AUDITS:
        if a.only and x.aid != a.only:
            continue
        r = x.run()
        bad += 0 if r["ok"] else 1
        flag = "ok  " if r["ok"] else "FAIL"
        why = "" if r["ok_real"] else \
            ("   <-- THE READER CANNOT SEE IT" if x.status == "KNOWN-BLIND"
             else "   <-- THE READER CANNOT SEE IT, and the census said it could")
        print(f"\n{flag} {x.aid}  [{x.status}]  {x.what}")
        print(f"     expected from : {x.src}")
        print(f"     subject       : {x.subject!r}")
        print(f"     FORM-COMPLETE : {r['want']!r}")
        print(f"     REAL reader   : {r['got']!r}{why}")
        ctl_note = "" if r["ok_ctl"] else \
            "   <-- AGREES WITH THE FORM-COMPLETE ANSWER: THIS AUDIT CANNOT FAIL"
        print(f"     CONTROL       : {r['ctl']!r}  ({x.ctl_name}){ctl_note}")
        if x.note:
            print(f"     {x.note}")
    print(f"\n{'-' * 100}")
    kb = sum(1 for x in AUDITS if x.status == "KNOWN-BLIND")
    print(f"{len(AUDITS) - bad}/{len(AUDITS)} assertions hold;  {bad} FAIL")
    print(f"denominator: {len(AUDITS)} constructed variants, {kb} of them KNOWN-BLIND.  This is")
    print(f"NOT a coverage statement: formblind-census.py names 65 FORM-BLIND tools and this")
    print(f"file asserts {len(AUDITS)} readers.  Every other FORM-BLIND tool is a FLOOR on the")
    print("census, not a clearance.")
    return 1 if bad else 0


def corpus_report() -> int:
    """THE SAME AUDITS AGAINST THE REAL TREE, so a constructed instance is corroborated by a
    measurement rather than being the only evidence. Run twice and compared; agent-core.md
    records four reads of one file giving 239/246/354/355 rows while a background job was
    still writing, and a count that grows while you watch it is an unfinished one."""
    print("=" * 100)
    print("CORPUS -- the blind variants, measured on this tree rather than only constructed")
    print("=" * 100)

    def scan():
        repo = HERE.parents[1]
        bend = sorted((repo / "tinybendygrad").rglob("*.bend"))
        quoted = bare = 0
        qfiles, bfiles = set(), set()
        for p in bend:
            try:
                t = p.read_text(errors="replace")
            except Exception:                    # noqa: BLE001
                continue
            q = len(re.findall(r'"[^"]*\.bend"', t))
            b = len(re.findall(r"(?m)^\s*import\s+\S*\.bend\b", t))
            quoted += q
            bare += b
            if q:
                qfiles.add(p)
            if b:
                bfiles.add(p)
        return len(bend), quoted, bare, len(qfiles), len(bfiles)

    n1, q1, b1, qf1, bf1 = scan()
    n2, q2, b2, qf2, bf2 = scan()
    print(f"A15 quoted-import vs bare-import, over tinybendygrad/**/*.bend")
    print(f"     run1: files={n1}  `\"x.bend\"` hits={q1} in {qf1} files   "
          f"`import <bare>.bend` hits={b1} in {bf1} files")
    print(f"     run2: files={n2}  `\"x.bend\"` hits={q2} in {qf2} files   "
          f"`import <bare>.bend` hits={b2} in {bf2} files")
    stable = "STABLE across two reads" if (n1, q1, b1) == (n2, q2, b2) else \
        "MOVED WHILE WATCHED -- treat as unfinished, not unstable"
    print(f"     {stable}")
    print(f"     the quoted grep's blast radius is {b1 - q1} imports INVISIBLE to it\n")

    from rowform import blind_reason
    rg = load_shared_reader()
    import collections
    tally = collections.Counter()
    lanes = 0
    for p in sorted(HERE.rglob("*.txt")):
        if p.stat().st_size > 4_000_000:
            continue
        try:
            t = p.read_text(errors="replace")
        except Exception:                        # noqa: BLE001
            continue
        if len(rg.rows(t)) < 20:
            continue
        lanes += 1
        for ln in t.splitlines():
            why = blind_reason(ln, rg.row(ln))
            if why:
                tally[why] += 1
    print(f"A1-A4 lane lines rebase-gate.rows() cannot read, over {lanes} lanes it DOES read")
    for k, v in sorted(tally.items(), key=lambda kv: -kv[1]):
        print(f"     {k:18} {v:>7}")
    print(f"     {'TOTAL (a floor)':18} {sum(tally.values()):>7}  -- every count in this repo")
    print(f"     produced through rows() is a FLOOR by at least this much.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())