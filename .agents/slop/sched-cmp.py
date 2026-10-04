#!/usr/bin/env python3
"""STAGE 2 COMPARATOR -- the port's rows against CPython's, FIELD BY FIELD.

It diffs WHOLE `name=value` lines, never row NAMES (the agent-core rule about the
harness that reported 0 for all 30 mutations in one unit), and it reports the
DENOMINATOR: specs attempted, specs scheduled, fields compared, fields agreeing --
every one of those five COMPUTED. They were literals once (`specs_attempted=6`
typed into an f-string while `fields_compared` was computed beside it), which is
the shape of the forked readers: one side computed, the other transcribed.

THE PORT SIDE IS PRODUCED BY THIS RUN. `./bin/bend <fixture>` is executed here and
its stdout IS the port side. `sched-port.txt` is read only to say whether the
committed snapshot is still FRESH. MEASURED WHY (audit 03 PLANT 2): a port edit
(`Lin.out` -> `List.drop(out, 1n)`) left the committed snapshot comparing at 60/60
rc=0, while feeding the mutated port's real output in by hand read 24/60 rc=1. The
comparator was never wrong about the values it was given; it was reading a snapshot
that no run had produced. A comparison whose port side this run did not produce now
says `SNAPSHOT_STALE` and is red, rather than reporting agreement.

THE ENCODING IS THE PORT'S, re-done here in Python, so the two sides are compared
in the same alphabet. `DIG` below is `dig` in `.agents/slop/sched-fixture.bend`,
field for field and value for value:

    AFTER 1  CALL 2  END 3  STORE 4  SINK 5  PARAM 6  BUFFER 7  ALLOC 8
    LINEAR 9  CONST 10 RANGE 11 MUL 12  ADD 13   INDEX 14 REDUCE 15 MAX 16
    CAST 17  (anything else 0)

`pack` is base36 over the flat src-op sequence; `pack16` is base16 over the
per-kernel arities; `ktop`/`kmark` are base36 over the per-kernel body op and over
the STORE's value op.

AN OP WITH NO CODE BECOMES 0, ON BOTH SIDES. So an op the port has not ported reads
as an agreement about the digit 0 -- and so does an EMPTY sequence, and so does a
STORE-less kernel. Three different questions, one answer, measured:

    pack(['SHR', 'SHL']) = 0     two uncoded ops
    pack([])           = 0       an empty src sequence
    pack([''])         = 0       absence, which `store_val_op` spells ''

`dig` therefore COUNTS every name it cannot code, and `main` prints that census and
turns the run RED on it. The census used to be a loop that discarded its result --
this docstring claimed it was printed and it was not, which is the fourth docstring
in this project found asserting a behaviour its file lacks. ARMED, not hypothetical:
the `where` spec built in `sched-oracle.py` puts a `WHERE` (an op `DIG` does not
code) straight into a compared `_kmark` field, and the port -- whose `dig` has the
same 17 codes and the same `case _ : 0` fallthrough -- answers 0 too. Pre-fix that
run printed `AGREE where_kmark=0` and `fields_agree=70 fields_disagree=0` with rc=0
and no mention of either word. See `unfalsifiable/sched-uncoded-arm.py`.

RUN:
  env -u PYTHONPATH LC_ALL=C DEV=NONE .venv/bin/python .agents/slop/sched-cmp.py
"""
import os, sys, collections, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
sys.path.insert(0, ROOT)
sys.path.insert(0, HERE)

DIG = {"AFTER": 1, "CALL": 2, "END": 3, "STORE": 4, "SINK": 5, "PARAM": 6,
       "BUFFER": 7, "ALLOC": 8, "LINEAR": 9, "CONST": 10, "RANGE": 11, "MUL": 12,
       "ADD": 13, "INDEX": 14, "REDUCE": 15, "MAX": 16, "CAST": 17}
U32 = 1 << 32

# THE FIELDS PER SPEC, AS THE ONE PLACE THE WIDTH IS WRITTEN. The denominator line
# is `len(SPEC_FIELDS)`, so a field added or removed here moves it -- which is what
# the literal `6 specs x {n // 6}` could not do.
SPEC_FIELDS = ("gated", "root_op", "lin_n", "lin_op", "ksrc", "ksrc_n", "knsrc",
               "ktop", "kmark", "cyc")

# THE UNCODED-OP CENSUS, ACCUMULATED WHERE IT IS IMPOSSIBLE TO FORGET. `dig` is the
# single funnel for all three packed fields and both single-name fields, so a field
# added later is covered without being remembered here.
UNCODED = collections.Counter()


def dig(name):
  v = DIG.get(name, 0)
  if v == 0:
    UNCODED[name] += 1
  return v


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
  the kernel. '' when there is no STORE -- and '' is NOT a code, so it packs to 0,
  which the census reports as `<empty>` rather than letting it hide as a digit."""
  for u in k.toposort():
    if u.op.name == "STORE":
      return u.src[1].op.name
  return ""


def spec_of(field_name):
  """`elementwise_ksrc_n` -> `elementwise`. Longest-suffix over the declared field
  list, so the parse cannot go stale the way a literal split on `_` would --
  `matmul_sym` contains one."""
  for f in SPEC_FIELDS:
    if field_name.endswith("_" + f):
      return field_name[:-len(f) - 1], f
  return field_name, "<unrecognised-field>"


def cpy_rows():
  """CPython's rows, recomputed by CALLING `create_schedule` again -- not read
  out of sched-oracle.txt. Two independent computations of the same expectation
  is the cheapest corroboration there is, and agent-core records the case where
  a mistake existed in BOTH the port and a hand-typed oracle.

  Returns (rows, attempted, scheduled). A spec that RAISES or schedules nothing is
  counted as NOT scheduled and contributes no fields, so `specs_scheduled` is a
  measurement and one bad spec cannot kill the run on its own data.
  """
  import importlib.util
  sp = importlib.util.spec_from_file_location("so", os.path.join(HERE, "sched-oracle.py"))
  SO = importlib.util.module_from_spec(sp)
  sp.loader.exec_module(SO)
  rows, scheduled = {}, 0
  for name, fn in SO.SPECS:
    SO._reset()
    SO._CAPTURED.clear()
    try:
      fn()
    except Exception as e:
      print(f"# CPYTHON_RAISED {name} {type(e).__name__}: {e}", file=sys.stderr)
      continue
    if not SO._CAPTURED:
      print(f"# CPYTHON_NO_SCHEDULE {name}", file=sys.stderr)
      continue
    scheduled += 1
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
  return rows, len(SO.SPECS), scheduled


def parse_rows(text):
  out = {}
  for ln in text.splitlines():
    ln = ln.strip()
    if "=" in ln and not ln.startswith("#") and not ln.startswith("bend"):
      k, v = ln.split("=", 1)
      out[k] = int(v)
  return out


def live_port_rows():
  """THE PORT SIDE, PRODUCED BY THIS RUN. Returns (rows, rc, note).

  `HERE` resolves the fixture, so a plant directory carries its own fixture and its
  own snapshot and the comparison stays inside the directory it was pointed at."""
  bend = os.path.join(ROOT, "bin/bend")
  fixture = os.path.join(HERE, "sched-fixture.bend")
  if not os.path.exists(fixture):
    return {}, None, f"NO FIXTURE at {fixture}"
  env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
  env["LC_ALL"] = "C"
  env["DEV"] = "NONE"
  r = subprocess.run([bend, fixture], capture_output=True, text=True, env=env,
                     cwd=ROOT, timeout=3600)
  note = r.stderr.strip().splitlines()[0] if r.stderr.strip() else ""
  return parse_rows(r.stdout), r.returncode, note


def main():
  cpy, attempted, scheduled = cpy_rows()
  port, brc, bnote = live_port_rows()
  snap = {}
  spath = os.path.join(HERE, "sched-port.txt")
  if os.path.exists(spath):
    with open(spath) as f:
      snap = parse_rows(f.read())
  bad = []

  print(f"# port side: this run's `./bin/bend` -> {len(port)} rows, rc={brc} "
        f"{bnote}")
  if not port:
    bad.append("NO_PORT_ROWS")
    print("# VERDICT NO_PORT_ROWS -- the port produced nothing this run, so there is "
          "no agreement to report")
  if snap != port:
    bad.append("SNAPSHOT_STALE")
    diff = sorted(set(snap) ^ set(port)) or \
        sorted(k for k in snap if snap[k] != port[k])
    print(f"# SNAPSHOT_STALE sched-port.txt holds {len(snap)} rows, this run produced "
          f"{len(port)}; {len(diff)} key(s) differ, first 5: "
          f"{[(k, snap.get(k), port.get(k)) for k in diff[:5]]}")
  else:
    print("# SNAPSHOT_FRESH sched-port.txt matches this run's output")

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
  compared = len(agree) + len(disagree)
  per = collections.Counter(spec_of(n)[0] for n in agree + [d[0] for d in disagree])
  print(f"# specs_attempted={attempted} specs_scheduled={scheduled} "
        f"fields_compared={compared} fields_agree={len(agree)} "
        f"fields_disagree={len(disagree)} port_only={len(missing)}")
  print(f"# denominator: {compared} fields = {len(per)} specs x "
        f"{len(SPEC_FIELDS)} fields")
  ragged = {s: c for s, c in per.items() if c != len(SPEC_FIELDS)}
  if ragged:
    bad.append("RAGGED_DENOMINATOR")
    print(f"# RAGGED_DENOMINATOR these specs do not carry {len(SPEC_FIELDS)} fields "
          f"each: {ragged} -- the denominator above is not {len(specs)} x "
          f"{len(SPEC_FIELDS)}")
  for n, c, p in disagree:
    print(f"DISAGREE {n} cpython={c} port={p}")
  for n in missing:
    print(f"PORT_ONLY {n}={port[n]}")
  for n in sorted(agree):
    print(f"AGREE {n}={cpy[n]}")

  # THE UNCODED-OP CENSUS, FOR REAL. Every name `dig` coded as 0 -- an unported op,
  # or '' for a kernel with no STORE -- is reported by name. `pack` is not injective
  # over these, so a field built only from them agrees with `pack([])`.
  if UNCODED:
    bad.append("UNCODED")
    c = " ".join(f"{k or '<empty>'}={v}" for k, v in sorted(UNCODED.items()))
    print(f"# UNCODED {len(UNCODED)} distinct name(s) in {sum(UNCODED.values())} packed "
          f"occurrence(s), each read as digit 0 on BOTH sides: {c}")
    print("# VERDICT UNCODED -- pack is not injective over these: an uncoded op, an "
          "empty src sequence and an absent STORE all pack to 0, so the fields "
          "naming them agree about nothing. Code the op in DIG and in the port's "
          "dig.")
  else:
    print("# UNCODED 0 -- every name packed into a compared field has a code")
  print(f"# alphabet={len(DIG)} ops, digit 0 reserved for 'no code'")
  if disagree:
    bad.append("DISAGREE")
  print(f"# VERDICT {'RED ' + ','.join(bad) if bad else 'AGREE'}")
  return 1 if bad else 0


if __name__ == "__main__":
  sys.exit(main())