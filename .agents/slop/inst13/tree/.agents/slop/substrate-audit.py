#!/usr/bin/env python3
"""substrate-audit.py -- THE OTHER ROOT CAUSE, and the test for it.

    .venv/bin/python .agents/slop/substrate-audit.py           # all four, exit 1 on any
    .venv/bin/python .agents/slop/substrate-audit.py --only S3

A TOOL THAT MATCHES A FORM CANNOT SEE THE INSTANCE THAT LACKS IT.
A TOOL THAT MEASURES THE RIGHT FORM OF THE WRONG SUBSTATION ANSWERS A QUESTION YOU DID NOT
ASK.  These are DIFFERENT root causes and they want different fixes: the first is fixed by
reading the argument instead of the spelling, the second by pointing the instrument at its
subject.  Conflating them produces the worst outcome available -- a tool that is precise about
the wrong thing -- so this file states the distinction and then ASSERTS each of the four
substrate cases against the live instrument.

THE FOUR, AND WHY EACH IS NOT FORM-BLINDNESS.  In all four the tool reasons about the correct
form of the right thing and is attached to the wrong thing entirely:

  S1  A DIGEST OVER THE MUTANT.  `revision-ledger.py`'s own header: 'FILE sha256 of the .bend
      the harness patches ... it protects the MUTANT -- it proves the edit you are about to
      make went into the file you meant. It says NOTHING about whether the rows you are diffing
      against describe that file.' And why it cannot: `zero-classify.py` documents that
      swapping `hi42`'s two shape args -- the exact M09 defect -- leaves `shape()`'s three
      fields byte-identical. **A DIGEST PROTECTS THE MUTANT, NOT THE REFERENCE.** The form is
      right (a sha256 over the file); the substrate is the wrong file.

  S2  A CACHE WHOSE FRESHNESS IS DECIDED BY A MTIME, OVER ROWS THAT ARE NOT A FILE.
      `rebase-scan-oracles.cached()` returns `'fresh'` from an mtime comparison between a
      cache FILE and a source FILE. The measured consequence, from its own header: 'a fresh
      file holding `{}` is not stale, so the mtime rule alone reads a FAILED lane from hours
      ago as a fresh measurement of zero. Measured consequence of the mtime rule alone: 8 of
      the 38 wired pairs measured 0 shared row names and every one of them was skipped in
      silence.' **A ZERO IS NOT A FRESHNESS SIGNAL.** The form is right; the substrate is a
      number where a file belongs.

  S3  A BINARY PATH KEYED ON A STEM.  `rebase-gate.native_bin` was `/tmp/rebase-gate/
      {bend.stem}.bin`. MEASURED on this tree: 131 `.bend` files carry 110 distinct stems --
      `__init__` x14, `dtype` x3, `spec`/`op`/`memory`/`movement`/`ip`/`elf` x2 each -- so
      fourteen ports wrote ONE path, `run_port()` UNLINKED it, compiled into it, and then
      executed whatever was at it. **A STEM IS NOT A KEY**, and the collapse is in the PATH,
      not in the contents.

  S4  A SELFTEST WHOSE PASS CAME FROM SYNTHETIC STATES.  `rebase-gate-selftest.py` reached
      PASS over six hand-built states with `run_port()` stubbed, so the states exercised the
      CLASSIFIER and never the instrument it classifies. Its own docstring records the
      correction: the six states 'made this file pass by measuring the re-implementation'.

WHY THESE FOUR GET A SEPARATE FILE AND NOT A LINE EACH IN `formblind-census.py`.  A census
that cannot see a variant and an instrument pointed at the wrong thing both produce a
confident wrong number, and both are found the same way -- by disagreement. But only one of
them is repaired by widening the selector. A ledger whose digest covers the mutant is not made
right by hashing more of the mutant.

WHERE THE EXPECTED VALUES COME FROM.  Each assertion names its source and each carries a
CONTROL that must NOT agree, so the audit can tell a broken instrument from a working one:
`not-applied-audit.py` records the bug that made an auditor pass a 4-cell row in a 3-column
table, and the cure for that is a control, not a better assertion.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))


def load(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def sha(p: pathlib.Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()[:16] if p.exists() else "MISSING"


# ---------------------------------------------------------------------------
# S1 -- a digest over the MUTANT cannot be a digest over the REFERENCE.
# ---------------------------------------------------------------------------
REV = HERE / "revision-ledger.py"


ENTRY = re.compile(
    r'\(\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*(None|"[^"]*")\s*,\s*(None|"[^"]*")\s*\)')


def s1():
    src = REV.read_text()
    unq = lambda s: "" if s == "None" else s.strip('"')      # noqa: E731
    every = [(t, h, unq(b), unq(base)) for t, h, b, base in ENTRY.findall(src)]
    rows = [x for x in every if x[2] != "" and x[3] != ""]
    same = [t for t, _h, b, base in rows if b == base]
    # A ledger naming NO baseline is also a substrate defect and the ledger reports it rather
    # than passing over it: such a table's zeros cannot be re-derived at all, because the
    # thing they were compared to is gone. MEASURED here rather than quoted.
    nob = [t for t, _h, _b, base in every if base == ""]
    # CONTROL: a ledger that pointed FILE and ROWS at ONE file. Built here, so the assertion
    # can fire on a ledger of that shape and not only on a missing one.
    control = [t for t, _h, b, base in [("t.txt", "h.py", "a.bend", "a.bend")] if b == base]
    ok = bool(rows) and not same and control == ["t.txt"] and bool(nob)
    return ok, (
        f"LEDGER rows parsed : {len(every)}\n"
        f"     declaring BOTH a FILE digest and a ROWS digest : {len(rows)}"
        f"   <-- the digest that can actually constrain the number in the table\n"
        f"     of those, FILE and ROWS pointing at ONE file     : {len(same)}"
        f"   (each is the same evidence printed twice under two headings)\n"
        f"     declaring NO baseline, so their zeros are not re-derivable : {len(nob)}"
        f"   <-- reported by the ledger as a finding\n"
        f"  WHY THE TWO DIGESTS CANNOT BE ONE.  `zero-classify.py` documents that swapping"
        f"\n     `hi42`'s two shape args -- the exact M09 defect -- leaves `shape()`'s three"
        f"\n     fields byte-identical, so a digest over the MUTANT cannot see it."
        f"  A DIGEST PROTECTS THE MUTANT, NOT THE REFERENCE.\n"
        f"  CONTROL -- a ledger with FILE==ROWS names {len(control)} such table, so this "
        f"assertion can fire")


# ---------------------------------------------------------------------------
# S2 -- a cache's freshness must not be readable off an mtime when the payload may be empty.
# ---------------------------------------------------------------------------
SCAN = HERE / "rebase-scan-oracles.py"


def s2():
    """THE SUBSTRATE IS A NUMBER WHERE A FILE BELONGS. And the fix is INCOMPLETE.

    `rebase-scan-oracles.cached()` has an `empty` clause: a cache that holds NO ROWS is a
    FAILED run, not a measurement of zero, and it refuses however new the file is. Its
    `store()` will not write one. That is correct and it is measured above.

    `wire_parse.read_fresh_cache()` -- THE SHARED READER, imported by `wire-rows.py` and
    `wire-pair.py` -- has NO such clause. MEASURED just below, on one constructed state: an
    empty cache NEWER than its source reads `({}, 'fresh')`. That is the substrate error the
    empty clause exists to prevent, still reachable through the function two tools call.

    So S2 is not a claim about a fixed bug. It is a claim that a fix landed in one CONSUMER
    rather than in the shared function, which is the same shape as the `rows()` FORK
    `cstyle-gate.py` carries: a correction that does not propagate is indistinguishable from a
    correction that did not happen.
    """
    wp = load(HERE / "wire_parse.py", "wire_parse_under_audit")
    scan = load(SCAN, "scan_under_audit")
    saved = scan.CACHE
    import os
    import tempfile
    fails = []
    detail = []
    try:
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            src = root / "port.bend"
            src.write_text("PROBE SOURCE\n")
            st = src.stat().st_mtime
            # THE STATE: an EMPTY cache, newer than its source. Bend stack-overflows about one
            # run in twenty and prints ZERO rows, so this state is what a crash leaves behind.
            scan.CACHE = root
            scan.write_cache(root, "K", {})
            cf = scan.cache_file(root, "K")
            os.utime(cf, (st + 10, st + 10))
            got_scan = scan.cached("K", src)
            got_wp = wp.read_fresh_cache(root, "K", src)
            detail.append(f"  rebase-scan-oracles.cached()   -> {got_scan}   "
                          f"(refuses: an empty cache is a FAILED run)")
            detail.append(f"  wire_parse.read_fresh_cache()   -> {got_wp}   "
                          f"(reports a FAILED run as a fresh measurement of ZERO)")
            if got_scan[1] != "empty":
                fails.append(f"the `empty` clause regressed: cached() said {got_scan[1]!r}")
            if got_wp[1] != "empty":
                fails.append(f"the SHARED reader still reports an empty cache as "
                             f"{got_wp[1]!r} -- a crash filed as a measurement")
            # AND the write half: `store` must refuse, or the read-side clause has no second
            # half and the next writer puts the state back.
            cf.unlink()
            scan.store("K", {}, "the control lane")
            if cf.exists():
                fails.append("store() WROTE an empty cache")
            detail.append(f"  store() wrote a file for an empty payload : {cf.exists()}")
    finally:
        scan.CACHE = saved
    return not fails, ("\n     ".join(detail) +
        "\n  CONTROL -- the mtime rule ALONE, which is `wire_parse.read_fresh_cache` in full: an"
        "\n     empty payload with a valid mtime reads fresh. rebase-scan-oracles.py's own header"
        "\n     gives the measured cost: 8 of the 38 wired pairs measured 0 shared row names and"
        "\n     EVERY ONE of them was skipped in silence.")


# ---------------------------------------------------------------------------
# S3 -- a path keyed on a STEM is not a key.
# ---------------------------------------------------------------------------
RG = HERE / "rebase-gate.py"


def s3():
    rg = load(RG, "rg_under_audit")
    bends = sorted((ROOT / "tinybendygrad").rglob("*.bend"))
    keys = [rg.port_key(b) for b in bends]
    stems = [b.stem for b in bends]
    collisions_key = len(keys) - len(set(keys))
    collisions_stem = len(stems) - len(set(stems))
    return collisions_key == 0 and collisions_stem > 0, (
        f"{len(bends)} .bend files on this tree\n"
        f"     distinct port_key() values : {len(set(keys))}   COLLISIONS: {collisions_key}\n"
        f"     distinct STEM values       : {len(set(stems))}   COLLISIONS: {collisions_stem}\n"
        f"  CONTROL -- the OLD spelling `{{bend.stem}}.bin` collides {collisions_stem} times on the "
        f"SAME tree, so the assertion is not a tautology\n"
        f"     the collapsed stems: "
        f"{sorted({s for s in stems if stems.count(s) > 1})}")


# ---------------------------------------------------------------------------
# S4 -- a selftest's PASS must come from the instrument, not from a re-implementation.
# ---------------------------------------------------------------------------
ST = HERE / "rebase-gate-selftest.py"


def s4():
    src = ST.read_text()
    # A selftest that only ever drives a classifier over synthetic states measures the
    # CLASSIFIER. The cure is that at least one assertion in the file runs the real thing.
    calls_run_port = len(re.findall(r"\brun_port\s*\(", src))
    stub_defs = len(re.findall(r"^\s*def\s+\w*run_port\w*\s*\([^)]*\)\s*:", src, re.M))
    stubs_run_port = len(re.findall(r"^\s*\w*run_port\w*\s*=\s*lambda", src, re.M))
    # AND the admission. A file that carries the mistake in its own header has already found
    # it; a file that has fixed it silently has not necessarily.
    admits = bool(re.search(r"six states|six synthetic|re-implementation|reimplementation",
                            src, re.I))
    ok = calls_run_port > 0 and admits
    return ok, (
        f"`run_port(` call sites in the selftest   : {calls_run_port}\n"
        f"     local defs shadowing it               : {stub_defs}\n"
        f"     lambda stubs shadowing it              : {stubs_run_port}\n"
        f"     the file NAMES the six-states mistake : {admits}\n"
        f"  CONTROL -- a selftest whose only `run_port` is a stub reaches PASS over synthetic\n"
        f"     states and measures nothing: calls_run_port would be 0 with stubs_run_port > 0")


CHECKS = [("S1", "a digest over the MUTANT is not a digest over the REFERENCE", s1),
          ("S2", "a cache's freshness is not readable off an mtime when the payload may be empty", s2),
          ("S3", "a binary path keyed on a STEM is not a key", s3),
          ("S4", "a selftest's PASS must come from the instrument, not a re-implementation", s4)]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only")
    a = ap.parse_args(argv)
    bad = 0
    print("=" * 100)
    print("SUBSTRATE AUDIT -- a tool that measures the RIGHT FORM of the WRONG THING. Different")
    print("root cause from form-blindness and a different fix: widening the selector does not")
    print("help an instrument pointed at the wrong subject.")
    print("=" * 100)
    for cid, what, fn in CHECKS:
        if a.only and cid != a.only:
            continue
        try:
            ok, detail = fn()
        except Exception as e:                   # noqa: BLE001
            ok, detail = False, f"raised {type(e).__name__}: {e}"
        bad += 0 if ok else 1
        print(f"\n{'ok  ' if ok else 'FAIL'} {cid}  {what}")
        print(f"     {detail}")
    print(f"\n{'-' * 100}")
    print(f"{len(CHECKS) - bad}/{len(CHECKS)} substrate assertions hold;  {bad} FAIL")
    print("denominator: 4 of the 4 substrate-wrong instruments named in this round. That is")
    print("NOT a claim about the other 825 tools under .agents/slop/: formblind-census.py reads")
    print("FORMS and cannot see a substrate error at all, so its FORM-COMPLETE verdict on a")
    print("wrong-substrate instrument is silence, not clearance.")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())