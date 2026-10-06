#!/usr/bin/env python3
"""Check every `# py=` comment in ops_dsp.bend against the INTERPRETED lane's
output.  A `py=` that disagrees is a WRONG EXPECTATION, which is a port bug or a
transcription bug -- either way it must not survive.
Usage: python3 .agents/slop/dsp_gate_check.py <lane-output-file>

THIS HAS NO AUTHORITY. Both sides of this comparison come out of ops_dsp.bend: the
lane's printed value and the `py=` literal baked into the same file. It therefore
answers "is the port self-consistent", never "does the port agree with CPython",
and it must never print the word CPython -- the day it can, it is a real gate and
this file is a strictly weaker thing. It says so on every run so nobody has to
remember.
"""
import re, sys
SRC = "tinybendygrad/runtime/ops_dsp.bend"
out = {}
for ln in open(sys.argv[1]):
  if "=" in ln:
    k, v = ln.rstrip("\n").split("=", 1)
    out[k] = v
# 0 rows is not 0 disagreements: an empty lane file used to print "py= rows
# matching: 0" and exit 0, which reads exactly like a clean run.
if not out:
  sys.exit("LANE DID NOT RUN: %s printed 0 name=value rows, so nothing was compared."
           % sys.argv[1])
bad, ok, noexp = [], 0, []
for i, ln in enumerate(open(SRC), 1):
  m = re.search(r'\b(?:row|urow|srow|lrow)\("([^"]+)",.*?#\s*py=(.*)$', ln)
  if not m:
    continue
  name, want = m.group(1), m.group(2).strip()
  if name not in out:
    noexp.append((i, name, "NOT PRINTED")); continue
  got = out[name]
  # normalise the documented "8,16,8 then 16 zeros" shorthand
  if want != got:
    bad.append((i, name, want, got))
  else:
    ok += 1
print(f"AUTHORITY: NONE -- both sides of this comparison come from {SRC}")
print(f"py= rows matching: {ok}")
print(f"py= rows MISMATCHED: {len(bad)}")
for i, n, w, g in bad:
  print(f"  line {i} {n}: py={w!r} got={g!r}")
print(f"rows with a py= but never printed: {len(noexp)}")
for i, n, w in noexp: print(f"  line {i} {n}: {w}")
# also: rows printed with no py= comment at all
src_rows = set()
for ln in open(SRC):
  m = re.search(r'\b(?:row|urow|srow|lrow)\("([^"]+)"', ln)
  if m: src_rows.add(m.group(1))
print(f"rows in source: {len(src_rows)}  rows printed: {len(out)}")
for k in sorted(src_rows - set(out)): print(f"  SOURCE ROW NEVER PRINTED: {k}")
for k in sorted(set(out) - src_rows): print(f"  PRINTED BUT NOT IN SOURCE: {k}")
