"""FLIPR-1 falsification. `canon_flip` rewrites a letter; a test that cannot see a real
difference in FLIP's arg is not a test. Run plainly:
    .venv/bin/python .agents/slop/flip/canon-falsify.py
"""
import importlib.util, pathlib, sys

REPO = pathlib.Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("gc", REPO / ".agents" / "slop" / "graphcmp.py")
gc = importlib.util.module_from_spec(spec)
sys.modules["gc"] = gc
spec.loader.exec_module(gc)

B, I = gc.ATOMS["bool"], gc.ATOMS["u32"]
fails = []


def check(name, cond):
  print(f"  {'ok  ' if cond else 'FAIL'} {name}")
  if not cond:
    fails.append(name)


print("== canon_flip's TEXT, directly ==")
for op, arg, want_arg, want_n in [
    ("FLIP", f"n({B}1,{B}0)", f"n({I}1,{I}0)", 2),
    ("FLIP", f"n({B}1,{B}1)", f"n({I}1,{I}1)", 2),
    ("PERMUTE", f"n({B}1,{B}0)", f"n({B}1,{B}0)", 0),      # NOT FLIP: untouched
    ("RESHAPE", f"n({B}1,{B}0)", f"n({B}1,{B}0)", 0),       # not FLIP
    ("FLIP", f"n({I}1,{I}0)", f"n({I}1,{I}0)", 0),           # already u32
    ("FLIP", "P(i0,Df32,i12,N,N,N,SGLOBAL,sCPU,b0,N,N,b1,N)",
             "P(i0,Df32,i12,N,N,N,SGLOBAL,sCPU,b0,N,N,b1,N)", 0),   # bools OUTSIDE n(..)
]:
  got, n = gc.canon_flip(op, arg)
  check(f"{op} {arg!r} -> {got!r} (n={n}, want {want_arg!r}/{want_n})", (got, n) == (want_arg, want_n))

print("\n== THE DIFFER MUST STILL SEE A REAL ARG CHANGE ==")
py = ["2:i1 5:ALLOC 3:f32 7:(l0:12) 2:i0 1:N 45:P(i0,Df32,i12,N,N,N,SGLOBAL,sCPU,b0,N,N,b1,N) 3:n()",
      "2:i2 5:CONST 7:weakint 2:() 2:i0 1:N 4:l0:4 3:n()",
      "2:i3 5:CONST 7:weakint 2:() 2:i0 1:N 4:l0:3 3:n()",
      "2:i4 5:STACK 7:weakint 6:(l0:2) 2:i0 1:N 1:N 8:n(i2,i3)",
      "2:i5 7:RESHAPE 3:f32 11:(l0:4,l0:3) 2:i0 1:N 1:N 8:n(i1,i4)"]


def graph(arg):
  # `unchunks` reads `<bytecount>:<that many bytes>`, so a shorter tuple needs its OWN
  # count -- MEASURED, writing `8:n(i1)` raised `ValueError: substring not found` at
  # `graphcmp.py:363` because the reader took 8 bytes and swallowed the next chunk's `5:`.
  return py + [f"2:i6 4:FLIP 3:f32 11:(l0:4,l0:3) 2:i0 1:N {len(arg)}:{arg} 5:n(i5)"]


def pairs(a, b):
  _, ca, _ = gc.build(graph(a), "py")
  _, cb, _ = gc.build(graph(b), "bend")
  return len(set(ca) & set(cb))


same = pairs(f"n({B}1,{B}0)", f"n({I}1,{I}0)")
check(f"the two SPELLINGS pair: shared cores = {same} (want 6)", same == 6)

flipped = pairs(f"n({B}1,{B}0)", f"n({I}0,{I}1)")     # axes genuinely swapped
check(f"a REAL flip-arg change does NOT pair: shared = {flipped} (want 5)", flipped == 5)

both = pairs(f"n({B}1,{B}1)", f"n({I}1,{I}1)")        # both flags true
check(f"both-flags-true on both sides DOES pair: shared = {both} (want 6)", both == 6)

mismatch = pairs(f"n({B}1,{B}1)", f"n({I}1,{I}0)")
check(f"flag VALUES differing does NOT pair: shared = {mismatch} (want 5)", mismatch == 5)

short = pairs(f"n({B}1,{B}0)", f"n({I}1)")             # length differs
check(f"a length change does NOT pair: shared = {short} (want 5)", short == 5)

print("\n== SELF-AGREEMENT (the control this all rests on) ==")
n_b, _, _ = gc.build(graph(f"n({B}1,{B}0)"), "py")
once, n1 = gc.canon_flip("FLIP", f"n({B}1,{B}0)")
twice, n2 = gc.canon_flip("FLIP", once)
check(f"canon_flip is idempotent: {twice!r} n=({n1},{n2})", (twice, n2) == (once, 0))
check("bnorm is 2 for the bool side and 0 for the u32 side",
      [sum(x.bnorm for x in n_b.values())] == [2])

print(f"\nRESULT: {'OK' if not fails else 'FAIL ' + repr(fails)}")
sys.exit(1 if fails else 0)