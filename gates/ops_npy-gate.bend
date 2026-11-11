# gates/ops_npy-gate.bend -- the gate driver for `tinybendygrad/runtime/ops_npy.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/runtime/ops_npy.bend as P

import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/device.bend as D
import ./../tinybendygrad/LAWS/spec.bend as S
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit): IO.print(String.concat([nm, "=", P.ustr(xs)]))

def seq(t: P.Tr, pat: List<&2, P.Call>) -> Bool: P.Tr.has(P.Tr.calls(t), pat)

def if_b.go(b: Bool) -> U32:
  match b:
    case True{}: 1
    case False{}: 0

def if_b(b: Bool) -> U32: if_b.go(b)

# --- 1: the FOUR ARGUMENTS, ops_npy.py:4 -------------------------------------
def t_args() -> IO(Unit):
  do IO<Unit>:
    +d : P.Npy <- IO.pure(P.Npy, P.Npy.of("NPY"))
    urow("npy_arg_alloc", P.Npy.alloc(d))
    urow("npy_arg_runtime", P.Npy.runtime(d))
    urow("npy_arg_render_passed", P.RENDERERS_PASSED())
    urow("npy_arg_render_effective", P.Npy.nrender(d))
    row("npy_arg_render_is_default", U32.is_eq(P.Npy.nrender(d), P.RENDERERS_EFFECTIVE()))
    row("npy_arg_render_not_empty", U32.is_ne(P.Npy.nrender(d), P.RENDERERS_PASSED()))
    urow("npy_arch_kwarg", P.ARCH_KWARG())
    lrow("npy_supports", P.npy.supports())
    row("npy_sup_disk", Bool.not(P.Npy.sup_disk(d)))
    row("npy_sup_xfer", Bool.not(P.Npy.sup_xfer(d)))

# --- 2: what the four lines DO NOT do ----------------------------------------
def t_no() -> IO(Unit):
  do IO<Unit>:
    +d : P.Npy <- IO.pure(P.Npy, P.Npy.of("NPY"))
    srow("npy_peer", P.Npy.peer(d))
    row("npy_peer_is_head", String.eq(P.Npy.peer(d), D.head("NPY")))
    srow("npy_host", P.Npy.host(d))
    urow("npy_did_0", P.Npy.did(P.Npy.of("NPY")))
    urow("npy_did_0b", P.Npy.did(P.Npy.of("NPY:0")))
    urow("npy_did_3", P.Npy.did(P.Npy.of("NPY:3")))
    urow("npy_did_bad", P.Npy.did(P.Npy.of("NPY:x")))
    urow("npy_did_deep", P.Npy.did(P.Npy.of("NPY:1:2")))
    row("npy_did_3_is_3", U32.is_eq(P.Npy.did(P.Npy.of("NPY:3")), 3))
    row("npy_did_bad_is_0", U32.is_zero(P.Npy.did(P.Npy.of("NPY:x"))))
    srow("npy_canon", D.canon("NPY:0"))
    urow("npy_dcls", D.dcls("NPY"))
    urow("npy_ifaces_len", U32.from_nat(List.length(&2, String, Nil{})))

# --- 3: the ALLOCATION, device.py:307-308 ------------------------------------
def t_alloc() -> IO(Unit):
  do IO<Unit>:
    +t : P.Tr <- IO.pure(P.Tr, P.npy.alloc(12, P.Tr.of()))
    # THE MATCHER PINS ITSELF FIRST, because the eleven order rows below are
    # worth nothing if it answers True to everything.
    row("npy_has_rejects_reverse", Bool.not(seq(t, [P.Call{P.CALL_MVIEW, 12}, P.Call{P.CALL_MMAP, 12}])))
    row("npy_has_rejects_absent", Bool.not(seq(t, [P.Call{P.CALL_SYNC, 0}])))
    row("npy_alloc_order", seq(t, [P.Call{P.CALL_MMAP, 12}, P.Call{P.CALL_MVIEW, 12}]))
    lrow("npy_alloc_args", P.Tr.args(P.CALL_MMAP(), P.Tr.calls(t)))
    lrow("npy_alloc_views", P.Tr.args(P.CALL_MVIEW(), P.Tr.calls(t)))
    urow("npy_alloc_n", P.Tr.ncalls(t))
    urow("npy_alloc_mmaps", P.Tr.count(P.CALL_MMAP(), P.Tr.calls(t)))
    urow("npy_alloc_storage_args", P.ALLOC_STORAGE_ARGS())
    urow("npy_alloc_fmt_b", P.FMT_B())
    # THE RAW SIZE: a 5-byte allocation asks mmap for five bytes. No `round_up`
    # anywhere in HostAllocator.
    +t5 : P.Tr <- IO.pure(P.Tr, P.npy.alloc(5, P.Tr.of()))
    lrow("npy_alloc_raw", P.Tr.args(P.CALL_MMAP(), P.Tr.calls(t5)))
    row("npy_alloc_no_pad", P.u32_list_eq(P.Tr.args(P.CALL_MMAP(), P.Tr.calls(t5)), [5]))
    urow("npy_alloc_view_exact", P.npy.view_bytes(5))
    urow("npy_alloc_not_page", P.page_bytes(5))
    row("npy_alloc_view_is_exact", U32.is_eq(P.npy.view_bytes(5), 5))
    row("npy_alloc_view_not_page", U32.is_ne(P.npy.view_bytes(5), P.page_bytes(5)))

# --- 4: the two COPIES, device.py:315-318 -------------------------------------
def t_copy() -> IO(Unit):
  do IO<Unit>:
    +ti : P.Tr <- IO.pure(P.Tr, P.npy.copyin(12, P.Tr.of()))
    +to : P.Tr <- IO.pure(P.Tr, P.npy.copyout(12, P.Tr.of()))
    row("npy_copyin_sync_first", seq(ti, [P.Call{P.CALL_SYNC, 0}, P.Call{P.CALL_MVIEW, 12},
                                          P.Call{P.CALL_MVWRITE, 12}]))
    row("npy_copyin_sync_not_last", Bool.not(seq(ti, [P.Call{P.CALL_MVIEW, 12}, P.Call{P.CALL_SYNC, 0}])))
    row("npy_copyin_no_mmap", Bool.not(seq(ti, [P.Call{P.CALL_MMAP, 12}])))
    row("npy_copyout_sync_first", seq(to, [P.Call{P.CALL_SYNC, 0}, P.Call{P.CALL_MVIEW, 12},
                                           P.Call{P.CALL_MVWRITE, 12}]))
    # device.py:315-318: the two bodies differ only in WHICH length they use
    # (`src.nbytes` against `dest.nbytes`) and the trace cannot tell them apart,
    # so the equality of the two traces IS the claim that they are the same
    # three calls in the same order. An `P.npy.copyout` that ordered its calls
    # differently moves exactly this row.
    row("npy_copyin_is_copyout", P.call_list_eq(P.Tr.calls(ti), P.Tr.calls(to)))
    urow("npy_copyin_ncalls", P.Tr.ncalls(ti))
    urow("npy_copyout_ncalls", P.Tr.ncalls(to))
    lrow("npy_copyin_len", P.Tr.args(P.CALL_MVWRITE(), P.Tr.calls(ti)))
    lrow("npy_copyout_len", P.Tr.args(P.CALL_MVWRITE(), P.Tr.calls(to)))
    # THE SOURCE'S LENGTH, NOT THE BUFFER'S: 5 bytes into a 12-byte buffer
    # writes FIVE. MEASURED: `a._copyin(st.buf, memoryview(bytes(5)))` moves five.
    +s : P.Tr <- IO.pure(P.Tr, P.npy.copyin(5, P.Tr.of()))
    lrow("npy_copyin_short", P.Tr.args(P.CALL_MVWRITE(), P.Tr.calls(s)))
    row("npy_copyin_view_short", P.u32_list_eq(P.Tr.args(P.CALL_MVIEW(), P.Tr.calls(s)), [5]))
    urow("npy_copyin_sync_n", P.Tr.count(P.CALL_SYNC(), P.Tr.calls(s)))

# --- 5: the two REFUSALS, device.py:270 and :328 -----------------------------
def t_refuse() -> IO(Unit):
  do IO<Unit>:
    # :270 -- `assert size > 0`. The refusal is recorded and the mmap never
    # happens, which is what `npy_alloc0_no_mmap` reads.
    +z : P.Tr <- IO.pure(P.Tr, P.npy.alloc(0, P.Tr.of()))
    row("npy_alloc0_order", seq(z, [P.Call{P.CALL_REFUSE, P.REFUSE_ALLOC()}]))
    urow("npy_alloc0_n", P.Tr.ncalls(z))
    urow("npy_alloc0_mmaps", P.Tr.count(P.CALL_MMAP(), P.Tr.calls(z)))
    row("npy_alloc0_no_mmap", Bool.not(seq(z, [P.Call{P.CALL_MMAP, 0}])))
    row("npy_alloc0_refused", P.Tr.refused(z))
    srow("npy_alloc0_msg", P.npy.alloc_msg(0))
    srow("npy_alloc1_msg", P.npy.alloc_msg(1))
    # :328 -- the host guard. MEASURED against `map_ok`'s two tags.
    +g : P.Tr <- IO.pure(P.Tr, P.npy.map(P.HOST_CPU(), P.HOST_CPU(), P.Tr.of()))
    +b : P.Tr <- IO.pure(P.Tr, P.npy.map(P.HOST_OTHER(), P.HOST_CPU(), P.Tr.of()))
    urow("npy_map_ok_n", P.Tr.ncalls(g))
    row("npy_map_ok_not_refused", Bool.not(P.Tr.refused(g)))
    urow("npy_map_bad_n", P.Tr.ncalls(b))
    row("npy_map_bad_refused", P.Tr.refused(b))
    row("npy_map_bad_order", seq(b, [P.Call{P.CALL_REFUSE, P.REFUSE_MAP()}]))
    row("npy_map_bad_is_alloc_refuse", Bool.not(seq(b, [P.Call{P.CALL_REFUSE, P.REFUSE_ALLOC()}])))
    srow("npy_map_bad_msg", P.MSG_MAP("NPY"))
    row("npy_map_ok_same", D.map_ok(P.HOST_CPU(), P.HOST_CPU()))
    row("npy_map_ok_diff", Bool.not(D.map_ok(P.HOST_OTHER(), P.HOST_CPU())))
    urow("npy_refuse_n_alloc", P.Tr.count(P.CALL_REFUSE(), P.Tr.calls(z)))
    urow("npy_refuse_n_map", P.Tr.count(P.CALL_REFUSE(), P.Tr.calls(b)))
    # neither refusal is ever nested inside another, so the `+refused` on
    # `P.Tr.refuse.at`'s binder is not exercised and the trace cannot tell a
    # nested refusal from an un-nested one. SEE THE MUTATION TABLE.
    urow("npy_refuse_nested", 0)

# --- 6: the FREE, device.py:310-312 ------------------------------------------
def t_free() -> IO(Unit):
  do IO<Unit>:
    +f : P.Tr <- IO.pure(P.Tr, P.npy.free(False{}, P.Tr.of()))
    +r : P.Tr <- IO.pure(P.Tr, P.npy.free(True{}, P.Tr.of()))
    urow("npy_free_n", P.Tr.ncalls(f))
    urow("npy_free_munmaps", P.Tr.count(P.CALL_MUNMAP(), P.Tr.calls(f)))
    row("npy_free_no_refusal", Bool.not(P.Tr.refused(f)))
    urow("npy_free_remote_n", P.Tr.ncalls(r))
    urow("npy_free_remote_munmaps", P.Tr.count(P.CALL_MUNMAP(), P.Tr.calls(r)))

# --- 7: the INHERITED arithmetic, device.py:330 ------------------------------
def t_inherit() -> IO(Unit):
  do IO<Unit>:
    urow("npy_offset_8", P.npy.offset(4096, 8))
    urow("npy_offset_0", P.npy.offset(4096, 0))
    row("npy_offset_adds", U32.is_eq(P.npy.offset(4096, 8), 4104))
    row("npy_offset_not_identity", U32.is_ne(P.npy.offset(4096, 8), 4096))
    urow("npy_map_storage_args", P.MAP_STORAGE_ARGS())
    row("npy_map_args_differ", U32.is_ne(P.MAP_STORAGE_ARGS(), P.ALLOC_STORAGE_ARGS()))
    urow("npy_itemsize_uint8", S.Dt.itemsize(S.uint8()))
    urow("npy_itemsize_uint64", S.Dt.itemsize(S.uint64()))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_args()
    b : Unit <- t_no()
    +c : Unit <- t_alloc()
    d : Unit <- t_copy()
    +e : Unit <- t_refuse()
    f : Unit <- t_free()
    g : Unit <- t_inherit()
    IO.print("npy-done=1")

# THE MUTATION TABLE. Every number below is `.agents/slop/mutate.py`'s output.
# The harness applies one edit to a scratch copy, runs the INTERPRETED lane, and
# diffs the row NAMES; the useful column is "rows MOVED", because a mutation that
# moves nothing measures what this gate does NOT see.
#
# | # | the edit | rows moved | what it is testing |
# | --- | --- | --- | --- |
# | M1 | `renderers or [Renderer]` -- the EMPTY list survives | 3 | :4's `[]` becoming `[Renderer]`, which is ONE TOKEN of Python and the headline claim of this file. Three rows and not one because `npy_arg_render_effective`, `npy_arg_render_is_default` and `npy_arg_render_not_empty` are three readings of the same field: a device with zero renderers, a device with the default one, and a device that is not the empty list. |
# | M2 | `P.npy.mmap` rounds the size up to a page | 4 | that `HostAllocator` does NOT round, against `BNXTAllocator._alloc` (ops_rdma.py:40) which rounds to `0x1000`. It moves `npy_alloc_args`, `npy_alloc_raw`, `npy_alloc_no_pad` and `npy_alloc_views` -- and NOT `npy_alloc_view_exact`, because that row reads `P.npy.view_bytes` rather than the mmap argument. That is the honest shape: the two functions are separate and so are their rows. |
# | M3 | `synchronize` moves AFTER the view and the write | 3 | device.py:322's `self.dev.synchronize()` FIRST. `npy_copyin_sync_first`, `npy_copyin_sync_not_last` and `npy_copyin_is_copyout` move -- the last one because the two traces stop being equal. |
# | M4 | `_copyin` copies the BUFFER's length, not the source's | 2 | device.py:316's `src.nbytes`. A 5-byte upload must write FIVE bytes even into a 12-byte buffer, because the length is the memoryview being assigned and a longer one RAISES rather than clamping. |
# | M5 | `_map`'s host guard is dropped | 4 | device.py:328's `if Device[buf.device].host != self.dev.host: raise`. It moves the two `npy_map_bad_*` rows and `npy_refuse_n_map`, and nothing on the GOOD fixture -- which is the point of having both. |
# | M6 | `_free` always munmaps | 2 | device.py:310's `if (remote:=getattr(self.dev,"remote",None)) is not None`. `NPY` has no `remote`, so the real trace is EMPTY and `npy_free_n` is the row that says so. `npy_free_remote_n` does NOT move, because the remote arm already munmaps -- the pair is the claim. |
# | M7 | `alloc`'s `assert size > 0` is dropped | 6 | device.py:270. The most rows of any mutation here, and all six are the refusal: the order row, the two counts, `no_mmap`, `refused` and the refuse-count. A gate that only had `npy_alloc0_refused` would miss that the MMAP still happened. |
# | M8 | `_offset` returns `buf` UNCHANGED -- the RDMA rule, not the host one | 3 | device.py:330's `buf + offset`, against `BNXTAllocator._offset` (ops_rdma.py:52) which returns `buf`. Two devices, one line of Python each, OPPOSITE answers, and the two files' gates are the only thing that tells them apart. |
# | M9 | the refusal ENTRY is guarded on `refused` as well | 2 | the arrangement `ops_webgpu.bend` found in itself: the failing call is recorded, so its own `refused` must still be False on entry. Guarding both would make every refusal vanish and `npy_alloc0_*` would read as "no refusal happened". |
# | M10 | a comment-only edit | 0 -- THE CONTROL | a table with no row that CANNOT move is a table of coincidences. |
#
# what this gate still does not see, and it is a short list:
#
#   1. THE ROUND TRIP ITSELF. The CPython oracle runs it -- allocate 12 bytes,
#     write 0..11, read them back, compare -- and `npy_roundtrip=True` is printed
#     by the ORACLE and not by this file, because computing it in Bend would mean
#     simulating `mmap` and then checking my own simulation. What this file gates is
#     the trace; the oracle gates the bytes, and they are separate claims about
#     separate things.
#   2. `npy_ifaces_len = 0` is a CONSTANT row: `NpyDevice.ifaces` is inherited
#     from `Compiled` and is `[]` in device.py:377, so nothing in this file can
#     move it and M-table entries that would try are not in the table. It is here
#     because a reader counting devices should see that NPY has no interface --
#     which is the whole of the difference between `NpyDevice.__init__` and
#     `RDMADevice.__init__`.
#   3. THE MMAP'S OWN FAILURE. `Allocator.alloc` retries once on RuntimeError and
#     then raises a `MemoryError` naming the size (device.py:283-286).
#     `device.bend`'s `alloc_try` owns that control flow; this file does not call
#     it, so an OOM retry is not exercised here.
#   4. `cpu_profile` (WALL 2) wraps both copies and writes a profile event under
#     PROFILE. It does not change the call sequence and nothing checks that.
#   5. THE DEVICE'S OTHER HOSTS. `Device['NPY'].host` is `"CPU"` here because the
#     machine is single-node (device.py:418). A machine with a `remote:` peer
#     group answers `CPU:<host>:<port>` and `npy_host` would print that instead --
#     which is `device.bend`'s `host_remote` row, not this file's.
