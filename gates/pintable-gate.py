#!/usr/bin/env python3
"""gates/pintable-gate.py -- THE EXPECTATION ROWS, AS THEIR OWN DENOMINATOR.

THE OLD NUMBER AND THE NEW ONE ARE NOT THE SAME COUNT.

`gates/pincensus-pop.py`'s value token is a `>=7` lowercase hex run. Its census counts
content addresses. `checks/differ.py`'s `PINS` holds `"graphs": "34"` and
`"selfcheck": "# SELFCHECK: OK"`: none of those values is an address, so the flagship
table is invisible to that number. Widening the hex rule would make the old number mean
something else. This gate does not widen it. It reports the expectation rows beside it.

THE DENOMINATOR IS THE AUTHORED `PINS` TABLE, NOT EVERY COPY OF IT. A path that ends in
`/<authored path>` is a shadow (a retained copy under `.agents/slop/`). A same-named table
that is neither the authored file nor a shadow of it is an orphan copy. Shadows and orphans
are printed and not judged: comparing a retained copy's expectations to the live run would
red this gate for a tree the copy is not about, and folding those rows into 17 would change
what 17 means.

WHAT GOES RED, AND THE TWO ARE INDEPENDENT:

  * a row's scan (what `ast` sees) and its declaration (what executing the module holds)
    disagree. A `PINS["graphs"] = "35"` after the literal is this case.
  * a declared expectation row is absent from the artifact the table names, or the
    artifact's value differs. Absence is not agreement. A wrong value is not current.

THE ARTIFACT IS DISCOVERED, NOT LISTED. An `_ARTIFACT` binding wins (`REPRO_PINS` takes
`REPRO_ARTIFACT`, via `gates/bind-subject.py`, loaded by path). A table with no such
binding takes the bare filename a function that NAMES the table passes to a read. The run
directory is the `runs/...` literal `bind-subject` already extracts from code. A live
`differ.py` is not read: `ps` first, and a running writer is REFUSED rather than sampled.

`RUN HEALTH : OK` is printed only when all of these rows are green. A census that cannot
see them cannot check the thing that line depends on.
"""
import argparse
import ast
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

PASS, FAIL, REFUSED, DEAD = 0, 1, 3, 5
FLAGSHIP = "PINS"


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def differ_running():
    """-> process lines whose args name `differ.py`. The grep is excluded, which is the
    brief's own probe. A hit means the artifact may be mid-write and must not be read."""
    r = subprocess.run(["ps", "-Ao", "pid,args"], capture_output=True, text=True)
    return [ln.strip() for ln in r.stdout.splitlines()
            if "differ.py" in ln and "grep" not in ln.split()]


def under_live_runs(path):
    live = os.path.join(ROOT, "runs")
    try:
        return os.path.commonpath([os.path.abspath(path), live]) == live
    except ValueError:
        return False


def corpus_of(pop, root, scratch):
    if not scratch:
        loaded = pop.load(root)
        corpus = loaded["corpus"]
        return corpus, pop.hosts(corpus), loaded["counts"]
    files = {}
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d != ".git"]
        for fn in fns:
            p = os.path.join(dp, fn)
            try:
                files[os.path.relpath(p, root)] = open(p, "rb").read().decode("utf-8")
            except (OSError, UnicodeDecodeError):
                continue
    return files, {t: pop.host_of(v) for t, v in files.items()}, {"scratch": len(files)}


def kv_of(text):
    """`unhealthy()`'s own parse: split on the first `=`, do not strip. Nine of the
    seventeen values contain spaces; a strip would be a second parser."""
    out = {}
    for ln in text.splitlines():
        if "=" not in ln:
            continue
        k, v = ln.split("=", 1)
        out[k] = v
    return out


def _bare_filename(node):
    if not isinstance(node, ast.Constant) or not isinstance(node.value, str):
        return None
    s = node.value
    if "/" in s or " " in s or "." not in s or s.startswith(".") or "*" in s:
        return None
    return s


def filenames_naming(text, name):
    """-> bare filenames a function that loads `name` actually reads.

    A docstring is not a read, and neither is a sentence. The two shapes that are a read
    in this tree are `D / "file"` and `text("file")`. Zero means the reader names none;
    more than one means the caller must not pick."""
    try:
        tree = ast.parse(text)
    except (SyntaxError, ValueError, RecursionError, MemoryError):
        return None
    found = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        if not any(isinstance(n, ast.Name) and n.id == name for n in ast.walk(node)):
            continue
        doc = ast.get_docstring(node)
        for n in ast.walk(node):
            if isinstance(n, ast.BinOp) and isinstance(n.op, ast.Div):
                s = _bare_filename(n.right)
            elif isinstance(n, ast.Call):
                s = next((got for a in n.args if (got := _bare_filename(a))), None)
            else:
                continue
            if s is None or s == doc:
                continue
            if s not in found:
                found.append(s)
    return found


def artifact_of(name, text, decl, bind):
    """-> (relpath, note) or (None, why).

    An `_ARTIFACT` binding is the tree's own name for the file, and it wins. The reader
    scan is only the fallback for a table that has no such binding -- `PINS` names its
    file inside `unhealthy()`, not in a binding. Unioning the two made `REPRO_PINS` look
    ambiguous: its binding says `D0-repro.txt` and its docstring mentions other files."""
    resolved = bind.resolve(name, decl)
    if resolved and resolved["kind"] == "ARTIFACT":
        named, how = [resolved["value"]], "named by an _ARTIFACT binding"
    else:
        read = filenames_naming(text, name)
        if read is None:
            return None, "the defining file did not parse, so its reader could not be read"
        named, how = read, "named by the function that reads the table"
    if not named:
        return None, "no `_ARTIFACT` binding and no reader filename; the key names a row, not a path"
    if len(named) > 1:
        return None, "the table names more than one artifact (%s); not picked" % ", ".join(named)
    dirs = decl.get("run-dirs") or []
    if len(dirs) != 1:
        return None, "run directory is %s, not one; the filename %s has nowhere to sit" % (
            dirs or "absent", named[0])
    return os.path.normpath(os.path.join(dirs[0], named[0])), how


def classify(files):
    """-> (judged, shadows, orphans). A shadow's path ends in `/<another defining path>`.
    Among what remains, the file those shadows were copied from is the authored one; a
    leftover with no shadow pointing at it is an orphan copy and is not the flagship."""
    shadow = {a for a in files for b in files if a != b and a.endswith("/" + b)}
    authored = [f for f in files if f not in shadow]
    if len(authored) <= 1:
        return authored, sorted(shadow), []
    flagship = [f for f in authored if any(s.endswith("/" + f) for s in shadow)]
    orphans = [f for f in authored if f not in flagship]
    return flagship, sorted(shadow), orphans


def judge(root, scratch=False, read_runs=True):
    """-> a dict. Pure in the corpus's bytes except the artifact read, which is refused
    while `differ.py` is live and the path is under this repo's `runs/`."""
    pop = load("pintable_pop", "pintable-pop.py").load_pop()
    tab = load("pintable_pop_gate", "pintable-pop.py")
    bind = load("pintable_bind", "bind-subject.py")
    corpus, host, counts = corpus_of(pop, root, scratch)
    code = {t: pop.code_lines(corpus[t], host[t]) for t in corpus if host.get(t) != "prose"}
    decls = bind.declarations(corpus, code)
    empty = {"subjects": {}, "artifacts": {}, "run-dirs": [], "at": {}}
    binds = tab.bindings(corpus, host)
    tables = tab.tables(binds, pop.PIN_NAME)
    exps = tab.expectations(tables, pop.HEX)
    by_name = {}
    for e in exps:
        by_name.setdefault(e["name"], set()).add(e["file"])
    judged, shadows, orphans = {}, {}, {}
    ambiguous = []
    for name, files in sorted(by_name.items()):
        flag, sh, orph = classify(sorted(files))
        shadows[name] = sh
        orphans[name] = orph
        if len(flag) == 1:
            judged[name] = flag[0]
        elif len(flag) > 1:
            ambiguous.append((name, flag))
    hex_sites = pop.rule_a(corpus, host) if not scratch else []
    hex_values = sum(len(s["values"]) for s in hex_sites)
    live = differ_running() if read_runs else []
    rows, findings, refused = [], [], []
    seen = {}
    for e in exps:
        if judged.get(e["name"]) != e["file"]:
            continue
        key = (e["file"], e["name"])
        if key not in seen:
            decl_rows, note = tab.declaration(root, e["file"], e["name"])
            scan = dict(e_row for e_row in
                        next(t["rows"] for t in tables
                             if t["file"] == e["file"] and t["name"] == e["name"]))
            scan_exp = {k: v for k, v in scan.items() if not pop.HEX.search(v)}
            if decl_rows is None:
                refused.append(f"{e['file']} {e['name']}: {note}")
                decl, cross, diff = None, note, set()
            else:
                decl = {k: v for k, v in decl_rows if not pop.HEX.search(v)}
                diff = {k for k in set(scan_exp) | set(decl) if scan_exp.get(k) != decl.get(k)}
                cross = ("SCAN-DECLARATION-DISAGREE " + ", ".join(sorted(diff))) if diff else "agree"
                if diff:
                    findings.append(f"{e['file']} {e['name']}: scan and declaration disagree on "
                                    + ", ".join(sorted(diff)))
            rel, why = artifact_of(e["name"], corpus[e["file"]], decls.get(e["file"], empty), bind)
            seen[key] = {"decl": decl, "cross": cross, "diff": diff, "rel": rel, "why": why,
                         "got": None, "read": None}
            if rel is None:
                refused.append(f"{e['file']} {e['name']}: {why}")
                seen[key]["read"] = "NO-SUBJECT"
            else:
                path = os.path.join(root, rel)
                if live and under_live_runs(path):
                    refused.append(f"{rel}: differ.py is live ({live[0]}); not read")
                    seen[key]["read"] = "NOT-READ"
                elif not os.path.isfile(path):
                    seen[key]["read"] = "ABSENT-FILE"
                else:
                    with open(path, encoding="utf-8", errors="replace") as fh:
                        seen[key]["got"] = kv_of(fh.read())
                    seen[key]["read"] = "READ"
                    seen[key]["mtime"] = os.stat(path).st_mtime
                    seen[key]["path"] = path
        slot = seen[key]
        declared = None if slot["decl"] is None else slot["decl"].get(e["key"])
        if e["key"] in slot["diff"]:
            verdict = "SCAN-DISAGREE"
        elif slot["read"] == "NOT-READ":
            verdict = "NOT-READ"
        elif slot["read"] == "NO-SUBJECT":
            verdict = "NO-SUBJECT"
        elif slot["read"] == "ABSENT-FILE" or (slot["got"] is not None and e["key"] not in slot["got"]):
            verdict = "ROW-ABSENT"
            findings.append(f"{e['name']}[{e['key']}] ABSENT from {slot['rel']}")
        elif slot["got"] is not None and slot["got"][e["key"]] != e["value"]:
            verdict = "MISMATCH"
            findings.append(
                f"{e['name']}[{e['key']}]={slot['got'][e['key']]!r} (expected {e['value']!r}) in {slot['rel']}")
        elif slot["got"] is not None and declared == e["value"]:
            verdict = "CURRENT"
        else:
            verdict = "UNREAD"
        rows.append({"file": e["file"], "line": e["line"], "name": e["name"], "key": e["key"],
                     "value": e["value"], "verdict": verdict, "artifact": slot["rel"]})
    return {
        "rows": rows, "findings": findings, "refused": refused, "counts": counts,
        "hex-values": hex_values, "hex-sites": len(hex_sites),
        "judged": judged, "shadows": shadows, "orphans": orphans, "ambiguous": ambiguous,
        "seen": seen, "live": live,
    }


def _denom(result, name):
    return [r for r in result["rows"] if r["name"] == name]


def report(result, out):
    pins = _denom(result, FLAGSHIP)
    out.write("pintable-gate: EXPECTATION ROWS, OWN DENOMINATOR\n")
    out.write(f"  OLD NUMBER: {result['hex-values']} content-address value(s) at "
              f"{result['hex-sites']} PIN-named site(s). A value is a >=7 lowercase hex run "
              f"(pincensus-pop.HEX). That count is addresses. It cannot see PINS.\n")
    out.write(f"  NEW NUMBER: {len(pins)} expectation row(s) of the authored table `{FLAGSHIP}`"
              f" in {result['judged'].get(FLAGSHIP, 'NOT DISCOVERED')}. "
              f"An expectation is a recorded measurement, not an address. "
              f"Not added to the old number.\n")
    others = sorted({r["name"] for r in result["rows"] if r["name"] != FLAGSHIP})
    for name in others:
        rows = _denom(result, name)
        out.write(f"  ALONGSIDE, NOT FOLDED: {name} = {len(rows)} expectation row(s) "
                  f"in {result['judged'].get(name)} (its own denominator)\n")
    for name, files in sorted(result["shadows"].items()):
        if files:
            out.write(f"  SHADOW (not judged, not in the denominator): {name} x{len(files)} "
                      f"path-suffix cop{'ies' if len(files) != 1 else 'y'}\n")
    for name, files in sorted(result["orphans"].items()):
        if files:
            out.write(f"  ORPHAN COPY (not judged, not in the denominator): {name} in {', '.join(files)}\n")
    if result["ambiguous"]:
        out.write(f"  AMBIGUOUS (not picked): {result['ambiguous']}\n")
    for (f, name), slot in sorted(result["seen"].items()):
        extra = ""
        if slot.get("mtime"):
            stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(slot["mtime"]))
            extra = f" mtime={stamp} epoch={int(slot['mtime'])} path={slot.get('path')}"
        out.write(f"  TABLE {f} {name}: scan/declaration {slot['cross']}; "
                  f"artifact {slot['rel'] or slot['why']} read={slot['read']}{extra}\n")
    by = {}
    for r in result["rows"]:
        by[r["verdict"]] = by.get(r["verdict"], 0) + 1
    out.write("  VERDICTS: " + " ".join(f"{k}={v}" for k, v in sorted(by.items())) + "\n")
    out.write("  CURRENT is the declared row against the recorded artifact. It is not a claim "
              "that the artifact describes the live tree; that comparison is substrate_digest, "
              "and it is not restated here.\n")
    for r in result["rows"]:
        if r["verdict"] != "CURRENT":
            out.write(f"    {r['verdict']:14} {r['name']}[{r['key']}] expected {r['value']!r} "
                      f"({r['file']}:{r['line']})\n")
    if result["findings"]:
        out.write(f"  RED: {len(result['findings'])}\n")
        for f in result["findings"]:
            out.write(f"    {f}\n")
    if result["refused"]:
        out.write(f"  REFUSED: {len(result['refused'])}\n")
        for f in result["refused"]:
            out.write(f"    {f}\n")
    return by


def exit_of(result):
    if not result["rows"] and not result["ambiguous"]:
        return DEAD
    if result["ambiguous"] or (FLAGSHIP not in result["judged"] and not result["findings"]):
        return REFUSED
    if result["findings"]:
        return FAIL
    if result["refused"]:
        return REFUSED
    if any(r["verdict"] != "CURRENT" for r in result["rows"]):
        return FAIL
    return PASS


def _copy_tree_file(root, rel, dest):
    dst = os.path.join(dest, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(os.path.join(root, rel), "rb") as fh:
        raw = fh.read()
    with open(dst, "wb") as fh:
        fh.write(raw)
    return raw


def plant():
    """Attack copies. The live tree is opened for reading and never written."""
    live = judge(ROOT, scratch=False)
    rel = live["judged"].get(FLAGSHIP)
    if not rel:
        print("pintable-plant: REFUSED -- the authored PINS table was not discovered", file=sys.stderr)
        return REFUSED
    slot = live["seen"].get((rel, FLAGSHIP))
    if not slot or not slot.get("rel"):
        print("pintable-plant: REFUSED -- PINS names no artifact, so the absence arm has no subject",
              file=sys.stderr)
        return REFUSED
    art_rel = slot["rel"]
    art_path = os.path.join(ROOT, art_rel)
    if not os.path.isfile(art_path):
        print(f"pintable-plant: REFUSED -- {art_rel} is absent, so a copy cannot be the control",
              file=sys.stderr)
        return REFUSED
    if differ_running() and under_live_runs(art_path):
        print("pintable-plant: REFUSED -- differ.py is live; the artifact is not copied", file=sys.stderr)
        return REFUSED
    key = next(r["key"] for r in live["rows"] if r["name"] == FLAGSHIP)
    old = next(r["value"] for r in live["rows"] if r["name"] == FLAGSHIP and r["key"] == key)
    planted_value = "PLANTED" if old != "PLANTED" else "PLANTED-2"
    before = open(os.path.join(ROOT, rel), "rb").read()
    base = tempfile.mkdtemp(prefix="pintable-plant-")
    try:
        control, disagree, absent = (os.path.join(base, n) for n in ("control", "disagree", "absent"))
        for dest in (control, disagree, absent):
            os.makedirs(dest)
            _copy_tree_file(ROOT, rel, dest)
            _copy_tree_file(ROOT, art_rel, dest)
        mutated = before + f'\n{FLAGSHIP}["{key}"] = "{planted_value}"\n'.encode()
        if mutated == before:
            print("pintable-plant: DEAD -- the rebinding did not change the copy", file=sys.stderr)
            return DEAD
        with open(os.path.join(disagree, rel), "wb") as fh:
            fh.write(mutated)
        art_raw = open(art_path, "rb").read()
        lines = art_raw.splitlines(keepends=True)
        kept = [ln for ln in lines if not ln.startswith(f"{key}=".encode())]
        if len(kept) == len(lines):
            print(f"pintable-plant: DEAD -- {key}= is not a line of {art_rel}", file=sys.stderr)
            return DEAD
        with open(os.path.join(absent, art_rel), "wb") as fh:
            fh.writelines(kept)
        c = judge(control, scratch=True, read_runs=False)
        d = judge(disagree, scratch=True, read_runs=False)
        a = judge(absent, scratch=True, read_runs=False)
        def one(result, k):
            return next((r for r in result["rows"] if r["name"] == FLAGSHIP and r["key"] == k), None)
        cr, dr, ar = one(c, key), one(d, key), one(a, key)
        decl_c = c["seen"].get((rel, FLAGSHIP), {}).get("decl") or {}
        decl_d = d["seen"].get((rel, FLAGSHIP), {}).get("decl") or {}
        print(f"pintable-plant: target {rel} {FLAGSHIP}[{key}]={old!r} artifact {art_rel}")
        print(f"  CONTROL  verdict={None if cr is None else cr['verdict']} declared={decl_c.get(key)!r}")
        print(f"  DISAGREE verdict={None if dr is None else dr['verdict']} declared={decl_d.get(key)!r}")
        print(f"  ABSENT   verdict={None if ar is None else ar['verdict']}")
        after = open(os.path.join(ROOT, rel), "rb").read()
        if after != before:
            print("pintable-plant: FAIL -- the live file changed", file=sys.stderr)
            return FAIL
        if cr is None or dr is None or ar is None:
            print("pintable-plant: FAIL -- a side produced no row, so the plant compared nothing",
                  file=sys.stderr)
            return FAIL
        if decl_c.get(key) == decl_d.get(key):
            print("pintable-plant: FAIL -- VACUOUS: control and disagree declare the same value",
                  file=sys.stderr)
            return FAIL
        disagree_fired = dr["verdict"] == "SCAN-DISAGREE" and cr["verdict"] != "SCAN-DISAGREE"
        absent_fired = ar["verdict"] == "ROW-ABSENT" and cr["verdict"] != "ROW-ABSENT"
        print(f"  DISAGREE {'FIRED' if disagree_fired else 'DID NOT FIRE'}")
        print(f"  ABSENT   {'FIRED' if absent_fired else 'DID NOT FIRE'}")
        print("  live file: untouched")
        if not disagree_fired or not absent_fired:
            print("pintable-plant: FAIL -- an arm did not fire, or its control was already red "
                  "for that arm", file=sys.stderr)
            return FAIL
        print("pintable-plant: the gate can fail, and the control did not")
        return PASS
    finally:
        shutil.rmtree(base, ignore_errors=True)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--scratch", action="store_true")
    ap.add_argument("--plant", action="store_true")
    args = ap.parse_args(argv)
    if args.plant:
        return plant()
    result = judge(args.root, scratch=args.scratch)
    report(result, sys.stdout)
    code = exit_of(result)
    pins = _denom(result, FLAGSHIP)
    green = sum(1 for r in pins if r["verdict"] == "CURRENT")
    print(f"pintable-gate: {len(pins)} {FLAGSHIP} row(s), {green} CURRENT, "
          f"exit {code} ({'PASS' if code == PASS else 'FAIL' if code == FAIL else 'REFUSED' if code == REFUSED else 'DEAD'})")
    if code == DEAD:
        print("pintable-gate: DEAD -- no expectation rows", file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
