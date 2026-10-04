#!/usr/bin/env python3
"""Does mutanchor now see `open(P,'w').write(...)`?  And what does it still miss?

Every case below is EXECUTED through mutanchor's AST reader, and every fixture is
written to a temp file and re-read, so the answers are CALLed, not reasoned about.
"""
import os, sys, tempfile
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop")
import mutanchor as MA

CASES = [
    # (label, source, must-be-seen?)
    ("open(P,'w').write(s)          MISSED BEFORE",
     "SRC='tinybendygrad/uop/ops.bend'\nopen(SRC,'w').write(s)\n", True),
    ("open(SRC, \"w\").write(s)      MISSED BEFORE",
     'SRC="tinybendygrad/uop/ops.bend"\nopen(SRC, "w").write(s)\n', True),
    ("open(SRC,'w').writelines(s)   MISSED BEFORE",
     "SRC='tinybendygrad/uop/ops.bend'\nopen(SRC,'w').writelines(s)\n", True),
    ("h = open(SRC,'w'); h.write(s) MISSED BEFORE",
     "SRC='tinybendygrad/uop/ops.bend'\nh=open(SRC,'w')\nh.write(s)\n", True),
    ("with open(SRC,'w') as f:      MISSED BEFORE",
     "SRC='tinybendygrad/uop/ops.bend'\nwith open(SRC,'w') as f:\n  f.write(s)\n", True),
    ("open(SRC,'a').write(s)        append",
     "SRC='tinybendygrad/uop/ops.bend'\nopen(SRC,'a').write(s)\n", True),
    ("open(SRC,'r+').write(s)       read-write",
     "SRC='tinybendygrad/uop/ops.bend'\nopen(SRC,'r+').write(s)\n", True),
    ("open(SRC, mode='w').write(s)  keyword mode",
     "SRC='tinybendygrad/uop/ops.bend'\nopen(SRC, mode='w').write(s)\n", True),
    ("io.open(SRC,'w').write(s)     io module",
     "import io\nSRC='tinybendygrad/uop/ops.bend'\nio.open(SRC,'w').write(s)\n", True),
    ("gzip.open(SRC,'wb').write(s)  gzip module",
     "import gzip\nSRC='tinybendygrad/uop/ops.bend'\ngzip.open(SRC,'wb').write(s)\n", True),
    ("SRC.write_text(s)             already caught",
     "SRC='tinybendygrad/uop/ops.bend'\nSRC.write_text(s)\n", True),
    ("shutil.copy(BAK, SRC)         already caught",
     "SRC='tinybendygrad/uop/ops.bend'\nBAK='/tmp/x'\nshutil.copy(BAK, SRC)\n", True),
    ("os.remove(SRC)                DELETION, missed before",
     "SRC='tinybendygrad/uop/ops.bend'\nos.remove(SRC)\n", True),
    ("shutil.rmtree(D)              DELETION, missed before",
     "D='tinybendygrad/uop'\nshutil.rmtree(D)\n", True),
    ("shutil.move(A, SRC)           missed before",
     "SRC='tinybendygrad/uop/ops.bend'\nA='/tmp/x'\nshutil.move(A, SRC)\n", True),
    ("open(SRC).read()              MUST NOT be a write",
     "SRC='tinybendygrad/uop/ops.bend'\ns=open(SRC).read()\n", False),
    ("open(SRC,'rb')                MUST NOT be a write",
     "SRC='tinybendygrad/uop/ops.bend'\ns=open(SRC,'rb').read()\n", False),
    ("s.replace(a,b)                MUST NOT be a write",
     "SRC='tinybendygrad/uop/ops.bend'\ns=open(SRC).read().replace(a,b)\n", False),
    ("dst.write_text(s) scratch     SCRATCH not IN-PLAY",
     "DST='/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/x'\n"
     "DST.write_text(s)\n", True),
]

td = tempfile.mkdtemp()
print("%-46s %-9s %s" % ("SPELLING", "SEEN?", "ZONES / spelling detected"))
print("-" * 110)
fails = 0
for label, src, want in CASES:
    f = os.path.join(td, "h.py")
    open(f, "w").write(src)
    sp = MA.write_spellings(MA.parse(f), "h.py")
    seen = bool(sp)
    ok = seen == want
    fails += not ok
    print("%-46s %-9s %s" % (label, ("yes" if seen else "NO") + ("" if ok else "  <-- WRONG"),
                            "; ".join("%s via %s" % (z, s) for z, _, s in sp) or "-"))
print("-" * 110)
print("%d/%d cases behave as required" % (len(CASES) - fails, len(CASES)))

# What is STILL missed, stated rather than guessed.
STILL = [
    ("nested open as an ARGUMENT: json.dump(x, open(SRC,'w'))",
     "import json\nSRC='tinybendygrad/uop/ops.bend'\njson.dump(x, open(SRC,'w'))\n"),
    ("print(..., file=open(SRC,'w'))",
     "SRC='tinybendygrad/uop/ops.bend'\nprint(x, file=open(SRC,'w'))\n"),
    ("handle passed as an ARGUMENT: dump(x, f)",
     "SRC='tinybendygrad/uop/ops.bend'\nf=open(SRC,'w')\ndump(x, f)\n"),
    ("handle returned / stored in a container",
     "SRC='tinybendygrad/uop/ops.bend'\nH={'f': open(SRC,'w')}\nH['f'].write(s)\n"),
    ("shell redirection: subprocess 'cat > SRC'",
     "SRC='tinybendygrad/uop/ops.bend'\nsubprocess.run('cat > %s' % SRC, shell=True)\n"),
    ("write through a subscript: H[0].write(s)",
     "SRC='tinybendygrad/uop/ops.bend'\nH=[open(SRC,'w')]\nH[0].write(s)\n"),
    ("module-scope side effect at IMPORT of another harness",
     "import sibling\n"),
]
print()
print("STILL MISSED, and each is a REAL hole rather than a curiosity:")
for label, src in STILL:
    f = os.path.join(td, "h2.py")
    open(f, "w").write(src)
    got = MA.writes(MA.parse(f), "h2.py")
    print("  %-56s detected=%s" % (label, got or "NOTHING"))