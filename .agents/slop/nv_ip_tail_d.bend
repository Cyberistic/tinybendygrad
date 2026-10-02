# ===========================================================================
# STAGE D -- THE REQUEST TRACE.
#
# A def here EITHER builds the argument of ONE call (pure, and the gate checks it)
# OR records that call in the trace (and the gate checks the ORDER). There is no
# third kind: every seam is a trace tag and nothing else, so ORDER and IDENTITY
# are gateable even though none of the calls is made.
#
# THE RAISE IS IN THE TRACE. `Tr.emit` records nothing once the seam has reported
# a failure, so a refusal shows up as a TRUNCATED trace and needs no guard of its
# own anywhere downstream. The failing call IS recorded -- it is what the seam
# refused -- so the rule is the one ops_webgpu.bend uses for its four pop sites.
#
# ONE ENTRY, FOUR WORDS. `k` is the seam tag and `a`/`b`/`c` are whatever the call
# needs to be identified: a function id, a byte offset, a count. There is
# deliberately no field for a call's full ARGUMENT list -- those are what the defs
# around this record build, and the gate reads them from the record a def RETURNS.
# ===========================================================================

# ELEVEN TAGS, AND ELEVEN IS THE NUMBER OF CALL SITES THIS FILE EMITS. The list
# used to run to twenty with gaps -- `C_HANDLE`, `C_ALLOC_MEM` and six RPC-kind
# tags that nothing ever passed to `Tr.emit` -- and the gaps were load-bearing
# twice over: they kept the dead constants out of the dead-def audit, and
# `C_ALLOC_MEM` was passed to `rp.record` WHERE PYTHON PASSES A FUNCTION ID, so
# the alloc trace claimed to send function 8 and sent function 4. The tags are
# numbered densely because the gate prints them and a hole in a printed sequence
# is a hole nobody can read.
def C_RPC_SEND() -> U32: 0
def C_QUEUE_WRITE() -> U32: 1
def C_QUEUE_WP() -> U32: 2
def C_BARRIER() -> U32: 3
def C_QUEUE_HEAD() -> U32: 4
def C_WAIT_RESP() -> U32: 5
def C_RPC_RAISE() -> U32: 6
def C_FSP_EMEMC() -> U32: 7
def C_FSP_EMEMD() -> U32: 8
def C_FSP_TAIL() -> U32: 9
def C_FSP_HEAD() -> U32: 10

type Cx is Data:
  Cx{k: U32, a: U32, b: U32, c: U32}

def Cx.of(k: U32, a: U32, b: U32, c: U32) -> Cx:
  Cx{k, a, b, c}

def Cx.k(x: Cx) -> U32:
  match x:
    case Cx{+k, a, b, c}: k

def Cx.a(x: Cx) -> U32:
  match x:
    case Cx{k, +a, b, c}: a

def Cx.b(x: Cx) -> U32:
  match x:
    case Cx{k, a, +b, c}: b

def Cx.c(x: Cx) -> U32:
  match x:
    case Cx{k, a, b, +c}: c

# THE MACHINE STATE OF THE SEAM. `wp` and `seq` are the ring's own fields, so they
# live here rather than being recomputed per call; `handle` is the
# `itertools.count(0xcf000000)` from :348; `fail_at` is the call ordinal at which
# the seam reports a refusal (0 = never, which is every successful fixture).
type Tr is Data:
  Tr{calls: List<&2, Cx>, wp: U32, seq: U32, handle: U32, fail_at: U32, refused: Bool}

def Tr.of() -> Tr: Tr{Nil{}, 0, 0, 3472883712, 0, False{}}
def Tr.of.wp(+wp: U32) -> Tr: Tr{Nil{}, wp, 0, 3472883712, 0, False{}}

def Tr.calls(t: Tr) -> List<&2, Cx>:
  match t:
    case Tr{+calls, wp, seq, handle, fail_at, refused}: calls

def Tr.wp(t: Tr) -> U32:
  match t:
    case Tr{calls, +wp, seq, handle, fail_at, refused}: wp

def Tr.seq(t: Tr) -> U32:
  match t:
    case Tr{calls, wp, +seq, handle, fail_at, refused}: seq

def Tr.handle(t: Tr) -> U32:
  match t:
    case Tr{calls, wp, seq, +handle, fail_at, refused}: handle

def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, wp, seq, handle, fail_at, +refused}: refused

def Tr.ncalls(t: Tr) -> U32:
  match t:
    case Tr{+calls, wp, seq, handle, fail_at, refused}: U32.from_nat(List.length(&2, Cx, calls))

# the refusal at `fail_at`, and the call ordinal the emit is ABOUT
def tr.hit(refused: Bool, fail_at: U32, n: U32) -> Bool:
  Bool.or(refused, U32.is_eq(U32.add(n, 1), fail_at))

# THE SEAM. `Bool.pick` answers its TRUE arm first and the untaken arm does not
# reach the answer, so the accumulator is computed by `tr.pick` and the append is
# the CALL -- see the note on `bump`. The failing call IS appended; everything
# after it is not, which is what makes a refusal a truncation.
def Tr.emit.go(+k: U32, +a: U32, +b: U32, +c: U32, +calls: List<&2, Cx>, +n: U32,
               refused: Bool) -> List<&2, Cx>:
  Bool.pick(List<&2, Cx>, refused, calls, List.append(&2, Cx, calls, [Cx.of(k, a, b, c)]))

def Tr.emit(+k: U32, +a: U32, +b: U32, +c: U32, +t: Tr) -> Tr:
  match t:
    case Tr{+calls, wp, seq, handle, fail_at, +refused}:
      tr.put(t, Tr.emit.go(k, a, b, c, calls, 0, refused), Tr.ncalls(t))

# `refused` is RECOMPUTED from the ordinal the emit was ABOUT, not read: `Tr.ncalls`
# is evaluated before the emit is spliced in, so it counts the calls BEFORE this
# one and `n + 1` is this call's ordinal. Reading `refused` out of the pattern AND
# asking `Tr.hit(t)` for it is two reads of one binder and the compiler refuses it
# as `refused (consumed more than once)` -- which names the field, not the twice.
def tr.put(+t: Tr, +calls: List<&2, Cx>, n: U32) -> Tr:
  match t:
    case Tr{c2, wp, seq, handle, +fail_at, refused}:
      tr.put2(calls, wp, seq, handle, fail_at, tr.hit(refused, fail_at, n))

def tr.put2(+calls: List<&2, Cx>, +wp: U32, +seq: U32, +handle: U32, +fail_at: U32,
            +refused: Bool) -> Tr:
  Tr{calls, wp, seq, handle, fail_at, refused}

def Tr.fail_at(+t: Tr, n: U32) -> Tr:
  match t:
    case Tr{calls, wp, seq, handle, +fail_at, refused}:
      Tr{calls, wp, seq, handle, n, refused}

# ---------------------------------------------------------------------------
# :38-55 `_send_rpc_record`, AND NOTHING ELSE. The five facts the trace carries
# are the five the Python computes, in the order Python computes them:
#
#   length    = len(msg) + 0x20                                  (:40)
#   elemCount = ceildiv(len(header) + len(msg) + 48, msgSize)    (:43)
#   total     = elemCount * msgSize                              (:45)
#   off/first = wp * msgSize, min(total, ring_len - wp * msgSize) (:48)
#   wp'       = (wp + elemCount) % msgCount                      (:51)
#
# and then `seq += 1` (:54) and `NV_PGSP_QUEUE_HEAD[0].write(0x0)` (:55), with a
# memory barrier between the pointer store and the doorbell (:52,:78).
# ---------------------------------------------------------------------------
type Rq is Data:
  Rq{func: U32, plen: U32, elem: U32, total: U32, off: U32, first: U32,
     wraps: Bool, wp: U32, seq: U32, cksum: U32, t: Tr}

def Rq.of(func: U32, plen: U32, elem: U32, total: U32, off: U32, first: U32,
         wraps: Bool, wp: U32, seq: U32, cksum: U32, t: Tr) -> Rq:
  Rq{func, plen, elem, total, off, first, wraps, wp, seq, cksum, t}

def Rq.func(r: Rq) -> U32:
  match r:
    case Rq{+func, plen, elem, total, off, first, wraps, wp, seq, cksum, t}: func

def Rq.plen(r: Rq) -> U32:
  match r:
    case Rq{func, +plen, elem, total, off, first, wraps, wp, seq, cksum, t}: plen

def Rq.elem(r: Rq) -> U32:
  match r:
    case Rq{func, plen, +elem, total, off, first, wraps, wp, seq, cksum, t}: elem

def Rq.total(r: Rq) -> U32:
  match r:
    case Rq{func, plen, elem, +total, off, first, wraps, wp, seq, cksum, t}: total

def Rq.off(r: Rq) -> U32:
  match r:
    case Rq{func, plen, elem, total, +off, first, wraps, wp, seq, cksum, t}: off

def Rq.first(r: Rq) -> U32:
  match r:
    case Rq{func, plen, elem, total, off, +first, wraps, wp, seq, cksum, t}: first

def Rq.wp(r: Rq) -> U32:
  match r:
    case Rq{func, plen, elem, total, off, first, wraps, +wp, seq, cksum, t}: wp

def Rq.seq(r: Rq) -> U32:
  match r:
    case Rq{func, plen, elem, total, off, first, wraps, wp, +seq, cksum, t}: seq

def Rq.cksum(r: Rq) -> U32:
  match r:
    case Rq{func, plen, elem, total, off, first, wraps, wp, seq, +cksum, t}: cksum

def Rq.tr(r: Rq) -> Tr:
  match r:
    case Rq{func, plen, elem, total, off, first, wraps, wp, seq, cksum, +t}: t

# the wire LENGTH: `length=len(msg) + 0x20` at :40, where `msg` is the PAYLOAD.
def rp.length(+plen: U32) -> U32: U32.add(plen, 32)
def rp.msg_size() -> U32: 4096
def rp.msg_count() -> U32: 63
def rp.ring_len() -> U32: U32.mul(rp.msg_size(), rp.msg_count())
def rp.entry_off() -> U32: 4096

# :43 `elemCount = ceildiv(len(msg) + ctypes.sizeof(GSP_MSG_QUEUE_ELEMENT),
# self.tx.msgSize)` -- and `msg` at that point is `bytes(header) + payload`, so
# the 32-byte header is IN the numerator.  Dropping it does not change the answer
# for any of the seven requests (they all round up to one element either way) and
# it changes the answer for a payload near a message boundary.
def rp.elem(+plen: U32) -> U32: cdiv(U32.add(U32.add(plen, 32), 48), rp.msg_size())

def rp.total(+plen: U32) -> U32: U32.mul(rp.elem(plen), rp.msg_size())

# 32 and 48 are `ctypes.sizeof(rpc_message_header_v)` and
# `ctypes.sizeof(GSP_MSG_QUEUE_ELEMENT)`, measured, and they are LITERALS here so
# that `rp.hdr_len`/`rp.phdr_len` keep the names the rows use.

# :48 `off, first = wp * msgSize, min(len(msg), len(queue_mv) - wp * msgSize)`
# and `len(queue_mv)` is `msgSize * msgCount` -- NOT the header's `size`.  On a
# real queue those differ by a page, so the ring length is its own row.
def rp.off(+wp: U32) -> U32: U32.mul(wp, rp.msg_size())
def rp.first(+total: U32, +wp: U32) -> U32:
  U32.min(total, U32.sub(rp.ring_len(), U32.mul(wp, rp.msg_size())))

def rp.wraps(+total: U32, +wp: U32) -> Bool: U32.is_lt(rp.first(total, wp), total)
def rp.wp_after(+wp: U32, +elem: U32) -> U32: U32.mod(U32.add(wp, elem), rp.msg_count())

# ---------------------------------------------------------------------------
# THE CHECKSUM, and this is the part of Stage D that is worth the file.
#
# :32-36 folds a 64-bit XOR over the u64 words of `bytes(phdr) + msg` and returns
# `hi32(c) ^ lo32(c)`.  Bend has no 64-bit integer -- and it does not need one:
# the accumulator is a XOR and `hi32 ^ lo32` COMMUTES with XOR over the words, so
# the whole thing collapses to TWO U32 folds over the 20 U32 words of
# `GSP_MSG_QUEUE_ELEMENT ++ rpc_message_header_v`.
#
# The payoff is that the fold needs the BYTE OFFSETS.  `checkSum` is the ninth
# U32 of the 48-byte element and `function` is the sixteenth of the 32-byte header,
# so a transposed pair or a wrong offset moves the row -- and a COUNT gate would
# see neither.  `ip_rp_<i>_cksum` is the row, and `ip_rp_<i>_w<k>` names every
# word so the offset ITSELF is a row too.
#
# What the fold cannot see is the hi/lo LABEL of a pair. `rp.finish` XORs the two
# accumulators together, so exchanging `rp.pickw`'s arms permutes the words between
# them and the total is unchanged -- that mutation moves zero rows, and that is
# arithmetic rather than a missing fixture. `rp.pair.hi`/`rp.pair.lo`, the first
# design, threaded a `{h, l}` record through the recursion instead of running two
# walks; `Bool.pick` drops its untaken arm, so a self-call inside an arm cannot
# carry state back out, and the record was deleted rather than fixed.
#
# The ONE thing that does not fold is the checksum slot ITSELF: :44 evaluates
# `bytes(phdr)` while `phdr.checkSum` is still zero, so the fold runs over a zero
# there and the value lands afterwards.  `rp.cksum` reproduces that, and the
# `cks_put` row is the slot.
# ---------------------------------------------------------------------------
def rp.w_seq() -> U32: 9
def rp.w_elem() -> U32: 10
def rp.w_version() -> U32: 12
def rp.w_signature() -> U32: 13
def rp.w_length() -> U32: 14
def rp.w_function() -> U32: 15
def rp.w_result() -> U32: 16
def rp.w_result_private() -> U32: 17
def rp.nwords() -> U32: 20

def rp.sig() -> U32: Cn.v(const_of("NV_VGPU_MSG_SIGNATURE_VALID"))
def rp.pending() -> U32: Cn.v(const_of("NV_VGPU_MSG_RESULT_RPC_PENDING"))
def rp.hdr_version() -> U32: U32.shln(3, 24n)

# ONE word of the image, by INDEX. The image is
#   [0..7]   authTagBuffer (zero)          [8]  checkSum   (ZERO here -- see above)
#   [8..15]  aadBuffer (zero)              [9]  seqNum
#   [10]     elemCount                     [11] padding (zero)
#   [12]     header_version                [13] signature
#   [14]     length                        [15] function
#   [16]     rpc_result                    [17] rpc_result_private
#   [18]     sequence (zero)               [19] u (zero)
#
# `elemCount` is at [10] and not [11]. `ip_rp_0_w10` is 1 for the seven requests
# and `ip_rp_0_w11` is 0, read off CPython's `bytes(phdr)`; this comment said the
# other way round for the whole life of the file, which no gate could see because
# a comment is not a row. The FOUR ZERO slots ([8], [11], [18], [19]) have no
# `rp.w_*` constant because `rp.word2` has no arm for them -- the arm would answer
# `0`, and a branch whose only answer is a literal is a comment with a runtime.
def rp.word(+i: U32, +func: U32, +plen: U32, +seq: U32) -> U32:
  rp.word2(rp.which(i), i, func, plen, seq)

# an index past the image reads the LAST word, so a caller that over-runs the
# twenty cannot address past them. `rp.nwords` is the authority for the count.
def rp.which(+i: U32) -> U32: U32.min(i, U32.sub(rp.nwords(), 1))


def rp.word2(+w: U32, +i: U32, +func: U32, +plen: U32, +seq: U32) -> U32:
  Bool.pick(U32, U32.is_eq(w, rp.w_seq()), seq,
    Bool.pick(U32, U32.is_eq(w, rp.w_elem()), rp.elem(plen),
      Bool.pick(U32, U32.is_eq(w, rp.w_version()), rp.hdr_version(),
        Bool.pick(U32, U32.is_eq(w, rp.w_signature()), rp.sig(),
          Bool.pick(U32, U32.is_eq(w, rp.w_length()), rp.length(plen),
            Bool.pick(U32, U32.is_eq(w, rp.w_function()), func,
              Bool.pick(U32, U32.is_eq(w, rp.w_result()), rp.pending(),
                Bool.pick(U32, U32.is_eq(w, rp.w_result_private()), rp.pending(), 0))))))))

# THE FOLD. `u64words` is the u64-aligned pair count: 80 bytes is TEN words, and
# word k is (lo = w[2k], hi = w[2k+1]) on little-endian.
def rp.nu64() -> U32: 10

# the u64 image, ten words, each a PAIR of U32s read little-endian. `pay` is the
# payload's contribution to the XOR and is the SEAM: it is 0 for a zero payload
# and whatever the bytes fold to otherwise.
type W64 is Data:
  W64{lo: U32, hi: U32}

def rp.cksum.xor(+func: U32, +plen: U32, +seq: U32) -> U32:
  rp.finish(rp.fold(U32.to_nat(rp.nu64()), func, plen, seq, True{}, 0),
            rp.fold(U32.to_nat(rp.nu64()), func, plen, seq, False{}, 0))

# THE FOLDS CARRY NO STATE, AND THAT IS THE POINT. The first version threaded
# `h` and `l` -- the two partial XORs -- as parameters, and the self-call could
# never supply them: they are consumed by the accumulator in the computed
# argument and the call is left partial ("observed : @+l:U32 -> U32"). So the fold
# is RECOMPUTED from scratch at each step: the words are a pure function of
# `(func, plen, seq)`, the XOR is associative and commutative, and
# `c ^ (a ^ b) == (c ^ a) ^ b`, so folding from zero every time gives the same
# answer with nothing to thread. `rp.fold` is six lines because there is no state.
# Two `Nat` countdown folds, each with ONE U32 accumulator, over the same ten u64
# words -- and `hi32(c) ^ lo32(c)` is `fold(hi) ^ fold(lo)` because XOR COMMUTES
# with the split. That is what makes a 64-bit checksum computable with no 64-bit
# integer, and it is why the fold is six lines instead of eight. So there are two
# `Nat` countdown folds, each with ONE U32 accumulator, over the same ten u64
# words -- and `hi32(c) ^ lo32(c)` is `fold(hi) ^ fold(lo)` because XOR COMMUTES
# with the split. That is what makes a 64-bit checksum computable with no 64-bit
# integer, and it is why the fold is five lines instead of eight.
def rp.fold(+k: Nat, +func: U32, +plen: U32, +seq: U32, +hi: Bool, +acc: U32) -> U32:
  match k:
    case 0n: acc
    case 1n+p: rp.fold(p, func, plen, seq, hi, rp.acc4(acc, p, func, plen, seq, hi))


# A `Nat` PATTERN BINDER cannot be read twice, so the word index is passed ONCE
# into a def whose own parameter is `+`: `rp.fold` reads `p` exactly once and
# `rp.acc4` reads it once as well, which is all two stateless folds need.

def rp.acc4(+acc: U32, +p: Nat, +func: U32, +plen: U32, +seq: U32, +hi: Bool) -> U32:
  U32.xor(acc, rp.wordof(p, func, plen, seq, hi))

def rp.wordof(+p: Nat, +func: U32, +plen: U32, +seq: U32, +hi: Bool) -> U32:
  rp.word(rp.pickw(p, hi), func, plen, seq)

# u64 word k is the PAIR (lo = the U32 at 8k, hi = the U32 at 8k+4) on
# little-endian, so the two halves are `word[2k]` and `word[2k+1]`. That is the
# WHOLE endianness assumption, and swapping it is invisible to `hi32(c) ^ lo32(c)`
# -- the XOR is symmetric -- so `ip_rp_<i>_cksum` is the row that would see it.
def rp.pickw(+p: Nat, +hi: Bool) -> U32:
  Bool.pick(U32, hi, U32.add(U32.mul(U32.from_nat(p), 2), 1), U32.mul(U32.from_nat(p), 2))

def rp.finish(+h: U32, +l: U32) -> U32: U32.xor(h, l)

# ---------------------------------------------------------------------------
# THE RECORD, :38-55, and it appends FIVE calls in Python's order.
# ---------------------------------------------------------------------------
def rp.record(+func: U32, +plen: U32, +pay: U32, t: Tr) -> Rq:
  rp.rec2(rp.elem(plen), rp.total(plen), func, plen, pay, t)

def rp.rec2(+elem: U32, +total: U32, +func: U32, +plen: U32, +pay: U32, +t: Tr) -> Rq:
  rp.rec3(rp.cksum.xor(func, plen, Tr.seq(t)), elem, total, func, plen, pay, t)

def rp.rec3(+cks: U32, +elem: U32, +total: U32, +func: U32, +plen: U32, +pay: U32, +t: Tr) -> Rq:
  rp.rec4(U32.xor(cks, pay), elem, total, func, plen, t)

def rp.rec4(+cks: U32, +elem: U32, +total: U32, +func: U32, +plen: U32, +t: Tr) -> Rq:
  Rq.of(func, plen, elem, total, rp.off(Tr.wp(t)), rp.first(total, Tr.wp(t)),
        rp.wraps(total, Tr.wp(t)), rp.wp_after(Tr.wp(t), elem), U32.add(Tr.seq(t), 1), cks,
        rp.trace(cks, elem, total, func, t))

def rp.trace(+cks: U32, +elem: U32, +total: U32, +func: U32, +t: Tr) -> Tr:
  rp.trace2(cks, elem, total, func, t, Tr.emit(C_RPC_SEND(), func, elem, total, t))

def rp.trace2(+cks: U32, +elem: U32, +total: U32, +func: U32, t0: Tr, +t1: Tr) -> Tr:
  rp.trace3(cks, elem, total, func, t1, Tr.emit(C_QUEUE_WRITE(), rp.off(Tr.wp(t1)),
                                                 rp.first(total, Tr.wp(t1)),
                                                 rp.wrapbit(total, Tr.wp(t1)), t1))

def rp.wrapbit(+total: U32, +wp: U32) -> U32:
  Bool.pick(U32, rp.wraps(total, wp), 1, 0)

def rp.trace3(+cks: U32, +elem: U32, +total: U32, +func: U32, +t1: Tr, +t2: Tr) -> Tr:
  rp.wp2(elem, t2)

# :51 `self.tx_view[writePtr] = (wp + phdr.elemCount) % self.tx.msgCount` -- the
# pointer store, which must happen BEFORE the doorbell or the GSP reads a stale
# index.  `ip_tr_<i>_order` is the row that says so.
def rp.wp2(+elem: U32, +t: Tr) -> Tr:
  rp.wp3(elem, Tr.wp(t), Tr.seq(t), Tr.emit(C_QUEUE_WP(), rp.wp_after(Tr.wp(t), elem), elem,
                                           rp.msg_count(), t))

def rp.wp3(+elem: U32, +wp: U32, +seq: U32, e: Tr) -> Tr:
  rp.barrier(rp.put_wp(e, rp.wp_after(wp, elem)))

# THE QUEUE FIELDS DO NOT ADVANCE PAST A REFUSAL. Without this the trace is
# truncated but `wp` and `seq` still move -- `ip_refuse_at1_wp` printed 1 against a
# trace holding only the send, which is not what Python does: the statements after
# a `raise` do not execute. So the store is a `Bool.pick` on `refused`, and that is
# the ONLY guard in the file -- it lives in the one def that owns the store.
#
# THE ARMS WERE SWAPPED ONCE, and the first oracle could not see it. It tabulated
# `wp` as "moves if fail_at < 3" and the port -- carrying `refused` in the wrong
# arm -- printed exactly that, so all five rows agreed and the guard was doing the
# precise opposite of its comment. The oracle now EXECUTES the body with the fault
# raised and reads `tx.writePtr` off the struct, and the rows invert. A hand-typed
# table of expected values reproduces a port's mistake whenever the mistake and the
# table are the same mistake.
def rp.put_wp(+e: Tr, +wp: U32) -> Tr:
  rp.put_wp2(e, Bool.pick(U32, Tr.refused(e), Tr.wp(e), wp))

def rp.put_wp2(+e: Tr, +wp: U32) -> Tr:
  Tr{Tr.calls(e), wp, Tr.seq(e), Tr.handle(e), rp.fail_of(e), Tr.refused(e)}

# :52 `System.memory_barrier()` -- between the pointer store and the doorbell.
def rp.barrier(+e: Tr) -> Tr: rp.bump(Tr.emit(C_BARRIER(), 0, 0, 0, e))

# :54 `self.seq += 1` -- between the BARRIER and the DOORBELL, and that position is
# load-bearing: `ip_refuse_at5_seq` is 1 and `ip_refuse_at4_seq` is 0, so a refusal
# at the doorbell leaves the sequence already advanced (:54 ran) and a refusal at
# the barrier leaves it not (:54 did not). Rung the doorbell before bumping would
# have made both rows 0 and the position unfalsifiable.
def rp.bump(+e: Tr) -> Tr: rp.door(rp.bumped(Tr.seq(e), Tr.handle(e), e))

# :55 `NV_PGSP_QUEUE_HEAD[0].write(0x0)` -- the LAST call, after the sequence.
def rp.door(+e: Tr) -> Tr: Tr.emit(C_QUEUE_HEAD(), 0, 0, 0, e)

# :54 `self.seq += 1` -- and past a refusal the sequence does NOT advance, for the
# same reason the write pointer does not: the statements after a `raise` do not
# execute. `rp.bumped` exists because `Bool.pick` answers the arm it takes and the
# other arm never reaches the answer, so a self-call placed INSIDE an arm is
# silently dropped -- the accumulator has to be computed first and the rebuild
# second. The queue fields are `+` PARAMETERS for the same reason the compiler
# cannot re-read one binder twice.
def rp.bumped(+seq: U32, +handle: U32, +e: Tr) -> Tr:
  rp.bumped2(seq, handle, e, Bool.pick(U32, Tr.refused(e), seq, U32.add(seq, 1)))

def rp.bumped2(+seq: U32, +handle: U32, +e: Tr, +s2: U32) -> Tr:
  Tr{Tr.calls(e), Tr.wp(e), s2, handle, rp.fail_of(e), Tr.refused(e)}

def rp.fail_of(+t: Tr) -> U32: tr.fail(t)

def tr.fail(+t: Tr) -> U32:
  match t:
    case Tr{calls, wp, seq, handle, +fail_at, refused}: fail_at

# :57-60 `send_rpc`: ONE record for the first `max_payload` and one CONTINUATION
# record per further `max_payload`. So a payload of exactly `max_payload` is ONE
# record and one byte more is TWO -- and `ip_rp_cont_*_n` is that row.
#
# `>` versus `>=` AT THE BOUNDARY IS NOT A RULE, and this comment used to say it
# was. `rp.cont_more` guards the subtraction and then CEIL-DIVIDES the remainder,
# so at `plen == max_payload` both guards reach `cdiv(0, max_payload) == 0` and
# `rp.cont_n` answers 1 either way -- the mutation table records that as an
# equivalent mutant, not as coverage. What the row really pins is that the
# subtraction happens AFTER the guard, which is the wrap below.
# ---------------------------------------------------------------------------
# `U32.sub` WRAPS, so `plen - max_payload` is 4294901840 for a payload of zero and
# `ip_rp_cont_0_n` printed 65617 records for an empty message. The subtraction is
# therefore inside the guard: `plen > max_payload` FIRST, and only then subtract.
def rp.cont_n(+plen: U32) -> U32:
  U32.add(1, rp.cont_more(plen))

def rp.cont_more(+plen: U32) -> U32:
  Bool.pick(U32, U32.is_gt(plen, rp.max_payload),
            cdiv(U32.sub(plen, rp.max_payload), rp.max_payload), 0)

def rp.cont_func() -> U32: Cn.v(const_of("NV_VGPU_MSG_FUNCTION_CONTINUATION_RECORD"))

# the function `rpc_alloc_memory` SENDS -- a value from the module's `rpc_fns`
# table, NOT a trace tag. Passing `C_ALLOC_MEM()` here is how the alloc trace came
# to claim it sent function 8 while it sent 4.
def rpc.func_alloc() -> U32: Cn.v(const_of("NV_VGPU_MSG_FUNCTION_ALLOC_MEMORY"))

# ---------------------------------------------------------------------------
# :526-536 `rpc_alloc_memory`. The :527 assert is the refusal: EVERY page must be
# 4 KiB, and a single 8 KiB page refuses the whole call.
# ---------------------------------------------------------------------------
def am.page_ok(+sz: U32) -> Bool: U32.is_eq(sz, 4096)
def am.pages_ok2(+sz0: U32, +sz1: U32) -> Bool: Bool.and(am.page_ok(sz0), am.page_ok(sz1))
def am.pages_ok4(+sz0: U32, +sz1: U32, +sz2: U32, +sz3: U32) -> Bool:
  Bool.and(am.pages_ok2(sz0, sz1), am.pages_ok2(sz2, sz3))

# the handle generator, :348 `itertools.count(0xcf000000)`
def hgen.first() -> U32: 3472883712
def hgen.next(+h: U32) -> U32: U32.add(h, 1)
def hgen.n() -> U32: 8

# :533 `bytes(rpc) + b''.join(struct_pte_desc_pte_pde(pte=(paddr >> 12)) for paddr
# in paddrs)` -- a FIXED 56-byte header plus eight per page, and the page count is
# `len(paddrs)`, which the :527 assert has already forced to be 4 KiB each.
def am.plen(+npages: U32) -> U32: U32.add(56, U32.mul(8, npages))

def rpc.am2(+hdev: U32, +hclass: U32, +npages: U32, +t: Tr) -> Rq:
  rpc.am3(hdev, hclass, npages, rp.record(rpc.func_alloc(), am.plen(npages), 0, t))

# :534 `send_rpc` then :535 `wait_resp` -- and the record's fields are CARRIED
# through, so this is the one place the wait's own `wp`/`seq` (which the record
# advanced) must not be read off the pre-wait trace.
def rpc.am3(+hdev: U32, +hclass: U32, +npages: U32, +r: Rq) -> Rq:
  Rq.of(Rq.func(r), Rq.plen(r), Rq.elem(r), Rq.total(r), Rq.off(r), Rq.first(r),
        rp.wraps(Rq.total(r), Tr.wp(Rq.tr(r))), Rq.wp(r), Rq.seq(r), Rq.cksum(r),
        rpc.minted(rpc.wait(rpc.func_alloc(), Rq.tr(r))))

# THE HANDLE IS NOT A CALL. `next(self.handle_gen)` is `itertools.count`, which
# touches no device, so it is QUEUE STATE beside `seq` and `wp` and not a trace
# entry -- recording it as one put it LAST (an emit can only append) where :529
# mints it FIRST. `ip_rp_am_0_order` is the row that saw it.
#
# `Tr.handle` is the NEXT handle to mint, so minting READS it and the bump stores
# the one after. Minting with `hgen.next` instead made the first allocation return
# 0xcf000001 where CPython returns 0xcf000000.
# IT KEEPS THE CALLS. It used to rebuild the trace as `Tr{Nil{}, ...}`, dropping
# the five calls `rp.record` had just appended, so the whole alloc trace was ONE
# entry -- and `rpc.am*` was called by no row, so nothing noticed.
def rpc.minted(+t: Tr) -> Tr:
  match t:
    case Tr{calls, wp, seq, +handle, fail_at, refused}:
      Tr{calls, wp, seq, hgen.next(handle), fail_at, refused}

# ---------------------------------------------------------------------------
# THE DOORBELL RULE, :590-591, and it lives here because it is a TRACE question
# and not a register question:
#   `st.workSubmitToken |= (self.chan_runlists[hObject] << 16) |
#                          ((1 << 30) if self.nvdev.chip_name.startswith("GB2") else 0)`
# The GSP fills in the channel id; the runlist id and, on GB2x ONLY, the
# doorbell-enable bit are added by the driver. So the OR is NOT symmetric between
# the two chip families and a port that always added bit 30 would ring a doorbell
# that does not exist on a GA10 part.
# ---------------------------------------------------------------------------
def door.rl_shift(+rl: U32) -> U32: U32.shln(rl, 16n)
def door.gb2_bit(+chip: String) -> U32: Bool.pick(U32, String.starts_with(chip, "GB2"), 1073741824, 0)
def door.token(+tok: U32, +rl: U32, +chip: String) -> U32:
  U32.or(tok, U32.or(door.rl_shift(rl), door.gb2_bit(chip)))

# ---------------------------------------------------------------------------
# THE ROW HELPERS for the trace: a trace rendered as ONE comma-joined string, so
# an ORDER row is a VALUE the differ can compare and not merely a count. Each
# entry is `tag(a,b,c)`, and the tag NAME is spelled out rather than numbered so a
# row can be read without the source.
# ---------------------------------------------------------------------------
def tr.tagname(+k: U32) -> String:
  Bool.pick(String, U32.is_eq(k, C_RPC_SEND()), "send",
    Bool.pick(String, U32.is_eq(k, C_QUEUE_WRITE()), "qwrite",
      Bool.pick(String, U32.is_eq(k, C_QUEUE_WP()), "qwp",
        Bool.pick(String, U32.is_eq(k, C_BARRIER()), "barrier",
          Bool.pick(String, U32.is_eq(k, C_QUEUE_HEAD()), "doorbell",
            Bool.pick(String, U32.is_eq(k, C_WAIT_RESP()), "wait",
              Bool.pick(String, U32.is_eq(k, C_RPC_RAISE()), "raise",
                Bool.pick(String, U32.is_eq(k, C_FSP_EMEMC()), "ememc",
                  Bool.pick(String, U32.is_eq(k, C_FSP_EMEMD()), "ememd",
                    Bool.pick(String, U32.is_eq(k, C_FSP_TAIL()), "tail",
                      Bool.pick(String, U32.is_eq(k, C_FSP_HEAD()), "head", "?")))))))))))

def tr.one(+x: Cx) -> String:
  String.concat([tr.tagname(Cx.k(x)), "(", U32.show(Cx.a(x)), ",", U32.show(Cx.b(x)), ",",
                 U32.show(Cx.c(x)), ")"])

def tr.show(+t: Tr) -> String: tr.go(Tr.calls(t), False{})

def tr.go(+xs: List<&2, Cx>, +first: Bool) -> String:
  match xs:
    case Nil{}: ""
    case x <> r: String.concat([tr.sep(first), tr.one(x), tr.go(r, True{})])

def tr.sep(+first: Bool) -> String: Bool.pick(String, first, ",", "")

# the `seq` the NEXT record will use -- :54's `self.seq += 1` means the record
# being built uses the CURRENT value and the queue ends up one higher.
# THE PARAMETER AND THE BINDER MUST NOT SHARE A NAME. `def tr.put_seq(+t, seq)`
# with `case Tr{calls, wp, +seq, ...}` binds the binder OVER the parameter, so the
# record is rebuilt with the queue's OWN sequence and `tr.at` is a no-op: all seven
# requests printed `ip_rp_<i>_seq1=1` and every checksum was the sequence-0 value.
# A pattern binder that shadows a parameter is reported as an ARITY error only
# when the names collide with a FIELD; here it silently used the wrong value.
def tr.at(+t: Tr, want: U32) -> Tr: tr.put_seq(t, want)

def tr.put_seq(+t: Tr, want: U32) -> Tr:
  match t:
    case Tr{calls, wp, +cur, handle, fail_at, refused}:
      Tr{calls, wp, want, handle, fail_at, refused}

# ---------------------------------------------------------------------------
# :77 `self.rx_view[0] = (self.rx_view[0] + round_up(hdr.length, msgSize) //
# msgSize) % msgCount` -- the RESPONSE pointer advances by the ROUNDED length, so
# a header of 0x1001 consumes TWO elements and not one, and the modulo is by
# `msgCount` and not by the ring length. `ip_rp_rx_*` walks six (rx, length)
# pairs so the boundary, the modulo and the rounding each have a row.
# ---------------------------------------------------------------------------
def rx_up(+hlen: U32) -> U32: ru(hlen, rp.msg_size())
def rx_elems(+hlen: U32) -> U32: U32.div(rx_up(hlen), rp.msg_size())
def rx_after(+rx: U32, +hlen: U32) -> U32: U32.mod(U32.add(rx, rx_elems(hlen)), rp.msg_count())
def rx_tag(+rx: U32, +hlen: U32) -> String:
  String.concat([U32.show(rx), "->", U32.show(rx_after(rx, hlen))])

def rp.rx_tag(+rx: U32, +hlen: U32) -> String: rx_tag(rx, hlen)
def rp.rx_after(+rx: U32, +hlen: U32) -> U32: rx_after(rx, hlen)
def rp.rx_up(+hlen: U32) -> U32: rx_up(hlen)
def rp.rx_elems(+hlen: U32) -> U32: rx_elems(hlen)

# :74 `is_err_state |= hdr.function in {OS_ERROR_LOG, MMU_FAULT_QUEUED}` -- the
# two-event SET is data, and `ip_rp_iserr_*` reaches both members and two
# non-members, so the row says "two of these four are in the set".
def is_err(+f: U32) -> Bool:
  Bool.or(U32.is_eq(f, Cn.v(const_of("NV_VGPU_MSG_EVENT_OS_ERROR_LOG"))),
          U32.is_eq(f, Cn.v(const_of("NV_VGPU_MSG_EVENT_MMU_FAULT_QUEUED"))))

def rp.is_err(+f: U32) -> Bool: is_err(f)

# eight `next()` calls on `itertools.count(0xcf000000)`, folded -- :348.
def hgen.nxt7() -> U32: hgen.go(7n, hgen.first())

# A `Nat` countdown -- a `U32` one cannot destructure at all: `case 1r:` is
# "expected : a numeric literal" and `case 1+r:` is "expected : 1 patterns".
def hgen.go(+k: Nat, +h: U32) -> U32:
  match k:
    case 0n: h
    case 1n+p: hgen.go(p, hgen.next(h))

# ---------------------------------------------------------------------------
# :328-344 `kfsp_send_msg`, in trace order: EMEMC, one EMEMD per word, TAIL,
# HEAD. `QUEUE_TAIL` is `len(buf) - 4` -- the padded total MINUS the last header
# word -- and `QUEUE_HEAD` is 0. The EMEMD count is the padded word count, which
# is what `ip_fsp_tr_*_nwords` pins; a port that wrote one EMEMD per PAYLOAD
# byte would write four times as many.
# ---------------------------------------------------------------------------
def fsp.trace(+nvmd: U32, +blen: U32) -> Tr: fsp.tr2(nvmd, blen, Tr.of())

def fsp.tr2(+nvmd: U32, +blen: U32, +t: Tr) -> Tr:
  fsp.tr3(nvmd, blen, t, Tr.emit(C_FSP_EMEMC(), fsp.tail_off(), fsp.aincw(), fsp.aincr(), t))

def fsp.tr3(+nvmd: U32, +blen: U32, +t: Tr, +e: Tr) -> Tr:
  fsp.ememd(nvmd, fsp.words(nvmd, blen), U32.to_nat(fsp.words(nvmd, blen)), e)

# THE COUNTDOWN IS THE FIRST ARGUMENT -- a self-call is read LEFT TO RIGHT and
# each argument must pass unchanged until one shrinks, so putting `t` (which the
# emit rebuilds) in front of the shrinking `p` is "expected : a decreasing
# self-call". The queue is threaded last and the emit is its argument.
# THE COUNTDOWN IS A `U32` AND IT IS A PARAMETER, not a pattern binder. The index
# is needed twice -- once as the countdown handed to the self-call and once to
# index the word table -- and a `Nat` pattern BINDER cannot be read twice (there
# is no `case 1n+ +p:` spelling), while a `+k` PARAMETER can. So the count is a
# `U32` matched with `case 0:` / `case 1+r:` and the countdown argument comes first
# so the self-call is DECREASING.
def fsp.ememd(+nvmd: U32, +total: U32, +k: Nat, +t: Tr) -> Tr:
  match k:
    case 0n: fsp.do_tail(t)
    case 1n+p: fsp.ememd(nvmd, total, p, fsp.put(t, fsp.word(total, k, nvmd)))

# THE WORD INDEX IS `total - k`: word 0 is the first EMEMD, word 1 is the second,
# and every word after that is payload -- whose bytes are the seam, so it records
# 0. `k` is a `+` PARAMETER here (not a pattern binder) so the two reads are legal.
def fsp.word(+total: U32, +k: Nat, +nvmd: U32) -> U32:
  Bool.pick(U32, U32.is_eq(U32.from_nat(k), total), fsp.w0(),
    Bool.pick(U32, U32.is_eq(U32.from_nat(k), U32.sub(total, 1)), fsp.w1(nvmd), 0))

def fsp.put(+t: Tr, +w: U32) -> Tr: Tr.emit(C_FSP_EMEMD(), w, 0, 0, t)

def fsp.do_tail(+t: Tr) -> Tr: fsp.do_head(Tr.emit(C_FSP_TAIL(), 0, 0, 0, t))

def fsp.do_head(+t: Tr) -> Tr: Tr.emit(C_FSP_HEAD(), 0, 0, 0, t)

# THE FSP VALUES. `fsp.tail` is the VALUE `len(buf) - 4` and `fsp.head` is 0;
# both are `U32` and neither is a trace def -- `fsp.do_tail`/`fsp.do_head` are
# those, and the split is what the compiler forces once `fsp.head` is a value.
def fsp.words(+nvmd: U32, +blen: U32) -> U32:
  U32.add(2, cdiv(U32.add(blen, fsp.pad(blen)), 4))

def fsp.pad(+blen: U32) -> U32: fsp_pad(blen)

def fsp.tail(+blen: U32) -> U32: U32.sub(U32.add(U32.add(blen, 8), fsp_pad(blen)), 4)
def fsp.head() -> U32: 0
def fsp.tail_off() -> U32: 0
def fsp.aincw() -> U32: 1
def fsp.aincr() -> U32: 0
def fsp.w0() -> U32: U32.or(U32.shln(1, 31n), U32.shln(1, 30n))

def fsp.w1(+nvmd: U32) -> U32: U32.or(U32.or(126, U32.shln(4318, 8n)), U32.shln(nvmd, 24n))
def fsp.nvmd_cot() -> U32: Cn.v(const_of("NVDM_TYPE_COT"))

# ---------------------------------------------------------------------------
# :557 `self.chan_runlists[obj] = self.runlists.get((e := params.engineType) +
# 10 * (e >= nv_gpu.NV2080_ENGINE_TYPE_NVDEC0), 0)` -- the NVDEC0 ADDEND. The
# runlist is looked up under the engine type NORMALISED by ten for NVDEC0, so a
# port that forgot the addend would read runlist 19 where the driver wrote 29,
# and the error is a silently wrong runlist rather than a fault. `ip_rp_runlist_key_*`
# walks the boundary at 18/19/20.
# ---------------------------------------------------------------------------
def rpc.runlist_key(+e: U32) -> U32: U32.add(e, rpc.nvdec_add(e))
def rpc.nvdec_add(+e: U32) -> U32: Bool.pick(U32, U32.is_ge(e, rpc.nvdec0()), 10, 0)
def rpc.nvdec0() -> U32: 19
def rpc.runlist_miss() -> U32: 0

# :551-554 the alloc records: `paramsSize = sizeof(params) if params else 0`
def rpc.ra_plen(+params: U32) -> U32: U32.add(32, params)
def rpc.rc_plen(+params: U32) -> U32: U32.add(24, params)

# ---------------------------------------------------------------------------
# :186-283 the falcon side. The register NAMES and their ORDER are ported and
# checked; the ADDRESSES come from `nvdev.include("dev_falcon_v4", "ga102")` at
# :100 and are the seam -- `autogen/nv_570.py` does not contain them, which is
# why they are not in the generated table either.
# ---------------------------------------------------------------------------
def fl.order() -> String:
  String.join(["reset", "dmatr_fb", "dmatr_fb1", "dmatr_offs", "falcon_offs",
               "brom_paraaddr", "brom_engidmask", "brom_ucode_id", "mod_sel",
               "bootvec", "mailbox0", "mailbox1", "start_cpu", "wait_halted"], ",")

def fl.order_n() -> U32: 14
def fl.falcon() -> U32: 1114112
def fl.sec2() -> U32: 8650752
def fl.ctx_dma() -> U32: 0
def fl.imem() -> U32: 1
def fl.sec() -> U32: 1
def fl.dmactl() -> U32: 0
def fl.allow_phys_no_ctx() -> U32: 1
def fl.reset_engines() -> U32: 2
def fl.dma_chunk() -> U32: 256
def fl.chunks(+size: U32) -> U32: cdiv(size, 256)
def fl.alias() -> U32: 2
def fl.startcpu() -> U32: 1
def fl.riscv_core1() -> U32: 1
def fl.riscv_core0() -> U32: 0

# :510-520 `NV_GSP.init_hw`'s order: the stat queue, then the cmd queue's rx view,
# then the two BAR1 blocks, then `priv_root`, then the golden image. The stat
# queue's `wait_resp(GSP_INIT_DONE)` sits between the second and third, so the
# order string alone would hide it -- `ip_gsp_init_order` is the string and the
# TRUNCATION rows in `t_refuse` are what say where the wait is.
def gsp.init_order() -> String:
  String.join(["stat_q", "cmd_q_rx", "wbar1", "fmc_bar1", "priv_root", "golden_image"], ",")

def gsp.init_n() -> U32: 6
def gsp.priv_root() -> U32: 3252682756

# :87-91 `wait_resp` -- and :91 is the refusal. `C_WAIT_RESP` is the call and
# `C_RPC_RAISE` is the raise; the raise TRUNCATES, so a timeout shows up as a
# trace that stops at the wait and needs no guard of its own downstream.
def rpc.wait(+func: U32, +t: Tr) -> Tr: Tr.emit(C_WAIT_RESP(), func, 0, 0, t)

# :84 `raise RuntimeError(f"RPC call {hdr.function} failed with result
# {hdr.rpc_result}")` -- the trace is truncated from here and `refused` is set, so
# every later `Tr.emit` is a no-op.
def rpc.raise(+func: U32, +result: U32, +t: Tr) -> Tr:
  rpc.raise2(func, result, Tr.emit(C_RPC_RAISE(), func, result, 0, t))

def rpc.raise2(+func: U32, +result: U32, +e: Tr) -> Tr:
  Tr{Tr.calls(e), Tr.wp(e), Tr.seq(e), Tr.handle(e), tr.fail(e), True{}}

# `len(buf)` -- the eight header bytes PLUS the padded payload. `QUEUE_TAIL` is
# this MINUS four, and the two are DIFFERENT numbers: 92 against 88 for an 82-byte
# payload. Conflating them was this file's first FSP bug and `ip_fsp_tr_tot` is
# the row that separates them.
def fsp.tot(+blen: U32) -> U32: U32.add(U32.add(blen, 8), fsp.pad(blen))
