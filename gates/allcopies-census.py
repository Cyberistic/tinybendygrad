#!/usr/bin/env python3
r"""allcopies-census.py -- CENSUS EVERY CONSTRUCT THAT ENUMERATES `Ops`, and grade each against upstream.

    .venv/bin/python gates/allcopies-census.py            # the census
    .venv/bin/python gates/allcopies-census.py --rows F   # TSV: class, n, file:line, site, missing, extra

WHAT IT IS FOR. `GS_ALL` (schedule/rangeify.bend) and `OP_ALL` (uop/spec.bend) are written-out copies of
one predicate -- "the set of every op" -- and both were reported as 76 against upstream's 75, both
omitting `CONST`. `dd_ops.all` (codegen/decomp/dtype.bend), `pr_ear_keys` (schedule/prepare.bend),
`op_list` (viz/serve.bend) and `all_ops` (uop/ops.bend) are more copies of the same predicate. This
finds all of them, counts them, and says which agree with upstream. It does not decide whether they
should -- see the CONSUMERS section, which is the evidence for that question.

## THE POPULATION IS A DECLARED RULE, NOT A NAME AND NOT A REGEX

Four rules, applied by walking. None is a list of files and none is a list of names:

  R1  FILES. `os.walk(tinybendygrad)` + `endswith(".bend")`, INTERSECTED with `git ls-tree -r HEAD
      -- tinybendygrad`. `git ls-files` is the INDEX and `jj` colocation arms it (AGENTS.md, doctrine 1),
      so an armed index reports the working copy as staged. The intersection drops mutation-harness
      scratch -- MEASURED below. It is not cosmetic: `codegen/decomp/dtype-mut.bend` carries a
      VERBATIM duplicate of `dd_ops.all`, so counting the walk alone would report a sixth copy of the
      predicate that no committed file contains.

  R2  PARSE BEFORE MATCH. Each file is comment-stripped by a scanner that tracks string literals, and
      every match runs on the stripped text. Two measured reasons, both in this tree:
        * a regex over raw source READS PROSE. `graphcmp.py` documents `Ops.FLIP` in a comment, so a
          raw-text census cannot tell an enumeration item from a word in a paragraph.
        * `#` occurs INSIDE string literals -- `renderer/amd/generate.bend` embeds CPython source with
          `# noqa` in it -- so a stripper that does not track quotes deletes CODE. That is
          `checks/sweep.py`'s `ORACLE_WORD` defect one layer down: an instrument reading the wrong
          layer of the file.

  R3  SITE. Any of:
        (a) a `def` whose RETURN TYPE is an op list (`List<&N, O.Op>` / `List<&N, Op>`);
        (b) a `def` whose body carries >=1 op CONSTRUCTOR (catches `PMEntry`-typed inline rows);
        (c) one `O.PMEntry{tag, ops, rejects}` ROW of an `O.PMEntrys{[ ... ]}` table -- per ROW, not
            per table, because a table is a CONSUMER of its rows' sets and grading a table as one
            enumeration invents a copy nobody wrote;
        (d) the `type Op is Data:` declaration block and the `Ops.value` arm table, which are
            enumerations too: one POSITIONAL, one keyed. They are the baseline the others are
            measured against, so the census prints them in its own output rather than assuming them.
      Clause (a) is what keeps ALIASES in: `def MOPS_END() -> List<&2, O.Op>: MOPS_FB()` has no
      constructor of its own and is still an enumeration.

  R4  MEMBERS. An ITEM is a CONSTRUCTOR `\bOps[A-Z0-9_]+\{\}` or a REFERENCE `name()`/`ns.name()`.
      References resolve transitively over the same file's sites to a fixed point, because a set
      built by `List.append(&2, O.Op, MOPS_FB(), [O.OpsINDEX{}])` is the union its arguments make, and
      a copy that only reads its own literals is a copy that cannot see its own bug. A reference with
      no same-file site is COUNTED AND PRINTED, never silently dropped: an unresolved reference that
      contributed members would shorten a set by an amount nobody measured, which is exactly what
      `checks/repro-paths.py`'s five-item suffix set did (it read a PREFIX of a path as the path, so
      a broken reference counted as RESOLVED and a dangling one counted as a row).

## WHAT IS NOT A SITE -- THE REJECTION TALLY, MADE RATHER THAN ASSUMED

  * `type OPTOPS is Data:` (`uop/ops.bend`) declares `OPS_TC/OPS_SPLIT/OPS_PADTO/OPS_SWAP`. A
    case-INSENSITIVE `Ops` pattern, or one lacking the word-boundary anchor, manufactures four phantom
    `Op` members -- the `OptOps.TC` tail hazard. The phantom count is asserted in this file's own
    output below, from the parse, not claimed here.
  * `List<&2, O.Op>` is a TYPE, and a type is not a member; only a constructor is.
  * A COUNT CONSTANT (`all_ops_n`, `n_OptOps = 4`) states a number without stating a set, so it can
    neither agree nor disagree. `ops.bend`'s `all_ops` header cites CPython measuring 77; that is
    PROSE about a measurement and R2 strips it before anything is counted.
  * A REGEX that reads the tail of an identifier is how the prior census manufactured three phantom
    members, and `R2 + \b + case-sensitive` is the structural answer, not a longer exclusion list.

## THE DERIVATION IS BORROWED, NOT REWRITTEN

Upstream's member set and the port's `type Op is Data:` block both come from `gates/opseven-gate.py`,
imported BY PATH. That is doctrine 1 clause (a). Nothing in this file transcribes a member list --
not upstream's, not the port's, and certainly not the contents of any copy it grades.
`ops_value_holds` in that gate is the shape to copy: it PREDICTS from `_declared_ops()` and
`_upstream_ops()` and never reads a list it typed itself.

## VERDICTS ARE FIVE, AND `EMPTY` IS ONE OF THEM

`FULL-PORT` equals the port's own declaration block. `FULL-UP` equals upstream's `class Ops`.
`SUBSET` a proper subset of the port's declaration. `OTHER` neither. `EMPTY` resolved to ZERO members.

`EMPTY` is printed, never omitted: doctrine 2's six-state harness, case 2 -- a site that printed no row
and a site that compared nothing are indistinguishable to a caller, so a zero is a row.
"""

import hashlib
import importlib.util
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

CTOR = re.compile(r"\bOps([A-Z0-9_]+)\{\}")                 # R4: word-boundary + case-sensitive
REF = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\(\)")
OPLIST_TYPE = re.compile(r"->\s*List<&\d+,\s*(?:O\.)?Op>\s*:")
DEF_HEAD = re.compile(r"^(\s*)def\s+([A-Za-z_][A-Za-z0-9_.]*)\s*\(")
ENTRY = re.compile(r"O\.PMEntry\{")
VALUE_ARM = re.compile(r"^\s*case Ops([A-Z0-9_]+)\{\}:")
CASE_KEY = re.compile(r"case\s+(?:O\.)?Ops[A-Z0-9_]+\{\}")
ROW_CALL = re.compile(r"\b(?:op_row|row|urow|brow|srow)\s*\(\s*\"")

# call-shaped tokens that are never an enumeration of anything: module namespaces, constructors of
# other datatypes, and Python builtins the port spells the same way.
NOT_A_REF = frozenset({
    "Nil", "List", "Bool", "U32", "Str", "S", "F", "O", "M", "CL", "CU", "WK", "R", "P",
    "int", "len", "range", "map", "filter", "sorted", "set", "tuple", "any", "all", "print", "min",
    "max", "sum", "abs", "zip", "list", "dict", "str", "bool", "float", "type", "repr",
})


def strip_comments(src: str) -> str:
    """R2. `#` outside a string starts a comment; quotes are tracked so a `#` INSIDE a string is data.
    Comment bytes become spaces, never deletions, so line numbers never shift."""
    out, i, n, quote = [], 0, len(src), None
    while i < n:
        ch = src[i]
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
        elif ch == "#":
            while i < n and src[i] != "\n":
                out.append(" ")
                i += 1
            continue
        elif ch in "\"'":
            quote = ch
            out.append(ch)
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def body_colon(hdr: str) -> int:
    """Index of the `:` that ENDS the signature, or -1.

    NOT `hdr.index(":")`: a parameter list carries colons of its own (`def f(x: U32)`), and the first
    version of this file split on it, called every block-bodied def inline-bodied, and returned an
    EMPTY member set for every site whose body is on the following line -- including `dd_ops.all`,
    whose 77 constructors were read from the signature alone.

    NOT angle brackets either, and the reason is worth the line: counting `>` for the `->` arrow
    drives the depth to -1 at the arrow, the `<` of `List<&2, O.Op>` brings it back, and the `>` of
    the same type takes it to -1 again, so the signature's own colon sits at -1 and is never found.
    That is a silent empty set, not an error: `pr_ear_keys` -- a written-out 77-member copy, one of
    the five -- measured 0 members. Angle brackets appear in a def header ONLY inside type arguments
    and the arrow, and neither can contain the colon that ends the signature, so `()[]{}` is the
    whole of it."""
    depth = 0
    for k, ch in enumerate(hdr):
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == ":" and depth == 0:
            return k
    return -1


def _load_opseven():
    """Doctrine 1(a): the generator's own parsers, loaded BY PATH, not retyped here."""
    spec = importlib.util.spec_from_file_location("opseven_gate", HERE / "opseven-gate.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


OG = _load_opseven()


def upstream_ops() -> list[str]:
    """Upstream's `Ops`, from `git show upstream:tinygrad/uop/__init__.py`, by the gate's own parser.
    NEVER from memory and NEVER from a brief: thirteen agents this session were sent to wrong line
    numbers, and one corrected a brief on a tag shift by measurement."""
    return OG._upstream_ops()


def declared_ops() -> list[str]:
    """The port's `type Op is Data:` block, by the gate's own parser."""
    return OG._declared_ops()


def tracked_bend() -> list[str]:
    """R1. The COMMIT's `.bend` files, relative to ROOT, that exist NOW."""
    out = subprocess.run(
        ["git", "ls-tree", "-r", "HEAD", "--name-only", "--", "tinybendygrad"],
        cwd=ROOT, capture_output=True, text=True, check=True).stdout.split()
    return sorted({p for p in out if p.endswith(".bend") and os.path.isfile(ROOT / p)})


def walk_bend() -> list[str]:
    """R1's other half, so the intersection is a measurement rather than an assumption."""
    return sorted(str((Path(d) / n).relative_to(ROOT))
                  for d, _, ns in os.walk(ROOT / "tinybendygrad")
                  for n in ns if n.endswith(".bend"))


def defs_of(lines: list[str]) -> list[tuple[str, int, int, int, str]]:
    """`def` headers of a stripped file: `(name, header_line0, indent, body_end, header)`.

    The body is the header's tail past its `:` plus the lines up to `body_end`, which is the next
    non-blank line at STRICTLY LESS indentation, or the next `def` at ANY indentation -- a nested
    `def pr_dispatch.go(...)` sits at the same indent as `pr_dispatch(...)`, and a def that does not
    terminate on one of the two swallows the rest of the file."""
    out = []
    for i, ln in enumerate(lines):
        m = DEF_HEAD.match(ln)
        if not m:
            continue
        indent = len(m.group(1))
        end = len(lines)
        for j in range(i + 1, len(lines)):
            s = lines[j]
            if not s.strip():
                continue
            if len(s) - len(s.lstrip()) < indent or DEF_HEAD.match(s):
                end = j
                break
        out.append((m.group(2), i, indent, end, ln))
    return out


def body_text(lines: list[str], i: int, end: int, hdr: str) -> str:
    """The def's body: the header's tail past its `:` (an inline `def f(): expr`) plus the indented
    block. An inline body contributes no following lines, which is why `body_end` is unused here."""
    colon = body_colon(hdr)
    head = hdr[colon + 1:] if colon >= 0 else ""
    return "\n".join([head] + lines[i + 1:end])


def members_of(text: str) -> tuple[set[str], set[str]]:
    """R4: `(constructors, references)`."""
    ctors = {m.group(1) for m in CTOR.finditer(text)}
    refs = {m.group(1) for m in REF.finditer(text)} - NOT_A_REF
    return ctors, {r for r in refs if not r.startswith("Ops")}


def match_close(text: str, open_at: int) -> int:
    """Index of the `]` matching the `[` at `open_at`, or -1."""
    depth = 0
    for j in range(open_at, len(text)):
        if text[j] == "[":
            depth += 1
        elif text[j] == "]":
            depth -= 1
            if depth == 0:
                return j
    return -1


def split_args(inner: str) -> list[str]:
    """Split a record's body on commas at depth 0 of `()[]{}`. Depth 0 or the commas inside
    `[A{}, B{}]` cut every ops field in two, which is what the first version of this did."""
    out, buf, depth = [], [], 0
    for ch in inner:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append("".join(buf))
            buf = []
            continue
        buf.append(ch)
    out.append("".join(buf))
    return out


def table_rows(text: str) -> list[tuple[str, int, str, str]]:
    """R3(c). One entry per `O.PMEntry{...}` ROW: `(rowkey, line0, ops-field, rejects-field)`.

    The ops field is either an inline `[...]` (this row enumerates) or a `NAME()` reference (this row
    CONSUMES an enumeration). Splitting the row is the point: a table is not a copy of the predicate,
    and grading it as one manufactures a sixth copy that nobody wrote."""
    rows = []
    for m in ENTRY.finditer(text):
        depth, j = 0, m.end() - 1
        while j < len(text):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        args = split_args(text[m.end():j])[:3]
        args += [""] * (3 - len(args))
        rows.append((f"PMEntry{{{args[0].strip()}}}", text[:m.start()].count("\n"),
                     args[1].strip(), args[2].strip()))
    return rows


def resolve(sites: dict[str, tuple[set[str], set[str]]]) -> dict[str, set[str]]:
    """R4's transitive closure over same-file references, to a fixed point."""
    resolved: dict[str, set[str]] = {}
    for name in sites:
        stack, acc = [name], set()
        # iterative with a seen-set over the whole component
        seen: set[str] = set()
        while stack:
            cur = stack.pop()
            if cur in seen:
                continue
            seen.add(cur)
            if cur not in sites:
                continue
            ctors, refs = sites[cur]
            acc |= ctors
            stack.extend(refs)
        resolved[name] = acc
    return resolved


def census() -> tuple[list[dict], dict[str, set[str]], list[tuple[str, str, str]]]:
    rows: list[dict] = []
    unres: dict[str, set[str]] = {}
    consumers: list[tuple[str, str, str]] = []
    for rel in tracked_bend():
        raw_lines = (ROOT / rel).read_text().split("\n")
        stripped = strip_comments("\n".join(raw_lines))
        lines = stripped.split("\n")
        sites: dict[str, tuple[set[str], set[str]]] = {}
        where: dict[str, tuple[int, str, str]] = {}
        for name, i, indent, end, hdr in defs_of(lines):
            text = body_text(lines, i, end, hdr)
            ctors, refs = members_of(text)
            if not (OPLIST_TYPE.search(hdr) or ctors):
                continue
            key, n = name, 1
            while key in sites:            # two defs of one name: keep both, do not merge
                n += 1
                key = f"{name}#{n}"
            sites[key] = (ctors, refs)
            # ORIGIN, decided HERE where the body text is in hand, because "a copy" and "something that
            # mentions a copy" are different objects and the whole question of whether duplication is a
            # defect turns on which one a site is:
            #   LITERAL  it spells its OWN constructors. The text IS the set, so it can rot alone.
            #   ALIAS    it spells none and inherits the whole set by reference. One edit upstream of it
            #            moves it; nothing in its own text is a copy of anything.
            #   TABLE    it is an `O.PMEntrys{[ ... ]}` written out. Its ROWS are the sets, so grading
            #            it as ONE set would manufacture a copy nobody wrote.
            if "PMEntrys{" in text:
                where[key] = (i, "def", "TABLE")
            elif not ctors:
                where[key] = (i, "def", "ALIAS")
            elif CASE_KEY.search(text):
                # A `case OpsX{}:` arm is a DISPATCH KEY, not a set as data. `dt_shape` (uop/fold.bend)
                # names all 77 that way and is a total FUNCTION over the enum -- a missing op is a
                # missing ARM, not a missing element, and it is not a copy of anything. Counted, and
                # tallied separately, because R3's "any def with >=1 constructor" cannot tell the two
                # apart and an instrument that cannot see its own over-inclusion is decoration.
                where[key] = (i, "def", "LADDER")
            elif ROW_CALL.search(text):
                # `main` (viz/serve.bend) constructs every op to EMIT ONE TEST ROW each. It enumerates
                # the enum as a fixture; it is not a set anything dispatches on.
                where[key] = (i, "def", "ROWS")
            else:
                where[key] = (i, "def", "SET")
        for rowkey, line0, ops, rejects in table_rows(stripped):
            if not ops:
                continue
            if ops.startswith("["):
                key, n = rowkey, 1
                while key in sites:        # two rows with the same tag in one file: keep both
                    n += 1
                    key = f"{rowkey}#{n}"
                sites[key] = members_of(ops)
                where[key] = (line0, "row", "ROW")
            else:
                consumers.append((rel, f"{rowkey}@{line0 + 1}", ops.split("(")[0].strip()))
        resolved = resolve(sites)
        for key, (_, refs) in sites.items():
            gone = {r for r in refs if r not in sites}
            if gone:
                unres[f"{rel}:{key}"] = gone
        for key, (line0, kind, origin) in where.items():
            ctors, _ = sites[key]
            rows.append(dict(site=key, file=rel, line=line0 + 1, kind=kind, origin=origin,
                             direct=len(ctors), members=resolved.get(key, set()),
                             claim=doc_claim(raw_lines, line0)))
    return rows, unres, consumers


def classify(members: set[str], port: set[str], up: set[str]) -> str:
    if not members:
        return "EMPTY"
    if members == port:
        return "FULL-PORT"
    if members == up:
        return "FULL-UP"
    if members <= port:
        return "SUBSET"
    return "OTHER"


def impossible(cond: bool, msg: str) -> None:
    """Refuse rather than report, on the conditions under which this census would measure nothing and
    print a clean table anyway. A census whose answer is `0 copies found` when the rule silently
    stopped matching is worse than no census (doctrine 2: `DEAD` is not a zero)."""
    if cond:
        print(f"REFUSED: {msg}")
        raise SystemExit(3)


CLAIM_WORDS = re.compile(r"GroupOp\.All|every constructor|whole enum|every op|all 7[0-9]|seventy-seven")


def doc_claim(raw_lines: list[str], line0: int) -> str:
    """What the site's own PROSE says it is, read from the comment block directly above it.

    The ONE place in this file that reads comments on purpose. R2 strips them because a regex over
    raw source cannot tell an enumeration item from a word in a paragraph; here the paragraph IS the
    question, because a whole-enum CLAIM is an intent and the only place an author states an intent
    is prose. It is reported as `claims-whole-enum` or `-`, and it is never used to classify."""
    claim, j = "-", line0 - 1
    while j >= 0 and (not raw_lines[j].strip() or raw_lines[j].lstrip().startswith("#")):
        if raw_lines[j].lstrip().startswith("#") and CLAIM_WORDS.search(raw_lines[j]):
            claim = "claims-whole-enum"
        j -= 1
    return claim


def main() -> int:
    walk, tracked = walk_bend(), tracked_bend()
    dropped = sorted(set(walk) - set(tracked))
    up, port = set(upstream_ops()), set(declared_ops())
    rows, unres, consumers = census()
    # R3(d): the baseline enumerations, read by the gate's own parsers, printed here so the census
    # states the yardstick it measures against instead of importing it silently.
    base = [("type Op is Data:  <DATA BLOCK>", set(declared_ops())),
            ("Ops.value arms (POSITIONAL)", {n for n, _ in OG._value_arms()}),
            ("Ops.name.of arms (KEYED)", {n for n, _ in OG._name_arms()}),
            ("all_ops (Ops.value's sibling)", set(OG._all_ops()))]

    # THE REVISION, because `uop/ops.bend` is being MID-RENUMBERED by another unit and this census
    # reads its declaration block. A count without the md5 it was taken at is a number about a file
    # that no longer exists (AGENTS.md: "NEVER QUOTE A ROW COUNT WITHOUT THE RULE THAT PRODUCED IT,
    # AND NEVER QUOTE ONE FROM A JOB THAT MAY STILL BE RUNNING").
    opsb = ROOT / "tinybendygrad/uop/ops.bend"
    md5 = hashlib.md5(opsb.read_bytes()).hexdigest()
    mtime = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(opsb.stat().st_mtime))
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True,
                          check=True).stdout.strip()
    upsha = subprocess.run(["git", "rev-parse", "upstream"], cwd=ROOT, capture_output=True, text=True,
                           check=True).stdout.strip()

    print(f"== REVISION  HEAD={head[:12]}  upstream={upsha[:12]}")
    print(f"            tinybendygrad/uop/ops.bend  md5={md5}  mtime={mtime}")
    print("            ANOTHER UNIT IS MID-RENUMBER ON THAT FILE. These numbers are true OF THAT md5.")
    print(f"== R1  walk(tinybendygrad/**/*.bend) = {len(walk)}; in COMMIT(HEAD) = {len(tracked)}; "
          f"dropped {len(dropped)}")
    for d in dropped:
        print(f"       dropped {d}")
    print(f"== DERIVED from gates/opseven-gate.py, loaded by path: port declared = {len(port)}, "
          f"upstream = {len(up)}, port-only = {sorted(port - up)}, upstream-only = {sorted(up - port)}")

    src = strip_comments((ROOT / "tinybendygrad/uop/ops.bend").read_text())
    blk = re.search(r"type OPTOPS is Data:(.*?)\n(?=\S)", src, re.S)
    phantom = sorted({m.group(1) for m in CTOR.finditer(blk.group(1))}) if blk else []
    print(f"== R2  phantom check, MEASURED: `type OPTOPS is Data:` contributes {len(phantom)} Op "
          f"constructors {phantom}. The OptOps.TC tail hazard is structurally absent, not excluded by list.")

    print(f"== R3  SITES = {len(rows)} (defs + PMEntry rows) across {len({r['file'] for r in rows})} files; "
          f"consuming rows = {len(consumers)}")

    impossible(not port, "`type Op is Data:` yielded 0 variants; R2/CTOR stopped matching and every "
                         "verdict below would read as a clean PASS")
    impossible(not up, "upstream's `class Ops` yielded 0 members; the agreement column would be vacuous")
    impossible(not dropped, "the walk and the commit agree exactly, so R1's intersection is not "
                            "intersecting anything -- the HEAD tree or the walk is wrong")

    by: dict[str, list[dict]] = {}
    for r in rows:
        r["cls"] = classify(r["members"], port, up)
        by.setdefault(r["cls"], []).append(r)
    print("\n== THE FIVE VERDICTS")
    for k in ("FULL-PORT", "FULL-UP", "SUBSET", "OTHER", "EMPTY"):
        print(f"   {k:10s} {len(by.get(k, [])):3d}")

    shapes: dict[str, int] = {}
    for r in rows:
        shapes[r["origin"]] = shapes.get(r["origin"], 0) + 1
    print("\n== REJECTION TALLY, by SHAPE. R3 admits any def carrying a constructor, so it admits four")
    print("   shapes that are NOT copies of the predicate-as-data. They are counted and named, not")
    print("   silently kept, because a census that cannot see its own over-inclusion is decoration.")
    for shape, why in (("SET", "the set as DATA: a `-> List<&N, O.Op>` value a rule dispatches on"),
                       ("ALIAS", "no constructor of its own; inherits a whole set by reference"),
                       ("ROW", "one PMEntry row: the sets are its own ops field"),
                       ("TABLE", "an `O.PMEntrys{[ ... ]}` written out; the ROWS are the sets"),
                       ("LADDER", "`case OpsX{}:` arms -- a total FUNCTION over the enum, not a set"),
                       ("ROWS", "constructs each op to EMIT a test row; a fixture, not a set")):
        n = shapes.get(shape, 0)
        print(f"   {shape:7s} {n:5d}  {why}")

    print("\n== R3(d) THE YARDSTICK: the enumerations this census measures the copies against")
    for label, members in base:
        cls = classify(members, port, up)
        miss = sorted(up - members)
        extra = sorted(members - up)
        agree = "AGREES" if not miss and not extra else "DISAGREES"
        print(f"   {label:34s} n={len(members):3d}  {cls:10s} {agree} with upstream"
              f"{': missing ' + str(miss) if miss else ''}{': extra ' + str(extra) if extra else ''}")

    whole = sorted(by.get("FULL-PORT", []) + by.get("FULL-UP", []), key=lambda q: (q["file"], q["line"]))
    # THE POPULATION OF INTEREST, and its threshold is DERIVED, not chosen to fit the answer:
    # upstream's enum has `len(up)` members TODAY, so any SET site carrying at least that many is
    # claiming the whole enum -- and a site one or two short of the port's declaration is still a
    # claim on the whole enum that is WRONG BY A MEMBER, which is precisely the defect under census.
    # A subset (30 ops, 47 ops) is not a claim and is not counted. So `n >= len(up)` and shape SET.
    claims = sorted((r for r in rows if r["origin"] == "SET" and len(r["members"]) >= len(up)),
                    key=lambda q: (q["file"], q["line"]))
    impossible(not claims, "no site of shape SET resolved to >= |upstream| members, so the whole-enum "
                           "census compared nothing; a refactor that renamed `-> List<&N, O.Op>` would "
                           "produce exactly this table and nothing else")
    print(f"\n== EVERY SITE THAT CLAIMS THE WHOLE ENUM (shape SET, n >= |upstream| = {len(up)}): "
          f"{len(claims)}")
    print("   `claim` is the site's own PROSE, read from the comment above it; `omits-of-port` is what")
    print("   it leaves out of the declaration, and is the number that makes a claim wrong.")
    for r in claims:
        print(f"   {r['site']:14s} n={len(r['members']):3d} {r['claim']:17s} "
              f"{r['file'].replace('tinybendygrad/', '')}:{r['line']}")
        print(f"       omits-of-port={sorted(port - r['members']) or '-'}  "
              f"omits-of-upstream={sorted(up - r['members']) or '-'}  "
              f"carries={sorted(r['members'] - up) or '-'}")

    other_shape = [r for r in whole if r["origin"] != "SET"]
    print(f"\n== SITES THAT REACH THE WHOLE ENUM BY ANOTHER SHAPE ({len(other_shape)}), so the")
    print("   count of CLAIMS is not mistaken for the count of sites that cover the enum")
    for r in other_shape:
        print(f"   {r['site']:14s} {r['origin']:7s} n={len(r['members']):3d} "
              f"{r['file'].replace('tinybendygrad/', '')}:{r['line']}")

    short_all = sorted((r for r in rows if len(port - r["members"]) == 1 and not r["members"] - port
                        and r["origin"] in ("SET", "ROW")),
                       key=lambda q: (q["file"], q["line"]))
    print(f"\n== EVERY SITE SHORT OF THE PORT'S OWN DECLARATION BY EXACTLY ONE MEMBER ({len(short_all)})")
    for r in short_all:
        print(f"   {r['site']:14s} {r['origin']:7s} n={len(r['members']):3d} omits "
              f"{sorted(port - r['members'])}  {r['file'].replace('tinybendygrad/', '')}:{r['line']}")

    subs = sorted(by.get("SUBSET", []), key=lambda q: (-len(q["members"]), q["file"]))
    print(f"\n== SUBSET ({len(subs)}): the largest. NOT copies of the predicate -- the sets other rules key on.")
    print("   -- the ones that are short of the port's own DECLARATION by exactly one member:")
    one_short = [r for r in subs if len(port - r["members"]) == 1 and len(r["members"] - port) == 0]
    for r in sorted(one_short, key=lambda q: (q["file"], q["line"])):
        print(f"      {r['site']:22s} {r['origin']:7s} n={len(r['members']):3d} omits "
              f"{sorted(port - r['members'])}  {r['file'].replace('tinybendygrad/', '')}:{r['line']}")
    if not one_short:
        print("      (none)")
    print("   -- the eight largest:")
    for r in subs[:8]:
        if r in one_short:
            continue
        print(f"      {r['site']:22s} {r['origin']:7s} n={len(r['members']):3d} "
              f"{r['file'].replace('tinybendygrad/', '')}:{r['line']}")
    if by.get("OTHER"):
        print(f"\n== OTHER ({len(by['OTHER'])}): carries a member the declaration does not declare")
        for r in by["OTHER"][:10]:
            print(f"   {r['site']:26s} {sorted(r['members'] - port)[:5]} {r['file']}:{r['line']}")
    empt = by.get("EMPTY", [])
    print(f"\n== EMPTY ({len(empt)}): enumerations that resolve to ZERO members. A row, not an omission.")
    for r in empt[:10]:
        print(f"   {r['site']:26s} {r['file'].replace('tinybendygrad/', '')}:{r['line']}")
    if len(empt) > 10:
        print(f"   ... and {len(empt) - 10} more")

    if consumers:
        print(f"\n== CONSUMERS ({len(consumers)}): PMEntry rows that REFERENCE an enumeration rather than "
              f"write one out. A row here is why a duplicated predicate is load-bearing -- its members "
              f"decide a DISPATCH.")
        for rel, rowkey, ref in consumers[:16]:
            print(f"   {rowkey:22s} -> {ref:18s} {rel.replace('tinybendygrad/', '')}")
        if len(consumers) > 16:
            print(f"   ... and {len(consumers) - 16} more")

    if unres:
        print(f"\n== R4  UNRESOLVED in-file references ({len(unres)} sites). Each is a consumer of an "
              f"enumeration defined in ANOTHER file, or a def R3 missed. Neither is silently dropped.")
        for k, v in sorted(unres.items())[:12]:
            print(f"   {k}: {sorted(v)[:5]}{' ...' if len(v) > 5 else ''}")

    if "--rows" in sys.argv:
        out = Path(sys.argv[sys.argv.index("--rows") + 1])
        out.write_text("".join(
            f"{r['cls']}\t{len(r['members'])}\t{r['file']}:{r['line']}\t{r['site']}\t"
            f"{','.join(sorted(up - r['members']))}\t{','.join(sorted(r['members'] - up))}\n"
            for r in sorted(rows, key=lambda q: (q["file"], q["line"], q["site"]))))
        print(f"\nwrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())