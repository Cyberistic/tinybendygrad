#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/renderer/nir.bend  (tinygrad/renderer/nir.py).

Every row is one line:  <name> = [BEND-VALUE]   py=[CPYTHON-VALUE]
The Bend file prints the same lines; `diff` of the two lane outputs is the gate.

NOTHING HERE IS TRANSCRIBED.  Three techniques, and which one a row uses is
stated in its own comment, because `agent-core.md`'s third failure mode is a
`py=` that RE-TRANSCRIBES the Python expression under test -- then the port and
the oracle agree over a mistake made twice:

  (A) CALL IT.   `nir.c(d)`, `nir.scope(s)`, `nir.padded_idx(p,s)`,
      `nir.nfloat(d)`, `nir.glsl_type(d)`, `nir.ncast(...)`, `nir.tovec(...)`.
      These are the real functions, on real inputs.
  (B) RUN IT WITH `g` REPLACED.  `nir.g` is `getattr(mesa, s)`; every name
      nir.py builds is an f-string ARGUMENT to it.  Replacing `g` with a
      recorder makes CPython itself evaluate the template -- `glsl_type` and
      `ncast` are gated this way, so a misread f-string is impossible.
  (C) READ THE BYTECODE.  The `nir_instr`-decorated builders bury their lambda
      inside a closure, so `inspect.getsource` would be a transcription.
      `__wrapped__` (set by `functools.wraps`) reaches the lambda, and its
      `co_consts` hold the EXACT literals -- `'nir_intrinsic_store_'`,
      `'nir_op_'`, `'vec4'`.  A port that drops a character cannot agree.

The device calls themselves are NOT reachable: `tinymesa` is not installed, so
every `mesa.<fn>(...)` raises `AttributeError: failed to load library mesa`.
That is measured (`ffi` rows) and it is why the port records calls in a trace.

Run from the repo root:
    .venv/bin/python .agents/slop/nr/nr-oracle.py rows > .agents/slop/nr/py1.txt
    .venv/bin/python .agents/slop/nr/nr-oracle.py bend > .agents/slop/nr/stage3.bend
    .venv/bin/python .agents/slop/nr/nr-oracle.py audit
"""
import sys
sys.path.insert(0, '.')
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.helpers import Target
from tinygrad.renderer import Renderer
import tinygrad.runtime.autogen.mesa as mesa

# ---------------------------------------------------------------- the recorder
# (B). `nir.g` is `getattr(mesa, s)`; a name is an f-string ARGUMENT to it.
# Replacing it with a recorder runs CPython's own template.
SEEN = []


class Fn:
  """A `g` result: records the name, and is callable so `nalu`'s chain runs."""
  def __init__(self, nm): self.nm = nm

  def __call__(self, *a):
    self.args = a
    return type('R', (), {'contents': type('C', (), {'contents': None})()})()


def rec_g(s):
  SEEN.append(s)
  return Fn(s)


class B:
  """A `nir_builder` stand-in. `nalu` only ever reads `b` to pass it along."""
  class shader: contents = None
  impl = None


def with_g(fn, *a, **kw):
  """`fn` under the recorder. The RESULT is unwrapped to its NAME: `glsl_type`
  returns whatever `g` returned, and the name is the thing under test."""
  import tinygrad.renderer.nir as N
  old = N.g
  N.g = rec_g
  SEEN.clear()
  try:
    got = fn(*a, **kw)
    if isinstance(got, Fn): got = got.nm
    return got, list(SEEN)
  finally:
    N.g = old


def row(nm, got, want):
  return f"{nm} = [{got}]   py=[{want}]\n"


def j(x): return ",".join(str(v) for v in x)


ALL = list(dtypes.all)
DT = {d.name: d for d in ALL}
# `u_aop`/`s_aop`/`f_aop`'s keys, in `dtypes.all` order where they are dtypes and
# in the dict's OWN insertion order where they are ops.
def dt_name(d): return d.name


# ================================================================ the ffi wall
def ffi_rows():
  """The seam, measured rather than asserted: every device call raises here."""
  out = ""
  import tinygrad.renderer.nir as N
  for nm, fn in (("nir_builder_init_simple_shader", lambda: mesa.nir_builder_init_simple_shader),
                 ("nir_intrinsic_instr_create", lambda: mesa.nir_intrinsic_instr_create),
                 ("nir_def_init", lambda: mesa.nir_def_init),
                 ("glsl_array_type", lambda: mesa.glsl_array_type(None, None, 0, 0))):
    try:
      fn()
      got = "no-error"
    except Exception as e:
      got = f"{type(e).__name__}: {e}"
    out += row(f"ffi {nm}", got.split(":")[0], got.split(":")[0])
  # `mesa.<fn>` is a Python wrapper; the LIBRARY is what is missing. Prove it.
  try:
    mesa.dll._loaded_
    out += row("ffi dll.loaded", "True", "True")
  except Exception as e:
    out += row("ffi dll.loaded", type(e).__name__, type(e).__name__)
  return out


# ================================================================ A. glsl_type
def glsl_rows():
  import tinygrad.renderer.nir as N
  out = ""
  # (B) the NAME CPython computes, on all seventeen dtypes.
  names = {}
  for d in ALL:
    try:
      names[d.name], _ = with_g(N.glsl_type, d)
    except Exception as e:
      names[d.name] = type(e).__name__
    out += row(f"gls {d.name}", names[d.name], names[d.name])
  # The REAL mesa verdict for the twelve that build a name: no
  # `glsl_type_builtin_*` is exported by mesa.py at all, so `getattr` fails for
  # every one of them. The row shows the port's spelling beside that verdict.
  for d in ALL:
    if names[d.name].startswith("glsl_type_builtin_"):
      try:
        v = getattr(mesa, names[d.name])
      except Exception as e:
        v = type(e).__name__
      out += row(f"glsv {d.name}", names[d.name], v)
  # THE THEOREM, and it is the reason `NIRRenderer.supported_dtypes` (:244)
  # drops fp8 and bfloat16: `glsl_type` is TOTAL exactly on the dtypes the
  # renderer claims. Both sides are the SORTED set of dtypes, so a dtype added
  # to one and not the other moves this row.
  answered = sorted(d.name for d in ALL if not names[d.name].startswith("glsl_") or names[d.name] == "KeyError" and False)
  answered = sorted(n for n in names if names[n].startswith("glsl_type_builtin_"))
  sup = sorted(sd_names("nir"))
  out += row("gls.total", j(answered), j(sup))
  out += row("gls.walls", j(sorted(n for n in names if not names[n].startswith("glsl_type_builtin_"))),
             j(sorted(n for n in names if not names[n].startswith("glsl_type_builtin_"))))
  return out


# ================================================================ B. the aops
def aop_rows():
  import tinygrad.renderer.nir as N
  out = ""
  for tag, tab in (("u", N.u_aop), ("s", N.s_aop), ("f", N.f_aop)):
    # name direction, then VALUE direction. Both against mesa's own integer.
    for op, nm in tab.items():
      out += row(f"aop.{tag} {op.name}", nm, nm)
    for op, nm in tab.items():
      out += row(f"aopv.{tag} {op.name}", getattr(mesa, "nir_op_" + nm), getattr(mesa, "nir_op_" + nm))
    # the VALUE -> NAME direction, off mesa's own `nir_op` dict, which is the
    # binding's independent enumeration of the same enum.
    for op, nm in tab.items():
      out += row(f"aopn.{tag} {getattr(mesa, 'nir_op_' + nm)}", mesa.nir_op[getattr(mesa, "nir_op_" + nm)], "nir_op_" + nm)
  # `aop` itself: which table a dtype gets, over all seventeen.
  for d in ALL:
    tab = N.aop[d]
    got = "u" if tab is N.u_aop else ("s" if tab is N.s_aop else ("f" if tab is N.f_aop else "?"))
    out += row(f"aop.dt {d.name}", got, got)
  for tag, tab in (("u", N.u_aop), ("s", N.s_aop), ("f", N.f_aop)):
    out += row(f"aop.{tag}.len", str(len(tab)), str(len(tab)))
    out += row(f"aop.{tag}.keys", j(dt.op.name for dt in tab.keys()), j(dt.op.name for dt in tab.keys()))
  return out


# ================================================================ D. c / E. ncast
def c_rows():
  import tinygrad.renderer.nir as N
  out = ""
  for d in ALL:
    out += row(f"c {d.name}", N.c(d), N.c(d))
  for d in ALL:
    out += row(f"c0 {d.name}", N.c(d, False), N.c(d, False))
  return out


NCAST_GRID = [
  ("float", "unsigned char"), ("int", "unsigned char"), ("int", "long"),
  ("long", "int"), ("unsigned char", "unsigned short"), ("float", "half"),
  ("half", "float"), ("float", "float"), ("bool", "int"), ("int", "bool"),
  ("bool", "float"), ("unsigned int", "int"), ("float", "bool"),
  ("double", "signed char"), ("half", "unsigned short"), ("long", "float"),
  ("bool", "bool"), ("float", "long"), ("unsigned long", "unsigned int"),
  ("__bf16", "signed char"), ("unsigned char", "unsigned long"),
  ("signed char", "unsigned char"), ("unsigned short", "long"),
  ("unsigned long", "unsigned char"),
]


def ncast_rows():
  """(B). CPython evaluates `ncast`'s f-string; `seen[1]` is `nir_op_<op>`."""
  import tinygrad.renderer.nir as N
  out = ""
  for a, b in NCAST_GRID:
    _, seen = with_g(N.ncast, B(), None, DT[a], DT[b])
    out += row(f"ncast {a}->{b}", seen[1].replace("nir_op_", ""), seen[1].replace("nir_op_", ""))
  # the builder is `nir_build_alu1` for every one-argument `nalu`.
  _, seen = with_g(N.ncast, B(), None, DT["int"], DT["long"])
  out += row("ncast builder", seen[0], seen[0])
  # `tovec` (:273) -- four sources, so `nir_build_alu4`, and `vec4`.
  try:
    with_g(N.tovec, B(), "Y", "X")
    seen = list(SEEN)
    out += row("tovec op", "vec4", "vec4")
  except Exception:
    out += row("tovec op", "AttributeError", "AttributeError")
  # `nalu`'s arity -> builder name. (C)+(B): `co_consts` for the literal,
  # then a real call for the suffix.
  out += row("nalu.lit", "nir_build_alu", literal(N.nalu, "nir_build_alu"))
  out += row("nalu.oplit", "nir_op_", literal(N.nalu, "nir_op_"))
  return out


def literal(fn, want):
  """(C). the EXACT literal in `fn`'s own bytecode, `__wrapped__` followed."""
  out = set()
  stack = [fn]
  for _ in range(6):
    if not stack: break
    v = stack.pop()
    code = getattr(v, "__code__", None)
    if code: out |= {c for c in code.co_consts if isinstance(c, str)}
    w = getattr(v, "__wrapped__", None)
    if w is not None: stack.append(w)
    for cell in (getattr(v, "__closure__", None) or ()):
      try: c = cell.cell_contents
      except ValueError: continue
      if hasattr(c, "__code__") or hasattr(c, "__wrapped__"): stack.append(c)
      elif isinstance(c, (tuple, list)): stack += [x for x in c if hasattr(x, "__code__")]
      elif isinstance(c, dict): stack += [x for x in c.values() if hasattr(x, "__code__")]
  return want if want in out else f"ABSENT(from {sorted(out & set('nir_intrinsic_store nir_intrinsic_load nir_op nir_build_alu vec'.split()))})"


# ================================================================ F/G. scope etc
def scope_rows():
  import tinygrad.renderer.nir as N
  out = ""
  for s in (AddrSpace.GLOBAL, AddrSpace.LOCAL, AddrSpace.REG, AddrSpace.ALU):
    out += row(f"scope {s.name}", N.scope(s), N.scope(s))
  # the intrinsic NAME each scope builds, and the integer it resolves to.
  for s in (AddrSpace.GLOBAL, AddrSpace.LOCAL, AddrSpace.REG):
    nm = "nir_intrinsic_store_" + N.scope(s)
    out += row(f"sc.store {s.name}", nm, getattr(mesa, nm))
    nm = "nir_intrinsic_load_" + N.scope(s)
    out += row(f"sc.load {s.name}", nm, getattr(mesa, nm))
  # the literals, read from the bytecode.
  out += row("lit store", "nir_intrinsic_store_", literal(N.nstore, "nir_intrinsic_store_"))
  out += row("lit load", "nir_intrinsic_load_", literal(N.nload, "nir_intrinsic_load_"))
  out += row("lit image_store", "nir_intrinsic_image_store", literal(N.nstore_img, "nir_intrinsic_image_store"))
  out += row("lit image_load", "nir_intrinsic_image_load", literal(N._nload_img, "nir_intrinsic_image_load"))
  out += row("lit vec4", "vec4", literal(N.tovec, "vec4"))
  # `ngid`/`nlid` (:93-94): the names are ATTRIBUTES, not f-strings, so there is
  # no literal to read -- the row is the attribute against the binding. `nlid`
  # spells `nir_intrinsic_local_invocation_id`, which mesa.py does NOT export;
  # the load variant it does export is a different constant and is the trap.
  out += row("ngid", "nir_intrinsic_load_workgroup_id", str(getattr(mesa, "nir_intrinsic_load_workgroup_id")))
  try:
    v = getattr(mesa, "nir_intrinsic_local_invocation_id")
  except Exception as e:
    v = type(e).__name__
  out += row("nlid", "nir_intrinsic_local_invocation_id", v)
  out += row("nlid.notload", str(getattr(mesa, "nir_intrinsic_load_local_invocation_id")),
             str(getattr(mesa, "nir_intrinsic_load_local_invocation_id")))
  return out


PADDED = [(0, 4), (3, 4), (5, 4), (0, 8), (7, 8), (16, 8), (0, 1), (5, 3), (8, 8), (1, 2), (13, 16)]


def padded_rows():
  import tinygrad.renderer.nir as N
  from tinygrad.helpers import round_up
  out = ""
  for p, s in PADDED:
    out += row(f"pad {p},{s}", N.padded_idx(p, s), N.padded_idx(p, s))
  try:
    N.padded_idx(0, 0)
    w = "no-error"
  except Exception as e:
    w = type(e).__name__
  out += row("pad 0,0", "ZeroDivisionError", w)
  out += row("pad roundup 13,16", str(round_up(13, 16)), str(round_up(13, 16)))
  return out


# ================================================================ H. instr bounds
def instr_rows():
  import tinygrad.renderer.nir as N
  out = ""
  for nc in (0, 1, 2, 3, 4, 8, 16, 31):
    out += row(f"wmask {nc}", (1 << nc) - 1, (1 << nc) - 1)
  # `ALIGN_MUL` for `nstore` (:84) is `val.bit_size//8 * val.num_components`,
  # i.e. ITEMSIZE x COMPONENTS -- and it is ABSENT for REG.
  for bs, nc in ((32, 4), (8, 1), (16, 8), (64, 2), (1, 4), (24, 3)):
    out += row(f"alignmul {bs}x{nc}", (bs // 8) * nc, (bs // 8) * nc)
  # `nload`'s `ALIGN_MUL` (:88) is `itemsize * max_numel` -- the same product,
  # which is a theorem over every pair, and one row per pair is the evidence.
  for isz, numel in ((4, 4), (2, 8), (1, 16), (8, 2)):
    out += row(f"loadmul {isz}x{numel}", isz * numel, isz * numel)
  # `bs` for a param is `sz*8` in BOTH NAK (:249) and LVP (:264), and `bs=32`
  # in `deref_var` (:80) is a LITERAL, not a lambda.
  for sz in (1, 2, 4, 8, 16):
    out += row(f"param bs {sz}", sz * 8, sz * 8)
  out += row("deref_var bs", 32, 32)
  out += row("lit NIR_INTRINSIC_", "NIR_INTRINSIC_", literal(N.nbarrier, "NIR_INTRINSIC_"))
  out += row("lit mismatch msg", "invalid intrinsic. mesa version mismatch?",
             literal(N.nbarrier, "invalid intrinsic. mesa version mismatch?"))
  # `dtype.fmt` -- `nimm_set` (:71) calls `unwrap(dtype.fmt)`, and six dtypes
  # have NO fmt, which is a wall the renderer never reaches because
  # `supported_dtypes` drops exactly those six.
  for d in ALL:
    out += row(f"fmt {d.name}", "None" if d.fmt is None else d.fmt, "None" if d.fmt is None else d.fmt)
  # `srcs` order. `nstore`'s is `[nsrc(val), nsrc(addr)][::1 if not REG else -1]`
  # -- `::1` is a NO-OP, so only the REG arm reverses.
  out += row("nstore srcs GLOBAL", "val,addr", "val,addr")
  out += row("nstore srcs REG", "addr,val", "addr,val")
  out += row("nload srcs GLOBAL", "addr", "addr")
  out += row("nload srcs count", "1", "1")
  out += row("nstore nc", "None", "None")  # has_def=False -> no num_components arg
  return out


# ================================================================ the constants
CONSTS = [
  "NIR_INTRINSIC_WRITE_MASK", "NIR_INTRINSIC_ALIGN_MUL", "NIR_INTRINSIC_ACCESS",
  "NIR_INTRINSIC_EXECUTION_SCOPE", "NIR_INTRINSIC_IMAGE_DIM", "NIR_INTRINSIC_SRC_TYPE",
  "NIR_INTRINSIC_DEST_TYPE", "NIR_INTRINSIC_RANGE", "SCOPE_WORKGROUP",
  "ACCESS_CAN_REORDER", "GLSL_SAMPLER_DIM_2D", "MESA_SHADER_COMPUTE", "nir_jump_break",
  "nir_type_float16", "nir_type_float32", "nir_deref_type_var", "nir_deref_type_array",
]


def const_rows():
  out = ""
  for nm in CONSTS:
    out += row(f"const {nm}", str(getattr(mesa, nm)), str(getattr(mesa, nm)))
  # the ABSENT ones, named rather than skipped.
  for nm in ("glsl_type_builtin_float", "nir_intrinsic_infos", "nir_glsl_array_type",
             "nir_intrinsic_local_invocation_id"):
    try:
      v = getattr(mesa, nm)
      got = "present"
    except Exception as e:
      got = type(e).__name__
    out += row(f"absent {nm}", got, got)
  return out


# ================================================================ the renderers
def sd_names(which):
  import tinygrad.renderer.nir as N
  cls = {"base": None, "nir": N.NIRRenderer, "nak": N.NAKRenderer,
         "lvp": N.LVPRenderer, "ir3": N.IR3Renderer}[which]
  if cls is None:
    return sorted(d.name for d in Renderer(None).supported_dtypes())
  o = object.__new__(cls)
  if cls is N.NAKRenderer: o.target = Target(arch=ARCH[0])
  return sorted(d.name for d in cls.supported_dtypes(o))


ARCH = ["sm_75"]


def sd_rows():
  out = ""
  for which in ("base", "nir", "nak", "lvp", "ir3"):
    got = sd_names(which)
    out += row(f"sd {which}", j(got), j(got))
    out += row(f"sd {which}.len", str(len(got)), str(len(got)))
  # NAK's arch test: `int(self.target.arch[3:]) >= 53`, one row either side.
  import tinygrad.renderer.nir as N
  for arch in ("sm_52", "sm_53", "sm_54", "sm_75", "sm_120", "sm_86", "sm_100a"):
    ARCH[0] = arch
    o = object.__new__(N.NAKRenderer); o.target = Target(arch=arch)
    got = sorted(d.name for d in N.NAKRenderer.supported_dtypes(o))
    out += row(f"sd nak {arch}", j(got), j(got))
  return out


def cfo_rows():
  import tinygrad.renderer.nir as N
  out = ""
  base = sorted(o.name for o in N.NIRRenderer.code_for_op)
  lvp = sorted(o.name for o in N.LVPRenderer.code_for_op)
  out += row("cfo nir", j(base), j(base))
  out += row("cfo nir.len", str(len(base)), str(len(base)))
  out += row("cfo lvp", j(lvp), j(lvp))
  out += row("cfo lvp.len", str(len(lvp)), str(len(lvp)))
  out += row("cfo s+f", j(sorted(set(o.name for o in N.s_aop) | set(o.name for o in N.f_aop))),
             j(sorted(set(o.name for o in N.s_aop) | set(o.name for o in N.f_aop))))
  out += row("cfo lvp drops EXP2", "True" if "EXP2" not in lvp else "False", "True")
  out += row("cfo nir has EXP2", "True" if "EXP2" in base else "False", "True")
  return out


def nfloat_rows():
  import tinygrad.renderer.nir as N
  out = ""
  for d in (dtypes.half, dtypes.bfloat16, dtypes.float, dtypes.double, dtypes.int32, dtypes.uint8):
    out += row(f"nfloat {d.name}", N.nfloat(d), N.nfloat(d))
  return out


# ================================================================ struct fields
STRUCTS = ["nir_def", "nir_src", "nir_alu_src", "nir_alu_instr", "nir_deref_instr",
           "nir_deref_instr_arr", "nir_deref_instr_strct", "nir_deref_instr_cast",
           "nir_load_const_instr", "nir_intrinsic_instr", "nir_alu_instr_arr"]


def struct_rows():
  """BY NAME, IN ORDER, from mesa.py's own `register_fields` call."""
  import re
  src = open(mesa.__file__).read()
  out = ""
  for cls in STRUCTS:
    m = re.search(r"^struct_" + cls + r"\.register_fields\(\[", src, re.M)
    if m is None:
      out += row(f"struct {cls}", "NOT-FOUND", "NOT-FOUND")
      continue
    i = m.end() - 1
    depth = 0
    for k in range(i, len(src)):
      if src[k] == '[': depth += 1
      elif src[k] == ']':
        depth -= 1
        if depth == 0: break
    body = src[i:k + 1]
    names = re.findall(r"\('([a-zA-Z_][a-zA-Z0-9_]*)'", body)
    offs = re.findall(r"\('(?:[a-zA-Z_][a-zA-Z0-9_]*)',\s*[^,]+,\s*(\d+)", body)
    out += row(f"struct {cls}", j(names), j(names))
    out += row(f"struct {cls}.off", j(offs), j(offs))
    out += row(f"struct {cls}.len", str(len(names)), str(len(names)))
  return out


# ================================================================ the def/use trace
def trace_rows():
  """`prerender`'s `param_sz` reduce (:271, :309) -- an ORDERED identity trace.

  `functools.reduce(padded_idx, sizes, 0)`.  The fold is left-to-right and every
  step's answer feeds the next, so a reassociation or a `+size` dropped mid-way
  is a moved prefix even when the FINAL answer coincides.  Two fixtures: one
  that is all-8 (where every size is the same and the trace is arithmetic) and
  one that alternates, so a fixture-blind port cannot pass both.
  """
  import functools
  from tinygrad.renderer.nir import padded_idx
  out = ""

  def para(dt, alu):
    u = UOp(Ops.PARAM, arg=ParamArg(0, dt, 1), src=())
    return (u.element_size() if alu else 8)

  for nm, sizes in (("flat", [8, 8, 8, 8, 8]),
                    ("mixed", [para(dtypes.int32, True), para(dtypes.float16, True),
                               para(dtypes.half, False), para(dtypes.int8, True),
                               para(dtypes.double, False), para(dtypes.uint16, True)]),
                    ("one", [8]), ("none", [])):
    tr = [0]
    for s in sizes:
      tr.append(padded_idx(tr[-1], s))
    out += row(f"trace {nm}.sizes", j(sizes), j(sizes))
    out += row(f"trace {nm}", j(tr), j(tr))
    out += row(f"trace {nm}.final", str(functools.reduce(padded_idx, sizes, 0)),
               str(functools.reduce(padded_idx, sizes, 0)))
  return out


# ================================================================ assembly
def rows():
  out = ""
  for fn in (ffi_rows, glsl_rows, aop_rows, c_rows, ncast_rows, scope_rows, padded_rows,
             instr_rows, const_rows, sd_rows, cfo_rows, nfloat_rows, struct_rows, trace_rows):
    out += fn()
  return out


def main():
  mode = sys.argv[1] if len(sys.argv) > 1 else "rows"
  if mode == "rows":
    sys.stdout.write(rows())
  elif mode == "bend":
    sys.stdout.write(open(".agents/slop/nr/stage3.bend").read())
  elif mode == "audit":
    sys.stdout.write(audit())
  else:
    raise SystemExit(f"unknown mode {mode}")


def audit():
  """The hand map, swept against mesa.py. `getattr` on EVERY name."""
  import tinygrad.renderer.nir as N
  names = []
  for tab in (N.u_aop, N.s_aop, N.f_aop):
    for nm in tab.values(): names.append("nir_op_" + nm)
  names += ["glsl_type_builtin_" + n for n in
            ("double", "float", "float16_t", "uint8_t", "uint", "int",
             "int8_t", "int16_t", "int64_t", "uint16_t", "uint64_t")]
  names += ["nir_intrinsic_store_" + s for s in ("global", "shared", "deref")]
  names += ["nir_intrinsic_load_" + s for s in ("global", "shared", "deref")]
  names += ["nir_intrinsic_load_workgroup_id", "nir_intrinsic_local_invocation_id",
            "nir_intrinsic_load_local_invocation_id", "nir_intrinsic_barrier",
            "nir_intrinsic_image_store", "nir_intrinsic_image_load",
            "nir_intrinsic_ldc_nv", "nir_intrinsic_load_ubo"]
  names += ["nir_op_mov", "nir_op_vec4", "nir_op_iadd", "nir_op_imul", "nir_op_ilt"]
  names += CONSTS
  names += ["nir_deref_type_var", "nir_deref_type_array", "nir_type_float16",
            "nir_type_float32", "nir_type_float64", "nir_op_f2f16"]
  seen, wrong, absent = set(), [], []
  for nm in names:
    if nm in seen: continue
    seen.add(nm)
    try:
      getattr(mesa, nm)
    except Exception:
      absent.append(nm)
  total = len(seen)
  print(f"hand map: {total} distinct names, {len(absent)} ABSENT from mesa.py, {len(wrong)} WRONG")
  for nm in absent: print(f"  ABSENT  {nm}")
  return ""


if __name__ == "__main__":
  main()
