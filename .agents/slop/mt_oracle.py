"""The CPython oracle for tinybendygrad/runtime/ops_metal.bend.

Nothing here is hand-transcribed. Two sources:

  * `ast` walks of ops_metal.py, which pull the objc selector out of every
    `mtl_msg(...)` / attribute call so the EXPECTED trace order is the file's
    own, not my reading of it.
  * LIVE calls into the real Metal runtime on this host: `MetalDevice()` opens,
    so `check_family`, the arch string and the storage mode are measured, not
    guessed.

Usage:  python3 .agents/slop/mt_oracle.py [rows]
"""
import ast, sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))

SRC = pathlib.Path(__file__).resolve().parents[2] / "tinygrad/runtime/ops_metal.py"
TREE = ast.parse(SRC.read_text())


def fn(name, cls=None):
  body = TREE.body
  if cls is not None:
    body = [n for n in TREE.body if isinstance(n, ast.ClassDef) and n.name == cls][0].body
  return [n for n in ast.walk(ast.Module(body=body, type_ignores=[]))
          if isinstance(n, ast.FunctionDef) and n.name == name][0]


def selector_of(call):
  """The selector string of an objc message: `mtl_msg(..., "sel", ...)` or
  `x.selector` / `x.selector:`. Returns None for anything else."""
  if isinstance(call, ast.Call) and getattr(call.func, "id", None) == "mtl_msg":
    for a in call.args:
      if isinstance(a, ast.Constant) and isinstance(a.value, str):
        return a.value
  f = call.func
  if isinstance(f, ast.Attribute):
    return f.attr
  return None


def walk_run():
  """`run` is a nested def with FOUR conditional arms, so the trace is NOT a
  straight line. One entry per statement: the arm it sits in and the objc
  selector of the msgSend it makes (a UOp `.store` is not a msgSend and is
  reported as `store`)."""
  r = fn("run", "MetalQueue")
  out = []
  for st in r.body:
    arm = "top"
    body = [st]
    if isinstance(st, ast.If):
      arm = ast.unparse(st.test)
      body = st.body
    for s in body:
      out.append((arm, call_of(s)))
  return out


def call_of(st):
  """The selector of the (possibly nested) objc message a statement makes.
  `h = cb.store(cbuf:=mtl_msg(...))` is one statement and ONE msgSend."""
  for n in ast.walk(st):
    if isinstance(n, ast.Call) and getattr(n.func, "id", None) == "mtl_msg":
      for a in n.args:
        if isinstance(a, ast.Constant) and isinstance(a.value, str):
          return a.value
  if isinstance(st, ast.Assign) and isinstance(st.value, ast.Call) and getattr(st.value.func, "attr", "") == "store":
    return f"store[{ast.unparse(st.value.func.value.args[0])}]"
  if isinstance(st, ast.Assign) and isinstance(st.value, ast.Call):
    return getattr(st.value.func, "id", None) or getattr(st.value.func, "attr", "?")
  return ast.unparse(st)[:40]


def walk_init():
  """MetalDevice.__init__, statement by statement, so the ORDER claim is the
  file's own and a dropped or moved line shows up as a moved row."""
  out = []
  for st in fn("__init__", "MetalDevice").body:
    out.append(ast.unparse(st) if isinstance(st, (ast.If, ast.FunctionDef)) else f"{ast.unparse(st)}"
               .split("=")[0].strip() + " = " + " ".join(
                 (getattr(c.func, "attr", None) or getattr(c.func, "id", "?"))
                 for c in ast.walk(st) if isinstance(c, ast.Call)))
  return out


def walk_submit():
  out = []
  for st in fn("submit", "MetalQueue").body:
    for n in ast.walk(st):
      if isinstance(n, ast.Call) and getattr(n.func, "id", None) == "run":
        out.append([ast.unparse(a) for a in n.args[1:]])
  return out


def sel_table():
  keep = {n.targets[0].id: ast.literal_eval(n.value) for n in TREE.body
          if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name)
          and n.targets[0].id in ("HANDLES", "SELECTORS", "REQUEST_TYPE_COMPILE")}
  return keep["HANDLES"], keep["SELECTORS"], keep["REQUEST_TYPE_COMPILE"]


HANDLES, SELECTORS, REQUEST_TYPE_COMPILE = sel_table()
BOTH = HANDLES + SELECTORS


def rows(live=True):
  from tinygrad.runtime.autogen import metal
  out = []
  A = out.append

  # --- the selector table, MEASURED by the same `.index` the source uses ------
  for i, n in enumerate(BOTH):
    A(f"sel_ix={BOTH.index(n)},{i},{n}")
  A(f"sel_n={len(BOTH)}")
  A(f"sel_handles={len(HANDLES)},{len(SELECTORS)}")
  A(f"req_compile={REQUEST_TYPE_COMPILE}")

  # --- the msgSend trace of `run`, arms tagged --------------------------------
  A(f"run_calls={len(walk_run())}")
  for i, (arm, sel) in enumerate(walk_run()):
    A(f"run_{i}={arm},{sel}")
  A("run_order=" + "|".join(s for _, s in walk_run()))
  A("run_sels=" + "|".join(str(BOTH.index(s)) if s in BOTH else "-1" for _, s in walk_run()))
  A("run_arms=" + "|".join(a for a, _ in walk_run()))

  # --- the submit tail: which (first, count, last) each `run` gets ------------
  A("submit_runs=" + " ".join(",".join(map(str, t)) for t in walk_submit()))

  # --- __init__ order --------------------------------------------------------
  for i, line in enumerate(walk_init()):
    A(f"init_{i}={line}")

  if not live:
    return out
  from tinygrad.runtime.ops_metal import MetalDevice
  d = MetalDevice()
  A(f"live_arch={d.arch}")
  A(f"live_device={d.device!r}")
  A(f"live_f16={d.has_copy_queue}")

  # check_family, verbatim from ops_metal.py:213
  def check_family(f):
    return next(filter(d.sysdevice.supportsFamily,
                       reversed([v for v, nm in metal.enum_MTLGPUFamily.items() if f in nm])), 0)
  A(f"live_apple={check_family('Apple')}")
  A(f"live_mac={check_family('Mac')}")
  A(f"live_arch2={metal.enum_MTLGPUFamily[check_family('Apple') or check_family('Mac')][12:]}")
  A(f"live_storagemode={metal.MTLResourceStorageModeShared}")
  A(f"live_concurrent={metal.enum_MTLIndirectCommandType[32]}")
  A(f"live_family8={metal.enum_MTLGPUFamily[1008]}")
  A(f"live_family8s={metal.enum_MTLGPUFamily[1008][12:]}")
  A(f"live_family_mac2={metal.enum_MTLGPUFamily[2002][12:]}")
  A(f"live_residency={d.residency.value is not None}")
  A(f"live_nsel={d.sels.size}")
  A(f"live_sels_nbytes={d.sels.nbytes}")

  # --- the compiler, ops_metal.py:55-63 --------------------------------------
  import platform
  macos_major = int(platform.mac_ver()[0].split('.')[0])
  A(f"live_macos_major={macos_major}")
  A(f"live_metal_version={metal_version(macos_major)}")
  A(f"live_params_tail={params('metal4.0').split('--driver-mode')[0]}")
  A(f"live_req={req_sizes(7)}")
  A(f"live_req2={req_sizes(1)}")
  A(f"live_ver={metal_version(25)},{metal_version(14)},{metal_version(13)},{metal_version(12)}")

  # --- ops_metal.py:111-113 -- the arg layout, MEASURED through layout_args ----
  from tinygrad.uop.ops import UOp
  from tinygrad.dtype import dtypes
  from tinygrad.runtime.support.hcq2 import layout_args
  addr = UOp.new_buffer("METAL", 64, dtypes.f32, 16).getaddr(None)
  A(f"live_getaddr_sz={addr.dtype.itemsize},{addr.dtype.name}")
  for name, ws, at in (("2buf1var", [addr, addr, UOp.const(1, dtypes.i32)], 0),
                       ("3buf", [addr, addr, addr], 0),
                       ("1buf2f16", [addr, UOp.const(1, dtypes.f16), UOp.const(1, dtypes.f16)], 256),
                       ("1buf", [addr], 0)):
    rws = layout_args(ws, at)
    A(f"live_layout_{name}=" + "|".join(f"{o}:{w.dtype.itemsize}" for o, w in rws))
    A(f"live_end_{name}=" + str(max([o + w.dtype.itemsize for o, w in rws], default=at + 8)))
  A(f"live_empty_end={max([], default=0 + 8)}")
  return out


def metal_version(macos_major):
  return "metal4.0" if macos_major >= 26 else "metal3.1" if macos_major >= 14 else "metal3.0" if macos_major >= 13 else "macos-metal2.0"


def params(mv):
  return f'-fno-fast-math -std={mv} --driver-mode=metal -x metal -fmodules-cache-path="CACHE" -fno-caret-diagnostics'


def req_sizes(n_src):
  from tinygrad.helpers import round_up
  src_padded = n_src + (round_up(n_src + 1, 4) - n_src)
  params_padded = len(params("metal3.1").encode()) + 1
  return f"{src_padded},{params_padded},{16 + src_padded + params_padded}"


if __name__ == "__main__":
  for r in rows(live=("--nol" not in sys.argv)):
    print(r)
