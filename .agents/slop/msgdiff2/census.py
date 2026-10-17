#!/usr/bin/env python3
"""census.py -- SIZE THE CEILING `gates/msgdiff-gate.py` STATES IN ITS HEADER BUT NEVER COUNTS.

    .venv/bin/python .agents/slop/msgdiff2/census.py
    .venv/bin/python .agents/slop/msgdiff2/census.py --plant

`msgdiff-gate.py`'s header says, first and loudest, that it cannot see three things: a
PERCENTAGE with no artefact, a DEAD PID, an INVENTED CONFIG KEY. NOBODY HAS COUNTED HOW MANY
THERE ARE. This file is that count, and it is a CENSUS: it renders no verdict about any commit,
because a census that refused commits would be a THIRD message instrument and the report argues
there should not be one.

THE POPULATION IS DISCOVERED, NEVER LISTED. `git log --format=%H%x00%B%x01` is the corpus. There
is no scope constant, no path list and no author filter in this file's body; `SCOPES` names
three ARGS to `git log`, because the denominator has to be stated and the three readings of
"the message corpus" genuinely differ. `pairs` measured 111 whole-tree against 5 scoped and said
both are correct for their scope and the number is meaningless without it.

THE CLASSES, AND WHY THERE ARE FIVE AND NOT FOUR. A claim is a thing that LOOKS like one -- the
shapes are a regex list, which is doctrine 1 clause (c) and not an exemption -- and each is
handed to the question "WHICH INSTRUMENT could settle this":

  DIFF      from the commit's own diff and tree: `msgdiff-gate.py`'s class, and the ONLY one with
            a gate behind it.
  TREE      from the tracked tree, as a MEASUREMENT: the number is written down NEXT TO ITS
            DENOMINATOR, so a reader can check it.
  MENTION   from the tracked tree, as a MENTION ONLY: the string occurs and NO line carrying it
            holds a denominator. THIS CLASS IS THE FINDING, and it is why the count is five.
  RUNTIME   only from a live measurement: a pid. `kill -0` settles it today and never again.
  NOTHING   from nothing at all: not in any tracked file. NOT A CLAIM ABOUT THE TREE -- a claim
            about a measurement someone took and did not write down.

WHY `MENTION` EXISTS, MEASURED, AND IT IS NOT A DETAIL. `41%` occurs in 20 lines across 10
tracked files and **ZERO** of those 20 lines carries a denominator. Every one is a REPORT ABOUT
THE CLAIM -- "the 41% is not in the tree", "41% lives only in the task prompt", "41% has zero
cites to move". A census that classified a percentage by "does the string occur anywhere
tracked" would call `41%` the BEST-corroborated number in the corpus when it is the one number
with no measurement behind it at all. A MENTION IS NOT WEAKER EVIDENCE THAN A MEASUREMENT; IT IS
THE SIGN THAT PRIOR READERS ALREADY FAILED TO FIND ONE.

ONE INDEX PER SHAPE, BUILT ONCE. The artefact corpus is HEAD's tree whatever the MESSAGE scope
is, so three scopes cost one index. `git grep` exits 1 on NO match, which is an answer here and
not a failure.

Writes `census.rows`, `pct.rows`, `pid.rows`, `detail.rows`, `mentions.rows`.
"""
import os
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent

# THE SCOPES: args to `git log`, nothing else. Every number below is printed with its scope in
# the SAME SENTENCE.
SCOPES = {
    "whole-tree": [],
    "since-2026-10-06T12:00": ["--since=2026-10-06T12:00"],
    "author=tinybendygrad": ["--author=tinybendygrad"],
}

# ---- the claim shapes -------------------------------------------------------------------
PCT = re.compile(r"(?<![\w.])(\d{1,3}(?:\.\d+)?)\s*%")
RATIO = re.compile(r"(?<![\w.])(\d{1,7})\s+(?:of|out of|/)\s+(\d{1,7})\b(?!\s*%)")
PID = re.compile(r"(?<![\w-])(?:pid|PID)\s*[:=]?\s*(\d{2,7})\b")
VERSION = re.compile(r"(?<![\w-])v?(\d+\.\d+\.\d+)(?![\w-])")
CONFIG_KEY = re.compile(r"`([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_-]*){1,4})`")
PATH = re.compile(r"[A-Za-z0-9_./-]+(?:\.(?:py|bend|md|rows|out|err|tsv|json|sh|mjs|js|ts|tsx|c))\b")
FILECOUNT = re.compile(r"(?:(?P<a>\d+)\s+(?:files?|paths?)\s+(?:changed|deleted|added|removed"
                       r"|touched)\b)|(?:(?:changed|deleted|added|removed|touched)\s+"
                       r"(?P<b>\d+)\s+(?:files?|paths?)\b)", re.I)

# A DENOMINATOR AS WRITTEN: a pair of numbers bound to each other. This is the whole definition
# of "this number was measured and written down", and it is the line the TREE/MENTION split
# reads. A version and a config key are their own text and are not split this way.
DENOMINATOR = re.compile(r"\d[\d,]*\s*(?:of|/)\s*\d[\d,]*|\(\s*[\d,]+\s*/\s*[\d,]+\s*\)"
                         r"|out of\s*\d", re.I)

# THE SHAPES THAT NEED A TRACKED-FILE LOOKUP, AND WHY THEY ARE GREPPED IN THREE BATCHES. One
# alternation over all 1796 needles builds a pattern PCRE must try at every position in 6454
# files; MEASURED, the shapes are cheap alone (2.3 s pct, and the keyword shape is bounded by its
# 491 needles) and the total is minutes. Three batches of one shape each is the same answer in a
# fraction of the time, and the batch boundaries are SHAPE boundaries, not arbitrary chunks.
LOOKUP_SHAPES = ("pct", "ratio", "version_config")


def git(*args, check=True):
    r = subprocess.run(["git", "--no-optional-locks", "-C", str(ROOT), *args],
                       capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: rc={r.returncode}: {r.stderr.strip()}")
    return r


def messages(args):
    """(sha, body) per commit in a scope. NUL/SOH framed so no body can split a record."""
    res = []
    for rec in git("log", "--format=%H%x00%B%x01", *args).stdout.split("\x01"):
        if "\x00" in rec:
            sha, body = rec.split("\x00", 1)
            res.append((sha.strip(), body))
    return res


def tracked_paths():
    """Every path in HEAD's tree: the universe a denominator may live in."""
    return set(git("ls-tree", "-r", "--name-only", "HEAD").stdout.splitlines())


def pid_alive(pid):
    """Does `pid` exist RIGHT NOW. The only resolver a pid has, and it is a LIVE one -- which is
    why the class is irreducible rather than impossible."""
    try:
        os.kill(int(pid), 0)
    except (ProcessLookupError, ValueError):
        return False
    except PermissionError:
        return True
    return True


def denominator_needles(kind, match):
    """The strings that, if a TRACKED FILE held one, would be this claim's denominator.

    A percentage's denominator is not its digits -- `29` is everywhere -- it is `29%` written
    down. A ratio's is the pair, in EITHER of the two spellings this corpus uses (`84 of 140`
    and `84/140`), because a denominator written in the other spelling is still a denominator."""
    if kind == "pct":
        return [f"{match}%"]
    if kind == "ratio":
        n, d = match
        return [f"{n} of {d}", f"{n}/{d}", f"{d} of {n}", f"{d}/{n}"]
    return [match]


def _pattern(needle):
    """How the needle would be WRITTEN in a tracked file. It differs from the needle on purpose:
    `29%` must be findable as `29%` and must NOT match inside `129%`."""
    if needle.endswith("%"):
        return re.escape(needle[:-1]) + r"\s*%"
    if " of " in needle:
        a, b = needle.split(" of ")
        return re.escape(a) + r"\s+of\s+" + re.escape(b)
    if "/" in needle:
        a, b = needle.split("/")
        return re.escape(a) + r"\s*/\s*" + re.escape(b)
    return re.escape(needle)


def build_index(patterns):
    """needle -> [(path, line_text)], by ONE `git grep -P` over an ALTERNATION.

    FOUR FORMS WERE MEASURED, AND THE COST OF THE FIRST THREE IS THE POINT:

      one `git grep -F -f needles` per needle, parsing LINES      -- did not finish in 15 minutes
      one `git grep -P -e pat` PER needle                          -- MEASURED 163.5 s for 152 pct
      one `git grep -P -e '(?:a|b|c)'`, RE-SCANNING the pattern list per output line
                                                                    -- MEASURED 186.6 s for 491 kw
      ONE `git grep -P -e '(?:a|b|c)'`, ONE compiled alternation, ONE dict lookup per hit
                                                                    -- MEASURED 1.6 s for 152 pct

    `-o` IS DELIBERATELY ABSENT, and that is what `DENOMINATOR` needs: with it git prints only
    the matched text and the LINE is gone, and the line is the thing that says whether the
    number was MEASURED or merely MENTIONED. Without it git prints `path:lineno:line` and one
    compiled alternation attributes every needle on that line.

    LONGEST-FIRST IS LOAD-BEARING. `re` alternation is LEFTMOST-FIRST, not longest: with
    `29|129` the `29` branch matches the first two digits of `129` and the claim is credited to
    the wrong needle. Sorting by pattern length, descending, removes the class.

    THE HIT->NEEDLE MAP IS BUILT, NOT SEARCHED. Re-scanning the order per hit is the 186.6 s
    form; a dict keyed on the pattern with whitespace collapsed is the 1.6 s form, and the key
    must be collapsed because a pattern ending in a whitespace class prints a hit that differs
    from the needle by trailing space.

    `-F` IS NOT USABLE HERE: it has no lookbehind, and matching `29%` inside `129%` is exactly
    the false positive this measures."""
    idx = {n: [] for n in patterns}
    if not patterns:
        return idx
    order = sorted(patterns, key=lambda n: -len(patterns[n]))
    rx = "(?:" + "|".join(f"(?:{patterns[n]})" for n in order) + ")"
    prx = re.compile(rx)
    by_hit = {re.sub(r"\s+", " ", patterns[n]): n for n in order}
    res = git("grep", "-P", "-I", "-n", "-e", rx, "--", check=False)
    for line in res.stdout.splitlines():
        path, sep1, rest = line.partition(":")
        _lineno, sep2, text = rest.partition(":")
        if not sep1 or not sep2:
            continue                        # a path with no line number is not a grep hit
        for hit in {re.sub(r"\s+", " ", m.group()) for m in prx.finditer(text)}:
            n = by_hit.get(hit)
            if n is not None:
                idx[n].append((path, text))
    return idx


def split_mentions(entries):
    """(measured, mentioned): the (path, line) pairs that CARRY A DENOMINATOR, and the pairs
    that merely NAME the number. THIS SPLIT IS WHAT THE CENSUS TURNS ON."""
    ok = [e for e in entries if DENOMINATOR.search(e[1])]
    return ok, [e for e in entries if not DENOMINATOR.search(e[1])]


def claims_of(body):
    """Every (kind, match, context) claim in one body, in ONE pass over the shapes above."""
    res = []
    for rx, kind in ((PCT, "pct"), (RATIO, "ratio"), (PID, "pid"), (VERSION, "version"),
                     (CONFIG_KEY, "config"), (PATH, "path"), (FILECOUNT, "filecount")):
        for m in rx.finditer(body):
            if kind == "ratio":
                val = (m.group(1), m.group(2))
            elif kind == "config":
                if "." not in m.group(1):
                    continue
                val = m.group(1)
            elif kind == "filecount":
                val = m.group()
            else:
                val = m.group(1) if m.groups() else m.group()
            ctx = " ".join(body[max(0, m.start() - 70):m.end() + 30].split())
            res.append((kind, val, m.start(), ctx))
    return res


def classify(kind, match, paths, idx):
    """(class, evidence). The order IS the definition and it is the order of what an instrument
    can do: DIFF is the cheapest resolver and is asked first; RUNTIME beats NOTHING because a
    live `kill -0` DOES settle a pid -- which is why that class is IRREDUCIBLE rather than
    impossible, and why a third instrument aimed at it would have something to say for exactly as
    long as the process lives."""
    if kind == "filecount":
        return "DIFF", "msgdiff-gate.py's COUNT lane: the diff holds the file count"
    if kind == "path":
        return "TREE", f"tracked at HEAD={match in paths}"
    if kind == "pid":
        return "RUNTIME", f"pid {match} alive_now={pid_alive(match)}"
    measured, mentioned = [], []
    for n in denominator_needles(kind, match):
        mnt = idx.get(n, [])
        measured += split_mentions(mnt)[0]
        mentioned += split_mentions(mnt)[1]
    if measured:
        paths_seen = sorted({p for p, _ in measured})
        return "TREE", (f"{len(measured)} tracked line(s) carry a DENOMINATOR, "
                        f"e.g. {paths_seen[0]}")
    if mentioned:
        paths_seen = sorted({p for p, _ in mentioned})
        return "MENTION", (f"{len(mentioned)} tracked line(s) NAME the number and NONE carries "
                            f"a denominator, e.g. {paths_seen[0]}")
    want = " or ".join(repr(n) for n in denominator_needles(kind, match))
    return "NOTHING", f"no tracked file contains {want}"


def census(scope_args, paths, idx):
    recs = messages(scope_args)
    by_class, by_shape, per_msg, detail = Counter(), Counter(), Counter(), []
    for sha, body in recs:
        seen = set()
        for kind, match, _i, ctx in claims_of(body):
            cls, why = classify(kind, match, paths, idx)
            by_class[cls] += 1
            by_shape[(kind, cls)] += 1
            seen.add(cls)
            if cls in ("NOTHING", "MENTION", "RUNTIME"):
                detail.append(f"{sha[:12]}\t{kind}\t{match}\t{cls}\t{why}\t{ctx}")
        for c in seen:
            per_msg[c] += 1
    return recs, by_class, by_shape, per_msg, detail


# ---------------------------------------------------------------- the plant
PLANTS = {
    # claim -> the class it MUST land in, and what would make the plant prove nothing
    "00b101574": ("DIFF", "the one real msgdiff defect: a deletion the diff does not witness"),
    "2368": ("RUNTIME", "the dead jj server AGENTS.md names; a live measurement, never in the diff"),
    "41%": ("MENTION", "20 tracked occurrences, ZERO with a denominator -- a mention, not a "
                        "measurement, and the whole reason the class exists"),
    "0.17-0.40%": ("TREE", "a ratio-of-a-run written down beside its figures: it MUST land in "
                           "TREE, or the DENOMINATOR rule is firing on nothing"),
}


def _plant(idx, paths):
    """FOUR REAL CLAIMS, THREE SCOPES OF CHECK, AND THE ASSERTION THAT MATTERS MOST: a plant
    that cannot FAIL is not a plant. Each entry names the class the claim MUST land in; a class
    that differs is a named failure, not a warning.

    THE FOURTH IS THE ONE THAT MAKES THE FIRST THREE MEANINGFUL. `41%` MENTION and `0.17-0.40%`
    TREE are the SAME shape differing only in whether a denominator sits beside the number, so
    between them they pin both sides of the split. A `DENOMINATOR` regex that matched nothing
    would make every percentage MENTION and this plant would be green on a census that calls the
    whole corpus unmeasured."""
    bad = []
    print("--plant: four real claims, the class each MUST land in")
    for text, (want, why) in PLANTS.items():
        body = f"{text} {text}"                    # a claim is found by shape, not by position
        hits = [(k, m) for k, m, _i, _c in claims_of(body)]
        if not hits:
            bad.append(f"{text!r}: no shape matched it at all -- the shapes cannot see this claim")
            print(f"  {text:<14} NO-SHAPE   want {want}")
            continue
        got = {classify(k, m, paths, idx)[0] for k, m in hits}
        ok = want in got
        bad += [] if ok else [f"{text!r} landed in {sorted(got)}, expected {want}"]
        print(f"  {text:<14} {sorted(got)[0] if len(got) == 1 else sorted(got)!s:<14} "
              f"want {want:<8} {'OK' if ok else 'RED'}   {why}")
    # THE BLIND SPOT, ASSERTED: a percentage that is NOWHERE at all must not be MENTION.
    absent = "7.77%"
    cls = classify("pct", "7.77", paths, idx)[0]
    ok = cls == "NOTHING"
    bad += [] if ok else [f"{absent} classified {cls}, expected NOTHING"]
    print(f"  {absent:<14} {cls:<14} want NOTHING   {'OK' if ok else 'RED'}   "
          f"the blind spot: a number in no tracked file is not a mention")
    print(f"--plant: {'all states OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return bad


def main(argv):
    paths = tracked_paths()
    recs_all = messages([])
    # ONE pass to collect the needles, then one index per SHAPE. The artefact corpus is HEAD's
    # tree whatever the MESSAGE scope is, so three scopes cost one index.
    needles = {s: set() for s in LOOKUP_SHAPES}
    for _sha, body in recs_all:
        for kind, match, _i, _c in claims_of(body):
            if kind in ("pct", "ratio", "version", "config"):
                batch = "pct" if kind == "pct" else ("ratio" if kind == "ratio" else "version_config")
                needles[batch].update(denominator_needles(kind, match))
    idx = {}
    for batch in LOOKUP_SHAPES:
        pats = {n: _pattern(n) for n in sorted(needles[batch])}
        t0 = len(idx)
        idx.update(build_index(pats))
        print(f"index[{batch}]: {len(pats)} needles -> {len(idx) - t0} keyed")
    print(f"artefacts: {len(paths)} tracked paths, {len(recs_all)} commits in the whole tree")

    if "--plant" in argv:
        return 1 if _plant(idx, paths) else 0

    lines, grand = [], Counter()
    details = []
    for name, args in SCOPES.items():
        recs, by_class, _shape, per_msg, detail = census(args, paths, idx)
        n = len(recs)
        lines.append(f"{name}\tcommits={n}\tclaims={sum(by_class.values())}\t"
                     f"DIFF={by_class['DIFF']}\tTREE={by_class['TREE']}\t"
                     f"MENTION={by_class['MENTION']}\tRUNTIME={by_class['RUNTIME']}\t"
                     f"NOTHING={by_class['NOTHING']}\tcommits_MENTION={per_msg['MENTION']}\t"
                     f"commits_NOTHING={per_msg['NOTHING']}\t"
                     f"commits_RUNTIME={per_msg['RUNTIME']}")
        print(lines[-1])
        grand.update(by_class)
        details += [f"{name}\t{d}" for d in detail]
    (HERE / "census.rows").write_text("\n".join(lines) + "\n")
    (HERE / "detail.rows").write_text("\n".join(details) + "\n")

    # ---- the two questions asked BY NAME -------------------------------------------------
    def pct_pid_rows(recs):
        pr, pidr = [], []
        for sha, body in recs:
            for kind, match, _i, ctx in claims_of(body):
                if kind == "pct":
                    cls, why = classify(kind, match, paths, idx)
                    pr.append(f"{sha[:12]}\t{match}\t{cls}\t{why}\t{ctx}")
                elif kind == "pid":
                    pidr.append(f"{sha[:12]}\t{match}\talive_now={pid_alive(match)}\t{ctx}")
        return pr, pidr

    since = messages(SCOPES["since-2026-10-06T12:00"])
    pct_rows, pid_rows = pct_pid_rows(since)
    (HERE / "pct.rows").write_text("\n".join(pct_rows) + "\n")
    (HERE / "pid.rows").write_text("\n".join(pid_rows) + "\n")
    wp, wr = pct_pid_rows(recs_all)
    (HERE / "pct-whole.rows").write_text("\n".join(wp) + "\n")
    (HERE / "pid-whole.rows").write_text("\n".join(wr) + "\n")

    def n_class(rows, cls):
        return sum(1 for r in rows if f"\t{cls}\t" in r)

    print(f"since-2026-10-06T12:00: percentage claims={len(pct_rows)} -- "
          f"TREE(measured)={n_class(pct_rows, 'TREE')} "
          f"MENTION={n_class(pct_rows, 'MENTION')} NOTHING={n_class(pct_rows, 'NOTHING')}")
    print(f"whole-tree: percentage claims={len(wp)} -- "
          f"TREE(measured)={n_class(wp, 'TREE')} MENTION={n_class(wp, 'MENTION')} "
          f"NOTHING={n_class(wp, 'NOTHING')}")
    print(f"whole-tree: pid citations={len(wr)}, "
          f"{sum(1 for r in wr if 'alive_now=False' in r)} whose pid is NOT alive now "
          f"({sum(1 for r in wr if 'alive_now=False' in r)}/{len(wr)})")
    print(f"whole-tree: grand total {dict(grand)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))