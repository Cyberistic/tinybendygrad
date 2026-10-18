#!/usr/bin/env python3
"""census-dev-gate.py -- the census's DEVICE precondition can still bite, and the token it
stopped comparing is an ABSENCE rather than a device.

    .venv/bin/python gates/census-dev-gate.py

FIVE LANES, AND NOT ONE OF THEM NEEDS `bend`. The rule under test is `device_verdict` in
`.agents/slop/graphcmp-oracle.py`, imported BY PATH -- not copied, so this gate cannot pass on a
rule the census no longer has. Lanes 6 and 7 read the differ's own `D0-coverage-census.txt` and
REFUSE (exit 3) when it is absent.

THE DEFECT THIS EXISTS SO IT CANNOT COME BACK. `devnames` returns ParamArg's eighth field as
TEXT, and that field prints `ATOMS["none"]` whenever `device` is None. The census compared the
raw sets, so an ABSENCE arrived where a device NAME belonged, and `loop` -- whose CPython graph
carries four addrspace-REG temps from `get_time_ms`/`do_get_time_ms` (`hcq2.py:65-78`) that the
bend fixture does not model -- failed `# ORACLE SELFCHECK` and took `census-rc` to 1. MEASURED
2026-10-18, `runs/graphcmp/D/D0-coverage-census.txt`: `loop: the two sides opened DIFFERENT
devices -- py ['N', 'sCPU'] against bend ['sCPU']`.

A REFINEMENT IS ONLY HONEST IF IT IS SHOWN TO STILL REJECT, so lane 3 is the one that matters:
it feeds the verdict a device MISMATCH and requires `DIFFERENT-DEVICES`. A gate that only ever
sees the case that now passes is a gate that measured the fix, not the rule.

LANES. (1) `N` is `ATOMS["none"]` and is spelled by `graphcmp.py` for `device=None`,
`sNULL` for the NULL DEVICE and `sCPU` for `CPU` -- so `N` cannot be a device name read wrong.
(2) The PORT renders a device-less ParamArg as the same `N` (`graphcmp.bend`'s `dm`), so the two
sides were never spelled differently. (3) `device_verdict` still returns `DIFFERENT-DEVICES` on a
mismatch -- the fatal branch BITES. (4) The three MEASURED corpus verdicts: `loop`'s py/bend sets
-> `ONE-SIDE-DEVICE-LESS`, `sym`'s -> `AGREE`, a hypothetical `CPU` against `METAL` ->
`DIFFERENT-DEVICES`. (5) `N` is in no `devnames` result as a NAME, i.e. `NODEV` removes nothing
that is a device: over all 34 graphs the py side's only device NAME is `sCPU`. (6, 7) The two
UNIONS the census takes -- `tot_ops` and `tot_atoms` -- carry no bend-only name, which is what
"not fatal" costs: a row the port models and CPython does not would put a name in a corpus total
that is not CPython's. (8) The absence atom never rides on an `SGLOBAL` ParamArg, so a
device-less row cannot select a `core` -- which is the invariant the fatal branch guards.

WHAT THIS DOES NOT CLAIM. It does not claim the census is now correct about `loop` -- that graph
is still REFUSED, by `_dispatch`, for the reason it was always refused (25 of 52 nodes modelled).
It claims the census no longer refuses a census over an absence token, and still refuses over a
device. `differ.py` owns the REFUSED verdict and is not touched here.
"""

import importlib.util
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
ROOT = Path(__file__).resolve().parents[1]
os.environ["DEV"] = "CPU"
sys.path.insert(0, str(ROOT / ".agents/slop"))

checks: list[tuple[bool, str]] = []


def report(name: str, ok: bool, evidence: list[str] | None = None) -> None:
  checks.append((ok, name))
  print(f"  {'PASS' if ok else 'FAIL'}  {name}")
  for e in evidence or []:
    print(f"        {e}")


def load(name: str, path: Path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


G = load("gc", ROOT / ".agents/slop/graphcmp.py")
G.load_tinygrad()
O = load("oracle", ROOT / ".agents/slop/graphcmp-oracle.py")

from tinygrad.dtype import dtypes  # noqa: E402
from tinygrad.uop.ops import ParamArg  # noqa: E402


def field(pa: ParamArg) -> str:
  return G.split_top(G.paramarg(pa)[2:-1])[7]


# 1 -- `N` is the absence atom, and the NULL DEVICE is spelled differently.
spelling = {"device=None": field(ParamArg(slot=0, dtype=dtypes.uint64)),
            'device="NULL"': field(ParamArg(slot=0, dtype=dtypes.uint64, device="NULL")),
            'device="CPU"': field(ParamArg(slot=0, dtype=dtypes.uint64, device="CPU"))}
report("1 `N` is ATOMS[\"none\"] -- the NULL DEVICE spells `sNULL`, so `N` is not a device",
       O.NODEV == frozenset({G.ATOMS["none"]}) and G.ATOMS["none"] == "N"
       and spelling == {"device=None": "N", 'device="NULL"': "sNULL", 'device="CPU"': "sCPU"},
       [f"{k} -> {v!r}" for k, v in spelling.items()])

# 2 -- the port renders its device-less ParamArg the same way, read as TEXT (no `bend`).
dm = re.search(r"def dm\(m: Maybe<&2, S\.Dev>\) -> String:.*?case _: (\S+)", (ROOT / ".agents/slop/graphcmp.bend").read_text(), re.S)
port_none = dm.group(1) if dm else "NOT-FOUND"
report("2 graphcmp.bend's `dm` prints the SAME absence atom, so the sides were never spelled "
       "differently", port_none == '"N"', [f"graphcmp.bend dm -> {port_none}"])

# 3 -- THE LANE THAT MATTERS: the fatal branch still rejects a device mismatch.
v = O.device_verdict({"sCPU"}, {"sMETAL"})
report("3 device_verdict STILL returns DIFFERENT-DEVICES on a device mismatch (the fatal "
       "branch bites)", v[0] == "DIFFERENT-DEVICES", [f"device_verdict({{'sCPU'}}, "
       f"{{'sMETAL'}}) -> {v}"])

# 4 -- the three MEASURED corpus verdicts.
measured = [("loop py=['N','sCPU'] bend=['sCPU']", {"N", "sCPU"}, {"sCPU"}, "ONE-SIDE-DEVICE-LESS"),
            ("sym  py=['N','sCPU'] bend=['N','sCPU']", {"N", "sCPU"}, {"N", "sCPU"}, "AGREE"),
            ("CPU against METAL", {"sCPU"}, {"sMETAL"}, "DIFFERENT-DEVICES")]
rows = []
ok4 = True
for label, p, b, want in measured:
  got = O.device_verdict(p, b)[0]
  ok4 &= got == want
  rows.append(f"{label} -> {got} (want {want})")
report("4 the three MEASURED corpus verdicts", ok4, rows)

# 5 -- `NODEV` discards no device: over all 34 graphs the only device NAME is `sCPU`.
names: set[str] = set()
for g in G.GRAPHS:
  names |= G.devnames(G.emit_py(g, None)) - O.NODEV
report("5 NODEV removes no device NAME -- every graph's py-side device name is `sCPU`",
       names == {"sCPU"}, [f"py-side device names over {len(G.GRAPHS)} graphs: {sorted(names)}"])

# 6, 7 -- THE CONTAMINATION QUESTION. `main()` takes `tot_ops` and `tot_atoms` as UNIONS of
# both sides, so a bend row the port models and CPython does not would put a name in a corpus
# total that is not CPython's -- and the fix above stops that row from being FATAL, so this is
# where "not fatal" has to be paid for. Read the differ's OWN artifact for what the union was
# and measure the py side live: the two are equal exactly when no graph contributed a bend-only
# name. Nothing here transcribes 68 or 16 -- both numbers come from the artifact in front of us,
# which is why this lane is REFUSED (3) rather than PASS when the artifact is absent.
ART = ROOT / "runs/graphcmp/D/D0-coverage-census.txt"
if not ART.is_file():
  print(f"  REFUSED  6,7 the differ's census artifact is ABSENT ({ART}), so the unions cannot "
        f"be compared against the live py side -- an absent input is not a pass")
  sys.exit(3)
text = ART.read_text(errors="replace")


def printed(pat: str) -> int | None:
  m = re.search(pat, text)
  return int(m.group(1)) if m else None


py_ops: set[str] = set()
py_atoms: set[str] = set()
for g in G.GRAPHS:
  for ln in G.emit_py(g, None):
    arg = G.unchunks(ln)[6]
    py_ops.add(G.unchunks(ln)[1])
    py_atoms |= O.atoms(arg)
comp = set(c[0] for c in G.COMPOSITE)

u_ops, p_ops = printed(r"nodes per side, (\d+) distinct ops"), len(py_ops)
report("6 `# TOTAL`'s op UNION carries no bend-only name (artifact's union == live py side)",
       u_ops is not None and u_ops == p_ops,
       [f"artifact `# TOTAL: ... {u_ops} distinct ops` against py-side {p_ops} over "
        f"{len(G.GRAPHS)} graphs; a bend-only name would make the first exceed the second"])

u_atoms = printed(r"DISTINCT ARG ATOM LETTERS REACHED: \S+ \((\d+) distinct")
report("7 `# DISTINCT ARG ATOM LETTERS`'s UNION carries no bend-only name",
       u_atoms is not None and u_atoms == len(py_atoms),
       [f"artifact `({u_atoms} distinct` against py-side {len(py_atoms)} "
        f"{''.join(sorted(py_atoms))}"])

# 8 -- WHY THE ABSENCE CANNOT SELECT A CORE, which is the whole reason lane 3's middle answer
# is not a failure. The invariant the check exists for is "an ALLOC's device selects its `core`",
# and an ALLOC is `addrspace=SGLOBAL`. So: over every `P(...)` row of every graph, the absence
# atom appears in the device field ONLY on REG or ALU temps, never on a global one. A
# device-less row is therefore a temp that selects no core, and the sentence the check used to
# print -- "this row's counts are about two different graphs", by way of a device disagreement --
# had no device disagreement behind it. MEASURED: the pairs are exactly these three.
nodev_addr: set[str] = set()
named_addr: set[str] = set()
for g in G.GRAPHS:
  for ln in G.emit_py(g, None):
    arg = G.unchunks(ln)[6]
    if not arg.startswith("P("):
      continue
    f = G.split_top(arg[2:-1])          # ParamArg's thirteen fields, in the order `paramarg` writes them
    (nodev_addr if f[7] in O.NODEV else named_addr).add(f[6])   # field 6 addrspace, field 7 device
report("8 the absence atom never rides on an `SGLOBAL` ParamArg, so a device-less row cannot "
       "select a core",
       not (nodev_addr & named_addr) and "SGLOBAL" not in nodev_addr
       and nodev_addr and named_addr,
       [f"addrspaces on device-less rows: {sorted(nodev_addr)}; on named-device rows: "
        f"{sorted(named_addr)}; both non-empty, because an earlier revision of this lane read "
        f"field 7 with a hand-rolled split, got the NAME column, and PASSED on `[]` -- a check "
        f"that is satisfied by reading nothing is satisfied by being broken"])

failed = [n for ok, n in checks if not ok]
print(f"# census-dev-gate: {len(checks) - len(failed)} of {len(checks)} PASS")
if failed:
  print(f"# FAILED: {failed}")
sys.exit(1 if failed else 0)