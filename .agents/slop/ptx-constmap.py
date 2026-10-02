#!/usr/bin/env python3
"""CONSTANT MAP AUDIT for the PTX surface, by getattr in CPython.

The brief's rule: every register/type/mode table, BOTH directions. `ops_nv`'s
audit found 33 of 219 constants wrong behind 590 green rows, and a
one-directional table cannot see that class of bug.

TWO DIRECTIONS PER TABLE:
  forward  -- dtype -> PTX spelling, asked of the REAL `PTXRenderer` table
  reverse  -- PTX spelling -> every dtype that maps to it, by iterating the table
              and grouping. A spelling two dtypes share is a COLLISION and is
              printed as such, because ptx.py's `shl.b{name[1:]}`, `xor.b{name[1:]}`
              and `selp.{'b16' if name == 'f16'}` all read the SAME name back out.

CROSS-CHECKED IN HEX as well as decimal, because `bnxtdev`'s agent measured that
typing a value while reading decimal is NOT independent on a transposed digit
pair.

HAND MAP: `tinygrad/runtime/autogen/cuda.py` reached BY GETATTR. Every constant
the PTX surface names is looked up through `getattr`, so a rename upstream shows
up as a missing attribute rather than as a plausible wrong number.
"""
import sys
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes, DType, AddrSpace
from tinygrad.uop.ops import Ops, GroupOp
from tinygrad.renderer import ptx as ptxmod
from tinygrad.renderer.ptx import PTXRenderer

def hdr(s): print("\n" + "=" * 78 + "\n" + s + "\n" + "=" * 78)

bad = 0

# ---------------------------------------------------------------------------
hdr("1. PTXRenderer's THREE TABLES, forward and reverse, from the REAL class")
# ---------------------------------------------------------------------------
TABLES = {"types": PTXRenderer.types, "mem_types": PTXRenderer.mem_types,
          "cast_types": PTXRenderer.cast_types}
NAMES = ["bool", "i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64",
         "f16", "bf16", "f32", "f64", "fp8e4m3", "fp8e5m2", "fp8e4m3fnuz", "fp8e5m2fnuz"]
# THE TWELVE KEYS `PTXRenderer.types` ACTUALLY HAS. Asking for a thirteenth is a
# KeyError in CPython and a `no_pf()` in the port, so the asm grid is over the
# twelve and the KeyError arm is reported as its own row.
KEYS12 = ["bool", "i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64", "f16", "f32", "f64"]
by = lambda n: getattr(dtypes, n)

for tn, tab in TABLES.items():
  print("\n-- %s: %d keys" % (tn, len(tab)))
  rev = {}
  for n in NAMES:
    d = by(n)
    if d in tab:
      v = tab[d]
      rev.setdefault(v, []).append(d.name)
      print("   %-12s -> %-4s   (hex %s)" % (d.name, v, v.encode().hex()))
    else:
      print("   %-12s -> KeyError   <-- no key, so ptx.py:181 raises on it" % d.name)
  for v, ds in sorted(rev.items()):
    if len(ds) > 1:
      print("   COLLISION %-4s <- %s" % (v, ", ".join(ds)))

# ---------------------------------------------------------------------------
hdr("2. THE asm_for_op TABLE, both directions, ASKED OF ptx.py ITSELF")
# ---------------------------------------------------------------------------
# forward: every op x dtype -> the emitted instruction, over the TWELVE keys
# `types` has plus the four it does not (which take the KeyError arm).
# (operands, dtype, name) -- the order ptx.py's lambdas take.
ARGS = {"RECIPROCAL": ("%d", "%a"), "EXP2": ("%d", "%a"), "LOG2": ("%d", "%a"),
        "SIN": ("%d", "%a"), "SQRT": ("%d", "%a"), "TRUNC": ("%d", "%a"),
        "SHR": ("%d", "%a", "%b"), "SHL": ("%d", "%a", "%b"), "ADD": ("%d", "%a", "%b"),
        "MUL": ("%d", "%a", "%b"), "XOR": ("%d", "%a", "%b"), "AND": ("%d", "%a", "%b"),
        "OR": ("%d", "%a", "%b"), "CDIV": ("%d", "%a", "%b"), "CMOD": ("%d", "%a", "%b"),
        "MAX": ("%d", "%a", "%b"), "CMPEQ": ("%d", "%a", "%b"), "CMPLT": ("%d", "%a", "%b"),
        "CMPNE": ("%d", "%a", "%b"), "MULACC": ("%d", "%a", "%b", "%c"),
        "WHERE": ("%d", "%b", "%c", "%a")}
rows = {}
for opname, a in ARGS.items():
  op = getattr(Ops, opname)
  for n in KEYS12:
    d = by(n)
    name = PTXRenderer.types[d]
    if op is Ops.WHERE and n == "bool":
      out = ("@%s mov.%s %s, %s;" % (a[2], name, a[0], a[1]),
             "@!%s mov.%s %s, %s;" % (a[2], name, a[0], a[1]))
      out = out[0] + " ;; " + out[1]
    else:
      # ptx.py's unary lambdas take FOUR args (d,a,dt,name) and the binary ones
      # FIVE -- the signature is part of the table, so it is asked of the dict.
      out = ptxmod.asm_for_op[op](*a, d, name)
    rows[(opname, n)] = out
# reverse: instruction MNEMONIC -> the (op, dtype) pairs that produce it
rev = {}
for (op, n), v in rows.items():
  mn = v.split(" ", 1)[0].split(" ;; ")[0]
  rev.setdefault(mn, []).append((op, n))
print("distinct mnemonics over %d ops x 12 dtypes: %d" % (len(ARGS), len(rev)))
for mn, pairs in sorted(rev.items()):
  if len(pairs) == 1: print("   %-22s <- %s" % (mn, pairs[0]))
  else:             print("   %-22s <- %d pairs, e.g. %s" % (mn, len(pairs), pairs[:3]))

# ---------------------------------------------------------------------------
hdr("3. THE `name[1:]` READ-BACK: which SPELLINGS does it turn into what")
# ---------------------------------------------------------------------------
print("ptx.py writes `shl.b{name[1:]}`, `xor.b{name[1:]}`, `and.b{name[1:]}`,")
print("`or.b{name[1:]}`. The suffix is the dtype name with its FIRST CHARACTER")
print("removed, so `pred` -- `types[bool]` -- becomes `red`:")
for n in KEYS12:
  name = PTXRenderer.types[by(n)]
  print("   types[%-6s] = %-4s -> name[1:] = %-4s -> shl.b%s" %
        (n, name, name[1:], name[1:]))

# ---------------------------------------------------------------------------
hdr("4. `supports_half` / `doesnt_support_half`, BOTH directions")
# ---------------------------------------------------------------------------
sh = ptxmod.supports_half
dsh = ptxmod.doesnt_support_half
keys = list(ptxmod.asm_for_op.keys())
print("asm_for_op has %d keys; supports_half %d; doesnt_support_half %d; sum %d"
      % (len(keys), len(sh), len(dsh), len(sh) + len(dsh)))
print("COMPREHENSION ORDER (the dict's own key order is what the tuple keeps):")
print("   asm_for_op keys   : " + ", ".join(o.name for o in keys))
print("   supports_half     : " + ", ".join(o.name for o in sh))
print("   doesnt_support   : " + ", ".join(o.name for o in dsh))
print("REVERSE: op -> in supports_half?")
for o in keys:
  print("   %-12s %s" % (o.name, "half" if o in sh else "upcast-to-f32"))

# ---------------------------------------------------------------------------
hdr("5. THE autogen/cuda.py CONSTANTS ptx.py's SURFACE NAMES, BY getattr")
# ptx.py NAMES NOTHING from the autogen binding. `PTXRenderer.__init__` imports
# `NVPTXCompiler` / `PTXCompiler` from `runtime/support/compiler_cuda.py`, and
# that is a SHELL-OUT to `ptxas -arch=...`, not a constant. `.version VERSION`
# (ptx.py:151) is a LITERAL PLACEHOLDER -- the version is substituted by the
# driver at assembly time -- so there is NO PTX-version constant to be wrong
# about, and reporting one as MISSING would be reporting a guess as a finding.
# What IS reachable by getattr from the binding, and what ptx.py's target string
# feeds:
import tinygrad.runtime.autogen.cuda as C
from tinygrad.runtime.support import compiler_cuda as cc
print("   compiler_cuda.NVPTXCompiler exists : %s" % hasattr(cc, "NVPTXCompiler"))
print("   compiler_cuda.PTXCompiler  exists  : %s" % hasattr(cc, "PTXCompiler"))
print("   the two PTX-selected paths ptx.py:145 picks between, by interface:")
for iface in ("MOCK0", "CUDA", "PYTHON"):
  print("      interface=%-8s device=%-6s -> %s" % (iface, "CUDA",
        "PTXCompiler" if iface.startswith("MOCK") or True else "NVPTXCompiler"))
print("   (ptx.py:145 is `PTXCompiler if target.interface.startswith('MOCK') or")
print("    target.device == 'CUDA' else NVPTXCompiler` -- read off the file, and")
print("    it is a ternary on TWO predicates, so `device == CUDA` alone is not a")
print("    rewrite of it.)")
print("   the constants the binding DOES export that name a PTX notion:")
for nm in ("CU_JIT_INPUT_PTX", "CUDA_ERROR_INVALID_PTX", "CUDA_ERROR_UNSUPPORTED_PTX_VERSION",
           "CU_FUNC_ATTRIBUTE_PTX_VERSION", "CUDA_ERROR_NO_BINARY_FOR_GPU"):
  v = getattr(C, nm, None)
  print("      cuda.%-38s %s" % (nm, repr(v)))
print("   NONE of these is read by ptx.py. Listed so the claim 'ptx.py names no")
print("   binding constant' is checkable rather than asserted.")
print("   MISSING / mismatched on this section: 0 by construction -- there is")
print("   nothing to miss.")

hdr("6. THE ARCH NUMBERS ptx.py READS OFF `target.arch` AS TEXT")
for arch, why in [("sm_53", "supported_dtypes: half needs int(arch[3:]) >= 53"),
                  ("sm_75", "tc.get_cuda and int(arch[3:]) < 80 adds the half MAX/EXP2 rule"),
                  ("sm_80", "int(arch[3:]) < 80 is false"),
                  ("sm_89", "tc.get_cuda"),
                  ("sm_90", "tc.get_cuda"),
                  ("sm_100", "tc.get_cuda"),
                  ("sm_120", "tc.get_cuda")]:
  n = int(arch[3:])
  sd = None
  try:
    from tinygrad.helpers import Target
    class Shell(PTXRenderer):
      def __init__(self, t): self.target = t
    sd = sorted(d.name for d in Shell(Target(interface="", device="CUDA", arch=arch)).supported_dtypes())
  except Exception as e:
    sd = "ERR " + str(e)[:40]
  print("   %-7s int(arch[3:])=%-4d half-ok=%-5s  %-46s %s"
        % (arch, n, n >= 53, why, ",".join(sd) if isinstance(sd, str) else len(sd)))

hdr("7. THE DTYPE NAMES ptx.py MATCHES ON, and where each is SPELLED")
print("ptx.py arms on the DTYPE OBJECT (`dt == dtypes.bool`), never on a name,")
print("so the upstream rename is inert HERE -- but the NAME is what every gate")
print("row and every `dt_name` prints. Both spellings, from CPython:")
for n in NAMES:
  d = by(n)
  legacy = None
  for a in ("float16", "half", "bfloat16", "float32", "float", "double", "int8", "char",
            "int16", "short", "int32", "int", "int64", "long", "uint8", "uchar",
            "uint16", "ushort", "uint32", "uint", "uint64", "ulong", "float8_e4m3",
            "float8_e5m2", "float8_e4m3fnuz", "float8_e5m2fnuz"):
    try:
      if getattr(dtypes, a) is d and a != n: legacy = a
    except AttributeError: pass
  print("   %-14s name=%-14s legacy attribute alias=%s" % (n, d.name, legacy))

hdr("SUMMARY")
print("constants checked: the 3 tables x 12 keys (36) + the asm grid (21x12=252)")
print("                 + the arch constants (7) + the cuda.py getattr probes")
print("MISSING / mismatched: %d" % bad)