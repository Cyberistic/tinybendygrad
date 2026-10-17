#!/usr/bin/env python3
"""WHICH CONTROL BROKE, AND IS THERE A REPLACEMENT POSITIVE THAT STILL EXISTS.

Runs `census.py`'s OWN extraction and OWN probes by importing it (module level defines only
constants and functions, so importing writes nothing) -- no file under `.agents/slop/onespelling/`
is modified and no control's subject is edited.

The census's `regex-anchor-set` kind requires a module-level `re.compile` whose source OPENS with a
`(?:^|...)` delimiter class.  That string is NECESSARY for the kind, so `git grep -F '(?:^|'` over
the committed `.py` is a SUPERSET of the kind's population, and the census's own
`literal_sites()` is then run unchanged on those files only.  That is the whole population for this
kind without `ast.parse` over 1889 files.

Also re-measures the other controls that do not need the full walk: pos2 needs only paths + prose,
pos3 needs `under`/`roots`/`prose`.  The four ast-spelling controls need the full walk and are NOT
re-measured here; the code says the fix cannot move them (`literal_sites()` appends every entry to
`group` regardless of `kind`), and that is stated as reading, not as a measurement.
"""
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
CENSUS = os.path.join(ROOT, ".agents/slop/onespelling/census.py")

spec = importlib.util.spec_from_file_location("census", CENSUS)
census = importlib.util.module_from_spec(spec)
spec.loader.exec_module(census)


def out(*parts) -> None:
    print(*parts)


# --- 1. the population for `regex-anchor-set`, by necessary-condition pre-filter -------------------
grep = subprocess.run(["git", "-C", ROOT, "grep", "-l", "-F", "(?:^|", "HEAD", "--", "*.py"],
                      capture_output=True, text=True, check=True).stdout.split()
files = sorted(p[len("HEAD:"):] for p in grep)
out(f"PRE-FILTER  `git grep -F '(?:^|' HEAD -- '*.py'` -> {len(files)} files")
for p in files:
    out(f"   {p}")

py_pairs = [(p, h) for p, h in census.committed(".py") if p in set(files)]
sites, by_file, stats = census.literal_sites(py_pairs)
rx = [s for s in sites if s["kind"] == "regex-anchor-set"]
out(f"\nREGEX-ANCHOR-SET POPULATION : {len(rx)} sites")
for s in rx:
    out(f"   {s['site']}")

# --- 2. the census's own verdict for each, over the committed prose at HEAD ----------------------
md = census.blobs(census.committed(".md"))
prose = dict(md)
out(f"prose at HEAD : {len(md)} committed .md")
rows = []
for s in rx:
    verdict, found, ev = census.probe_regex(s, [t for _, t in md])
    rows.append(dict(site=s["site"], kind=s["kind"], verdict=verdict, evidence=ev))
    out(f"   {verdict:8} {s['site']}\n            {ev}")

# --- 3. the control predicate, verbatim from `census.selfcheck` -----------------------------------
def control_holds(kind: str, verdict: str, frag: str) -> bool:
    """`census.selfcheck`'s predicate, verbatim, over the rows this kind's population yields."""
    return bool([r for r in rows if r["kind"] == kind and frag in r["site"] and r["verdict"] == verdict])


out("\nCONTROLS OF THIS KIND, AS `selfcheck()` ASKS THEM")
for frag in ("checks/repro-paths.py", ".agents/slop/reprorefs/probe.py", ""):
    out(f"   frag={frag!r:34} holds={control_holds('regex-anchor-set', 'POSITIVE', frag)}")

# --- 4. what happened to checks/repro-paths.py itself ---------------------------------------------
rp_sites, rp_by_file, rp_stats = census.literal_sites(
    [(p, h) for p, h in census.committed(".py") if p == "checks/repro-paths.py"])
out("\nEVERY MODULE-LEVEL LITERAL IN checks/repro-paths.py, WITH ITS KIND")
group = rp_by_file.get("checks/repro-paths.py", [])
out(f"   {rp_stats['literals']} module-level literals, spellings {dict(rp_stats['spellings'])}")
for e in group:
    out(f"   kind={str(e['kind']):22} spelling={e['spelling']:12} name={e['name']}")
if not group:
    out("   -> NO literal in this file has a kind, so the file contributes NO row at all "
        "(`by_file` is kept only `if found`, census.py:369-371)")
for s in rp_sites:
    out(f"   -> SITE {s['site']} kind={s['kind']}")

# --- 5. the other controls that need no full walk --------------------------------------------------
paths = [p for p, _ in census.committed()]
roots = sorted({p.split("/", 1)[0] for p in paths if "/" in p})
out(f"\npaths at HEAD : {len(paths)}   roots : {len(roots)}")
hits, cited = census.ambiguous_basenames([t for _, t in md], paths)
out(f"pos2 bare basenames : cited={cited} ambiguous={len(hits)}")
for frag in ("differ.py", "gatekit.py", "extract.py"):
    out(f"   pos2 frag={frag!r:14} holds={bool(hits.get(frag))}  files={len(hits.get(frag, []))}")

under = {p for p in paths} | {q for p in paths for q in census.prefixes(p)}
tb_sites, _, _ = census.literal_sites(
    [(p, h) for p, h in census.committed(".py") if p == ".agents/slop/toolsledger/extract.py"])
for s in tb_sites:
    if s["kind"] == "single-base-resolver":
        v, f, e = census.probe_base(s, under, roots, prose)
        out(f"pos3 frag={s['site']!r}\n   {v:8} {f:4} {e}")
out(f"   pos3 holds={any(census.probe_base(s, under, roots, prose)[0] == 'POSITIVE' and
                        '.agents/slop/toolsledger/extract.py' in s['site']
                        for s in tb_sites if s['kind'] == 'single-base-resolver')}")

# --- 6. is the REPAIRED pattern itself one-spelling? what does the census now not watch? ----------
spec2 = importlib.util.spec_from_file_location("rp", os.path.join(ROOT, "checks/repro-paths.py"))
rp = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(rp)
new = rp.REF
widest = census.re.compile(r"((?:\.agents/slop/|checks/|gates/)[\w./-]*\.[A-Za-z0-9]+)")
seen_n: set[str] = set()
seen_w: set[str] = set()
ctx: dict[str, str] = {}
for rel, text in md:
    a = {m.group(1) for m in new.finditer(text)}
    seen_n |= a
    for m in widest.finditer(text):
        p = m.group(1)
        seen_w.add(p)
        if p not in seen_n and p not in ctx:
            ctx[p] = (f"{rel}: ...{text[max(0, m.start() - 14):m.start()]!r}"
                      if m.start() else f"{rel}: at-line-start")
out("\nTHE REPAIRED checks/repro-paths.py REF, MEASURED OVER THE SAME PROSE")
out(f"   REF names {len(seen_n)} distinct paths; with NO leading-anchor clause at all it names "
    f"{len(seen_w)}; {len(seen_w - seen_n)} spellings the shipped pattern still cannot see")
found = sorted(seen_n)
for p in sorted(seen_w - seen_n):
    longer = next((f for f in reversed(found) if f.endswith("/" + p)), "")
    out(f"      still invisible: {p}   {ctx[p]}   is a TAIL of a token REF does find: "
        f"{longer or 'NO -- a path the shipped pattern misses outright'}")
out(f"   the census CANNOT measure this, because `widened()` returns "
    f"{census.widened(new.pattern)!r} for it, so the kind never fires")

# --- 7. what the FIX alone did to the census: the SAME file at its PARENT commit --------------------
log = subprocess.run(["git", "-C", ROOT, "log", "--format=%H", "-2", "--", "checks/repro-paths.py"],
                     capture_output=True, text=True, check=True).stdout.split()
fix_commit, before_commit = log[0], log[1]
subj = subprocess.run(["git", "-C", ROOT, "log", "-1", "--format=%s", fix_commit],
                     capture_output=True, text=True, check=True).stdout.strip()
anc = subprocess.run(["git", "-C", ROOT, "merge-base", "--is-ancestor", fix_commit, "HEAD"]).returncode
out(f"\nTHE FIX COMMIT FOR checks/repro-paths.py : {fix_commit}  (ancestor of HEAD: {anc == 0})")
out(f"   subject: {subj}")
out(f"its parent                            : {before_commit}")
def site_rows(rev: str, label: str) -> list[dict]:
    meta = subprocess.run(["git", "-C", ROOT, "ls-tree", rev, "--", "checks/repro-paths.py"],
                          capture_output=True, text=True, check=True).stdout.split("\t")
    h = meta[0].split()[2]
    s, byf, st = census.literal_sites([(label, h)])
    out(f"   {label} @ {rev[:12]}  blob {h[:12]}  literals={st['literals']}  sites={len(s)}  "
        f"spellings={dict(st['spellings'])}")
    rows_ = []
    for e in s:
        v, f, ev = census.probe_regex(e, [t for _, t in md])
        out(f"      {e['kind']:18} {e['site'].split(':')[-1]:12} {v:8} {f:4} {ev}")
        rows_.append((e, v))
    return rows_


before = site_rows(before_commit, f"checks/repro-paths.py@{before_commit[:12]}")
after = site_rows("HEAD", "checks/repro-paths.py@HEAD")
out(f"   -> the fix alone moves the census by {len(before) - len(after)} site(s) and "
    f"{sum(1 for _, v in before if v == 'POSITIVE') - sum(1 for _, v in after if v == 'POSITIVE')} POSITIVE")
pats = {}
for e, _ in before + after:
    pats.setdefault(e["site"].split(":")[-1] + "@" + e["path"].split("@")[1][:12], e["extra"]["pattern"])
for k, v in sorted(pats.items()):
    out(f"   pattern {k:18} {v}")
permissive = next(s["extra"]["pattern"] for s in rx if s["site"].endswith("PERMISSIVE"))
old_shipped = before[0][0]["extra"]["pattern"] if before else ""
new_shipped = rp.REF.pattern
out(f"   probe.py:27 PERMISSIVE == the SHIPPED pattern BEFORE the fix ? {permissive == old_shipped}")
out(f"   probe.py:27 PERMISSIVE == the SHIPPED pattern AFTER  the fix ? {permissive == new_shipped}")

# --- 8. rows -------------------------------------------------------------------------------------
with open(os.path.join(HERE, "measure.rows"), "w") as fh:
    fh.write("# re-derived from census.py's own literal_sites()+probe_regex() over a necessary-condition\n"
             "# pre-filter (`git grep -F '(?:^|' HEAD -- '*.py'`), at the HEAD named in decision.md\n")
    fh.write(f"# git-grep files\t{len(files)}\t" + ",".join(files) + "\n")
    fh.write(f"# prose files\t{len(md)}\n")
    fh.write(f"# census literal_sites stats on the subset\t{json.dumps({k: v for k, v in stats.items()})}\n")
    for r in rows:
        fh.write(f"regex-anchor-set\t{r['site']}\t{r['verdict']}\t{r['evidence']}\n")
    for frag in ("checks/repro-paths.py", ".agents/slop/reprorefs/probe.py", ""):
        fh.write(f"control\tfrag={frag!r}\tholds={control_holds('regex-anchor-set', 'POSITIVE', frag)}\n")
    fh.write(f"repro-paths-literal\t{rp_stats['literals']} module-level literals\t"
             f"spellings={dict(rp_stats['spellings'])}\tsites={len(rp_sites)}\n")
    for e in group:
        fh.write(f"repro-paths-literal\t{e['name']}\tkind={e['kind']}\tspelling={e['spelling']}\n")
    for frag in ("differ.py", "gatekit.py", "extract.py"):
        fh.write(f"control-pos2\tfrag={frag}\tholds={bool(hits.get(frag))}\tfiles={len(hits.get(frag, []))}\n")
    for s in tb_sites:
        if s["kind"] == "single-base-resolver":
            v, f, e = census.probe_base(s, under, roots, prose)
            fh.write(f"control-pos3\t{s['site']}\t{v}\t{e}\n")
    fh.write(f"fix-commit\t{fix_commit}\tparent={before_commit}\n")
    for e, v in before:
        fh.write(f"before-fix\t{e['site']}\tkind={e['kind']}\t{v}\t{e['extra']['pattern']}\n")
    fh.write(f"after-fix\tchecks/repro-paths.py@HEAD\tsites={len(after)}\t"
             f"literals={rp_stats['literals']}\t{new_shipped}\n")
    for e, v in after:
        fh.write(f"after-fix\t{e['site']}\tkind={e['kind']}\t{v}\t{e['extra'].get('pattern')}\n")
    fh.write(f"pattern-identity\tprobe.py:27 PERMISSIVE == shipped BEFORE fix: {permissive == old_shipped}"
             f"\t== shipped AFTER fix: {permissive == new_shipped}\n")
    fh.write(f"repaired-REF\tshipped={len(seen_n)}\tno-anchor-clause={len(seen_w)}\t"
             f"invisible={len(seen_w - seen_n)}\twidened()={census.widened(new.pattern)!r}\n")
    for p_ in sorted(seen_w - seen_n):
        fh.write(f"repaired-REF-still-invisible\t{p_}\t{ctx[p_]}\n")
out(f"\nwrote {os.path.join(HERE, 'measure.rows')}")