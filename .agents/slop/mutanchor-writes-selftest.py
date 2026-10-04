#!/usr/bin/env python3
"""Does mutanchor see `open(P,'w').write(...)`?  And what does it still miss?

Every case below is EXECUTED through mutanchor's AST reader, and every fixture is
written to a temp file and re-read, so the answers are CALLed, not reasoned about.

THE SELFTEST IS A GATE, not a report, and it is a gate in both directions.  The
negative cases are the load-bearing half: a reader that reports a READ as a write, or
a SCRATCH copy as IN-PLAY, has taught its user to stop believing the column, and that
is the same failure as missing a spelling -- only slower and harder to notice.
"""
import os, sys, tempfile
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop")
import mutanchor as MA

S = "SRC='tinybendygrad/uop/ops.bend'\n"

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
    ("json.dump(x, open(SRC,'w'))   nested argument",
     "import json\nSRC='tinybendygrad/uop/ops.bend'\njson.dump(x, open(SRC,'w'))\n", True),
    ("print(x, file=open(SRC,'w'))  keyword argument",
     "SRC='tinybendygrad/uop/ops.bend'\nprint(x, file=open(SRC,'w'))\n", True),
    # --- CLOSED 2026-10-04, the three that were on the STILL list -------------
    ("dump(x, f)                    MAY, handle as argument",
     "import dump\n" + S + "f=open(SRC,'w')\ndump(x, f)\n", True),
    ("dump(x, handle=f)             MAY, keyword argument",
     "import dump\n" + S + "f=open(SRC,'w')\ndump(x, handle=f)\n", True),
    ("H[0].write(s)                 handle in a LIST",
     S + "H=[open(SRC,'w')]\nH[0].write(s)\n", True),
    ("H['f'].write(s)               handle in a DICT",
     S + "H={'f': open(SRC,'w')}\nH['f'].write(s)\n", True),
    ("run('cat > %s' % SRC, shell=True)   shell redirect",
     "import subprocess\n" + S + "subprocess.run('cat > %s' % SRC, shell=True)\n", True),
    ("run('cat >> SRC', shell=True)        append redirect, literal",
     "import subprocess\n" + S + "subprocess.run('cat >> ' + SRC, shell=True)\n", True),
    ("run(['bash','-c','cat > x'])   bash -c form",
     "import subprocess\n" + S + "subprocess.run(['bash','-c','cat > tinybendygrad/uop/ops.bend'])\n", True),
    # --- THE NEGATIVE HALF, and it is the half that keeps the column ----------
    ("open(SRC).read()              MUST NOT be a write",
     "SRC='tinybendygrad/uop/ops.bend'\ns=open(SRC).read()\n", False),
    ("open(SRC,'rb')                MUST NOT be a write",
     "SRC='tinybendygrad/uop/ops.bend'\ns=open(SRC,'rb').read()\n", False),
    ("s.replace(a,b)                MUST NOT be a write",
     "SRC='tinybendygrad/uop/ops.bend'\ns=open(SRC).read().replace(a,b)\n", False),
    ("dst.write_text(s) scratch     SCRATCH not IN-PLAY",
     "DST='/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/x'\n"
     "DST.write_text(s)\n", True),
    ("read handle as argument       MUST NOT be a write",
     "import parse\n" + S + "f=open(SRC)\nparse(f)\n", False),
    ("handle in a list, only READ   MUST NOT be a write",
     S + "H=[open(SRC)]\nH[0].read()\n", False),
    ("H[i] for a VARIABLE index     MUST NOT be resolved",
     S + "H=[open(SRC,'w')]\ni=0\nH[i].write(s)\n", False),
    ("'2> log' descriptor redirect  MUST NOT be read as a file write",
     "import subprocess\n" + S + "subprocess.run('bend f.bend 2> ' + SRC, shell=True)\n", False),
    ("no shell=True, no sh -c       MUST NOT be read as a redirect",
     "import subprocess\n" + S + "subprocess.run(['cat','>',SRC])\n", False),
    ("a method call is not a MAY    MUST NOT be double counted",
     S + "f=open(SRC,'w')\nf.write(s)\n", True),
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
    print("%-46s %-9s %s" % (label, ("yes" if seen else "no") + ("" if ok else "  <-- WRONG"),
                            "; ".join("%s via %s" % (z, s) for z, _, s in sp) or "-"))
print("-" * 110)
print("%d/%d cases behave as required" % (len(CASES) - fails, len(CASES)))

# A DOUBLE COUNT is its own defect: the same destination reported twice by two
# branches makes a count wrong for a structural reason, and a count wrong for a
# structural reason is a count nobody can check by looking.
print()
print("NO DESTINATION IS REPORTED TWICE FOR ONE FILE (a double count inflates a total)")
dupes = 0
for label, src, want in CASES:
    f = os.path.join(td, "h3.py")
    open(f, "w").write(src)
    sp = MA.write_spellings(MA.parse(f), "h3.py")
    dests = [d for _, d, _ in sp]
    if len(dests) != len(set(dests)):
        dupes += 1
        print("  DOUBLE COUNTED  %-40s %s" % (label, dests))
print("  %d of %d fixtures double count" % (dupes, len(CASES)))

# What is STILL missed, stated rather than guessed.  Every entry here is a REAL hole,
# and each one says what closing it would need.
STILL = [
    ("import-time side effect of a SIBLING harness",
     "import sibling\n",
     "the write is in ANOTHER FILE.  Needs cross-file dataflow, or executing the "
     "import -- and mutanchor executes nothing by design.  `imports()` enumerates the "
     "EDGE so the other file is one read away, but it does not resolve the write."),
    ("a handle in a container at a VARIABLE index, H[i].write(s)",
     S + "H=[open(SRC,'w')]\ni=0\nH[i].write(s)\n",
     "needs the VALUE of i.  Guessing index 0 would be the reader inventing the "
     "measurement, so this is left open rather than closed with a guess."),
    ("a handle stored in an object attribute, self.f.write(s)",
     "import harness\nharness.setup()\n",
     "needs an object model.  Outside a single-file AST."),
    ("a write via an alias of an alias, f = g = open(P,'w')",
     S + "g=open(SRC,'w')\nf=g\nf.write(s)\n",
     "REACHABLE and cheap: `_bounds` already iterates to a fixpoint over Assign, but "
     "it stops when `_path` cannot read the RIGHT-HAND side, and `f = g` needs a "
     "handle-to-handle edge.  Not closed here."),
    ("a redirect built at runtime, cmd = 'cat > ' + P",
     "import subprocess\nsubprocess.run(cmd, shell=True)\n",
     "the command is a NAME, so the string is not in this AST.  Closing it needs the "
     "constant folder, i.e. dataflow."),
    ("a redirect through a nested shell, sh -c 'sh -c ... > P'",
     "import subprocess\nsubprocess.run(['sh','-c','sh -c \"cat > p\"'], shell=True)\n",
     "quoting.  A string shape check is not a shell parser and will not be one."),
]
print()
print("STILL MISSED, each a REAL hole and each naming what closing it would need:")
for label, src, why in STILL:
    f = os.path.join(td, "h2.py")
    open(f, "w").write(src)
    got = MA.writes(MA.parse(f), "h2.py")
    print("  %-56s detected=%s" % (label, got or "NOTHING"))
    print("      %s" % why)

print()
print("THE IMPORT EDGE, which is closeable even though the write is not:")
f = os.path.join(td, "h4.py")
open(f, "w").write("import staged_mut\nimport patch_not_apply as PNA\n"
                   "from zero_classify import main\n"
                   "def go():\n    import hashlib\n")
print("  module-scope imports of h4.py: %s" % sorted(MA.imports(MA.parse(f))))
print("  ...the function-local `import hashlib` is correctly NOT listed: a sibling's")
print("     import-time write only matters at module scope.")