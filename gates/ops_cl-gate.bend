# gates/ops_cl-gate.bend -- THE GATE DRIVER for `tinybendygrad/runtime/ops_cl.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and
# this file carries the instrument, and the tree's own convention says so:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# And the rows are pure consumers: they call the port's defs and define
# nothing that the port needs.

import Base
import ./../tinybendygrad/runtime/ops_cl.bend as P
import ./../tinybendygrad/helpers.bend as H

# cl:98 `err = cl.clGetDeviceIDs(platform_ids[0], device_type, 0, None, num_devices)`
# -- the PROBE, whose status is compared to 0 and then forgotten. The real call
# at cl:102 IS checked.
def cl_probe_checked() -> Bool: False{}

# cl:105, :107, :114 -- `(cl.clGetDeviceInfo(...), buf.value.decode())[1]`.
# Three sites, one shape: the status is dropped on the floor.
def cl_info_checked() -> Bool: False{}

# cl:29-30 -- the build log is read twice, unchecked, and the raise at :32 is a
# `CompileError`, not a `RuntimeError` from `check`.
def cl_build_log_checked() -> Bool: False{}
def cl_err_aliases() -> U32: U32.sub(P.cl_err_names_n(), P.cl_err_n())

# cl:18 f"OpenCL Error {status}: {cl_errors.get(status, 'Unknown error')}". The
# f-string has a DEFAULT, so there is NO `.get(...) is not None` test to port: the
# lookup's own default IS the message's tail and the two arms of such a pick would
# be equal. MEASURED: adding the `is not None` pick back moves ZERO gate rows --
# `cl_err_p999` prints `Unknown error` either way -- so the pick was dead code and
# `cl_err_hit` is gone with it. `u32s` puts the SIGN BACK, because the table stores
# two's complement and CPython's f-string spells `-1`. That is why the row that
# pins this says so in its P.NAME (`cl_err_m1` prints `-1`) and the oracle prints the
# same `str()`.
def cl_err_msg(+status: U32) -> String:
  String.concat(["OpenCL Error ", P.u32s(status), ": ", P.cl_err_of(status)])

# cl:97-99 -- the WINNING device type, and `one_u` answers 0 for a `None` index,
# which is NEITHER candidate: an exhausted probe leaves `P.Prb.idx` at P.NO_IDX, so
# `cl_probe_type_none` is the row that says the port answers 0 where Python would
# raise IndexError.
def cl.dev_type(+p: P.Prb) -> U32: P.one_u(List.get(&2, U32, P.cl_types(), U32.to_nat(P.Prb.idx(p))))

def cl_has_colon(+cs: List<&2, Char>) -> Bool: P.cl_colon_at(cs, False{})

# the FIVE success-path calls, in order.
def comp.compile(+t: P.Tr) -> P.Tr:
  +t1 = P.comp.from_src(t)
  +t2 = P.comp.build(t1)
  +t3 = P.comp.prg_info(P.CL_PROGRAM_BINARY_SIZES(), t2)
  +t4 = P.comp.prg_info(P.CL_PROGRAM_BINARIES(), t3)
  P.comp.release(t4)

# cl:28-32 -- `if build_status != 0:` then the TWO log reads and the raise. The
# raise is a `CompileError`, NOT a `check`, and this is the ONE refusal in the
# three files that the trace's `raise` does not model. Faithfulness here means the
# trace STOPS after the log reads, because after :32 nothing else in `compile`
# happens -- which is the same observable shape as a `check` refusal and is the
# reason the model covers it without a flag.
def comp.compile.bad(+t: P.Tr) -> P.Tr:
  +t1 = P.comp.from_src(t)
  +t2 = P.comp.build(t1)
  P.comp.build_log(0, P.comp.build_log(0, t2))

def prog.init(+d: P.Dev, +entry: String, libn: U32, +t: P.Tr, +sig: List<&2, P.Sig>) -> P.Prog:
  +t1 = P.prog.from_bin(libn, t)
  +t2 = P.prog.binary_check(t1)
  +t3 = P.prog.build(t2)
  +t4 = P.prog.kernel(entry, t3)
  P.Prog{P.V_CL(), P.Dev.didx(d), P.Dev.ctx(d), P.Tr.here(t1), P.Tr.here(t4), entry,
       sig, Nil{}, 1, 1, 1, 1, 1, 1, False{}, t4}

def prog.del(+p: P.Prog) -> P.Tr:
  P.prog.del.go(Bool.not(U32.is_zero(P.Prog.kernel(p))), Bool.not(U32.is_zero(P.Prog.prg(p))), P.Prog.t(p))

# cl:58 `getattr(ctypes, f"c_int{dt.bitsize}")(vals[slot - len(bufs)])` -- the
# ctypes TYPE NAME. Portable, and the one part of WALL 6 compared
# string-for-string against CPython. Note it is `c_int` for UNSIGNED dtypes too:
# the f-string has no `u` in it. It is the f-string, so the suffix is the DECIMAL
# PRINTER and not a four-way table -- 7 is `c_int7`, not `c_int32`, and the gate
# pins that off-grid row because a table keyed on {8,16,32,64} gets it wrong.
def ct.typename(bits: U32) -> String: String.concat(["c_int", P.u32_dec(bits)])

def arg.val_index(slot: U32, +nbufs: U32) -> U32: U32.sub(slot, nbufs)

def cl.pitch(osx: Bool, +s: P.Sig) -> U32: P.cl.pitch.at(osx, P.Sig.w(s), P.Sig.isz(s))

# cl:62 `desc = cl.cl_image_desc(cl.CL_MEM_OBJECT_IMAGE2D, shape[1], shape[0],
# image_row_pitch=pitch, buffer=b)` -- WIDTH is shape[1] and HEIGHT is shape[0],
# i.e. the OpenCL descriptor's two extents are the Python shape's LAST TWO in the
# opposite order, because a CL image is row-pitched and a numpy shape is
# row-major. Two separate defs so the swap is gateable on its own.
def img.desc_kind() -> U32: P.CL_MEM_OBJECT_IMAGE2D()
def img.desc_w(+s: P.Sig) -> U32: P.Sig.w(s)
def img.desc_h(+s: P.Sig) -> U32: P.Sig.h(s)

# cl:55-76 -- the step order IS the order of the Python.
def prog.call.at(+sigs: List<&2, P.Sig>, nbufs: U32, gx: U32, gy: U32, gz: U32,
                lx: U32, ly: U32, lz: U32, +want: Bool, +p0: P.Prog) -> P.Prog:
  +p1 = P.prog.args.go(sigs, 0, nbufs, p0)
  P.prog.launch(want, P.prog.geometry(p1, sigs, gx, gy, gz, lx, ly, lz, want))

# cl:89 `self.dev.synchronize()` -- the append that `_copyin` made is released
# here, so the COUNT of pending copies is what `synchronize` clears.
def copy.pending_clear(d: P.Dev) -> P.Dev:
  match d:
    case P.Dev{didx, ctx, q0, qflags, name, drv, exts, ipa, has_ipa, ckey, arch, pending, t}:
      P.Dev{didx, ctx, q0, qflags, name, drv, exts, ipa, has_ipa, ckey, arch, 0, t}

# cl:126 `def count(self) -> int: return len(unwrap(self.device_ids))` -- no call
# at all, and that is the row: `cl_count_gpu` is the probe's `n` and the trace has
# nothing to do with it.
def cl.count(p: P.Prb) -> U32: P.Prb.n(p)

def img.is_image(ndim: U32, last: U32) -> Bool:
  Bool.and(U32.is_eq(ndim, 3), U32.is_eq(last, 4))

# cl:75 `float(end.value - start.value) * OSX_TIMING_RATIO * 1e-9` -- the ns->s
# divisor and the ratio are portable and the u64 subtraction is WALL 2.
def timing.scale(osx: Bool) -> F32: F32.mul(P.timing.ratio(osx), 0.000000001)


def arg.strs(+xs: List<&2, P.Arg>) -> String: String.join(P.arg.strs.go(xs, Nil{}), " ")



# --- THE GATE ROWS ------------------------------------------------------
# THE GATE. Every row is a claim about the TEXT of the three Python files, about
# a constant read out of `tinygrad/runtime/autogen/*.py`, or about a table those
# two things define. The row name says which Python line it is about, and where a
# row's value is a P.NAME it is printed as a STRING -- never as a Bool about a
# string, because `String.concat` drops a literal silently and a Bool cannot see
# that it did.
#
# THE FIXTURES.
#   `fx_gpu`    the OpenCL device with two extensions and pitch alignment 0.
#   `fx_def`    the same, with the device-type loop falling through to DEFAULT.
#   `fx_none`   the same, with the loop EXHAUSTED (every candidate zero devices).
#   `fx_img`    the same with `cl_khr_image2d_from_buffer` and alignment 128.
#   `sig3`      three GLOBAL buffers and ONE val -- the shape of a 2-input
#               1-output float kernel, which is what cstyle's OpenCL text names
#               `data0_4, data1_4`.
#   `sig_img`   the same with ONE of the buffers an image (16x8, half).
#   `sig_skew`  the same with the SLOTS not the positions, which is what separates
#               cl:57's `enumerate` index from cl:58's `slot`.
# ===========================================================================

# --- 1: the vendor table, the CL column ---------------------------------
def t_vend() -> IO(Unit):
  do IO<Unit>:
    P.urow("vend_count_cl", P.vend.count())
    P.srowlist("vend_names_cl", P.vend.cl())
    P.urow("vend_len_cl", U32.from_nat(List.length(&2, String, P.vend.cl())))
    P.srow("vend_alloc_cl", P.vend.name(P.OP_ALLOC()))
    P.srow("vend_setarg_cl", P.vend.name(P.OP_SET_ARG()))
    P.srow("vend_relkernel_cl", P.vend.name(P.OP_RELEASE_KERNEL()))
    P.srow("vend_relprg_cl", P.vend.name(P.OP_RELEASE_PRG()))
    P.srow("vend_initext_cl", P.vend.name(P.OP_INIT()))
    P.srow("vend_none_cl", P.vend.name(P.OP_NONE()))
    P.srow("vend_oob", P.vend.name(39))
    # the two ARGUMENT-COLUMN rows and the table width are not per vendor:
    # `vend.argname` is the trace's one `arg` column and `P.OP_N` is the width
    # all three tables are asserted against, so they live with the first file.
    P.srowlist("vend_argnames", P.vend.argname())
    P.urow("vend_len_argnames", U32.from_nat(List.length(&2, String, P.vend.argname())))
    P.urow("vend_op_n", P.OP_N())

# --- 2: the check table, cl:98/105/114 ----------------------------------
def t_check() -> IO(Unit):
  do IO<Unit>:
    P.urow("vend_nchecked_cl", P.chk_count())
    P.urow("cl_unchecked_n", U32.from_nat(List.length(&2, U32, P.cl_unchecked())))
    P.brow("chk_cl_alloc", P.vend.checked(P.OP_ALLOC()))
    P.brow("cl_probe_checked", cl_probe_checked())
    P.brow("cl_info_checked", cl_info_checked())
    P.brow("cl_build_log_checked", cl_build_log_checked())

# --- 3: the error table, cl:16 ------------------------------------------
def t_err() -> IO(Unit):
  do IO<Unit>:
    P.urow("cl_err_n", P.cl_err_n())
    P.urow("cl_err_aliases", cl_err_aliases())
    P.srow("cl_err_0", cl_err_msg(0))
    P.srow("cl_err_m1", cl_err_msg(4294967295))
    P.srow("cl_err_m2", cl_err_msg(4294967294))
    P.srow("cl_err_m3", cl_err_msg(4294967293))
    P.srow("cl_err_m19", cl_err_msg(4294967277))
    P.srow("cl_err_m30", cl_err_msg(4294967266))
    P.srow("cl_err_m72", cl_err_msg(4294967224))
    P.srow("cl_err_p999", cl_err_msg(999))
    # the four ALIASED codes -- 0, -1, -2 and -3 carry 9, 2, 2 and 2 names -- and
    # the comprehension keeps the LAST one, so these four rows are what pins WHICH
    # name survives. Without them `cl_err_step`'s "first hit wins" guard is
    # invisible: MEASURED, dropping it moved nothing until these four rows existed.
    P.srow("cl_err_alias_m3", P.cl_err_of(4294967293))
    P.srow("cl_err_alias_m2", P.cl_err_of(4294967294))
    P.srow("cl_err_alias_m1", P.cl_err_of(4294967295))
    P.srow("cl_err_alias_0", P.cl_err_of(0))

# --- 4: the integer printer, which is the only sign repair in the file -----
def t_print() -> IO(Unit):
  do IO<Unit>:
    P.srow("u32s_0", P.u32s(0))
    P.srow("u32s_7", P.u32s(7))
    P.srow("u32s_63", P.u32s(63))
    P.srow("u32s_100", P.u32s(100))
    P.srow("u32s_999", P.u32s(999))
    P.srow("u32s_712", P.u32s(712))
    P.srow("u32s_neg1", P.u32s(4294967295))
    P.srow("u32s_neg19", P.u32s(4294967277))
    P.urow("dec_len_0", P.dec_len(0))
    P.urow("dec_len_9", P.dec_len(9))
    P.urow("dec_len_10", P.dec_len(10))
    P.urow("dec_len_63", P.dec_len(63))
    P.urow("dec_len_64", P.dec_len(64))
    P.urow("dec_len_99", P.dec_len(99))
    P.urow("dec_len_100", P.dec_len(100))
    P.urow("dec_len_999", P.dec_len(999))
    P.urow("dec_len_1000", P.dec_len(1000))
    P.urow("dec_len_4294967295", P.dec_len(4294967295))
    P.srow("dgt_0", P.dgt(0))
    P.srow("dgt_9", P.dgt(9))
    # F32 constants are gated by their BIT PATTERN and not by `F32.show`: the two
    # lanes agree on `F32.bits` and on `struct.pack('<f')`, and `F32.show` prints
    # seven significant digits, which no CPython format reproduces. MEASURED on
    # both lanes against `struct.unpack('<I', struct.pack('<f', v))[0]`.
    P.urow("timing_ratio_off_bits", F32.bits(P.timing.ratio(False{})))
    P.urow("timing_ratio_on_bits", F32.bits(P.timing.ratio(True{})))
    P.urow("timing_ns_scale_bits", F32.bits(timing.scale(False{})))
    P.urow("timing_ns_scale_on_bits", F32.bits(timing.scale(True{})))

# --- 5: the OpenCL INIT SEQUENCE, cl:93-124 --------------------------------
def EXTS_A() -> List<&2, String>: ["cl_khr_fp16", "cl_khr_int64_base_atomics"]
def EXTS_C() -> List<&2, String>: ["cl_khr_fp16"]
def fx_gpu() -> P.Dev: P.cl.init(P.Prb.seed([2, 1]), P.DEV0(), P.NAME(), P.DRV(), EXTS_C(), 0, P.Tr.of())
def fx_def() -> P.Dev: P.cl.init(P.Prb.seed([0, 3]), P.DEV0(), P.NAME(), P.DRV(), EXTS_C(), 0, P.Tr.of())
def fx_none() -> P.Dev: P.cl.init(P.Prb.seed([0, 0]), P.DEV0(), P.NAME(), P.DRV(), EXTS_C(), 0, P.Tr.of())

def t_clinit() -> IO(Unit):
  do IO<Unit>:
    P.srow("cl_init_trace", P.vend.trace(P.Tr.calls(P.Dev.t(fx_gpu()))))
    P.srow("cl_init_trace_def", P.vend.trace(P.Tr.calls(P.Dev.t(fx_def()))))
    P.srow("cl_init_trace_img", P.vend.trace(P.Tr.calls(P.Dev.t(P.fx_img()))))
    P.urow("cl_init_calls", P.Tr.n(P.Dev.t(fx_gpu())))
    P.urow("cl_init_calls_def", P.Tr.n(P.Dev.t(fx_def())))
    P.urow("cl_init_calls_img", P.Tr.n(P.Dev.t(P.fx_img())))
    P.urow("cl_init_platforms", P.Tr.count(P.OP_PLATFORMS(), P.Tr.calls(P.Dev.t(fx_gpu()))))
    P.urow("cl_init_getdevices", P.Tr.count(P.OP_GET_DEVICES(), P.Tr.calls(P.Dev.t(fx_gpu()))))
    P.urow("cl_init_getdevices_none", P.Tr.count(P.OP_GET_DEVICES(), P.Tr.calls(P.Dev.t(fx_none()))))
    P.urow("cl_init_ctx", P.Tr.count(P.OP_CTX_CREATE(), P.Tr.calls(P.Dev.t(fx_gpu()))))
    P.urow("cl_init_queue", P.Tr.count(P.OP_QUEUE_CREATE(), P.Tr.calls(P.Dev.t(fx_gpu()))))
    P.urow("cl_init_info", P.Tr.count(P.OP_GET_DEVICE_INFO(), P.Tr.calls(P.Dev.t(fx_gpu()))))
    P.urow("cl_init_info_img", P.Tr.count(P.OP_GET_DEVICE_INFO(), P.Tr.calls(P.Dev.t(P.fx_img()))))
    P.srowlist("cl_init_info_params", P.Tr.args(P.OP_GET_DEVICE_INFO(), P.Tr.calls(P.Dev.t(P.fx_img()))))
    P.urow("cl_probe_idx_gpu", P.Prb.idx(P.cl.probe_init(P.Prb.seed([2, 1]), P.Tr.of())))
    P.urow("cl_probe_idx_def", P.Prb.idx(P.cl.probe_init(P.Prb.seed([0, 3]), P.Tr.of())))
    P.urow("cl_probe_idx_none", P.Prb.idx(P.cl.probe_init(P.Prb.seed([0, 0]), P.Tr.of())))
    P.urow("cl_probe_n_gpu", P.Prb.n(P.cl.probe_init(P.Prb.seed([2, 1]), P.Tr.of())))
    P.urow("cl_probe_n_def", P.Prb.n(P.cl.probe_init(P.Prb.seed([0, 3]), P.Tr.of())))
    P.urow("cl_probe_n_none", P.Prb.n(P.cl.probe_init(P.Prb.seed([0, 0]), P.Tr.of())))
    P.urow("cl_probe_type_gpu", cl.dev_type(P.cl.probe_init(P.Prb.seed([2, 1]), P.Tr.of())))
    P.urow("cl_probe_type_def", cl.dev_type(P.cl.probe_init(P.Prb.seed([0, 3]), P.Tr.of())))
    P.urow("cl_probe_type_none", cl.dev_type(P.cl.probe_init(P.Prb.seed([0, 0]), P.Tr.of())))
    P.lrow("cl_types", P.cl_types())
    P.urow("cl_count_gpu", cl.count(P.cl.probe_init(P.Prb.seed([2, 1]), P.Tr.of())))
    P.urow("cl_count_none", cl.count(P.cl.probe_init(P.Prb.seed([0, 0]), P.Tr.of())))
    P.urow("cl_didx_empty", P.cl_dev_index(P.DEV0()))
    P.urow("cl_didx_0", P.cl_dev_index("OPENCL:0"))
    P.urow("cl_didx_2", P.cl_dev_index(P.DEV2()))
    P.urow("cl_didx_17", P.cl_dev_index(P.DEV17()))
    P.brow("cl_didx_colon", cl_has_colon(String.to_list(P.DEV2())))
    P.brow("cl_didx_nocolon", cl_has_colon(String.to_list(P.DEV0())))
    P.srow("cl_arch_none", P.Dev.arch(fx_gpu()))
    P.srow("cl_arch_img", P.Dev.arch(P.fx_img()))
    P.srow("cl_key", P.Dev.ckey(fx_gpu()))
    P.urow("cl_ctx_id", P.Dev.ctx(fx_gpu()))
    P.urow("cl_queue_id", P.Dev.q0(fx_gpu()))
    P.urow("cl_qflags", P.Dev.qflags(fx_gpu()))
    P.urow("cl_pending", P.Dev.pending(fx_gpu()))
    P.urow("cl_pending_after", P.Dev.pending(copy.pending_clear(fx_gpu())))

# --- 6: the arch string and the image tables, cl:120-123 and :60-62 --------
def t_climg() -> IO(Unit):
  do IO<Unit>:
    P.brow("cl_img_ext_a", P.cl.has_img_ext(EXTS_A()))
    P.brow("cl_img_ext_b", P.cl.has_img_ext(P.EXTS_B()))
    P.brow("cl_img_ext_c", P.cl.has_img_ext(EXTS_C()))
    P.srow("cl_arch_suffix_none", P.cl.arch_suffix(False{}, 128))
    P.srow("cl_arch_suffix_128", P.cl.arch_suffix(True{}, 128))
    P.srow("cl_ext_join_a", P.cl.ext_join(EXTS_A()))
    P.srow("cl_ext_join_b", P.cl.ext_join(P.EXTS_B()))
    P.urow("cl_pitch_align", P.cl.PITCH_ALIGN())
    P.urow("cl_channels", P.IMAGE_CHANNELS())
    P.urow("cl_pitch_noosx_8_8", cl.pitch(False{}, P.Sig.of(0, 32, 4, True{}, 8, 8)))
    P.urow("cl_pitch_osx_8_8", cl.pitch(True{}, P.Sig.of(0, 32, 4, True{}, 8, 8)))
    P.urow("cl_pitch_osx_1_1", cl.pitch(True{}, P.Sig.of(0, 16, 2, True{}, 1, 1)))
    P.urow("cl_pitch_osx_257_4", cl.pitch(True{}, P.Sig.of(0, 16, 2, True{}, 257, 4)))
    P.urow("cl_pitch_osx_4_257", cl.pitch(True{}, P.Sig.of(0, 16, 2, True{}, 4, 257)))
    P.urow("img_fmt_1", P.img.fmt_of(1))
    P.urow("img_fmt_2", P.img.fmt_of(2))
    P.urow("img_fmt_4", P.img.fmt_of(4))
    P.urow("img_fmt_8", P.img.fmt_of(8))
    P.urow("img_desc_kind", img.desc_kind())
    P.urow("img_desc_w_16_8", img.desc_w(P.Sig.of(0, 32, 4, True{}, 16, 8)))
    P.urow("img_desc_h_16_8", img.desc_h(P.Sig.of(0, 32, 4, True{}, 16, 8)))
    P.urow("img_desc_w_4_257", img.desc_w(P.Sig.of(0, 16, 2, True{}, 4, 257)))
    P.urow("img_desc_h_4_257", img.desc_h(P.Sig.of(0, 16, 2, True{}, 4, 257)))
    P.brow("img_is_image_3_4", img.is_image(3, 4))
    P.brow("img_is_image_3_1", img.is_image(3, 1))
    P.brow("img_is_image_2_4", img.is_image(2, 4))
    P.brow("img_is_image_4_4", img.is_image(4, 4))
    P.srow("ct_int8", ct.typename(8))
    P.srow("ct_int16", ct.typename(16))
    P.srow("ct_int32", ct.typename(32))
    P.srow("ct_int64", ct.typename(64))
    P.srow("ct_int7", ct.typename(7))
    P.urow("cl_ptr_sz", P.PTR_SZ())
    P.urow("arg_size_mem", P.arg.size(P.KIND_MEM(), 4))
    P.urow("arg_size_image", P.arg.size(P.KIND_IMAGE(), 4))
    P.urow("arg_size_scalar32", P.arg.size(P.KIND_SCALAR(), 4))
    P.urow("arg_size_scalar16", P.arg.size(P.KIND_SCALAR(), 2))
    P.urow("arg_kind_mem", P.arg.kind(P.Sig.of(0, 32, 4, False{}, 0, 0), 3))
    P.urow("arg_kind_scalar", P.arg.kind(P.Sig.of(3, 32, 4, False{}, 0, 0), 3))
    P.urow("arg_kind_image", P.arg.kind(P.Sig.of(1, 16, 2, True{}, 16, 8), 3))
    P.brow("arg_is_buf_0_3", P.arg.is_buf(0, 3))
    P.brow("arg_is_buf_3_3", P.arg.is_buf(3, 3))
    P.urow("arg_val_index_3_3", arg.val_index(3, 3))
    P.urow("arg_val_index_4_3", arg.val_index(4, 3))

def sig3() -> List<&2, P.Sig>:
  [P.Sig.of(0, 32, 4, False{}, 0, 0), P.Sig.of(1, 32, 4, False{}, 0, 0),
   P.Sig.of(2, 32, 4, False{}, 0, 0), P.Sig.of(3, 32, 4, False{}, 0, 0)]

def sig_img() -> List<&2, P.Sig>:
  [P.Sig.of(0, 32, 4, False{}, 0, 0), P.Sig.of(1, 16, 2, True{}, 16, 8),
   P.Sig.of(2, 32, 4, False{}, 0, 0), P.Sig.of(3, 32, 4, False{}, 0, 0)]

# the signature where the SLOTS are not the positions: TinyELF's slots are
# assignable (ops.py:1378 dedups them) so `slot` can skip, and that is the fixture
# that separates cl:57's `enumerate` index from cl:58's `slot`.
def sig_skew() -> List<&2, P.Sig>:
  [P.Sig.of(0, 32, 4, False{}, 0, 0), P.Sig.of(3, 32, 4, False{}, 0, 0),
   P.Sig.of(1, 32, 4, False{}, 0, 0), P.Sig.of(4, 32, 4, False{}, 0, 0)]

# --- 7: the compile and program-init sequences, cl:25-47 ------------------
def t_clprog() -> IO(Unit):
  do IO<Unit>:
    P.srow("cl_compile_trace", P.vend.trace(P.Tr.calls(comp.compile(P.Tr.of()))))
    P.srow("cl_compile_bad_trace", P.vend.trace(P.Tr.calls(comp.compile.bad(P.Tr.of()))))
    P.urow("cl_compile_calls", P.Tr.n(comp.compile(P.Tr.of())))
    P.urow("cl_compile_bad_calls", P.Tr.n(comp.compile.bad(P.Tr.of())))
    P.srowlist("cl_compile_prginfo", P.Tr.args(P.OP_PRG_INFO(), P.Tr.calls(comp.compile(P.Tr.of()))))
    P.srowlist("cl_compile_badlog", P.Tr.args(P.OP_BUILD_LOG(), P.Tr.calls(comp.compile.bad(P.Tr.of()))))
    P.srow("cl_compile_err", P.CL_COMPILE_ERR())
    +p : P.Prog <- IO.pure(P.Prog, prog.init(fx_gpu(), "k", 128, P.Tr.of(), sig3()))
    P.srow("cl_prog_init_trace", P.vend.trace(P.Tr.calls(P.Prog.t(p))))
    P.urow("cl_prog_init_calls", P.Tr.n(P.Prog.t(p)))
    P.urow("cl_prog_prg_id", P.Prog.prg(p))
    P.urow("cl_prog_kernel_id", P.Prog.kernel(p))
    P.urow("cl_prog_unit", P.Prog.unit(p))
    P.urow("cl_prog_ctx", P.Prog.ctx(p))
    P.srow("cl_prog_kernel_name", P.Prog.entry(p))
    P.srow("cl_prog_del_trace", P.vend.trace(P.Tr.calls(prog.del(p))))
    P.srow("cl_prog_del_nokernel", P.vend.trace(P.Tr.calls(prog.del(P.Prog.of(P.V_CL(), "k", Nil{})))))
    P.urow("cl_prog_del_full", P.Tr.n(prog.del(p)))
    P.urow("cl_prog_del_bare", P.Tr.n(prog.del(P.Prog.of(P.V_CL(), "k", Nil{}))))

# --- 8: ONE PROGRAM CALL, cl:55-76 -----------------------------------------
def fx_call3(want: Bool) -> P.Prog:
  prog.call.at(sig3(), 3, 8, 2, 1, 4, 1, 1, want, prog.init(fx_gpu(), "k", 128, P.Tr.reset(P.Tr.of()), sig3()))

def fx_callimg(want: Bool) -> P.Prog:
  prog.call.at(sig_img(), 3, 8, 2, 1, 4, 1, 1, want, prog.init(fx_gpu(), "k", 128, P.Tr.reset(P.Tr.of()), sig_img()))

def fx_callskew(want: Bool) -> P.Prog:
  prog.call.at(sig_skew(), 2, 8, 2, 1, 4, 1, 1, want, prog.init(fx_gpu(), "k", 128, P.Tr.reset(P.Tr.of()), sig_skew()))

def t_clcall() -> IO(Unit):
  do IO<Unit>:
    +p : P.Prog <- IO.pure(P.Prog, fx_call3(False{}))
    +t : P.Tr <- IO.pure(P.Tr, P.Prog.t(p))
    P.srow("cl_call_trace", P.vend.trace(P.Tr.calls(t)))
    P.srow("cl_call_args", arg.strs(P.Prog.args(p)))
    P.srow("cl_call_trace_wait", P.vend.trace(P.Tr.calls(P.Prog.t(fx_call3(True{})))))
    P.srow("cl_call_args_img", arg.strs(P.Prog.args(fx_callimg(False{}))))
    P.srow("cl_call_args_skew", arg.strs(P.Prog.args(fx_callskew(False{}))))
    P.srow("cl_call_trace_img", P.vend.trace(P.Tr.calls(P.Prog.t(fx_callimg(False{})))))
    P.srow("cl_call_trace_skew", P.vend.trace(P.Tr.calls(P.Prog.t(fx_callskew(False{})))))
    P.urow("cl_call_calls", P.Tr.n(t))
    P.urow("cl_call_calls_wait", P.Tr.n(P.Prog.t(fx_call3(True{}))))
    P.urow("cl_call_setargs", P.Tr.count(P.OP_SET_ARG(), P.Tr.calls(t)))
    P.urow("cl_call_setargs_img", P.Tr.count(P.OP_SET_ARG(), P.Tr.calls(P.Prog.t(fx_callimg(False{})))))
    P.urow("cl_call_images", P.Tr.count(P.OP_IMAGE(), P.Tr.calls(P.Prog.t(fx_callimg(False{})))))
    P.urow("cl_call_images_3", P.Tr.count(P.OP_IMAGE(), P.Tr.calls(t)))
    P.urow("cl_call_gx", P.Prog.gsx(p))
    P.urow("cl_call_gy", P.Prog.gsy(p))
    P.urow("cl_call_gz", P.Prog.gsz(p))
    P.urow("cl_call_lsx", P.Prog.lsx(p))
    P.urow("cl_call_lsy", P.Prog.lsy(p))
    P.urow("cl_call_lsz", P.Prog.lsz(p))
    P.urow("cl_call_launch", P.Tr.count(P.OP_LAUNCH(), P.Tr.calls(t)))
    P.urow("cl_call_waitev", P.Tr.count(P.OP_WAIT_EVENT(), P.Tr.calls(t)))
    P.urow("cl_call_waitev_wait", P.Tr.count(P.OP_WAIT_EVENT(), P.Tr.calls(P.Prog.t(fx_call3(True{})))))
    P.urow("cl_call_time", P.Tr.count(P.OP_TIME_END(), P.Tr.calls(t)))
    P.urow("cl_call_time_wait", P.Tr.count(P.OP_TIME_END(), P.Tr.calls(P.Prog.t(fx_call3(True{})))))
    P.srowlist("cl_call_time_params", P.Tr.args(P.OP_TIME_END(), P.Tr.calls(P.Prog.t(fx_call3(True{})))))
    P.srowlist("cl_call_launch_arg", P.Tr.args(P.OP_LAUNCH(), P.Tr.calls(t)))
    P.srowlist("cl_call_setarg_args", P.Tr.args(P.OP_SET_ARG(), P.Tr.calls(t)))
    P.urow("cl_geom_8_4", P.cl.geom(8, 4))
    P.urow("cl_geom_1_1", P.cl.geom(1, 1))
    P.urow("cl_geom_0_5", P.cl.geom(0, 5))
    P.urow("cl_geom_1000_1000", P.cl.geom(1000, 1000))

# --- 9: the allocator, cl:78-89 and :126-130 -------------------------------
def t_clalloc() -> IO(Unit):
  do IO<Unit>:
    +a : P.Made <- IO.pure(P.Made, P.alloc.of(64, P.Tr.of()))
    P.srow("cl_alloc_trace", P.vend.trace(P.Tr.calls(P.Made.tr(a))))
    P.urow("cl_alloc_size", P.Buf.size(P.Made.buf(a)))
    P.urow("cl_alloc_id", P.Buf.id(P.Made.buf(a)))
    +f : P.Tr <- IO.pure(P.Tr, P.alloc.free(a))
    P.srow("cl_free_trace", P.vend.trace(P.Tr.calls(f)))
    P.srowlist("cl_free_args", P.Tr.args(P.OP_FREE(), P.Tr.calls(f)))
    +i : P.Tr <- IO.pure(P.Tr, P.copy.copyin(64, P.Tr.of()))
    P.srow("cl_copyin_trace", P.vend.trace(P.Tr.calls(i)))
    P.srowlist("cl_copyin_args", P.Tr.args(P.OP_COPY_IN(), P.Tr.calls(i)))
    +o : P.Tr <- IO.pure(P.Tr, P.copy.copyout(64, P.Tr.of()))
    P.srow("cl_copyout_trace", P.vend.trace(P.Tr.calls(o)))
    P.srowlist("cl_copyout_args", P.Tr.args(P.OP_COPY_OUT(), P.Tr.calls(o)))
    P.urow("cl_copyout_finishes", P.Tr.count(P.OP_FINISH(), P.Tr.calls(o)))
    P.urow("cl_copyin_finishes", P.Tr.count(P.OP_FINISH(), P.Tr.calls(i)))
    +sy : P.Tr <- IO.pure(P.Tr, P.cl.sync(P.Tr.of()))
    P.srow("cl_sync_trace", P.vend.trace(P.Tr.calls(sy)))

# --- 10: the REFUSAL paths, every CL `check` (cl:17-19) ----------------------
# PORT-LOCAL CORRECTION: the pre-split heading read "every `check` in the three
# files", and ALL 29 of its rows are `cl_refuse_*`. It was CL-only before the
# split too. `t_cross`'s `x_free_*` rows are the three-file part.
# `bad_at` names the CALL ORDINAL at which `check` reports, and the trace is
# TRUNCATED from there -- which is the whole refusal model. `bad_at` is read AT
# EMIT TIME, so it must be armed BEFORE the calls happen: the first version armed
# a finished trace, all four rows printed the full nine calls and every flag was
# False. `bad_at` numbers the PROGRAM's own trace (which `P.Tr.reset` starts at
# zero), so 1 is `clCreateProgramWithBinary` and 5 is the first `clSetKernelArg`.
def fx_refuse.prog(bad_at: U32) -> P.Prog:
  prog.init(fx_gpu(), "k", 128, P.Tr.fail_at(P.Tr.reset(P.Tr.of()), bad_at), sig3())

def fx_refuse(bad_at: U32) -> P.Prog:
  prog.call.at(sig3(), 3, 8, 2, 1, 4, 1, 1, False{}, fx_refuse.prog(bad_at))

def t_refuse() -> IO(Unit):
  do IO<Unit>:
    +a : P.Prog <- IO.pure(P.Prog, fx_refuse(1))
    +b : P.Prog <- IO.pure(P.Prog, fx_refuse(2))
    +c : P.Prog <- IO.pure(P.Prog, fx_refuse(4))
    +d : P.Prog <- IO.pure(P.Prog, fx_refuse(5))
    +e : P.Prog <- IO.pure(P.Prog, fx_refuse(6))
    P.srow("cl_refuse_1_trace", P.vend.trace(P.Tr.calls(P.Prog.t(a))))
    P.srow("cl_refuse_2_trace", P.vend.trace(P.Tr.calls(P.Prog.t(b))))
    P.srow("cl_refuse_4_trace", P.vend.trace(P.Tr.calls(P.Prog.t(c))))
    P.srow("cl_refuse_5_trace", P.vend.trace(P.Tr.calls(P.Prog.t(d))))
    P.srow("cl_refuse_6_trace", P.vend.trace(P.Tr.calls(P.Prog.t(e))))
    P.urow("cl_refuse_1_calls", P.Tr.n(P.Prog.t(a)))
    P.urow("cl_refuse_2_calls", P.Tr.n(P.Prog.t(b)))
    P.urow("cl_refuse_4_calls", P.Tr.n(P.Prog.t(c)))
    P.urow("cl_refuse_5_calls", P.Tr.n(P.Prog.t(d)))
    P.urow("cl_refuse_6_calls", P.Tr.n(P.Prog.t(e)))
    P.urow("cl_refuse_5_setargs", P.Tr.count(P.OP_SET_ARG(), P.Tr.calls(P.Prog.t(d))))
    P.urow("cl_refuse_6_setargs", P.Tr.count(P.OP_SET_ARG(), P.Tr.calls(P.Prog.t(e))))
    P.urow("cl_refuse_5_launch", P.Tr.count(P.OP_LAUNCH(), P.Tr.calls(P.Prog.t(d))))
    P.urow("cl_refuse_6_launch", P.Tr.count(P.OP_LAUNCH(), P.Tr.calls(P.Prog.t(e))))
    P.urow("cl_refuse_5_args", U32.from_nat(List.length(&2, P.Arg, P.Prog.args(d))))
    P.urow("cl_refuse_6_args", U32.from_nat(List.length(&2, P.Arg, P.Prog.args(e))))
    P.urow("cl_refuse_5_calls_after_init", U32.sub(P.Tr.n(P.Prog.t(d)), P.PROG_INIT_N()))
    P.urow("cl_refuse_6_calls_after_init", U32.sub(P.Tr.n(P.Prog.t(e)), P.PROG_INIT_N()))
    P.brow("cl_refuse_1_flag", P.Tr.refused(P.Prog.t(a)))
    P.brow("cl_refuse_5_flag", P.Tr.refused(P.Prog.t(d)))
    P.brow("cl_refuse_0_flag", P.Tr.refused(P.Prog.t(fx_call3(False{}))))
    # the MATCHER pins itself first: a reversed pair must NOT match, an absent entry
    # must NOT match, and a real pair must. Five order rows are decorative
    # without these three.
    +t : P.Tr <- IO.pure(P.Tr, P.Prog.t(fx_call3(False{})))
    P.brow("cl_has_rejects_reverse", Bool.not(P.Tr.has(P.Tr.calls(t),
      [P.Call{P.OP_LAUNCH(), "3"}, P.Call{P.OP_WAIT_EVENT(), "1"}])))
    P.brow("cl_has_rejects_absent", Bool.not(P.Tr.has(P.Tr.calls(t), [P.Call{P.OP_LAUNCH(), "999"}])))
    P.brow("cl_has_rejects_arg", Bool.not(P.Tr.has(P.Tr.calls(t), [P.Call{P.OP_LAUNCH(), "4"}])))
    P.brow("cl_has_pair", P.Tr.has(P.Tr.calls(t), [P.Call{P.OP_SET_ARG(), "1"}, P.Call{P.OP_LAUNCH(), "3"}]))
    P.brow("cl_has_prefix", P.Tr.has(P.Tr.calls(t), [P.Call{P.OP_SET_ARG(), "0"}, P.Call{P.OP_SET_ARG(), "1"}]))


def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_vend()
    b : Unit <- t_check()
    c : Unit <- t_err()
    d : Unit <- t_print()
    e : Unit <- t_clinit()
    f : Unit <- t_climg()
    g : Unit <- t_clprog()
    h : Unit <- t_clcall()
    i : Unit <- t_clalloc()
    j : Unit <- t_refuse()
    IO.print("cl-done=1")
