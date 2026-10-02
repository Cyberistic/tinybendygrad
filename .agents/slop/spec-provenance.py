#!/usr/bin/env python
# Why is spec.bend's te_len 56 and CPython's 55? PROVENANCE, not assertion.
#
# spec.bend's own header claims `tensor_own()` is "CPython's 22 tensor rules plus a
# DUPLICATE of one of the 33 shared ones", and that the duplicate is CUSTOM_FUNCTION at
# tensor index 4 / shared tag 22. That claim is CHECKED here against the real pattern
# lists rather than believed, because a header comment asserting its own correctness is
# the `device.bend` `sig=0 4 5` failure mode.
#
# The question a count cannot answer: WHICH rule is extra, and is it a genuine duplicate
# or a rule CPython has and the port dropped?
import os, sys, collections

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from tinygrad.uop.ops import Ops
import tinygrad.uop.spec as SP


def ops_name(p):
  return "|".join(sorted(o.name for o in p.op))


def rej_name(p):
  return "|".join(sorted(o.name for o in p.early_reject))


def key(p):
  return (ops_name(p), rej_name(p), p.name)


shared = SP.spec_shared.patterns
tensor = SP.spec_tensor.patterns
print(f"# shared={len(shared)} tensor={len(tensor)}")
print(f"# tensor_own={len(tensor) - len(shared)}")

# ---- the SET comparison: which tensor rules are literally shared rules? -----------
shared_keys = {}
for i, (p, _) in enumerate(shared):
  shared_keys.setdefault(key(p), []).append(i)

print("# --- tensor rules whose (ops,reject,name) is IDENTICAL to some shared rule ---")
tensor_own_n = len(tensor) - len(shared)
for i, (p, _) in enumerate(tensor):
  if i >= tensor_own_n:
    print(f"#   idx {i}: IN THE SHARED TAIL (not an own rule)")
    continue
  k = key(p)
  if k in shared_keys:
    print(f"#   idx {i}: DUP of shared tags {shared_keys[k]}  ops={k[0]} rej={k[1]} name={k[2]}")
  else:
    print(f"#   idx {i}: own  ops={k[0]} rej={k[1]} name={k[2]}")

# ---- the POSITIONAL alignment: does tensor[i] line up with what the port cites? ----
print("# --- own rules, in order, with their spec.py-ish identity ---")
for i, (p, _) in enumerate(tensor):
  if i < tensor_own_n:
    print(f"own[{i}] ops={ops_name(p)} rej={rej_name(p)} name={p.name}")
  else:
    print(f"tail[{i}] ops={ops_name(p)} rej={rej_name(p)} name={p.name}")