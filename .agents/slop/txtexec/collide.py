import csv, os, hashlib, pathlib
from collections import Counter

ROOT = pathlib.Path(".")
plan = list(csv.DictReader(open(".agents/slop/txt259/PLAN.tsv"), delimiter="\t"))

# class -> target extension
EXT = {
    "rowdump": ".rows",
    "crash-dump-in-txt": ".err",
    "source-in-txt": None,   # special
    "rowdump?/md": ".md",
    "rowdump?/tsv": ".tsv",
    "rowdump?/empty": None,  # leave
}
SPECIAL_SOURCE = {
    "oracles/usb-arith-rows.bend.txt": "oracles/usb-arith-rows.bend",
}

def target(r):
    p = r["path"]; cls = r["cls"]
    if cls == "source-in-txt":
        return SPECIAL_SOURCE.get(p, p[:-4] + ".py")
    if cls == "rowdump?/empty":
        return None
    return p[:-4] + EXT[cls]

rows_t = []
for r in plan:
    t = target(r)
    rows_t.append((r["path"], r["cls"], t))

# collisions: target already exists on disk (and isn't the source itself)
print("=== TARGET COLLISIONS (target exists on disk, != source) ===")
coll = 0
for old, cls, t in rows_t:
    if t is None:
        continue
    if t != old and os.path.exists(t):
        same = ""
        if os.path.exists(old):
            a = hashlib.sha256(open(old,'rb').read()).hexdigest()
            b = hashlib.sha256(open(t,'rb').read()).hexdigest()
            same = "IDENTICAL" if a == b else "DIFFER"
        print(f"  {old} ({cls}) -> {t}  EXISTS [{same}]")
        coll += 1
print("collisions:", coll)

# duplicate targets among the plan
print()
tgts = [t for _,_,t in rows_t if t]
dups = [t for t,c in Counter(tgts).items() if c > 1]
print("duplicate targets within plan:", dups)

print()
print("=== class -> target ext tally ===")
tally = Counter()
for old, cls, t in rows_t:
    tally[(cls, os.path.splitext(t)[1] if t else "LEAVE")] += 1
for k in sorted(tally):
    print(f"  {k[0]:20s} -> {k[1]:8s} {tally[k]}")
