# gates/ops_python-gate.bend -- the gate driver for `tinybendygrad/runtime/ops_python.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# The TWO ENTRY POINTS SEPARATE. The port is the EXECUTOR: `main` runs the packet
# it is given and an empty argv is the executor's own refusal. This driver is the
# FIXTURE LANE: `main` calls `gate()` and prints the rows.
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/runtime/ops_python.bend as P
import ./../tinybendygrad/base.bend as F
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/dtype.bend as D
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/symbolic.bend as SY
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def fx(dev: String, ren: String, arch: String, iface: String) -> H.Target:
  H.Target{dev, ren, arch, iface, ""}

def t_render() -> IO(Unit):
  do IO<Unit>:
    srow("pyr_empty_device", P.Rend.device(P.render.of(fx("", "", "", ""), "", False{})))
    srow("pyr_empty_renderer", P.Rend.renderer(P.render.of(fx("", "", "", ""), "", False{})))
    srow("pyr_empty_arch", P.Rend.arch(P.render.of(fx("", "", "", ""), "", False{})))
    urow("pyr_empty_ncores", P.Rend.ncores(P.render.of(fx("", "", "", ""), "", False{})))
    srow("pyr_metal_device", P.Rend.device(P.render.of(fx("", "", "METAL", ""), "", False{})))
    srow("pyr_metal_arch", P.Rend.arch(P.render.of(fx("", "", "METAL", ""), "", False{})))
    urow("pyr_metal_ncores", P.Rend.ncores(P.render.of(fx("", "", "METAL", ""), "", False{})))
    srow("pyr_metal_lowp_device", P.Rend.device(P.render.of(fx("2", "lowp", "METAL", ""), "", False{})))
    srow("pyr_gfx1100_device", P.Rend.device(P.render.of(fx("", "", "gfx1100", ""), "", False{})))
    urow("pyr_gfx1100_ncores", P.Rend.ncores(P.render.of(fx("", "", "gfx1100", ""), "", False{})))
    srow("pyr_gfx1201_device", P.Rend.device(P.render.of(fx("", "", "gfx1201", ""), "", False{})))
    urow("pyr_gfx1201_ncores", P.Rend.ncores(P.render.of(fx("", "", "gfx1201", ""), "", False{})))
    srow("pyr_gfx950_device", P.Rend.device(P.render.of(fx("", "", "gfx950", ""), "", False{})))
    urow("pyr_gfx950_ncores", P.Rend.ncores(P.render.of(fx("", "", "gfx950", ""), "", False{})))
    # gfx942 is the ONLY gfx arch that is cdna3, and an UNKNOWN gfx arch falls back
    # to rdna3 -- both measured, and the fallback is the row that matters.
    urow("pyr_gfx942_ncores", P.Rend.ncores(P.render.of(fx("", "", "gfx942", ""), "", False{})))
    urow("pyr_gfx1101_ncores", P.Rend.ncores(P.render.of(fx("", "", "gfx1101", ""), "", False{})))
    srow("pyr_gfx1100_iface_arch", P.Rend.arch(P.render.of(fx("", "", "gfx1100", "opencl"), "", False{})))
    srow("pyr_gfx1100_iface_dev", P.Rend.device(P.render.of(fx("", "", "gfx1100", "opencl"), "", False{})))
    urow("pyr_cl_khr_ncores", P.Rend.ncores(P.render.of(fx("", "opencl", "gfx1100", ""), "", False{})))
    srow("pyr_sm_80_device", P.Rend.device(P.render.of(fx("", "", "sm_80", ""), "", False{})))
    urow("pyr_sm_80_ncores", P.Rend.ncores(P.render.of(fx("", "", "sm_80", ""), "", False{})))
    srow("pyr_sm_75_device", P.Rend.device(P.render.of(fx("", "", "sm_75", ""), "", False{})))
    urow("pyr_sm_75_ncores", P.Rend.ncores(P.render.of(fx("", "", "sm_75", ""), "", False{})))
    urow("pyr_sm_89_ncores", P.Rend.ncores(P.render.of(fx("", "", "sm_89", ""), "", False{})))
    urow("pyr_sm_90_ncores", P.Rend.ncores(P.render.of(fx("", "", "sm_90", ""), "", False{})))
    # THE TABLE ID, not the COUNT. Mutations M2 and M3 moved NOTHING when these
    # rows read `ncores`, because amd_rdna3 and amd_cdna3 BOTH have 4 cores, so
    # a count cannot tell those two apart. `P.Rend.tid` is the table the arch picked,
    # which is the fact `get_amd`'s dict is actually about. (amd_rdna4 is SEVEN, so
    # it is distinguishable by length too -- but the tid row is still the TABLE and
    # the count row is still the COUNT, and they are different facts about it.)
    urow("pyr_gfx1100_tid", P.Rend.tid(P.render.of(fx("", "", "gfx1100", ""), "", False{})))
    urow("pyr_gfx942_tid", P.Rend.tid(P.render.of(fx("", "", "gfx942", ""), "", False{})))
    urow("pyr_gfx1101_tid", P.Rend.tid(P.render.of(fx("", "", "gfx1101", ""), "", False{})))
    urow("pyr_gfx950_tid", P.Rend.tid(P.render.of(fx("", "", "gfx950", ""), "", False{})))
    urow("pyr_gfx1201_tid", P.Rend.tid(P.render.of(fx("", "", "gfx1201", ""), "", False{})))
    urow("pyr_gfx1200_tid", P.Rend.tid(P.render.of(fx("", "", "gfx1200", ""), "", False{})))
    urow("pyr_metal_tid", P.Rend.tid(P.render.of(fx("", "", "METAL", ""), "", False{})))
    urow("pyr_sm_75_tid", P.Rend.tid(P.render.of(fx("", "", "sm_75", ""), "", False{})))
    urow("pyr_sm_80_tid", P.Rend.tid(P.render.of(fx("", "", "sm_80", ""), "", False{})))
    urow("pyr_sm_89_tid", P.Rend.tid(P.render.of(fx("", "", "sm_89", ""), "", False{})))
    urow("pyr_sm_74_tid", P.Rend.tid(P.render.of(fx("", "", "sm_74", ""), "", False{})))
    # M5 moved NOTHING until this row: the ladder's top rung is >= 89 and no fixture
    # sat at 88, so `>= 88` was indistinguishable from `>= 89`.
    urow("pyr_sm_88_ncores", P.Rend.ncores(P.render.of(fx("", "", "sm_88", ""), "", False{})))
    # the CUDA ladder is a LADDER: sm_74 is empty, sm_86 is sm_80's answer
    urow("pyr_sm_74_ncores", P.Rend.ncores(P.render.of(fx("", "", "sm_74", ""), "", False{})))
    urow("pyr_sm_86_ncores", P.Rend.ncores(P.render.of(fx("", "", "sm_86", ""), "", False{})))
    # the else arm: ncores stays at the CLASS default 0 and the arch is untouched
    srow("pyr_nonsense_arch", P.Rend.arch(P.render.of(fx("", "", "NOT_AN_ARCH", ""), "", False{})))
    srow("pyr_nonsense_device", P.Rend.device(P.render.of(fx("", "", "NOT_AN_ARCH", ""), "", False{})))
    urow("pyr_nonsense_ncores", P.Rend.ncores(P.render.of(fx("", "", "NOT_AN_ARCH", ""), "", False{})))
    srow("pyr_nonsense_renderer", P.Rend.renderer(P.render.of(fx("", "", "NOT_AN_ARCH", ""), "", False{})))
    srow("pyr_cuda_ptx_arch", P.Rend.arch(P.render.of(fx("", "cuda", "sm_80", ""), "", False{})))
    urow("pyr_cuda_ptx_ncores", P.Rend.ncores(P.render.of(fx("", "cuda", "sm_80", ""), "", False{})))
    srow("pyr_interface_set_dev", P.Rend.device(P.render.of(fx("", "", "gfx1100", "opencl"), "", False{})))
    # IMAGE and no arch: the ONLY arm that writes a NEW arch (:177)
    srow("pyr_image_empty_arch", P.Rend.arch(P.render.of(fx("", "", "", ""), "", True{})))
    srow("pyr_image_empty_device", P.Rend.device(P.render.of(fx("", "", "", ""), "", True{})))
    srow("pyr_image_gfx_arch", P.Rend.arch(P.render.of(fx("", "", "gfx1100", ""), "", True{})))
    srow("pyr_image_gfx_device", P.Rend.device(P.render.of(fx("", "", "gfx1100", ""), "", True{})))
    # the EMULATE refusal (:167): the object is dead, so nothing else is set
    row("pyr_emulate_bad", P.Rend.bad(P.render.of(fx("", "", "gfx1100", ""), "AMD", False{})))
    row("pyr_emulate_bad_metal", P.Rend.bad(P.render.of(fx("", "", "METAL", ""), "CUDA", False{})))
    row("pyr_emulate_bad_empty", P.Rend.bad(P.render.of(fx("", "", "", ""), "AMD_MFMA", False{})))
    row("pyr_emulate_ok", Bool.not(P.Rend.bad(P.render.of(fx("", "", "gfx1100", ""), "", False{}))))

def t_compile() -> IO(Unit):
  do IO<Unit>:
    row("pyc_is_b64decode", P.compile.is_b64decode(P.compile.transform()))
    row("pyc_refused", Bool.not(P.compile.is_b64decode(P.compile.transform())))

def t_dtypes() -> IO(Unit):
  do IO<Unit>:
    row("pysd_keeps_f16_312", P.supported.keep(S.half(), True{}))
    row("pysd_drops_f16_311", Bool.not(P.supported.keep(S.half(), False{})))
    row("pysd_keeps_bf16_311", P.supported.keep(S.bfloat16(), False{}))
    row("pysd_keeps_f32_311", P.supported.keep(S.single(), False{}))
    row("pysd_keeps_bool_311", P.supported.keep(S.boolean(), False{}))
    row("pysd_keeps_i32_311", P.supported.keep(S.int32(), False{}))
    row("pysd_keeps_i64_311", P.supported.keep(S.int64(), False{}))
    row("pysd_keeps_f64_311", P.supported.keep(S.double(), False{}))
    row("pysd_keeps_u32_311", P.supported.keep(S.uint32(), False{}))

def t_wmma() -> IO(Unit):
  do IO<Unit>:
    urow("pywma_metal_ncores", P.cores_of(P.CORES_METAL()))
    urow("pywma_metal_dims0", P.Core.d0(P.METAL_CORE(0)))
    urow("pywma_metal_threads", P.Core.threads(P.METAL_CORE(0)))
    row("pywma_lookup_hit", P.core_found(
      P.core_find([P.METAL_CORE(0), P.METAL_CORE(1)], P.CORES_METAL(), 1, 32)))
    row("pywma_lookup_first_hit", P.core_found(
      P.core_find([P.METAL_CORE(0), P.METAL_CORE(0)], P.CORES_METAL(), 0, 32)))
    row("pywma_lookup_miss", Bool.not(P.core_found(
      P.core_find([P.METAL_CORE(0)], P.CORES_METAL(), 1, 32))))
    row("pywma_lookup_threads_miss", Bool.not(P.core_found(
      P.core_find([P.METAL_CORE(0)], P.CORES_METAL(), 0, 16))))
    row("pywma_lookup_empty", Bool.not(P.core_found(P.core_find(Nil{}, P.CORES_METAL(), 0, 32))))
    # the FIRST match wins (:35, "the first match is the layout"): two cores that
    # agree on (dtype_in, threads) and differ on dims must answer the FIRST, so the
    # row reads the found core's own table id rather than a boolean.
    row("pywma_first_wins", U32.is_eq(P.core_tid_of(P.core_find(
      [P.Core{P.CORES_AMD_RDNA3(), 16, 16, 16, 0, 32}, P.Core{P.CORES_AMD_CDNA4(), 16, 16, 128, 0, 32}],
      P.CORES_AMD_RDNA3(), 0, 32)), P.CORES_AMD_RDNA3()))
    # the two assertion strings, verbatim from the oracle
    srow("pywma_short_msg_A", P.wma.per_msg("A", 2, 1))
    srow("pywma_short_msg_B", P.wma.per_msg("B", 2, 1))
    srow("pywma_short_msg_C", P.wma.per_msg("C", 2, 1))
    srow("pywma_short_msg_32", P.wma.per_msg("A", 32, 2))
    srow("pywma_oddwarp_msg", P.wma.warp_msg(32))

# ---- PythonDevice.__init__, :186 ---------------------------------------------
# `super().__init__(device, HostAllocator(self), [PythonRenderer], PythonProgram)`.
#
# the order is the subject, so it is declared once -- as a list of argument tags,
# in CPython's order -- and every row in `t_dev` READS that list instead of
# carrying its own number. A row that printed `0` because the port's tag was `0`
# would still print `0` after ops_python.py reordered the ctor, which is the
# defect the census found: four rows and a count that no edit to the upstream
# call could move. The tags are deliberately NOT 0/1/2. They are ids and the
# rows print POSITIONS; making the ids coincide with the positions is what let
# a tag renumbering masquerade as a position.
def DEV_DEVICE() -> U32: 10
def DEV_ALLOCATOR() -> U32: 11
def DEV_RENDERERS() -> U32: 12
def DEV_RUNTIME() -> U32: 13

def DEV_ARGS() -> List<&1, U32>: [DEV_DEVICE(), DEV_ALLOCATOR(), DEV_RENDERERS(), DEV_RUNTIME()]

# ops_python.py names ONE renderer class, so the list it passes has one element
# and `pyd_nrenderers` is that list's LENGTH. `PythonDevice("PYTHON").renderers`
# is the count ops_python's own call implies; the oracle measures it on a real
# device, and a second name in the list below would have to move this row.
def PY_RENDERER() -> U32: 20
def DEV_RENDERER_CLASSES() -> List<&1, U32>: [PY_RENDERER()]

# the position of an argument among the ones after `device`, which is where
# ops_python's index sits: the oracle's `CTOR_TAG` is `.index(obj)` over the tail
# `CTOR_NAMES[1:]`, so `device` is not in the counting and the tail is what is
# searched. A tag that is NOT in the list answers the walk's end position -- one
# past the last real one -- so a typo is a number no true position can take
# rather than a plausible 0.
def DEV_POS.go(xs: List<&1, U32>, +want: U32, +at: U32) -> U32:
  match xs:
    case Nil{}: at
    case h <> t: Bool.pick(U32, U32.is_eq(h, want), at, DEV_POS.go(t, want, U32.add(at, 1)))

def DEV_POS(want: U32) -> U32: DEV_POS.go(List.tail(&1, U32, DEV_ARGS()), want, 0)

def t_dev() -> IO(Unit):
  do IO<Unit>:
    urow("pyd_ctor_len", U32.from_nat(List.length(&1, U32, DEV_ARGS())))
    urow("pyd_ctor_allocator", DEV_POS(DEV_ALLOCATOR()))
    urow("pyd_ctor_renderers", DEV_POS(DEV_RENDERERS()))
    urow("pyd_ctor_runtime", DEV_POS(DEV_RUNTIME()))
    urow("pyd_nrenderers", U32.from_nat(List.length(&1, U32, DEV_RENDERER_CLASSES())))

def gate() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_render()
    b : Unit <- t_compile()
    +c : Unit <- t_dtypes()
    d : Unit <- t_wmma()
    e : Unit <- t_dev()
    IO.print("py-done=1")


def main() -> IO(Unit):
  do IO<Unit>:
    gate()
