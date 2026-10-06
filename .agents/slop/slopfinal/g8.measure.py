#!/usr/bin/env python3
"""G8: FOR EACH `residue-internal-citer` ROW, IS THE CITER ITSELF A COPY?

THE THIRD OCCURRENCE OF THE SELF-CITATION TRAP HAS A NAME AND A DISCRIMINATOR. Three times now a
citation index built from a tree that includes the instrument has cited the instrument. All three
variants were "the citer is not a person, it is a copy":

  1. `residue`'s `000-the-residue.md` names every row; a bare `git add` staged it; UNNAMED 40 -> 0.
  2. The oracle self-check's `C` collided with a MAPPED atom under `DEV=NULL`, so the letter was
     self-concealing: the citer was the output the check writes.
  3. A shadow tree names the files it copied. **That is the same shape as 1 and 2 and it has been
     folded into the same bucket**, so the class carries three populations that need three verdicts.

THE DISCRIMINATOR IS ONE LOOKUP. `residue.outside_twins` already returns, for each subject, every
file OUTSIDE the residue with identical bytes. So "is this citer a copy" is "does the citer appear as
a KEY in that map" -- and a copy's citation is not evidence of a dependency, it is the corpus naming
itself.

WHAT THIS DOES AND DOES NOT DECIDE. It splits the class. It does NOT by itself make any row DELETE:
a copy can be the last copy. It makes the row's `needs=` CHANGE from "cannot tell" to the question
that is actually open, which is the only thing a `needs=` is allowed to be.
"""
import collections, importlib.util, os, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

sweep = load("sweep", os.path.join(ROOT, "checks/sweep.py"))
res = load("residue", os.path.join(ROOT, "checks/residue.py"))

f = sweep.facts()
tracked = res.git_tracked(ROOT)
files = res.walk(ROOT)
age = res.dir_ages(ROOT, files)
auth = res.authorities()
named = f.mentioned
first = lambda rel, n: sweep.verdict_for(rel, n, f)

sweep_delete = [rel for rel, sz in files if sweep.verdict_for(rel, named, f) == "DELETE"]
print(f"# sweep DELETE rows entering residue: {len(sweep_delete)}", file=sys.stderr)

# THE MAP. Subjects = EVERY residue file, not just the DELETE rows, because the CITERS are arbitrary
# residue files and a map keyed only on deletion candidates cannot answer a question about a citer.
t0 = time.time()
twins_all = res.outside_twins(ROOT, tracked, [(r, 0) for r, _ in files])
copies = set(twins_all)
print(f"# twin map: {len(twins_all)} of {len(files)} residue files have an outside twin "
      f"({time.time()-t0:.1f}s)", file=sys.stderr)

twins_del = {k: v for k, v in twins_all.items() if k in set(sweep_delete)}

cites = collections.defaultdict(set)
for rel in sorted(tracked):
    if res.excluded(rel):
        continue
    try:
        with open(os.path.join(ROOT, rel), "rb") as fh:
            blob = fh.read(4 << 20).decode("utf-8", "replace")
    except OSError:
        continue
    res.index_citations(cites, ROOT, rel, blob)

rows = []
for rel, sz in files:
    if rel not in twins_del:
        continue
    _f2, rv, why = res.classify(ROOT, rel, sz, sweep_named=named, first_pass=first, auth=auth,
                                 age=age, window=0, twins=twins_del, cites=cites,
                                 tracked=tracked, disabled=set())
    rows.append((rel, sz, rv, why))

counts = collections.Counter(v for _r, _s, v, _w in rows)
print("\n# residue verdicts on sweep's DELETE rows (window 0):")
for v, n in counts.most_common():
    print(f"#   {v:9s} {n:5d}")

# ---- G8 ------------------------------------------------------------------------------------
g8 = [r for r in rows if r[2] == "UNKNOWN" and "residue-internal-citer" in r[3]]
print(f"\n# G8 POPULATION: {len(g8)} rows with needs=residue-internal-citer")

split = collections.Counter()
detail = collections.Counter()
for rel, sz, rv, why in g8:
    name = os.path.basename(rel)
    citers = set(cites.get(name, ()))
    internal = {c for c in citers if res.in_residue(c)}
    if not internal:
        split["no-internal-citer-left"] += 1
        continue
    copy_citers = {c for c in internal if c in copies}
    other = internal - copy_citers
    if other:
        # a citer that is NOT a copy: a real tool in the residue that may genuinely depend on it
        split["citer-not-a-copy (still ambiguous)"] += 1
        detail[sorted(other)[0].split(os.sep, 2)[-1]] += 1
    elif copy_citers:
        split["EVERY citer is a COPY -> decidable"] += 1
    else:
        split["internal-but-no-citer"] += 1

print("\n# G8 SPLIT:")
for k, n in split.most_common():
    print(f"#   {k:42s} {n:4d} rows")
print("\n# non-copy internal citers, by directory (a bucket, not a path list):")
for k, n in detail.most_common(15):
    print(f"#   {k:52s} {n:4d}")
