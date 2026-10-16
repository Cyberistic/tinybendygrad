#!/usr/bin/env python3
r"""docnum-census -- CENSUS LOAD-BEARING NUMBERS AND CLAIMS IN SHIPPED PROSE.

The four instances that dispatched this census, all one day, all one shape:

  1. `decomp`'s FOOTER named the wrong blocker and its own rows refuted it.
  2. `uop/spec.bend:1488` justified a P6 wall with `Device.tag`, WHICH DOES NOT EXIST, and a
     gate quoted the citation forward.
  3. `nn/optim.bend`'s claim that a fixture "NEEDS `Device.tag`" was PROVED FALSE.
  4. `gates/README.md` justified a whole section on "THE NUMERATOR OF 'A GATE THAT ANYTHING
     RUNS' WAS 0 OF 77" -- and `checks/gatesweep.py`, 358 lines, ALREADY EXISTED.

So the class is not "wrong number". It is: **a number written where a measurement could be
taken, in prose that outlives the measurement.** The only question worth automating:

    COULD IT BE COMPUTED INSTEAD OF WRITTEN?
    IF A GATE PRINTS IT, THE PROSE SHOULD POINT AT THE GATE, NOT AT THE NUMBER.

WHAT IS A POPULATION HERE, AND WHY IT IS A WALK
------------------------------------------------
The population is NOT a list of documents. It is:

    WALK = os.walk over the repo, keeping `.md`, `.bend` and `.py`, pruning
           {'.git','.jj','.venv','references','__pycache__','.ruff_cache','node_modules',
            '.pytest_cache'} and the prefix `.agents/slop/`.

and VENDORED-UPSTREAM is DERIVED, not spelled, so this file holds no home list:

    VENDORED(p)  iff  p is in `git ls-tree -r <PIN>` AND the pin's blob sha equals the
                     blob sha of the file on disk.

`PIN` is READ OUT OF THE TREE'S OWN RECORD, `.agents/UPSTREAM-PIN.md` ("The pin is
`6c3d401cf324`"), loaded by path -- a generator's declaration, not a transcription. The
EQUALITY clause is not decoration: this project MODIFIES vendored files (`ad117c928`
re-vendored 16 files under `tinygrad/`; `AGENTS.md` is upstream's file and 100% ours), so
plain `ls-tree` membership would call every edited upstream blob "vendored" and delete the
very prose under audit. Both ledgers are printed so the rule can be seen from both sides.

A POPULATION MUST BE DERIVED, AND TWO DERIVATIONS WERE TRIED AND ONE WAS WRONG
-----------------------------------------------------------------------------
`git log -E --grep='\(#[0-9]+\)'` -- "a commit whose subject carries an upstream PR number
is an upstream commit" -- is NOT a discriminator, and the tree manufactures the counterexample
without trying. `gates/onnx_census-gate.py` reads as upstream by that rule, and its only
adding commit is `0b1edd858`, THIS PROJECT'S, whose message quotes `(#18575)` while
discussing a re-vendor. `--grep` reads the WHOLE MESSAGE, so a commit that CITES an upstream
PR is indistinguishable from one that IS one. It also misfiled 194 files under `test/` and
71 under `tinygrad/`. Recorded here because the pin has a recorded failure and this rule
does not; a reader must not reach for it.

EVERY REJECTION RULE TALLIES ITSELF, AND THE TOKEN IS EVERY NUMBER
-------------------------------------------------------------------
A prior unit deleted 666 TRUE ROWS because `[^/]*` matched empty. The moral, taken the other
way, is this file's rule: **a truncated token writes a FALSE ROW; a wrong exclusion writes NO
ROW, and no row does not argue back.** So:

  * the token is EVERY maximal number span, not every number-with-a-unit. The unit is
    CONTEXT, captured for the row and never part of the match;
  * a rule reads the LINE and the MATCH, never the token alone -- a token is the number, so
    it cannot see `2026-10-06`'s own suffix or `f32`'s own prefix;
  * `--rejects` prints a row for EVERY rule including those that fired zero times;
  * `--prove` asserts `len(ROWS) + sum(REJECTED) == TOKENS` and prints `LEAK` if not, and
    `DEAD` (5) on a zero denominator -- because "0 disagreements over 0 comparisons" is not
    agreement, it is an instrument that measured nothing.

The token-is-every-number change is also what made two rules REACHABLE: `version` and
`file-line` had been written against a unit-bearing match, so `3.12` and `gatekit.py:436`
were never produced and the rules that would have removed them could never fire. A rule that
cannot fire is decoration.

THE DISPOSITIONS THIS FILE PRINTS (the judgement is the report's, the arithmetic is here's)
----------------------------------------------------------------------------------------------
    STALE-BUT-DATED   a historical reading carrying its own date -- NOT A DEFECT. `AGENTS.md`:
                      "QUOTE THIS NUMBER WITH A TIMESTAMP OR NOT AT ALL."
    ATTRIBUTED        a number attributed to a MEASURED/RECORDED marker, undated on its line
    UNDATED           a number presenting itself as current with nothing behind it

    CURRENT / STALE-UNDATED / LOAD-BEARING-AND-WRONG / NOT-A-NUMBER are the report's five, and
    they need the MEASUREMENT, which this file does not have. Where no shipped instrument
    re-prints a number, the truthful token is `NO-INSTRUMENT`, never a guess: a wrong reason
    is worse than no reason.

USAGE
    .venv/bin/python gates/docnum-census.py --plan     # the population and both ledgers
    .venv/bin/python gates/docnum-census.py --rows     # the byte-reproducible table
    .venv/bin/python gates/docnum-census.py --rejects  # every rule, with its own count
    .venv/bin/python gates/docnum-census.py --prove    # the token identity; MUST be able to fail
    .venv/bin/python gates/docnum-census.py --plant    # a REAL temp repo; MUST be able to fail
"""

import argparse
import hashlib
import io
import os
import re
import subprocess
import sys
import tempfile
import tokenize

PROSE_EXT = (".md", ".bend", ".py")

# Stated here and TALLIED, because a wrong prune is an exclusion with no row.
PRUNE_DIRS = (".git", ".jj", ".venv", "references", "__pycache__", ".ruff_cache",
              "node_modules", ".pytest_cache")
PRUNE_PREFIXES = (".agents/slop",)

PIN_RECORD = ".agents/UPSTREAM-PIN.md"

MARKERS = ("MEASURED", "MEASURE", "RECORDED", "READ", "OBSERVED")
DATE = r"(?:19|20)\d{2}-\d{2}(?:-\d{2})?"
ATTRIBUTED = re.compile(r"\b(" + "|".join(MARKERS) + r")\b", re.I)

NUMBER = r"\d[\d,]*(?:\.\d+)?"
TOKEN = re.compile(NUMBER)
# Context AFTER the number, captured but NEVER merged into the token. `-NN` is deliberately
# absent: that is what truncated `2026-10-06` into `2026-10`, and a range then reads as two
# tokens rather than one lie.
AFTER = re.compile(r"\s*(\S{0,20})")

# --------------------------------------------------------------------------------------
# THE WALK, AND THE PIN
# --------------------------------------------------------------------------------------

def walk(root):
    """A DIRECTORY WALK. `os.walk` yields sets, so `dirs[:]` is sorted: the population is
    a set and the table is a table, and an unsorted walk is how a table stops reproducing."""
    files, pruned = [], {}
    for here, dirs, names in os.walk(root):
        rel = "" if here == root else os.path.relpath(here, root)
        rel = "" if rel == "." else rel
        keep = []
        for d in sorted(dirs):
            child = os.path.join(rel, d) if rel else d
            # THE PREFIX RULE MUST BE FALSE WHEN NOTHING MATCHED. Written as
            # `next((p for p in PRE if match(p)), "")` and concatenated, the empty default
            # yields the truthy string "prune-prefix:", so EVERY directory is pruned and the
            # walk returns 4 files out of 1402 -- while still printing 18 "pruned" rows, so
            # the ledger LOOKED busy and the population was almost empty. That is the exact
            # shape the tree records as "a wrong exclusion writes no row": here it wrote 18
            # rows that were all lies.
            hit = next((p for p in PRUNE_PREFIXES
                        if child == p or child.startswith(p + "/")), None)
            if d in PRUNE_DIRS:
                pruned["prune-dir:" + d] = pruned.get("prune-dir:" + d, 0) + 1
            elif hit:
                pruned["prune-prefix:" + hit] = pruned.get("prune-prefix:" + hit, 0) + 1
            else:
                keep.append(d)
        dirs[:] = keep
        for name in sorted(names):
            if name.endswith(PROSE_EXT):
                files.append(os.path.join(rel, name) if rel else name)
    return files, pruned


def read_pin(root):
    """THE PIN IS READ OUT OF THE TREE'S OWN RECORD, never transcribed here."""
    try:
        text = open(os.path.join(root, PIN_RECORD), encoding="utf-8").read()
    except OSError as exc:
        raise SystemExit("REFUSED: cannot read %s: %s" % (PIN_RECORD, exc))
    m = re.search(r"[Tt]he pin is \*\*`([0-9a-f]{7,40})`\*\*", text) or \
        re.search(r"\*\*OUR PIN\*\*.*?`([0-9a-f]{7,40})`", text)
    if not m:
        raise SystemExit("REFUSED: %s names no pin in either recorded form" % PIN_RECORD)
    return m.group(1)


def pin_trees(root, pin):
    """path -> blob sha from ONE `git ls-tree -r`, so the map cannot disagree with itself."""
    proc = subprocess.run(["git", "ls-tree", "-r", pin], cwd=root,
                          capture_output=True, text=True, check=True)
    tree = {}
    for line in proc.stdout.splitlines():
        meta, _, path = line.partition("\t")
        bits = meta.split()
        if len(bits) >= 3:
            tree[path] = bits[2]
    return tree


def blob_sha_of(path):
    """git's OBJECT id, not the content's sha1.

    `git ls-tree` prints `sha1("blob " + len + "\\0" + content)`. Hashing the raw bytes
    instead -- the obvious one-liner -- yields an id that never equals a pin blob, so every
    vendored file reads as edited and the population silently becomes the whole tree. Not a
    hypothesis: that WAS this function, and the ledger read 894 of 1401 `edited-vendor`.
    """
    data = open(path, "rb").read()
    h = hashlib.sha1()
    h.update(b"blob %d\0" % len(data))
    h.update(data)
    return h.hexdigest()

# --------------------------------------------------------------------------------------
# THE FIVE REJECTION RULES.  `(name, predicate(line, m, dates), what it removed)`
# --------------------------------------------------------------------------------------

def _is_date(line, m, dates):
    """`2026-10-06`, its `10-06` and `06` fragments, and `14:16`.

    TWO PASSES OVER THE LINE, and both are necessary. The token is the number span, so for
    `2026-10-06` the token is `2026` and the `-10-06` is in the TAIL -- a `fullmatch` on the
    token can never see it, which is why the first version of this rule fired ZERO times on
    the one string it was written for. And the line also holds `10` and `06` as separate
    tokens, which no token-local test can pair with the year. So `dates` is the set of
    CHARACTER OFFSETS covered by a date span, computed once per line.
    """
    return m.start() in dates


def _is_file_line(line, m, dates):
    """`gatekit.py:436`, `spec.bend:1488-1490` -- a CITE, not a count.

    `AGENTS.md` records 189 `file:line` citations drifted across 65+ files as ANOTHER unit's
    population. This rule does not census them; it removes them from MINE so the two censuses
    cannot double-count, and it COUNTS what it removed so the subtraction is auditable.
    """
    before, tail = line[:m.start()], line[m.end():]
    if re.search(r"[\w/.\-]\.(?:py|bend|md|sh|rows|out|err|json|tsv):\s*\d*$", before):
        return True
    # the RIGHT half of a range whose left half is a line number
    if re.search(r"[\w/.\-]\.(?:py|bend|md|sh|rows|out|err|json|tsv):\s*\d+\s*[-–]\s*$", before):
        return True
    return bool(re.match(r"^\s*[-–]\s*\d", tail)) and bool(
        re.search(r":\s*\d+\s*[-–]\s*$", before))


def _is_hex(line, m, dates):
    """`e69de29b`, `0x4bb4`, and the DIGITS INSIDE one -- `60` in `` **`60b4c4bbb` ``.

    The digits inside a blob are the reason this rule takes the LINE. A 40-char sha is three
    numbers as far as `TOKEN` is concerned, and without the enclosing-word test they are
    three FALSE ROWS asserting that this port has 60 and 755 of something.
    """
    before, tail = line[:m.start()], line[m.end():]
    if re.search(r"0[xb][0-9a-fA-F]*$", before):
        return True
    # the maximal alphanumeric run CONTAINING this token
    s = m.start()
    while s > 0 and re.match(r"[0-9A-Za-z]", line[s - 1]):
        s -= 1
    e = m.end()
    while e < len(line) and re.match(r"[0-9A-Za-z]", line[e]):
        e += 1
    run = line[s:e]
    if len(run) < 7 or not re.fullmatch(r"[0-9a-f]+", run):
        return False
    if re.match(r"\s*(?:files?|dirs?|rows?|lines?|gates?|graphs?|commits?|paths?|of\b|/)", tail):
        return False
    return True


def _is_version(line, m, dates):
    """`3.12`, `2.0.34`, `0.14.0`, and a bare `18781` after the word `version`."""
    tok, before, tail = m.group(0), line[:m.start()], line[m.end():]
    # `3.12` is ONE token -- `NUMBER` takes the fractional part -- so the dot test must read
    # the TOKEN, not the tail. The first version tested `^\.\d+` against the tail, which is
    # unreachable for the very string the rule was written for, and the plant caught it.
    if "." in tok:
        return True
    if re.match(r"^\.\d+", tail):
        return True
    if re.match(r"^\s*(?:of\b|/|[-–]\s*\d|files?|dirs?|rows?|lines?|gates?|graphs?"
                r"|commits?|paths?|MB|GB|KB|B\b|s\b|ms\b|min\b|sec\b|%)", tail):
        return False
    return bool(re.search(r"\b(?:version|python|rungeno)\s*$", before, re.I))


def _is_identifier(line, m, dates):
    """`f32`, `i64`, `utf8`, `shl2`, `n256`, `bf16`, `p6`, `c3` -- a NAME that has digits.

    The whole rule is ADJACENCY: the token is the number span, so `f32` arrives as token `32`
    with `... , f` to its left. Requiring a digit INSIDE the left word (the first version)
    therefore never fires -- the digit is the token. What separates a name from a count is
    that there is no space: `spec 1` is a count, `p6` is a wall class, and only the character
    immediately before the digits tells them apart. Rejecting the number and keeping the word
    loses the claim, so the rule COUNTS, loudly, rather than filtering in silence.
    """
    before, tail = line[:m.start()], line[m.end():]
    if not re.search(r"[A-Za-z_]$", before):
        return False
    if re.match(r"^\s*(?:of\b|/|[-–]\s*\d|files?|dirs?|rows?|lines?|gates?|graphs?"
                r"|commits?|paths?|MB|GB|KB|B\b|s\b|ms\b|min\b|sec\b|%|\u00d7)", tail, re.I):
        return False
    return True


def _is_ordinal(line, m, dates):
    """`0)`, `1)`, `2)`, `(4` -- an ENUMERATION in a clause list, not a measurement.

    A tree that writes its arguments as numbered prose has tens of thousands of these, and
    they are indistinguishable from counts by value (`0` is both "zero disagreements" and
    "the first arm"). What separates them is the CLOSER: `1)` closes a clause, `47 paths`
    does not. The rule is deliberately narrow -- `103,` is followed by a comma and is KEPT,
    which the plant asserts, because "followed by punctuation" would have eaten every number
    in a comma-separated list, and a census that eats them writes no row to argue back.
    """
    tok, before, tail = m.group(0), line[:m.start()], line[m.end():]
    if len(tok.replace(",", "")) > 2:
        return False
    if before and not re.search(r"(?:^|\s|\(|`|\*|-)$", before):
        return False
    return bool(re.match(r"^\s*[)\]}:;](?:\s|$|,|$)", tail))


REJECT_RULES = (
    ("date", _is_date, "an ISO date or a fragment of one"),
    ("file-line", _is_file_line, "a file:line CITATION -- another unit's population"),
    ("hex", _is_hex, "a hash, or digits inside one"),
    ("version", _is_version, "a version or a dotted literal"),
    ("identifier", _is_identifier, "a NAME that happens to contain digits"),
    ("ordinal", _is_ordinal, "an enumeration in a clause list"),
)

# POPULATION rules remove a FILE, not a token, and are tallied in their own ledger so the
# two identities cannot be mistaken for one.
POPULATION_RULES = (
    ("vendored-at-pin", "byte-identical to its blob in the recorded pin: not our prose"),
    ("edited-vendor", "in the pin but our bytes differ: our edit of upstream"),
)

DATE_SPAN = re.compile(DATE + r"(?![\d-])|\d{2}:\d{2}(?![\d:])")


def date_offsets(line):
    """Character offsets covered by a date/time span. One pass; `m.start() in dates`."""
    return {i for m in DATE_SPAN.finditer(line) for i in range(m.start(), m.end())}


def prose_spans(path, text):
    """-> [(lineno, prose_text)], the PROSE of a file, and a tally of what was left out.

    A NUMBER IN CODE IS NOT A CLAIM IN PROSE. The first version tokenised whole files, and
    `536` prose files yielded **174,181** claim rows -- of which the overwhelming majority
    were `0x4bb4`, `1e9` and loop bounds in `.py`. A census that cannot tell code from prose
    has no denominator at all: every number is a row and no row is a claim.

    Three carriers, three rules, each stated because it is a choice and not a fact:
      `.md`   every line -- markdown is prose by definition of the format.
      `.bend` a line whose first non-blank character is `#`, or a `#` after code.  The
              trailing form is included because this tree writes its walls as trailing
              comments and a trailing wall is the exact kind of prose under audit.
      `.py`   `tokenize`'s COMMENT and STRING tokens. STRING is over-inclusive -- it includes
              data, not only docstrings -- and it is over-inclusive ON PURPOSE, because
              narrowing to docstrings needs a parser judgement and a wrong narrowing writes
              no row. The over-inclusion is COUNTED so it is visible.

    Returns spans whose line numbers are the FILE's, so a row points at the citation.
    """
    ext = os.path.splitext(path)[1]
    if ext == ".md":
        return [(i, ln) for i, ln in enumerate(text.splitlines(), 1)], 0
    if ext == ".bend":
        out = []
        for i, ln in enumerate(text.splitlines(), 1):
            hash_at = ln.find("#")
            if hash_at >= 0:
                out.append((i, ln[hash_at:]))
        return out, 0
    out, dropped = [], 0
    try:
        for tok in tokenize.generate_tokens(io.StringIO(text).readline):
            if tok.type in (tokenize.COMMENT, tokenize.STRING):
                out.append((tok.start[0], tok.string))
            else:
                dropped += tok.end[0] - tok.start[0] + 1
        return out, dropped
    except (tokenize.TokenError, IndentationError, SyntaxError):
        # A file `tokenize` cannot read is a REAL loss of population, so it is COUNTED and
        # the raw text is used instead -- never silently skipped.
        return ([(i, ln) for i, ln in enumerate(text.splitlines(), 1)], 0), 1


def classify_token(m, line, dates):
    for name, pred, _why in REJECT_RULES:
        try:
            hit = pred(line, m, dates)
        except Exception:
            hit = False
        if hit:
            return "REJECT:" + name
    return "STALE-BUT-DATED" if ATTRIBUTED.search(line) else "UNDATED"


def census(root):
    files, pruned = walk(root)
    pin = read_pin(root)
    tree = pin_trees(root, pin)
    rows = []
    # BOTH ledgers are PRE-SEEDED: a rule that fires zero times still prints a row. A rule
    # nobody can see cannot be wrong, and cannot be shown to be right either.
    rejects = dict.fromkeys([r for r, _p, _w in REJECT_RULES] +
                            [r for r, _w in POPULATION_RULES], 0)
    n_tokens = n_unread = n_code = n_untokenizable = 0
    for path in files:
        inpin = tree.get(path)
        if inpin is not None and inpin == blob_sha_of(os.path.join(root, path)):
            rejects["vendored-at-pin"] += 1
            continue
        if inpin is not None:
            rejects["edited-vendor"] += 1
        try:
            text = open(os.path.join(root, path), encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            n_unread += 1
            continue
        spans, code_lines = prose_spans(path, text)
        n_code += code_lines
        if isinstance(spans, tuple):          # `(spans, 1)`: tokenize failed, counted above
            spans, n_untokenizable = spans
            n_untokenizable += 1
        for lineno, line in spans:
            dates = date_offsets(line)
            for m in TOKEN.finditer(line):
                n_tokens += 1
                disp = classify_token(m, line, dates)
                if disp.startswith("REJECT:"):
                    rejects[disp[7:]] += 1
                    continue
                after = AFTER.match(line[m.end():])
                rows.append((path, lineno, m.group(0),
                             (after.group(1).strip()[:24] if after else ""), disp))
    rows.sort(key=lambda r: (r[0], r[1], r[2]))
    return {"pin": pin, "files_walked": len(files), "prune_tally": pruned,
            "ours": len(files) - rejects["vendored-at-pin"], "rows": rows,
            "rejects": rejects, "pin_paths": len(tree), "tokens": n_tokens,
            "unread": n_unread, "code_lines": n_code, "untokenizable": n_untokenizable}

# --------------------------------------------------------------------------------------
# MODES
# --------------------------------------------------------------------------------------

def emit_plan(res, out):
    w = out.write
    w("PIN                   : %s  (read out of %s)\n" % (res["pin"], PIN_RECORD))
    w("PIN PATHS             : %d\n" % res["pin_paths"])
    w("WALK                  : %d prose files (.md/.bend/.py)\n" % res["files_walked"])
    for k in sorted(res["prune_tally"]):
        w("  PRUNED %5d  %s\n" % (res["prune_tally"][k], k))
    w("VENDORED (byte==pin)  : %d\n" % res["rejects"]["vendored-at-pin"])
    w("EDITED VENDOR (ours)  : %d\n" % res["rejects"]["edited-vendor"])
    w("OURS (the population) : %d\n" % res["ours"])
    w("UNREADABLE (tallied)  : %d\n" % res["unread"])
    w("UNTOKENIZABLE .py     : %d  (fell back to raw text, and is counted)\n" % res["untokenizable"])
    w("CODE LINES EXCLUDED   : %d  (.py only; .bend and .md carry no code)\n" % res["code_lines"])
    w("NUMBER TOKENS IN PROSE: %d\n" % res["tokens"])
    w("CLAIM ROWS            : %d\n" % len(res["rows"]))


def emit_rows(res, out):
    """THE TABLE. Sorted, tab-separated, content-only: no clock, no pid, no absolute path,
    so two runs in two SEPARATE PROCESSES hash the same bytes."""
    for path, lineno, tok, ctx, disp in res["rows"]:
        out.write("%s\t%d\t%s\t%s\t%s\n" % (path, lineno, tok, ctx, disp))


def emit_rejects(res, out):
    out.write("LEDGER\tRULE\tCOUNT\tWHAT IT REMOVED\n")
    for rule, _p, why in REJECT_RULES:
        out.write("token\t%s\t%d\t%s\n" % (rule, res["rejects"][rule], why))
    for rule, why in POPULATION_RULES:
        out.write("file\t%s\t%d\t%s\n" % (rule, res["rejects"][rule], why))


def emit_prove(res, out):
    """THE IDENTITY: rows + every token rejection == tokens read. It must be able to FAIL,
    and it fails two DIFFERENTLY, because they are different defects."""
    rejected = sum(res["rejects"][r] for r, _p, _w in REJECT_RULES)
    total = len(res["rows"]) + rejected
    out.write("TOKENS %d\n" % res["tokens"])
    out.write("ROWS %d\n" % len(res["rows"]))
    for rule, _p, _w in REJECT_RULES:
        out.write("REJECTS %s %d\n" % (rule, res["rejects"][rule]))
    out.write("REJECTED %d\n" % rejected)
    out.write("IDENTITY rows+rejected=%d tokens=%d\n" % (total, res["tokens"]))
    if res["tokens"] == 0:
        out.write("DEAD: zero tokens -- a zero denominator is not agreement\n")
        return 5
    if total != res["tokens"]:
        out.write("LEAK: %d token(s) reached no disposition\n" % (res["tokens"] - total))
        return 1
    out.write("IDENTITY OK\n")
    return 0


PLANT_TREE = {
    "p.md": "The corpus is 34 graphs and MEASURED 2026-10-06 14:16 spec 1 covers 70 of 77.\n",
    "q.py": "# e69de29b is a hash, 3.12 is a version, f32 is a name, 788-913 s projected\n",
    "r.bend": "# 13 of 34 graphs fail and 47 paths right now, per gatekit.py:59\n",
}
PLANT_KEEP = ("34", "13", "47", "70", "77")     # counts and ratios: MUST survive
PLANT_REJECT = (("date", 3, "2026-10-06 plus its 10 and 06 fragments"),
                ("file-line", 1, "gatekit.py:59 is another unit's population"),
                ("hex", 1, "e69de29b is an object id"),
                ("version", 1, "3.12 is a version"),
                ("identifier", 1, "f32 is a name"))


def _git(tmp, *args):
    env = dict(os.environ, GIT_AUTHOR_NAME="plant", GIT_AUTHOR_EMAIL="plant@x",
               GIT_COMMITTER_NAME="plant", GIT_COMMITTER_EMAIL="plant@x",
               GIT_AUTHOR_DATE="2000-01-01T00:00:00+0000",
               GIT_COMMITTER_DATE="2000-01-01T00:00:00+0000")
    return subprocess.run(("git",) + args, cwd=tmp, env=env, check=True,
                          capture_output=True, text=True)


def plant(out):
    """A REAL TREE IN A REAL REPO, because the population is `git ls-tree` of a real pin.

    The first version wrote a `.agents/UPSTREAM-PIN.md` naming `deadbee` and then called
    `census()`, which died inside `git ls-tree deadbee` with exit 128 -- a plant that reaches
    the instrument's own `subprocess` and never reaches a verdict is a plant of `git`. So the
    plant commits, reads HEAD back, and writes the pin that commit really has. The pin names a
    commit holding NO prose, so every planted file lands in the population; a pin containing
    the plant would classify all three files VENDORED and the whole expectation set would pass
    over an empty tree.
    """
    with tempfile.TemporaryDirectory() as tmp:
        _git(tmp, "init", "-q")
        os.makedirs(os.path.join(tmp, PIN_RECORD.rsplit("/", 1)[0]), exist_ok=True)
        open(os.path.join(tmp, PIN_RECORD), "w", encoding="utf-8").write("# pin record\n")
        _git(tmp, "add", "-A")
        _git(tmp, "commit", "-q", "-m", "plant: an empty pin")
        pin = _git(tmp, "rev-parse", "HEAD").stdout.strip()
        open(os.path.join(tmp, PIN_RECORD), "w", encoding="utf-8").write(
            "# plant pin record\n\nThe pin is **`%s`**\n" % pin)
        for rel, body in sorted(PLANT_TREE.items()):
            open(os.path.join(tmp, rel), "w", encoding="utf-8").write(body)
        res = census(tmp)
        emit_rows(res, out)
        emit_rejects(res, out)
        out.write("PLANT files=%d rows=%d tokens=%d\n"
                  % (res["ours"], len(res["rows"]), res["tokens"]))
        bad = 0
        # A plant that cannot fail is a comment. Each KEEP is a claim the rules must not
        # eat; each REJECT is a rule that must FIRE, because a wrong exclusion writes no row
        # and no row argues back. This plant found three real defects in its own rules: the
        # `date` rule read the token and so never saw `-10-06` (0 hits), the `identifier` rule
        # looked for the digit in the LEFT WORD and the digit is the token (0 hits), and a
        # `sha256`-shaped pin contributed two false rows until `_is_hex` took the enclosing word.
        kept = {r[2] for r in res["rows"]}
        for want in PLANT_KEEP:
            ok = want in kept
            bad += 0 if ok else 1
            out.write("%s keep %s -- a count or a ratio\n" % ("OK  " if ok else "FAIL", want))
        for gone in ("06", "16", "59", "12", "32"):
            ok = gone not in kept
            bad += 0 if ok else 1
            out.write("%s drop %s -- not a measurement\n" % ("OK  " if ok else "FAIL", gone))
        for rule, at_least, why in PLANT_REJECT:
            ok = res["rejects"][rule] >= at_least
            bad += 0 if ok else 1
            out.write("%s reject %s >= %d -- %s\n"
                      % ("OK  " if ok else "FAIL", rule, at_least, why))
        rc = emit_prove(res, out)
        if bad or rc:
            out.write("PLANT FAILED: %d expectation(s) unmet, prove rc=%d\n" % (bad, rc))
            return 1
        out.write("PLANT OK\n")
        return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    for mode in ("plan", "rows", "rejects", "prove", "plant"):
        ap.add_argument("--" + mode, action="store_true")
    ap.add_argument("--root", default=".")
    a = ap.parse_args(argv)
    if a.plant:
        return plant(sys.stdout)
    res = census(a.root)
    if a.plan:
        emit_plan(res, sys.stdout)
    if a.rows:
        emit_rows(res, sys.stdout)
    if a.rejects:
        emit_rejects(res, sys.stdout)
    if a.prove:
        return emit_prove(res, sys.stdout)
    if not any((a.plan, a.rows, a.rejects)):
        emit_plan(res, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())