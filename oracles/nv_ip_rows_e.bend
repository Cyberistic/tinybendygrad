# ===========================================================================
# STAGE E -- THE REFUSALS.
#
# A Python `raise` or `assert` in the middle of a sequence is not a branch here:
# it is a TRUNCATION. `Tr.emit` records nothing once the seam has reported a
# failure, so a refusal leaves a trace that stops at the failing call and every
# later call is simply absent -- no guard anywhere downstream, and no third kind
# of def. `ip_refuse_at<N>_order` is the row that says so, and the trace it prints
# is a PREFIX of `ip_tr_0_order` for every N in 1..5.
#
# The failing call IS recorded: it is what the seam refused. The first version of
# this guard skipped it (three of the four emit sites in ops_webgpu.bend were
# guarded, the fourth was not, and four pops and one create survived a refusal at
# pop 1 -- which is not what Python does). `ip_refuse_at1_n=1` is the row.
#
# The NON-TRACE refusals are assertions on DEVICE DATA this file cannot reach, so
# what is ported is the PREDICATE and the value is the seam's: `ip_refuse_*` below
# is a row per assertion with the exact Python expression and its Python line.
# ===========================================================================

def t_refuse() -> IO(Unit):
  do IO<Unit>:
    t_refuse_trace()
    t_refuse_asserts()

# --- the trace truncations -------------------------------------------------
# ONE fixture per refusal ordinal. `fail_at` is the call ordinal the seam refuses,
# 0 = never, and the suite walks 1..5 -- which is every call a single RPC record
# makes, so `at5` refuses at the LAST call and the trace is complete-but-flagged.
def t_refuse_trace() -> IO(Unit):
  do IO<Unit>:
    t_ref_at(1)
    t_ref_at(2)
    t_ref_at(3)
    t_ref_at(4)
    t_ref_at(5)
    t_ref_clean()

def t_ref_at(+n: U32) -> IO(Unit):
  do IO<Unit>:
    +r : Rq <- IO.pure(Rq, rp.record(72, 928, 0, Tr.fail_at(Tr.of(), n)))
    +t : Tr <- IO.pure(Tr, Rq.tr(r))
    +k : String <- IO.pure(String, String.concat(["ip_refuse_at", U32.show(n), "_"]))
    urow(String.concat([k, "n"]), Tr.ncalls(t))
    srow(String.concat([k, "order"]), tr.show(t))
    row(String.concat([k, "flag"]), Tr.refused(t))
    urow(String.concat([k, "wp"]), Tr.wp(t))
    urow(String.concat([k, "seq"]), Tr.seq(t))

# `_wp` is the write pointer the port is left holding and `_seq` the sequence;
# together they are the rows that say the statements AFTER the failing call did
# not run. `_wp` first moves at ordinal 4 (the store at :51 IS the third call, so
# a refusal at or before it cannot have executed it) and `_seq` first moves at
# ordinal 5 (:54 `self.seq += 1` sits between the barrier and the doorbell).

# `fail_at = 0` is the clean fixture, and it is the CONTROL: it prints the same
# order as `ip_tr_0_order` and nothing is flagged. A gate with no non-movement
# fixture has a `match`'s catch-all arm that is dead code.
def t_ref_clean() -> IO(Unit):
  do IO<Unit>:
    +t : Tr <- IO.pure(Tr, Rq.tr(rp.record(72, 928, 0, Tr.fail_at(Tr.of(), 0))))
    urow("ip_refuse_at0_n", Tr.ncalls(t))
    srow("ip_refuse_at0_order", tr.show(t))
    row("ip_refuse_at0_flag", Tr.refused(t))
    urow("ip_refuse_at0_wp", Tr.wp(t))
    urow("ip_refuse_at0_seq", Tr.seq(t))
    srow("ip_refuse_control", tr.show(t))
    urow("ip_refuse_control_wp", Tr.wp(t))
    urow("ip_refuse_control_seq", Tr.seq(t))

# --- the assertion refusals, one row each -------------------------------
# :123 `assert bit_header.Signature == 0x00544942` -- the VBIOS BIT header's
# signature. Wrong ROM, wrong offset, or a device that is not a GSP part. Bend has
# no hex literals, so the constant is decimal 5523778 and `ip_refuse_bit_sig_val`
# prints it back: the transcription is the only place a wrong digit can hide.
def ref.bit_sig(+sig: U32) -> Bool: U32.is_eq(sig, 5523778)

# :194 `assert self.nvdev.NV_PFB_PRI_MMU_WPR2_ADDR_HI.read() != 0` -- the falcon
# image did not land. Non-zero means LOADED, so the predicate is `!= 0`.
def ref.wpr2(+v: U32) -> Bool: U32.is_ne(v, 0)

# :207 `assert mbx[0] == 0x0, f"Booter failed to execute, mailbox is ..."`
def ref.mbx(+v: U32) -> Bool: U32.is_eq(v, 0)

# :210 `assert ...read_bitfields()['active_stat'] == 1, "GSP Core is not active"`
def ref.active(+v: U32) -> Bool: U32.is_eq(v, 1)

# :332 `assert len(buf) < 0x400, f"FSP message too long: {len(buf)} bytes"`
def ref.fsp_len(+n: U32) -> Bool: U32.is_lt(n, 1024)

# :453 `assert self.nvdev.flcn.frts_offset == m.frtsOffset` -- the FRTS region the
# falcon loader carved out must be the one the WPR meta advertises. This is the
# only assertion in the file that compares TWO independently computed values, and
# it is the one that catches a WPR-meta layout change.
def ref.frts(+flcn: U32, +meta: U32) -> Bool: U32.is_eq(flcn, meta)

# :660 `assert mailbox == 0x0, f"Falcon SEC2 failed to execute"`
def ref.mailbox(+v: U32) -> Bool: U32.is_eq(v, 0)

# :527 `assert all(sz == 0x1000 for _, sz in paddrs)` -- EVERY page, so a list of
# pages is a fold and a refusal is the first non-4 KiB entry. `am.pages_ok4` is
# four pages; `ip_refuse_pages` is the fold over a list.
def ref.pages_ok(+xs: List<&2, U32>) -> Bool: ref.pages_go(xs, True{})

def ref.pages_go(+xs: List<&2, U32>, +ok: Bool) -> Bool:
  match xs:
    case Nil{}: ok
    case s <> r: ref.pages_go(r, Bool.and(ok, am.page_ok(s)))

# :90-91 `self.cmd_q.wait_resp(cmd)` then, on timeout,
# `raise RuntimeError(f"Timeout waiting for RPC response for command {cmd}")`.
# The wait is a CALL (:90) and the raise is the next one (:91), so the trace holds
# both and stops there -- `rpc.wait` records the wait and `rpc.raise` records the
# refusal that truncates everything after it.
def ref.timeout(+func: U32, +t: Tr) -> Tr: rpc.raise(func, 4294967295, rpc.wait(func, t))

# :661 `raise ValueError(f"Unknown op code {op} in run_cpu_seq")` -- the opcode is
# outside 0x0..0x8, so the walk FREEZES at that word and records nothing for it.
# Only the two refusing values get a row: `ip_seq_ok_8` and `ip_seq_bad_9` in
# stage C already pin the boundary, and a third `ref.bad_op(8)` row here would be
# the same def on the same argument with the same answer.
def ref.bad_op(+op: U32) -> Bool: seq_bad(op)

def t_refuse_asserts() -> IO(Unit):
  do IO<Unit>:
    row("ip_refuse_bit_sig", ref.bit_sig(5523778))
    row("ip_refuse_bit_sig_bad", ref.bit_sig(5523779))
    urow("ip_refuse_bit_sig_val", 5523778)
    row("ip_refuse_wpr2", ref.wpr2(1))
    row("ip_refuse_wpr2_bad", ref.wpr2(0))
    row("ip_refuse_mbx", ref.mbx(0))
    row("ip_refuse_mbx_bad", ref.mbx(1))
    row("ip_refuse_active", ref.active(1))
    row("ip_refuse_active_bad", ref.active(0))
    # the row NAME is the PAYLOAD and the argument is `len(buf)` -- the framed
    # length `fsp.tot`, which is 8 + payload + pad and so always a multiple of 4.
    # Naming the rows by the framed length instead (as the first version did)
    # made `ip_refuse_fsp_1019` a row for a length the shape cannot produce, and
    # collapsed 1011 and 1012 onto one name. The pair 1011/1012 and the pair
    # 1015/1016 are the ones that show the pad is applied BEFORE the comparison.
    row("ip_refuse_fsp_80", ref.fsp_len(fsp.tot(80)))
    row("ip_refuse_fsp_84", ref.fsp_len(fsp.tot(84)))
    row("ip_refuse_fsp_1011", ref.fsp_len(fsp.tot(1011)))
    row("ip_refuse_fsp_1012", ref.fsp_len(fsp.tot(1012)))
    row("ip_refuse_fsp_1015", ref.fsp_len(fsp.tot(1015)))
    row("ip_refuse_fsp_1016", ref.fsp_len(fsp.tot(1016)))
    row("ip_refuse_frts", ref.frts(2145386496, 2145386496))
    row("ip_refuse_frts_bad", ref.frts(2145386496, 2145386497))
    row("ip_refuse_mailbox", ref.mailbox(0))
    row("ip_refuse_mailbox_bad", ref.mailbox(1))
    row("ip_refuse_pages_ok", ref.pages_ok(pages4()))
    row("ip_refuse_pages_bad", ref.pages_ok(pages3()))
    row("ip_refuse_pages_one", ref.pages_ok(pages1()))
    row("ip_refuse_bad_op_9", ref.bad_op(9))
    row("ip_refuse_bad_op_57005", ref.bad_op(57005))
    t_refuse_timeout()

# The timeout fires on a queue that has ALREADY sent REQ0, so the sequence the
# earlier record established is 1 and the refusal must leave it at 1. A fixture
# starting from a zero sequence would print 0 here and could not tell "carried"
# from "never moved" -- which is the same reason the old hand-written row used 3:
# an arbitrary seed makes a carry-unchanged row pass by accident.
def t_refuse_timeout() -> IO(Unit):
  do IO<Unit>:
    +t : Tr <- IO.pure(Tr, ref.timeout(4097, Rq.tr(rp.record(72, 928, 0, Tr.of()))))
    srow("ip_refuse_timeout_order", tr.show(t))
    urow("ip_refuse_timeout_n", Tr.ncalls(t))
    row("ip_refuse_timeout_flag", Tr.refused(t))
    urow("ip_refuse_timeout_seq", Tr.seq(t))
    urow("ip_refuse_timeout_wp", Tr.wp(t))

def pages4() -> List<&2, U32>:
  List.concat(&2, U32, [[4096], [4096], [4096], [4096]])

# one 8 KiB page among three 4 KiB ones: `all(sz == 0x1000)` refuses the WHOLE
# call, and the trace is empty -- :527 is before the send.
def pages3() -> List<&2, U32>:
  List.concat(&2, U32, [[4096], [8192], [4096]])

def pages1() -> List<&2, U32>:
  List.concat(&2, U32, [[4096]])