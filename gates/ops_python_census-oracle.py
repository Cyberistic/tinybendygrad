#!/usr/bin/env python3
"""ops_python_census-oracle.py -- the CPython side of the `ops_python` census.

    .venv/bin/python gates/ops_python_census-oracle.py     # 84 rows + py-done=1

WHAT THIS READS. `tinygrad.runtime.ops_python` ITSELF -- `PythonRenderer`,
`PythonDevice`, `PythonCompiler`, `PythonProgram.__init__`, and the module-level
`wmma` -- driven by real `Target`s from `tinygrad.helpers` and real `TensorCore`s
from `tinygrad.renderer.tc`. NOTHING here re-implements an op_python rule: there is
no second `render.of`, no hand-written "expected ncores", no transcribed assertion
message. Where a row is about an ORDER rather than a value the order is READ OFF
CPython's OWN BYTECODE (`ctor_call`), and where a row is about a refusal the
refusal is the real `AssertionError` CPython raises (`msg`).

WHY AN INTERPRETER-LAYER ORACLE MUST DO EXACTLY THIS. The temptation in
`ops_python` is maximal, because the module has four small helpers that could each
be re-typed in twenty lines and each of those would agree with itself. `wmma`'s
two assertion strings are the clearest case: `f"{cc} must have {len(co[0])} elements
per thread, it has {len(x)}"` is a five-token f-string, and writing it here would
produce a green gate that compared my f-string to the port's f-string and checked
neither against a `TensorCore`. So `msg()` calls the real `wmma` with real
fragments, and the string it catches is the string ops_python built.

TWO PROCESS FACTS THE ROWS DEPEND ON, both measured and both load-bearing.

  * `EMULATE` is read through `getenv("EMULATE", "")`, which is `@functools.cache`d
    (helpers.py:162), so setting `os.environ` alone is a NO-OP after the first call.
    `emulate()` clears the cache on every set and every pop.
  * `IMAGE` is a `ContextVar` (helpers.py:238), not a `getenv`, so it is entered
    with `Context(IMAGE=...)` and never through the environment.

`TC_TABLES` IS THE ONE TRANSLATION IN THIS FILE, and it is the tid axis. The port
prints the id of the TABLE `get_amd`/`get_cuda`/`metal` picked; CPython has no such
id, it has the LIST the arch picked. So the oracle asks `which of tc.py's own
module-level tables IS this list` -- an identity question answered against the
module object, so a renamed table is a `SystemExit` rather than a silent 0. The
gate's `tid_axis_hold()` then checks that the port's nine `CORES_*` constants and
this dict are the same nine NAMES, so the translation is pinned on both sides
rather than trusted here.
"""
import base64
import dis
import inspect
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from unittest import mock                                                    # noqa: E402

import tinygrad.runtime.ops_python as op                                      # noqa: E402
from tinygrad.device import Compiled                                          # noqa: E402
from tinygrad.dtype import dtypes                                             # noqa: E402
from tinygrad.helpers import Context, Target, getenv                          # noqa: E402
from tinygrad.renderer import tc                                              # noqa: E402

# tc.py's module-level tensor-core TABLES, under tc.py's OWN names, in the order
# ops_python.bend numbers them. `tid_axis_hold()` cross-checks the key set against
# the port's `CORES_*` constant names and against `vars(tc)`.
TC_TABLES = {"metal": 1, "amd_rdna3": 2, "amd_cdna3": 3, "amd_cdna4": 4,
             "amd_rdna4": 5, "cuda_sm75": 6, "cuda_sm80": 7, "cuda_sm89": 8}


def renderer(device="", ren="", arch="", iface="", emulate="", image=0):
    """A real `PythonRenderer`, under the process constants `render.of` reads."""
    if emulate:
        os.environ["EMULATE"] = emulate
    else:
        os.environ.pop("EMULATE", None)
    getenv.cache_clear()
    with Context(IMAGE=image):
        return op.PythonRenderer(Target(device, ren, arch, iface))


def tid_of(cores):
    """The TABLE `get_amd`/`get_cuda`/`metal` returned, by IDENTITY.

    `get_amd` is a dict and `get_cuda` a ladder of module-level lists (tc.py:68,
    :98), so an arch answers with the SAME list object every call and identity is
    the question. The empty list is `get_cuda`'s own bottom arm (tc.py:68), and it
    is the port's `CORES_NONE`.
    """
    if not cores:
        return 0
    for nm, v in TC_TABLES.items():
        if cores is getattr(tc, nm, None):
            return v
    print(f"== REFUSED, NOT A VERDICT: ops_python_census-oracle: an unknown tensor-core "
          f"table reached the oracle: {cores!r}", file=sys.stderr)
    sys.exit(3)   # 3, and this file's OWN header at :36 already said what to do -- "so a
                  # renamed table is a `SystemExit` rather than a silent 0". A `SystemExit`
                  # of a STRING is 1, so the intent and the code disagreed and the code won.
                  # `main()` runs to completion or not at all, and `ops_python_census-gate.py
                  # :276` maps ANY non-zero rc of this oracle to a FAIL row, so the only
                  # reader this buys anything for is one reading `$?` directly. The site
                  # BELOW it is left alone and that is deliberate -- see the report: whether
                  # a stale upstream FIXTURE is a refusal or a wrong answer is not settled.


def refused(fn):
    """`True` when the call REFUSED, which is what ops_python.py:167 does with its
    bare `assert` -- the message is a deprecation notice and is not the subject."""
    try:
        fn()
        return False
    except AssertionError:
        return True


def lookup(cores, arg):
    """ops_python.py:35 verbatim -- `next(x for x in tensor_cores if (x.dims,
    x.dtype_in, x.threads) == arg[:3])`. StopIteration answers `None`, which is the
    refusal the port spells `None{}`."""
    try:
        return next(x for x in cores if (x.dims, x.dtype_in, x.threads) == arg)
    except StopIteration:
        return None


def msg(fn):
    """The REAL `wmma` assertion TEXT, or `NO-ASSERT` if it did not refuse."""
    try:
        fn()
        return "NO-ASSERT"
    except AssertionError as e:
        return str(e)


def frags(core):
    return core.frag_coords()


def wmma_call(core, inp, warp):
    return lambda: op.wmma([core], (core.dims, core.dtype_in, core.threads), inp, warp)


def sized(core, short=None, n=None):
    """A three-fragment input where every operand is its OWN element count, except
    operand `short`, which is given `n` instead -- the input that makes
    ops_python.py:37 refuse on that fragment."""
    f = frags(core)
    return [[0.0] * (n if j == short else len(f[j][0])) for j in range(3)]


# ---- PythonCompiler.compile, ops_python.py:160 ------------------------------
# `base64.b64decode(src)` under another name (ops_python.py:160). Decided by
# CALLING it on a fixture set, which is the fact the port's header says is
# "decidable without running the transform" -- and it is.
B64_FIXTURES = ("", "AA==", "AP8=", "AP9/", "AP9/AQ==", "QUJDRA==",
                "AAECAwQFBgc=", "dGhlIHF1aG5pcyBvZiBEaXRoIQ==")
B64_HOLDS = all(op.PythonCompiler().compile(s) == base64.b64decode(s) for s in B64_FIXTURES)

# ---- PythonRenderer.supported_dtypes, ops_python.py:182 ---------------------
# The real method, called on a real `PythonRenderer` instance built without
# `__init__` (it reads no instance state: `Renderer.supported_dtypes` is a set
# comprehension over `self` only through `super()`). `ge312` is which interpreter
# the row is about, and it is applied by patching `sys.version_info` -- the
# expression ops_python.py:182 actually evaluates.
_BLANK_RENDERER = op.PythonRenderer.__new__(op.PythonRenderer)


def keeps(dtype, ge312):
    with mock.patch.object(sys, "version_info", (3, 12) if ge312 else (3, 11)):
        return dtype in op.PythonRenderer.supported_dtypes(_BLANK_RENDERER)


# ---- PythonDevice.__init__, ops_python.py:186 -------------------------------
def ctor_call():
    """`(arity, [argument names])` of `PythonDevice.__init__`'s `super().__init__`,
    read off the function's OWN BYTECODE.

    ops_python.py:186 is `super().__init__(device, HostAllocator(self),
    [PythonRenderer], PythonProgram)`, and the census asks how many arguments there
    are and which position each object holds. Both are read here, so the gate
    measures CPython's compiled call rather than a transcription of it -- which is
    the same property `msg()` gives the assertion strings.
    """
    co = op.PythonDevice.__init__.__code__
    ins = list(dis.get_instructions(co))
    start = next(n for n, i in enumerate(ins) if i.opname == "LOAD_SUPER_ATTR")
    # the LAST `CALL` of the function, not the first: `HostAllocator(self)` is a
    # `CALL 1` of its own, and taking that one answers 1 for a four-argument ctor.
    stop = max(n for n, i in enumerate(ins) if i.opname == "CALL")
    # `self` appears TWICE -- the receiver and `HostAllocator(self)`'s argument --
    # so it is dropped and the remainder is deduplicated in ORDER. What is left is
    # the argument list, and its ORDER is the answer ops_python.py:186 states.
    seen = [n for n in dict.fromkeys(i.argval for i in ins[start + 1:stop]
                                     if i.opname in ("LOAD_GLOBAL", "LOAD_FAST")) if n != "self"]
    return ins[stop].argval, seen


CTOR_ARITY, CTOR_NAMES = ctor_call()
# The tag is the position among the arguments AFTER `device`; ops_python.bend's own
# comment says these are all constants so a row reading the fields would be reading
# the port's own numbering. `Compiled.__init__`'s signature is the other half of
# the check and is exported as CTOR_PARAMS.
CTOR_PARAMS = [p for p in inspect.signature(Compiled.__init__).parameters
               if p not in ("self", "device", "arch")]
CTOR_OBJECTS = {"allocator": "HostAllocator", "renderers": "PythonRenderer",
                "runtime": "PythonProgram"}
CTOR_TAG = {nm: CTOR_NAMES[1:].index(obj) for nm, obj in CTOR_OBJECTS.items()}
N_RENDERERS = len(op.PythonDevice("PYTHON").renderers)


def main():
    R = renderer
    m = tc.metal[0]
    mt = tc.metal[0].dims[0]
    found = lookup
    rows = []

    def u(k, v):
        rows.append(f"{k}={v}")

    def s(k, v):
        rows.append(f"{k}={v}")

    def b(k, v):
        rows.append(f"{k}={'True' if v else 'False'}")

    # ---- t_render : PythonRenderer.__init__ over the arch axis ---------------
    u("pyr_empty_device", R().target.device)
    s("pyr_empty_renderer", R().target.renderer)
    s("pyr_empty_arch", R().target.arch)
    u("pyr_empty_ncores", len(R().tensor_cores))
    s("pyr_metal_device", R(arch="METAL").target.device)
    s("pyr_metal_arch", R(arch="METAL").target.arch)
    u("pyr_metal_ncores", len(R(arch="METAL").tensor_cores))
    s("pyr_metal_lowp_device", R(device="2", ren="lowp", arch="METAL").target.device)
    for arch in ("gfx1100", "gfx1201", "gfx950"):
        s(f"pyr_{arch}_device", R(arch=arch).target.device)
        u(f"pyr_{arch}_ncores", len(R(arch=arch).tensor_cores))
    u("pyr_gfx942_ncores", len(R(arch="gfx942").tensor_cores))
    # the UNKNOWN gfx arm: tc.py:98's dict default, so gfx1101 is a full rdna3 set
    u("pyr_gfx1101_ncores", len(R(arch="gfx1101").tensor_cores))
    s("pyr_gfx1100_iface_arch", R(arch="gfx1100", iface="opencl").target.arch)
    s("pyr_gfx1100_iface_dev", R(arch="gfx1100", iface="opencl").target.device)
    u("pyr_cl_khr_ncores", len(R(ren="opencl", arch="gfx1100").tensor_cores))
    for arch in ("sm_80", "sm_75"):
        s(f"pyr_{arch}_device", R(arch=arch).target.device)
        u(f"pyr_{arch}_ncores", len(R(arch=arch).tensor_cores))
    u("pyr_sm_89_ncores", len(R(arch="sm_89").tensor_cores))
    u("pyr_sm_90_ncores", len(R(arch="sm_90").tensor_cores))
    # THE TABLE, NOT THE COUNT. Measured: amd_rdna3, amd_cdna3 and amd_rdna4 all
    # answer 4 cores, so a count reads the same for three of tc.py's tables.
    for arch in ("gfx1100", "gfx942", "gfx1101", "gfx950", "gfx1201", "gfx1200", "metal",
                 "sm_75", "sm_80", "sm_89", "sm_74"):
        u(f"pyr_{arch}_tid", tid_of(renderer(arch="METAL" if arch == "metal" else arch)
                                    .tensor_cores))
    u("pyr_sm_88_ncores", len(R(arch="sm_88").tensor_cores))
    u("pyr_sm_74_ncores", len(R(arch="sm_74").tensor_cores))
    u("pyr_sm_86_ncores", len(R(arch="sm_86").tensor_cores))
    s("pyr_nonsense_arch", R(arch="NOT_AN_ARCH").target.arch)
    s("pyr_nonsense_device", R(arch="NOT_AN_ARCH").target.device)
    u("pyr_nonsense_ncores", len(R(arch="NOT_AN_ARCH").tensor_cores))
    s("pyr_nonsense_renderer", R(arch="NOT_AN_ARCH").target.renderer)
    s("pyr_cuda_ptx_arch", R(ren="cuda", arch="sm_80").target.arch)
    u("pyr_cuda_ptx_ncores", len(R(ren="cuda", arch="sm_80").tensor_cores))
    s("pyr_interface_set_dev", R(arch="gfx1100", iface="opencl").target.device)
    s("pyr_image_empty_arch", R(image=1).target.arch)
    s("pyr_image_empty_device", R(image=1).target.device)
    s("pyr_image_gfx_arch", R(arch="gfx1100", image=1).target.arch)
    s("pyr_image_gfx_device", R(arch="gfx1100", image=1).target.device)
    b("pyr_emulate_bad", refused(lambda: R(arch="gfx1100", emulate="AMD")))
    b("pyr_emulate_bad_metal", refused(lambda: R(arch="METAL", emulate="CUDA")))
    b("pyr_emulate_bad_empty", refused(lambda: R(emulate="AMD_MFMA")))
    b("pyr_emulate_ok", not refused(lambda: R(arch="gfx1100")))

    # ---- t_compile : PythonCompiler.compile ---------------------------------
    b("pyc_is_b64decode", B64_HOLDS)
    b("pyc_refused", not B64_HOLDS)

    # ---- t_dtypes : PythonRenderer.supported_dtypes --------------------------
    b("pysd_keeps_f16_312", keeps(dtypes.half, True))
    b("pysd_drops_f16_311", not keeps(dtypes.half, False))
    for nm, d in (("bf16", dtypes.bfloat16), ("f32", dtypes.float32), ("bool", dtypes.bool),
                  ("i32", dtypes.int32), ("i64", dtypes.int64), ("f64", dtypes.float64),
                  ("u32", dtypes.uint32)):
        b(f"pysd_keeps_{nm}_311", keeps(d, False))

    # ---- t_wmma : the module-level `wmma` and tc.py's tables -----------------
    u("pywma_metal_ncores", len(tc.metal))
    u("pywma_metal_dims0", mt)
    u("pywma_metal_threads", m.threads)
    # two cores that agree on (dims, threads) and differ on dtype_in
    pair = [tc.metal[0], tc.metal[2]]
    a2 = (tc.metal[2].dims, tc.metal[2].dtype_in, tc.metal[2].threads)
    a0 = (tc.metal[0].dims, tc.metal[0].dtype_in, tc.metal[0].threads)
    # THE THREE `*_miss` ROWS ARE REFUSALS, not empty answers: ops_python.py:35 is
    # `next(...)` over a generator, and an exhausted generator is StopIteration.
    b("pywma_lookup_hit", found(pair, a2) is not None)
    b("pywma_lookup_first_hit", found(pair, a0) is not None)
    b("pywma_lookup_miss", found(pair, (m.dims, dtypes.int8, m.threads)) is None)
    b("pywma_lookup_threads_miss", found(pair, (m.dims, m.dtype_in, 16)) is None)
    b("pywma_lookup_empty", found([], a0) is None)
    # :35 "the first match is the layout": two cores from DIFFERENT tc.py tables
    # with the SAME triple (amd_rdna3[0] and amd_rdna4[0] are both (16,16,16) /
    # f16 / 32 threads), queried with the FIRST one's triple.
    first, other = tc.amd_rdna3[0], tc.amd_rdna4[0]
    if (first.dims, first.dtype_in, first.threads) != (other.dims, other.dtype_in, other.threads):
        sys.exit("amd_rdna3[0] and amd_rdna4[0] no longer share a triple, so this "
                 "row is no longer the FIRST-MATCH row it is named for")
    b("pywma_first_wins",
      found([first, other], (first.dims, first.dtype_in, first.threads)) is first)
    # THE ASSERTION TEXTS, built by ops_python.py:37 and :38 out of real fragments.
    for j, cc in enumerate("ABC"):
        s(f"pywma_short_msg_{cc}", msg(wmma_call(m, sized(m, short=j, n=1), 32)))
    wide = next(c for t in TC_TABLES for c in (getattr(tc, t) if t != "metal" else tc.metal)
                if len(frags(c)[0][0]) == 32)
    s("pywma_short_msg_32", msg(wmma_call(wide, sized(wide, short=0, n=2), wide.threads)))
    s("pywma_oddwarp_msg", msg(wmma_call(m, sized(m), 1)))

    # ---- t_dev : PythonDevice.__init__ --------------------------------------
    u("pyd_ctor_len", CTOR_ARITY)
    u("pyd_ctor_allocator", CTOR_TAG["allocator"])
    u("pyd_ctor_renderers", CTOR_TAG["renderers"])
    u("pyd_ctor_runtime", CTOR_TAG["runtime"])
    u("pyd_nrenderers", N_RENDERERS)

    rows.append("py-done=1")
    print("\n".join(rows))


if __name__ == "__main__":
    main()