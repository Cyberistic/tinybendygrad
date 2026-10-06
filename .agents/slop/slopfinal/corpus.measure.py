#!/usr/bin/env python3
"""`:(glob)` BLINDED THE CITATION CORPUS TO 63% OF THE REPORTS. Measure the correct one.

THE MEASUREMENT THAT BREAKS THE OLD ONE. `NAMED_BY`'s `:(glob).agents/slop/*.md` was introduced to
stop a shadow tree's copies of the corpus from counting as citations -- MEASURED then: the blob was
3,736,092 chars of which 1,370,376 were real, so 63% of the evidence was a copy of the evidence.

BUT `:(glob)` DOES NOT CROSS `/`, AND EVERY UNIT WRITES ITS REPORT INTO A SUBDIRECTORY. MEASURED on
this tree:

    committed .md under .agents/slop, any depth          262
    of those, at depth 1, which is all `:(glob)` reaches   98
    INVISIBLE to the corpus                               164

So the fix removed the corruption AND removed 164 real reports, and the two are INDISTINGUISHABLE BY
DEPTH: `.agents/slop/abi4/README.md` (a unit's claim) and
`.agents/slop/arghalf/pin-tree/tinygrad/viz/README.md` (a copy of upstream) are both at depth 2.

THE RIGHT DISCRIMINATOR IS NOT DEPTH, IT IS WHETHER THE FILE IS A COPY -- and the twin map already
answers that. **A CORPUS FILE THAT IS A BYTE-COPY OF ANOTHER FILE CONTRIBUTES NO CITATION THE OTHER
DOES NOT ALREADY CONTRIBUTE.** So a copy is excluded by a proof, and a unit's own report is included
because it is not a copy. That is one filter and it has no list in it.

Same principle as G8, applied one level up: G8 asks "is the CITER a copy?", this asks "is the CORPUS
MEMBER a copy?".
"""
import collections, importlib.util, os, subprocess, sys, time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


sweep = load("sweep", os.path.join(ROOT, "checks/sweep.py"))
res = load("residue", os.path.join(ROOT, "checks/residue.py"))

tracked = sweep.tracked_files()
files = sweep.walk_residue()
copies = sweep.residue_copies(ROOT, [r for r, _ in files])
selfdirs = set(sweep.self_output_dirs()) | {sweep.SELF}

def depth(n): return n.count("/")

def in_self(p): return any(p.startswith(d + "/") for d in selfdirs)

def corpus(paths):
    """The three candidate corpora, each as a set of paths."""
    old = set()
    for nm in subprocess.run(["git", "ls-files", "--", *sweep.NAMED_BY, *sweep.self_excludes()],
                             cwd=ROOT, capture_output=True, text=True).stdout.split():
        old.add(nm)
    wide = set(n for n in paths
               if n.endswith(".md") and n.startswith(".agents/slop/") and not in_self(n))
    wide |= {n for n in paths
             if (n == "AGENTS.md" or (n.startswith("checks/") or n.startswith("gates/")
                                      or n.startswith(".agents/")) and n.endswith((".md", ".py")))}
    return old, wide

paths = sorted(tracked)
old, wide = corpus(paths)
wide_copies = {p for p in wide if p in copies}
new = wide - wide_copies

def load_text(names):
    out = []
    for nm in sorted(names):
        r = subprocess.run(["git", "show", f"HEAD:{nm}"], cwd=ROOT,
                           capture_output=True, text=True, errors="replace")
        if r.returncode == 0:
            out.append((nm, r.stdout))
    return out

print(f"# {'corpus':44s} {'files':>7s} {'chars':>12s}")
corpora = {"AS SHIPPED (the :(glob) one)": old,
           "WIDENED (every depth, self-outputs out)": wide,
           "WIDENED MINUS COPIES  <-- the fix": new}
texts = {}
for k, v in corpora.items():
    t = load_text(v)
    texts[k] = t
    print(f"# {k:44s} {len(t):7d} {sum(len(x) for _n, x in t):12d}")

print(f"\n# what the filter removed, by bucket (not by path):")
removed = wide - new
buck = collections.Counter()
for p in sorted(removed):
    parts = p.split("/")
    buck[parts[1] if len(parts) > 2 else "(top of .slop)"] += 1
for k, n in buck.most_common(12):
    print(f"#   {k:44s} {n:4d}")
print(f"#   TOTAL removed as copies{'':25s} {len(removed):4d} of {len(wide)}")

# ---- does the corpus change move any VERDICT? ---------------------------------------------
def index(texts_):
    cites = [{}, {}]
    chars = 0
    for nm, text in texts_:
        chars += len(text)
        for belt, toks in ((0, sweep.mentioned_filenames(text)), (1, sweep.whole_path_tokens(text))):
            idx = cites[belt]
            for tok in toks:
                idx.setdefault(tok, set()).add(nm)
                idx.setdefault(tok.rsplit("/", 1)[-1], set()).add(nm)
    return cites, chars

base = sweep.Facts()
cites_new, chars_new = index(texts["WIDENED MINUS COPIES  <-- the fix"])

class F2(sweep.Facts):
    pass

f2 = F2.__new__(F2)
f2.__dict__.update(base.__dict__)
f2.cites, f2.chars = cites_new, chars_new
f2.mentioned = set(cites_new[0])

live = sweep.live_set(60)
rows = [(r, sweep.verdict_for(r, base.mentioned, base), sweep.verdict_for(r, f2.mentioned, f2))
        for r, _ in files]
changed = [(r, a, b) for r, a, b in rows if a != b]
print(f"\n# VERDICTS THAT MOVE, shipped corpus -> fixed corpus, at window 60:")
print(f"#   {len(changed)} of {len(rows)} rows change verdict")
mv = collections.Counter((sweep.bucket(a), sweep.bucket(b)) for _r, a, b in changed)
for (a, b), n in mv.most_common():
    print(f"#   {a:12s} -> {b:12s} {n:5d} rows")
newly_del = {r for r, a, b in changed if b == "DELETE" and a != "DELETE"}
newly_keep = {r for r, a, b in changed if b != "DELETE" and a == "DELETE"}
print(f"\n#   rows that become DELETE:      {len(newly_del)}")
print(f"#   rows that STOP being DELETE:  {len(newly_keep)}")
print(f"#   by bucket:", dict(collections.Counter(r.split('/')[1] if len(r.split('/')) > 2 else '(top)' for r in newly_keep)))
