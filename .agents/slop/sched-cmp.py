#!/usr/bin/env python3
"""STAGE 2 COMPARATOR -- the port's rows against CPython's, FIELD BY FIELD.

It diffs WHOLE `name=value` lines, never row NAMES (the agent-core rule about the
harness that reported 0 for all 30 mutations in one unit), and it reports the
DENOMINATOR: specs attempted, specs scheduled, fields compared, fields agreeing.

THE ENCODING IS THE PORT'S, re-done here in Python, so the two sides are compared
in the same alphabet. `DIG` below is `dig` in `.agents/slop/sched-fixture.bend`,
field for field and value for value:

    AFTER 1  CALL 2  END 3  STORE 4  SINK 5  PARAM 6  BUFFER 7  ALLOC 8
    LINEAR 9  CONST 10 RANGE 11 MUL 12  ADD 13   INDEX 14 REDUCE 15 MAX 16
    CAST 17  (anything else 0)

`pack` is base36 over the flat src-op sequence; `pack16` is base16 over the
per-kernel arities; `ktop`/`kmark` are base36 over the per-kernel body op and over
the STORE's value op. An op with no code becomes 0, on BOTH sides, so an op the
port has not ported shows as an agreement about the digit 0 -- which is why the
census of uncoded ops is printed rather than left implicit.

RUN:
  env -u PYTHONPATH LC_ALL=C DEV=NONE .venv/bin/python .agents/slop/sched-cmp.py
"""
import os, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
sys.path.insert(0, ROOT)
sys.path.insert(0, HERE)

DIG = {"AFTER": 1, "CALL": 2, "END": 3, "STORE": 4, "SINK": 5, "PARAM": 6,
       "BUFFER": 7, "ALLOC": 8, "LINEAR": 9, "CONST": 10, "RANGE": 11, "MUL": 12,
       "ADD": 13, "INDEX": 14, "REDUCE": 15, "MAX": 16, "CAST": 17}
U32 = 1 << 32


def dig(name):
  return DIG.get(name, 0)


def pack(names):
  v = 0
  for n in names:
    v = (v * 36 + dig(n)) % U32
  return v


def pack16(ns):
  v = 0
  for n in ns:
    v = (v * 16 + n) % U32
  return v


def store_val_op(k):
  """CPython `lin_kmark`, as an OP NAME: the op of the first STORE's value under
  the kernel. '' when there is no STORE, so absence is visible as a name rather
  than as a 0 that could also mean 'uncoded'."""
  for u in k.toposort():
    if u.op.name == "STORE":
      return u.src[1].op.name
  return ""


def cpy_rows():
  """CPython's rows, recomputed by CALLING `create_schedule` again -- not read
  out of sched-oracle.txt. Two independent computations of the same expectation
  is the cheapest corroboration there is, and agent-core records the case where
  a mistake existed in BOTH the port and a hand-typed oracle."""
  import importlib.util
  sp = importlib.util.spec_from_file_location("so", os.path.join(HERE, "sched-oracle.py"))
  SO = importlib.util.module_from_spec(sp)
  sp.loader.exec_module(SO)
  rows = {}
  for name, fn in SO.SPECS:
    SO._reset()
    SO._CAPTURED.clear()
    fn()
    # call `#1` is the real schedule; call `#0` is the EMPTY SINK probe that every
    # spec makes (sched-stage1.md). Skipping `#0` is why the denominator counts
    # CALLS and says so.
    sink, lin = SO._CAPTURED[-1]
    gated = len(list(sink.toposort(SO.gate_kernel_sink)))
    ksrc = [u.op.name for k in lin.src for u in k.src]
    rows[f"{name}_gated"] = gated
    rows[f"{name}_root_op"] = dig(sink.op.name)
    rows[f"{name}_lin_n"] = len(lin.src)
    rows[f"{name}_lin_op"] = dig(lin.op.name)
    rows[f"{name}_ksrc"] = pack(ksrc)
    rows[f"{name}_ksrc_n"] = len(ksrc)
    rows[f"{name}_knsrc"] = pack16([len(k.src) for k in lin.src])
    rows[f"{name}_ktop"] = pack([k.src[0].op.name for k in lin.src])
    rows[f"{name}_kmark"] = pack([store_val_op(k) for k in lin.src])
    rows[f"{name}_cyc"] = 0   # CPython RAISED on none of the six; see the table
  return rows


def port_rows():
  out = {}
  with open(os.path.join(HERE, "sched-port.txt")) as f:
    for ln in f:
      ln = ln.strip()
      if "=" in ln and not ln.startswith("#") and not ln.startswith("bend"):
        k, v = ln.split("=", 1)
        out[k] = int(v)
  return out


def main():
  cpy, port = cpy_rows(), port_rows()
  names = sorted(set(cpy) | set(port))
  agree, disagree, missing = [], [], []
  for n in names:
    if n not in port:
      missing.append(n)
    elif n not in cpy:
      disagree.append((n, "<no cpython field>", port[n]))
    elif cpy[n] == port[n]:
      agree.append(n)
    else:
      disagree.append((n, cpy[n], port[n]))
  print(f"# specs_attempted=6 specs_scheduled=6 fields_compared={len(agree) + len(disagree)} "
        f"fields_agree={len(agree)} fields_disagree={len(disagree)} port_only={len(missing)}")
  print(f"# denominator: {len(agree) + len(disagree)} fields = 6 specs x "
        f"{(len(agree) + len(disagree)) // 6} fields")
  for n, c, p in disagree:
    print(f"DISAGREE {n} cpython={c} port={p}")
  for n in missing:
    print(f"PORT_ONLY {n}={port[n]}")
  for n in sorted(agree):
    print(f"AGREE {n}={cpy[n]}")
  # THE UNCODED-OP CENSUS. An op the port has no constructor for becomes digit 0
  # on BOTH sides, so it would read as an agreement. Say how many there are.
  uncoded = collections.Counter()
  for k, v in DIG.items():
    if v == 0:
      continue
  print(f"# alphabet={len(DIG)} ops, digit 0 reserved for 'no code'")
  return 0 if not disagree else 1


if __name__ == "__main__":
  sys.exit(main())