#!/usr/bin/env python3
"""gates/code-reader-census.py -- THE CENSUS OF A READER THAT DROPPED THE TAIL OF A FILE.

WHAT THIS IS. `gates/pincensus-pop.py:code_lines()` is the reader every pin census, every
edge gate and every subject resolver asks for "the code of this file". Until 2026-10-20 it
decided for itself where a string ended: it OPENED a docstring at a line whose text begins
with a quote and CLOSED it at the next line whose text ENDS with a quote. Those are two
different questions and the gap between them is a FILE'S TAIL. A line that is the CLOSER of
a triple-quoted block whose OPENER carried a prefix -- `BEND_MAIN = r'''` ... `'''` -- is a
line that begins with a quote and is NOT an opener, so the reader opened a docstring there,
nothing closed it, and every line after it was invisible. INCLUDING THE
`if __name__ == "__main__":` GUARD, which is the line that says "RUN THIS AS A PROGRAM".

This file is the CENSUS of that damage, and it is a census in the tree's sense: it repairs
nothing. The census run reports three things, and each is a measurement:

  1 HOW MANY TRACKED FILES LOST A TAIL, HOW MANY LINES EACH LOST, AND WHAT WAS IN IT.
  2 THE POPULATION BEFORE AND AFTER THE FIX, for the reader AND for the pin census that
    rides on it.
  3 WHICH VERDICTS MOVED, AND WHY.

THE BEFORE-ARM IS THE TREE'S OWN HISTORY, LOADED FROM THE OBJECT STORE, AND NOT A SECOND
COPY OF THE READER. A hand-written "old reader" beside the new one would be a second
witness with no generator, and it would rot the moment the fix changed shape. So this file
asks git for `gates/pincensus-pop.py` AT A PINNED COMMIT and loads THAT, and if the blob is
not in this repository's object store the census REFUSES rather than measuring something
else. `git show`, never `git fetch`: other units are live in this tree and a fetch moves a
ref under them.

THE POPULATION IS DISCOVERED, NEVER LISTED. It is `gates/pincensus-pop.py:load()`'s: an
`os.walk` bounded by `git ls-tree -r HEAD`, a UTF-8 decode, and a host classifier that is
`ast.parse` -- so a file is CODE because its CONTENT says so and not because its name ends
in something. `glob` is never used: `AGENTS.md` records the measurement that `glob('*.bend')`
returns `[]` while the files are on disk and tracked.

THE VERDICTS. This file returns PASS 0, FAIL 1, REFUSED 3, and SKIP 4 -- `gates/gatekit.py`'s
vocabulary, not an invented one. It FAILS if the reader still swallows a tail, and it FAILS
if the fix moved a pin row from CAN-FAIL to CANNOT-FAIL, because CANNOT-FAIL is the
accusation and a fix that creates an accusation has weakened the instrument it was meant to
strengthen. It REFUSES if the before-arm is not in this repository.

`--plant` IS NOT THE CENSUS. It writes two copies into a temporary directory and judges
those copies. It does not call `load()`, so it does not walk the tree and it does not
read `damage.rows`. The control asks the fixed reader whether it sees the sentinel
`ends_inside` appends after a prefixed closer. The before reader, loaded by `git show`
of `BEFORE_COMMIT`, does not. Substituting that before reader as the after reader makes
the control red, and the plant requires the red: a control that cannot fail is not a
control. A second copy the tokenizer cannot read must keep every line.
"""
import argparse
import importlib.util
import io
import os
import re
import subprocess
import sys
import tempfile
import time
import tokenize

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ART = os.path.join(HERE, "artifacts", "code-reader-census")
PY = ".venv/bin/python"

PASS, FAIL, REFUSED, SKIP = 0, 1, 3, 4

# THE COMMIT WHOSE `gates/pincensus-pop.py` IS THE READER AS IT WAS. It is the parent of the
# fix, and it is named here rather than inferred, because "the reader as it was" is a claim
# about a COMMIT and a commit that is inferred is a commit that moves.
BEFORE_COMMIT = "c3c4120f4556dadde82511f6bd96cd6a2c3bd5ab"

# THE MARKER. A line that carries it is a line the reader SAW. It is planted in the plant's
# copies and it is what the plant's assertions are about.
MARKER = "TAIL_MARKER"

# THE SENTINEL, AND IT IS THE CENSUS'S ABSOLUTE TEST. The reader is asked about a COPY of
# the file with ONE LINE APPENDED, and it must show that line. A reader that is still inside
# a string when the file ends cannot show it -- and a reader that is still inside a string
# when the file ends has dropped the file's tail, which is the defect. The test needs no
# opinion about what a docstring is, and no second reader to compare against, and it is
# therefore not a restatement of the rule it checks.
SENTINEL = "CODE_READER_SENTINEL = 1"

# A `__main__` GUARD, and a DEFINITION. The two things a tail usually carries and the two
# things whose loss is not cosmetic.
MAIN_GUARD = re.compile(r"^\s*if\s+__name__\s*==\s*[\"']__main__[\"']\s*:")
DEFINITION = re.compile(r"^\s*(?:async\s+def|def|class)\s+\w+")


def git(*argv, cwd=ROOT):
    r = subprocess.run(["git", *argv], cwd=cwd, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_before(root=ROOT):
    """-> the reader as it was, loaded from the object store, or None if it is not here.

    REFUSING IS THE POINT. A census that cannot see the damage it is censusing must say so
    rather than report the damage it can see, which would be a smaller number with the same
    authority.
    """
    src = git("show", f"{BEFORE_COMMIT}:gates/pincensus-pop.py", cwd=root)
    if not src:
        return None
    tmp = os.path.join(ART, "before-pincensus-pop.py")
    os.makedirs(ART, exist_ok=True)
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(src)
    return load_module("code_reader_before_pop", tmp)


def comment_only(line):
    return line.strip().startswith("#")


def ends_inside(reader, text, host):
    """-> True if the reader is still INSIDE a string when the file ends.

    THE ABSOLUTE TEST, AND IT IS THE ONE THE CENSUS JUDGES BY. A copy of the file gets ONE
    LINE APPENDED and the reader is asked about the copy. If the reader shows the appended
    line, it was not inside a string at the end of the file. If it does not, it was, and a
    reader that is inside a string at the end of a file has dropped that file's tail.

    It needs no second reader and no opinion about what a docstring is, so it cannot be
    fooled by a file that merely ENDS with a comment or with a docstring: the appended line
    is outside both and the reader shows it.
    """
    lines = text.splitlines()
    probe = text + ("" if text.endswith("\n") or not text else "\n") + SENTINEL + "\n"
    seen = {n for n, _ in reader.code_lines(probe, host)}
    return (len(lines) + 1) not in seen


def damage(corpus, host, before, after):
    """-> one row per file whose tail the BEFORE reader lost."""
    rows = []
    for path in sorted(corpus):
        h = host[path]
        if h == "prose":
            continue
        text = corpus[path]
        if not ends_inside(before, text, h):
            continue
        lines = text.splitlines()
        b = before.code_lines(text, h)
        a = after.code_lines(text, h)
        last = b[-1][0] if b else 0
        first = next((n for n in range(last + 1, len(lines) + 1)
                      if not comment_only(lines[n - 1])), last + 1)
        tail = lines[first - 1:]
        rows.append({
            "file": path,
            "host": h,
            "last-line-seen-by-before": last,
            "last-line-seen-by-after": a[-1][0] if a else 0,
            "lines": len(lines),
            "lines-lost": len(lines) - first + 1,
            "first-lost-line": first,
            "main-guard": any(MAIN_GUARD.match(l) for l in tail),
            "definition": any(DEFINITION.match(l) for l in tail),
        })
    return rows


def still_swallowing(corpus, host, after):
    """-> the files the AFTER reader still loses a tail of. This must be EMPTY, and the
    census FAILS if it is not: a reader that drops the end of a file is the defect this file
    exists to measure, and an instrument that reports the defect without failing on it is a
    printer."""
    return [(path, len(corpus[path].splitlines()))
            for path in sorted(corpus)
            if host[path] != "prose" and ends_inside(after, corpus[path], host[path])]


def pin_census(before_mod, after_mod):
    """-> (rows_before, rows_after, meta_before, meta_after) of the TREE'S OWN pin census.

    The pin census is `gates/pincensus-gate.py`, and it is run TWICE with the SAME tree and
    the SAME bytes: once with the reader as it was and once with the reader as it is. The
    ONLY thing that differs is which reader `load_pop()` hands back, so every difference
    between the two row sets is attributable to the reader and to nothing else.
    """
    PC = load_module("code_reader_pc", os.path.join(HERE, "pincensus-gate.py"))
    real_load_pop = PC.load_pop
    out = []
    for mod in (before_mod, after_mod):
        PC.load_pop = lambda mod=mod: mod
        try:
            rows, meta = PC.census()
        finally:
            PC.load_pop = real_load_pop
        out.append((rows, meta))
    return out[0], out[1]


def moved_rows(rows_before, rows_after):
    """-> the rows whose class or reader set moved. A row is identified by WHERE it is and
    WHAT it is, never by a line number alone, because a line number moves when a file does.
    """
    b = {(r["where"], r["what"], r["value"]): r for r in rows_before}
    a = {(r["where"], r["what"], r["value"]): r for r in rows_after}
    out = []
    for key in sorted(set(b) | set(a)):
        rb, ra = b.get(key), a.get(key)
        if rb is None or ra is None:
            out.append((key, "ADDED" if rb is None else "REMOVED", rb, ra))
            continue
        if rb["class"] != ra["class"] or rb["n-readers"] != ra["n-readers"]:
            out.append((key, "MOVED", rb, ra))
    return out


def write_rows(rows):
    os.makedirs(ART, exist_ok=True)
    path = os.path.join(ART, "damage.rows")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("# code-reader-census damage.rows -- TAB separated. Generated by "
                 "gates/code-reader-census.py.\n")
        fh.write(f"# before-reader {BEFORE_COMMIT}\n")
        fh.write("\t".join(["file", "host", "lines", "last-line-seen-by-before",
                             "last-line-seen-by-after", "lines-lost", "first-lost-line",
                             "main-guard", "definition"]) + "\n")
        for r in rows:
            fh.write("\t".join(str(r[k]) for k in
                                ["file", "host", "lines", "last-line-seen-by-before",
                                 "last-line-seen-by-after", "lines-lost", "first-lost-line",
                                 "main-guard", "definition"]) + "\n")
    return path


def saw(reader, text, host, needle):
    """-> True if `reader` returned a line carrying `needle`."""
    return any(needle in line for _, line in reader.code_lines(text, host))


def tokenizer_failed(text):
    """-> True if `tokenize` cannot read `text`. The same exceptions `triple_blocks` catches."""
    try:
        list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (tokenize.TokenError, IndentationError, SyntaxError, ValueError):
        return True
    return False


def write_copy(directory, name, text):
    """Write `text` to a file under `directory` and return what was read back.
    None if the copy's bytes are not the bytes that were written."""
    path = os.path.join(directory, name)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    with open(path, encoding="utf-8") as fh:
        got = fh.read()
    return got if got == text else None


def control_holds(reader, text, host):
    """The control's question, asked of one reader.
    True only if the reader sees the sentinel `ends_inside` appends (`ends_inside`
    is false) and sees the planted marker. Substituting the before reader here
    must be false: that is the falsifier."""
    return (not ends_inside(reader, text, host)) and saw(reader, text, host, MARKER)


def kept_every_line(reader, text, host):
    """The census's rule, on a copy the tokenizer cannot read.
    The copy contains a triple quote, so `code_lines` asks the tokenizer, and it
    contains no comment, so every line of the file is a line the reader must return.
    A reader that treats the failure as 'drop the file' loses them."""
    if "'''" not in text and '"""' not in text:
        return False
    if not tokenizer_failed(text):
        return False
    lines = text.splitlines()
    got = [line for _, line in reader.code_lines(text, host)]
    return got == lines and any(MARKER in line for line in lines)


def plant(root=ROOT):
    """The control, the plant, and the falsifier. Copies only. `load()` is not called."""
    after = load_module("code_reader_plant_after",
                        os.path.join(root, "gates", "pincensus-pop.py"))
    before = load_before(root)
    if before is None:
        print(f"code-reader-census --plant: REFUSED -- the before reader is not in "
              f"this repository at {BEFORE_COMMIT}.", file=sys.stderr)
        return REFUSED

    # THE PREFIXED CLOSER. The marker is a line AFTER the closer, which is the tail
    # the before reader swallows and the fixed reader must see. The sentinel is not
    # in this text: `ends_inside` appends it.
    prefixed = (
        "BEND_MAIN = r'''\n"
        "the body of a prefixed closer\n"
        "'''\n"
        f"{MARKER} = 1\n"
    )
    # THE TOKENIZE FAILURE. An unterminated triple quote, so the tokenizer is asked
    # and cannot answer. The opener does not start the line, so the before reader's
    # own state machine does not swallow this tail: the only way the fixed reader
    # drops a line here is by weakening the failure rule.
    broken = f"x = '''unterminated\n{MARKER} = 1\nkept = 1\n"
    host = "python"

    with tempfile.TemporaryDirectory(prefix="code-reader-plant-") as td:
        root_abs = os.path.abspath(root)
        if os.path.commonpath([os.path.abspath(td), root_abs]) == root_abs:
            print("code-reader-census --plant: REFUSED -- the copy directory is inside "
                  "the live tree.", file=sys.stderr)
            return REFUSED
        text = write_copy(td, "prefixed.py", prefixed)
        bad = write_copy(td, "unreadable.py", broken)
        if text is None or bad is None:
            print("code-reader-census --plant: FAIL -- a copy did not read back as the "
                  "bytes that were written.", file=sys.stderr)
            return FAIL
        if tokenizer_failed(text) or not tokenizer_failed(bad):
            print("code-reader-census --plant: FAIL -- the copies do not have the shapes "
                  "the two arms ask about.", file=sys.stderr)
            return FAIL

        after_inside = ends_inside(after, text, host)
        before_inside = ends_inside(before, text, host)
        after_saw = saw(after, text, host, MARKER)
        before_saw = saw(before, text, host, MARKER)
        # THE FALSIFIER IS THE CONTROL'S OWN QUESTION, with the before reader in the
        # after slot. It must return FAIL. A control that still holds has not been
        # shown able to fail.
        control_rc = PASS if control_holds(after, text, host) else FAIL
        falsifier_rc = PASS if control_holds(before, text, host) else FAIL
        tokenize_ok = kept_every_line(after, bad, host)

    before_blind = before_inside and not before_saw
    out = sys.stdout
    out.write("code-reader-census --plant: copies, not the live tree; load() was not called\n")
    out.write(f"  CONTROL   rc={control_rc}  ends_inside={str(after_inside).lower()}  "
              f"marker-seen={str(after_saw).lower()}  "
              f"the fixed reader sees the sentinel after a prefixed closer\n")
    out.write(f"  PLANT     ends_inside={str(before_inside).lower()}  "
              f"marker-seen={str(before_saw).lower()}  "
              f"the before reader does not see that sentinel\n")
    out.write(f"  FALSIFIER rc={falsifier_rc}  before substituted as after; "
              f"{'went red' if falsifier_rc == FAIL else 'DID NOT GO RED'}\n")
    out.write(f"  TOKENIZE  {'kept every line' if tokenize_ok else 'DROPPED A LINE'}  "
              f"a tokenize failure must keep every line\n")
    ok = (control_rc == PASS and falsifier_rc == FAIL and before_blind and tokenize_ok)
    if not ok:
        print("code-reader-census --plant: FAIL", file=sys.stderr)
        return FAIL
    out.write("  PASS: the control holds, the substitution goes red, and a tokenize "
              "failure kept every line.\n")
    return PASS


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--no-write", action="store_true")
    ap.add_argument("--plant", action="store_true",
                    help="the control and its falsifier, on copies; does not walk the tree")
    args = ap.parse_args()
    root = args.root
    if args.plant:
        return plant(root)
    out = sys.stdout

    after = load_module("code_reader_after_pop", os.path.join(root, "gates", "pincensus-pop.py"))
    before = load_before(root)
    if before is None:
        print(f"code-reader-census: REFUSED -- the reader as it was is not in this "
              f"repository's object store at {BEFORE_COMMIT}, so the damage cannot be "
              f"measured. `git show {BEFORE_COMMIT}:gates/pincensus-pop.py` answers ''.",
              file=sys.stderr)
        return REFUSED

    loaded = after.load(root)
    corpus, counts = loaded["corpus"], loaded["counts"]
    host = after.hosts(corpus)

    rows = damage(corpus, host, before, after)
    leftovers = still_swallowing(corpus, host, after)

    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    out.write("code-reader-census: A READER THAT DROPPED THE TAIL OF A FILE\n")
    out.write(f"  generated {stamp} HEAD={git('rev-parse', '--short', 'HEAD')}\n")
    out.write(f"  before-arm: gates/pincensus-pop.py at {BEFORE_COMMIT} "
              f"({git('cat-file', '-t', BEFORE_COMMIT + ':gates/pincensus-pop.py') or 'ABSENT'})\n")
    out.write(f"  population (os.walk + UTF-8 decode, bounded by `git ls-tree -r HEAD`): "
              f"{counts['walk-decoded']} walked, {counts['in-both']} in both, "
              f"{counts['tree-tracked']} in the tree\n")
    code_files = sum(1 for t in corpus if host[t] != "prose")
    out.write(f"  code files in the population: {code_files}\n\n")

    out.write("  THE DAMAGE, BEFORE THE FIX\n")
    out.write(f"    files whose tail the reader dropped: {len(rows)}\n")
    out.write(f"    lines lost, in all: {sum(r['lines-lost'] for r in rows)}\n")
    out.write(f"    of those tails, carrying a `__main__` guard: "
              f"{sum(1 for r in rows if r['main-guard'])}\n")
    out.write(f"    of those tails, carrying a `def`/`class`: "
              f"{sum(1 for r in rows if r['definition'])}\n")
    out.write(f"    files still losing a tail AFTER the fix: {len(leftovers)}"
              f"{' (MUST BE 0)' if not leftovers else ' -- SEE BELOW'}\n")
    out.write("\n")
    for r in rows:
        out.write(f"    {r['file']:66s} {r['host']:6s} lines={r['lines']:5d} "
                  f"before-last={r['last-line-seen-by-before']:5d} "
                  f"after-last={r['last-line-seen-by-after']:5d} "
                  f"lost={r['lines-lost']:5d} main={int(r['main-guard'])} "
                  f"def={int(r['definition'])}\n")
    for path, total in leftovers:
        out.write(f"    STILL SWALLOWED {path}: {total} lines, the reader is still inside a "
                  f"string at the end\n")

    out.write("\n  THE POPULATION, BEFORE AND AFTER -- THE PIN CENSUS'S OWN VERDICTS\n")
    (rb, mb), (ra, ma) = pin_census(before, after)
    out.write(f"    before: rows {len(rb)}  classes {mb['classes']}\n")
    out.write(f"    after : rows {len(ra)}  classes {ma['classes']}\n")
    moved = moved_rows(rb, ra)
    out.write(f"    rows whose class or reader set moved: {len(moved)}\n")
    for key, kind, b, a in moved:
        bc = b["class"] if b else "-"
        ac = a["class"] if a else "-"
        bn = b["n-readers"] if b else "-"
        an = a["n-readers"] if a else "-"
        out.write(f"      {kind} {key[0]}:{key[1]} {bc}({bn}) -> {ac}({an})\n")

    # WHY THE VERDICTS DID OR DID NOT MOVE, AND THE ANSWER IS A MEASUREMENT AND NOT A STORY.
    # `gates/pincensus-pop.py:readers()` scopes a reader to THE FILE THAT DEFINES THE
    # CONSTANT, so a read inside a swallowed tail can only change a pin's verdict if the pin
    # is DEFINED in that same file. So the population that can move is the intersection of
    # "the files whose tail was swallowed" and "the files a pin is defined in", and this
    # prints both and the intersection.
    damaged = {r["file"] for r in rows}
    site_files = {s["file"] for s in after.rule_a(corpus, host) if s["host"] != "prose"}
    both = sorted(damaged & site_files)
    out.write(f"    files whose tail was swallowed: {len(damaged)}\n")
    out.write(f"    files a pin is defined in: {len(site_files)}\n")
    out.write(f"    the intersection -- the only files whose pin verdicts COULD move: "
              f"{len(both)}\n")
    for f in both:
        out.write(f"      {f}\n")
    if not moved and not both:
        out.write("    so no pin verdict could move, and none did. The two agree.\n")

    if not args.no_write:
        out.write(f"\n  damage rows: {write_rows(rows)}\n")

    # THE VERDICT.
    if leftovers:
        print(f"code-reader-census: FAIL -- the reader still loses the tail of "
              f"{len(leftovers)} file(s).", file=sys.stderr)
        return FAIL
    lost_accusations = [(k, b, a) for k, kind, b, a in moved
                        if b and a and b["class"] == "CAN-FAIL" and a["class"] == "CANNOT-FAIL"]
    if lost_accusations:
        print(f"code-reader-census: FAIL -- the fix moved {len(lost_accusations)} row(s) from "
              f"CAN-FAIL to CANNOT-FAIL, and CANNOT-FAIL is the accusation: the fix weakened "
              f"the instrument it was meant to strengthen.", file=sys.stderr)
        return FAIL
    if not rows:
        print("code-reader-census: DEAD -- no file lost a tail, so there is nothing to "
              "report and the measurement is not exercising the defect.", file=sys.stderr)
        return FAIL
    out.write("\n  PASS: no file loses its tail, and no pin row lost a reader.\n")
    return PASS


if __name__ == "__main__":
    sys.exit(main())
