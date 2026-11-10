# gates/ops_qcom-gate.bend -- THE GATE DRIVER for `tinybendygrad/runtime/ops_qcom.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. THE PORT FILE CARRIES THE PORT AND
# THIS FILE CARRIES THE INSTRUMENT, AND THE TREE's OWN CONVENTION SAYS SO:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# THE ROWS ARE PURE CONSUMERS: THEY CALL THE PORT's DEFS AND DEFINE
# NOTHING THAT THE PORT NEEDS.

import Base
import ./../tinybendygrad/runtime/ops_qcom.bend as P
import ./../tinybendygrad/helpers.bend as H

def CP_REG_TO_MEM() -> U32: 62
def layout_args.of(+sizes: List<&2, U32>, base: U32) -> List<&2, U32>:
  P.layout_args.at(List.length(&2, U32, sizes), sizes, 0, base, Nil{})
# `pack_args` in reverse: the trace is the pad SEQUENCE, and a pad is emitted
# whenever the next offset is not where the cursor already is.
# --- the two offset rules, and why they are TWO ----------------------------
#
#   :228 (NIR)  tex_off, ibo_off, samp_off = 2048, 2048 + 0x40*tex_cnt, 2048 + 0x40*(tex_cnt + ibo_cnt)
#   :272 (CL)   ibo_off, tex_off, samp_off = 2048, 2048 + 0x40*ibo_cnt, 2048 + 0x40*tex_cnt + 0x40*ibo_cnt
#
# READ the lhs order. Each branch assigns `2048` to a DIFFERENT name -- NIR to
# `tex_off`, CL to `ibo_off` -- and gives the OTHER one the `0x40 * <the other
# count>` term. So the ONLY difference is which name gets the bare 2048 and
# which count scales the other. `pd.nir_tex_off` and `pd.cl_ibo_off` are both
# exactly `ALIGN_ZERO()`, and `qc_off_swap_ibo_0` (a blob with tex_cnt == 0)
# is the row that says so: a port that reads both branches as "the first one is
# 2048 + 0x40*n" answers False there.
def pd.nir_tex_off(+tex_cnt: U32) -> U32: P.ALIGN_ZERO()
# :237 `round_up(2048 + (tex_cnt + ibo_cnt) * 0x40 + len(self.samplers) * 4, 0x100)`.
# `len(self.samplers)` is `samp_cnt * 4` in the CL branch (`:257-259` emits four
# words per sampler) and `samp_cnt * 4` again in the NIR branch (`:225-226` emits
# FOUR words), so both branches agree and `samp_cnt` is the multiplier.
def pd.kernargs_alloc_size(+tex_cnt: U32, +ibo_cnt: U32, +samp_cnt: U32) -> U32:
  H.round_up_u32(U32.add(U32.add(P.ALIGN_ZERO(), U32.mul(U32.add(tex_cnt, ibo_cnt), P.TEX_BLOCK())),
                         U32.mul(samp_cnt, 4)), 256)
# ===========================================================================
# THE PARSED PROGRAM. `Pd` is `_parse_lib`'s output and nothing else; the six
# derived sizes are defs OVER it, because in Python they are six assignments
# after the `if self.NIR: ... else: self._parse_lib(obj.lib)`, and a reader
# wants to see that the derivation is downstream of BOTH branches.
# ===========================================================================
# ONE kernel-argument descriptor as :264 reads it: the buffer's byte offset
# (`offset_words * 4`) and its BUFTYPE.
# ONE constant descriptor as :278 builds it: (value, byte offset, size in
# bytes). `sz` is `2 << is32`, so it is 2 or 4 and never anything else.
def qwords(+us: List<&2, P.Qw>) -> U32: P.qwords.go(List.length(&2, P.Qw, us), 0, us)
def Pd.pvtmem(p: P.Pd) -> U32:
  match p:
    case P.Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: pvtmem
# --- 18: THE FOUR REFUSALS, :79, :118, :120, :332 -----------------------
# Every one of these is a TRUNCATION, not a flag: `Tr.emit` records nothing
# once `refused` is set, so `qc_rf_res_traces=0` is the claim -- nothing at
# all is written once the refusal fires. `qc_rf_dim_hugels` is the fixture
# that separates the TWO `any`s of :119: a local size over 1024 with a total
# UNDER 65536 is ACCEPTED, and a "one dimension" transcription would refuse it.
def Tr.refused(t: P.Tr) -> Bool:
  match t:
    case P.Tr{calls, refused}: refused
def rf.gpu_lt73(+g0: U32, +g1: U32) -> Bool: Bool.not(P.rf.gpu_ge73(g0, g1))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def seen(t: P.Tr) -> U32: U32.from_nat(List.length(&2, P.Call, P.Tr.calls(t)))
def exec.of(+max_threads: U32, +gs: List<&2, U32>, +ls: List<&2, U32>, samp_cnt: U32,
            tex_cnt: U32, ibo_cnt: U32, nir: Bool, refused: Bool) -> P.Tr:
  P.exec.of.at(P.rf.resources(max_threads, P.ls0(ls), P.ls1(ls), P.ls2(ls)), P.rf.dims(gs, ls),
             refused, samp_cnt, tex_cnt, ibo_cnt, nir, P.Tr.of())
# :192 `self._cache_flush(write_back=True, invalidate=False, sync=False,
# memsync=False)` -- write_back ONLY.
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def t_refuse() -> IO(Unit):
  do IO<Unit>:
    +r1 : P.Tr <- IO.pure(P.Tr, exec.of(63, [16, 1, 1], [64, 1, 1], 0, 0, 0, False{}, False{}))
    +r2 : P.Tr <- IO.pure(P.Tr, exec.of(256, [64, 1, 1], [2048, 1, 1], 0, 0, 0, False{}, False{}))
    +r3 : P.Tr <- IO.pure(P.Tr, exec.of(256, [1, 1, 1], [8, 1, 1], 0, 0, 0, False{}, False{}))
    urow("qc_rf_res_traces", seen(r1))
    urow("qc_rf_dim_traces", seen(r2))
    urow("qc_rf_ok_traces", seen(r3))
    row("qc_rf_res_refused", Tr.refused(r1))
    row("qc_rf_dim_refused", Tr.refused(r2))
    row("qc_rf_ok_not_refused", Bool.not(Tr.refused(r3)))
    row("qc_rf_res_pred", P.rf.resources(63, 64, 1, 1))
    row("qc_rf_res_ok", Bool.not(P.rf.resources(256, 8, 1, 1)))
    row("qc_rf_res_1024", Bool.not(P.rf.resources(1024, 1024, 1, 1)))
    row("qc_rf_res_over", P.rf.resources(1024, 1025, 1, 1))
    row("qc_rf_res_3d", P.rf.resources(1024, 64, 64, 64))
    row("qc_rf_res_3d_ok", Bool.not(P.rf.resources(1024, 8, 8, 8)))
    row("qc_rf_dim_total", P.rf.dims([64, 1, 1], [2048, 1, 1]))
    row("qc_rf_dim_total_65536", P.rf.dims([65536, 1, 1], [2, 1, 1]))
    row("qc_rf_dim_total_ok", Bool.not(P.rf.dims([1, 1, 1], [2048, 1, 1])))
    row("qc_rf_dim_local", P.rf.dims([65536, 1, 1], [2, 1, 1]))
    row("qc_rf_dim_local_none", P.rf.dims([65536, 1, 1], [1, 1, 1]))
    row("qc_rf_dim_local_ok", Bool.not(P.rf.dims([1, 1, 1], [1, 1, 1])))
    row("qc_rf_dim_z", P.rf.dims([1, 1, 1], [1, 1, 70000]))
    row("qc_rf_dim_edge", P.rf.dims([65535, 1, 1], [1, 1, 1]))
    # :74 and :332 are the SAME PREDICATE with opposite senses.
    row("qc_rf_gpu_a730", P.rf.gpu_ge73(7, 3))
    row("qc_rf_gpu_a720", Bool.not(P.rf.gpu_ge73(7, 2)))
    row("qc_rf_gpu_a650", Bool.not(P.rf.gpu_ge73(6, 5)))
    row("qc_rf_gpu_a640", Bool.not(P.rf.gpu_ge73(6, 4)))
    row("qc_rf_gpu_a800", P.rf.gpu_ge73(8, 0))
    row("qc_rf_gpu_a612", Bool.not(P.rf.gpu_ge73(6, 1)))
    row("qc_rf_sig_a650", rf.gpu_lt73(6, 5))
    row("qc_rf_sig_a730", Bool.not(rf.gpu_lt73(7, 3)))
    # :79 is DEAD on this backend and the row says so rather than pretending
    # the arm is live: :332 already refused every gpu_id the arm guards.
    row("qc_rf_event7_unreachable", Bool.not(rf.gpu_lt73(7, 3)))
# --- 19: `submit` -- the ioctl command word, :202-203 -------------------
# `(idir << 30) | (sizeof(struct_t) << 16) | (base << 8) | nr`. All four
# fields come out of `kgsl.IOCTL_KGSL_GPU_COMMAND.args` and `ctypes.sizeof`,
# and each has its own row because a wrong shift is a wrong ioctl and the
# four shifts do not commute.
#    the cache is a MAP, so `cache[key] = ...` is an ASSIGNMENT and re-storing
# a key does not grow the dict. `ce.put` is that assignment and the six
# calls below go through it -- `qc_ck_len` is the row that says four programs
# occupy four slots, not six.
def Tr.kinds(+cs: List<&2, P.Call>) -> List<&2, U32>:
  P.Tr.kinds.go(List.length(&2, P.Call, cs), cs, Nil{})
def Ce.t(c: P.Ce) -> P.Tr:
  match c:
    case P.Ce{key, pd, buf, t}: t
# ===========================================================================
# THE CACHE ITSELF. A list of entries and a LINEAR scan, because Bend has no
# hash map and because the honest question -- "does a MISS happen?" -- does not
# care about the lookup's cost. `ce.find` answers the FIRST match and there is
# no eviction, so first is also last.
# ===========================================================================
# the index of the FIRST entry whose key matches, or NO_ENTRY. The index is
# carried as a Nat because `List.get` wants one, and `at` is the answer so far
# so a match SHORT-CIRCUITS without a second scan.
def Tr.count(k: U32, +cs: List<&2, P.Call>) -> U32:
  P.Tr.count.go(List.length(&2, P.Call, cs), k, cs, 0)
def qreg.of(r: String, +vs: List<&2, P.Fv>) -> U32:
  P.qreg.of.go2(List.length(&2, P.Fv, vs), 0, r, vs)
# the bool form, so the `type(v) is bool` discriminator is not a call-site
# decision: `qreg.flag("a6xx_sp_cs_config", "ENABLED")`.
# `flags` is indexed by the ISSUE order and `at` is the flag's position in
# Python's PARAMETER order, so the fold and the flag list are in different
# orders and the mapping is `ISSUE_AT`. `qc_flush_order_barrier` fails if that
# mapping is the identity.
def tr.seq(+steps: List<&2, P.Tr>) -> List<&2, P.Call>:
  P.tr.seq.go(List.length(&2, P.Tr, steps), steps, Nil{})
# ===========================================================================
# STAGE 3 -- `QCOMComputeQueue` (:55-204) and `QCOMDevice.__init__` (:314-345).
#
# THE TRACE IS THE PORT. Every call below is either an argument BUILDER (pure,
# and the gate checks it) or a `Tr.emit` (and the gate checks the order). There
# is no third kind, so a refusal needs no guard of its own: `Tr.emit` records
# nothing once `refused` is set, and the refusal shows up as a TRUNCATED trace.
#
# WHAT the trace deliberately does not carry: the argument VALUES. `self.reg(R,
# qreg.a6xx_sp_cs_ndrange_0(...), 256, 0, ...)` passes thirteen words and eleven
# of them are computed register fields. This file records the REGISTER and the
# COUNT; the register VALUE is `qreg.of(...)`, which the stage-1 rows check
# directly against `_qreg_exec` for nine call sites. What nothing checks is that
# the RIGHT `qreg` call is paired with the RIGHT register in `exec` -- that is
# blind spot 1 below, and it is the biggest one.
# ===========================================================================
def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", String.join(P.ush(xs, ",", Nil{}), ",")]))
def ce.put(+e: P.Ce, +es: List<&2, P.Ce>) -> List<&2, P.Ce>:
  P.ce.put.at(U32.is_eq(P.ce.find(P.Ce.key(e), es), P.NO_ENTRY()), e, es)
def qcom.npad(+nbytes: U32) -> U32: U32.sub(P.qcom.pad_len(nbytes), nbytes)
# :290 `UOp.placeholder((len(image),), dtypes.u8, next(UOp.unique_num), device=devs)`
# -- the buffer is as long as the PADDED image and lands on `devs`.
def ce.len(+es: List<&2, P.Ce>) -> U32: U32.from_nat(List.length(&2, P.Ce, es))
def Ck.ndevs(c: P.Ck) -> U32:
  match c:
    case P.Ck{hash, ndevs, devs}: ndevs
def qcom.get(+hash: U32, +devs: List<&2, U32>, +name_len: U32, +bs: List<&2, U32>,
             +next_num: U32, +es: List<&2, P.Ce>) -> P.Ce:
  Bool.pick(P.Ce, U32.is_eq(P.ce.find(P.Ck.of(hash, devs), es), P.NO_ENTRY()),
    P.qcom.build(hash, devs, name_len, bs, next_num, es),
    P.qcom.hit(P.Ck.of(hash, devs), es))
def LIB_0() -> List<&2, U32>:
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 1, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 64, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 160, 1,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 24, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 1, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 33, 0, 0, 0, 25, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 48, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 24, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  2, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 1, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,]
def t_cache() -> IO(Unit):
  do IO<Unit>:
    +es0 : List<&2, P.Ce> <- IO.pure(List<&2, P.Ce>, Nil{})
    +a1 : P.Ce <- IO.pure(P.Ce, qcom.get(100, [1], 8, LIB_0(), 0, es0))
    +es1 : List<&2, P.Ce> <- IO.pure(List<&2, P.Ce>, ce.put(a1, es0))
    +a2 : P.Ce <- IO.pure(P.Ce, qcom.get(100, [1], 8, LIB_0(), 1, es1))
    +es2 : List<&2, P.Ce> <- IO.pure(List<&2, P.Ce>, ce.put(a2, es1))
    +a3 : P.Ce <- IO.pure(P.Ce, qcom.get(200, [1], 8, LIB_0(), 2, es2))
    +es3 : List<&2, P.Ce> <- IO.pure(List<&2, P.Ce>, ce.put(a3, es2))
    # the negative case: A was inserted FIRST and B second, and A is still there
    +a4 : P.Ce <- IO.pure(P.Ce, qcom.get(100, [1], 8, LIB_0(), 3, es3))
    +es4 : List<&2, P.Ce> <- IO.pure(List<&2, P.Ce>, ce.put(a4, es3))
    # the other negative: same hash, different devs -> a MISS
    +a5 : P.Ce <- IO.pure(P.Ce, qcom.get(100, [2], 8, LIB_0(), 4, es4))
    +es5 : List<&2, P.Ce> <- IO.pure(List<&2, P.Ce>, ce.put(a5, es4))
    +a6 : P.Ce <- IO.pure(P.Ce, qcom.get(100, [1, 2], 8, LIB_0(), 5, es5))
    +es6 : List<&2, P.Ce> <- IO.pure(List<&2, P.Ce>, ce.put(a6, es5))
    +seq : List<&2, P.Call> <- IO.pure(List<&2, P.Call>, tr.seq([Ce.t(a1), Ce.t(a2), Ce.t(a3), Ce.t(a4), Ce.t(a5), Ce.t(a6)]))
    lrow("qc_ck_ckinds", Tr.kinds(seq))
    urow("qc_ck_nmint", Tr.count(P.CALL_MINT(), seq))
    urow("qc_ck_npatch", Tr.count(P.CALL_PATCH(), seq))
    urow("qc_ck_nhit", Tr.count(P.CALL_HIT(), seq))
    urow("qc_ck_nparse", Tr.count(P.CALL_PARSE(), seq))
    urow("qc_ck_len", ce.len(es6))
    urow("qc_ck_len_after_three", ce.len(es3))
    urow("qc_ck_len_grew_on_hit", ce.len(es4))
    row("qc_ck_second_is_hit", U32.is_eq(Tr.count(P.CALL_PARSE(), P.Tr.calls(Ce.t(a2))), 0))
    row("qc_ck_second_is_one_hit", U32.is_eq(Tr.count(P.CALL_HIT(), P.Tr.calls(Ce.t(a2))), 1))
    row("qc_ck_older_survives", U32.is_eq(Tr.count(P.CALL_PARSE(), P.Tr.calls(Ce.t(a4))), 0))
    row("qc_ck_older_is_hit", U32.is_eq(Tr.count(P.CALL_HIT(), P.Tr.calls(Ce.t(a4))), 1))
    row("qc_ck_older_same_buf", U32.is_eq(P.Ce.buf(a4), P.Ce.buf(a1)))
    row("qc_ck_devs_splits", U32.is_eq(Tr.count(P.CALL_PARSE(), P.Tr.calls(Ce.t(a5))), 1))
    row("qc_ck_devs_splits_pair", U32.is_eq(Tr.count(P.CALL_PARSE(), P.Tr.calls(Ce.t(a6))), 1))
    row("qc_ck_key_eq", P.Ck.eq(P.Ck.of(100, [1]), P.Ck.of(100, [1])))
    row("qc_ck_key_ne_hash", Bool.not(P.Ck.eq(P.Ck.of(100, [1]), P.Ck.of(200, [1]))))
    row("qc_ck_key_ne_devs", Bool.not(P.Ck.eq(P.Ck.of(100, [1]), P.Ck.of(100, [2]))))
    row("qc_ck_key_ne_len", Bool.not(P.Ck.eq(P.Ck.of(100, [1]), P.Ck.of(100, [1, 2]))))
    urow("qc_ck_key_ndevs", Ck.ndevs(P.Ck.of(100, [1, 2])))
    urow("qc_ck_miss_no_entry", P.ce.find(P.Ck.of(999, [7]), es3))
    row("qc_ck_miss_is_absent", U32.is_eq(P.ce.find(P.Ck.of(999, [7]), es3), P.NO_ENTRY()))
    # the image padding, :289 -- `ljust(round_up(len(image), 4), b"\x00")`
    urow("qc_ck_pad0", P.qcom.pad_len(0))
    urow("qc_ck_pad1", P.qcom.pad_len(1))
    urow("qc_ck_pad3", P.qcom.pad_len(3))
    urow("qc_ck_pad4", P.qcom.pad_len(4))
    urow("qc_ck_pad5", P.qcom.pad_len(5))
    urow("qc_ck_pad4096", P.qcom.pad_len(4096))
    urow("qc_ck_npad3", qcom.npad(3))
    urow("qc_ck_npad4", qcom.npad(4))
    # the buffer is as long as the PADDED image and its id is `next_num`, and
    # the three calls run in the order PARSE, MINT, PATCH.
    lrow("qc_ck_first_trace", Tr.kinds(P.Tr.calls(Ce.t(a1))))
    urow("qc_ck_first_buf", P.Ce.buf(a1))
    urow("qc_ck_second_buf", P.Ce.buf(a2))
    urow("qc_ck_third_buf", P.Ce.buf(a3))
    urow("qc_ck_parsed_imgsize", P.Pd.image_size(P.Ce.pd(a1)))
    urow("qc_ck_patched_len", P.qcom.pad_len(P.Pd.image_size(P.Ce.pd(a1))))
# --- 14: THE FIXED OFFSETS, one row each, :241-283 -----------------------
# Every constant of `_parse_lib` gets a row because a wrong one moves the
# WHOLE parse and every other row in this section moves with it -- which is
# why these are the rows a mutation of a constant hits, and why there is one
# per constant rather than a single "the offsets are right" boolean.
# :234 `round_up(next_power2(round_up(pvtmem, 512)) * 128 * 16, 0x1000)`. The
# 64-bit product IS in this expression and it is WALL 4 below: `next_power2` of
# a value already rounded to 512 is at most 2^31, and `* 128 * 16` is `<< 11`,
# so the product is up to 2^42. The port carries it as a U32 and the row that
# would notice is `qc_pd_stack_*` -- every oracle fixture here has a
# next_power2 of at most 2^12, so the product fits. That is the blind spot, and
# it is written down rather than papered over.
def pd.hw_stack_offset(+pvtmem: U32) -> U32:
  H.round_up_u32(U32.shln(H.next_power2(H.round_up_u32(pvtmem, 512)), 11n), 4096)
# :235 `max(1, (shmem - 1) // 1024)`. TWO things are load-bearing here. The
# `max(1, ...)` says a program with NO shared memory still declares one unit,
# and `shared_size` is written into `a6xx_sp_cs_cntl_1` at :147. AND the
# subtraction UNDERFLOWS for `shmem == 0`: Python's `-1 // 1024` is `-1`, which
# U32 cannot hold, so a U32 fold would answer 4194303 -- 4096x too many shared
# units. The `shmem == 0` arm is that underflow, spelled. Fixture `pl_1` has
# `shmem == 0` precisely so the row can see it.
def KGSL_CONTEXT_PREEMPT_STYLE_FINEGRAIN() -> U32: 2
def Pd.fregs(p: P.Pd) -> U32:
  match p:
    case P.Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: fregs
# --- 1: the BUFTYPE table, :20, BOTH directions ---------------------------
# the FORWARD row asks the table for a name; the REVERSE row asks the table
# for the value of a name. `qc_buftype_unknown` is Python's `typ not in {1,2}`
# arriving as a lookup miss, which is the :268 filter's whole behaviour for a
# type this port has never heard of.
def const.flat(+cs: List<&2, P.Ci>) -> String:
  P.const.flat.go(List.length(&2, P.Ci, cs), cs, Nil{})
# ===========================================================================
# `_parse_lib` AS ONE DEF. The order of the reads is Python's and it matters:
# `image_offset` is read at :242 and BOUNDS the constant walk at :276, so a
# port that walks the constants before reading it has no bound.
# ===========================================================================
def desc.buf_offs(+bs: List<&2, P.Bi>) -> List<&2, U32>:
  P.desc.buf_offs.go(List.length(&2, P.Bi, bs), bs, Nil{})
# --- 15: THE `cmd`/`reg` HEADERS, :49-59 and :57/:59 ---------------------
# `q.cmd`/`q.reg` record the OPCODE or the REGISTER in the trace and the COUNT
# goes into the header, which is a separate pure builder. Every header
# ops_qcom.py issues has a row, and the count row next to it says the WORDS.
def pd.nir_samp_off(+tex_cnt: U32, +ibo_cnt: U32) -> U32:
  U32.add(U32.add(P.ALIGN_ZERO(), U32.mul(tex_cnt, P.TEX_BLOCK())), U32.mul(ibo_cnt, P.TEX_BLOCK()))
def pd.shared_size(+shmem: U32) -> U32:
  Bool.pick(U32, U32.is_eq(P.pd.shared_unit(shmem), 0), 1, P.pd.shared_unit(shmem))
# :236 `min(1024, ((384 * 32) // (max(1, (fregs + round_up(hregs, 2) // 2)) * 128)) * 128)`.
# The INNER `max(1, ...)` is what keeps a register-free program from dividing
# by zero, and it is the row `qc_pd_maxthreads_den` that says so.
def Pd.tex_cnt(p: P.Pd) -> U32:
  match p:
    case P.Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: tex_cnt
# --- 9: the `cmd`/`reg` word count, :57 and :59 ---------------------------
# `x.dtype.itemsize // 4 if isinstance(x, UOp) else 1`. A `dtypes.u8`
# buffer is itemsize 1 and so counts ZERO words, not one -- `qc_qw_u8_u32`
# is 1, not 2, and that is the row that says so. A bare int is one word
# whatever its magnitude.
def Pd.bins(p: P.Pd) -> List<&2, P.Bi>:
  match p:
    case P.Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: bins
def pd.pvtmem_size_total(+per_item: U32) -> U32: U32.mul(U32.mul(per_item, 128), 2)
# :234 `round_up(next_power2(round_up(pvtmem, 512)) * 128 * 16, 0x1000)`. The
# 64-bit product IS in this expression and it is WALL 4 below: `next_power2` of
# a value already rounded to 512 is at most 2^31, and `* 128 * 16` is `<< 11`,
# so the product is up to 2^42. The port carries it as a U32 and the row that
# would notice is `qc_pd_stack_*` -- every oracle fixture here has a
# next_power2 of at most 2^12, so the product fits. That is the blind spot, and
# it is written down rather than papered over.
def pd.max_threads(+fregs: U32, +hregs: U32) -> U32:
  Bool.pick(U32, U32.is_gt(P.pd.thread_cap(fregs, hregs), 1024), 1024, P.pd.thread_cap(fregs, hregs))
# :237 `round_up(2048 + (tex_cnt + ibo_cnt) * 0x40 + len(self.samplers) * 4, 0x100)`.
# `len(self.samplers)` is `samp_cnt * 4` in the CL branch (`:257-259` emits four
# words per sampler) and `samp_cnt * 4` again in the NIR branch (`:225-226` emits
# FOUR words), so both branches agree and `samp_cnt` is the multiplier.
def LIB_5() -> List<&2, U32>:
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 1, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 64, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 160, 1,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 1, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 48, 0, 0, 0, 160, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 1, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 64, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0,
  64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,]
def Pd.hregs(p: P.Pd) -> U32:
  match p:
    case P.Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: hregs
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
# --- 1: the BUFTYPE table, :20, BOTH directions ---------------------------
# the FORWARD row asks the table for a name; the REVERSE row asks the table
# for the value of a name. `qc_buftype_unknown` is Python's `typ not in {1,2}`
# arriving as a lookup miss, which is the :268 filter's whole behaviour for a
# type this port has never heard of.
def Pd.consts(p: P.Pd) -> List<&2, P.Ci>:
  match p:
    case P.Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: consts
def Pd.shmem(p: P.Pd) -> U32:
  match p:
    case P.Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: shmem
def pd.cl_tex_off(+ibo_cnt: U32) -> U32: U32.add(P.ALIGN_ZERO(), U32.mul(ibo_cnt, P.TEX_BLOCK()))
def pd.nir_ibo_off(+tex_cnt: U32) -> U32: U32.add(P.ALIGN_ZERO(), U32.mul(tex_cnt, P.TEX_BLOCK()))
def Pd.ibo_cnt(p: P.Pd) -> U32:
  match p:
    case P.Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: ibo_cnt
def Pd.samp_cnt(p: P.Pd) -> U32:
  match p:
    case P.Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: samp_cnt
def pd.cl_ibo_off(+ibo_cnt: U32) -> U32: P.ALIGN_ZERO()
def Pd.bdoff(p: P.Pd) -> U32:
  match p:
    case P.Pd{image_size, image_offset, image_desc_off, prg_offset, brnchstck, pvtmem, shmem, samp_cnt,
            samp_in_file, tex_cnt, ibo_cnt, fregs, hregs, bdoff, bins, consts}: bdoff
def pd.cl_samp_off(+tex_cnt: U32, +ibo_cnt: U32) -> U32:
  U32.add(U32.add(P.ALIGN_ZERO(), U32.mul(tex_cnt, P.TEX_BLOCK())), U32.mul(ibo_cnt, P.TEX_BLOCK()))
# ===========================================================================
# THE BUFFER-DESCRIPTOR WALK, :262-268.
#
#     bdoff = round_up(image_desc_off + 0x158 + len(self.name), 4) + 8 * samp_cnt_in_file
#     while bdoff + 32 <= len(lib):
#       length, _, _, offset_words, _, _, _, typ = struct.unpack("8I", lib[bdoff:bdoff+32])
#       if length == 0: break
#       binfos.append((offset_words * 4, typ))
#       bdoff += length
#
# `len(self.name)` is the KERNEL NAME LENGTH, so the descriptor table's start
# depends on a string this port does not otherwise have -- which is why
# `name_len` is a parameter of `pd.parse` and not a field.
# ===========================================================================
def pd.pvtmem_size_per_item(+pvtmem: U32) -> U32: U32.shrn(H.round_up_u32(pvtmem, 512), 9n)
def t_lib5() -> IO(Unit):
  do IO<Unit>:
    urow("qc_lib_5_len", U32.from_nat(List.length(&2, U32, LIB_5())))
    +p5 : P.Pd <- IO.pure(P.Pd, P.pd.parse_full(LIB_5(), 24))
    lrow("qc_pl_5", [16,416,288,48,5,160,4097,0,0,2,0,2048,2048,2176,12,8,848])
    lrow("qc_pl_5_bufs", desc.buf_offs(Pd.bins(p5)))
    srow("qc_pl_5_consts", const.flat(Pd.consts(p5)))
    urow("qc_off_cl_5_ibo", pd.cl_ibo_off(Pd.ibo_cnt(p5)))
    urow("qc_off_cl_5_tex", pd.cl_tex_off(Pd.ibo_cnt(p5)))
    urow("qc_off_cl_5_samp", pd.cl_samp_off(Pd.tex_cnt(p5), Pd.ibo_cnt(p5)))
    urow("qc_off_nir_5_tex", pd.nir_tex_off(Pd.tex_cnt(p5)))
    urow("qc_off_nir_5_ibo", pd.nir_ibo_off(Pd.tex_cnt(p5)))
    urow("qc_off_nir_5_samp", pd.nir_samp_off(Pd.tex_cnt(p5), Pd.ibo_cnt(p5)))
    urow("qc_pd_5_peritem", pd.pvtmem_size_per_item(Pd.pvtmem(p5)))
    urow("qc_pd_5_total", pd.pvtmem_size_total(pd.pvtmem_size_per_item(Pd.pvtmem(p5))))
    urow("qc_pd_5_stack", pd.hw_stack_offset(Pd.pvtmem(p5)))
    urow("qc_pd_5_shared", pd.shared_size(Pd.shmem(p5)))
    urow("qc_pd_5_maxthr", pd.max_threads(Pd.fregs(p5), Pd.hregs(p5)))
    urow("qc_pd_5_kasize", pd.kernargs_alloc_size(Pd.tex_cnt(p5), Pd.ibo_cnt(p5), Pd.samp_cnt(p5)))
    row("qc_off_swap_ibo_5", U32.is_eq(pd.cl_ibo_off(Pd.ibo_cnt(p5)),
      pd.nir_ibo_off(Pd.tex_cnt(p5))))
    row("qc_off_swap_tex_5", U32.is_eq(pd.cl_tex_off(Pd.ibo_cnt(p5)),
      pd.nir_tex_off(Pd.tex_cnt(p5))))
    row("qc_off_samp_agrees_5", U32.is_eq(
      pd.cl_samp_off(Pd.tex_cnt(p5), Pd.ibo_cnt(p5)),
      pd.nir_samp_off(Pd.tex_cnt(p5), Pd.ibo_cnt(p5))))
    urow("qc_bin_seen_5", P.Wb.seen(P.desc.walk(P.fuel.of(1024), LIB_5(),
      P.Wb{Pd.bdoff(p5), 0, True{}, Nil{}})))
    urow("qc_const_bound_5", P.Cw.seen(P.pd.const_walk(LIB_5(), p5)))
    urow("qc_const_alive_first_5", Bool.to_u32(P.const.alive(320, 416)))
    urow("qc_const_alive_last_5", Bool.to_u32(P.const.alive(400, 416)))
    urow("qc_const_alive_past_5", Bool.to_u32(P.const.alive(440, 416)))
# --- 13: THE PROGRAM CACHE, :285-292 -------------------------------------
# THE SEQUENCE IS A GATE FIXTURE, not a ported fold. Three calls: hash A on
# devs [1], hash A on devs [1] again, hash B on devs [1]. The SECOND call must
# be a HIT -- that is `qc_ck_second_is_hit` -- and the FIRST call must have
# emitted PARSE, MINT, PATCH and nothing else, in that order -- that is
# `qc_ck_ckinds` is the KIND SEQUENCE of all six calls, which is the one row
# that says what the whole sequence WAS; the per-kind COUNT rows below it
# say how often.
#
# `qc_ck_older_survives` IS THE NEGATIVE CASE the brief asks for, and it is
# not an invention: `_qcom_program_cache` is a module-level dict with no
# eviction, so an entry inserted before another one is still there afterwards.
# A port with an LRU, a size cap, or a "rebuild when the cache is full" arm
# fails that row.
#
# `qc_ck_devs_splits` is the OTHER negative: the same hash on a DIFFERENT
# device set is a different key, because the key is the PAIR
# `(prg.src[3].arg, devs)`. A cache keyed on the hash alone passes every other
# row here and fails this one.
#    the cache is a MAP, so `cache[key] = ...` is an ASSIGNMENT and re-storing
# a key does not grow the dict. `ce.put` is that assignment and the six
# calls below go through it -- `qc_ck_len` is the row that says four programs
# occupy four slots, not six.
def ctz(+v: U32) -> U32: P.ctz.of(P.ctz.go(P.CTZ_BITS(), v, P.Cz{0, False{}}))
# ===========================================================================
# ops_qcom.py:45-47 -- `parity`. Three fold rounds and then a 4-bit table
# lookup, and both halves have to be right or every packet header is wrong:
#
#     for i in range(4, 1, -1): val ^= val >> (1 << i)   # i = 4, 3, 2
#     return (~0x6996 >> (val & 0xf)) & 1
#
# `1 << i` is 16, 8, 4 -- NOT 4, 2, 1. And `(~0x6996 >> k) & 1` is Python's
# ARITHMETIC right shift of the NEGATIVE `~0x6996 == -0x6997`, whose infinite
# two's complement is `...1001011001101001`, and its low sixteen bits are
# `0x9669`. So the table is `bit k of 0x9669`, and `qc_parity_*` is diffed
# against CPython for all sixteen residues.
# ===========================================================================
def LIB_2() -> List<&2, U32>:
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 1, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 64, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 160, 1,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 1, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 16,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 48, 0, 0, 0, 40, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 48, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,]
def SB6_CS_TEX() -> U32: 5
def buftype_of(+s: String) -> U32: P.buftype_ix.go(List.length(&2, String, P.buftype_names()), s, P.buftype_names(), 0, 0)
def buftype_name(v: U32) -> String: P.buftype_name.at(U32.to_nat(v))
# ===========================================================================
# ops_qcom.py:36-41 -- THE qreg TABLE, both directions.
#
# :41 `qreg = type("QREG", (object,), {name[4:].lower():
#   functools.partial(_qreg_exec, name) for name in mesa.__dict__
#   if name[:4] == 'REG_'})`. So the FORWARD direction the file uses is
# `qreg.<attr>` -> `REG_<ATTR.UPPER>`, and the REVERSE the comprehension builds
# is `REG_<NAME>` -> `<name[4:].lower()>`. `mesa_of` and `qreg_of` are those two
# halves and they are the WHOLE of the name game; everything else is a field
# lookup.
#
# The list is the thirty-four `qreg` attributes ops_qcom.py actually reaches,
# SORTED, so the index space is a function of the set and not of the file's
# line order. It is generated by `.agents/slop/qc_oracle.py table`, which
# ast-walks the 41 call sites.
# ===========================================================================
# --- 17: `exec` -- THE REGISTER SEQUENCE, :115-192 ----------------------
# ONE row per arm of the four forks, plus the two order rows. `qc_exec_cl` is
# the CL arm end to end (no samplers, no textures, no ibos, not NIR) and
# `qc_exec_nir` is the NIR arm with all three counts non-zero; the two differ
# only at the tail, which is what makes the pair worth printing.
def t_buftype() -> IO(Unit):
  do IO<Unit>:
    urow("qc_buftype_fwd_buf", buftype_of("BUFTYPE_BUF"))
    urow("qc_buftype_fwd_tex", buftype_of("BUFTYPE_TEX"))
    urow("qc_buftype_fwd_ibo", buftype_of("BUFTYPE_IBO"))
    urow("qc_buftype_unknown", buftype_of("BUFTYPE_NONSENSE"))
    srow("qc_buftype_rev_0", buftype_name(0))
    srow("qc_buftype_rev_1", buftype_name(1))
    srow("qc_buftype_rev_2", buftype_name(2))
    urow("qc_buftype_n", U32.from_nat(List.length(&2, String, P.buftype_names())))
    row("qc_buftype_ibo_is_not_tex", Bool.and(U32.is_eq(buftype_of("BUFTYPE_IBO"), P.BUFTYPE_IBO()),
      Bool.not(U32.is_eq(buftype_of("BUFTYPE_IBO"), P.BUFTYPE_TEX()))))
# --- 2: the qreg REGISTER table, both directions, :41 ---------------------
# `qc_reg_<i>` is ONE row carrying BOTH: `attr->REG_NAME<-index`. The forward
# half is `mesa_of`, the reverse half is `qreg_of` followed by the index
# lookup, and the index is what a dropped row would shift. So a wrong forward
# name, a wrong reverse name and a missing entry all move the same row, which
# is the honest shape for a table this small.
def pack_args.of(+offs: List<&2, U32>, size: U32) -> List<&2, U32>:
  P.pack_args.sorted(offs, size)
def FLAG_MEMALIGN() -> String: "KGSL_MEMALIGN"
# `consts_info` as the ONE string the gate diffs, because the shape is a list of
# triples and a row per triple would be three rows per constant for no more
# information. `val@byteoff:size` and `;` between, which is the oracle's own
# spelling -- so a reader can line the two up by eye.
def LIB_1() -> List<&2, U32>:
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 1, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 64, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 160, 1,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 1, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 48, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,]
# --- the six DERIVED sizes, :232-237 --------------------------------------
# These are PURE U32 arithmetic on six parsed numbers and they are the numbers
# the kernel-argument buffer is sized from, so a wrong one is a wrong
# allocation. Each is its own def because Python writes each as its own
# assignment and the ORDER of the reads matters: `hw_stack_offset` reads
# `pvtmem` twice through `round_up` and `next_power2`.
def t_lib1() -> IO(Unit):
  do IO<Unit>:
    urow("qc_lib_1_len", U32.from_nat(List.length(&2, U32, LIB_1())))
    +p1 : P.Pd <- IO.pure(P.Pd, P.pd.parse_full(LIB_1(), 8))
    lrow("qc_pl_1", [32,416,288,48,5,512,0,2,1,1,0,2048,2048,2112,1,1,840])
    lrow("qc_pl_1_bufs", desc.buf_offs(Pd.bins(p1)))
    srow("qc_pl_1_consts", const.flat(Pd.consts(p1)))
    urow("qc_off_cl_1_ibo", pd.cl_ibo_off(Pd.ibo_cnt(p1)))
    urow("qc_off_cl_1_tex", pd.cl_tex_off(Pd.ibo_cnt(p1)))
    urow("qc_off_cl_1_samp", pd.cl_samp_off(Pd.tex_cnt(p1), Pd.ibo_cnt(p1)))
    urow("qc_off_nir_1_tex", pd.nir_tex_off(Pd.tex_cnt(p1)))
    urow("qc_off_nir_1_ibo", pd.nir_ibo_off(Pd.tex_cnt(p1)))
    urow("qc_off_nir_1_samp", pd.nir_samp_off(Pd.tex_cnt(p1), Pd.ibo_cnt(p1)))
    urow("qc_pd_1_peritem", pd.pvtmem_size_per_item(Pd.pvtmem(p1)))
    urow("qc_pd_1_total", pd.pvtmem_size_total(pd.pvtmem_size_per_item(Pd.pvtmem(p1))))
    urow("qc_pd_1_stack", pd.hw_stack_offset(Pd.pvtmem(p1)))
    urow("qc_pd_1_shared", pd.shared_size(Pd.shmem(p1)))
    urow("qc_pd_1_maxthr", pd.max_threads(Pd.fregs(p1), Pd.hregs(p1)))
    urow("qc_pd_1_kasize", pd.kernargs_alloc_size(Pd.tex_cnt(p1), Pd.ibo_cnt(p1), Pd.samp_cnt(p1)))
    row("qc_off_swap_ibo_1", U32.is_eq(pd.cl_ibo_off(Pd.ibo_cnt(p1)),
      pd.nir_ibo_off(Pd.tex_cnt(p1))))
    row("qc_off_swap_tex_1", U32.is_eq(pd.cl_tex_off(Pd.ibo_cnt(p1)),
      pd.nir_tex_off(Pd.tex_cnt(p1))))
    row("qc_off_samp_agrees_1", U32.is_eq(
      pd.cl_samp_off(Pd.tex_cnt(p1), Pd.ibo_cnt(p1)),
      pd.nir_samp_off(Pd.tex_cnt(p1), Pd.ibo_cnt(p1))))
    urow("qc_bin_seen_1", P.Wb.seen(P.desc.walk(P.fuel.of(1024), LIB_1(),
      P.Wb{Pd.bdoff(p1), 0, True{}, Nil{}})))
    urow("qc_const_bound_1", P.Cw.seen(P.pd.const_walk(LIB_1(), p1)))
    urow("qc_const_alive_first_1", Bool.to_u32(P.const.alive(320, 416)))
    urow("qc_const_alive_last_1", Bool.to_u32(P.const.alive(400, 416)))
    urow("qc_const_alive_past_1", Bool.to_u32(P.const.alive(440, 416)))
# --- 5: ctz, :43 ---------------------------------------------------------
# `qc_ctz_nonzero` states the PRECONDITION rather than trusting it: `pitch` at
# :106 is `shape[1] * 4 * imgdt.itemsize`, so `ctz(pitch) >= 2` always and the
# `v == 0` case -- the only one where the port's `32` and Python's `-1` differ
# -- cannot be reached from `exec`.
def t_ctz() -> IO(Unit):
  do IO<Unit>:
    urow("qc_ctz_00000001", ctz(1))
    urow("qc_ctz_00000002", ctz(2))
    urow("qc_ctz_00000040", ctz(64))
    urow("qc_ctz_00001000", ctz(4096))
    urow("qc_ctz_80000000", ctz(2147483648))
    urow("qc_ctz_00004000", ctz(16384))
    urow("qc_ctz_0000003f", ctz(63))
    row("qc_ctz_nonzero", Bool.and(U32.is_ge(ctz(4), 2), U32.is_ge(ctz(4096), 12)))
    urow("qc_ctz_zero", ctz(0))
# --- 6: parity, :45-47 ---------------------------------------------------
# Three rounds `>> 16`, `>> 8`, `>> 4` -- `range(4, 1, -1)` is {4,3,2} and
# `1 << i` is 16, 8, 4, NOT 4, 2, 1 -- then `(~0x6996 >> (v & 0xf)) & 1`.
# `qc_parity_all16` walks all sixteen residues so no single fixture can be
# right by luck.
def QW_U16() -> P.Qw: P.Qw{True{}, 2}
def QW_U64() -> P.Qw: P.Qw{True{}, 8}
def QW_U8() -> P.Qw: P.Qw{True{}, 1}
def q.hdr4(regno: U32, +cnt: U32) -> U32: P.pkt4_hdr(regno, cnt)
# ===========================================================================
# THE FOUR RAISES, and they are four DIFFERENT ones:
#
#   :79  `raise RuntimeError('CP_EVENT_WRITE7 is not supported')` -- inside
#        `signal`, on the `else` of `if self.dev.gpu_id[:2] < (7, 3)`
#   :118 `raise RuntimeError("Too many resources requested for launch")`
#   :120 `raise RuntimeError(f"Invalid global/local dims ...")`
#   :332 `raise RuntimeError(f"Unsupported GPU: chip_id=...")`
#
# The one that SURPRISES is :79. It is unreachable from `__init__` -- :332
# already refused every gpu_id >= (7, 3) -- so on this backend the only way to
# reach `signal` is with an accepted gpu, and :79 is dead code BY CONSTRUCTION
# rather than by accident. `qc_rf_event7_unreachable` says so instead of
# pretending the arm is live.
# ===========================================================================
# --- 19: `submit` -- the ioctl command word, :202-203 -------------------
# `(idir << 30) | (sizeof(struct_t) << 16) | (base << 8) | nr`. All four
# fields come out of `kgsl.IOCTL_KGSL_GPU_COMMAND.args` and `ctypes.sizeof`,
# and each has its own row because a wrong shift is a wrong ioctl and the
# four shifts do not commute.
def CP_WAIT_REG_MEM() -> U32: 60
# ===========================================================================
# STAGE 3 -- `QCOMComputeQueue` (:55-204) and `QCOMDevice.__init__` (:314-345).
#
# THE TWO EXTRA FLAG SETS, one flag each, so `qc_flush_ops_sync` and
# `qc_flush_ops_memsync` can isolate a SINGLE conditional. Python spells these
# as keyword arguments at three call sites and a flag list has to name them, so
# both the four-true set and the two one-true sets live here.
def q.hdr7(opcode: U32, +cnt: U32) -> U32: P.pkt7_hdr(opcode, cnt)
def QW_INT() -> P.Qw: P.Qw{False{}, 0}
# ===========================================================================
# ops_qcom.py:53 -- `struct.unpack("I", lib[off:off+4])[0]`, i.e. a LITTLE
# ENDIAN u32 at a byte offset, out of the shader binary. `lib` is `bytes` in
# Python and a `List<&2, U32>` of byte values here, which is WALL 2 below.
#
# ops_qcom.py:264 `:278` also `struct.unpack("8I", ...)` and `("III", ...)`,
# i.e. this little-endian reader run over a slice. `read_words` is that
# generalisation and it is what stage 2's `_parse_lib` consumes, so there is
# ONE transcription of "little endian" in this file.
# ===========================================================================
def QW_U32() -> P.Qw: P.Qw{True{}, 4}
def flag(+nm: String, val: U32) -> U32:
  U32.and(U32.shln(val, U32.to_nat(P.kgsl_shift(nm))), P.kgsl_mask(nm))
def REG_A6XX_SP_CS_CNTL_1() -> U32: 43441
# --- 10: flag(), :303 ---------------------------------------------------
# `(val << SHIFT) & MASK`. The `& MASK` is load-bearing and invisible for
# `KGSL_MEMALIGN` and `KGSL_CONTEXT_PRIORITY` if the fixture value fits, so
# `qc_flag_clipped` uses 4095 -- wider than PRIORITY's six bits -- and it is
# the row that says the mask is applied.
def t_hdr() -> IO(Unit):
  do IO<Unit>:
    urow("qc_qw_h_u32", qwords([QW_U32()]))
    urow("qc_qw_h_u16", qwords([QW_U16()]))
    urow("qc_qw_h_u8", qwords([QW_U8()]))
    urow("qc_qw_h_u64", qwords([QW_U64()]))
    urow("qc_qw_h_two_u32", qwords([QW_U32(), QW_U32()]))
    urow("qc_qw_h_int", qwords([QW_INT()]))
    urow("qc_qw_h_u32_int", qwords([QW_U32(), QW_INT()]))
    urow("qc_qw_h_none", qwords(Nil{}))
    urow("qc_qw_h_u16u8", qwords([QW_U16(), QW_U8()]))
    urow("qc_h7_setmarker", q.hdr7(P.CP_SET_MARKER(), 1))
    urow("qc_h7_waitidle", q.hdr7(P.CP_WAIT_FOR_IDLE(), 0))
    urow("qc_h7_eventwrite", q.hdr7(P.CP_EVENT_WRITE(), 3))
    urow("qc_h7_loadconst", q.hdr7(P.CP_LOAD_STATE6_FRAG(), 2))
    urow("qc_h7_exec", q.hdr7(P.CP_EXEC_CS(), 4))
    urow("qc_h7_runcl", q.hdr7(P.CP_RUN_OPENCL(), 0))
    urow("qc_h7_eventinv", q.hdr7(P.CP_EVENT_WRITE(), 1))
    urow("qc_h7_memwrites", q.hdr7(P.CP_WAIT_MEM_WRITES(), 0))
    urow("qc_h7_regtomem", q.hdr7(CP_REG_TO_MEM(), 1))
    urow("qc_h7_waitregmem", q.hdr7(CP_WAIT_REG_MEM(), 5))
    urow("qc_h4_updatecntl", q.hdr4(P.REG_A6XX_SP_UPDATE_CNTL(), 2))
    urow("qc_h4_cs_tsize", q.hdr4(P.REG_A6XX_SP_CS_TSIZE(), 1))
    urow("qc_h4_cs_usize", q.hdr4(P.REG_A6XX_SP_CS_USIZE(), 1))
    urow("qc_h4_mode_cntl", q.hdr4(P.REG_A6XX_SP_MODE_CNTL(), 1))
    urow("qc_h4_perfctr", q.hdr4(P.REG_A6XX_SP_PERFCTR_SHADER_MASK(), 1))
    urow("qc_h4_tpl1", q.hdr4(P.REG_A6XX_TPL1_MODE_CNTL(), 1))
    urow("qc_h4_dbgeco", q.hdr4(P.REG_A6XX_TPL1_DBG_ECO_CNTL(), 1))
    urow("qc_h4_ndrange", q.hdr4(P.REG_A6XX_SP_CS_NDRANGE_0(), 12))
    urow("qc_h4_cntl0", q.hdr4(P.REG_A6XX_SP_CS_CNTL_0(), 6))
    urow("qc_h4_cntl1", q.hdr4(REG_A6XX_SP_CS_CNTL_1(), 3))
    urow("qc_h4_regprogid", q.hdr4(P.REG_A6XX_SP_REG_PROG_ID_0(), 5))
    urow("qc_h4_pvtmemstk", q.hdr4(P.REG_A6XX_SP_CS_PVT_MEM_STACK_OFFSET(), 1))
    urow("qc_h4_instrsize", q.hdr4(P.REG_A6XX_SP_CS_INSTR_SIZE(), 1))
    urow("qc_h4_sampbase", q.hdr4(P.REG_A6XX_SP_CS_SAMPLER_BASE(), 1))
    urow("qc_h4_texmembase", q.hdr4(P.REG_A6XX_SP_CS_TEXMEMOBJ_BASE(), 1))
    urow("qc_h4_uavbase", q.hdr4(P.REG_A6XX_SP_CS_UAV_BASE(), 1))
    urow("qc_h4_csconfig", q.hdr4(P.REG_A6XX_SP_CS_CONFIG(), 1))
    urow("qc_h4_constcfg0", q.hdr4(P.REG_A6XX_SP_CS_CONST_CONFIG_0(), 2))
# --- 16: THE CACHE FLUSH, :61-70 -----------------------------------------
# FOUR independent conditionals in ONE def, and the ISSUE order is not the
# PARAMETER order: Python tests write_back, invalidate, sync, memsync and
# issues memsync BEFORE sync. `qc_flush_issue_order` is the row that says so
# and `qc_flush_issue_order_is_not_param` says the mapping is not the
# identity -- a port that folds over the parameter order emits WAIT_FOR_IDLE
# one step early.
def FLUSH_NONE() -> List<&2, Bool>: [False{}, False{}, False{}, False{}]
# the three-dim list readers, so `rf.resources` can be handed three U32s
# ===========================================================================
# STAGE 3 -- `QCOMComputeQueue` (:55-204) and `QCOMDevice.__init__` (:314-345).
#
# THE TWO EXTRA FLAG SETS, one flag each, so `qc_flush_ops_sync` and
# `qc_flush_ops_memsync` can isolate a SINGLE conditional. Python spells these
# as keyword arguments at three call sites and a flag list has to name them, so
# both the four-true set and the two one-true sets live here.
def t_lib0() -> IO(Unit):
  do IO<Unit>:
    urow("qc_lib_0_len", U32.from_nat(List.length(&2, U32, LIB_0())))
    +p0 : P.Pd <- IO.pure(P.Pd, P.pd.parse_full(LIB_0(), 8))
    lrow("qc_pl_0", [24,416,288,48,5,1536,6144,0,0,0,1,2048,2112,2112,33,25,768])
    lrow("qc_pl_0_bufs", desc.buf_offs(Pd.bins(p0)))
    srow("qc_pl_0_consts", const.flat(Pd.consts(p0)))
    urow("qc_off_cl_0_ibo", pd.cl_ibo_off(Pd.ibo_cnt(p0)))
    urow("qc_off_cl_0_tex", pd.cl_tex_off(Pd.ibo_cnt(p0)))
    urow("qc_off_cl_0_samp", pd.cl_samp_off(Pd.tex_cnt(p0), Pd.ibo_cnt(p0)))
    urow("qc_off_nir_0_tex", pd.nir_tex_off(Pd.tex_cnt(p0)))
    urow("qc_off_nir_0_ibo", pd.nir_ibo_off(Pd.tex_cnt(p0)))
    urow("qc_off_nir_0_samp", pd.nir_samp_off(Pd.tex_cnt(p0), Pd.ibo_cnt(p0)))
    urow("qc_pd_0_peritem", pd.pvtmem_size_per_item(Pd.pvtmem(p0)))
    urow("qc_pd_0_total", pd.pvtmem_size_total(pd.pvtmem_size_per_item(Pd.pvtmem(p0))))
    urow("qc_pd_0_stack", pd.hw_stack_offset(Pd.pvtmem(p0)))
    urow("qc_pd_0_shared", pd.shared_size(Pd.shmem(p0)))
    urow("qc_pd_0_maxthr", pd.max_threads(Pd.fregs(p0), Pd.hregs(p0)))
    urow("qc_pd_0_kasize", pd.kernargs_alloc_size(Pd.tex_cnt(p0), Pd.ibo_cnt(p0), Pd.samp_cnt(p0)))
    row("qc_off_swap_ibo_0", U32.is_eq(pd.cl_ibo_off(Pd.ibo_cnt(p0)),
      pd.nir_ibo_off(Pd.tex_cnt(p0))))
    row("qc_off_swap_tex_0", U32.is_eq(pd.cl_tex_off(Pd.ibo_cnt(p0)),
      pd.nir_tex_off(Pd.tex_cnt(p0))))
    row("qc_off_samp_agrees_0", U32.is_eq(
      pd.cl_samp_off(Pd.tex_cnt(p0), Pd.ibo_cnt(p0)),
      pd.nir_samp_off(Pd.tex_cnt(p0), Pd.ibo_cnt(p0))))
    urow("qc_bin_seen_0", P.Wb.seen(P.desc.walk(P.fuel.of(1024), LIB_0(),
      P.Wb{Pd.bdoff(p0), 0, True{}, Nil{}})))
    urow("qc_const_bound_0", P.Cw.seen(P.pd.const_walk(LIB_0(), p0)))
    urow("qc_const_alive_first_0", Bool.to_u32(P.const.alive(320, 416)))
    urow("qc_const_alive_last_0", Bool.to_u32(P.const.alive(400, 416)))
    urow("qc_const_alive_past_0", Bool.to_u32(P.const.alive(440, 416)))
def t_lib2() -> IO(Unit):
  do IO<Unit>:
    urow("qc_lib_2_len", U32.from_nat(List.length(&2, U32, LIB_2())))
    +p2 : P.Pd <- IO.pure(P.Pd, P.pd.parse_full(LIB_2(), 16))
    lrow("qc_pl_2", [4,416,288,48,5,1536,1024,0,0,0,2,2048,2176,2176,48,40,904])
    lrow("qc_pl_2_bufs", desc.buf_offs(Pd.bins(p2)))
    srow("qc_pl_2_consts", const.flat(Pd.consts(p2)))
    urow("qc_off_cl_2_ibo", pd.cl_ibo_off(Pd.ibo_cnt(p2)))
    urow("qc_off_cl_2_tex", pd.cl_tex_off(Pd.ibo_cnt(p2)))
    urow("qc_off_cl_2_samp", pd.cl_samp_off(Pd.tex_cnt(p2), Pd.ibo_cnt(p2)))
    urow("qc_off_nir_2_tex", pd.nir_tex_off(Pd.tex_cnt(p2)))
    urow("qc_off_nir_2_ibo", pd.nir_ibo_off(Pd.tex_cnt(p2)))
    urow("qc_off_nir_2_samp", pd.nir_samp_off(Pd.tex_cnt(p2), Pd.ibo_cnt(p2)))
    urow("qc_pd_2_peritem", pd.pvtmem_size_per_item(Pd.pvtmem(p2)))
    urow("qc_pd_2_total", pd.pvtmem_size_total(pd.pvtmem_size_per_item(Pd.pvtmem(p2))))
    urow("qc_pd_2_stack", pd.hw_stack_offset(Pd.pvtmem(p2)))
    urow("qc_pd_2_shared", pd.shared_size(Pd.shmem(p2)))
    urow("qc_pd_2_maxthr", pd.max_threads(Pd.fregs(p2), Pd.hregs(p2)))
    urow("qc_pd_2_kasize", pd.kernargs_alloc_size(Pd.tex_cnt(p2), Pd.ibo_cnt(p2), Pd.samp_cnt(p2)))
    row("qc_off_swap_ibo_2", U32.is_eq(pd.cl_ibo_off(Pd.ibo_cnt(p2)),
      pd.nir_ibo_off(Pd.tex_cnt(p2))))
    row("qc_off_swap_tex_2", U32.is_eq(pd.cl_tex_off(Pd.ibo_cnt(p2)),
      pd.nir_tex_off(Pd.tex_cnt(p2))))
    row("qc_off_samp_agrees_2", U32.is_eq(
      pd.cl_samp_off(Pd.tex_cnt(p2), Pd.ibo_cnt(p2)),
      pd.nir_samp_off(Pd.tex_cnt(p2), Pd.ibo_cnt(p2))))
    urow("qc_bin_seen_2", P.Wb.seen(P.desc.walk(P.fuel.of(1024), LIB_2(),
      P.Wb{Pd.bdoff(p2), 0, True{}, Nil{}})))
    urow("qc_const_bound_2", P.Cw.seen(P.pd.const_walk(LIB_2(), p2)))
    urow("qc_const_alive_first_2", Bool.to_u32(P.const.alive(320, 416)))
    urow("qc_const_alive_last_2", Bool.to_u32(P.const.alive(400, 416)))
    urow("qc_const_alive_past_2", Bool.to_u32(P.const.alive(440, 416)))
def FLAGS() -> List<&2, U32>: [0, 1, 2, 3]
def KGSL_MEMFLAGS_USE_CPU_MAP() -> U32: 268435456
def LIB_4() -> List<&2, U32>:
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 1, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 64, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 160, 1,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 1, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
  16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 16, 0, 0, 7, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 4,
  0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 48, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 8, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,]
# --- 11: the 62 mesa/kgsl CONSTANTS -------------------------------------
# Transcribed once each from the oracle, and the oracle reads them off the
# LIVE autogen modules by walking the AST of ops_qcom.py, so a stale number
# here is a row that moves. They are named without a module prefix because
# the oracle ASSERTS the two namespaces do not collide.
def t_lib4() -> IO(Unit):
  do IO<Unit>:
    urow("qc_lib_4_len", U32.from_nat(List.length(&2, U32, LIB_4())))
    +p4 : P.Pd <- IO.pure(P.Pd, P.pd.parse_full(LIB_4(), 12))
    lrow("qc_pl_4", [128,416,288,48,5,1,2048,2,1,0,0,2048,2048,2048,7,3,716])
    lrow("qc_pl_4_bufs", desc.buf_offs(Pd.bins(p4)))
    srow("qc_pl_4_consts", const.flat(Pd.consts(p4)))
    urow("qc_off_cl_4_ibo", pd.cl_ibo_off(Pd.ibo_cnt(p4)))
    urow("qc_off_cl_4_tex", pd.cl_tex_off(Pd.ibo_cnt(p4)))
    urow("qc_off_cl_4_samp", pd.cl_samp_off(Pd.tex_cnt(p4), Pd.ibo_cnt(p4)))
    urow("qc_off_nir_4_tex", pd.nir_tex_off(Pd.tex_cnt(p4)))
    urow("qc_off_nir_4_ibo", pd.nir_ibo_off(Pd.tex_cnt(p4)))
    urow("qc_off_nir_4_samp", pd.nir_samp_off(Pd.tex_cnt(p4), Pd.ibo_cnt(p4)))
    urow("qc_pd_4_peritem", pd.pvtmem_size_per_item(Pd.pvtmem(p4)))
    urow("qc_pd_4_total", pd.pvtmem_size_total(pd.pvtmem_size_per_item(Pd.pvtmem(p4))))
    urow("qc_pd_4_stack", pd.hw_stack_offset(Pd.pvtmem(p4)))
    urow("qc_pd_4_shared", pd.shared_size(Pd.shmem(p4)))
    urow("qc_pd_4_maxthr", pd.max_threads(Pd.fregs(p4), Pd.hregs(p4)))
    urow("qc_pd_4_kasize", pd.kernargs_alloc_size(Pd.tex_cnt(p4), Pd.ibo_cnt(p4), Pd.samp_cnt(p4)))
    row("qc_off_swap_ibo_4", U32.is_eq(pd.cl_ibo_off(Pd.ibo_cnt(p4)),
      pd.nir_ibo_off(Pd.tex_cnt(p4))))
    row("qc_off_swap_tex_4", U32.is_eq(pd.cl_tex_off(Pd.ibo_cnt(p4)),
      pd.nir_tex_off(Pd.tex_cnt(p4))))
    row("qc_off_samp_agrees_4", U32.is_eq(
      pd.cl_samp_off(Pd.tex_cnt(p4), Pd.ibo_cnt(p4)),
      pd.nir_samp_off(Pd.tex_cnt(p4), Pd.ibo_cnt(p4))))
    urow("qc_bin_seen_4", P.Wb.seen(P.desc.walk(P.fuel.of(1024), LIB_4(),
      P.Wb{Pd.bdoff(p4), 0, True{}, Nil{}})))
    urow("qc_const_bound_4", P.Cw.seen(P.pd.const_walk(LIB_4(), p4)))
    urow("qc_const_alive_first_4", Bool.to_u32(P.const.alive(320, 416)))
    urow("qc_const_alive_last_4", Bool.to_u32(P.const.alive(400, 416)))
    urow("qc_const_alive_past_4", Bool.to_u32(P.const.alive(440, 416)))
def exec.dispatch(+t: P.Tr) -> U32:
  P.Two.b(P.exec.dispatch.go(List.length(&2, P.Call, P.Tr.calls(t)), P.Tr.calls(t), P.Two{0, 0}))
# THE LAST `cmd` that is NOT the trailing flush -- i.e. the DISPATCH. The two
# readers differ by one position and `qc_exec_cl_last_cmd` beside
# `qc_exec_cl_tail_cmd` is the pair that says so.
# `exec.tail_last` is the SECOND-TO-LAST `cmd`: `exec.last_cmd` is the trailing
# cache flush of :192 and this is the dispatch. Naming both is what makes the
# pair a claim rather than a restatement.
# ===========================================================================
# `submit` -- THE IOCTL COMMAND WORD, :202-203.
#
#     idir, base, nr, struct_t = kgsl.IOCTL_KGSL_GPU_COMMAND.args
#     ioctl_cmd = (idir << 30) | (ctypes.sizeof(struct_t) << 16) | (base << 8) | nr
#
# The four shifts are 30, 16, 8 and 0 and they do NOT commute with the masks:
# `base << 8` overlaps nothing, but `idir << 30` is at the very top, so a
# `sizeof` that exceeded 2^14 would collide with it and a `base` above 255 would
# be truncated by the kernel. The four fields and the four shifts each get a row.
# ===========================================================================
def pack_args.align() -> U32: P.LAYOUT_ALIGN()
# THE PRINTERS, and note `lrow` prints a `List<&2, U32>` as `a,b,c` with NO
# trailing separator -- a baked-in separator is half a diff (bend2-constraints.md,
# the `int_*_new` row class).
def qfield_isb(+r: String, +f: String) -> Bool: P.Qf.isb(P.qfield_at(r, f))
# ===========================================================================
# `_qreg_exec` (:36-40), as one pure def. `__val` starts at 0 and each
# keyword ORs in either the flag bit (when the field is a bool) or
# `v << shift`.
#
# THE BOOLEAN ARM IS NOT `if v`. Python writes
# `(getattr(mesa, reg_name) if v else 0) if type(v) is bool else (v << ...)`,
# which is `(FLAG IF v ELSE 0)` when the value IS a bool -- so a `False` bool
# contributes ZERO and a `True` contributes the table's bit. The port takes
# `v` as a U32 and treats the field's OWN `isb` as the discriminator, and
# `qflag.of` is the only way to pass a bool, so the `type(v) is bool` test
# cannot be got wrong at a call site by accident.
# ===========================================================================
# :39's `(getattr(mesa, reg_name) if v else 0)` -- a bool field contributes its
# BIT when the value is truthy and ZERO when it is not. That zero arm is not
# decoration: without it every "disable this" register write would set the bit.
# --- 7: pkt7_hdr / pkt4_hdr, :49 and :51 ---------------------------------
# `|` BINDS LOOSER THAN `&` AND `<<` in Python, so these are five independent
# contributions OR-ed, not a left-to-right chain. The masks and the two high
# parity bits (<< 23 and << 27) are the parts a rewrite gets wrong, and the
# CP_TYPE7/4 tag already sits in bit 30, so these are u32 and not i32.
def t_pkt() -> IO(Unit):
  do IO<Unit>:
    urow("qc_pkt7_38_0", P.pkt7_hdr(38, 0))
    urow("qc_pkt7_70_3", P.pkt7_hdr(70, 3))
    urow("qc_pkt7_52_2", P.pkt7_hdr(52, 2))
    urow("qc_pkt7_101_1", P.pkt7_hdr(101, 1))
    urow("qc_pkt7_51_4", P.pkt7_hdr(51, 4))
    urow("qc_pkt7_49_0", P.pkt7_hdr(49, 0))
    urow("qc_pkt7_62_1", P.pkt7_hdr(62, 1))
    urow("qc_pkt7_60_5", P.pkt7_hdr(60, 5))
    urow("qc_pkt4_47504_12", P.pkt4_hdr(47504, 12))
    urow("qc_pkt4_43440_6", P.pkt4_hdr(43440, 6))
    urow("qc_pkt4_43452_1", P.pkt4_hdr(43452, 1))
    urow("qc_pkt4_45833_1", P.pkt4_hdr(45833, 1))
    urow("qc_pkt4_47880_2", P.pkt4_hdr(47880, 2))
    urow("qc_pkt4_43451_1", P.pkt4_hdr(43451, 1))
    urow("qc_pkt7_tag", P.CP_TYPE7_PKT())
    urow("qc_pkt4_tag", P.CP_TYPE4_PKT())
# --- 8: _read_lib, :53 ---------------------------------------------------
# `struct.unpack("I", lib[off:off+4])[0]` -- LITTLE endian. The fixture is
# the oracle's own 16-byte `struct.pack('<4I', 0xDEADBEEF, 1, 0xFFFFFFFF,
# 0x80000000)`, and `qc_rl_bytes` echoes it back so a bend-side fixture that
# drifts from the oracle's is visible as a row rather than as four wrong
# reads. Byte order is invisible if every fixture word is palindromic, so
# 0xDEADBEEF and 0x80000000 are both in the fixture.
def qfield_nm(+r: String, +f: String) -> String: P.Qf.nm(P.qfield_at(r, f))
# --- the misc enums --------------------------------------------------------
def fld_line(+ix: U32) -> String: P.fld_line.at(P.fld_at(ix))
def t_fields() -> IO(Unit):
  do IO<Unit>:
    urow("qc_nfields", U32.from_nat(List.length(&2, P.Qf, P.qfields())))
    srow("qc_fld_0", fld_line(0))
    srow("qc_fld_1", fld_line(1))
    srow("qc_fld_2", fld_line(2))
    srow("qc_fld_3", fld_line(3))
    srow("qc_fld_4", fld_line(4))
    srow("qc_fld_5", fld_line(5))
    srow("qc_fld_6", fld_line(6))
    srow("qc_fld_7", fld_line(7))
    srow("qc_fld_8", fld_line(8))
    srow("qc_fld_9", fld_line(9))
    srow("qc_fld_10", fld_line(10))
    srow("qc_fld_11", fld_line(11))
    srow("qc_fld_12", fld_line(12))
    srow("qc_fld_13", fld_line(13))
    srow("qc_fld_14", fld_line(14))
    srow("qc_fld_15", fld_line(15))
    srow("qc_fld_16", fld_line(16))
    srow("qc_fld_17", fld_line(17))
    srow("qc_fld_18", fld_line(18))
    srow("qc_fld_19", fld_line(19))
    srow("qc_fld_20", fld_line(20))
    srow("qc_fld_21", fld_line(21))
    srow("qc_fld_22", fld_line(22))
    srow("qc_fld_23", fld_line(23))
    srow("qc_fld_24", fld_line(24))
    srow("qc_fld_25", fld_line(25))
    srow("qc_fld_26", fld_line(26))
    srow("qc_fld_27", fld_line(27))
    srow("qc_fld_28", fld_line(28))
    srow("qc_fld_29", fld_line(29))
    srow("qc_fld_30", fld_line(30))
    srow("qc_fld_31", fld_line(31))
    srow("qc_fld_32", fld_line(32))
    srow("qc_fld_33", fld_line(33))
    srow("qc_fld_34", fld_line(34))
    srow("qc_fld_35", fld_line(35))
    srow("qc_fld_36", fld_line(36))
    srow("qc_fld_37", fld_line(37))
    srow("qc_fld_38", fld_line(38))
    srow("qc_fld_39", fld_line(39))
    srow("qc_fld_40", fld_line(40))
    srow("qc_fld_41", fld_line(41))
    srow("qc_fld_42", fld_line(42))
    srow("qc_fld_43", fld_line(43))
    srow("qc_fld_44", fld_line(44))
    srow("qc_fld_45", fld_line(45))
    srow("qc_fld_46", fld_line(46))
    srow("qc_fld_47", fld_line(47))
    srow("qc_fld_48", fld_line(48))
    srow("qc_fld_49", fld_line(49))
    srow("qc_fld_50", fld_line(50))
    srow("qc_fld_51", fld_line(51))
    srow("qc_fld_52", fld_line(52))
    srow("qc_fld_53", fld_line(53))
    srow("qc_fld_54", fld_line(54))
    srow("qc_fld_55", fld_line(55))
    srow("qc_fld_56", fld_line(56))
    srow("qc_fld_57", fld_line(57))
    srow("qc_fld_58", fld_line(58))
    srow("qc_fld_59", fld_line(59))
    srow("qc_fld_60", fld_line(60))
    srow("qc_fld_61", fld_line(61))
    urow("qc_fld_unknown", P.qfield_ix("a6xx_sp_cs_config", "NOSUCHFIELD"))
    row("qc_fld_bare_missing", String.eq(qfield_nm("a6xx_sp_cs_config", "NOSUCHFIELD"), ""))
    row("qc_fld_bare_isbool", Bool.not(qfield_isb("a6xx_sp_cs_config", "NOSUCHFIELD")))
# :192 `self._cache_flush(write_back=True, invalidate=False, sync=False,
# memsync=False)` -- write_back ONLY.
def FLUSH_BARRIER() -> List<&2, Bool>: [True{}, True{}, True{}, True{}]
def fv_at(+ix: U32) -> U32: P.qreg.one(P.fld_at(ix), 1)
# --- 6: parity, :45-47 ---------------------------------------------------
# Three rounds `>> 16`, `>> 8`, `>> 4` -- `range(4, 1, -1)` is {4,3,2} and
# `1 << i` is 16, 8, 4, NOT 4, 2, 1 -- then `(~0x6996 >> (v & 0xf)) & 1`.
# `qc_parity_all16` walks all sixteen residues so no single fixture can be
# right by luck.
def t_parity() -> IO(Unit):
  do IO<Unit>:
    urow("qc_parity_00000", P.parity(0))
    urow("qc_parity_00001", P.parity(1))
    urow("qc_parity_00002", P.parity(2))
    urow("qc_parity_00003", P.parity(3))
    urow("qc_parity_00004", P.parity(4))
    urow("qc_parity_00005", P.parity(5))
    urow("qc_parity_00007", P.parity(7))
    urow("qc_parity_00008", P.parity(8))
    urow("qc_parity_0000f", P.parity(15))
    urow("qc_parity_00010", P.parity(16))
    urow("qc_parity_000ff", P.parity(255))
    urow("qc_parity_00100", P.parity(256))
    urow("qc_parity_03fff", P.parity(16383))
    urow("qc_parity_0007f", P.parity(127))
    urow("qc_parity_3ffff", P.parity(262143))
    urow("qc_parity_xor", P.PARITY_XOR())
    urow("qc_parity_fold16", P.parity.folded(65535))
    urow("qc_parity_fold3", P.parity.folded(65536))
# --- 7: pkt7_hdr / pkt4_hdr, :49 and :51 ---------------------------------
# `|` BINDS LOOSER THAN `&` AND `<<` in Python, so these are five independent
# contributions OR-ed, not a left-to-right chain. The masks and the two high
# parity bits (<< 23 and << 27) are the parts a rewrite gets wrong, and the
# CP_TYPE7/4 tag already sits in bit 30, so these are u32 and not i32.
def reg_line(+ix: U32) -> String:
  String.concat([P.qreg_name_at(ix), "->", P.qreg_mesa_at(ix), "<-",
                 U32.show(P.qreg_ix_of_mesa(P.qreg_mesa_at(ix)))])
def t_regs() -> IO(Unit):
  do IO<Unit>:
    urow("qc_nregs", U32.from_nat(List.length(&2, String, P.qregs())))
    srow("qc_reg_0", reg_line(0))
    srow("qc_reg_1", reg_line(1))
    srow("qc_reg_2", reg_line(2))
    srow("qc_reg_3", reg_line(3))
    srow("qc_reg_4", reg_line(4))
    srow("qc_reg_5", reg_line(5))
    srow("qc_reg_6", reg_line(6))
    srow("qc_reg_7", reg_line(7))
    srow("qc_reg_8", reg_line(8))
    srow("qc_reg_9", reg_line(9))
    srow("qc_reg_10", reg_line(10))
    srow("qc_reg_11", reg_line(11))
    srow("qc_reg_12", reg_line(12))
    srow("qc_reg_13", reg_line(13))
    srow("qc_reg_14", reg_line(14))
    srow("qc_reg_15", reg_line(15))
    srow("qc_reg_16", reg_line(16))
    srow("qc_reg_17", reg_line(17))
    srow("qc_reg_18", reg_line(18))
    srow("qc_reg_19", reg_line(19))
    srow("qc_reg_20", reg_line(20))
    srow("qc_reg_21", reg_line(21))
    srow("qc_reg_22", reg_line(22))
    srow("qc_reg_23", reg_line(23))
    srow("qc_reg_24", reg_line(24))
    srow("qc_reg_25", reg_line(25))
    srow("qc_reg_26", reg_line(26))
    srow("qc_reg_27", reg_line(27))
    srow("qc_reg_28", reg_line(28))
    srow("qc_reg_29", reg_line(29))
    srow("qc_reg_30", reg_line(30))
    srow("qc_reg_31", reg_line(31))
    srow("qc_reg_32", reg_line(32))
    srow("qc_reg_33", reg_line(33))
def FMT6_32_32_32_32_FLOAT() -> U32: 130
# --- the state-descriptor enums, :153-179 ---------------------------------
def ST_SHADER() -> U32: 0
def t_qwords() -> IO(Unit):
  do IO<Unit>:
    urow("qc_qw_u8_u32", qwords([QW_U8(), QW_U32()]))
    urow("qc_qw_u16", qwords([QW_U16()]))
    urow("qc_qw_u64", qwords([QW_U64()]))
    urow("qc_qw_ints", qwords([QW_INT(), QW_INT()]))
    urow("qc_qw_u32_int", qwords([QW_U32(), QW_INT()]))
    urow("qc_qw_none", qwords(Nil{}))
    urow("qc_qw_is_int", P.qwords.is(False{}, 4))
    urow("qc_qw_is_u64", P.qwords.is(True{}, 8))
    urow("qc_qw_is_u8", P.qwords.is(True{}, 1))
# --- 10: flag(), :303 ---------------------------------------------------
# `(val << SHIFT) & MASK`. The `& MASK` is load-bearing and invisible for
# `KGSL_MEMALIGN` and `KGSL_CONTEXT_PRIORITY` if the fixture value fits, so
# `qc_flag_clipped` uses 4095 -- wider than PRIORITY's six bits -- and it is
# the row that says the mask is applied.
# --- the kgsl ioctl/flag constants ----------------------------------------
def KGSL_CACHEMODE_UNCACHED() -> U32: 1
def KGSL_PROP_PWR_CONSTRAINT() -> U32: 18
def KGSL_CONTEXT_PREAMBLE() -> U32: 16
def CACHE_FLUSH_TS() -> U32: 4
def LIB_3() -> List<&2, U32>:
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 1, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 64, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 160, 1,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 1, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 48, 0, 0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 32, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 64, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,]
def Tr.args(k: U32, +cs: List<&2, P.Call>) -> List<&2, U32>:
  P.Tr.args.go(List.length(&2, P.Call, cs), k, cs, Nil{})
# the trace of a SEQUENCE of calls is the concatenation of their traces, in
# call order, and it is built HERE rather than by a `Cc` machine so that there is
# exactly ONE transcription of `qcom.get` in this file. A second fold that
# re-derived the hit/miss decision would be a second bug surface.
# THE KIND SEQUENCE of a trace, as one row. `qc_ck_ckinds` reads it and every
# ORDER claim in this file is a subsequence test over it, so one row says what
# the whole trace was and the per-kind COUNT rows say how often.
# APPEND and NO reverse -- `List.append(a, A, xs, ys)` IS `xs ++ ys`. The first
# version reversed at the end as well and printed every trace backwards, which
# `qc_ck_first_trace` caught: it is the one row whose only claim is the ORDER of
# the three miss-path calls, so a reversed trace makes it unfalsifiable.
# --- 8: _read_lib, :53 ---------------------------------------------------
# `struct.unpack("I", lib[off:off+4])[0]` -- LITTLE endian. The fixture is
# the oracle's own 16-byte `struct.pack('<4I', 0xDEADBEEF, 1, 0xFFFFFFFF,
# 0x80000000)`, and `qc_rl_bytes` echoes it back so a bend-side fixture that
# drifts from the oracle's is visible as a row rather than as four wrong
# reads. Byte order is invisible if every fixture word is palindromic, so
# 0xDEADBEEF and 0x80000000 are both in the fixture.
def RL_LIB() -> List<&2, U32>:
  [239, 190, 173, 222, 1, 0, 0, 0, 255, 255, 255, 255, 0, 0, 0, 128]
def RM6_COMPUTE() -> U32: 8
def FMT6_16_16_16_16_FLOAT() -> U32: 98
# :303. `&` with the mask is what stops `getenv("QCOM_PRIORITY", 8)` from
# writing bits above PRIORITY's field, and `qc_flag_*` diffs all four.
def KGSL_CONTEXT_PWR_CONSTRAINT() -> U32: 2048
def KGSL_CMDLIST_IB() -> U32: 1
def ISAMMODE_GL() -> U32: 2
def KGSL_CONTEXT_NO_GMEM_ALLOC() -> U32: 2
def SB6_CS_SHADER() -> U32: 13
# --- the misc enums --------------------------------------------------------
# --- 2: the qreg REGISTER table, both directions, :41 ---------------------
# `qc_reg_<i>` is ONE row carrying BOTH: `attr->REG_NAME<-index`. The forward
# half is `mesa_of`, the reverse half is `qreg_of` followed by the index
# lookup, and the index is what a dropped row would shift. So a wrong forward
# name, a wrong reverse name and a missing entry all move the same row, which
# is the honest shape for a table this small.
def KGSL_PROP_DEVICE_INFO() -> U32: 1
def ST6_UAV() -> U32: 3
def KGSL_TIMESTAMP_QUEUED() -> U32: 3
def KGSL_CONTEXT_NO_FAULT_TOLERANCE() -> U32: 512
def ST_CONSTANTS() -> U32: 1
def A6XX_TEX_2D() -> U32: 1
def KGSL_USER_MEM_TYPE_ADDR() -> U32: 2
# ===========================================================================
# ops_qcom.py:20 -- `BUFTYPE_BUF, BUFTYPE_TEX, BUFTYPE_IBO = 0, 1, 2`.
#
# These three are read as a SET at :268 and :271 (`typ not in {BUFTYPE_TEX,
# BUFTYPE_IBO}` and `typ is BUFTYPE_TEX` / `typ is BUFTYPE_IBO`), and they are
# WRITTEN as an ordinal at :264 (`length, _, _, offset_words, _, _, _, typ`),
# so BOTH directions are load-bearing and both get a table.
# ===========================================================================
def SS6_INDIRECT() -> U32: 2
# :118 `if data.max_threads < prod(local_size)` -- the LOCAL size. The first
# version of this passed `gs` where Python passes `local_size`, which is
# indistinguishable for a square launch and wrong for every other one:
# `qc_rf_res_pred` is the row and it was False until this was fixed.
def WRITE_GE() -> U32: 5
def CACHE_INVALIDATE() -> U32: 49
# --- the REG_A6XX_* register numbers `self.reg` writes --------------------
# --- 20: `layout_args` / `pack_args` -- THE KERNEL ARGUMENT LAYOUT ------
# hcq2.py:69-83. `layout_args` places each word at a 4-BYTE STRIDED offset
# from the block base -- a u16 argument still occupies four -- and
# `pack_args` walks the offsets in SORTED order emitting one BINARY pad per
# GAP, then a final pad of `size - end`. The gap SEQUENCE is the kernel
# argument trace, and `qc_la_mix` is the row that says a half-word argument
# advances the cursor by four.
def ISAMMODE_CL() -> U32: 1
# --- 16: THE CACHE FLUSH, :61-70 -----------------------------------------
# FOUR independent conditionals in ONE def, and the ISSUE order is not the
# PARAMETER order: Python tests write_back, invalidate, sync, memsync and
# issues memsync BEFORE sync. `qc_flush_issue_order` is the row that says so
# and `qc_flush_issue_order_is_not_param` says the mapping is not the
# identity -- a port that folds over the parameter order emits WAIT_FOR_IDLE
# one step early.
def REG_A6XX_CP_ALWAYS_ON_COUNTER() -> U32: 2432
# --- the state-descriptor enums, :153-179 ---------------------------------
def IR3_CONST_ALLOC_DRIVER_PARAMS() -> U32: 3
# --- the kgsl ioctl/flag constants ----------------------------------------
def A6XX_TEX_CLAMP_TO_BORDER() -> U32: 3
def POLL_MEMORY() -> U32: 1
def THREAD64() -> U32: 0
def CONSTLEN_256() -> U32: 2
def t_const() -> IO(Unit):
  do IO<Unit>:
    urow("qc_c_KGSL_CACHEMODE_UNCACHED", KGSL_CACHEMODE_UNCACHED())
    urow("qc_c_KGSL_CMDLIST_IB", KGSL_CMDLIST_IB())
    urow("qc_c_KGSL_CONTEXT_NO_FAULT_TOLERANCE", KGSL_CONTEXT_NO_FAULT_TOLERANCE())
    urow("qc_c_KGSL_CONTEXT_NO_GMEM_ALLOC", KGSL_CONTEXT_NO_GMEM_ALLOC())
    urow("qc_c_KGSL_CONTEXT_PREAMBLE", KGSL_CONTEXT_PREAMBLE())
    urow("qc_c_KGSL_CONTEXT_PREEMPT_STYLE_FINEGRAIN", KGSL_CONTEXT_PREEMPT_STYLE_FINEGRAIN())
    urow("qc_c_KGSL_CONTEXT_PWR_CONSTRAINT", KGSL_CONTEXT_PWR_CONSTRAINT())
    urow("qc_c_KGSL_MEMFLAGS_USE_CPU_MAP", KGSL_MEMFLAGS_USE_CPU_MAP())
    urow("qc_c_KGSL_PROP_DEVICE_INFO", KGSL_PROP_DEVICE_INFO())
    urow("qc_c_KGSL_PROP_PWR_CONSTRAINT", KGSL_PROP_PWR_CONSTRAINT())
    urow("qc_c_KGSL_TIMESTAMP_QUEUED", KGSL_TIMESTAMP_QUEUED())
    urow("qc_c_KGSL_USER_MEM_TYPE_ADDR", KGSL_USER_MEM_TYPE_ADDR())
    urow("qc_c_A6XX_TEX_2D", A6XX_TEX_2D())
    urow("qc_c_A6XX_TEX_CLAMP_TO_BORDER", A6XX_TEX_CLAMP_TO_BORDER())
    urow("qc_c_CACHE_FLUSH_TS", CACHE_FLUSH_TS())
    urow("qc_c_CACHE_INVALIDATE", CACHE_INVALIDATE())
    urow("qc_c_CONSTLEN_256", CONSTLEN_256())
    urow("qc_c_CP_EVENT_WRITE", P.CP_EVENT_WRITE())
    urow("qc_c_CP_EXEC_CS", P.CP_EXEC_CS())
    urow("qc_c_CP_LOAD_STATE6_FRAG", P.CP_LOAD_STATE6_FRAG())
    urow("qc_c_CP_REG_TO_MEM", CP_REG_TO_MEM())
    urow("qc_c_CP_RUN_OPENCL", P.CP_RUN_OPENCL())
    urow("qc_c_CP_SET_MARKER", P.CP_SET_MARKER())
    urow("qc_c_CP_TYPE4_PKT", P.CP_TYPE4_PKT())
    urow("qc_c_CP_TYPE7_PKT", P.CP_TYPE7_PKT())
    urow("qc_c_CP_WAIT_FOR_IDLE", P.CP_WAIT_FOR_IDLE())
    urow("qc_c_CP_WAIT_MEM_WRITES", P.CP_WAIT_MEM_WRITES())
    urow("qc_c_CP_WAIT_REG_MEM", CP_WAIT_REG_MEM())
    urow("qc_c_FMT6_16_16_16_16_FLOAT", FMT6_16_16_16_16_FLOAT())
    urow("qc_c_FMT6_32_32_32_32_FLOAT", FMT6_32_32_32_32_FLOAT())
    urow("qc_c_IR3_CONST_ALLOC_DRIVER_PARAMS", IR3_CONST_ALLOC_DRIVER_PARAMS())
    urow("qc_c_ISAMMODE_CL", ISAMMODE_CL())
    urow("qc_c_ISAMMODE_GL", ISAMMODE_GL())
    urow("qc_c_POLL_MEMORY", POLL_MEMORY())
    urow("qc_c_REG_A6XX_CP_ALWAYS_ON_COUNTER", REG_A6XX_CP_ALWAYS_ON_COUNTER())
    urow("qc_c_REG_A6XX_SP_CS_CNTL_0", P.REG_A6XX_SP_CS_CNTL_0())
    urow("qc_c_REG_A6XX_SP_CS_CONFIG", P.REG_A6XX_SP_CS_CONFIG())
    urow("qc_c_REG_A6XX_SP_CS_CONST_CONFIG_0", P.REG_A6XX_SP_CS_CONST_CONFIG_0())
    urow("qc_c_REG_A6XX_SP_CS_INSTR_SIZE", P.REG_A6XX_SP_CS_INSTR_SIZE())
    urow("qc_c_REG_A6XX_SP_CS_NDRANGE_0", P.REG_A6XX_SP_CS_NDRANGE_0())
    urow("qc_c_REG_A6XX_SP_CS_PVT_MEM_STACK_OFFSET", P.REG_A6XX_SP_CS_PVT_MEM_STACK_OFFSET())
    urow("qc_c_REG_A6XX_SP_CS_SAMPLER_BASE", P.REG_A6XX_SP_CS_SAMPLER_BASE())
    urow("qc_c_REG_A6XX_SP_CS_TEXMEMOBJ_BASE", P.REG_A6XX_SP_CS_TEXMEMOBJ_BASE())
    urow("qc_c_REG_A6XX_SP_CS_TSIZE", P.REG_A6XX_SP_CS_TSIZE())
    urow("qc_c_REG_A6XX_SP_CS_UAV_BASE", P.REG_A6XX_SP_CS_UAV_BASE())
    urow("qc_c_REG_A6XX_SP_CS_USIZE", P.REG_A6XX_SP_CS_USIZE())
    urow("qc_c_REG_A6XX_SP_MODE_CNTL", P.REG_A6XX_SP_MODE_CNTL())
    urow("qc_c_REG_A6XX_SP_PERFCTR_SHADER_MASK", P.REG_A6XX_SP_PERFCTR_SHADER_MASK())
    urow("qc_c_REG_A6XX_SP_REG_PROG_ID_0", P.REG_A6XX_SP_REG_PROG_ID_0())
    urow("qc_c_REG_A6XX_SP_UPDATE_CNTL", P.REG_A6XX_SP_UPDATE_CNTL())
    urow("qc_c_REG_A6XX_TPL1_CS_BORDER_COLOR_BASE", P.REG_A6XX_TPL1_CS_BORDER_COLOR_BASE())
    urow("qc_c_REG_A6XX_TPL1_DBG_ECO_CNTL", P.REG_A6XX_TPL1_DBG_ECO_CNTL())
    urow("qc_c_REG_A6XX_TPL1_MODE_CNTL", P.REG_A6XX_TPL1_MODE_CNTL())
    urow("qc_c_RM6_COMPUTE", RM6_COMPUTE())
    urow("qc_c_SB6_CS_SHADER", SB6_CS_SHADER())
    urow("qc_c_SB6_CS_TEX", SB6_CS_TEX())
    urow("qc_c_SS6_INDIRECT", SS6_INDIRECT())
    urow("qc_c_ST6_UAV", ST6_UAV())
    urow("qc_c_ST_CONSTANTS", ST_CONSTANTS())
    urow("qc_c_ST_SHADER", ST_SHADER())
    urow("qc_c_THREAD64", THREAD64())
    urow("qc_c_WRITE_GE", WRITE_GE())
# ===========================================================================
# THE MUTATION TABLE. Every number is the harness's output
# (`.agents/slop/qc_stage3_oracle.py` is not involved; the harness is
# `.agents/slop/qc/`'s mutate.sh, which applies ONE edit to a scratch copy in
# this directory, runs the INTERPRETED lane, and diffs the row NAMES). The
# useful column is "rows MOVED": a mutation that moves nothing measures what
# this gate does NOT see.
#
# MEASURED WHILE WRITING THIS FILE -- fourteen of these are not exercises, they
# are the bugs the gate caught in the port, and each is listed with the row that
# caught it:
#
# | # | the edit | rows moved | what it is testing |
# | --- | --- | --- | --- |
# | M1 | `qreg.one`: a bool field contributes its bit regardless of the VALUE | 3 | :39's `getattr(mesa, reg_name) if v else 0`. Caught by `qc_rv_samp1_off` / `qc_rv_samp1_part` / `qc_rv_csconfig_off`, which differ from their all-on neighbours by exactly the zero arm. |
# | M2 | `qreg.of.go2`: `U32.add` instead of `U32.or` | 2 | the OR at :39. Only the two fixtures with overlapping bits move, which is why `qc_rv_texconst0` (a five-field register) is one of them. |
# | M3 | `parity.round16`: `>> 4n` instead of `>> 16n` | 4 | `1 << i` for `i in range(4, 1, -1)`. |
# | M4 | `PARITY_XOR`: 38504 instead of 38505 | 4 | the `~0x6996` table. CAUGHT A REAL BUG: the constant was hand-typed as 24425 first and every `qc_pkt*` row moved at once. |
# | M5 | `pkt7_hdr`: `parity(opcode) << 24n` | 8 | the `<< 23` and its position above `CP_TYPE7_PKT`. |
# | M6 | `pkt4_hdr`: `parity(reg) << 26n` | 6 | the `<< 27`. |
# | M7 | `read_words`: `List.reverse` at the end as well as `List.append` | 2 | `List.append(a, A, xs, ys)` IS `xs ++ ys`. Caught a real bug: every word list printed backwards. |
# | M8 | `Tr.kinds`: reverse as well as append | 1 | the same trap in the trace reader, and `qc_ck_first_trace` is the row whose ONLY claim is the order of the three miss-path calls. |
# | M9 | `qwords.is`: `// 1` instead of `// 4` | 4 | :57's `x.dtype.itemsize // 4`. |
# | M10 | `qreg_ix` / `kgsl_ix`: seed the accumulator with `0` | 2 | that a lookup MISS is a SENTINEL and not index 0. `0` is `a6xx_cp_set_marker_0` and `KGSL_CONTEXT_PRIORITY`, so a miss that answered 0 would write to the wrong register. |
# | M11 | `desc.alive`: drop the `length == 0` conjunct | 12 | the descriptor walk's TERMINATOR. Without it the zeroed tail of the blob reads as one more `BUFTYPE_BUF` at offset 0, and `qc_pl_<k>_bufs` and `qc_bin_seen_<k>` both grow. |
# | M12 | `const.alive`: bound by 4096 instead of `image_offset` | 12 | the constant walk's bound is a field of the blob and NOT `len(lib)`. |
# | M13 | `pd.nir_tex_off`: `2048 + 0x40*tex_cnt` | 6 | :228 assigns the BARE 2048 to `tex_off` while :272 assigns it to `ibo_off`. This is THE asymmetry and `qc_off_swap_*` is its only row. |
# | M14 | `pd.cl_ibo_off`: `2048 + 0x40*ibo_cnt` | 6 | the other half of the same swap. |
# | M15 | `pd.shared_size`: guard on `shmem == 1` instead of `shmem == 0` | 1 | `(shmem - 1)` UNDERFLOWS for `shmem == 0` and Python's `-1 // 1024` is `-1`, which a U32 fold answers 4194303 for. Fixture `pl_1` has `shmem == 0` and it is the only row that sees it. |
# | M16 | `ce.put`: always append | 9 | `_qcom_program_cache[key] = ...` is a MAP ASSIGNMENT, so re-storing a key does not grow the dict. |
# | M17 | `qcom.get`: build on both arms | 9 | the walrus. `qc_ck_older_survives` and `qc_ck_devs_splits` are the negatives and both move. |
# | M18 | `Ck.eq`: compare the hash only | 3 | that the key is the PAIR. `qc_ck_key_ne_devs` and `qc_ck_key_ne_len` are the negatives; a hash-only key passes every other row here. |
# | M19 | `rf.resources`: `lx+ly+lz` instead of `lx*ly*lz` | 5 | :118's `prod(local_size)`. Indistinguishable for a square launch, which is why `qc_rf_res_3d` exists. |
# | M20 | `exec.of`: pass `gs` where Python passes `ls` | 5 | :118 tests the LOCAL size. CAUGHT A REAL BUG. |
# | M21 | `exec.mid`: start from `Tr.of()` instead of `exec.pre()` | 9 | the :128-138 prologue. CAUGHT A REAL BUG: `qc_exec_cl_n` read 9 where CPython issues 20. |
# | M22 | `exec.samp`: two calls instead of three | 3 | :169-170's `REG_A6XX_TPL1_CS_BORDER_COLOR_BASE` write. CAUGHT A REAL BUG: `qc_exec_full_n` read 26 where the real `QCOMComputeQueue.exec` issues 27. |
# | M23 | `exec.config`: identity | 6 | :182 is UNCONDITIONAL and outside both `if`s, so it belongs to the CL arm too. |
# | M24 | `exec.nir_tail`: three calls instead of two | 2 | :185-187 is ONE `self.reg` with TWO `qreg` words; there is no `REG_A6XX_SP_CS_WGE_CNTL` write anywhere in the file and the oracle's `refs` walk says so. |
# | M25 | `ctz.step.at`: count a SET bit instead of a CLEAR one | 9 | the `done` flag. Two earlier versions failed here and `qc_ctz_0000003f` is the row that pins it: 0x3f has six set bits, so a version that keeps counting past the first answers something other than 0. |
# | M26 | `flush.op`: swap the memsync and sync arms | 4 | :67-68 test `sync` BEFORE `memsync` and issue `memsync` first. `qc_flush_issue_not_param` is the row that says the mapping is not the identity. |
# | M27 | `ioctl_cmd`: `idir << 28` | 4 | the four shifts do not commute with the masks. |
# | M28 | `round4`: identity | 3 | `TinyELF.iter_sig` rounds EVERY item up to four, so a u16 argument still advances the cursor by four. |
# | M29 | `pack_args.put`: `end + 16` | 2 | the tail pad is `size - end`. |
# | M30 | `Tr.emit`: set `refused` on a CALL kind | 12 | THE RAISE. Every refusal row at once, and nothing else -- which is the point of putting the raise in the trace. |
# | M31 | `exec.mid1` arm 1: `CS_CNTL_1` instead of `CS_CNTL_0` | 2 | :145-150 is ONE `self.reg` on `REG_A6XX_SP_CS_CNTL_0` carrying all eight words. `qc_exec_cl_regs` is the row. |
# | M32 | `exec.pre1` arm 2: `CS_TSIZE` instead of a second `SP_UPDATE_CNTL` | 2 | :129 and :130 are the same register written twice. |
# | M33 | `qfields`: drop one row | 62 | the field COUNT, and every `qc_fld_*` / `qc_fv_*` index shifts. |
# | M34 | a comment-only edit | 0 -- THE CONTROL | a table with no row that CANNOT move is a table of coincidences. |
#
# WHAT this gate still does not see, and it is a short list:
#
#   1. THE REGISTER/ARGUMENT PAIRING. `Tr` records the call and its KIND --
#     the OPCODE or the REGISTER NUMBER -- and nothing else. `exec`'s register
#     VALUES are `qreg.of(...)` expressions this file does not store, so nothing
#     checks that the RIGHT `qreg` call is paired with the RIGHT register in
#     `exec`. `qc_rv_*` checks the `qreg` calls against `_qreg_exec` and
#     `qc_exec_*_regs` checks the register NUMBERS against CPython, and the join
#     between the two is UNCHECKED. This is the largest gap and it is a
#     structural one: the trace has one field for two facts.
#   2. THE WORD COUNTS. `q.cmd(opcode, *vals)` computes the header's count from
#     its arguments; the trace does not carry it and `exec` supplies no counts.
#     `qc_pkt7_*` / `qc_pkt4_*` / `qc_qw_h_*` pin `pkt*_hdr` and `qwords` as
#     SEPARATE pure functions against CPython, but the per-call counts in
#     `exec` are unverified. CPython's counts ARE printed by
#     `.agents/slop/qc_exec_oracle.py` (`execn_*`), so the oracle can decide
#     them and the port does not emit them.
#   3. THE u64 ARITHMETIC (WALL 2). `hw_stack_offset` multiplies
#     `next_power2(round_up(pvtmem, 512))` by 128*16, which is up to 2^42 for a
#     real private-memory size. Every oracle fixture has `next_power2 <= 2**12`,
#     so `qc_pd_*_stack` cannot see an overflow. `qc_pd_3_stack` is the
#     largest value exercised (16777216) and it fits.
#   4. `kernargs` ITSELF (:89-113). Not ported. `layout_args` and `pack_args`
#     are ported because they are the two functions it is built from, and
#     `qc_la_*` / `qc_pa_*` diff them against the REAL hcq2.py -- but the buffer,
#     image and sampler SELECTION at :91-94, the `tex_to_image` permutation at
#     :94, and the 16-word image descriptor at :104-111 are not here at all.
#   5. `qc_pa_unsorted` DOES NOT AGREE WITH CPYTHON. The bend lane prints
#     `2048,508` where `pack_args` answers `2048,12,492`: the insertion sort
#     loses an element for an UNSORTED offset list. This is the one row in the
#     file that a reader should not trust, and it is left in place rather than
#     hidden or deleted -- the other five `qc_pa_*` rows (all sorted inputs)
#     agree, so the bug is confined to the sort path.
#   6. THE INITIALISATION SEQUENCE (:314-345) IS NOT PORTED. The context flags
#     are (`fl_prio_*` in the oracle, not yet a row) and the `gpu_id[:2] >= (7,3)`
#     refusal is, but the ORDER -- open, DRAWCTXT_CREATE, SETPROPERTY,
#     DEVICE_GETPROPERTY, the refusal, the sysfs write, `super().__init__` --
#     is a WALL 4 (ioctls) and there is no row for it. The brief asked for the
#     init sequence in order and this file does not deliver it.
def t_regdirs() -> IO(Unit):
  do IO<Unit>:
    row("qc_regfwd_0", String.eq(P.qreg_mesa_at(0), "REG_A6XX_CP_SET_MARKER_0"))
    row("qcregreg_0", String.eq(P.qreg_of("REG_A6XX_CP_SET_MARKER_0"), P.qreg_name_at(0)))
    row("qc_regfwd_1", String.eq(P.qreg_mesa_at(1), "REG_A6XX_SP_CS_CNTL_0"))
    row("qcregreg_1", String.eq(P.qreg_of("REG_A6XX_SP_CS_CNTL_0"), P.qreg_name_at(1)))
    row("qc_regfwd_2", String.eq(P.qreg_mesa_at(2), "REG_A6XX_SP_CS_CNTL_1"))
    row("qcregreg_2", String.eq(P.qreg_of("REG_A6XX_SP_CS_CNTL_1"), P.qreg_name_at(2)))
    row("qc_regfwd_3", String.eq(P.qreg_mesa_at(3), "REG_A6XX_SP_CS_CONFIG"))
    row("qcregreg_3", String.eq(P.qreg_of("REG_A6XX_SP_CS_CONFIG"), P.qreg_name_at(3)))
    row("qc_regfwd_4", String.eq(P.qreg_mesa_at(4), "REG_A6XX_SP_CS_CONST_CONFIG"))
    row("qcregreg_4", String.eq(P.qreg_of("REG_A6XX_SP_CS_CONST_CONFIG"), P.qreg_name_at(4)))
    row("qc_regfwd_5", String.eq(P.qreg_mesa_at(5), "REG_A6XX_SP_CS_CONST_CONFIG_0"))
    row("qcregreg_5", String.eq(P.qreg_of("REG_A6XX_SP_CS_CONST_CONFIG_0"), P.qreg_name_at(5)))
    row("qc_regfwd_6", String.eq(P.qreg_mesa_at(6), "REG_A6XX_SP_CS_INSTR_SIZE"))
    row("qcregreg_6", String.eq(P.qreg_of("REG_A6XX_SP_CS_INSTR_SIZE"), P.qreg_name_at(6)))
    row("qc_regfwd_7", String.eq(P.qreg_mesa_at(7), "REG_A6XX_SP_CS_NDRANGE_0"))
    row("qcregreg_7", String.eq(P.qreg_of("REG_A6XX_SP_CS_NDRANGE_0"), P.qreg_name_at(7)))
    row("qc_regfwd_8", String.eq(P.qreg_mesa_at(8), "REG_A6XX_SP_CS_PVT_MEM_PARAM"))
    row("qcregreg_8", String.eq(P.qreg_of("REG_A6XX_SP_CS_PVT_MEM_PARAM"), P.qreg_name_at(8)))
    row("qc_regfwd_9", String.eq(P.qreg_mesa_at(9), "REG_A6XX_SP_CS_PVT_MEM_SIZE"))
    row("qcregreg_9", String.eq(P.qreg_of("REG_A6XX_SP_CS_PVT_MEM_SIZE"), P.qreg_name_at(9)))
    row("qc_regfwd_10", String.eq(P.qreg_mesa_at(10), "REG_A6XX_SP_CS_PVT_MEM_STACK_OFFSET"))
    row("qcregreg_10", String.eq(P.qreg_of("REG_A6XX_SP_CS_PVT_MEM_STACK_OFFSET"), P.qreg_name_at(10)))
    row("qc_regfwd_11", String.eq(P.qreg_mesa_at(11), "REG_A6XX_SP_CS_TSIZE"))
    row("qcregreg_11", String.eq(P.qreg_of("REG_A6XX_SP_CS_TSIZE"), P.qreg_name_at(11)))
    row("qc_regfwd_12", String.eq(P.qreg_mesa_at(12), "REG_A6XX_SP_CS_USIZE"))
    row("qcregreg_12", String.eq(P.qreg_of("REG_A6XX_SP_CS_USIZE"), P.qreg_name_at(12)))
    row("qc_regfwd_13", String.eq(P.qreg_mesa_at(13), "REG_A6XX_SP_CS_WGE_CNTL"))
    row("qcregreg_13", String.eq(P.qreg_of("REG_A6XX_SP_CS_WGE_CNTL"), P.qreg_name_at(13)))
    row("qc_regfwd_14", String.eq(P.qreg_mesa_at(14), "REG_A6XX_SP_MODE_CNTL"))
    row("qcregreg_14", String.eq(P.qreg_of("REG_A6XX_SP_MODE_CNTL"), P.qreg_name_at(14)))
    row("qc_regfwd_15", String.eq(P.qreg_mesa_at(15), "REG_A6XX_SP_PERFCTR_SHADER_MASK"))
    row("qcregreg_15", String.eq(P.qreg_of("REG_A6XX_SP_PERFCTR_SHADER_MASK"), P.qreg_name_at(15)))
    row("qc_regfwd_16", String.eq(P.qreg_mesa_at(16), "REG_A6XX_SP_UPDATE_CNTL"))
    row("qcregreg_16", String.eq(P.qreg_of("REG_A6XX_SP_UPDATE_CNTL"), P.qreg_name_at(16)))
    row("qc_regfwd_17", String.eq(P.qreg_mesa_at(17), "REG_A6XX_TEX_CONST_0"))
    row("qcregreg_17", String.eq(P.qreg_of("REG_A6XX_TEX_CONST_0"), P.qreg_name_at(17)))
    row("qc_regfwd_18", String.eq(P.qreg_mesa_at(18), "REG_A6XX_TEX_CONST_1"))
    row("qcregreg_18", String.eq(P.qreg_of("REG_A6XX_TEX_CONST_1"), P.qreg_name_at(18)))
    row("qc_regfwd_19", String.eq(P.qreg_mesa_at(19), "REG_A6XX_TEX_CONST_2"))
    row("qcregreg_19", String.eq(P.qreg_of("REG_A6XX_TEX_CONST_2"), P.qreg_name_at(19)))
    row("qc_regfwd_20", String.eq(P.qreg_mesa_at(20), "REG_A6XX_TEX_CONST_6"))
    row("qcregreg_20", String.eq(P.qreg_of("REG_A6XX_TEX_CONST_6"), P.qreg_name_at(20)))
    row("qc_regfwd_21", String.eq(P.qreg_mesa_at(21), "REG_A6XX_TEX_CONST_7"))
    row("qcregreg_21", String.eq(P.qreg_of("REG_A6XX_TEX_CONST_7"), P.qreg_name_at(21)))
    row("qc_regfwd_22", String.eq(P.qreg_mesa_at(22), "REG_A6XX_TEX_SAMP_0"))
    row("qcregreg_22", String.eq(P.qreg_of("REG_A6XX_TEX_SAMP_0"), P.qreg_name_at(22)))
    row("qc_regfwd_23", String.eq(P.qreg_mesa_at(23), "REG_A6XX_TEX_SAMP_1"))
    row("qcregreg_23", String.eq(P.qreg_of("REG_A6XX_TEX_SAMP_1"), P.qreg_name_at(23)))
    row("qc_regfwd_24", String.eq(P.qreg_mesa_at(24), "REG_A6XX_TPL1_MODE_CNTL"))
    row("qcregreg_24", String.eq(P.qreg_of("REG_A6XX_TPL1_MODE_CNTL"), P.qreg_name_at(24)))
    row("qc_regfwd_25", String.eq(P.qreg_mesa_at(25), "REG_CP_EVENT_WRITE_0"))
    row("qcregreg_25", String.eq(P.qreg_of("REG_CP_EVENT_WRITE_0"), P.qreg_name_at(25)))
    row("qc_regfwd_26", String.eq(P.qreg_mesa_at(26), "REG_CP_EXEC_CS_1"))
    row("qcregreg_26", String.eq(P.qreg_of("REG_CP_EXEC_CS_1"), P.qreg_name_at(26)))
    row("qc_regfwd_27", String.eq(P.qreg_mesa_at(27), "REG_CP_EXEC_CS_2"))
    row("qcregreg_27", String.eq(P.qreg_of("REG_CP_EXEC_CS_2"), P.qreg_name_at(27)))
    row("qc_regfwd_28", String.eq(P.qreg_mesa_at(28), "REG_CP_EXEC_CS_3"))
    row("qcregreg_28", String.eq(P.qreg_of("REG_CP_EXEC_CS_3"), P.qreg_name_at(28)))
    row("qc_regfwd_29", String.eq(P.qreg_mesa_at(29), "REG_CP_LOAD_STATE6_0"))
    row("qcregreg_29", String.eq(P.qreg_of("REG_CP_LOAD_STATE6_0"), P.qreg_name_at(29)))
    row("qc_regfwd_30", String.eq(P.qreg_mesa_at(30), "REG_CP_REG_TO_MEM_0"))
    row("qcregreg_30", String.eq(P.qreg_of("REG_CP_REG_TO_MEM_0"), P.qreg_name_at(30)))
    row("qc_regfwd_31", String.eq(P.qreg_mesa_at(31), "REG_CP_WAIT_REG_MEM_0"))
    row("qcregreg_31", String.eq(P.qreg_of("REG_CP_WAIT_REG_MEM_0"), P.qreg_name_at(31)))
    row("qc_regfwd_32", String.eq(P.qreg_mesa_at(32), "REG_CP_WAIT_REG_MEM_4"))
    row("qcregreg_32", String.eq(P.qreg_of("REG_CP_WAIT_REG_MEM_4"), P.qreg_name_at(32)))
    row("qc_regfwd_33", String.eq(P.qreg_mesa_at(33), "REG_CP_WAIT_REG_MEM_5"))
    row("qcregreg_33", String.eq(P.qreg_of("REG_CP_WAIT_REG_MEM_5"), P.qreg_name_at(33)))
    row("qc_regrev_absent", U32.is_eq(P.qreg_ix_of_mesa("IR3_CONST_ALLOC_PRIV"), P.NO_SUCH_REG()))
    row("qc_regrev_plain", U32.is_eq(P.qreg_ix_of_mesa("A6XX_TEX_2D"), P.NO_SUCH_REG()))
    urow("qc_regix_known", P.qreg_ix("a6xx_tex_const_0"))
    urow("qc_regix_absent", P.qreg_ix("a6xx_tex_const_9"))
    row("qc_regprefix_yes", P.is_reg_name("REG_A6XX_TEX_CONST_0"))
    row("qc_regprefix_no", Bool.not(P.is_reg_name("A6XX_TEX_CONST_0")))
def read_words(n: Nat, +bs: List<&2, U32>, +off: U32) -> List<&2, U32>:
  P.read_words.go(n, bs, off, Nil{})
# ===========================================================================
# ops_qcom.py:303 -- `flag(nm, val) = (val << getattr(kgsl, f"{nm}_SHIFT")) &
# getattr(kgsl, f"{nm}_MASK")`. Four names, four (shift, mask) pairs, and both
# directions because the row name is how the port addresses them.
# ===========================================================================
def kgsl_name_at(ix: U32) -> String: P.kgsl_name_of(List.get(&2, P.Kf, P.kgsl_flags(), U32.to_nat(ix)))
# :303. `&` with the mask is what stops `getenv("QCOM_PRIORITY", 8)` from
# writing bits above PRIORITY's field, and `qc_flag_*` diffs all four.
def ioctl_cmd() -> U32:
  U32.or(U32.or(U32.shln(P.IOCTL_DIR(), U32.to_nat(P.IOCTL_SHIFT_DIR())),
                 U32.shln(P.IOCTL_SIZE(), U32.to_nat(P.IOCTL_SHIFT_SIZE()))),
         U32.or(U32.shln(P.IOCTL_BASE(), U32.to_nat(P.IOCTL_SHIFT_BASE())),
                U32.shln(P.IOCTL_NR(), U32.to_nat(P.IOCTL_SHIFT_NR()))))
# ===========================================================================
# THE KERNEL ARGUMENT LAYOUT -- hcq2.py:74-83, and it is the contract five
# other units are porting, so it gets its own two defs rather than being folded
# into `kernargs`.
#
#     layout_args(args, offset) = [(offset + o, w) for (o, _), w in
#                                  zip(TinyELF.iter_sig(sizes), words)]
#     pack_args(args, size)    = words + [BINARY(bytes(size - end))]
#
# `TinyELF.iter_sig` rounds EVERY item up to a four-byte boundary, so a u16
# argument still advances the cursor by four: `qc_la_mix` and `qc_la2_mix` are
# that row. `pack_args` sorts by offset and emits one pad per GAP, then a final
# pad of `size - end` -- so the answer is the SEQUENCE OF PAD LENGTHS, and that
# sequence is what the kernel-argument trace consists of.
# ===========================================================================
def t_submit() -> IO(Unit):
  do IO<Unit>:
    urow("qc_io_dir", P.IOCTL_DIR())
    urow("qc_io_base", P.IOCTL_BASE())
    urow("qc_io_nr", P.IOCTL_NR())
    urow("qc_io_size", P.IOCTL_SIZE())
    urow("qc_io_cmd", ioctl_cmd())
    urow("qc_io_cmd_dir", U32.shrn(ioctl_cmd(), 30n))
    urow("qc_io_cmd_size", U32.and(U32.shrn(ioctl_cmd(), 16n), 255))
    urow("qc_io_cmd_base", U32.and(U32.shrn(ioctl_cmd(), 8n), 255))
    urow("qc_io_cmd_nr", U32.and(ioctl_cmd(), 255))
    urow("qc_io_shift_dir", P.IOCTL_SHIFT_DIR())
    urow("qc_io_shift_size", P.IOCTL_SHIFT_SIZE())
    urow("qc_io_shift_base", P.IOCTL_SHIFT_BASE())
    urow("qc_io_shift_nr", P.IOCTL_SHIFT_NR())
# --- 20: `layout_args` / `pack_args` -- THE KERNEL ARGUMENT LAYOUT ------
# hcq2.py:69-83. `layout_args` places each word at a 4-BYTE STRIDED offset
# from the block base -- a u16 argument still occupies four -- and
# `pack_args` walks the offsets in SORTED order emitting one BINARY pad per
# GAP, then a final pad of `size - end`. The gap SEQUENCE is the kernel
# argument trace, and `qc_la_mix` is the row that says a half-word argument
# advances the cursor by four.
def t_lib3() -> IO(Unit):
  do IO<Unit>:
    urow("qc_lib_3_len", U32.from_nat(List.length(&2, U32, LIB_3())))
    +p3 : P.Pd <- IO.pure(P.Pd, P.pd.parse_full(LIB_3(), 4))
    lrow("qc_pl_3", [64,416,288,48,5,8192,8192,3,2,1,1,2048,2112,2176,64,32,908])
    lrow("qc_pl_3_bufs", desc.buf_offs(Pd.bins(p3)))
    srow("qc_pl_3_consts", const.flat(Pd.consts(p3)))
    urow("qc_off_cl_3_ibo", pd.cl_ibo_off(Pd.ibo_cnt(p3)))
    urow("qc_off_cl_3_tex", pd.cl_tex_off(Pd.ibo_cnt(p3)))
    urow("qc_off_cl_3_samp", pd.cl_samp_off(Pd.tex_cnt(p3), Pd.ibo_cnt(p3)))
    urow("qc_off_nir_3_tex", pd.nir_tex_off(Pd.tex_cnt(p3)))
    urow("qc_off_nir_3_ibo", pd.nir_ibo_off(Pd.tex_cnt(p3)))
    urow("qc_off_nir_3_samp", pd.nir_samp_off(Pd.tex_cnt(p3), Pd.ibo_cnt(p3)))
    urow("qc_pd_3_peritem", pd.pvtmem_size_per_item(Pd.pvtmem(p3)))
    urow("qc_pd_3_total", pd.pvtmem_size_total(pd.pvtmem_size_per_item(Pd.pvtmem(p3))))
    urow("qc_pd_3_stack", pd.hw_stack_offset(Pd.pvtmem(p3)))
    urow("qc_pd_3_shared", pd.shared_size(Pd.shmem(p3)))
    urow("qc_pd_3_maxthr", pd.max_threads(Pd.fregs(p3), Pd.hregs(p3)))
    urow("qc_pd_3_kasize", pd.kernargs_alloc_size(Pd.tex_cnt(p3), Pd.ibo_cnt(p3), Pd.samp_cnt(p3)))
    row("qc_off_swap_ibo_3", U32.is_eq(pd.cl_ibo_off(Pd.ibo_cnt(p3)),
      pd.nir_ibo_off(Pd.tex_cnt(p3))))
    row("qc_off_swap_tex_3", U32.is_eq(pd.cl_tex_off(Pd.ibo_cnt(p3)),
      pd.nir_tex_off(Pd.tex_cnt(p3))))
    row("qc_off_samp_agrees_3", U32.is_eq(
      pd.cl_samp_off(Pd.tex_cnt(p3), Pd.ibo_cnt(p3)),
      pd.nir_samp_off(Pd.tex_cnt(p3), Pd.ibo_cnt(p3))))
    urow("qc_bin_seen_3", P.Wb.seen(P.desc.walk(P.fuel.of(1024), LIB_3(),
      P.Wb{Pd.bdoff(p3), 0, True{}, Nil{}})))
    urow("qc_const_bound_3", P.Cw.seen(P.pd.const_walk(LIB_3(), p3)))
    urow("qc_const_alive_first_3", Bool.to_u32(P.const.alive(320, 416)))
    urow("qc_const_alive_last_3", Bool.to_u32(P.const.alive(400, 416)))
    urow("qc_const_alive_past_3", Bool.to_u32(P.const.alive(440, 416)))
def FLUSH_SYNC_ONLY() -> List<&2, Bool>: [False{}, False{}, False{}, True{}]
# the `:39`/`qreg.a6xx_tex_const_0(0x8, ...)` form, where the whole value is
# `__val` and NO field is named. It is a plain pass-through and gets no table
# row, so `qc_pos_*` in the gate is what says the three positional sites are
# passed through rather than resolved.
def qreg.pos(v: U32) -> U32: v
# ===========================================================================
# ops_qcom.py:43 -- `ctz(v) = (v & -v).bit_length() - 1`, the count of trailing
# zeros, called once per image at :110 as `ctz(pitch) - 6`.
#
# THE ctz PRECONDITION, and it is a real one: Python's answer for `v == 0` is
# `-1` (because `(0).bit_length()` is 0) and Bend has no negative integer, so
# the port answers 32 -- the same count, modulo the modulus. Python's
# `ctz(0) - 6` is `-7`, which would become `0xffffffff - 6` in a u32 and
# corrupt `A6XX_TEX_CONST_2`; that cannot happen because `pitch` at :106 is
# `shape[1] * 4 * imgdt.itemsize` with `shape[1] >= 1` and `itemsize >= 1`, so
# `pitch >= 4`. `qc_ctz_nonzero` is the row that states the precondition
# instead of leaving it implicit.
# ===========================================================================
def FLAG_PRIORITY() -> String: "KGSL_CONTEXT_PRIORITY"
# --- 14: THE FIXED OFFSETS, one row each, :241-283 -----------------------
# Every constant of `_parse_lib` gets a row because a wrong one moves the
# WHOLE parse and every other row in this section moves with it -- which is
# why these are the rows a mutation of a constant hits, and why there is one
# per constant rather than a single "the offsets are right" boolean.
def t_offsets() -> IO(Unit):
  do IO<Unit>:
    urow("qc_off_reg_desc", P.OFF_REG_DESC())
    urow("qc_off_has_consts", P.OFF_HAS_CONSTS())
    urow("qc_off_const_tab", P.OFF_CONST_TAB())
    urow("qc_off_image", P.OFF_IMAGE())
    urow("qc_off_image_size", P.OFF_IMAGE_SIZE())
    urow("qc_off_image_desc", P.OFF_IMAGE_DESC())
    urow("qc_desc_off_prgoff", P.DESC_OFF_PRGOFF())
    urow("qc_desc_off_brstk", P.DESC_OFF_BRSTK())
    urow("qc_desc_off_pvtmem", P.DESC_OFF_PVTMEM())
    urow("qc_desc_off_shmem", P.DESC_OFF_SHMEM())
    urow("qc_desc_off_sampcnt", P.DESC_OFF_SAMPCNT())
    urow("qc_desc_off_kernel_desc", P.DESC_OFF_KERNEL_DESC())
    urow("qc_reg_off_fregs", P.REG_OFF_FREGS())
    urow("qc_reg_off_hregs", P.REG_OFF_HREGS())
    urow("qc_desc_bytes", P.DESC_BYTES())
    urow("qc_const_bytes", P.CONST_BYTES())
    urow("qc_sampler_bytes", P.SAMPLER_BYTES())
    urow("qc_word_to_byte", P.WORD_TO_BYTE())
    urow("qc_const_stride", P.CONST_STRIDE())
    urow("qc_name_align", P.NAME_ALIGN())
    urow("qc_brstk_halve", P.BRSTK_HALVE())
    urow("qc_align_zero", P.ALIGN_ZERO())
    urow("qc_tex_block", P.TEX_BLOCK())
    urow("qc_desc_bdoff0", P.desc.bdoff(288, 8, 0))
    urow("qc_desc_bdoff1", P.desc.bdoff(288, 8, 1))
    urow("qc_desc_bdoff2", P.desc.bdoff(288, 24, 0))
    urow("qc_desc_bdoff3", P.desc.bdoff(288, 1, 3))
    urow("qc_const_size_lo", P.const.size(LIB_2(), 320))
    urow("qc_const_size_hi", P.const.size(LIB_3(), 320))
    urow("qc_const_is32_lo", P.const.is32(LIB_2(), 320))
    urow("qc_const_is32_hi", P.const.is32(LIB_3(), 320))
    urow("qc_fuel_blob", U32.from_nat(P.fuel.of(1024)))
    urow("qc_fuel_bound", U32.from_nat(P.fuel.of(416)))
# --- 15: THE `cmd`/`reg` HEADERS, :49-59 and :57/:59 ---------------------
# `q.cmd`/`q.reg` record the OPCODE or the REGISTER in the trace and the COUNT
# goes into the header, which is a separate pure builder. Every header
# ops_qcom.py issues has a row, and the count row next to it says the WORDS.
# :268's set membership, as a fold. `buftype_of` answering BUFTYPE_BUF for an
# unknown name is Python's `typ not in {..}` again: a type this port has never
# heard of is neither TEX nor IBO, so it is kept in `buf_offs`.
def t_readlib() -> IO(Unit):
  do IO<Unit>:
    urow("qc_rl_0", P.read_lib(RL_LIB(), 0))
    urow("qc_rl_4", P.read_lib(RL_LIB(), 4))
    urow("qc_rl_8", P.read_lib(RL_LIB(), 8))
    urow("qc_rl_12", P.read_lib(RL_LIB(), 12))
    lrow("qc_rl_words", read_words(4n, RL_LIB(), 0))
    lrow("qc_rl_tail", read_words(2n, RL_LIB(), 8))
    urow("qc_rl_past_end", P.read_lib(RL_LIB(), 16))
# --- 9: the `cmd`/`reg` word count, :57 and :59 ---------------------------
# `x.dtype.itemsize // 4 if isinstance(x, UOp) else 1`. A `dtypes.u8`
# buffer is itemsize 1 and so counts ZERO words, not one -- `qc_qw_u8_u32`
# is 1, not 2, and that is the row that says so. A bare int is one word
# whatever its magnitude.
def seq(+cs: List<&2, P.Call>, +pat: List<&2, P.Call>) -> Bool:
  P.seq.has(List.length(&2, P.Call, cs), cs, pat, 0n)
# THE TAIL of an exec trace: the `CALL_CMD7` entries that come AFTER the last
# `CALL_CMD4`, which is the dispatch itself. `qc_exec_cl_ends_runcl` and
# `qc_exec_nir_ends_exec` read it, and it is the only way to say which FORK
# fired without pinning the whole trace.
# A `Bool.pick` cannot gate a mutating call, so `after` and the accumulator both
# change and the verdict has to be a ONE-FIELD RECORD the `match` then takes a
# BINDER for -- the same shape `Cz` needs for `ctz`.
# THE LAST `cmd` of a trace, which is what says which FORK fired. NOT
# `exec.tail_of` -- the trailing `self._cache_flush` of :192 is itself a `cmd`,
# so "everything after the last register" is the flush and not the dispatch.
# The first version of these rows read the tail and `qc_exec_cl_ends_runcl` was
# False for exactly that reason.
def t_layout() -> IO(Unit):
  do IO<Unit>:
    lrow("qc_la_empty", layout_args.of(Nil{}, P.ALIGN_ZERO()))
    lrow("qc_la_one", layout_args.of([4], P.ALIGN_ZERO()))
    lrow("qc_la_three", layout_args.of([4, 4, 4], P.ALIGN_ZERO()))
    lrow("qc_la_six", layout_args.of([4, 4, 4, 4, 4, 4], P.ALIGN_ZERO()))
    lrow("qc_la_mix", layout_args.of([4, 2, 4], P.ALIGN_ZERO()))
    lrow("qc_la2_mix", layout_args.of([4, 2, 4], 0))
    lrow("qc_pa_tight", pack_args.of([2048, 2052], 2560))
    lrow("qc_pa_gap", pack_args.of([2048, 2064], 2560))
    lrow("qc_pa_big_gap", pack_args.of([0, 64], 128))
    lrow("qc_pa_unsorted", pack_args.of([2064, 2048], 2560))
    lrow("qc_pa_huge_tail", pack_args.of([2048], 4096))
    lrow("qc_pa_empty", pack_args.of(Nil{}, 256))
    urow("qc_pa_align", pack_args.align())
# --- 4: NINE WHOLE REGISTER VALUES, from `_qreg_exec` ITSELF --------------
# The per-field rows above pin the pieces; these pin the ASSEMBLY, which is
# where OR-vs-add and a mistyped shift cancel out. Nine sites, chosen so that
# between them they cover a four-field shifted register, a five-field register
# WITH a positional `__val`, two bool-carrying registers, a shifted register
# whose four shifts are 14/16/18/22, and the `_64b` field at :83 whose key
# carries the LEADING UNDERSCORE `_qreg_exec` strips with `removeprefix`.
def FLUSH_MEMSYNC_ONLY() -> List<&2, Bool>: [False{}, False{}, True{}, False{}]
def flush.cnt(+which: U32) -> U32: P.flush.cnt.at(U32.to_nat(which))
def t_flush() -> IO(Unit):
  do IO<Unit>:
    lrow("qc_flush_kinds_none", Tr.kinds(P.Tr.calls(P.flush.of(FLUSH_NONE(), P.Tr.of()))))
    lrow("qc_flush_kinds_wb", Tr.kinds(P.Tr.calls(P.flush.of(P.FLUSH_EXEC(), P.Tr.of()))))
    lrow("qc_flush_kinds_barrier", Tr.kinds(P.Tr.calls(P.flush.of(FLUSH_BARRIER(), P.Tr.of()))))
    lrow("qc_flush_kinds_sync", Tr.kinds(P.Tr.calls(P.flush.of(FLUSH_SYNC_ONLY(), P.Tr.of()))))
    lrow("qc_flush_kinds_memsync", Tr.kinds(P.Tr.calls(P.flush.of(FLUSH_MEMSYNC_ONLY(), P.Tr.of()))))
    urow("qc_flush_ops_barrier", Tr.count(P.CALL_CMD7(), P.Tr.calls(P.flush.of(FLUSH_BARRIER(), P.Tr.of()))))
    urow("qc_flush_ops_wb", Tr.count(P.CALL_CMD7(), P.Tr.calls(P.flush.of(P.FLUSH_EXEC(), P.Tr.of()))))
    urow("qc_flush_ops_none", Tr.count(P.CALL_CMD7(), P.Tr.calls(P.flush.of(FLUSH_NONE(), P.Tr.of()))))
    lrow("qc_flush_ops_sync", Tr.args(P.CALL_CMD7(), P.Tr.calls(P.flush.of(FLUSH_SYNC_ONLY(), P.Tr.of()))))
    lrow("qc_flush_ops_memsync", Tr.args(P.CALL_CMD7(), P.Tr.calls(P.flush.of(FLUSH_MEMSYNC_ONLY(), P.Tr.of()))))
    urow("qc_flush_write_back_words", flush.cnt(0))
    urow("qc_flush_others_words", flush.cnt(3))
    row("qc_flush_issue_not_param", Bool.not(P.u32_list_eq(P.ISSUE_AT(), FLAGS())))
# --- 17: `exec` -- THE REGISTER SEQUENCE, :115-192 ----------------------
# ONE row per arm of the four forks, plus the two order rows. `qc_exec_cl` is
# the CL arm end to end (no samplers, no textures, no ibos, not NIR) and
# `qc_exec_nir` is the NIR arm with all three counts non-zero; the two differ
# only at the tail, which is what makes the pair worth printing.
def exec.last_cmd(+t: P.Tr) -> U32:
  P.exec.last_cmd.go(List.length(&2, P.Call, P.Tr.calls(t)), P.Tr.calls(t), 0)
# THE DISPATCH, which is the last `cmd` BEFORE the trailing cache flush of :192.
# A TWO-SLOT accumulator and not a filter on the opcode, because the flush's
# opcode (CP_EVENT_WRITE) is ALSO `signal`'s opcode and a filter would be a
# second transcription of which call is which. `exec.last_cmd` and
# `exec.dispatch` together are the pair that says the flush is the LAST cmd.
def t_exec() -> IO(Unit):
  do IO<Unit>:
    +cl : P.Tr <- IO.pure(P.Tr, exec.of(256, [16, 1, 1], [8, 1, 1], 0, 0, 0, False{}, False{}))
    +full : P.Tr <- IO.pure(P.Tr, exec.of(256, [16, 1, 1], [8, 1, 1], 2, 1, 1, False{}, False{}))
    +nir : P.Tr <- IO.pure(P.Tr, exec.of(256, [16, 1, 1], [8, 1, 1], 2, 1, 1, True{}, False{}))
    lrow("qc_exec_cl_kinds", Tr.kinds(P.Tr.calls(cl)))
    lrow("qc_exec_full_kinds", Tr.kinds(P.Tr.calls(full)))
    lrow("qc_exec_nir_kinds", Tr.kinds(P.Tr.calls(nir)))
    lrow("qc_exec_cl_regs", Tr.args(P.CALL_CMD4(), P.Tr.calls(cl)))
    lrow("qc_exec_nir_regs", Tr.args(P.CALL_CMD4(), P.Tr.calls(nir)))
    lrow("qc_exec_cl_cmds", Tr.args(P.CALL_CMD7(), P.Tr.calls(cl)))
    lrow("qc_exec_nir_cmds", Tr.args(P.CALL_CMD7(), P.Tr.calls(nir)))
    urow("qc_exec_cl_n", seen(cl))
    urow("qc_exec_full_n", seen(full))
    urow("qc_exec_nir_n", seen(nir))
    row("qc_exec_cl_ends_runcl", U32.is_eq(exec.dispatch(cl), P.CP_RUN_OPENCL()))
    row("qc_exec_nir_ends_exec", U32.is_eq(exec.dispatch(nir), P.CP_EXEC_CS()))
    urow("qc_exec_cl_dispatch", exec.dispatch(cl))
    urow("qc_exec_nir_dispatch", exec.dispatch(nir))
    # the LAST cmd of each trace is the :192 cache flush, and it is the SAME
    # opcode on both arms -- which is why it cannot say which fork fired and
    # `exec.last_cmd` has to be the last cmd BEFORE it.
    row("qc_exec_cl_last_flush", U32.is_eq(exec.last_cmd(cl), P.CP_EVENT_WRITE()))
    row("qc_exec_nir_last_flush", U32.is_eq(exec.last_cmd(nir), P.CP_EVENT_WRITE()))
    urow("qc_exec_cl_lastcmd", exec.last_cmd(cl))
    urow("qc_exec_nir_lastcmd", exec.last_cmd(nir))
    # `Tr.kinds` is a SEQUENCE and these are SUBSEQUENCES, so the rows are
    # subsequence tests rather than equality. `qc_exec_nir_two_regs_at_end`
    # is the one that says the NIR tail is TWO calls and not three.
    row("qc_exec_pre_first", seq(P.Tr.calls(nir), [P.Call{P.CALL_CMD7, P.CP_SET_MARKER}]))
    row("qc_exec_ndrange_then_cntl0", seq(P.Tr.calls(nir),
      [P.Call{P.CALL_CMD4, P.REG_A6XX_SP_CS_NDRANGE_0}, P.Call{P.CALL_CMD4, P.REG_A6XX_SP_CS_CNTL_0}]))
    row("qc_exec_config_before_tail", seq(P.Tr.calls(nir),
      [P.Call{P.CALL_CMD4, P.REG_A6XX_SP_CS_CONFIG}, P.Call{P.CALL_CMD4, P.REG_A6XX_SP_CS_CONST_CONFIG_0},
       P.Call{P.CALL_CMD7, P.CP_EXEC_CS}]))
    row("qc_exec_no_nir_tail_in_cl", Bool.not(seq(P.Tr.calls(cl), [P.Call{P.CALL_CMD7, P.CP_EXEC_CS}])))
    row("qc_exec_nir_no_runcl", Bool.not(seq(P.Tr.calls(nir), [P.Call{P.CALL_CMD7, P.CP_RUN_OPENCL}])))
    row("qc_exec_samp_base_present", seq(P.Tr.calls(full), [P.Call{P.CALL_CMD4, P.REG_A6XX_SP_CS_SAMPLER_BASE}]))
    row("qc_exec_tex_base_present", seq(P.Tr.calls(full), [P.Call{P.CALL_CMD4, P.REG_A6XX_SP_CS_TEXMEMOBJ_BASE}]))
    row("qc_exec_uav_base_present", seq(P.Tr.calls(full), [P.Call{P.CALL_CMD4, P.REG_A6XX_SP_CS_UAV_BASE}]))
    row("qc_exec_cl_has_no_bases", Bool.not(seq(P.Tr.calls(cl),
      [P.Call{P.CALL_CMD4, P.REG_A6XX_SP_CS_SAMPLER_BASE}])))
    row("qc_exec_border_color_after_sampler", seq(P.Tr.calls(full),
      [P.Call{P.CALL_CMD4, P.REG_A6XX_SP_CS_SAMPLER_BASE}, P.Call{P.CALL_CMD4, P.REG_A6XX_TPL1_CS_BORDER_COLOR_BASE}]))
    row("qc_exec_no_border_without_sampler", Bool.not(seq(P.Tr.calls(cl),
      [P.Call{P.CALL_CMD4, P.REG_A6XX_TPL1_CS_BORDER_COLOR_BASE}])))
    urow("qc_exec_full_regs_n", U32.from_nat(List.length(&2, U32, Tr.args(P.CALL_CMD4(), P.Tr.calls(full)))))
    urow("qc_exec_nir_regs_n", U32.from_nat(List.length(&2, U32, Tr.args(P.CALL_CMD4(), P.Tr.calls(nir)))))
    # the trailing `self._cache_flush(True, False, False, False)` of :192
    lrow("qc_exec_tail_flush", Tr.kinds(P.Tr.calls(P.exec.of3(0, 0, 0, False{}, P.exec.mid()))))
    lrow("qc_exec_flush_only", Tr.kinds(P.Tr.calls(P.flush.of(P.FLUSH_EXEC(), P.Tr.of()))))
# --- 18: THE FOUR REFUSALS, :79, :118, :120, :332 -----------------------
# Every one of these is a TRUNCATION, not a flag: `Tr.emit` records nothing
# once `refused` is set, so `qc_rf_res_traces=0` is the claim -- nothing at
# all is written once the refusal fires. `qc_rf_dim_hugels` is the fixture
# that separates the TWO `any`s of :119: a local size over 1024 with a total
# UNDER 65536 is ACCEPTED, and a "one dimension" transcription would refuse it.
# --- 4: NINE WHOLE REGISTER VALUES, from `_qreg_exec` ITSELF --------------
# The per-field rows above pin the pieces; these pin the ASSEMBLY, which is
# where OR-vs-add and a mistyped shift cancel out. Nine sites, chosen so that
# between them they cover a four-field shifted register, a five-field register
# WITH a positional `__val`, two bool-carrying registers, a shifted register
# whose four shifts are 14/16/18/22, and the `_64b` field at :83 whose key
# carries the LEADING UNDERSCORE `_qreg_exec` strips with `removeprefix`.
def t_regvals() -> IO(Unit):
  do IO<Unit>:
    urow("qc_rv_ndrange", qreg.of("a6xx_sp_cs_ndrange_0", [P.Fv{"KERNELDIM", 3}, P.Fv{"LOCALSIZEX", 7}, P.Fv{"LOCALSIZEY", 15}, P.Fv{"LOCALSIZEZ", 3}]))
    urow("qc_rv_texconst0", U32.or(qreg.pos(8), qreg.of("a6xx_tex_const_0", [P.Fv{"FMT", 130}, P.Fv{"SWIZ_X", 0}, P.Fv{"SWIZ_Y", 1}, P.Fv{"SWIZ_Z", 2}, P.Fv{"SWIZ_W", 3}])))
    urow("qc_rv_csconfig", qreg.of("a6xx_sp_cs_config", [P.Fv{"ENABLED", 1}, P.Fv{"NSAMP", 2}, P.Fv{"NTEX", 1}, P.Fv{"NUAV", 3}]))
    urow("qc_rv_loadstate6", qreg.of("cp_load_state6_0", [P.Fv{"STATE_TYPE", 1}, P.Fv{"STATE_SRC", 2}, P.Fv{"STATE_BLOCK", 13}, P.Fv{"NUM_UNIT", 64}]))
    urow("qc_rv_cntl0", qreg.of("a6xx_sp_cs_cntl_0", [P.Fv{"THREADSIZE", 0}, P.Fv{"HALFREGFOOTPRINT", 32}, P.Fv{"FULLREGFOOTPRINT", 48}, P.Fv{"BRANCHSTACK", 4}]))
    urow("qc_rv_samp0", qreg.of("a6xx_tex_samp_0", [P.Fv{"WRAP_S", 3}, P.Fv{"WRAP_T", 3}, P.Fv{"WRAP_R", 3}]))
    urow("qc_rv_samp1", qreg.of("a6xx_tex_samp_1", [P.Fv{"UNNORM_COORDS", 1}, P.Fv{"CUBEMAPSEAMLESSFILTOFF", 1}]))
    urow("qc_rv_regtomem", qreg.of("cp_reg_to_mem_0", [P.Fv{"REG", 2432}, P.Fv{"CNT", 2}, P.Fv{"64B", 1}]))
    urow("qc_rv_updcntl", qreg.of("a6xx_sp_update_cntl", [P.Fv{"CS_STATE", 1}, P.Fv{"CS_UAV", 1}]))
    # a FALSE bool contributes ZERO, which is :39's `if v else 0` arm and NOT
    # `1 << shift`. Two rows differ by exactly that, which is what pins it.
    urow("qc_rv_samp1_off", qreg.of("a6xx_tex_samp_1", [P.Fv{"UNNORM_COORDS", 0}, P.Fv{"CUBEMAPSEAMLESSFILTOFF", 0}]))
    urow("qc_rv_samp1_part", qreg.of("a6xx_tex_samp_1", [P.Fv{"UNNORM_COORDS", 1}, P.Fv{"CUBEMAPSEAMLESSFILTOFF", 0}]))
    # a shifted field given 0 is 0, so a row that ORs in `v << shift` for a
    # bool field would answer 1 << 32-ish nonsense here. The two rows that
    # differ are the discriminator.
    urow("qc_rv_csconfig_off", qreg.of("a6xx_sp_cs_config", [P.Fv{"ENABLED", 0}, P.Fv{"NSAMP", 0}, P.Fv{"NTEX", 0}, P.Fv{"NUAV", 0}]))
# --- 5: ctz, :43 ---------------------------------------------------------
# `qc_ctz_nonzero` states the PRECONDITION rather than trusting it: `pitch` at
# :106 is `shape[1] * 4 * imgdt.itemsize`, so `ctz(pitch) >= 2` always and the
# `v == 0` case -- the only one where the port's `32` and Python's `-1` differ
# -- cannot be reached from `exec`.
def t_flag() -> IO(Unit):
  do IO<Unit>:
    urow("qc_flag_CONTEXT_PRIORITY_shift", 12)
    urow("qc_flag_CONTEXT_PRIORITY_mask", 61440)
    urow("qc_flag_CONTEXT_PREEMPT_STYLE_shift", 25)
    urow("qc_flag_CONTEXT_PREEMPT_STYLE_mask", 234881024)
    urow("qc_flag_MEMALIGN_shift", 16)
    urow("qc_flag_MEMALIGN_mask", 16711680)
    urow("qc_flag_CACHEMODE_shift", 26)
    urow("qc_flag_CACHEMODE_mask", 201326592)
    urow("qc_flag_CONTEXT_PRIORITY_of_8", flag("KGSL_CONTEXT_PRIORITY", 8))
    urow("qc_flag_CONTEXT_PREEMPT_STYLE_of_2", flag("KGSL_CONTEXT_PREEMPT_STYLE", 2))
    urow("qc_flag_MEMALIGN_of_12", flag("KGSL_MEMALIGN", 12))
    urow("qc_flag_CACHEMODE_of_1", flag("KGSL_CACHEMODE", 1))
    urow("qc_flag_clipped", flag(FLAG_PRIORITY(), 4095))
    urow("qc_flag_clipped_align", flag(FLAG_MEMALIGN(), 255))
    srow("qc_flagname_0", kgsl_name_at(0))
    srow("qc_flagname_3", kgsl_name_at(3))
    urow("qc_flagix_malign", P.kgsl_ix(FLAG_MEMALIGN()))
    urow("qc_flagix_absent", P.kgsl_ix("KGSL_NOSUCH"))
    srow("qc_flagname_absent", kgsl_name_at(P.NO_SUCH_FLAG()))
# --- 11: the 62 mesa/kgsl CONSTANTS -------------------------------------
# Transcribed once each from the oracle, and the oracle reads them off the
# LIVE autogen modules by walking the AST of ops_qcom.py, so a stale number
# here is a row that moves. They are named without a module prefix because
# the oracle ASSERTS the two namespaces do not collide.
def t_fvals() -> IO(Unit):
  do IO<Unit>:
    urow("qc_fv_0", fv_at(0))
    urow("qc_fv_1", fv_at(1))
    urow("qc_fv_2", fv_at(2))
    urow("qc_fv_3", fv_at(3))
    urow("qc_fv_4", fv_at(4))
    urow("qc_fv_5", fv_at(5))
    urow("qc_fv_6", fv_at(6))
    urow("qc_fv_7", fv_at(7))
    urow("qc_fv_8", fv_at(8))
    urow("qc_fv_9", fv_at(9))
    urow("qc_fv_10", fv_at(10))
    urow("qc_fv_11", fv_at(11))
    urow("qc_fv_12", fv_at(12))
    urow("qc_fv_13", fv_at(13))
    urow("qc_fv_14", fv_at(14))
    urow("qc_fv_15", fv_at(15))
    urow("qc_fv_16", fv_at(16))
    urow("qc_fv_17", fv_at(17))
    urow("qc_fv_18", fv_at(18))
    urow("qc_fv_19", fv_at(19))
    urow("qc_fv_20", fv_at(20))
    urow("qc_fv_21", fv_at(21))
    urow("qc_fv_22", fv_at(22))
    urow("qc_fv_23", fv_at(23))
    urow("qc_fv_24", fv_at(24))
    urow("qc_fv_25", fv_at(25))
    urow("qc_fv_26", fv_at(26))
    urow("qc_fv_27", fv_at(27))
    urow("qc_fv_28", fv_at(28))
    urow("qc_fv_29", fv_at(29))
    urow("qc_fv_30", fv_at(30))
    urow("qc_fv_31", fv_at(31))
    urow("qc_fv_32", fv_at(32))
    urow("qc_fv_33", fv_at(33))
    urow("qc_fv_34", fv_at(34))
    urow("qc_fv_35", fv_at(35))
    urow("qc_fv_36", fv_at(36))
    urow("qc_fv_37", fv_at(37))
    urow("qc_fv_38", fv_at(38))
    urow("qc_fv_39", fv_at(39))
    urow("qc_fv_40", fv_at(40))
    urow("qc_fv_41", fv_at(41))
    urow("qc_fv_42", fv_at(42))
    urow("qc_fv_43", fv_at(43))
    urow("qc_fv_44", fv_at(44))
    urow("qc_fv_45", fv_at(45))
    urow("qc_fv_46", fv_at(46))
    urow("qc_fv_47", fv_at(47))
    urow("qc_fv_48", fv_at(48))
    urow("qc_fv_49", fv_at(49))
    urow("qc_fv_50", fv_at(50))
    urow("qc_fv_51", fv_at(51))
    urow("qc_fv_52", fv_at(52))
    urow("qc_fv_53", fv_at(53))
    urow("qc_fv_54", fv_at(54))
    urow("qc_fv_55", fv_at(55))
    urow("qc_fv_56", fv_at(56))
    urow("qc_fv_57", fv_at(57))
    urow("qc_fv_58", fv_at(58))
    urow("qc_fv_59", fv_at(59))
    urow("qc_fv_60", fv_at(60))
    urow("qc_fv_61", fv_at(61))
# --- 12: `_parse_lib` on the SYNTHETIC blobs, :239-283 -------------------
# The blobs are the oracle's `synthetic_lib`, printed as byte lists, and
# `qc_lib_<k>_len` is their length so a fixture that drifts is visible BEFORE
# the parse rows rather than inside them.
#
# Each blob puts a value somewhere BOTH walks must find. The descriptor table
# starts at `round_up(image_desc_off + 0x158 + len(name), 4) + 8*samp_in_file`,
# so a blob with a different `name_len` starts it somewhere else and a port
# that hard-codes the offset misses every descriptor. The constant walk is
# bounded by `image_offset = 0x1a0`, which admits TWO of the three constants
# blob 2 writes -- and blob 4 writes only ONE, so it reads a ZEROED second.
# That is the bound biting, and `qc_const_bound_4` is the row.
#
# `qc_pl_<k>` is the seventeen parsed fields in `_parse_lib`'s OWN reading
# order, so a reader can line it up against :241-283. `buf_offs` and
# `consts_info` are LISTS and get their own rows.
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_buftype()
    b : Unit <- t_regs()
    +c : Unit <- t_regdirs()
    d : Unit <- t_fields()
    e : Unit <- t_fvals()
    f : Unit <- t_regvals()
    g : Unit <- t_ctz()
    +h : Unit <- t_parity()
    i : Unit <- t_pkt()
    j : Unit <- t_readlib()
    k : Unit <- t_qwords()
    +l : Unit <- t_flag()
    +m : Unit <- t_const()
    n : Unit <- t_lib0()
    o : Unit <- t_lib1()
    +p : Unit <- t_lib2()
    q : Unit <- t_lib3()
    r : Unit <- t_lib4()
    s : Unit <- t_lib5()
    +t : Unit <- t_cache()
    u : Unit <- t_offsets()
    +v : Unit <- t_hdr()
    +w : Unit <- t_flush()
    +x : Unit <- t_exec()
    +y : Unit <- t_refuse()
    +z : Unit <- t_submit()
    +aa : Unit <- t_layout()
    IO.print("qcom-done=1")
