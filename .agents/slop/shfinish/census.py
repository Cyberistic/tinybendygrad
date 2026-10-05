#!/usr/bin/env python3
"""Re-measure the .sh census of .agents/slop, and cite honestly.

THE FOUR TRAPS, each of which produced a wrong number last time, and one I hit myself:
  `:(glob)**` pathspec -- `-- '*.sh'` crosses `/` and swept reports out of shadow trees.
  WHOLE PATH TOKEN    -- a citation is a token EQUAL to the path (or the bare basename), never a
                        substring of one: `.out` occurs inside 23 tokens where 2 paths are cited.
  os.lstat for size    -- `getsize` follows the 167 symlinks in .slop.
  DO NOT BLIND-READ    -- `.agents/slop/e2epy/fixtures/plant-*/sandbox/node` -> /usr/local/bin/node
                        is a 139 MB binary behind a 19-byte symlink. Reading every tracked path
                        as text wrote a 1.7 GB corpus.txt. lstat says regular; the CONTENT is
                        139 MB. Filter on S_ISREG **and** cap the size, or do not read it.
  SHADOW EXCLUDED     -- differverdict/ and xd1/ hold COPIES OF SOURCE TREES.
Prints the whole measurement: the numbers must be re-derivable, not trustworthy."""
import os, re, hashlib, stat, collections, subprocess, json

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SLOP = os.path.join(ROOT, ".agents/slop")
SHADOW = ("differverdict", "xd1")
GATE_RX = re.compile(r"(gate|verify|check|lint|sweep|census|audit|guard|test|smoke|selftest|budget|stry|diff)")
CAP = 4 << 20

def walk(top):
    for dirpath, dirnames, files in os.walk(top, followlinks=False):
        dirnames[:] = [d for d in dirnames if not (dirpath == SLOP and d in SHADOW)]
        for f in files:
            yield os.path.join(dirpath, f)

def sha(p):
    try: return hashlib.sha256(open(p, "rb").read()).hexdigest()
    except OSError: return None

def size(p):
    try: return os.lstat(p).st_size
    except OSError: return 0

pop = [p for p in walk(SLOP) if p.endswith((".sh", ".py")) and "/tinygrad/" not in p]
sh  = sorted(p for p in pop if p.endswith(".sh"))
gate = [p for p in pop if GATE_RX.search(os.path.basename(p))]
shgate = sorted(p for p in gate if p.endswith(".sh"))

def byhash(ps):
    d = collections.defaultdict(list)
    for p in ps: d[sha(p)].append(p)
    return d
shh = byhash(shgate)

tracked = [t for t in subprocess.run(["git", "ls-files", ":(glob)**"], capture_output=True,
                                     text=True, cwd=ROOT).stdout.split("\n") if t]
TOK: set[str] = set()
for t in tracked:
    p = os.path.join(ROOT, t)
    try:
        st = os.lstat(p)
        if not stat.S_ISREG(st.st_mode) or st.st_size > CAP: continue
        with open(p, encoding="utf-8", errors="replace") as f:
            TOK.update(re.split(r"[\s\"'`;|&<>(){}\[\],:!$*?=+~^]+", f.read()))
    except OSError:
        pass

def cite(path):
    rel, base = os.path.relpath(path, ROOT), os.path.basename(path)
    if rel in TOK: return "repo-path"
    if base in TOK: return "basename"
    if any(t.endswith("/" + base) for t in TOK): return "path-suffix"
    return "-"

print(f"tracked files read (:(glob)**, S_ISREG, <=4MiB): {len(tracked)}   tokens: {len(TOK):,}")
print(f"population .sh+.py in .slop, minus tinygrad: {len(pop)} = {len(sh)} .sh + {len(pop)-len(sh)} .py")
print(f"gate-shaped by NAME: {len(gate)} ({len(shgate)} of them .sh)")
print(f".sh gate-shaped distinct by sha256: {len(shh)}")
print(f".sh gate-shaped cited as a WHOLE TOKEN: {sum(1 for v in shh.values() if cite(v[0]) != '-')}/{len(shh)}")
print()
print("=== .sh gates, biggest family first ===")
for k, v in sorted(shh.items(), key=lambda kv: (-len(kv[1]), kv[1][0])):
    for p in sorted(v, key=lambda q: os.path.relpath(q, SLOP)):
        print(f"{len(v):3d}  {size(p):7d}B  {cite(p):11}  {os.path.relpath(p, SLOP)}")
print()
print("=== every remaining .sh, non-gate-shaped ===")
for p in sh:
    if p not in shgate: print(f"       {size(p):7d}B           {os.path.relpath(p, SLOP)}")
json.dump({"sh": [os.path.relpath(p, ROOT) for p in sh],
           "gate_sh": [os.path.relpath(p, ROOT) for p in shgate]},
          open(os.path.join(os.path.dirname(__file__), "census.json"), "w"), indent=1)
