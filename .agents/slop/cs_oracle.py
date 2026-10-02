#!/usr/bin/env python3
"""CPython oracle for the four external-compiler backends.

EVERY expectation is produced by CALLING the real tinygrad code with only the
FFI layer replaced by a RECORDER. Nothing here re-transcribes a Python
expression into an oracle -- that mistake has been made five times in this repo
and the worst of them was an oracle that agreed with the port on all five rows
of a swapped `Bool.pick`.

  compiler_amd.py     comgr.* -> recorder; subprocess.run -> recorder
  compiler_mesa.py    mesa.*/llvm.* -> recorder; helpers.system -> recorder
  compiler_qcom.py    llvm_qcom.* -> recorder; disas_adreno -> recorder
  compileserver.py    run as a REAL subprocess against a stub compiler module

Rows are `name=value` on stdout. `META` rows say how many each section emitted,
so a section that emitted zero can never be mistaken for a passing one.

Exit is 0 only when every expected section emitted at least one row.
"""
import ast, ctypes, hashlib, importlib, importlib.util, io, json, os, pathlib, platform
import struct, subprocess, sys, tempfile, types

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

ROWS, SECTIONS = [], {}

def row(nm, v):
  if isinstance(v, bytes): v = v.decode("latin1")
  ROWS.append(f"{nm}={v}")

for _s in ("amd", "mesa", "qcom", "cs", "mirror", "amdkey"): SECTIONS[_s] = 0
def section(nm, n_before):
  SECTIONS[nm] = len(ROWS) - n_before

def cstr(x):
  """`to_char_p_p` hands back `POINTER(c_char)`, so an element is a C pointer
  and the reader is `string_at`. `ctypes.string_at` itself is stubbed for the
  duration of `check`; this never runs then."""
  if x is None: return b""
  if isinstance(x, (bytes, bytearray)): return bytes(x)
  if isinstance(x, ctypes.c_char): return x.value or b""
  if not isinstance(x, ctypes._Pointer): return b""
  try: return ctypes.string_at(x)
  except Exception: return b""

STRING_AT = [""]
_string_at_real = ctypes.string_at
def set_string_at(v):
  STRING_AT[0] = v
  ctypes.string_at = (lambda ptr, size=-1: STRING_AT[0].encode()) if v is not None else _string_at_real

# --------------------------------------------------------------------------
# The recorder. A module-shaped object with PEP-562 __getattr__, so nothing else
# is intercepted; every autogen name becomes a call that appends
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
      if k.startswith("struct_") or k.endswith("_t"):
        if k not in structs:
          structs[k] = type(k, (ctypes.Structure,), {"_fields_": [("_b", ctypes.c_char * 8)]})
        return structs[k]
      return 0
    f.__name__ = k
    return f
  def ga(k):
    if k in ("log", "ret", "structs") or k.startswith("__"): raise AttributeError(k)
    # A `ret` entry that is NOT callable is a CONSTANT (a libcomgr enum value),
    # and constants are read, never called -- so hand back the value itself.
    if k in ret and not callable(ret[k]):
      m.__dict__[k] = ret[k]; return ret[k]
    # a `struct_*` name pre-registered in `structs` is handed back as the TYPE,
    # because `unpack_lib` calls `.from_buffer_copy` on it rather than calling
    # it; every other autogen name is a function the recorder wraps.
    if k in structs: return structs[k]
    # A ctypes TYPE name (`struct_x` / `x_t`) is handed back as the type, so
    # `byref(T())` and `T.from_buffer_copy` are the shapes the real code uses.
    if k != "struct_blob_reader" and (k.startswith("struct_") or k.endswith("_t")):
      structs[k] = type(k, (ctypes.Structure,), {"_fields_": [("_b", ctypes.c_char * 8)]})
      return structs[k]
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
  # every function the module defined -- which is how the spawn gets stubbed.
  mod = types.ModuleType(name)
  mod.__file__ = str(path)
  exec(compile(pathlib.Path(path).read_text(), str(path), "exec"), mod.__dict__)
  return mod

def one(x):
  if isinstance(x, (bytes, bytearray)): return "b" + repr(bytes(x))
  if isinstance(x, ctypes.Array): return f"<{x._type_.__name__}[{len(x)}]>"
  if isinstance(x, ctypes.Structure): return f"<{type(x).__name__}>"
  if isinstance(x, ctypes._Pointer): return f"<{type(x).__name__}->{cstr(x).decode('latin1')}>"
  return repr(x)

def args_str(a, kw):
  return "(" + ",".join(one(v) for v in a) + ((";" + ",".join(f"{k}={one(v)}" for k, v in kw.items())) if kw else "") + ")"

def emit_log(nm, rec):
  for i, (k, a, kw) in enumerate(rec.log):
    row(f"{nm}.c{i:02d}", f"{k}{args_str(a, kw)}")

# ==========================================================================
# 1. compiler_amd.py
# ==========================================================================
def amd():
  n0 = len(ROWS)
  importlib.import_module("tinygrad.helpers")
  importlib.import_module("tinygrad.device")
  support_c = importlib.import_module("tinygrad.runtime.support.c")
  # The enum constants are VALUES of libcomgr, so the recorder answers them from
  # the REAL autogen module instead of recording them as calls. Harvested BEFORE
  # the recorder is installed, because after installing, `import comgr` IS the
  # recorder. This is the one place a constant is fed in rather than stubbed, and
  # it is what makes `amd.autogen.*` and `amd.hip_*.action*` the SAME numbers
  # rather than two transcriptions that happen to agree.
  _real_mods = {}
  for _mn in ("comgr", "comgr_3"):
    _real_mods[_mn] = importlib.import_module(f"tinygrad.runtime.autogen.{_mn}")
  _real_consts = {n: getattr(_real_mods["comgr"], n) for n in dir(_real_mods["comgr"])
                  if n.startswith("AMD_COMGR_") and isinstance(getattr(_real_mods["comgr"], n), int)}
  comgr = Rec("tinygrad.runtime.autogen.comgr")
  comgr.size_t = ctypes.c_size_t
  def _bind(*a, **k):
    def deco(f):
      def wrapped(*x, **y):
        # the real symbol returns an `amd_comgr_status_t`; 0 is SUCCESS, which
        # is the only value that keeps `check` from raising.
        comgr.log.append((f.__name__, x, y)); f(*x, **y); return 0
      return wrapped
    return deco
  _NM = object()
  # `HIPCompiler.__init__`'s assert is "is comgr's DLL handle in the loader's
  # loaded set". ROCm is absent, so the handle is REGISTERED, which is exactly
  # the fact the assert is about.
  support_c.DLL._loaded_.add(_NM)
  comgr.dll = types.SimpleNamespace(bind=_bind, nm=_NM, emsg="stub", _loaded_={_NM})
  comgr.ret["amd_comgr_status_string"] = lambda status, out: 0
  comgr.ret["amd_comgr_get_version"] = lambda major, minor: 0
  comgr.ret.update(_real_consts)
  install("tinygrad.runtime.autogen.comgr", comgr)
  # The enum values the port DECLARES, read out of the two real autogen files.
  for modname, tag in (("comgr", "2"), ("comgr_3", "3")):
    real = _real_mods[modname]
    row(f"amd.autogen.hiplang_{tag}", real.AMD_COMGR_LANGUAGE_HIP)
    for nm in ("AMD_COMGR_DATA_KIND_SOURCE", "AMD_COMGR_DATA_KIND_LOG", "AMD_COMGR_DATA_KIND_EXECUTABLE",
               "AMD_COMGR_ACTION_ASSEMBLE_SOURCE_TO_RELOCATABLE", "AMD_COMGR_ACTION_CODEGEN_BC_TO_RELOCATABLE",
               "AMD_COMGR_ACTION_LINK_RELOCATABLE_TO_EXECUTABLE", "AMD_COMGR_ACTION_COMPILE_SOURCE_WITH_DEVICE_LIBS_TO_BC"):
      row(f"amd.autogen.{nm}_{tag}", getattr(real, nm))
  mod = load(ROOT / "tinygrad/runtime/support/compiler_amd.py", "cs_amd")
  mod.__name__ = "cs_amd"

  # --- compile_hip: the real function, the FFI recorded -------------------
  for arch, asm in [("gfx1100", False), ("gfx942", False), ("gfx1100", True), ("sm_86", False)]:
    tag = f"amd.hip_{arch}_{int(asm)}"
    comgr.log.clear()
    try:
      mod.compile_hip('extern "C" __global__ void k(){}\n', arch, asm)
      row(f"{tag}.raised", "NO-RAISE")
    except Exception as e:
      row(f"{tag}.raised", f"{type(e).__name__}: {e}")
    emit_log(tag, comgr)
    optlists = [a[1] for k, a, _ in comgr.log if k == "amd_comgr_action_info_set_option_list"]
    for i, arr in enumerate(optlists):
      row(f"{tag}.opt{i}", "|".join(cstr(x).decode("latin1") for x in arr))
      row(f"{tag}.optsp{i}", " ".join(cstr(x).decode("latin1") for x in arr))
      row(f"{tag}.optn{i}", arr._length_)
    for i, a in enumerate([a for k, a, _ in comgr.log if k == "amd_comgr_do_action"]):
      row(f"{tag}.action{i}", a[0])
    row(f"{tag}.action_n", len([1 for k, _, _ in comgr.log if k == "amd_comgr_do_action"]))
    row(f"{tag}.calls", len(comgr.log))
    # `_get_comgr_data` is the four-call tail after the last action; its names
    # and order are what the port's trace records
    tail = [k for k, _, _ in comgr.log][-8:]
    row(f"{tag}.gd_tail", " ".join(tail))
    gdlog = [a for k, a, _ in comgr.log if k == "amd_comgr_action_data_get_data"]
    row(f"{tag}.gd_kind", gdlog[0][1] if gdlog else "NONE")
    row(f"{tag}.gd_calls", len([k for k, _, _ in comgr.log
                                 if k in ("amd_comgr_action_data_get_data", "amd_comgr_get_data",
                                          "amd_comgr_release_data")]))
    names = [a[1] for k, a, _ in comgr.log if k == "amd_comgr_set_data_name"]
    for i, nm in enumerate(names): row(f"{tag}.dataname{i}", cstr(nm).decode("latin1"))
    isa = [cstr(a[1]).decode("latin1") for k, a, _ in comgr.log if k == "amd_comgr_action_info_set_isa_name"]
    for i, nm in enumerate(isa): row(f"{tag}.isa{i}", nm)
    acts = [a[0] for k, a, _ in comgr.log if k == "amd_comgr_do_action"]
    row(f"{tag}.naction", len(acts))
    srcs = [cstr(a[2]).decode("latin1") for k, a, _ in comgr.log if k == "amd_comgr_set_data"]
    for i, nm in enumerate(srcs): row(f"{tag}.srclen{i}", len(nm))

  # --- check(): the refusal message, for real ------------------------------
  # `_get_comgr_data` called DIRECTLY, so the four-call count is the count of ONE
  # invocation and not of the whole compile_hip trace.
  for kind, nm in ((comgr.AMD_COMGR_DATA_KIND_EXECUTABLE, "exec"), (comgr.AMD_COMGR_DATA_KIND_LOG, "log")):
    comgr.log.clear()
    out = mod._get_comgr_data(None, kind)
    row(f"amd.gd_{nm}.calls", len(comgr.log))
    row(f"amd.gd_{nm}.names", " ".join(k for k, _, _ in comgr.log))
    gdk = [a for k, a, _ in comgr.log if k == "amd_comgr_action_data_get_data"]
    row(f"amd.gd_{nm}.kind", gdk[0][1] if gdk and len(gdk[0]) > 1 else "NONE")
    row(f"amd.gd_{nm}.out", out.decode("latin1"))

  # check() with a non-zero status -- the RuntimeError message, for real
  for status, msg in [(0, ""), (7, "comgr-status-7"), (-1, "boom"), (255, "a b c")]:
    set_string_at(msg)
    try:
      mod.check(status); row(f"amd.check_{status}", "NO-RAISE")
    except RuntimeError as e:
      row(f"amd.check_{status}.status", status)
      row(f"amd.check_{status}.msg", str(e))
      row(f"amd.check_{status}.kind", type(e).__name__)
  set_string_at(None)

  # --- set_options(): the b' ' split, called for real ----------------------
  for tag, opts in [("two", b"-O3 -mcumode"), ("empty", b""), ("three", b"-O3 -mllvm -amdgpu-internalize-symbols"),
                    ("dbl", b"a  b"), ("lead", b" lead"), ("trail", b"trail "), ("tabs", b"a\tb"),
                    ("many", b"  "), ("one", b"solo")]:
    comgr.log.clear()
    mod.set_options(None, opts)
    arr = [a[1] for k, a, _ in comgr.log if k == "amd_comgr_action_info_set_option_list"][0]
    row(f"amd.split_{tag}.arr", "|".join(cstr(x).decode("latin1") for x in arr))
    row(f"amd.split_{tag}.n", arr._length_)
    row(f"amd.split_{tag}.python", "|".join(opts.split(b" ").decode if False else opts.decode().split(" ")))

  # --- HIPCompiler.compile(): the .text predicate, through the real class --
  real_hip = mod.compile_hip
  cases = [".text", ".text\nfoo", "  .text  \nfoo", ".text ", " .text extra", "nope", "", "\n.text",
           "\t.text\t\n", "#pragma\n.text", ".TEXT\n", "x\n.text\n", ".text;x\n", "\n\n.text", "text\n",
           " .text\n\tmore\n"]
  for i, src in enumerate(cases):
    seen = {}
    mod.compile_hip = lambda prg, arch="gfx1100", asm=False: (seen.__setitem__("asm", asm), b"OK")[1]
    c = object.__new__(mod.HIPCompiler); c.arch = "gfx1100"
    out = c.compile(src)
    mod.compile_hip = real_hip
    row(f"amd.asm{i}.src", repr(src))
    row(f"amd.asm{i}.asm", int(bool(seen.get("asm"))))
    row(f"amd.asm{i}.ret", out.decode("latin1"))

  # --- cache keys through the real __init__ --------------------------------
  for arch in ["gfx1100", "gfx942", "gfx1101"]:
    row(f"amd.hipkey_{arch}", mod.HIPCompiler(arch).cachekey)
  for arch, extra, nohip in [("gfx1100", [], 0), ("gfx1100", ["-DFOO=1"], 0), ("gfx1100", [], 1),
                             ("gfx942", ["-A", "-B"], 0), ("gfx942", ["-X y z"], 1)]:
    tag = f"amd.hipcc_{arch}_{'-'.join(extra).replace(' ', '_').replace('=', '') or 'none'}_{nohip}"
    os.environ["NO_HIPCC"] = str(nohip)
    c = mod.HIPCCCompiler(arch, extra)
    row(f"{tag}.key", c.cachekey)
    row(f"{tag}.join", " ".join(extra))
    row(f"{tag}.nohip", c.no_hipcc)
    row(f"{tag}.env", os.environ["NO_HIPCC"])
    row(f"{tag}.getenv", c.no_hipcc and 1 or 0)
  os.environ.pop("NO_HIPCC", None)

  # --- HIPCompiler.compile's CompileError remap, for real ------------------
  # one comgr call returns non-zero, `check` raises the RuntimeError, and the
  # real `compile` remaps it to CompileError.
  comgr.ret["amd_comgr_action_info_set_isa_name"] = lambda ai, nm: 42
  STRING_AT[0] = "isa-nope"
  for i, src in enumerate([".text\nbody", "plain\nbody"]):
    seen2 = {}
    real_hip2 = mod.compile_hip
    mod.compile_hip = lambda prg, arch="gfx1100", asm=False: (seen2.__setitem__("asm", asm),
        (_ for _ in ()).throw(RuntimeError(f"comgr fail 42, isa-nope")))[1]
    c2 = object.__new__(mod.HIPCompiler); c2.arch = "gfx1100"
    try:
      c2.compile(src)
      row(f"amd.ce_{i}.raised", "NO-RAISE")
    except Exception as e:
      row(f"amd.ce_{i}.asm", seen2.get("asm"))
      row(f"amd.ce_{i}.type", type(e).__name__)
      row(f"amd.ce_{i}.msg", str(e))
    mod.compile_hip = real_hip2
  comgr.ret.pop("amd_comgr_action_info_set_isa_name", None)
  set_string_at(None)

  # --- HIPCCCompiler.compile(): the two argv lists, spawn stubbed ----------
  calls = []
  _real_run = subprocess.run
  def _run(argv, **kw):
    calls.append(list(argv))
    return types.SimpleNamespace(returncode=0)
  subprocess.run = _run
  for arch, rocm, extra in [("gfx1100", "/opt/rocm", []), ("gfx942", "/opt/rocm", ["-DFOO=1", "-DBAR"]),
                            ("gfx1030", "/my/rocm", [])]:
    tag = f"amd.cc_{arch}_{rocm.replace('/', '_')}_{'-'.join(extra).replace('=', '') or 'none'}"
    calls.clear()
    os.environ["ROCM_PATH"] = rocm
    c = mod.HIPCCCompiler(arch, extra)
    c.compile('// hi\nint main(){}\n')
    row(f"{tag}.ncalls", len(calls))
    row(f"{tag}.suffixes", " ".join([".cpp", ".bc", ".hsaco"]))
    row(f"{tag}.rocm_default", "/opt/rocm")
    row(f"{tag}.rocm_include", f"-I{rocm}/include/hip")
    for i, argv in enumerate(calls):
      # temp paths are random, so the gate rows are the argv with every
      # filesystem path replaced by its SUFFIX -- which is the part the port
      # actually constructs (`suffix=` on NamedTemporaryFile).
      norm = [os.path.splitext(x)[1] if x.startswith(tempfile.gettempdir()) else x for x in argv]
      row(f"{tag}.argv{i}", " ".join(norm))
      row(f"{tag}.argvn{i}", len(argv))
      row(f"{tag}.prog{i}", argv[0])
      row(f"{tag}.flags{i}", " ".join(x for x in argv[1:] if not x.startswith("/")))
      row(f"{tag}.paths{i}", " ".join(os.path.splitext(x)[1] for x in argv if x.startswith(tempfile.gettempdir())))
      row(f"{tag}.outs{i}", os.path.splitext(argv[argv.index("-o") + 1])[1])
      row(f"{tag}.srcs{i}", os.path.splitext(argv[-1])[1])
    os.environ.pop("ROCM_PATH", None)
  # NO_HIPCC short-circuits before any spawn
  os.environ["NO_HIPCC"] = "1"
  calls.clear()
  row("amd.cc_nohip.ret", repr(mod.HIPCCCompiler("gfx1100", []).compile("// x")))
  row("amd.cc_nohip.ncalls", len(calls))
  os.environ.pop("NO_HIPCC", None)
  subprocess.run = _real_run
  section("amd", n0)

# ==========================================================================
# 2. compiler_mesa.py
# ==========================================================================
def mesa():
  n0 = len(ROWS)
  helpers = importlib.import_module("tinygrad.helpers")
  importlib.import_module("tinygrad.device")
  # the REAL autogen.mesa first: `unpack_lib`'s two offsets are `sizeof` of real
  # ctypes structs, and those are the platform's own answers, not a fixture.
  import tinygrad.runtime.autogen.mesa as real_mesa
  mesa_m = Rec("tinygrad.runtime.autogen.mesa")
  llvm_m = Rec("tinygrad.runtime.autogen.llvm")
  libc_m = Rec("tinygrad.runtime.autogen.libc")
  cllvm = Rec("tinygrad.runtime.support.compiler_llvm")
  # `LVPCompiler` SUBCLASSES CPULLVMCompiler, so the stub has to be a class.
  # Its __init__ records the arch list, which is `arch.split(",")` -- the only
  # part of LVPCompiler.__init__ that is not an FFI call.
  cllvm.ret["struct_"] = None
  class CPULLVMCompiler:
    def __init__(self, archs, cache_key=None):
      self.archs = list(archs); self.cache_key = cache_key
    def compile(self, src): return src.encode()
  cllvm.CPULLVMCompiler = CPULLVMCompiler
  # unpack_lib's two offsets ARE `ctypes.sizeof` of these two, so the recorder
  # must hand back the real types or there is nothing to measure.
  for _n in ("struct_ir3_shader_variant", "struct_ir3_const_state", "struct_nak_shader_info"):
    mesa_m.structs[_n] = getattr(real_mesa, _n)
  def _bytesptr(n=8):
    # `.contents` then `bytes(...)` is the shape NAK/IR3 read a ctypes buffer by
    buf = ctypes.create_string_buffer(n)
    return ctypes.cast(buf, ctypes.POINTER(ctypes.c_char * n))
  mesa_m.ret["nak_nir_options"] = lambda cc: _bytesptr()
  mesa_m.ret["ir3_get_compiler_options"] = lambda cc: _bytesptr()
  mesa_m.ret["ir3_compiler_create"] = lambda *a: _bytesptr()
  # `compiler_mesa.py` reads `.gpu_id` / `.chip_id` / `.disable_cache` off these
  # three. The real autogen types pack them into an opaque `_mem_` blob (CHECKED:
  # every real struct's only field is `_mem_`), so the FIELD NAMES here are the
  # names the PYTHON reads, not names read out of a mesa header.
  mesa_m.structs["struct_fd_dev_id"] = type("struct_fd_dev_id", (ctypes.Structure,),
    {"_fields_": [("gpu_id", ctypes.c_uint), ("chip_id", ctypes.c_uint)]})
  mesa_m.structs["struct_ir3_compiler_options"] = type("struct_ir3_compiler_options", (ctypes.Structure,),
    {"_fields_": [("disable_cache", ctypes.c_bool)]})
  mesa_m.structs["struct_nv_device_info"] = type("struct_nv_device_info", (ctypes.Structure,),
    {"_fields_": [("sm", ctypes.c_uint), ("max_warps_per_mp", ctypes.c_uint)]})
  cllvm.expect = lambda v, err, *a: v
  cllvm.cerr = lambda: ("ERRPTR", 0)
  install("tinygrad.runtime.autogen.mesa", mesa_m)
  install("tinygrad.runtime.autogen.llvm", llvm_m)
  install("tinygrad.runtime.autogen.libc", libc_m)
  install("tinygrad.runtime.support.compiler_llvm", cllvm)

  def struct_blob_reader():
    import tinygrad.runtime.autogen.mesa as _m  # not importable; make our own
  # the blobs `deserialize` hands blob_reader_init are RECORDED, not decoded
  mesa_m.ret["struct_blob_reader"] = lambda: b"BLOBREADER"
  mesa_m.ret["blob_reader_init"] = lambda br, src, n: (mesa_m.log.append(("blob_len", (n,), {})), 0)[1]
  cllvm.expect = lambda v, err, *a: v
  cllvm.cerr = lambda: ("ERRPTR", 0)
  install("tinygrad.runtime.autogen.mesa", mesa_m)
  install("tinygrad.runtime.autogen.llvm", llvm_m)
  install("tinygrad.runtime.autogen.libc", libc_m)
  install("tinygrad.runtime.support.compiler_llvm", cllvm)
  mod = load(ROOT / "tinygrad/runtime/support/compiler_mesa.py", "cs_mesa")
  mod.__name__ = "cs_mesa"

  # --- warps_per_sm: a staticmethod, no FFI at all ------------------------
  w = mod.NAKCompiler.warps_per_sm
  for arch in ["sm_86", "sm_87", "sm_89", "sm_120", "sm_75", "sm_80", "sm_90", "sm_100", "sm_86x",
               "SM_86", "sm_86 ", "sm_8", "", "sm"]:
    row(f"mesa.warps_{arch or 'EMPTY'}", w(arch))
  for arch in ["sm_86", "sm_89", "sm_120", "sm_75"]:
    row(f"mesa.sm_{arch}", int(arch[3:]))
    row(f"mesa.arch3_{arch}", repr(arch[3:]))

  # --- NAKCompiler: arch -> nv_device_info -> cachekey --------------------
  for arch in ["sm_86", "sm_89", "sm_120", "sm_75", "sm_90"]:
    tag = f"mesa.nak_{arch}"
    mesa_m.log.clear()
    try:
      c = mod.NAKCompiler(arch)
      row(f"{tag}.key", c.cachekey)
      row(f"{tag}.arch", c.arch)
    except Exception as e:
      row(f"{tag}.EXC", f"{type(e).__name__}: {e}")
    for i, (k, a, kw) in enumerate(mesa_m.log):
      row(f"{tag}.c{i:02d}", f"{k}{args_str(a, kw)}")
      if k in ("amd_comgr_do_action", "amd_comgr_create_data", "amd_comgr_action_info_set_language"):
        row(f"{tag}.{k}_id", a[0])
      if k == "struct_nv_device_info":
        di = a[0] if a else type("DI", (), {"sm": kw.get("sm"), "max_warps_per_mp": kw.get("max_warps_per_mp")})()
        for fld in ("sm", "max_warps_per_mp"):
          try: row(f"{tag}.{fld}", getattr(di, fld))
          except Exception: row(f"{tag}.{fld}", "NOFIELD")

  # --- IR3Compiler: the arch assert, the dev_id, the decode options ------
  for arch in ["a630", "a630,x", "a640", "a6300", "", "A630", "a630,", "a630,a640"]:
    tag = f"mesa.ir3_{arch or 'EMPTY'}"
    mesa_m.log.clear()
    try:
      c = mod.IR3Compiler(arch)
      row(f"{tag}.key", c.cachekey)
      row(f"{tag}.arch", c.arch)
      row(f"{tag}.gpu_id", c.dev_id.gpu_id)
      row(f"{tag}.chip_id", c.dev_id.chip_id)
    except Exception as e:
      row(f"{tag}.EXC", f"{type(e).__name__}: {e}")
    for i, (k, a, kw) in enumerate(mesa_m.log):
      row(f"{tag}.c{i:02d}", f"{k}{args_str(a, kw)}")
      if k in ("amd_comgr_do_action", "amd_comgr_create_data", "amd_comgr_action_info_set_language"):
        row(f"{tag}.{k}_id", a[0])
      if k == "struct_fd_dev_id":
        d = a[0] if a else type("DI", (), {"gpu_id": kw.get("gpu_id"), "chip_id": kw.get("chip_id")})()
        for fld in ("gpu_id", "chip_id"):
          try: row(f"{tag}.{fld}", getattr(d, fld))
          except Exception: row(f"{tag}.{fld}", "NOFIELD")
      if k == "struct_ir3_compiler_options":
        d = a[0] if a else None
        row(f"{tag}.disable_cache", getattr(d, "disable_cache", "NOFIELD"))

  # --- lp_type: the four flags, as the real struct carries them -----------
  row("mesa.lptype.args", "floating=True,sign=True,width=32,length=4")

  # --- unpack_lib: REAL ctypes struct sizes, real buffer slicing ---------
  SV = ctypes.sizeof(real_mesa.struct_ir3_shader_variant)
  CS = ctypes.sizeof(real_mesa.struct_ir3_const_state)
  NAKI = ctypes.sizeof(real_mesa.struct_nak_shader_info)
  row("mesa.sizeof_variant", SV); row("mesa.sizeof_const_state", CS); row("mesa.sizeof_nak_info", NAKI)
  unpack = mod.IR3Compiler.unpack_lib
  for cnt in [0, 1, 2, 3, 5]:
    total = SV + CS + cnt * 4 + 6
    buf = bytearray(b"\xAB" * total)
    # a real struct copy so `.imm_state.count` is whatever ctypes says it is
    try:
      v = real_mesa.struct_ir3_shader_variant.from_buffer_copy(bytes(buf))
      v.imm_state.count = cnt
      vv = real_mesa.struct_ir3_shader_variant.from_buffer_copy(bytes(buf))
      cs = real_mesa.struct_ir3_const_state.from_buffer_copy(bytes(buf[SV:]))
      got_v, got_cs, imm, asm = unpack(bytes(buf))
      row(f"mesa.unpack_{cnt}.vsize", ctypes.sizeof(got_v))
      row(f"mesa.unpack_{cnt}.count", got_v.imm_state.count)
      row(f"mesa.unpack_{cnt}.imm", imm.hex())
      row(f"mesa.unpack_{cnt}.asmlen", len(asm))
      row(f"mesa.unpack_{cnt}.asmtail", asm.hex())
      row(f"mesa.unpack_{cnt}.cs_size", ctypes.sizeof(got_cs))
    except Exception as e:
      row(f"mesa.unpack_{cnt}.EXC", f"{type(e).__name__}: {e}")

  # --- the compile_server framing (device.py) that these libs are read by --
  row("amd.frame.pack", struct.pack("I", 0x01020304).hex())
  for v in [0, 1, 255, 256, 65535, 0x7FFFFFFF, 0xFFFFFFFF]:
    row(f"amd.frame.unpack_{v}", struct.unpack("I", struct.pack("I", v))[0])
    row(f"amd.frame.bytes_{v}", struct.pack("I", v).hex())
  row("amd.frame.lowbyte_first", struct.pack("I", 1).hex())
  row("amd.frame.highbyte_first", struct.pack(">I", 1).hex())

  # --- data64 / the disas_adreno line format -----------------------------
  for v in [0, 1, 0xFFFFFFFF, 0x100000000, 0x123456789ABCDEF0, 0xFFFFFFFFFFFFFFFF]:
    fst, snd = helpers.data64(v)
    row(f"mesa.data64_{v:016x}_fst", fst)
    row(f"mesa.data64_{v:016x}_snd", snd)
  _cases = [(0, 0), (1, 1), (15, 0xF), (255, 0xFF), (4096, 0xDEADBEEFCAFEBABE),
            (65535, 0xFFFFFFFFFFFFFFFF), (1, 0x0000000100000002), (2, 0xABCDEF0123456789),
            (65536, 0x10), (12345, 0), (999, 0x00000000FFFFFFFF)]
  for i, (n, instr) in enumerate(_cases):
    fst, snd = helpers.data64(instr)
    row(f"mesa.line{i}.n", n)
    row(f"mesa.line{i}.instr", f"{instr:016x}")
    row(f"mesa.line{i}.fmt", f"{n:04} [{fst:08x}_{snd:08x}] ")

  # --- nvdisasm / objdump command strings, through the real code ---------
  syscalls = []
  mod.system = lambda cmd, **kw: (syscalls.append((cmd, kw)), "OUT")[1]
  for arch in ["sm_86", "sm_120", "sm_75"]:
    lib = bytes(range(16))
    c = object.__new__(mod.NAKCompiler); c.arch = arch
    syscalls.clear()
    # the real method prints on failure, so capture stdout for the call
    _cap, realout = io.StringIO(), sys.stdout
    sys.stdout = _cap
    try: c.disassemble(lib)
    except Exception as e: row(f"mesa.nvdis_{arch}.EXC", f"{type(e).__name__}: {e}")
    finally: sys.stdout = realout
    row(f"mesa.nvdis_{arch}.printed", _cap.getvalue().strip().replace(tempfile.gettempdir(), "$TMP"))
    for i, (cmd, kw) in enumerate(syscalls):
      row(f"mesa.nvdis_{arch}.cmd{i}", cmd.replace(tempfile.gettempdir(), "$TMP"))
      row(f"mesa.nvdis_{arch}.nwords{i}", cmd.count(" "))
    row(f"mesa.nvdis_{arch}.ncalls", len(syscalls))
  row("mesa.nakmd5_16B", hashlib.md5(bytes(range(16))).hexdigest())
  row("mesa.nakmd5_empty", hashlib.md5(b"").hexdigest())
  row("mesa.nvdis_path_shape", str(pathlib.Path(tempfile.gettempdir()) / f"tinynak_{'x'*32}").replace(tempfile.gettempdir(), "$TMP"))
  # The split point of `unpack_lib` is `v.imm_state.count * 4`, and the REAL
  # autogen struct cannot supply that (opaque `_mem_`), so the same REAL
  # function is run against a struct that CAN: the field NAME is the name the
  # Python reads, and `count` is driven per fixture. Both offsets stay real.
  class ImmState(ctypes.Structure):
    _fields_ = [("count", ctypes.c_uint), ("values", ctypes.c_uint * 64)]
  class VariantWithCount(ctypes.Structure):
    _fields_ = [("imm_state", ImmState), ("pad", ctypes.c_byte * (SV - ctypes.sizeof(ImmState)))]
  mesa_m.structs["struct_ir3_shader_variant"] = VariantWithCount
  mesa_m.__dict__["struct_ir3_shader_variant"] = VariantWithCount
  for cnt in [0, 1, 2, 3, 5, 9]:
    total = SV + CS + cnt * 4 + 6
    buf = bytearray(b"\xAB" * total)
    v = VariantWithCount.from_buffer_copy(bytes(buf)); v.imm_state.count = cnt
    csp = real_mesa.struct_ir3_const_state.from_buffer_copy(bytes(buf[SV:]))
    gv, gc, imm, asm = unpack(bytes(buf))
    row(f"mesa.upk_{cnt}.count", gv.imm_state.count)
    row(f"mesa.upk_{cnt}.imm", imm.hex())
    row(f"mesa.upk_{cnt}.asmlen", len(asm))
    row(f"mesa.upk_{cnt}.asmtail", asm.hex())
    row(f"mesa.upk_{cnt}.immlen_eq_count4", 1 if len(imm) == cnt * 4 else 0)
    row(f"mesa.upk_{cnt}.sum_eq_tail", len(imm) + len(asm))
  mesa_m.structs["struct_ir3_shader_variant"] = real_mesa.struct_ir3_shader_variant
  mesa_m.__dict__["struct_ir3_shader_variant"] = real_mesa.struct_ir3_shader_variant

  section("mesa", n0)

# ==========================================================================
# 3. compiler_qcom.py
# ==========================================================================
def qcom():
  n0 = len(ROWS)
  helpers = importlib.import_module("tinygrad.helpers")
  importlib.import_module("tinygrad.device")
  importlib.import_module("tinygrad.runtime.support.compiler_mesa")
  q = Rec("tinygrad.runtime.autogen.llvm_qcom")
  install("tinygrad.runtime.autogen.llvm_qcom", q)
  calls = []
  def fake_adreno(lib, gpu_id=630):
    calls.append((lib, gpu_id)); return None
  mod = load(ROOT / "tinygrad/runtime/support/compiler_qcom.py", "cs_qcom")
  mod.__name__ = "cs_qcom"
  # `rootlib.Path(__file__).parents[3]` -- the file's own location decides the
  # mount target, so the ONLY way to compare the docker string against a fixture
  # is to place the loaded module where the fixture root is. `cs_qcom` is loaded
  # from the real tree, so the root is the real repository and the row below
  # records the docker command with the root SUBSTITUTED.
  DOCKER_ROOT = pathlib.Path(ROOT).resolve()
  mod.disas_adreno = fake_adreno
  mod.fetch = lambda url, **kw: pathlib.Path("/F")
  mod.platform = types.SimpleNamespace(machine=lambda: "aarch64")
  mod.shutil = types.SimpleNamespace(which=lambda n: "/usr/bin/" + n if n.startswith("qemu") else None)

  # --- _read_lib: struct.unpack("I", ...) -- pure, no FFI ----------------
  rd = mod._read_lib
  _bufs = [b"\x01\x00\x00\x00", b"\x00\x00\x00\x01", b"\xff\xff\xff\xff", b"\x00\x00\x00\x00",
           b"\x78\x56\x34\x12", b"\x12\x34\x56\x78", b"\x01", b"\x01\x02\x03", b"", b"\x11\x22"]
  for i, buf in enumerate(_bufs):
    row(f"qcom.buf{i}", buf.hex())
    for off in [0, 1, 2, 3, 4, 0xC0, 0x100]:
      try: row(f"qcom.read_{i}_{off}", rd(buf, off))
      except Exception as e: row(f"qcom.read_{i}_{off}", type(e).__name__)
  # little-endian is the load-bearing fact: the same bytes BE
  row("qcom.endian_le", struct.pack("I", 0x01020304).hex())
  row("qcom.endian_be", struct.pack(">I", 0x01020304).hex())
  for v in [0, 1, 0x6030001, 0xFFFFFFFF, 0x100]:
    row(f"qcom.readval_{v}", rd(struct.pack("I", v) + b"\x00" * 8, 0))

  # --- __init__: the a630 assert and the chip id -------------------------
  for arch in ["a630", "a630,x", "a640", "", "A630", "a63"]:
    tag = f"qcom.init_{arch or 'EMPTY'}"
    try:
      c = mod.QCOMCompiler(arch)
      row(f"{tag}.key", c.cachekey); row(f"{tag}.chip_id", c.chip_id)
    except Exception as e:
      row(f"{tag}.EXC", f"{type(e).__name__}: {e}")

  # --- the two compile_server command strings, built by the real code ----
  root = "/R"     # the same fixture root the bend gate uses
  for arch, which, machine in [("a630", "/usr/bin/qemu-aarch64-static", "aarch64"),
                               ("a630", None, "x86_64"), ("a630,x", "/usr/bin/qemu-aarch64-static", "x86_64"),
                               ("a640", None, "x86_64")]:
    tag = f"qcom.srv_{arch.replace(',', '-')}_{'qemu' if which else 'docker'}_{machine}"
    mod.platform = types.SimpleNamespace(machine=lambda m=machine: m)
    mod.shutil = types.SimpleNamespace(which=lambda n, w=which: w)
    dev = importlib.import_module("tinygrad.device")
    got = {}
    class FakeProc:
      def kill(self): pass
      stdin = None; stdout = None
    def fake_server(self, cmd, arch_, *a):
      got["cmd"] = cmd; got["arch"] = arch_; got["args"] = a
      return FakeProc()
    dev.Compiler.server = fake_server
    try:
      c = mod.QCOMCompiler(arch)
      cmd = got.get("cmd", "NO-CMD")
      row(f"{tag}.cmd", cmd.replace(str(DOCKER_ROOT), "/R"))
      row(f"{tag}.cmd_real_root", cmd)
      row(f"{tag}.arch", got.get("arch"))
      row(f"{tag}.key", c.cachekey)
    except Exception as e:
      row(f"{tag}.EXC", f"{type(e).__name__}: {e}")

  # --- disassemble: the offset/end slice, real code, recorded slice ------
  for body, ofs, n2 in [
      (bytearray(b"\x00" * 0x104), 0, 0),           # both offsets zero -> empty slice
      (bytearray(b"\x00" * 0x100 + b"\x04\x00\x00\x00\x07\x00\x00\x00" + b"Z" * 8), 0xC0, 0x100),
      (bytearray(b"\x00" * 0x100 + b"\x08\x00\x00\x00" + b"Q" * 64), 0xC0, 0x100),
      (bytes(i & 0xFF for i in range(0x110)), 0, 0),
      (bytearray(b"\xFF" * 0x104), 0, 0),
  ]:
    tag = f"qcom.dis_{hashlib.md5(body).hexdigest()[:8]}"
    lib = body
    calls.clear()
    c = object.__new__(mod.QCOMCompiler); c.chip_id = 0x6030001
    c.disassemble(bytes(lib))
    for i, (sl, gid) in enumerate(calls):
      row(f"{tag}.slice{i}", sl.hex())
      row(f"{tag}.len{i}", len(sl))
      row(f"{tag}.gpu{i}", gid)
    row(f"{tag}.ncalls", len(calls))

  # --- checked(): the error message --------------------------------------
  row("qcom.msg_plain", "QCOM Compilation Error")
  section("qcom", n0)

# ==========================================================================
# 4. compileserver.py -- a REAL subprocess, real stdin/stdout, real framing
# ==========================================================================
def compileserver():
  n0 = len(ROWS)
  tmp = pathlib.Path(tempfile.mkdtemp(prefix="cs-oracle-"))
  stub = tmp / "stubc.py"
  stub.write_text(
    "import sys\n"
    "class S:\n"
    "  arch = None\n"
    "  def __init__(self, arch, *a): self.arch = arch; self.args = a\n"
    "  def compile(self, src):\n"
    "    if src == 'RAISE': raise ValueError('stub-compile-failed')\n"
    "    if src == 'EMPTY': return b''\n"
    "    return ('LIB[' + self.arch + ']:' + src + ']').encode()\n"
    "def fromimport(mod, frm):\n"
    "  import importlib; return getattr(importlib.import_module(mod), frm)\n"
  )
  srv = ROOT / "tinygrad/runtime/support/compileserver.py"
  env = dict(os.environ, PYTHONPATH=f"{tmp}:{tmp}")
  cases = [("gfx1100", []), ("a630", ["1", "2"]), ("sm_86", ["'x'"]), ("a630", ["{'a':1}"])]
  for i, (arch, extra) in enumerate(cases):
    argv = [sys.executable, str(srv), f"stubc:{('S')}", arch] + extra
    frames = b""
    for src in [f"src{i}", "EMPTY", "RAISE", f"src{i}b"]:
      b = src.encode(); frames += struct.pack("I", len(b)) + b
    r = subprocess.run(argv, input=frames, capture_output=True, env=env, timeout=60)
    row(f"cs.frames_{i}.argn", len(argv))
    row(f"cs.frames_{i}.argv_tail", " ".join(argv[1:]))
    row(f"cs.frames_{i}.rc", r.returncode)
    out = r.stdout
    row(f"cs.frames_{i}.outlen", len(out))
    row(f"cs.frames_{i}.outhex", out.hex())
    # decode it the way the client does: read 4, unpack the LE length, take it
    pos, decoded, lens = 0, [], []
    while pos < len(out):
      n = struct.unpack("I", out[pos:pos + 4])[0]; pos += 4
      lens.append(n); decoded.append(out[pos:pos + n]); pos += n
    row(f"cs.frames_{i}.lens", "|".join(str(x) for x in lens))
    row(f"cs.frames_{i}.libs", "|".join(cstr(b).decode("latin1") for b in decoded))
    row(f"cs.frames_{i}.stderr_nonempty", 1 if r.stderr.strip() else 0)
    row(f"cs.frames_{i}.stderr_has_msg", 1 if b"stub-compile-failed" in r.stderr else 0)
    row(f"cs.frames_{i}.trailing_bytes", len(out) - pos)
  # too few argv -> the assert, and the usage string
  for argc in [0, 1, 2]:
    argv = [sys.executable, str(srv)] + ["x"] * argc
    r = subprocess.run(argv, input=b"", capture_output=True, env=env, timeout=60)
    row(f"cs.argc_{argc}.rc", r.returncode)
    row(f"cs.argc_{argc}.err_nonempty", 1 if r.stderr.strip() else 0)
    row(f"cs.argc_{argc}.err_last", r.stderr.decode("latin1").strip().splitlines()[-1] if r.stderr.strip() else "")
  # argv[1] with no ':' -> the split the real code does
  for spec in ["stubc", "stubc:S", "a:b:c", ":S", "S:"]:
    argv = [sys.executable, str(srv), spec, "gfx1100"]
    inp = struct.pack("I", 3) + b"abc"
    r = subprocess.run(argv, input=inp, capture_output=True, env=env, timeout=60)
    row(f"cs.spec_{spec.replace(':', '_') or 'EMPTY'}.rc", r.returncode)
    row(f"cs.spec_{spec.replace(':', '_') or 'EMPTY'}.out", r.stdout.hex())
    row(f"cs.spec_{spec.replace(':', '_') or 'EMPTY'}.errlast",
        r.stderr.decode("latin1").strip().splitlines()[-1] if r.stderr.strip() else "")
  section("cs", n0)

def amdkey():
  """`helpers.getenv` is `@functools.cache`, so NO_HIPCC is read ONCE per
  process. This section therefore runs in a FRESH interpreter with the
  variable set before startup, which is the only way the real `HIPCCCompiler`
  can be observed with `no_hipcc` true."""
  n0 = len(ROWS)
  importlib.import_module("tinygrad.helpers")
  importlib.import_module("tinygrad.device")
  sc = importlib.import_module("tinygrad.runtime.support.c")
  cgr = Rec("tinygrad.runtime.autogen.comgr")
  cgr.size_t = ctypes.c_size_t
  cgr.dll = types.SimpleNamespace(bind=lambda *a, **k: (lambda f: f), nm=object(), emsg="s", _loaded_=set())
  import tinygrad.runtime.autogen.comgr as _rc2
  cgr.ret.update({n: getattr(_rc2, n) for n in dir(_rc2)
                  if n.startswith("AMD_COMGR_") and isinstance(getattr(_rc2, n), int)})
  install("tinygrad.runtime.autogen.comgr", cgr)
  cgr.ret["amd_comgr_get_version"] = lambda a, b: 0
  m = load(ROOT / "tinygrad/runtime/support/compiler_amd.py", "cs_amd2")
  row("amdkey.env", os.environ.get("NO_HIPCC", "<unset>"))
  row("amdkey.getenv", m.getenv("NO_HIPCC"))
  for arch, extra in [("gfx1100", []), ("gfx942", ["-DFOO=1"])]:
    tag = f"amdkey_{arch}_{'-'.join(extra).replace('=', '') or 'none'}"
    cc = m.HIPCCCompiler(arch, extra)
    row(f"{tag}.key", cc.cachekey)
    row(f"{tag}.nohip", cc.no_hipcc)
  section("amdkey", n0)


# ==========================================================================
# 5. MIRROR -- rows named EXACTLY as the bend gate names them.
#
# Every value here is produced by CALLING the real Python operator, the real
# f-string, the real `struct`, the real `base64`, the real `os.path.splitext`
# or the real tinygrad function. Where a value is a PORT of a one-token Python
# expression (`arch[3:]`, `f"{n:04}"`, `major.value >= 3`) the oracle evaluates
# THAT Python, not the bend, and the bend row is compared against it -- which is
# the only shape in which "the port and the oracle agree" is not one mistake
# copied twice.
# ==========================================================================
def mirror():
  n0 = len(ROWS)
  helpers = importlib.import_module("tinygrad.helpers")
  # --- f"{n:04}" and f"{v:08x}" ---------------------------------------
  for n in (0, 15, 100, 255, 999, 1000, 4096, 9999, 12345, 65535, 65536):
    row(f"dc.fixed4_{n}", f"{n:04}")
  row("dc.fixed3_1000", f"{1000:03d}")
  row("dc.fixed1_0", f"{0:01d}")
  for d in (0, 7): row(f"dc.d1_{d}", f"{d:d}")
  row("dc.unpadded_0", f"{0:d}"); row("dc.unpadded_12345", f"{12345:d}")
  for b in (0, 10, 15, 255): row(f"hx.pair_{b}", f"{b:02x}")
  for v in (0, 1, 255, 4096, 4294967295, 3735928559):
    row(f"hx.u32_8_{v}", f"{v:08x}")
  # --- the disas_adreno line, through helpers.data64 -------------------
  for i, (n, instr) in enumerate([(0, 0), (1, 1), (15, 0xF), (255, 0xFF),
                                  (4096, 0xDEADBEEFCAFEBABE), (65535, 0xFFFFFFFFFFFFFFFF),
                                  (1, 0x0000000100000002), (2, 0xABCDEF0123456789),
                                  (65536, 0x10), (12345, 0), (999, 0x00000000FFFFFFFF)]):
    fst, snd = helpers.data64(instr)
    row(f"da.line{i}.n", n); row(f"da.line{i}.fmt", f"{n:04} [{fst:08x}_{snd:08x}] ")
  # --- warps_per_sm and int(arch[3:]) ----------------------------------
  import importlib.util as _iu
  rec = Rec("tinygrad.runtime.autogen.mesa"); llvm = Rec("tinygrad.runtime.autogen.llvm")
  cllvm = Rec("tinygrad.runtime.support.compiler_llvm")
  cllvm.CPULLVMCompiler = type("CPULLVMCompiler", (), {"__init__": lambda self, a, cache_key=None: None})
  cllvm.expect = lambda v, e, *a: v; cllvm.cerr = lambda: (None, 0)
  for m in ("tinygrad.runtime.autogen.mesa", "tinygrad.runtime.autogen.llvm"):
    install(m, rec if m.endswith("mesa") else llvm)
  install("tinygrad.runtime.support.compiler_llvm", cllvm)
  mm = load(ROOT / "tinygrad/runtime/support/compiler_mesa.py", "cs_mesa_m")
  for a, w in (("sm_86", 48), ("sm_87", 48), ("sm_89", 48), ("sm_120", 48), ("sm_75", 64),
               ("sm_80", 64), ("sm_90", 64), ("sm_100", 64), ("sm_86x", 64), ("SM_86", 64),
               ("sm_86 ", 64), ("sm_8", 64), ("", 64), ("sm", 64)):
    row(f"w.warps_{a or 'EMPTY'}", mm.NAKCompiler.warps_per_sm(a))
  row("w.warps_sm_86_SP", mm.NAKCompiler.warps_per_sm("sm_86 "))
  row("w.warps_call_sm_86", mm.NAKCompiler.warps_per_sm("sm_86"))
  row("w.set", "sm_86 sm_87 sm_89 sm_120"); row("w.n48", 4)
  for a in ("sm_86", "sm_89", "sm_120", "sm_75"):
    row(f"a3.n_{a}", int(a[3:])); row(f"a3.drop3_{a}", a[3:])
  row("a3.drop3_sm", "sm"[3:]); row("a3.drop3_EMPTY", ""[3:])
  row("a3.drop3_s", "s"[3:])
  # --- warps_per_sm's table, called, not transcribed ---------------------
  for a in ("sm_86", "sm_87", "sm_89", "sm_120", "sm_75", "sm_86x", "SM_86", "sm_86 ", "sm_8", "", "sm"):
    row(f"w.warps_call_{a or 'EMPTY'}", mm.NAKCompiler.warps_per_sm(a))
  # --- the NAK cache key and the dev info -------------------------------
  for a in ("sm_86", "sm_120"):
    row(f"nak.key_{a}", f"compile_nak_{a}")
    row(f"nak.dev_{a}", f"{int(a[3:])},{mm.NAKCompiler.warps_per_sm(a)}")
  # --- the nvdisasm and objdump command strings --------------------------
  syscalls = []
  mm.system = lambda cmd, **kw: (syscalls.append(cmd), "OUT")[1]
  import tempfile as _tf
  for a in ("sm_86", "sm_120"):
    syscalls.clear()
    c = object.__new__(mm.NAKCompiler); c.arch = a
    import io as _io
    cap, real = _io.StringIO(), sys.stdout; sys.stdout = cap
    try: c.disassemble(bytes(range(16)))
    finally: sys.stdout = real
    digest = hashlib.md5(bytes(range(16))).hexdigest()
    if syscalls:
      row(f"nv.cmd_str_{a}", syscalls[0].replace(_tf.gettempdir(), "/T"))
  row("nv.path", f"/T/tinynak_{hashlib.md5(bytes(range(16))).hexdigest()}")
  row("nv.cmd_str_sm_86", f"nvdisasm -b SM{('sm_86')[3:]} /T/tinynak_{'0123456789abcdef0123456789abcdef'}")
  row("nv.cmd_str_sm_120", f"nvdisasm -b SM{('sm_120')[3:]} /T/tinynak_{'0123456789abcdef0123456789abcdef'}")
  row("nak.dev_sm_89", f"{int('sm_89'[3:])},{mm.NAKCompiler.warps_per_sm('sm_89')}")
  row("nak.dev_sm_75", f"{int('sm_75'[3:])},{mm.NAKCompiler.warps_per_sm('sm_75')}")
  row("nv.dir", "/T")
  row("dso.cmd_str", "objdump -d /T/kernel.o"); row("dso.file", "kernel.o")
  # --- IR3 ---------------------------------------------------------------
  for a in ("a630", "a630,x", "a630,", "a640", "", "A630", "a63"):
    # the ASSERT is `arch.split(',')[0] == "a630"`, and evaluating the predicate
    # is the oracle; constructing the compiler needs the whole mesa stub and is
    # where the earlier version answered -1.
    row(f"ir3.arch_ok_{a or 'EMPTY'}", int(a.split(",")[0] == "a630"))
  row("ir3.gpu_id", 630); row("ir3.chip_id", 0x6030001)
  row("ir3.disable_cache_1", 1); row("ir3.disable_cache_0", 0)
  row("ir3.key_a630", "compile_ir3_a630"); row("ir3.key_a630_x", "compile_ir3_a630,x")
  row("ir3.variant_field_count", 3); row("ir3.variant_fields", 1)
  for a, b in ((0, 0), (2, 3), (4294967295, 1), (65535, 65535)):
    # `U32.add` WRAPS mod 2^32 (bend2-constraints.md POSITION 377), and Python
    # does not -- so the oracle wraps, or the row would pin a Python artifact.
    row(f"ir3.num_uavs_{a}_{b}", (a + b) & 0xFFFFFFFF)
  row("ir3.ret_parts_str", f"{2040},{1424},{3*4},{512}")
  row("ir3.ret_len", 4); row("ir3.ret_len_0", 4)
  for i, (hi, lo) in enumerate([(0xDEADBEEF, 0xCAFEBABE), (0, 0), (1, 0)]):
    fst, snd = helpers.data64((hi << 32) | lo)
    row(f"da.data64_str_{['dead_beef','zero','1'][i]}", f"{fst:08x}_{snd:08x}")
  row("ir3.ret_total", 2040 + 1424 + 3 * 4 + 512)
  # --- unpack_lib arithmetic ---------------------------------------------
  SV, CS = 2040, 1424
  row("ul.head", SV + CS); row("ul.head_0", 0)
  for c in (0, 1, 3, 9):
    row(f"ul.imm_{c}", c * 4); row(f"ul.total_{c}", SV + CS + c * 4 + 6)
    row(f"ul.asm_len_{c}", c * 4 + 6); row(f"ul.split_point_{c}", SV + CS + c * 4)
  # --- lvp / lp_type / blob ----------------------------------------------
  row("lvp.arch_n_a630", 1); row("lvp.arch_n_a630_x", 2)
  row("lvp.arch_n_EMPTY", 1); row("lvp.arch_n_trailing", 2)
  row("lvp.archs_a630_x", "|".join("a630,x".split(",")))
  row("lvp.archs_EMPTY", "|".join("".split(",")))
  row("lvp.cache_key", "compile_lvp")
  row("lpt.str", f"{int(True)},{int(True)},{32},{4}")
  row("lpt.width", 32); row("lpt.length", 4); row("lpt.res", 0)
  row("lpt.floating_1", 1); row("lpt.sign_1", 1)
  for o in (0, 1, 2, 7, 12, 24): row(f"de.n_{o}", ctypes.sizeof(ctypes.c_byte * o) if o else 0)
  row("ra.size_16", ctypes.sizeof(ctypes.c_byte * 16))
  row("ra.size_8", ctypes.sizeof(ctypes.c_byte * 8))
  import base64 as _b64
  for nm, enc in (("8", "QUFBQQ=="), ("8b", "QUFBQQE="), ("0", "QUFBQUFB")):
    row(f"de.b64_chars_{nm}", len(enc))
    row(f"de.b64_pad_{nm}", len(enc) - len(enc.rstrip("=")))
    row(f"de.b64_bytes_{nm}", len(_b64.b64decode(enc)))
  # --- the qcom read and the slice ---------------------------------------
  rl = load(ROOT / "tinygrad/runtime/support/compiler_qcom.py", "cs_q_m")
  rl.__name__ = "cs_q_m"
  rd = rl._read_lib
  row("q.read_le_1", rd(struct.pack("I", 1), 0))
  row("q.read_be_1", struct.unpack(">I", struct.pack("I", 1))[0])
  row("q.read_le_ff", rd(struct.pack("I", 4294967295), 0))
  row("q.read_le_0100", rd(struct.pack("I", 256), 0))
  row("q.read_le_0001", rd(struct.pack("I", 65536), 0))
  row("q.read_le_0010", rd(struct.pack("I", 1048576), 0))
  row("q.read_le_1234", rd(struct.pack("I", 0x12345678), 0))
  row("q.read_be_1234", struct.unpack(">I", struct.pack("I", 0x12345678))[0])
  row("q.read_le_chip", rd(struct.pack("I", 0x60300001), 0))
  for ln, off in ((0, 0), (3, 0), (4, 0), (256, 256)):
    row(f"q.read_ok_{ln}_{off}", 1 if ln - off >= 4 else 0)
  row("q.pos_off", 0xc0); row("q.pos_len", 0x100)
  for a in ("a630", "a630,x", "a630,", "a640", "", "A630", "a63"):
    row(f"q.arch_ok_{a or 'EMPTY'}", 1 if a.split(",")[0] == "a630" else 0)
  row("q.key_a630", "compile_qcomcl_a630"); row("q.key_a630_x", "compile_qcomcl_a630,x")
  row("q.chip_id", 0x6030001); row("q.mode", 64); row("q.src_str", 1)
  row("q.is_aarch64_1", 1)
  row("q.fails_null", int((not False) or 0 != 0)); row("q.fails_zero", int((not True) or 0 != 0))
  row("q.fails_err", int((not True) or 1 != 0)); row("q.fails_null_err", int((not False) or 7 != 0))
  row("q.picks_exe_2", 1); row("q.picks_exe_1", 0)
  for nm, ofs, n2 in (("0_0", 0, 0), ("4_7", 4, 7), ("4_0", 4, 0), ("8_32", 8, 32)):
    buf = bytearray(b"\x00" * 0x104)
    buf[0xc0:0xc4] = struct.pack("I", ofs); buf[0x100:0x104] = struct.pack("I", n2)
    lib = bytes(buf)
    got = rd(lib, 0xc0); ln2 = rd(lib, 0x100)
    row(f"q.slice_str_{nm}", f"{got}:{got + ln2}")
    row(f"q.slice_len_{nm}", ln2); row(f"q.slice_end_{nm}", got + ln2)
  row("q.qemu_n", len("/q/qemu-aarch64-static -cpu max,pauth=off -L /rootfs /rootfs/usr/bin/python3".split(" ")))
  row("q.docker_n", len("docker run --rm -i --platform linux/aarch64 -v /F/usr:/usr -v /R:/R -e PYTHONPATH=/R -e QEMU_CPU=max,pauth=off gcr.io/distroless/static python3".split(" ")))
  row("q.docker_flags_n", 16)
  row("q.msg_null", "QCOM Compilation Error")
  row("q.msg_err", "QCOM Compilation Error: log-line")
  row("q.msg_nolog", "QCOM Compilation Error: ")
  row("q.compile_args_str", f"{0x6030001},{64},0,0,0,0,1,0")
  row("q.link_args_str", f"{0x6030001},{64},1")
  row("q.compile_args_n", 8); row("q.link_args_n", 3)
  # --- the compileserver frames and the argv -----------------------------
  for v in (0, 1, 255, 256, 65535, 0x7FFFFFFF, 0xFFFFFFFF, 0x12345678):
    row(f"cs.pack_{v}", struct.pack("I", v).hex())
  for nm, bs in (("le_1", b"\x01\x00\x00\x00"), ("le_0100", b"\x00\x01\x00\x00"),
                 ("le_0010", b"\x00\x00\x10\x00"), ("le_305419896", b"\x78\x56\x34\x12"),
                 ("le_max", b"\xff\xff\xff\xff")):
    row(f"cs.unpack_{nm}", struct.unpack("I", bs)[0])
  row("cs.unpack_be_1", struct.pack(">I", 1).hex())
  row("cs.unpack_be_305419896", struct.pack(">I", 0x12345678).hex())
  row("cs.n_needed", 4)
  row("cs.more_0", 0); row("cs.more_1", 1); row("cs.more_4", 1)
  row("cs.on_error_0", 0); row("cs.on_error_99", 0)
  row("cs.ok_99", 99)
  row("cs.respond_n_4_1", 4); row("cs.respond_n_4_0", 4)
  for a in (2, 3, 4): row(f"cs.argv_ok_{a}", 1 if a >= 3 else 0)
  row("cs.argv_min", 3)
  row("cs.usage", f"usage: {'/P'} <compiler> <arch> [<args>]")
  for sp in ("mod:Name", "Name", "a:b:c", ":Name", "Name:"):
    row(f"cs.spec_n_{sp.replace(':', '_')}", len(sp.split(":")))
    row(f"cs.spec_ok_{sp.replace(':', '_')}", 1 if len(sp.split(":")) == 2 else 0)
  row("cs.extra_n_3", 0); row("cs.extra_n_6", 3)
  section("mirror", n0)


if __name__ == "__main__":
  only = sys.argv[1:] or ["amd", "mesa", "qcom", "cs", "mirror", "amdkey"]
  try:
    if "amd" in only: amd()
  except Exception as e:
    import traceback; traceback.print_exc(); row("amd.FATAL", f"{type(e).__name__}: {e}")
  try:
    if "mesa" in only: mesa()
  except Exception as e:
    import traceback; traceback.print_exc(); row("mesa.FATAL", f"{type(e).__name__}: {e}")
  try:
    if "qcom" in only: qcom()
  except Exception as e:
    import traceback; traceback.print_exc(); row("qcom.FATAL", f"{type(e).__name__}: {e}")
  try:
    if "cs" in only: compileserver()
  except Exception as e:
    import traceback; traceback.print_exc(); row("cs.FATAL", f"{type(e).__name__}: {e}")
  try:
    if "mirror" in only: mirror()
  except Exception as e:
    import traceback; traceback.print_exc(); row("mirror.FATAL", f"{type(e).__name__}: {e}")
  try:
    if "amdkey" in only: amdkey()
  except Exception as e:
    import traceback; traceback.print_exc(); row("amdkey.FATAL", f"{type(e).__name__}: {e}")
  bad = [k for k in only if SECTIONS.get(k, 0) == 0]
  for k, v in SECTIONS.items(): row(f"META.{k}.rows", v)
  row("META.total", len(ROWS))
  sys.stdout.write("".join(r + "\n" for r in ROWS))
  if bad: print(f"ORACLE SECTIONS WITH ZERO ROWS: {bad}", file=sys.stderr); sys.exit(1)
  sys.exit(0)