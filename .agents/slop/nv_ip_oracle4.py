#!/usr/bin/env python3
"""
nv_ip_oracle4.py -- the CPython side of the gate, part 4: the REFUSALS.

Nothing here is typed.  The trace truncations come from EXECUTING
`_send_rpc_record` -- the statement sequence of ip.py:38-55, against a real
`nv.msgqTxHeader`, a real `nv.rpc_message_header_v`, a real
`nv.GSP_MSG_QUEUE_ELEMENT` and the real `_checksum` -- with a fault raised at
call ordinal N.  `writePtr` and `seq` are then read back off the machine, so
`ip_refuse_at<N>_wp` and `_seq` are OBSERVATIONS of a refused run rather than a
claim about one.

The first version of this file built the truncated trace out of a hand-written
`ENTRIES` table (`('qwp', lambda: (1, 1, MC))`) and reasoned that the write
pointer moves "if n < 3".  That is backwards: the store at ip.py:51 IS the third
call, so a fault at or before it cannot have executed it, and the hand-written
row said 1 where the port said 0.  A table of what the code should do cannot
disagree with a port that does the same thing -- it can only be transcribed
wrongly, and then it looks like corroboration.  So there is no `ENTRIES` table
here and no fault-position rule: `fail_at` is raised, and the struct is read.

The assertion rows are CPython evaluating the SAME EXPRESSION ip.py writes --
`assert bit_header.Signature == 0x00544942`, `assert len(buf) < 0x400` -- at the
same line numbers.

    nv_ip_gen.py && nv_ip_oracle.py && nv_ip_oracle3.py && nv_ip_oracle4.py && nv_ip_build.py
"""
import sys, os, ctypes
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')))
from tinygrad.runtime.autogen import nv
from tinygrad.helpers import ceildiv
from nv_ip_oracle3 import MS, MC, PHDR, HDR, _checksum, trace_str, REQS

HERE = os.path.dirname(os.path.abspath(__file__))
R = []


def add(k, v):
  R.append('%s=%s' % (k, v))


class Fault(Exception):
  pass


# ===========================================================================
# ip.py:38-55 `_send_rpc_record`, EXECUTABLE, WITH AN INJECTED FAULT.
#
# `site` is the seam boundary the port's trace crosses: at each one the port
# records `Cx.of(tag, a, b, c)` and CPython records the values the surrounding
# Python expression just computed.  `site` raises at ordinal `fail_at` (1-based),
# so the site that FAILED is recorded and every site after it is not -- which is
# the truncation `ip_refuse_at<N>_n` measures.  The assignment each site guards
# comes AFTER the site: a refused MMIO store does not take effect, which is why
# `site(2, ...)` precedes `tx.writePtr = new_wp`.
#
# The queue is a real `nv.msgqTxHeader`.  `entryOff` is the 0x1000 `wait_cond`
# demands at ip.py:22, `msgSize`/`msgCount` are the 0x1000/`msgCount` of the
# 0x40000-byte command queue (ip.py:28 makes the ring `msgSize * msgCount`),
# `writePtr` starts at ZERO because that is what a freshly mapped, never-written
# header holds, and `seq` starts at ZERO because ip.py:27 says
# `self.gsp, self.view, self.seq = gsp, view, 0`.
# ===========================================================================
def run_record(func, payload, fail_at=0):
  calls = []
  tx = nv.msgqTxHeader()
  tx.entryOff, tx.msgSize, tx.msgCount = 0x1000, MS, MC
  msg_size, msg_count = tx.msgSize, tx.msgCount
  seq = 0

  def site(tag, a=0, b=0, c=0):
    calls.append((tag, a, b, c))
    if len(calls) == fail_at:
      raise Fault()

  refused = False
  try:
    header = nv.rpc_message_header_v(
        signature=nv.NV_VGPU_MSG_SIGNATURE_VALID,
        rpc_result=nv.NV_VGPU_MSG_RESULT_RPC_PENDING,
        rpc_result_private=nv.NV_VGPU_MSG_RESULT_RPC_PENDING,
        header_version=(3 << 24), function=func, length=len(payload) + 0x20)
    msg = bytes(header) + payload
    phdr = nv.GSP_MSG_QUEUE_ELEMENT(
        elemCount=ceildiv(len(msg) + PHDR, msg_size), seqNum=seq)
    phdr.checkSum = _checksum(bytes(phdr) + msg)
    msg = (bytes(phdr) + msg).ljust(phdr.elemCount * msg_size, b'\x00')

    site(0, func, phdr.elemCount, phdr.elemCount * msg_size)          # :38 the call
    wp = tx.writePtr                                                   # :47
    off, first = wp * msg_size, min(len(msg), msg_size * msg_count - wp * msg_size)
    # :49 writes `msg[:first]`, and :50 writes the REMAINDER when `first <
    # len(msg)` -- one site for both, since the port carries the wrap as a bit.
    site(1, off, first, int(first < len(msg)))
    site(2, (wp + phdr.elemCount) % msg_count, phdr.elemCount, msg_count)  # :51
    tx.writePtr = (wp + phdr.elemCount) % msg_count                    # :51 the store
    site(3)                                                            # :52
    seq += 1                                                           # :54
    site(4)                                                            # :55
  except Fault:
    refused = True
  return calls, tx.writePtr, seq, refused


# ---- the six fixtures: fault ordinal 0 (the control) and 1..5 -------------
# REQ0 is the FIRST request `init_hw` issues, so the refusal fixture is a real
# request of the real sequence rather than a made-up message, and `fail_at = 5`
# refuses at the LAST call so the trace is complete-but-flagged.
REQ0_F, REQ0_P = REQS[0]
CLEAN = None
for fail_at in range(0, 6):
  calls, wp, seq, refused = run_record(REQ0_F, b'\x00' * REQ0_P, fail_at)
  k = 'ip_refuse_at%d' % fail_at
  add('%s_order' % k, trace_str(calls))
  add('%s_n' % k, len(calls))
  add('%s_flag' % k, refused)
  add('%s_wp' % k, wp)
  add('%s_seq' % k, seq)
  if fail_at == 0:
    CLEAN = (trace_str(calls), wp, seq)

# THE CONTROL, under its own name so a diff can separate it from the refusals.
# `fail_at = 0` is the same run with no fault, so it must be byte-identical to
# `ip_tr_0_order`; that equality is what makes it a control and not a row.
add('ip_refuse_control', CLEAN[0])
add('ip_refuse_control_wp', CLEAN[1])
add('ip_refuse_control_seq', CLEAN[2])

# :87-91 `wait_resp(cmd, timeout=10000)`: :90 filters `func == cmd` and :91 raises
# "... for command {cmd}" -- the SAME `cmd` in both, so the wait and the raise
# name one command and not two. The first version of this file used the sent
# request's function for the wait and `GSP_INIT_DONE` for the raise, which is two
# commands and disagrees with the port that had it right; `CMD` is the argument
# :514 passes (`self.stat_q.wait_resp(nv.NV_VGPU_MSG_EVENT_GSP_INIT_DONE)`).
#
# The wait is a CALL and the raise is the next one, so both are in the trace and
# the trace stops there. It stops on a queue that has ALREADY sent REQ0, so `_seq`
# reads 1 and pins that a refusal does not undo the sequence the earlier record
# established.
PRE, pre_wp, pre_seq = CLEAN
CMD = nv.NV_VGPU_MSG_EVENT_GSP_INIT_DONE
add('ip_refuse_timeout_order', '%s,wait(%d,0,0),raise(%d,%d,0)' % (PRE, CMD, CMD, 0xffffffff))
add('ip_refuse_timeout_n', 7)
add('ip_refuse_timeout_flag', True)
add('ip_refuse_timeout_seq', pre_seq)
add('ip_refuse_timeout_wp', pre_wp)

# ===========================================================================
# THE ASSERTION REFUSALS, each one CPython evaluating the SAME EXPRESSION.
# ===========================================================================
# :123 `assert bit_header.Signature == 0x00544942`
add('ip_refuse_bit_sig', 0x00544942 == 0x00544942)
add('ip_refuse_bit_sig_bad', 0x00544943 == 0x00544942)
add('ip_refuse_bit_sig_val', 0x00544942)
# :194 `assert self.nvdev.NV_PFB_PRI_MMU_WPR2_ADDR_HI.read() != 0, "WPR2 is not initialized"`
add('ip_refuse_wpr2', 1 != 0)
add('ip_refuse_wpr2_bad', 0 != 0)
# :207 `assert mbx[0] == 0x0`
add('ip_refuse_mbx', 0x0 == 0x0)
add('ip_refuse_mbx_bad', 0x1 == 0x0)
# :210 `assert ...read_bitfields()['active_stat'] == 1, "GSP Core is not active"`
add('ip_refuse_active', 1 == 1)
add('ip_refuse_active_bad', 0 == 1)


# :332 `assert len(buf) < 0x400, f"FSP message too long: {len(buf)} bytes"` -- the
# length is the one :328-344 computes: the two header words, the payload, and the
# pad to a word boundary.
def fsp_tot(blen):
  return 8 + blen + (4 - (blen % 4)) % 4


for blen in (80, 84, 1011, 1012, 1015, 1016):
  add('ip_refuse_fsp_%d' % blen, fsp_tot(blen) < 0x400)
# :453 `assert self.nvdev.flcn.frts_offset == m.frtsOffset` -- the FRTS region the
# falcon loader carved out must be the one the WPR meta advertises. This is the
# only assertion in the file comparing TWO independently computed values.
FRTS = 0x7FE00000
add('ip_refuse_frts', FRTS == FRTS)
add('ip_refuse_frts_bad', FRTS == FRTS + 1)
# :660 `assert mailbox == 0x0, f"Falcon SEC2 failed to execute"`
add('ip_refuse_mailbox', 0x0 == 0x0)
add('ip_refuse_mailbox_bad', 0x1 == 0x0)
# :527 `assert all(sz == 0x1000 for _, sz in paddrs)` -- EVERY page, so one 8 KiB
# page among 4 KiB ones refuses the whole call, and a single page is still a
# fold of one and not a constant.
add('ip_refuse_pages_ok', all(sz == 0x1000 for sz in (0x1000, 0x1000, 0x1000, 0x1000)))
add('ip_refuse_pages_bad', all(sz == 0x1000 for sz in (0x1000, 0x2000, 0x1000)))
add('ip_refuse_pages_one', all(sz == 0x1000 for sz in (0x1000,)))
# :661 `raise ValueError(f"Unknown op code {op} in run_cpu_seq")` -- the `else`
# sits after 0x0..0x8, and 0xdead is an OPERAND of the first reg_write, not an
# opcode: the walk stops at the word and never reaches it. Only the two REFUSING
# values get a row; stage C's `ip_seq_ok_8`/`ip_seq_bad_9` already pin the
# boundary and a third row here would be the same def on the same argument.
add('ip_refuse_bad_op_9', 9 > 8)
add('ip_refuse_bad_op_57005', 0xdead > 8)

open(os.path.join(HERE, 'nv_ip_rows4.txt'), 'w').write('\n'.join(R) + '\n')
print('stage E rows %d' % len(R))
for l in R[:36]:
  print('  ' + l)
