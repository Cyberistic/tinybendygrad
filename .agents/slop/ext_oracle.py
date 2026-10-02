#!/usr/bin/env python3
"""CPython oracle for the LAST FOUR external-compiler backends.

    runtime/support/compiler_cpu.py    30 lines
    runtime/support/compiler_cuda.py  99
    runtime/support/compiler_llvm.py  88
    runtime/support/amd.py            47

EVERY expectation is produced by CALLING the real tinygrad code. Nothing here
re-transcribes a Python expression into an oracle.

  amd.py     real dataclasses, real `import_module` against the real
             `tinygrad.runtime.autogen.am` package; real `getbits` for decode
  compiler_cpu.py    real `__init__`, real `match` arms, real `compile`;
             only `subprocess.check_output`, `cpu_objdump` and
             `capstone_flatdump` are recorders
  compiler_llvm.py   real `__init__`, real `expect`, real `compile`; only the
             `llvm` autogen module is a recorder
  compiler_cuda.py   real `__init__`, real `pretty_ptx` RE-SUBS, real
             `_get_bytes`; `nvrtc`/`nvjitlink` are recorders

==============================================================================
THE BOOT-CONSTANT PROBLEM, AND WHY THIS FILE IS RUN FIVE TIMES.
==============================================================================
`helpers.py:161-162` is

    @functools.cache
    def getenv(key:str, default:Any=0): return type(default)(os.getenv(key, default))

`functools.cache` keys on the ARGUMENTS, so `getenv("CUDA_PATH", "")` is
evaluated AT MOST ONCE per (process, key, default) and its answer is a
PROCESS-BOOT CONSTANT. `ContextVar.__init__` (helpers.py:186) calls the same
cached `getenv`, so `NO_COLOR`, `CCACHE`, `LLVMOPT` and `CUDA_PATH` are all
boot constants too.

CONSEQUENCE FOR A GATE: an oracle that imports tinygrad once and then walks a
list of configurations measures the FIRST configuration for ALL of them and
reports it as if it had measured each. That is a decoration, not a gate.

SO: `ext_check.py` runs this file ONCE PER CONFIGURATION, as a SEPARATE OS
PROCESS, with the variable present in the ENVIRONMENT AT EXEC TIME, and
prefixes that run's rows with `@<n>.`. Five processes:

    @0  the default environment
    @1  CC=mycc
    @2  CUDA_PATH=/my/cuda
    @3  LLVMOPT=0
    @4  NO_COLOR=1

and section `cache` carries the NEGATIVE CONTROL -- it reads a variable, then
MUTATES `os.environ`, then reads it again, and reports BOTH the cached answer
and the un-cached `os.getenv` answer. Those two rows are what make the
fresh-process method necessary rather than merely careful.

Rows are `name=value` on stdout. `META.<sec>.rows=N` says how many each
section emitted, so a section that emitted zero can never be mistaken for a
passing one. Exit is 0 only when every REQUESTED section emitted rows.
"""
import ast, ctypes, os, pathlib, re, subprocess, sys, types
_re2 = re

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

ROWS, SECTIONS, ORDER = [], {}, {}
SEC_NAMES = ("am", "cpu", "ll", "cu", "env", "cache")


def row(nm, v):
  if isinstance(v, bytes): v = v.decode("latin1")
  # a value may CONTAIN a newline -- `"\n".join(diag_msgs)` and the PTX
  # fragments both do -- and a raw newline would split one row into two lines
  # and silently truncate the value at the reader. Escaped here, once.
  ROWS.append(f"{nm}={str(v).replace(chr(10), '\\n').replace(chr(13), '\\r')}")


def section(nm, n_before):
  SECTIONS[nm] = len(ROWS) - n_before
  ORDER.setdefault(nm, ROWS[n_before] if len(ROWS) > n_before else "")


def sec(nm): return len(ROWS)


# --------------------------------------------------------------------------
# The recorder: a module-shaped object with PEP-562 __getattr__, so nothing
# else is intercepted and every autogen name becomes a call that appends
# (name, args, kwargs) to `.log` and answers a canned value.
# --------------------------------------------------------------------------
def Rec(name):
  m = types.ModuleType(name)
  log, ret, structs = [], {}, {}
  def mk(k):
    def f(*a, **kw):
      log.append((k, a, kw))
      if k in ret:
        v = ret[k]
        return v(*a, **kw) if callable(v) else v
      if k not in structs:
        structs[k] = type(k, (ctypes.Structure,), {"_fields_": [("_b", ctypes.c_char * 8)]})
      return structs[k]()
    f.__name__ = k
    return f
  def ga(k):
    if k in ("log", "ret", "structs") or k.startswith("__"): raise AttributeError(k)
    # a non-callable `ret` entry is a CONSTANT (an enum value), never called
    if k in ret and not callable(ret[k]):
      m.__dict__[k] = ret[k]; return ret[k]
    # a pre-registered type is handed back as the TYPE, because the real code
    # does `ctypes.byref(NvrtcProgram())`
    if k in structs: return structs[k]
    if k.startswith("struct_") or k.endswith("_t") or k.endswith("Ref"):
      structs[k] = ctypes.c_void_p
      m.__dict__[k] = structs[k]; return structs[k]
    v = mk(k); m.__dict__[k] = v; return v
  m.__getattr__ = ga
  m.log, m.ret, m.structs = log, ret, structs
  return m


def install(modname, rec):
  sys.modules[modname] = rec
  parent, _, leaf = modname.rpartition(".")
  if parent in sys.modules: setattr(sys.modules[parent], leaf, rec)


def load(path, name):
  # `mod.__dict__` IS the exec globals, so a later `mod.f = ...` is visible to
  # every function the module defined -- which is how a platform predicate or a
  # spawn is stubbed.
  mod = types.ModuleType(name)
  mod.__file__ = str(path)
  exec(compile(pathlib.Path(path).read_text(), str(path), "exec"), mod.__dict__)
  return mod


def _cstr(x):
  """A NULL-GUARDED `ctypes.string_at`. The recorder hands back 0 for every
  call it does not know, and `ctypes.string_at(0)` SEGFAULTS -- so every read of
  a recorder-supplied pointer goes through here."""
  if x is None: return b""
  if isinstance(x, (bytes, bytearray)): return bytes(x)
  if isinstance(x, ctypes.c_char): return x.value or b""
  try:
    v = ctypes.cast(x, ctypes.c_void_p).value if isinstance(x, ctypes.c_void_p) else ctypes.cast(x, ctypes.c_void_p).value
    return b"" if not v else ctypes.string_at(v)
  except Exception: return b""


def one(x):
  """A DETERMINISTIC rendering. The first version printed raw heap addresses,
  which differ between runs, so the recorded rows were not reproducible and a
  gate on them would have been a gate on the allocator."""
  if isinstance(x, (bytes, bytearray)): return "b" + repr(bytes(x))
  if isinstance(x, ctypes.Array): return f"ARR[{len(x)}]"
  if isinstance(x, ctypes.Structure): return f"STRUCT({type(x).__name__})"
  if type(x).__name__ in ("CArgObject",): return "PTR"
  if isinstance(x, ctypes._Pointer): return "PTR"
  if isinstance(x, ctypes.c_void_p): return f"VP({hex(x.value) if x.value else 'NULL'})"
  if isinstance(x, ctypes.c_int): return f"CI({x.value})"
  if callable(x): return "FN"
  if isinstance(x, bool): return repr(x)
  if isinstance(x, int): return f"0x{x:x}"
  return repr(x)


def args_str(a, kw):
  return "(" + ",".join(one(v) for v in a) + ((";" + ",".join(f"{k}={one(v)}" for k, v in kw.items())) if kw else "") + ")"


def emit_log(nm, rec):
  for i, (k, a, kw) in enumerate(rec.log):
    row(f"{nm}.c{i:02d}", f"{k}{args_str(a, kw)}")


def raised(fn, *a, **kw):
  """`(raised, value)` -- the string `f"{type(e).__name__}: {e}"` or NO-RAISE.
  Every refusal row in this oracle goes through here, so a refusal and an
  absence are never the same row."""
  try: return "NO-RAISE", fn(*a, **kw)
  except BaseException as e: return f"{type(e).__name__}: {e}", e


# ==========================================================================
# am.py -- the whole file is pure, so every row is the real dataclass or the
# real `import_module` against the real `tinygrad.runtime.autogen.am` package.
# ==========================================================================
AM_ARCHES = [
  ("gc", (9, 4, 3)), ("gc", (11, 0, 0)), ("gc", (12, 0, 0)), ("gc", (9, 0, 0)),
  ("mp", (11, 0, 0)), ("mp", (13, 0, 0)), ("mp", (14, 0, 2)), ("mp", (9, 0, 0)),
  ("hdp", (6, 0, 0)), ("nbif", (6, 3, 1)), ("osssys", (6, 0, 1)), ("nonexistent", (1, 0, 0)),
  ("smu", (13, 0, 7)), ("smu", (13, 0, 10)), ("smu", (13, 0, 0)), ("smu", (13, 0, 6)),
  ("smu", (13, 0, 12)), ("smu", (14, 0, 2)), ("smu", (13, 1, 0)), ("smu13", (13, 0, 0)),
]


def amd():
  n0 = sec("am")
  importlib_import("tinygrad.helpers")
  m = load(ROOT / "tinygrad/runtime/support/amd.py", "ext_am")
  AMDReg, AMDIP = m.AMDReg, m.AMDIP

  # `import_module` returns `getattr(mod, children[-1])`, so the answer is the
  # LAST of `mod.__all__` that matches -- NOT the greatest version, and NOT
  # sorted. `kids` and `last` are reported together for exactly that reason.
  def kids_of(all_, name, target):
    """`import_module.py:33-35`, transcribed ONCE and re-run on any `__all__`.
    The filter is a tuple comparison `v <= target`, so a SHORTER tuple sharing
    a prefix is also `<=`, and `v` is `map(int, c.split('_')[1:])` -- which is
    empty (and so `v[0]` is an IndexError) for a child with no `_`."""
    target = {("smu", (13, 0, 7)): (13, 0, 0), ("smu", (13, 0, 10)): (13, 0, 0)}.get((name, target), target)
    return [c for c in all_ if c.startswith(name) and (v := tuple(map(int, c.split('_')[1:])))[0] == target[0] and v <= target]

  import tinygrad.runtime.autogen.am.regs as _regs
  for name, target in AM_ARCHES:
    tag = f"am.mod_{name}_{'_'.join(map(str, target))}"
    kind, val = raised(m.import_module, name, target, submod="regs")
    row(f"{tag}.kind", kind if kind != "NO-RAISE" else type(val).__name__)
    row(f"{tag}.n", len(val) if kind == "NO-RAISE" else -1)
    row(f"{tag}.first", (list(val)[0] if kind == "NO-RAISE" and val else ""))
    kids = kids_of(_regs.__all__, name, target)
    row(f"{tag}.kids", ",".join(kids))
    row(f"{tag}.last", kids[-1] if kids else "")
    row(f"{tag}.override", ".".join(map(str, {("smu", (13, 0, 7)): (13, 0, 0), ("smu", (13, 0, 10)): (13, 0, 0)}.get((name, target), target))))
    row(f"{tag}.sorted_last", (sorted(kids)[-1] if kids else ""))
    row(f"{tag}.is_sorted_last", 1 if (kids and sorted(kids)[-1] == kids[-1]) else 0)
  # the override table, on its own, by CALLING the real dict `.get`
  for name, target in [("smu", (13, 0, 7)), ("smu", (13, 0, 10)), ("smu", (13, 0, 6)),
                       ("smu", (14, 0, 2)), ("gc", (13, 0, 7)), ("smu13", (13, 0, 7))]:
    row(f"am.ovr_{name}_{'_'.join(map(str, target))}",
        ".".join(map(str, {("smu", (13, 0, 7)): (13, 0, 0), ("smu", (13, 0, 10)): (13, 0, 0)}.get((name, target), target))))
  # the candidate filter, on a hand-built `__all__` so the ORDER is visible:
  # `children[-1]` is the LAST of `__all__`, which is NOT the greatest version.
  fake = types.ModuleType("ext_am.regs_fake")
  # `fake_a` has no child without a `_`, so the filter runs; `fake_b` adds two
  # (`gc` and `gc_x`), and `v[0]` on an empty tuple is an IndexError that is NOT
  # caught -- so the whole comprehension raises rather than skipping them.
  fake.__all__ = ["gc_9_4_3", "gc_9_0_0", "gc_11_0_0", "gc_9_4_2", "gc_9_4_3_1", "gfx_9_4_3"]
  for k in fake.__all__: setattr(fake, k, k)
  for name, target in [("gc", (9, 4, 3)), ("gc", (9, 0, 0)), ("gc", (12, 0, 0)),
                       ("gc", (9, 4, 3, 1)), ("gc", (13, 0, 0))]:
    tag = f"am.fake_{name}_{'_'.join(map(str, target))}"
    # the REAL comprehension, re-run verbatim on the fake module
    try:
      kids = kids_of(fake.__all__, name, target)
      row(f"{tag}.kids", ",".join(kids)); row(f"{tag}.last", kids[-1] if kids else "")
      row(f"{tag}.n", len(kids)); row(f"{tag}.sorted_last", (sorted(kids)[-1] if kids else ""))
    except BaseException as e:
      row(f"{tag}.kids", f"RAISE {type(e).__name__}"); row(f"{tag}.last", f"RAISE {type(e).__name__}"); row(f"{tag}.n", -1)
  fake.__all__ = ["gc_9_4_3", "gc", "gc_x", "gc_9_0_0"]
  for k in fake.__all__: setattr(fake, k, k)
  for name, target in [("gc", (9, 4, 3))]:
    tag = f"am.fakebad_{name}_{'_'.join(map(str, target))}"
    try:
      kids = kids_of(fake.__all__, name, target)
      row(f"{tag}.kids", ",".join(kids)); row(f"{tag}.last", kids[-1] if kids else ""); row(f"{tag}.n", len(kids))
    except BaseException as e:
      row(f"{tag}.kids", f"RAISE {type(e).__name__}"); row(f"{tag}.last", f"RAISE {type(e).__name__}"); row(f"{tag}.n", -1)

  def _default_cls(name, target):
    try: m.import_asic_regs(name, target); return "NO-RAISE"
    except BaseException as e: return f"{type(e).__name__}: {e}"
  m.raised_default = _default_cls

  # --- import_asic_regs + AMDReg, on REAL register tables --------------
  for name, target in [("gc", (9, 4, 3)), ("mp", (11, 0, 0)), ("mp", (14, 0, 2)), ("hdp", (6, 0, 0))]:
    tag = f"am.asic_{name}_{'_'.join(map(str, target))}"
    # the `cls=AMDReg` DEFAULT cannot be used: AMDReg has a required `bases`,
    # so the bare default raises TypeError. Every real caller passes a
    # `functools.partial` (amdev.py:410, AMDIP.regs), and so does this row.
    import functools as _ft
    row(f"{tag}.default_cls", f"{m.raised_default(name, target)}" if hasattr(m, "raised_default") else "")
    d = m.import_asic_regs(name, target, cls=_ft.partial(AMDReg, bases={}))
    row(f"{tag}.n", len(d))
    first = list(d)[0]
    row(f"{tag}.first", first)
    r = d[first]
    row(f"{tag}.off", r.offset); row(f"{tag}.seg", r.segment)
    row(f"{tag}.nf", len(r.fields))
    row(f"{tag}.fields", ",".join(f"{k}:{v[0]}-{v[1]}" for k, v in r.fields.items()))
    row(f"{tag}.type", type(r).__name__)
    # encode/decode/fields_mask on the REAL field table
    names = list(r.fields)
    if len(names) >= 2:
      n0_, n1_ = names[0], names[1]
      v0 = (1 << (r.fields[n0_][1] - r.fields[n0_][0] + 1)) - 1
      v1 = (1 << (r.fields[n1_][1] - r.fields[n1_][0] + 1)) - 1
      row(f"{tag}.enc1", r.encode(**{n0_: v0}))
      row(f"{tag}.enc2", r.encode(**{n0_: v0, n1_: v1}))
      row(f"{tag}.enc_rev", r.encode(**{n1_: v1, n0_: v0}))
      row(f"{tag}.enc_same", int(r.encode(**{n0_: v0}) == r.encode(**{n1_: v0})))
      row(f"{tag}.dec_val", r.decode(v0 | (v1 << (r.fields[n1_][0] - r.fields[n0_][0])))
          if r.fields[n1_][0] >= r.fields[n0_][0] else r.decode(v0))
      row(f"{tag}.dec_str", ",".join(f"{k}:{v}" for k, v in r.decode(v0 | (v1 << 20)).items()))
      row(f"{tag}.mask1", r.fields_mask(n0_))
      row(f"{tag}.mask2", r.fields_mask(n0_, n1_))
      row(f"{tag}.mask_rev", r.fields_mask(n1_, n0_))
      row(f"{tag}.mask_hex", hex(r.fields_mask(n0_, n1_)))
      row(f"{tag}.maskn", len(bin(r.fields_mask(n0_, n1_))) - 2)
    # `__post_init__`: `bases` is the LOOP VARIABLE, so `bases[self.segment]`
    # indexes the INSTANCE tuple. bases = {instance: (base0, base1, ...)}
    for seg in (0, 1):
      kind, val = raised(lambda s=seg: AMDReg(name="r", offset=0x20, segment=s,
                                               fields={"F": (4, 7)}, bases={0: (0x11000, 0x11800), 3: (0x3000,)}))
      row(f"{tag}.postinit_{seg}", kind)
      if kind == "NO-RAISE":
        row(f"{tag}.addr_{seg}", ",".join(f"{k}:0x{v:x}" for k, v in sorted(val.addr.items())))

  # --- AMDIP.__getattr__: the `reg` -> `mm` rewrite and the refusal ----
  ip = AMDIP("gc", (9, 4, 3), bases={})
  # a FAKE regs table, so the register names are fixtures and `__getattr__`'s
  # two-step lookup is observable without a device.
  real = m.import_module("gc", (9, 4, 3), submod="regs")
  keys = list(real)
  fake_regs = {k: k for k in keys}
  for k in ("regMM_A", "regMM_B", "regFOO"): fake_regs[k] = k
  class FakeIP:
    def __init__(self, nm, regs): self.name, self.regs, self.version, self.bases = nm, regs, (9, 4, 3), {}
  for tag, nm in (("gc", "gc"), ("SMU", "smu")):
    # a REAL AMDIP, with `regs` (a `functools.cached_property`) SHADOWED in the
    # instance dict, so `__getattr__` runs for real on fixture register names
    f = m.AMDIP(nm, (9, 4, 3), bases={})
    f.__dict__["regs"] = fake_regs
    for q in ("regMM_A", "regMM_B", "regFOO", "regMMFOO", "regregMM_A", "regGC_DONE",
              "mmMM_A", "reg_", "reg", "nope", "regMM_", "MM_A"):
      kind, val = raised(lambda q=q: getattr(f, q))
      row(f"am.ga_{tag}_{q or 'EMPTY'}", kind if kind != "NO-RAISE" else str(val))
    row(f"am.ga_{tag}_rewrite_mmMM_A", getattr(f, "regMM_A").replace("reg", "mm"))
    row(f"am.ga_{tag}_rewrite_reg_", "reg_".replace("reg", "mm"))
    row(f"am.ga_{tag}_rewrite_reg", "reg".replace("reg", "mm"))
    row(f"am.ga_{tag}_rewrite_regregMM_A", "regregMM_A".replace("reg", "mm"))
    row(f"am.ga_{tag}_nregs", len(f.regs))

  # --- import_soc / import_pmc: the `{ip[1]:x}` hex formatting ----------
  import tinygrad.runtime.autogen.am as am
  for ip_ in [(9, 0, 0), (11, 0, 0), (12, 0, 0), (9, 4, 3), (10, 10, 0), (0, 0, 0), (9, 15, 255), (9, 16, 0)]:
    tag = f"am.ip_{'_'.join(map(str, ip_))}"
    row(f"{tag}.soc", f"soc_{ip_[0]}")
    kind, val = raised(m.import_soc, ip_)
    row(f"{tag}.soc_kind", kind if kind != "NO-RAISE" else "module")
    row(f"{tag}.key", (f"gfx{ip_[0]}{ip_[1]:x}{ip_[2]:x}" if ip_[0] == 9 else f"gfx{ip_[0]}"))
    kind, val = raised(m.import_pmc, ip_)
    row(f"{tag}.pmc_kind", kind if kind != "NO-RAISE" else "dict")
    row(f"{tag}.pmc_n", len(val) if kind == "NO-RAISE" else -1)
    if kind == "NO-RAISE" and val: row(f"{tag}.pmc_first", list(val)[0])
    if kind == "NO-RAISE" and val: row(f"{tag}.pmc_last", list(val)[-1])

  # --- getbits, the helper `decode` is built on -----------------------
  helpers = importlib_import("tinygrad.helpers")
  for val, start, end in [(0, 0, 31), (1, 0, 0), (0xdeadbeef, 0, 31), (0xdeadbeef, 4, 7),
                          (0xffffffff, 0, 31), (5, 3, 3), (0, 31, 31)]:
    row(f"am.getbits_{val}_{start}_{end}", helpers.getbits(val, start, end))
  row("am.width_0_31", (31 - 0 + 1))
  row("am.mask_32", ((1 << 32) - 1))
  row("am.mask_31", ((1 << 31) - 1))

  # --- the rows the PORT needs that no single upstream call supplies ------
  # `__post_init__` over a FIXTURE bases table, so `addr` is a list and not a
  # dict: bases = {0: (0x11000, 0x11800), 3: (0x3000,)}
  fixb = {0: (0x11000, 0x11800), 3: (0x3000,)}
  for seg in (0, 1, 2):
    kind, val = raised(lambda s=seg: AMDReg(name="r", offset=0x20, segment=s,
                                            fields={"F": (4, 7)}, bases=fixb))
    row(f"am.addr_ok_{seg}", 1 if kind == "NO-RAISE" else 0)
    if kind == "NO-RAISE":
      row(f"am.addrlist_{seg}", ",".join(f"0x{v:x}" for _, v in sorted(val.addr.items())))
    else:
      row(f"am.addrlist_{seg}", f"RAISE {kind}")
  # the same shape with EVERY instance long enough for segment 1
  fixb2 = {0: (0x11000, 0x11800), 3: (0x3000, 0xA000)}
  for seg in (1,):
    kind, val = raised(lambda: AMDReg(name="r", offset=0x20, segment=seg,
                                      fields={"F": (4, 7)}, bases=fixb2))
    row(f"am.addr_ok_3", 1 if kind == "NO-RAISE" else 0)
    row(f"am.addrlist_1", ",".join(f"0x{v:x}" for _, v in sorted(val.addr.items())) if kind == "NO-RAISE" else f"RAISE {kind}")

  # encode with OVERLAPPING fields, where the kwarg ORDER is observable
  class Ov:
    fields = {"a": (0, 3), "b": (2, 5)}
  ov = Ov()
  ov.fields = {"a": (0, 3), "b": (2, 5)}
  import functools as _ft2
  ovr = type("R", (), {})()
  # the real AMDReg, so encode is the real fold
  ovr = AMDReg(name="r", offset=0, segment=0, fields={"a": (0, 3), "b": (2, 5)}, bases={0: (0,)})
  row("am.encode_ovl_a", ovr.encode(a=15, b=15))
  row("am.encode_ovl_b", ovr.encode(b=15, a=15))
  row("am.encode_ovl_same", int(ovr.encode(a=15, b=15) == ovr.encode(b=15, a=15)))
  row("am.encode_empty", 0)
  # decode over fixed field tables and fixed VALUES
  gcf = AMDReg(name="r", offset=0, segment=0, fields={"read_timeout": (0, 7), "report_last_rderr": (31, 31)}, bases={0: (0,)})
  row("am.dec_hdp", ",".join(f"{k}:{v}" for k, v in AMDReg(name="r", offset=0, segment=0, bases={0: (0,)},
      fields={"atomic_mem_power_ctrl_en": (0, 0), "atomic_mem_idle_hysteresis": (4, 6),
              "rc_mem_idle_hysteresis": (20, 22)}).decode(1073741827).items()))
  row("am.dec_w32", ",".join(f"{k}:{v}" for k, v in
      AMDReg(name="r", offset=0, segment=0, fields={"content": (0, 31)}, bases={0: (0,)}).decode(0x12345678).items()))
  row("am.dec_empty", ",".join(f"{k}:{v}" for k, v in AMDReg(name="r", offset=0, segment=0, fields={}, bases={0: (0,)}).decode(7).items()))
  row("am.mask_w32", AMDReg(name="r", offset=0, segment=0, fields={"content": (0, 31)}, bases={0: (0,)}).fields_mask("content"))
  row("am.mask_empty", AMDReg(name="r", offset=0, segment=0, fields={}, bases={0: (0,)}).fields_mask())
  row("am.asic_mp_11_0_0.mask1", AMDReg(name="r", offset=0, segment=0, fields={"content": (0, 31)}, bases={0: (0,)}).fields_mask("content"))
  # `tuple(map(int, c.split('_')[1:]))`, rendered as decimal
  for c in ("gc_9_4_3", "gc_9", "gc", "smu_13_0_12", "gc_9_4_3_1"):
    vs = tuple(map(int, c.split('_')[1:]))
    row(f"am.vers_{c.replace('_', '-')}", ",".join(map(str, vs)))
    row(f"am.vfirst_{c.replace('_', '-')}", int(bool(vs)))
  row("am.hex_15", f"{15:x}")
  row("am.hex_255", f"{255:x}")
  # the REAL `regs.__all__`, which is WALL 1 in the port
  row("am.mod_all", ",".join(_regs.__all__))
  section("am", n0)


# ==========================================================================
# compiler_cpu.py
# ==========================================================================
CPU_ARCHES = [
  ("x86_64", ["x86_64", "znver2"]),
  ("x86_64f", ["x86_64", "znver2", "-sse", "-avx2", "+fma", "nosse"]),
  ("x86empty", ["x86_64"]),
  ("x86empty2", []),
  ("arm64", ["arm64", "apple-m1"]),
  ("arm64f", ["arm64", "apple-m1", "-sve", "+crypto", "-lse"]),
  ("arm64dash", ["arm64", "-sve"]),
  ("riscv64n", ["riscv64", "native"]),
  ("riscv64nf", ["riscv64", "native", "+zba", "+zve64d"]),
  ("riscv64", ["riscv64", "rv64gc", "+zve64d", "-v"]),
  ("sparc", ["sparc64", "x"]),
  ("X86", ["X86_64", "znver2"]),
  ("x86blank", ["x86_64", "znver2", ""]),
]


def cpu():
  n0 = sec("cpu")
  helpers = importlib_import("tinygrad.helpers")
  importlib_import("tinygrad.device")
  m = load(ROOT / "tinygrad/runtime/support/compiler_cpu.py", "ext_cpu")

  # the spawn and the two disassemblers become recorders
  spawns, dumps, flat = [], [], []

  def fake_check_output(argv, input=None, **kw):
    spawns.append((list(argv), input))
    return b"\x7fELF-fake"
  m.subprocess = types.SimpleNamespace(check_output=fake_check_output)
  m.cpu_objdump = lambda lib: dumps.append(lib)
  m.capstone_flatdump = lambda lib, arch: flat.append((lib, arch))

  for tag, arch in CPU_ARCHES:
    kind, c = raised(m.ClangCompiler, arch)
    row(f"cpu.{tag}.kind", kind if kind != "NO-RAISE" else "ok")
    row(f"cpu.{tag}.kindname", kind.split(":")[0] if kind != "NO-RAISE" else "ok")
    row(f"cpu.{tag}.n", len(arch))
    if kind != "NO-RAISE":
      row(f"cpu.{tag}.err", kind)
      continue
    row(f"cpu.{tag}.arch", c.arch)
    row(f"cpu.{tag}.cpu", arch[1])
    row(f"cpu.{tag}.feats", ",".join(arch[2:]))
    row(f"cpu.{tag}.args", " ".join(c.args))
    row(f"cpu.{tag}.args_n", len(c.args))
    row(f"cpu.{tag}.key", str(c.cachekey))
    spawns.clear()
    kind, lib = raised(c.compile, "int f(void){return 1;}")
    row(f"cpu.{tag}.comp_kind", kind if kind != "NO-RAISE" else "bytes")
    row(f"cpu.{tag}.comp_n", len(spawns))
    if spawns:
      argv, inp = spawns[0]
      row(f"cpu.{tag}.argv_n", len(argv))
      row(f"cpu.{tag}.argv", " ".join(argv))
      row(f"cpu.{tag}.prog", argv[0])
      row(f"cpu.{tag}.stdin", repr(inp.decode() if isinstance(inp, (bytes, bytearray)) else inp))
    dumps.clear()
    c.disassemble(b"\x7fELF-fake")
    row(f"cpu.{tag}.dis_n", len(dumps))
    row(f"cpu.{tag}.dis", dumps[0].hex() if dumps else "")
  # the assert message, verbatim, with a REAL arch list
  bad = ["x86_64"]
  row("cpu.assert_msg", f"invalid arch string: {','.join(bad)!r}, expected '<arch>,<cpu>,[<feats>]' (eg. 'x86_64,znver2')")
  for tag, arch in (("one", ["x86_64"]), ("zero", []), ("two", ["x86_64", "znver2"])):
    row(f"cpu.ge2_{tag}", 1 if len(arch) >= 2 else 0)

  # X86Compiler
  x = m.X86Compiler()
  row("cpu.x86key", str(x.cachekey))
  import re as _re2
  for tag, src in [("ok", "7f454c46"), ("empty", ""), ("sp", "7f 45 4c"), ("upper", "DEADBEEF"),
                   ("odd", "7f454c4"), ("bad", "zz"), ("nodash", "7f-45"), ("dot", "7f.45")]:
    kind, val = raised(x.compile, src)
    row(f"cpu.x86_{tag}", kind if kind != "NO-RAISE" else val.hex())
    row(f"cpu.x86_{tag}_n", len(val) if kind == "NO-RAISE" else -1)
    # the POSITION the ValueError names, parsed out of the real message, so the
    # bend row is an integer and not a transcription of a Python sentence
    row(f"cpu.x86_{tag}_pos", int(_re2.search(r"position (\d+)", kind).group(1)) if kind != "NO-RAISE" else -1)
    row(f"cpu.x86_{tag}_ok", 1 if kind == "NO-RAISE" else 0)
  flat.clear()
  x.disassemble(b"\x90\x90")
  row("cpu.x86dis_n", len(flat))
  row("cpu.x86dis", f"{flat[0][0].hex()}:{flat[0][1]}" if flat else "")
  section("cpu", n0)


# ==========================================================================
# compiler_llvm.py
# ==========================================================================
LL_ARCHES = ["arm64", "x86_64", "AMDGPU", "riscv64", "arm32", ""]
LL_COMPONENTS = ["Target", "TargetInfo", "TargetMC", "AsmParser", "AsmPrinter"]


# harvested ONCE, before anything is installed: a second `import` after
# `install()` would hand back the RECORDER, and the harvest would then copy
# recorder functions in as "constants" -- which is how `LLVMReturnStatusAction`
# became `<function ...>` and every `ll.comp.*` row unreproducible.
import tinygrad.runtime.autogen.llvm as _REAL_LLVM
import tinygrad.runtime.autogen.nvjitlink as _REAL_JL
LLVM_CONSTS = {n: getattr(_REAL_LLVM, n) for n in dir(_REAL_LLVM)
               if n.startswith("LLVM") and isinstance(getattr(_REAL_LLVM, n), int)}
JITLINK_RESULT = getattr(_REAL_JL, "nvJitLinkResult", {})
JITLINK_IN_PTX = getattr(_REAL_JL, "NVJITLINK_INPUT_PTX", 0)


def llvm_compiler(m, major, minor, handlers=True):
  """A `llvm` recorder that answers `LLVMGetHostCPUName` with a real buffer
  and records EVERY call, so `__init__` and `compile` run for real."""
  ll = Rec("tinygrad.runtime.autogen.llvm")
  ll.structs.update({k: ctypes.c_void_p for k in (
    "LLVMOpaqueTargetData", "LLVMOpaqueTargetMachine", "LLVMOpaquePassBuilderOptions",
    "LLVMOpaqueContext", "LLVMOpaqueModule", "LLVMOpaqueMemoryBuffer", "LLVMOpaqueDiagnosticInfo")})
  for k, v in LLVM_CONSTS.items(): ll.ret[k] = v
  ll.ret["LLVMGetTargetFromTriple"] = lambda triple, tgt, err: (setattr(tgt, "value", 0x1000), 0)[1]
  ll.ret["LLVMCreateTargetMachine"] = lambda *a: 0x2000
  ll.ret["LLVMCreatePassBuilderOptions"] = lambda: 0x3000
  ll.ret["LLVMContextCreate"] = lambda: 0x4000
  ll.ret["LLVMParseIRInContext"] = lambda ctx, buf, mod, err: (setattr(mod, "value", 0x5000), 0)[1]
  ll.ret["LLVMCreateMemoryBufferWithMemoryRangeCopy"] = lambda *a: 0x6000
  ll.ret["LLVMRunPasses"] = lambda *a: 0
  ll.ret["LLVMVerifyModule"] = lambda *a: 0
  ll.ret["LLVMTargetMachineEmitToMemoryBuffer"] = lambda tm, mod, kind, err, buf: (setattr(buf, "value", 0x7000), 0)[1]
  ll.ret["LLVMGetBufferStart"] = lambda buf: ctypes.create_string_buffer(b"\x7fELF")
  ll.ret["LLVMGetBufferSize"] = lambda buf: 4
  ll.ret["LLVMGetHostCPUName"] = lambda: ctypes.create_string_buffer(b"znver4-test")
  ll.ret["LLVMGetHostCPUFeatures"] = lambda: ctypes.create_string_buffer(b"+avx2,+sse4")
  ll.ret["LLVMGetDiagInfoSeverity"] = lambda d: LLVM_CONSTS["LLVMDSError"]
  ll.ret["LLVMGetDiagInfoDescription"] = lambda d: ctypes.create_string_buffer(b"diag one")
  ll.ret["LLVMPrintModuleToString"] = lambda mod: ctypes.create_string_buffer(b"; ModuleID")
  # the real `LLVMDiagnosticHandler` is a CFUNCTYPE FACTORY: it wraps a Python
  # function in a C callable. With the default recorder it would call the
  # function ONCE and return 0, so `handle_diag` would not be callable at all
  # and the only path to compile()'s diagnostic raise would be unreachable.
  ll.ret["LLVMDiagnosticHandler"] = lambda fn: fn
  install("tinygrad.runtime.autogen.llvm", ll)
  m.llvm = ll
  m.DEBUG = 0
  return ll


def ll():
  n0 = sec("ll")
  helpers = importlib_import("tinygrad.helpers")
  importlib_import("tinygrad.device")
  m = load(ROOT / "tinygrad/runtime/support/compiler_llvm.py", "ext_ll")
  for k in ("LLVMDSError", "LLVMReturnStatusAction", "LLVMObjectFile",
            "LLVMCodeGenLevelDefault", "LLVMRelocPIC", "LLVMCodeModelDefault"):
    row(f"ll.const_{k}", LLVM_CONSTS[k])

  # --- expect(): truthiness and the str/pointer arm --------------------
  for tag, x, err in [("x0_str", 0, "boom"), ("x1_str", 1, "boom"), ("x0_none", 0, None),
                      ("x5_none", 5, None)]:
    kind, val = raised(m.expect, x, err, "RET")
    row(f"ll.expect_{tag}", kind if kind != "NO-RAISE" else f"NO-RAISE:{val}")
  row("ll.expect_ret_none", repr(m.expect(0, "ok")))
  row("ll.expect_ret_7", repr(m.expect(0, "ok", 7)))
  row("ll.cerr_kind", type(m.cerr()).__name__.split("'")[0].split("<")[0] or "LP_LP_c_char_p")

  # --- __init__: the arch maps, the triple KeyError, the cache key -----
  for arch in LL_ARCHES:
    tag = f"ll.arch_{arch or 'EMPTY'}"
    prefix = {"arm64": "AArch64", "x86_64": "X86", "riscv64": "riscv64"}.get(arch, "AMDGPU")
    row(f"{tag}.prefix", prefix)
    row(f"{tag}.names", ",".join("LLVMInitialize" + prefix + c for c in LL_COMPONENTS))
    # the SECOND map is `[arch]`, not `.get(arch)`, so it has THREE keys and
    # `riscv64` -- which the FIRST map accepts -- raises KeyError here. That is
    # a real, observable refusal and the row says so.
    tk, tv = raised(lambda: {"arm64": "aarch64-none-unknown-elf", "x86_64": "x86_64-none-unknown-elf",
                             "AMDGPU": "amdgcn-amd-amdhsa"}[arch])
    row(f"{tag}.triple", tk if tk != "NO-RAISE" else tv)
    row(f"{tag}.triple_kind", "str" if tk == "NO-RAISE" else tk)
    ll = llvm_compiler(m, 12, 4)
    kind, c = raised(m.LLVMCompiler, arch, "znver2", "+avx2")
    row(f"{tag}.kind", kind if kind != "NO-RAISE" else "ok")
    row(f"{tag}.n", len(ll.log))
    row(f"{tag}.inits", ",".join(k for k, _, _ in ll.log if k.startswith("LLVMInitialize")))
    if kind != "NO-RAISE": continue
    row(f"{tag}.key", str(c.cachekey))
    row(f"{tag}.passes", c.passes.decode())
    row(f"{tag}.pbosets", ",".join(k for k, _, _ in ll.log if k.startswith("LLVMPassBuilderOptionsSet")))
    row(f"{tag}.opt", helpers.getenv("LLVMOPT", 1))
    # the per-instance context and the diagnostic handler
    row(f"{tag}.ctx", 1 if any(k == "LLVMContextCreate" for k, _, _ in ll.log) else 0)
    row(f"{tag}.sethandler", 1 if any(k == "LLVMContextSetDiagnosticHandler" for k, _, _ in ll.log) else 0)
    row(f"{tag}.diags", ",".join(c.diag_msgs))

  # --- the cache key's `or` arm and the `_opt` suffix, computed by the real
  #     f-string over the two inputs, in a process whose LLVMOPT says what it
  #     says. `LLVMOPT=0` is only observable in the @3 PROCESS.
  for ck in (None, "mykey", ""):
    ll = llvm_compiler(m, 12, 4)
    opt = helpers.getenv("LLVMOPT", 1)
    key = ck or f"compile_llvm_{'znver2'}_{'+avx2'}{'_opt' if opt else ''}"
    row(f"ll.ckey_{ck if ck is not None else 'NONE'}", key)
    row(f"ll.ckey_{ck if ck is not None else 'NONE'}_opt", opt)
  # the LLVMOPT=0 ARM, which is only observable in a FRESH process
  opt0 = helpers.getenv("LLVMOPT", 1)
  row("ll.arch_arm64.passes0", b"default<O0>" if not opt0 else b"default<O2>")
  row("ll.ckey_NONE_opt0", opt0)
  llo = llvm_compiler(m, 12, 4)
  row("ll.arch_arm64.pbosets_n0", len([k for k, _, _ in llo.log if k.startswith("LLVMPassBuilderOptionsSet")]))

  # --- compile(): the ten-call ORDER ---------------------------------
  ll = llvm_compiler(m, 12, 4)
  c = m.LLVMCompiler("AMDGPU", "gfx1100", "+cumode")
  ll.log.clear()
  kind, obj = raised(c.compile, "; ModuleID = 'x'")
  row("ll.comp_kind", kind if kind != "NO-RAISE" else "bytes")
  row("ll.comp_n", len(ll.log))
  emit_log("ll.comp", ll)
  row("ll.comp_obj", obj.hex() if kind == "NO-RAISE" else "")
  # The REAL `handle_diag`, found as the argument the recorder saw in
  # `LLVMContextSetDiagnosticHandler`, called directly. This is the only way to
  # reach compile()'s `if self.diag_msgs: raise`, because `compile` CLEARS the
  # list first and nothing else appends to it.
  lld = llvm_compiler(m, 12, 4)
  cd = m.LLVMCompiler("AMDGPU", "gfx1100", "+cumode")
  handler = None
  for k, a, _ in lld.log:
    if k == "LLVMContextSetDiagnosticHandler": handler = a[1]
  row("ll.handler_found", 1 if handler is not None else 0)
  row("ll.sethandler_arg0", one([a[0] for k, a, _ in lld.log if k == "LLVMContextSetDiagnosticHandler"][0]) if any(k == "LLVMContextSetDiagnosticHandler" for k, _, _ in lld.log) else "-")
  # the handler belongs to `cd`, so the raise is observed on `cd`
  c = cd
  lld.log.clear()
  kind, _ = raised(handler, "DIAGREF", None)
  row("ll.handler_kind", kind if kind != "NO-RAISE" else "NO-RAISE")
  row("ll.handler_sev_calls", ",".join(k for k, _, _ in lld.log))
  row("ll.handler_desc", ",".join(one(a[0]) for k, a, _ in lld.log if k == "LLVMGetDiagInfoDescription"))
  row("ll.handler_sev", ",".join(str(a[0]) for k, a, _ in lld.log if k == "LLVMGetDiagInfoSeverity"))
  row("ll.diag_after", ",".join(c.diag_msgs))
  # compile CLEARS the list first, so the raise is only reachable when the
  # handler fires DURING the compile. Wiring `LLVMVerifyModule` to call the
  # REAL handler is the faithful way to do that.
  c.diag_msgs.clear()
  lld.ret["LLVMVerifyModule"] = lambda *a: (handler("DIAGREF", None), 0)[1]
  kind, _ = raised(c.compile, "; ModuleID = 'y'")
  row("ll.comp_diag", kind)
  row("ll.comp_diag_msg", ("llvm diagnostic: " + "\n".join(c.diag_msgs)) if kind != "NO-RAISE" else "")
  row("ll.comp_cleared", ",".join(c.diag_msgs))
  # TWO diagnostics, so the "\n".join is a join and not a single message
  c.diag_msgs.clear()
  state = [0]
  def two(*a):
    for d in (b"diag one", b"diag two"):
      lld.ret["LLVMGetDiagInfoDescription"] = lambda _d, _b=d: ctypes.create_string_buffer(_b)
      handler("DIAGREF", None)
    state[0] += 1
    return 0
  lld.ret["LLVMVerifyModule"] = two
  row("ll.diag2_twice", str(state[0]))
  kind, _ = raised(c.compile, "; ModuleID = 'z'")
  row("ll.comp_diag2", kind)
  row("ll.comp_diag2_n", len(c.diag_msgs))
  row("ll.comp_diag2_msg", ("llvm diagnostic: " + "\n".join(c.diag_msgs)) if kind != "NO-RAISE" else "")
  # a severity that is not DSError collects nothing, and the compile succeeds
  ll3 = llvm_compiler(m, 12, 4)
  ll3.ret["LLVMGetDiagInfoSeverity"] = lambda d: LLVM_CONSTS["LLVMDSError"] + 1
  c2 = m.LLVMCompiler("AMDGPU", "gfx1100", "+cumode")
  h2 = [a[1] for k, a, _ in ll3.log if k == "LLVMContextSetDiagnosticHandler"][0]
  raised(h2, "DIAGREF", None)
  row("ll.diag_nonerror_n", len(c2.diag_msgs))

  # --- expect / cerr / the numeric facts the port also builds ----------
  row("ll.expect_f0_1", int(bool(5)))
  row("ll.expect_msg2", "failed to run passes")
  row("ll.cerr_depth", 2)
  row("ll.cpu_ge2_two", int(len(["x86_64", "znver2"]) >= 2))
  row("ll.cpu_x18_arm", "+reserve-x18,")
  row("ll.cpu_x18_x86", "")
  row("ll.del_order", "LLVMPassBuilderOptionsDispose LLVMContextDispose")
  row("ll.del_n", 2)
  row("ll.diags_join", "\n".join(["diag one", "diag two"]))
  row("ll.diag_msg", "llvm diagnostic: " + "\n".join(["diag one"]))
  row("ll.diag_msg2", "llvm diagnostic: " + "\n".join(["diag one", "diag two"]))
  row("ll.diag_raise_kind", "RuntimeError")
  row("ll.append_ok", "diag one")
  row("ll.append_ok_n", 1)
  row("ll.append_no", "")
  row("ll.append_no_n", 0)
  row("ll.arch_arm64.triple_ok", 1)
  row("ll.arch_riscv64.triple_ok", 0)
  row("ll.arch_riscv64.inits_n", len(LL_COMPONENTS))
  row("ll.ckey_NONE_opt0_key", "" if helpers.getenv("LLVMOPT", 1) else "compile_llvm_znver2_+avx2")

  # --- __del__ ------------------------------------------------------
  ll = llvm_compiler(m, 12, 4)
  c = m.LLVMCompiler("AMDGPU", "gfx1100", "+cumode")
  ll.log.clear()
  kind, _ = raised(lambda: c.__del__())
  row("ll.del_n", len(ll.log))
  emit_log("ll.del", ll)

  # --- CPULLVMCompiler: featstr, native, reserve-x18 ----------------
  for tag, arch in [("x86", ["x86_64", "znver2"]), ("x86f", ["x86_64", "znver2", "-sse", "+avx2", "fma", "-f16c"]),
                    ("x86n", ["x86_64", "native"]), ("x86nf", ["x86_64", "native", "-sse"]),
                    ("armn", ["arm64", "native"]),
                    ("arm", ["arm64", "apple-m1", "-sve", "+crypto"]), ("rvn", ["riscv64", "native"])]:
    ll = llvm_compiler(m, 12, 4)
    kind, c = raised(m.CPULLVMCompiler, arch)
    row(f"ll.cpu_{tag}.kind", kind if kind != "NO-RAISE" else "ok")
    if kind != "NO-RAISE":
      row(f"ll.cpu_{tag}.err", kind); continue
    row(f"ll.cpu_{tag}.arch", c.arch)
    feats = arch[2:]
    featstr = ",".join(f if f.startswith('-') else '+' + f for f in feats)
    row(f"ll.cpu_{tag}.featstr", featstr)
    # the feats string ACTUALLY handed to `super().__init__`, which carries the
    # `+reserve-x18,` PREFIX and its own trailing comma -- `ll.cpu_arm.tm_args`
    # is the real `LLVMCreateTargetMachine` argument and is the authority here.
    x18 = "+reserve-x18," if arch[0] == "arm64" else ""
    if arch[1] == "native":
      row(f"ll.cpu_{tag}.cpu", "znver4-test")
      row(f"ll.cpu_{tag}.feat_final", x18 + featstr + ("," if featstr else "") + "+avx2,+sse4")
    else:
      row(f"ll.cpu_{tag}.cpu", arch[1]); row(f"ll.cpu_{tag}.feat_final", x18 + featstr)
    row(f"ll.cpu_{tag}.x18", x18)
    if arch[1] == "native" and feats:
      row(f"ll.cpu_{tag}.feat_final_native", x18 + featstr + "," + "+avx2,+sse4")
      row(f"ll.cpu_{tag}.featstr_native", featstr)
    row(f"ll.cpu_{tag}.passes", c.passes.decode())
    row(f"ll.cpu_{tag}.tm_args", ",".join(one(v) for k, a, _ in ll.log if k == "LLVMCreateTargetMachine" for v in a[2:4]))
    row(f"ll.cpu_{tag}.key", str(c.cachekey))
    # the triple for this arch, from the real arch map
    row(f"ll.cpu_{tag}.triple", {"arm64": "aarch64-none-unknown-elf", "x86_64": "x86_64-none-unknown-elf",
                                 "AMDGPU": "amdgcn-amd-amdhsa"}[c.arch])

  # --- AMDLLVMCompiler: reduce, the remap, disassemble --------------
  ll = llvm_compiler(m, 12, 4)
  kind, c = raised(m.AMDLLVMCompiler, "gfx1100")
  row("ll.amd_kind", kind if kind != "NO-RAISE" else "ok")
  if kind == "NO-RAISE":
    row("ll.amd_arch", c.arch)
    row("ll.amd_tm", ",".join(one(v) for k, a, _ in ll.log if k == "LLVMCreateTargetMachine" for v in a[1:4]))
    row("ll.amd_reduce", str(c.__reduce__()))
    row("ll.amd_reduce_kind", type(c.__reduce__()[0]).__name__)
    row("ll.amd_reduce_n", len(c.__reduce__()[1]))
    for tag, msg in [("amdgcn", "undefined value '@llvm.amdgcn.ds_read_u32'"),
                     ("other", "some other RuntimeError"),
                     ("plain", "undefined value"),
                     ("amdgcn_end", "xx undefined value '@llvm.amdgcn.'")]:
      row(f"ll.remap_{tag}", int("undefined value '@llvm.amdgcn." in msg))
      row(f"ll.remap_{tag}_msg", (msg + "AMD with LLVM backend requires LLVM >= 18")
          if "undefined value '@llvm.amdgcn." in msg else msg)
  section("ll", n0)


# ==========================================================================
# compiler_cuda.py
# ==========================================================================
CU_ARCHES = ["sm_75", "sm_86", "sm_120", "compute_86", "sm_89", "sm_90"]


def cuda_mod(major=12, minor=4):
  import tinygrad.runtime.autogen.nvrtc as real_nvrtc
  import tinygrad.runtime.autogen.nvjitlink as real_jl
  nv = Rec("tinygrad.runtime.autogen.nvrtc")
  jl = Rec("tinygrad.runtime.autogen.nvjitlink")
  nv.structs["nvrtcProgram"] = ctypes.c_void_p
  jl.structs["nvJitLinkHandle"] = ctypes.c_void_p
  nv.ret["nvrtcVersion"] = lambda ma, mi: (setattr(ma, "value", major), setattr(mi, "value", minor), 0)[2]
  nv.ret["nvrtcGetErrorString"] = lambda st: ctypes.create_string_buffer(f"nvrtc-string-{st}".encode())
  nv.ret["nvrtcCreateProgram"] = lambda *a: 0
  nv.ret["nvrtcCompileProgram"] = lambda *a: 0
  nv.ret["nvrtcDestroyProgram"] = lambda *a: 0
  nv.ret["nvrtcGetPTXSize"] = lambda *a: 0
  nv.ret["nvrtcGetPTX"] = lambda *a: 0
  nv.ret["nvrtcGetCUBINSize"] = lambda *a: 0
  nv.ret["nvrtcGetCUBIN"] = lambda *a: 0
  jl.ret["nvJitLinkVersion"] = lambda *a: 0
  jl.ret["nvJitLinkCreate"] = lambda *a: 0
  jl.ret["nvJitLinkAddData"] = lambda *a: 0
  jl.ret["nvJitLinkComplete"] = lambda *a: 0
  jl.ret["nvJitLinkDestroy"] = lambda *a: 0
  jl.ret["nvJitLinkGetLinkedCubinSize"] = lambda *a: 0
  jl.ret["nvJitLinkGetLinkedCubin"] = lambda *a: 0
  jl.ret["NVJITLINK_INPUT_PTX"] = JITLINK_IN_PTX
  jl.ret["nvJitLinkResult"] = JITLINK_RESULT
  install("tinygrad.runtime.autogen.nvrtc", nv)
  install("tinygrad.runtime.autogen.nvjitlink", jl)
  row("cu.const_jitlinkresult_n", len(JITLINK_RESULT))
  for k in sorted(JITLINK_RESULT): row(f"cu.const_jitlinkresult_{k}", JITLINK_RESULT[k])
  for k in (0, 15, 99, -1): row(f"cu.const_jitlinkresult_get_{k}", JITLINK_RESULT.get(k))
  return nv, jl


def cu():
  n0 = sec("cu")
  helpers = importlib_import("tinygrad.helpers")
  importlib_import("tinygrad.device")
  importlib_import("tinygrad.runtime.support.c")
  nv, jl = cuda_mod()
  m = load(ROOT / "tinygrad/runtime/support/compiler_cuda.py", "ext_cu")

  # the module-level constants
  row("cu.cudapath", repr(m.CUDA_PATH))
  row("cu.root", str(m.root))
  row("cu.root_is_repo", 1 if str(m.root) == str(ROOT) else 0)
  row("cu.osx", repr(m.OSX))
  row("cu.docker", m.osx_docker_cmd)

  # --- colored(): the escape number and the NO_COLOR guard -----------
  colors = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white']
  for c in colors:
    st = helpers.colored("X", c)
    row(f"cu.esc_{c}", st[2:st.index("m")])
    # RAW, not repr(): the bend row carries the ESC byte itself, so a repr on
    # one side and a raw string on the other would be a formatting difference
    # reported as a port bug.
    row(f"cu.colored_{c}", st)
  row("cu.colored_none", helpers.colored("X", None))
  row("cu.esc_bg_blue", helpers.colored("X", "blue", background=True)[2:helpers.colored("X", "blue", background=True).index("m")])
  row("cu.esc_open_34", "\x1b[34m")
  row("cu.esc_reset", "\x1b[0m")
  row("cu.colors_n", len(colors))
  row("cu.esc_BLUE", helpers.colored("X", "BLUE")[2:helpers.colored("X", "BLUE").index("m")])
  row("cu.colored_BLUE", helpers.colored("X", "BLUE"))

  # --- pretty_ptx: the SIX patterns, read OUT OF THE SOURCE FILE by ast,
  #     and matched by CPython's own `re`.  The port never sees a
  #     transcription of the pattern; it sees the same bytes the upstream
  #     source has.
  src = (ROOT / "tinygrad/runtime/support/compiler_cuda.py").read_text()
  pats = [c.args[0].value for c in ast.walk(ast.parse(src))
          if isinstance(c, ast.Call) and isinstance(c.func, ast.Attribute) and c.func.attr == "sub"
          and c.args and isinstance(c.args[0], ast.Constant)]
  row("cu.npat", len(pats))
  for i, p in enumerate(pats): row(f"cu.pat{i}", p)
  # Each pattern is matched in the MINIMAL context its own group-1 and group-3
  # classes admit, so `group(2)` IS the token when it matches. The context is
  # part of the fixture, not of the pattern.
  CTX = {0: (" ", " "), 1: ("x", "."), 2: ("\t", ";"), 3: (" ", " "), 4: (".", ""), 5: (".", "")}
  TOKENS = [
    "buf0", "buf12", "buf_d", "_foo1", "$bar", "%r15", "_r0", "_t0.x", "_t0.y", "_t0.z",
    "_t0.xy", "_t0:", "$_x1", "%.L_x_1", "_ZN4mainE", "mov", "mad.lo.s64", "s32", "f16",
    "u8", "b64", "pred", "bar.warp", "ld.param.u64", "add.s32", "cvta", "0f3F800000",
    "0F3F800000", "0x1f", "0X1F", "42", "0", "st.global.f32", "ld.global.nc.v4.f32",
    "cvta.to.global.u64", ".param", ".reg", ".global", ".version", ".target",
    ".address_size", ".visible", ".entry", "R0", "RZ", "s16", "u64", "0xdeadBEEF",
    "f8", "u4", "s7", "9", "255", "0x0", "param", "version", "x", "_", "%", "$",
    "buf", "bufa", "bufX", "_a", "$.x", "%.y", "0f3F80000", "0f3F8000000", "0x", "0f",
  ]
  SHARP = ["buf0", "buf", "bufX", "_t0.x", "_t0.xy", "%.L_x_1", "s32", "f16", "b64", "pred",
           "f8", "u4", "0f3F800000", "0f3F80000", "0x1f", "42", "param", "version",
           "mov", "mad.lo.s64", "cvta.to.global.u64", "buf_d", "s7", "0x", "0f"]
  for i, p in enumerate(pats):
    rx = re.compile(p, re.M)
    pre, post = CTX[i]
    def g2(t, _rx=rx, _pre=pre, _post=post):
      m = _rx.search(_pre + t + _post)
      return m.group(2) if (m and m.lastindex and m.lastindex >= 2) else "-"
    row(f"cu.cls{i}", ",".join(f"{t}:{g2(t)}" for t in TOKENS))
    row(f"cu.cls{i}_n", sum(1 for t in TOKENS if g2(t) != "-"))
    row(f"cu.cls{i}_first", g2(TOKENS[0]))
    for t in SHARP: row(f"cu.p{i}_{t}", g2(t))
  # --- _get_bytes: the TWO calls, size then fill --------------------
  nv.log.clear()
  kind, data = raised(m._get_bytes, "PROG", nv.nvrtcGetPTX, nv.nvrtcGetPTXSize, lambda s: None)
  row("cu.getbytes_kind", kind if kind != "NO-RAISE" else "bytes")
  row("cu.getbytes_n", len(nv.log))
  emit_log("cu.getbytes", nv)
  nv.log.clear()
  m._get_bytes("PROG", nv.nvrtcGetCUBIN, nv.nvrtcGetCUBINSize, lambda s: None)
  row("cu.getbytes_size_ptx", "nvrtcGetPTXSize,nvrtcGetPTX")
  row("cu.getbytes_cubin2b", "nvrtcGetCUBINSize,nvrtcGetCUBIN")
  row("cu.getbytes_cubin", ",".join(k for k, _, _ in nv.log))
  row("cu.getbytes_cubin2", ",".join(k for k, _, _ in nv.log[1:]))

  # --- nvrtc_check / jitlink_check: the message ---------------------
  for st in (0, 1, 15, 99):
    kind, _ = raised(m.nvrtc_check, st)
    row(f"cu.nvrtcerr_{st}", kind if kind != "NO-RAISE" else "NO-RAISE")
    if kind != "NO-RAISE": row(f"cu.nvrtcerr_{st}_msg", str(_))
  for st in (0, 1, 15, 99):
    kind, _ = raised(m.jitlink_check, st)
    row(f"cu.jiterr_{st}", kind if kind != "NO-RAISE" else "NO-RAISE")
    if kind != "NO-RAISE": row(f"cu.jiterr_{st}_msg", str(_))
  row("cu.nvrtcerr_fmt", f"Nvrtc Error {15}, nvrtc-string-{15}\n")
  row("cu.jiterr_n", len(JITLINK_RESULT))
  row("cu.jiterr_fmt", f"jitlink Error {15}, {getattr(importlib_import('tinygrad.runtime.autogen.nvjitlink'), 'nvJitLinkResult', {}).get(15)}\n")

  # --- NVRTCCompiler: the non-OSX arm, three nvrtc versions ---------
  for tag, ma, mi in [("v1204", 12, 4), ("v1203", 12, 3), ("v1108", 11, 8), ("v1300", 13, 0), ("v0902", 9, 2)]:
    nv, jl = cuda_mod(ma, mi)
    # `from tinygrad.runtime.autogen import nvrtc, nvjitlink as jitlink` BINDS
    # the modules as globals at import, so replacing sys.modules does not
    # rebind them -- without these two lines every version would be measured
    # with the FIRST recorder and the `(12,4)` threshold would be untested.
    m.nvrtc, m.jitlink = nv, jl
    m.OSX = False
    row(f"cu.nvrtc_{tag}.ver", f"{ma}.{mi}")
    kind, c = raised(m.NVRTCCompiler, "sm_86")
    row(f"cu.nvrtc_{tag}.kind", kind if kind != "NO-RAISE" else "ok")
    if kind != "NO-RAISE": row(f"cu.nvrtc_{tag}.err", kind); continue
    row(f"cu.nvrtc_{tag}.opts", " ".join(c.compile_options))
    row(f"cu.nvrtc_{tag}.opts_n", len(c.compile_options))
    row(f"cu.nvrtc_{tag}.minimal", 1 if "--minimal" in c.compile_options else 0)
    row(f"cu.nvrtc_{tag}.key", str(c.cachekey))
    row(f"cu.nvrtc_{tag}.arch", c.arch)
    row(f"cu.nvrtc_{tag}.ptx", c.ptx)
    nv.log.clear()
    kind, _ = raised(c.compile, ".version 7.5")
    row(f"cu.nvrtc_{tag}.calls_n", len(nv.log))
    row(f"cu.nvrtc_{tag}.calls", ",".join(k for k, _, _ in nv.log))
    row(f"cu.nvrtc_{tag}.first", nv.log[0][0] if nv.log else "")
    row(f"cu.nvrtc_{tag}.last", nv.log[-1][0] if nv.log else "")
  # the CUDA_PATH arm, in whatever process this is
  for tag, cp in [("set", "/my/cuda"), ("unset", "")]:
    row(f"cu.inc_{tag}", f"-I{cp}/include" if cp else "-I/usr/local/cuda/include -I/usr/include -I/opt/cuda/include")
    row(f"cu.inc_{tag}_n", 1 if cp else 3)

  # --- cuda_disassemble: the name, the rstrip, the two commands -----
  import tempfile, hashlib
  for tag, lib, arch, ptx in [("ptx", b"\x00ptx\x00\x00", "sm_86", True), ("cubin", b"\x00cub\x00", "sm_86", False),
                              ("zeros", b"\x00\x00\x00", "sm_120", True), ("empty", b"", "sm_89", False)]:
    digest = hashlib.md5(lib).hexdigest()
    row(f"cu.disfn_{tag}", f"tinycuda_{digest}")
    row(f"cu.disfn_{tag}_n", len(f"tinycuda_{digest}"))
    row(f"cu.disptxas_{tag}", f"ptxas -arch={arch} -o tinycuda_{digest} tinycuda_{digest}" if ptx else "")
    row(f"cu.disnvdisasm_{tag}", f"nvdisasm tinycuda_{digest}")
    row(f"cu.disrstrip_{tag}", lib.rstrip(b'\x00').hex())
    row(f"cu.diskeep_{tag}", lib.hex())
    row(f"cu.disrstrip_n_{tag}", len(lib.rstrip(b'\x00')))
  row("cu.disfail", "Failed to generate SASS")
  row("cu.disfail2", "Make sure your PATH contains ptxas/nvdisasm binary of compatible version.")

  # --- NVCCCompiler: the mode/suffix pair and the command ----------
  for tag, arch, ptx, extra in [("ptx", "sm_86", True, []), ("cubin", "sm_86", False, []),
                                ("extra", "sm_120", True, ["-DFOO=1", "-DBAR=2"]), ("one", "sm_90", False, ["-lineinfo"])]:
    cm, sfx = ("-ptx", ".ptx") if ptx else ("-cubin", ".cubin")
    row(f"cu.nvcc_{tag}.mode", cm); row(f"cu.nvcc_{tag}.suffix", sfx)
    row(f"cu.nvcc_{tag}.join", " ".join(extra))
    row(f"cu.nvcc_{tag}.cmd", f"nvcc -arch={arch} {cm} -o LIB SRC " + " ".join(extra))
    import hashlib as _h
    row(f"cu.nvcc_{tag}.hex8", _h.sha256(" ".join(extra).encode()).hexdigest()[:8])
    row(f"cu.nvcc_{tag}.keystr", f"compile_nvcc_{'cuda'}{'ptx' if ptx else ''}_{arch}")
  row("cu.nvcc_suffixes", ".cu " + "-ptx -cubin")

  # --- PTXCompiler: the version selection and the two replaces -----
  def ptx_ver(arch):
    ver = int(arch[3:])
    return "8.7" if ver >= 120 else ("7.8" if ver >= 89 else "7.5")
  for tag, arch in [("sm75", "sm_75"), ("sm86", "sm_86"), ("sm88", "sm_88"), ("sm89", "sm_89"),
                    ("sm90", "sm_90"), ("sm120", "sm_120"), ("sm200", "sm_200"),
                    ("compute86", "compute_86"), ("short", "sm_8"), ("empty", "sm_"), ("x", "x")]:
    c = m.PTXCompiler(arch)
    row(f"cu.ptxc_{tag}.key", str(c.cachekey))
    row(f"cu.ptxc_{tag}.arch", c.arch)
    pk, pv = raised(ptx_ver, arch)
    row(f"cu.ptxc_{tag}.ver", pk if pk != "NO-RAISE" else pv)
    # the two replaces, in ORDER, on a source that contains both targets
    kind, val = raised(c.compile, ";".join([".version TARGET", ".version VERSION", ".target TARGET"]))
    row(f"cu.ptxc_{tag}.out", kind if kind != "NO-RAISE" else val.decode())
    # a source with SEVERAL occurrences, so a replace-all vs replace-one shows
    k2, v2 = raised(c.compile, "TARGET TARGET")
    row(f"cu.ptxc_{tag}.out2", k2 if k2 != "NO-RAISE" else v2.decode())
    k3, v3 = raised(c.compile, "no targets here")
    row(f"cu.ptxc_{tag}.out3", k3 if k3 != "NO-RAISE" else v3.decode())
    row(f"cu.ptxc_{tag}.ver_ge120", 1 if arch[3:].isdigit() and int(arch[3:]) >= 120 else 0)
    row(f"cu.ptxc_{tag}.ver_ge89", 1 if arch[3:].isdigit() and int(arch[3:]) >= 89 else 0)
  row("cu.ptxc_key_alt", str(m.PTXCompiler("sm_86", cache_key="nv_ptx").cachekey))

  # --- NVPTXCompiler: the jitlink call order -----------------------
  for tag, arch, ptx in [("sm86", "sm_86", True), ("sm120", "sm_120", False)]:
    nv, jl = cuda_mod()
    m.nvrtc, m.jitlink = nv, jl
    m.OSX = False
    kind, c = raised(m.NVPTXCompiler, arch)
    row(f"cu.nvptx_{tag}.kind", kind if kind != "NO-RAISE" else "ok")
    if kind != "NO-RAISE": row(f"cu.nvptx_{tag}.err", kind); continue
    row(f"cu.nvptx_{tag}.key", str(c.cachekey))
    row(f"cu.nvptx_{tag}.arch", c.arch)
    jl.log.clear()
    kind, _ = raised(c.compile, f".version 7.5\n.target {arch}\n")
    row(f"cu.nvptx_{tag}.calls_n", len(jl.log))
    row(f"cu.nvptx_{tag}.calls", ",".join(k for k, _, _ in jl.log))
    row(f"cu.nvptx_{tag}.input", ",".join(str(a[1]) for k, a, _ in jl.log if k == "nvJitLinkAddData"))
  section("cu", n0)


# ==========================================================================
# env / cache -- the boot-constant evidence
# ==========================================================================
def env():
  n0 = sec("env")
  h = importlib_import("tinygrad.helpers")
  for k in ("CC", "CUDA_PATH", "LLVMOPT", "NO_COLOR", "CCACHE", "CUDA_ARCH"):
    row(f"env.raw_{k}", repr(os.environ.get(k, "<unset>")))
  # RAW, not repr(): the bend rows carry the value itself, and a repr on one
  # side and a raw string on the other is a formatting difference that would be
  # reported as a port bug.
  row("env.getenv_CC", h.getenv("CC", "clang"))
  row("env.getenv_CC_bare", repr(h.getenv("CC")))
  row("env.getenv_CUDA_PATH", h.getenv("CUDA_PATH", ""))
  row("env.getenv_LLVMOPT", repr(h.getenv("LLVMOPT", 1)))
  row("env.OSX", repr(h.OSX))
  row("env.NO_COLOR", repr(h.NO_COLOR.value))
  row("env.CCACHE", repr(h.CCACHE.value))
  row("env.colored_blue", h.colored("X", "blue"))   # RAW: the @4 process is where NO_COLOR answers
  section("env", n0)


def cache():
  """The NEGATIVE CONTROL for the fresh-process method, in one process:
  read, then MUTATE `os.environ`, then read again."""
  n0 = sec("cache")
  h = importlib_import("tinygrad.helpers")
  row("cache.before", repr(h.getenv("PROBE_VAR_XYZ", "default")))
  os.environ["PROBE_VAR_XYZ"] = "mutated"
  row("cache.after", repr(h.getenv("PROBE_VAR_XYZ", "default")))
  row("cache.os_after", repr(os.environ.get("PROBE_VAR_XYZ", "default")))
  # a DIFFERENT default is a DIFFERENT functools.cache key, so `getenv(k, 0)`
  # has NOT been consulted yet and DOES see the mutation -- which is why the
  # boot constant is per-ARGUMENTS and not per-key.
  row("cache.other_default", repr(h.getenv("PROBE_VAR_XYZ", "")))
  bk, bv = raised(h.getenv, "PROBE_VAR_XYZ")
  row("cache.bare_after", bk if bk != "NO-RAISE" else repr(bv))
  row("cache.cache_info", repr(h.getenv.cache_info()))
  # and the row that makes the method NECESSARY for a module constant:
  # `compiler_cuda.CUDA_PATH` is bound at IMPORT, so a later mutation is
  # invisible to the module even though `getenv` would see it.
  try:
    sys.modules.pop("ext_cu_mut", None)
    import types as _t
    mm = _t.ModuleType("ext_cu_mut"); mm.__file__ = str(ROOT / "tinygrad/runtime/support/compiler_cuda.py")
    exec(compile((ROOT / "tinygrad/runtime/support/compiler_cuda.py").read_text(), "cu", "exec"), mm.__dict__)
    row("cache.module_before", repr(mm.CUDA_PATH))
    os.environ["CUDA_PATH"] = "/mutated/after/import"
    row("cache.module_after", repr(mm.CUDA_PATH))
    row("cache.getenv_after", repr(h.getenv("CUDA_PATH", "")))
    row("cache.env_after", repr(os.environ.get("CUDA_PATH", "<unset>")))
    row("cache.os_after_2", repr(os.environ.get("PROBE_VAR_XYZ", "<unset>")))
  except BaseException as e:
    row("cache.module_before", f"{type(e).__name__}"); row("cache.module_after", "ERR"); row("cache.getenv_after", "ERR")
  section("cache", n0)


def importlib_import(nm):
  import importlib
  return importlib.import_module(nm)


ENTRY = {"am": "amd", "cpu": "cpu", "ll": "ll", "cu": "cu", "env": "env", "cache": "cache"}


def main():
  only = sys.argv[1:] or list(SEC_NAMES)
  for nm in SEC_NAMES: SECTIONS[nm] = 0
  for nm in only:
    n0 = len(ROWS)
    try: globals()[ENTRY[nm]]()
    except BaseException:
      import traceback
      traceback.print_exc(file=sys.stdout); sys.stdout.flush()
      row(f"{nm}.FATAL", "yes")
    section(nm, n0)
  sys.stdout.write("".join(r + "\n" for r in ROWS)); sys.stdout.flush()
  bad = [nm for nm in only if SECTIONS[nm] == 0]
  for nm in SEC_NAMES: sys.stdout.write(f"META.{nm}.rows={SECTIONS[nm]}\n")
  sys.exit(1 if bad else 0)


if __name__ == "__main__":
  main()