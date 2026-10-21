#!/usr/bin/env python3
"""gates/expectcopy-gate.py -- the NO-SUBJECT-DECLARED expectation files, named.

`gates/pincensus-gate.py` counts expectation rows apart from hex pins. A row
classed NO-SUBJECT-DECLARED has no artifact the tree names. Those rows live in
files. This gate re-derives that population by loading the census modules by
path, then asks one question the census did not: is each such file a copy of
`checks/differ.py`, or a different object?

  byte-identical shadow   the file's bytes equal the flagship. A shadow is not
                          a second pin table. Judging it as the flagship would
                          double-count.
  fork                    the bytes differ. A different object.
  absent                  the path is not on disk. A dangling declaration.
                          FAIL, not a skip.

PASS means every such file is a shadow: these are copies, not a second
population. It does not mean the authored table is current. That is
`gates/pintable-gate.py`'s job, and it is not re-verdicted here.

`checks/differ.py` is the reference the copies are compared to. It is not a
member of the copy set, and it is not classed NO-SUBJECT-DECLARED. A file is
not a shadow of itself.

The census count is printed as measured. A copy is not dropped to keep a
previous number.
"""
import argparse
import importlib.util
import io
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FLAGSHIP = "checks/differ.py"
# The 1755e2338 reading. A comparison point, not a filter: if the census moves,
# the new count is printed and every file is still classified.
PRIOR = 85

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5
VERDICT = {PASS: "PASS", FAIL: "FAIL", REFUSED: "REFUSED", SKIP: "SKIP", DEAD: "DEAD"}
PASS_LINE = (
    "PASS: these are copies, not a second population, not a verdict that the flagship is current")


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def differ_running():
    """-> process lines whose args name `differ.py`, grep excluded. A hit means
    `runs/graphcmp/` may be mid-write. This gate does not read it either way."""
    r = subprocess.run(["ps", "-Ao", "pid,args"], capture_output=True, text=True)
    return [ln.strip() for ln in r.stdout.splitlines()
            if "differ.py" in ln and "grep" not in ln.split()]


def corpus_of(pop, root, scratch):
    """The census's own walk. Scratch has no git tree, so it is not intersected
    with `ls-tree`; the live tree is, which is the bound `pincensus-pop.load` uses.
    `__undecodable__` is a count the walker stashes in the dict, not a file."""
    if scratch:
        disk = pop.walk_text(root)
        disk.pop("__undecodable__", None)
        return disk, {t: pop.host_of(v) for t, v in disk.items()}
    loaded = pop.load(root)
    return loaded["corpus"], pop.hosts(loaded["corpus"])


def rows_of(root, scratch=False):
    """-> expectation rows, currency included.

    THE MODULES ARE LOADED BY PATH, and the class is theirs: `expectations`
    drops a hex value, `resolve` joins a table to its artifact, and
    `expectation_currency` is what says NO-SUBJECT-DECLARED. This function does
    not execute the defining modules. Executing `checks/differ.py` is running
    it, and the currency of a missing subject does not depend on that
    execution -- it depends on the binding the file already contains.
    """
    pop = load("expectcopy_pop", "pincensus-pop.py")
    tab = load("expectcopy_tab", "pintable-pop.py")
    bind = load("expectcopy_bind", "bind-subject.py")
    pc = load("expectcopy_pc", "pincensus-gate.py")
    corpus, host = corpus_of(pop, root, scratch)
    code = {t: pop.code_lines(corpus[t], host[t]) for t in corpus if host.get(t) != "prose"}
    decls = bind.declarations(corpus, code)
    empty = {"subjects": {}, "artifacts": {}, "run-dirs": [], "at": {}}
    exps = tab.expectations(tab.tables(tab.bindings(corpus, host), pop.PIN_NAME), pop.HEX)
    rows = []
    for e in exps:
        decl = decls.get(e["file"], empty)
        resolved = bind.resolve(e["name"], decl)
        subject = pc.expectation_subject(resolved, decl, e["key"])
        verdict = pc.expectation_currency(e["value"], subject, root, root)[0]
        rows.append({"file": e["file"], "name": e["name"], "key": e["key"],
                     "currency": verdict})
    return rows


def classify(rows, root):
    """-> the copy set. The flagship is removed before any file is judged, so
    it cannot be classed as a copy of itself."""
    nosub = [r for r in rows if r["currency"] == "NO-SUBJECT-DECLARED"]
    by = {}
    for r in nosub:
        by[r["file"]] = by.get(r["file"], 0) + 1
    ref_rows = by.pop(FLAGSHIP, 0)
    ref_path = os.path.join(root, FLAGSHIP)
    result = {
        "rows": rows, "nosubject": len(nosub), "by": by, "reference": FLAGSHIP,
        "reference-rows": ref_rows, "reference-class": "REFERENCE", "copies": [],
        "refused": None,
    }
    if not os.path.isfile(ref_path):
        result["refused"] = f"{FLAGSHIP} is absent, so a copy cannot be compared to it"
        return result
    ref = open(ref_path, "rb").read()
    for rel, n in sorted(by.items()):
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            kind, note = "ABSENT", "absent"
        elif open(path, "rb").read() == ref:
            kind, note = "SHADOW", "byte-identical shadow of " + FLAGSHIP
        else:
            kind, note = "FORK", "differs from " + FLAGSHIP
        result["copies"].append({"path": rel, "rows": n, "kind": kind, "note": note})
    accounted = ref_rows + sum(c["rows"] for c in result["copies"])
    if accounted != len(nosub):
        result["refused"] = f"accounting {accounted} != NO-SUBJECT-DECLARED {len(nosub)}"
    return result


def exit_of(result):
    if result.get("refused"):
        return REFUSED
    if not result["rows"]:
        return DEAD
    kinds = [c["kind"] for c in result["copies"]]
    if any(k in ("FORK", "ABSENT") for k in kinds):
        return FAIL
    if kinds and all(k == "SHADOW" for k in kinds):
        return PASS
    if not kinds:
        return REFUSED
    return FAIL


def report(result, out, live=None):
    n = result["nosubject"]
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    out.write(f"expectcopy-gate: NO-SUBJECT-DECLARED rows={n}")
    if n != PRIOR:
        out.write(f" (moved from {PRIOR}; not dropped to keep {PRIOR})\n")
    else:
        out.write(f" (did not move from {PRIOR})\n")
    out.write(f"  generated {stamp}\n")
    if live is not None:
        out.write(f"  differ.py running: {'yes ' + live[0] if live else 'no'}\n")
    out.write(f"  REFERENCE {result['reference']} rows={result['reference-rows']} "
              f"class={result['reference-class']} "
              f"(not classed NO-SUBJECT-DECLARED; not re-verdicted)\n")
    if result.get("refused"):
        out.write(f"  REFUSED: {result['refused']}\n")
    for c in result["copies"]:
        out.write(f"  {c['kind']:6} {c['path']} rows={c['rows']} {c['note']}\n")
    kinds = {}
    for c in result["copies"]:
        kinds[c["kind"]] = kinds.get(c["kind"], 0) + 1
    out.write(f"  shadows={kinds.get('SHADOW', 0)} forks={kinds.get('FORK', 0)} "
              f"absent={kinds.get('ABSENT', 0)}\n")
    code = exit_of(result)
    if code == PASS:
        out.write(f"  {PASS_LINE}\n")
    elif code == FAIL:
        out.write("  FAIL: a fork or an absent path is in the set. "
                  "A fork is a different object. An absent path is not a skip.\n")
    elif code == DEAD:
        out.write("  DEAD: the expectation population emitted no rows\n")
    elif code == REFUSED:
        out.write("  REFUSED: the copy comparison was not made\n")
    out.write(f"expectcopy-gate: exit {code} ({VERDICT[code]})\n")
    return code


def _write(root, rel, raw):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(raw)
    return path


def one_byte(raw):
    """-> `raw` with one comment byte changed, or None. The file must still
    parse, or the fork leaves the population and the plant compares nothing."""
    i = raw.find(b"# ")
    if i < 0 or i + 1 >= len(raw):
        return None
    return raw[:i + 1] + b"X" + raw[i + 2:]


def _kind(result, rel):
    got = [c for c in result["copies"] if c["path"] == rel]
    return got[0]["kind"] if len(got) == 1 else None


def plant():
    """Attack copies. The live flagship is opened for reading and never written.

    FOUR ARMS, and each one can fail on its own:

      SHADOW   a byte-identical copy is a shadow, and the gate exits PASS.
      FORK     one byte changed is a fork, and the gate exits FAIL.
      ABSENT   the path the population named is removed before the compare.
               FAIL, not SKIP.
      CONTROL  the input classes the flagship NO-SUBJECT-DECLARED (that is the
               census's currency for `PINS`, which names no artifact). This
               gate does not. A control that never saw the flagship in the
               input compared nothing.
    """
    live_path = os.path.join(ROOT, FLAGSHIP)
    before = open(live_path, "rb").read()
    flipped = one_byte(before)
    if flipped is None or flipped == before or len(flipped) != len(before):
        print("expectcopy-plant: DEAD -- one byte could not be changed", file=sys.stderr)
        return DEAD
    copy_rel = os.path.join(".agents", "slop", "plant", "checks", "differ.py")
    base = tempfile.mkdtemp(prefix="expectcopy-plant-")
    try:
        shadow_root, fork_root, absent_root, control_root = (
            os.path.join(base, name) for name in ("shadow", "fork", "absent", "control"))
        for dest in (shadow_root, fork_root, absent_root, control_root):
            _write(dest, FLAGSHIP, before)
        _write(shadow_root, copy_rel, before)
        _write(fork_root, copy_rel, flipped)
        _write(absent_root, copy_rel, before)
        shadow_rows = rows_of(shadow_root, scratch=True)
        fork_rows = rows_of(fork_root, scratch=True)
        absent_rows = rows_of(absent_root, scratch=True)
        control_rows = rows_of(control_root, scratch=True)
        os.remove(os.path.join(absent_root, copy_rel))
        s = classify(shadow_rows, shadow_root)
        f = classify(fork_rows, fork_root)
        a = classify(absent_rows, absent_root)
        c = classify(control_rows, control_root)
        bad = []
        after = open(live_path, "rb").read()
        if after != before:
            bad.append("the live flagship changed")
        if not any(r["file"] == FLAGSHIP and r["currency"] == "NO-SUBJECT-DECLARED"
                   for r in shadow_rows):
            bad.append("VACUOUS: the flagship was not NO-SUBJECT-DECLARED in the input, "
                       "so the control compared nothing")
        if not any(r["file"] == copy_rel and r["currency"] == "NO-SUBJECT-DECLARED"
                   for r in fork_rows):
            bad.append("the one-byte copy left the population, so the fork was not tested")
        if not any(r["file"] == copy_rel for r in absent_rows):
            bad.append("the absent path was never in the population, so the arm compared nothing")
        for label, result in (("SHADOW", s), ("FORK", f), ("ABSENT", a), ("CONTROL", c)):
            if any(copy["path"] == FLAGSHIP for copy in result["copies"]):
                bad.append(f"{label}: {FLAGSHIP} was classed as a copy")
            if result["reference-class"] != "REFERENCE":
                bad.append(f"{label}: the flagship class is {result['reference-class']}")
        if _kind(s, copy_rel) != "SHADOW" or exit_of(s) != PASS:
            bad.append(f"SHADOW did not fire ({_kind(s, copy_rel)}, exit {exit_of(s)})")
        if _kind(f, copy_rel) != "FORK" or exit_of(f) != FAIL:
            bad.append(f"FORK did not fire ({_kind(f, copy_rel)}, exit {exit_of(f)})")
        if _kind(a, copy_rel) != "ABSENT" or exit_of(a) != FAIL:
            bad.append(f"ABSENT did not fire ({_kind(a, copy_rel)}, exit {exit_of(a)})")
        if exit_of(a) == SKIP:
            bad.append("ABSENT exited SKIP")
        if exit_of(s) == exit_of(f):
            bad.append("VACUOUS: shadow and fork exited the same")
        if c["copies"]:
            bad.append(f"CONTROL had copies: {c['copies']}")
        buf = io.StringIO()
        report(s, buf)
        if PASS_LINE not in buf.getvalue():
            bad.append("the PASS line does not say these are copies")
        if "flagship is current" in buf.getvalue() and "not a verdict" not in buf.getvalue():
            bad.append("PASS was reported as a currency verdict")
        print(f"expectcopy-plant: copy {copy_rel}")
        print(f"  SHADOW  kind={_kind(s, copy_rel)} exit={exit_of(s)} ({VERDICT[exit_of(s)]})")
        print(f"  FORK    kind={_kind(f, copy_rel)} exit={exit_of(f)} ({VERDICT[exit_of(f)]}) "
              f"one byte at offset {before.find(b'# ')}")
        print(f"  ABSENT  kind={_kind(a, copy_rel)} exit={exit_of(a)} ({VERDICT[exit_of(a)]}) "
              f"not-skip={exit_of(a) != SKIP}")
        print(f"  CONTROL flagship-in-copies={any(copy['path'] == FLAGSHIP for copy in c['copies'])} "
              f"class={c['reference-class']} input-nosubject="
              f"{sum(1 for r in control_rows if r['file'] == FLAGSHIP and r['currency'] == 'NO-SUBJECT-DECLARED')}")
        print("  live flagship: untouched" if after == before else "  live flagship: CHANGED")
        if bad:
            print("expectcopy-plant: FAIL -- " + "; ".join(bad), file=sys.stderr)
            return FAIL
        print("expectcopy-plant: a shadow passes, a fork fails, an absent path fails, "
              "and the flagship is not classed NO-SUBJECT-DECLARED")
        return PASS
    finally:
        shutil.rmtree(base, ignore_errors=True)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--scratch", action="store_true")
    ap.add_argument("--plant", action="store_true")
    args = ap.parse_args(argv)
    if args.plant:
        return plant()
    live = differ_running()
    result = classify(rows_of(args.root, scratch=args.scratch), args.root)
    return report(result, sys.stdout, live=live)


if __name__ == "__main__":
    sys.exit(main())
