# tinybendygrad/runtime/ops_null.bend -- port of tinygrad/runtime/ops_null.py
#
# ONE BEND FILE PER UPSTREAM .py, AT THE SAME PATH. This was `ops_cpu_null.bend`,
# which held `ops_cpu.py` AND `ops_null.py`; the 1:1 ruling gives each its own file.
# `runtime/ops_cpu.bend` is the other half and the rows are the SAME rows -- 308 across
# the pair before the split, 308 after. The unit's THE GATE paragraph, its FIXTURES
# paragraph and the `device.bend` DEFECT REPORT are in `ops_cpu.bend`'s head.
#
# ops_null.py is the DEGENERATE BACKEND: `NullQueue` writes FOUR words per command
# into a bytearray and the emulated device computes NOTHING. Eleven of the thirteen ops
# answer all-zero and TWO DO NOT -- `eye` and `arange` -- and both are in the gate with
# their CPython answers, so a port claiming "everything is zero" is caught by two rows.
#
# THE SPLIT, restated because it is the whole discipline here: a def EITHER BUILDS THE
# ARGUMENT of one device call OR RECORDS that call in the trace. There is no third
# kind, and that is what puts the `raise` in the trace, so a refusal appears as a
# TRUNCATED trace and no step needs a guard of its own.
#
# ONE DEVIATION FROM ops_webgpu.bend, deliberate. There a `raise` lives INSIDE a loop of
# calls, so it had to be a flag and a refusal showed as a TRUNCATED trace. Neither
# refusal here is inside such a loop -- ops_null.py's two (`_copyout`'s panic,
# `__init__`'s EMULATE assert) are both TERMINAL -- so `C.Tr.refused` is set once by
# the assert and the device's trace is then EMPTY: the same observable for a different
# reason, and `nr_assert_trace_n` is the row that pins it.
#
# THE SUBSTRATE IS IMPORTED, NOT COPIED: `C.Tr`/`C.Tr.*` (the trace), `C.CALL_PING` (the
# seam tag the `EMULATE` assert probes with), `C.Cn`/`C.cn_slot` (the slot walk the
# kernargs layout shares with ops_cpu.py:70), `C.Cr`, `C.nth` and the row printers live
# in `ops_cpu.bend` and every use here is `C.`. `Ca`/`Cam` are there too because
# ops_cpu.py:91's arch map and ops_null.py:62's EMULATE map are the same scan.
#
# `nr.has_copy_queue` is a NULL fact -- `ops_null.py` does not override
# `@property def has_copy_queue` at all, so NULL inherits `Compiled`'s `True` while
# `ops_cpu.py:84` returns `False`. `C.cpu.has_copy_queue` is the other half of that
# pair and it lives in `ops_cpu.bend` beside the comment explaining why two rows exist.
#
# ONE FILE IN HERE IS NOT MINE TO MOVE. `pk`/`Pk`/`fx_pk`/`pkend` and the `pk_*` rows
# port `pack_args`, which is `runtime/support/hcq2.py:78-83` -- a file with its own
# `.bend` and another unit's. They stay here because `ops_null.py:29-30` builds the
# kernargs through them. THE FIX IS TO MOVE THEM to `runtime/support/hcq2.bend`;
# flagged here and in the report, not done, because hcq2.bend is read-only here.
#
import Base
import ../helpers.bend as H
import ../device.bend as D
import ../LAWS/spec.bend as S
import ./ops_cpu.bend as C

def nr.has_copy_queue() -> U32: 1
# ===========================================================================
# ops_null.py -- THE DEGENERATE BACKEND.
#
# Everything below is either an INTEGER the queue lays down or a DECISION about
# whether to lay it down. There is no arithmetic on results, no shader, no
# compiler and no synchronisation, and the header's WALL 4 says so rather than
# inventing one.
#
# `NullQueue.q` (hcq2.py:366) writes each word LITTLE-ENDIAN and pads a UOp with
# its own bytes, and `HWQueue.blob` accumulates them -- that is the one place
# the words become bytes and it is a seam. What survives the crossing is the
# SHAPE: how many words per command, what each position means, and which of the
# five ops pads.
# ===========================================================================

# ops_null.py:22, `EXEC, COPY, WAIT, STORE, TIMESTAMP = range(5)`. Five tags,
# zero-based, and the tag is word 0 of every command.
def NEXEC() -> U32: 0
def NCOPY() -> U32: 1
def NWAIT() -> U32: 2
def NSTORE() -> U32: 3
def NTIMESTAMP() -> U32: 4

# ===========================================================================
# ops_null.py:25, `def cmd(self, op, *args): self.q(*[... for a in (op, *args,
# 0, 0, 0)][:4])`. THREE FACTS AND ALL THREE ARE THE FILE:
#
#   1. the tuple is (op, *args, 0, 0, 0) -- THREE trailing zeros, so a command
#      with one argument is padded by two and one with two is padded by one;
#   2. the slice is [:4], so the length is ALWAYS FOUR and an over-long argument
#      list is TRUNCATED, not extended;
#   3. word 0 is the op and the args follow in order, so a two-argument command
#      has its second argument in word 2 and its PAD in word 3.
#
# (1) is `nr.pads` and (2) is `nr.words`, and they are separate because they are
# separate facts: a port that padded correctly and emitted five words would pass
# `nr_pads_*` and fail `nr_words`.
# ===========================================================================

# THE ARITY OF EACH `cmd` CALL SITE, as a `U32` literal ladder in DESCENDING
# order (bend2-constraints.md, tc_ptx rule 4: an ascending ladder makes every
# arm after `case 0:` dead code that still typechecks).
def nr.nargs(op: U32) -> U32:
  match op:
    case 4: 1
    case 3: 2
    case 2: 3
    case 1: 3
    case _: 3

# (1) -- the pads are `3 - arity`, because the tuple has three zeros and the
# slice keeps the first four.
def nr.pads(op: U32) -> U32: U32.sub(3, nr.nargs(op))

# (2) and (3) -- the argument of one `cmd` call, as the four words `q` receives.
# The three arg SLOTS are parameters rather than a list because the call sites
# have different arities and a list would have to be sliced at every one of them.
def nr.words(op: U32, a0: U32, a1: U32, a2: U32) -> List<&2, U32>: [op, a0, a1, a2]

# ops_null.py:30, `self.cmd(EXEC, kernargs, len(args), self.event(...))`.
def nr.exec(kernargs: U32, nargs: U32, ev: U32) -> List<&2, U32>:
  nr.words(NEXEC(), kernargs, nargs, ev)

# ops_null.py:31, `self.cmd(COPY, dst, src, self.event(...))`.
def nr.copy(dst: U32, src: U32, ev: U32) -> List<&2, U32>: nr.words(NCOPY(), dst, src, ev)

# ops_null.py:36, `self.cmd(WAIT, signal, value, int(eq))` -- `int(eq)` is a
# Bool widened, and it is the LAST word, so `eq` never collides with a pad.
def nr.wait(sig: U32, val: U32, eq: Bool) -> List<&2, U32>:
  nr.words(NWAIT(), sig, val, Bool.to_u32(eq))

# ops_null.py:37, `self.cmd(STORE, signal, value)` -- TWO args, so ONE pad, and
# the pad is word 3. That the pad is a CONSTANT ZERO and `value` may also be zero
# is why the gate reads the arity rather than counting zero words.
def nr.signal(sig: U32, val: U32) -> List<&2, U32>: nr.words(NSTORE(), sig, val, 0)

# ops_null.py:34, `self.cmd(TIMESTAMP, signal.getaddr(self.devs) +
# UOp.const(8, dtypes.u64))` -- ONE arg, so TWO pads. The `+ 8` is the
# timeline's VALUE slot (`timeline` is `Buffer(dev, 2, uint64)`) and it is the
# only arithmetic in the file.
def nr.timestamp(addr: U32) -> List<&2, U32>: nr.words(NTIMESTAMP(), U32.add(addr, 8), 0, 0)

# ops_null.py:31, the two event-key strings. They are USER-VISIBLE -- they are
# the device and name a profile graph entry carries -- and they are the only two
# strings in the file.
def nr.copy_dev(src_dev: String) -> String: String.concat([src_dev, ":SDMA:0"])
def nr.copy_name(+src_dev: String, +dst_dev: String) -> String:
  String.concat([src_dev, " -> ", dst_dev])


# ===========================================================================
# ops_null.py:48 and :26 -- `null_events` and `event`. A process-global dict
# keyed by `(device, name, key)` and `setdefault`'d with `len(null_events)`, so
# AN EVENT'S ID IS ITS FIRST-APPEARANCE INDEX and two events with the same key
# share one id. `key` is `bytes | None` and only identity matters, so the port
# carries it as a U32 with 0 meaning None.
#
# First-wins over the table, and the ANSWER and the LIST both come back, so the
# accumulator is a record: `Ev.lookup` needs the id and `Ev.put` needs the
# grown list, and both read the same walk.
# ===========================================================================

type Nk is Data:
  Nk{dev: String, nm: String, C.key: U32}

def Nk.dev(x: Nk) -> String:
  match x:
    case Nk{dev, nm, key}: dev

def Nk.nm(x: Nk) -> String:
  match x:
    case Nk{dev, nm, key}: nm

def Nk.key(x: Nk) -> U32:
  match x:
    case Nk{dev, nm, key}: key

# `(device, name, key)` equality -- all THREE, and the third is the one a
# two-field comparison drops. A profile KEY distinguishes two executions of the
# SAME kernel, so a port that compared only (device, name) would merge them.
def Nk.same(+a: Nk, +b: Nk) -> Bool:
  Bool.and(Bool.and(String.eq(Nk.dev(a), Nk.dev(b)), String.eq(Nk.nm(a), Nk.nm(b))),
           U32.is_eq(Nk.key(a), Nk.key(b)))

type EvA is Data:
  EvA{hit: Bool, id: U32, evs: List<&2, Nk>}

def EvA.hit(a: EvA) -> Bool:
  match a:
    case EvA{hit, id, evs}: hit

def EvA.id(a: EvA) -> U32:
  match a:
    case EvA{hit, id, evs}: id

def EvA.evs(a: EvA) -> List<&2, Nk>:
  match a:
    case EvA{hit, id, evs}: evs

# ONCE a key is found the walk must NOT record a later equal one, or the id
# would be the LAST hit rather than the first. `hit` rides on the accumulator
# for exactly that. MEASURED (M28): flipping it to last-wins moves NO row, and
# it cannot: `Nk.same` IS Python's tuple equality on `(device, name, key)`,
# `null_events` is a dict so it never holds two equal keys, and `Ev.put` -- the
# only inserter, and pinned by M29's five rows -- appends on a miss only. So
# "no equal pair in the table" is an invariant, and the fold is a redundancy
# the dict makes unreachable, not a behaviour the gate is missing. The key being
# examined is `k` (a walk binder) and the key being SOUGHT is `want`, so
# `Nk.same` never has to read the list back by index.
def EvA.step(want: Nk, k: Nk, at: U32, acc: EvA) -> EvA:
  match acc:
    case EvA{+hit, +id, +evs}:
      Bool.pick(EvA, hit, acc, Bool.pick(EvA, Nk.same(k, want), EvA{True{}, at, evs}, acc))

def EvA.go(n: Nat, ks: List<&2, Nk>, +want: Nk, +at: U32, acc: EvA) -> EvA:
  match n:
    case 0n: acc
    case 1n+p:
      match ks:
        case Nil{}: acc
        case h <> t: EvA.go(p, t, want, U32.add(at, 1), EvA.step(want, h, at, acc))

def Ev.walk(want: Nk, +evs: List<&2, Nk>) -> EvA:
  EvA.go(List.length(&2, Nk, evs), evs, want, 0, EvA{False{}, U32.from_nat(List.length(&2, Nk, evs)), evs})

# `null_events.setdefault(key, len(null_events))` -- the id a MISS returns, which
# is also the slot the key would take.
def Ev.lookup(+k: Nk, evs: List<&2, Nk>) -> U32: EvA.id(Ev.walk(k, evs))

# `setdefault` on a MISS INSERTS, so the list grows by one. A hit does not.
def Ev.put(+k: Nk, +evs: List<&2, Nk>) -> List<&2, Nk>:
  Bool.pick(List<&2, Nk>, EvA.hit(Ev.walk(k, evs)), evs,
    List.append(&2, Nk, evs, [k]))

# ===========================================================================
# hcq2.py:78-83, `pack_args`, which is what ops_null.py:29 builds the kernargs
# LINEAR from. It is the only REAL ARITHMETIC in the NULL backend and the only
# place its queue has a layout:
#
#   for offset, arg in sorted(args, key=lambda x: x[0]):
#     words += [UOp(Ops.BINARY, arg=bytes(offset - end)), arg] if offset != end
#              else [arg]
#     end = offset + arg.dtype.itemsize
#   return words + [UOp(Ops.BINARY, arg=bytes(size - end))]
#
# and the SIZE is ops_null.py:29's `8 * max(len(args), 1)`. MEASURED over five
# arg lists:
#
#   itemsizes  size  offsets   nsrc  tail bytes
#   [4]          8      [0]        2         4
#   [4,4]       16     [0,4]       3         8
#   [4,4,4]     24     [0,4,8]     4        12
#   [8,4]       16     [0,8]       3         4
#   [8,8]       16     [0,8]       3         0
#
# TWO facts fall out and they are independent: the LINEAR has `nargs + 1` srcs
# one TAIL BINARY always, PLUS one per interior gap, and the tail's byte count
# is `size - end`. The interior count is zero for five of the seven MEASURED
# layouts and ONE for `[4,8,4]`, because a 1-byte argument between two 4-byte
# ones makes `layout_args` place the third at slot 8 rather than slot 5.
# ===========================================================================

# :29, `8 * max(len(args), 1)`. The `max` matters for the EMPTY call and only
# for it -- a zero-argument kernel is the one case where `size` is not 0.
def pk.size(+nargs: U32) -> U32: U32.mul(Bool.pick(U32, U32.is_zero(nargs), 1, nargs), 8)

# one TAIL BINARY, one entry per argument, and one BINARY per INTERIOR GAP.
# `nargs + 1` is right for every CONTIGUOUS layout and wrong by the pad count
# otherwise -- and `[4,8,4]` is the one MEASURED layout that is not contiguous,
# at `pk_pads_484` / `pk_nsrc_484`.
def pk.nsrc(nargs: U32, pads: U32) -> U32: U32.add(U32.add(nargs, 1), pads)

# the tail's byte count, `bytes(size - end)` with `end` the running sum of
# itemsizes. A NEGATIVE tail is impossible for a signature whose itemsizes sum
# to at most `8*nargs`, and the `[8,8]` row is the one where the tail is zero --
# `bytes(0)` is a real BINARY node with an empty arg, which is why
# `pk_tail_88` is 0 and not "absent".
def pk.tail(nargs: U32, end: U32) -> U32: U32.sub(pk.size(nargs), end)

# the interior-pad count, which is the port of hcq2.py:76's `if offset != end`:
# it counts the offsets that are NOT contiguous with the running end. FIVE of the
# SEVEN measured layouts give 0 and `[4,8,4]` gives 1, because a 1-byte argument
# between two 4-byte ones makes `layout_args` place the third at slot 8 rather
# than slot 5. A pad count that was CONSTANT zero would pass six rows and fail
# the seventh, so `pk_pads_484` is the row that makes the count vary.
def pk.pads.go(n: Nat, ks: List<&2, U32>, +off: U32, end: U32, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+p:
      match ks:
        case Nil{}: acc
        case s <> t:
          +r: C.Cn = C.cn_slot(off, s)
          pk.pads.go(p, t, C.Cn.next(r), C.Cn.next(r),
            U32.add(acc, Bool.to_u32(Bool.not(U32.is_eq(C.Cn.at(r), end)))))

def pk.pads(+ks: List<&2, U32>) -> U32: pk.pads.go(List.length(&2, U32, ks), ks, 0, 0, 0)

# ===========================================================================
# ops_null.py:38-46 -- `NullProgram`, the emulated executor. It is FORTY-EIGHT
# lines of Python and every one of them is a fold over the command words:
#
#   :38  streams = [(i, prod(s)) for i,(n,_,_,s) in enumerate(obj.signature)
#                  if (n or "").startswith("cmdbuf")]
#   :40  st, words = perf_counter_us(), [w for i,n in self.streams
#                                       for w in MMIOInterface(bufs[i], n, fmt='Q')[:]]
#   :42  for op, addr, done in zip(words[0::4], words[1::4],
#                                 itertools.accumulate(op in (EXEC, COPY)
#                                                     for op in words[0::4])):
#          if op == TIMESTAMP: MMIOInterface(addr,8,fmt='Q')[0] = int((st+done)*1000)
#   :44  descs = [list(null_events)[event] for op, event in zip(words[0::4],
#                  words[3::4]) if op in (EXEC, COPY)] if PROFILE else []
#   :45  sigs = [st + sum(x[0]==d[0] for x in descs[:i]) + k
#                for i,d in enumerate(descs) for k in (0,1)]
#   :46  if descs: cpu_events.append(ProfileGraphEvent(...))
#
# So the four words of a quad are (op, addr, value, event), the emulated clock
# is `st + done` where `done` is the running count of EXEC-or-COPY commands, and
# the profile lane of an entry is its device's OWN ordinal. `st` is INJECTED --
# `perf_counter_us` is a seam and a gate may not read a clock.
# ===========================================================================

# :38 -- one SIGNATURE ENTRY, and only the three fields the comprehension reads:
# the index `i`, the name `n` and the shape product `prod(s)`. `prod(())` is 1,
# so `nbytes` is never 0 for a real entry and 0 is free to mean "no stream".
type Sg is Data:
  Sg{ix: U32, nm: String, sz: U32}

# the two answers `streams` gives: the byte total (which is what the Q-word
# count is derived from) and the `(index, bytes)` pairs IN ORDER. `List.append`
# is `xs ++ ys`, so the walk APPENDS and the pairs come out in signature order --
# the opposite choice reverses them and `nprog_streams` is the row that dies.
type St is Data:
  St{nbytes: U32, pairs: List<&2, U32>}

def St.nbytes(s: St) -> U32:
  match s:
    case St{nbytes, pairs}: nbytes

def St.pairs(s: St) -> List<&2, U32>:
  match s:
    case St{nbytes, pairs}: pairs

# `(n or "")` -- a signature name is `str | None` and `None` reads as the empty
# string, which is the one thing that makes `.startswith` total.
def Sg.is_stream(nm: String) -> Bool: String.starts_with(nm, "cmdbuf")

def nprog.streams.go(n: Nat, xs: List<&2, Sg>, +nb: U32, +ps: List<&2, U32>) -> St:
  match n:
    case 0n: St{nb, ps}
    case 1n+p:
      match xs:
        case Nil{}: St{nb, ps}
        case Sg{ix, +nm, +sz} <> t:
          nprog.streams.go(p, t,
            Bool.pick(U32, Sg.is_stream(nm), U32.add(nb, sz), nb),
            Bool.pick(List<&2, U32>, Sg.is_stream(nm),
              List.append(&2, U32, ps, [ix, sz]), ps))

def nprog.streams(+xs: List<&2, Sg>) -> St:
  nprog.streams.go(List.length(&2, Sg, xs), xs, 0, Nil{})

# :40 -- `MMIOInterface(bufs[i], n, fmt='Q')` reads `n` BYTES as Q words, so the
# word count is `n / 8`. It is `/` and not `n`: `n` is `prod(shape)` and the
# shape is in BYTES, which is the one place the two units meet.
def nprog.qwords(nbytes: U32) -> U32: U32.div(nbytes, 8)

# the quad count is the number of FOUR-word groups, which is the stream's Q
# words over four -- and it is `U32.div`, not the byte count, because a word list
# IS already in words.
def nprog.quads(+ws: List<&2, U32>) -> U32: U32.div(U32.from_nat(List.length(&2, U32, ws)), 4)

# :42 -- the accumulate. `itertools.accumulate(op in (EXEC, COPY) for op in
# words[0::4])` is a PREFIX COUNT of the EXEC-or-COPY commands, inclusive of the
# current one, so the first quad's `done` is 1 when the quad is an EXEC. This is
# the fold that has to be a fold and not a `List.get`: the value at quad `i`
# depends on all `i` of them.
def nprog.is_work(+op: U32) -> Bool:
  Bool.or(U32.is_eq(op, NEXEC()), U32.is_eq(op, NCOPY()))

def nprog.done.go(n: Nat, ws: List<&2, U32>, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+p:
      match ws:
        case Nil{}: acc
        case h <> t:
          nprog.done.go(p, List.drop(&2, U32, t, 3n),
            U32.add(acc, Bool.to_u32(nprog.is_work(h))))

# THE FUEL IS `quads + 1`, because `itertools.accumulate` answers element `i` with
# the sum of elements `0..i` INCLUSIVE and this fold returns the accumulator after
# `n` steps. `nprog_done_at_2` came out 0 where CPython says 1, and the COPY that
# makes it 1 is quad 2 -- the row that found the off-by-one. `nprog_done_sum` is
# the same fold over every quad, so it asks for `quads + 1` there too.
def nprog.done_at(+ws: List<&2, U32>, quads: Nat) -> U32:
  nprog.done.go(Nat.add(quads, 1n), ws, 0)

# :42-43 -- `if op == TIMESTAMP: MMIOInterface(addr,8,fmt='Q')[0] =
# int((st+done)*1000)`. The WRITE COUNT is the number of TIMESTAMP commands and
# that is the whole of WALL 4's claim: on a stream with none, the emulated device
# writes NOTHING and every kernel result is whatever the buffer already held.
def nprog.stamp.go(n: Nat, ws: List<&2, U32>, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+p:
      match ws:
        case Nil{}: acc
        case h <> t: nprog.stamp.go(p, List.drop(&2, U32, t, 3n),
          U32.add(acc, Bool.to_u32(U32.is_eq(h, NTIMESTAMP()))))

# THE WRITE COUNT over a whole stream: the number of TIMESTAMP commands among
# the quads the stream actually has. `nprog.quads` is the number of FOUR-word
# groups, which is the stream's Q words over four -- and it is `U32.div`, not
# the byte count, because a word list IS already in words.
def nprog.writes(+ws: List<&2, U32>) -> U32: nprog.stamp.go(U32.to_nat(nprog.quads(ws)), ws, 0)

# `int((st+done)*1000)` -- microseconds to nanoseconds. `st` is injected.
def nprog.stamp_val(st: U32, done: U32) -> U32: U32.mul(U32.add(st, done), 1000)

# :44 -- `descs = [list(null_events)[event] for op, event in zip(words[0::4],
# words[3::4]) if op in (EXEC, COPY)]`. TWO folds: one over the quads keeping the
# event IDs, one over those IDs projecting each to its KEY'S DEVICE. The device
# is the only part the NEXT line reads (`x[0]`), so projecting here rather than
# carrying `Nk` saves a fold and loses nothing.
# word 3 of the quad `ws` starts at.
def nprog.word_at(+ws: List<&2, U32>, k: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, List.drop(&2, U32, ws, U32.to_nat(k)), 0n), 0)

# the projection `list(null_events)[event]`, i.e. the KEY at that slot.
def nprog.dev_at.of(m: Maybe<&2, Nk>) -> String:
  match m:
    case Some{+k}: Nk.dev(k)
    case None{}: ""

# `list(null_events)[event]` -- the KEY at that slot. An id past the end is the
# empty device, which is Python's `IndexError` reduced to the one thing a fold
# can carry; no real stream reaches it because every event word is an id the
# queue interned on the way in.
def nprog.dev_at(+evs: List<&2, Nk>, i: U32) -> String:
  nprog.dev_at.of(List.get(&2, Nk, evs, U32.to_nat(i)))

def nprog.devs.go(n: Nat, +ws: List<&2, U32>, +evs: List<&2, Nk>,
                   +acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+p:
      match ws:
        case Nil{}: acc
        case h <> t:
          nprog.devs.go(p, List.drop(&2, U32, t, 3n), evs,
            Bool.pick(List<&2, String>, nprog.is_work(h),
              List.append(&2, String, acc, [nprog.dev_at(evs, nprog.word_at(ws, 3))]), acc))

def nprog.descs(+ws: List<&2, U32>, +evs: List<&2, Nk>) -> List<&2, String>:
  nprog.devs.go(U32.to_nat(nprog.quads(ws)), ws, evs, Nil{})

# :45 -- `sum(x[0]==d[0] for x in descs[:i])`, the number of EARLIER profile
# entries on the SAME DEVICE. This is the per-device lane: two entries on
# different devices share a base and two on the same device do not. The
# `[i]` is the CURRENT entry, never the whole list -- an accumulator that read
# the whole list would answer `len(descs)` for every entry and every sig would
# be `st + len(descs) + k`, which is a plausible string and a wrong graph.
def nprog.lane.go(n: Nat, +d: String, ds: List<&2, String>, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+p:
      match ds:
        case Nil{}: acc
        case x <> t: nprog.lane.go(p, d, t, U32.add(acc, Bool.to_u32(String.eq(x, d))))

def nprog.dev_at_list.of(m: Maybe<&2, String>) -> String:
  match m:
    case Some{+d}: d
    case None{}: ""

def nprog.dev_at_list(ds: List<&2, String>, i: Nat) -> String:
  nprog.dev_at_list.of(List.get(&2, String, ds, i))

def nprog.lane(+ds: List<&2, String>, +i: Nat) -> U32:
  nprog.lane.go(i, nprog.dev_at_list(ds, i), ds, 0)

# :45 -- the sigs, two per entry: `st + lane(i) + k for k in (0,1)`. They are
# PAIRED, so the gate reads a flat list of 2*len(descs) numbers and the pair
# structure is the row that checks it.
def nprog.sig_one(st: U32, lane: U32, k: U32) -> U32: U32.add(U32.add(st, lane), k)

# THE INDEX IS A PARAMETER AND THE LIST IS NEVER MATCHED. The first version read
# `i` out of `len(acc)/2` and matched on `ds` in the same arm -- and
# `case h <> t:` SPENDS its scrutinee, so `nprog.lane(ds, i)` was handed a spent
# list, `nprog.dev_at_list` answered "" for every entry and every lane was 0.
# `nprog_sigs_same` came out 1000,1001,1001,1002,1000,1001: the first two entries
# right and every later one wrong. The fuel IS the length, so there is nothing to
# walk and nothing to spend.
def nprog.sigs.go(n: Nat, +ds: List<&2, String>, +st: U32, +acc: List<&2, U32>,
                  +i: U32) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p:
      +ln: U32 = nprog.lane(ds, U32.to_nat(i))
      nprog.sigs.go(p, ds, st,
        List.append(&2, U32, List.append(&2, U32, acc, [nprog.sig_one(st, ln, 0)]),
          [nprog.sig_one(st, ln, 1)]), U32.add(i, 1))

def nprog.sigs(+st: U32, +ds: List<&2, String>) -> List<&2, U32>:
  nprog.sigs.go(List.length(&2, String, ds), ds, st, Nil{}, 0)

# :46 -- `[ProfileGraphEntry(d, n, 2*i, 2*i+1, k) for i,(d,n,k) in
# enumerate(descs)]`, so the entry ids are 2i and 2i+1 and they are the same
# numbers `sigs` is indexed by.
def nprog.ent_ids(+i: U32) -> List<&2, U32>: [U32.mul(i, 2), U32.add(U32.mul(i, 2), 1)]

# THE SIGNATURE MEASURED ON THE REAL NULL DEVICE (DEV=NULL, DEBUG=3): seven
# entries, itemsizes [8,1,8,1,8,1,1], two of them named `cmdbuf_*` at indices 3
# and 5 with 160 and 224 bytes. The fixture is this list and nothing else.
def nprog.sig7() -> List<&2, Sg>:
  [Sg{0, "slots_0", 14}, Sg{1, "doorbell_1", 256}, Sg{2, "timeline_2", 2},
   Sg{3, "cmdbuf_copy_0_3", 160}, Sg{4, "inputs_4", 3},
   Sg{5, "cmdbuf_compute_0_5", 224}, Sg{6, "kernargs_compute_0_6", 16}]

# ===========================================================================
# ops_null.py:48-52 -- `NullAllocator`. FOUR lines of source and the only 64-BIT
# arithmetic in either file.
#
#   def _alloc(self, size, options, va=itertools.count(1 << 40, 1 << 32)):
#     return BufferStorage(next(va))
#   def _copyin(self, dest, src): pass
#   def _copyout(self, dest, src): NULL_ALLOW_COPYOUT or panic(RuntimeError, "no copyout on NULL")
#   def _map(self, buf): return BufferStorage(buf._buf if buf.device.startswith("NULL") else buf.host.addr)
#
# `va` is a DEFAULT ARGUMENT, so the counter is created ONCE per `NullAllocator`
# class and every `_alloc` in the process draws from the SAME sequence. That is
# why the addresses are monotone and not per-call, and MEASURED over three real
# allocations: 1099511627776, 1103806595072, 1108101562368.
# ===========================================================================

# `1 << 40` AND `1 << 32` ARE NOT `Nat` LITERALS -- a `Nat` literal is capped at
# 4294967295n (MEASURED) -- so each is a product of two halves that are under
# the cap. 1024 * (1 << 30) and 2 * (1 << 31). The ANSWERS are the rows
# `nva_base` and `nva_step`.
def nva.base() -> Nat: Nat.mul(1024n, 1073741824n)
def nva.step() -> Nat: Nat.mul(2n, 2147483648n)

# `next(va)` k times. `k` is the ALLOCATION ORDINAL, and the port carries it as
# a `Nat` because the answer does not fit in a `U32` -- which is the one place
# WALL 1 does not bite, and it is worth a row (`nva_step_1`) to say so.
def nalloc.va(k: Nat) -> Nat: Nat.add(nva.base(), Nat.mul(k, nva.step()))

# :51, `NULL_ALLOW_COPYOUT or panic(RuntimeError, "no copyout on NULL")`. THE
# PANIC IS THE ANSWER: with the flag unset `_copyout` raises, and the message is
# user-visible, so it is a constant here and a row. `nalloc.copyout_ok` answers
# whether the write is allowed at all.
def nalloc.copyout_msg() -> String: "no copyout on NULL"

def nalloc.copyout_ok(allow: U32) -> U32: Bool.to_u32(Bool.not(U32.is_zero(allow)))

# :50, `def _copyin(self, dest, src): pass`. The function is a no-op, so the
# number of bytes it moves is the whole of it -- and it is ZERO, which is how a
# NULL upload leaves the destination untouched and every kernel result is
# whatever the buffer already held (WALL 4).
def nalloc.copyin_nops() -> U32: 0

# :52, `buf._buf if buf.device.startswith("NULL") else buf.host.addr`. A NULL
# buffer's OWN storage address is the mapping; anything else has to come from
# the host allocator, and on a remote node that is a different address. The test
# is `startswith("NULL")` and not equality, so `NULL:1` and `NULL` both map
# themselves -- `nr_map_*` walks four spellings.
def nalloc.map_is_null(dev: String) -> Bool: String.starts_with(dev, "NULL")

# ===========================================================================
# ops_null.py:11-19 -- `NullRenderer`. Four attributes and TWO code_for_op
# overrides, and the overrides are the file's only STRING-BUILDING code.
#
#   has_local = False; float4 = "float4"; barrier = "// BARRIER"
#   code_for_op = {**CStyleLanguage.code_for_op,
#                  Ops.THREEFRY: lambda a,b,dtype: f"threefry({a},{b})",
#                  Ops.MAX:      lambda a,b,dtype: f"max({a},{b})"}
#
# MEASURED: `{**CStyleLanguage.code_for_op}` has 21 entries, NullRenderer's has
# 23, and the two it adds are EXACTLY MAX and THREEFRY -- every shared entry is
# the SAME lambda object (`cfop_changed == 0`). So the merge is ADDITIVE, and
# `nr_cfop_overrides` being 2 rather than 23 is the row that says so.
# ===========================================================================

def nr.has_local() -> U32: 0
def nr.float4() -> String: "float4"
def nr.barrier() -> String: "// BARRIER"
def nr.cstyle_n() -> U32: 21
def nr.cfop_overrides() -> U32: 2
def nr.cfop_total() -> U32: 23

# The lambdas take the RENDERED OPERAND STRINGS -- cstyle.py:66-67 passes
# `ctx[v]`, a string -- so the format is `threefry(<a>,<b>)` with NO SPACE.
# MEASURED with operands "A" and "B".
def nr.cfop_threefry(+a: String, +b: String) -> String:
  String.concat(["threefry(", a, ",", b, ")"])

def nr.cfop_max(+a: String, +b: String) -> String: String.concat(["max(", a, ",", b, ")"])

# :17, `assert self.target.arch.startswith("gfx"), "only amd supports assembly"`.
# The assert REFUSES a non-AMD arch, and both arch spellings the assert message
# and the three in the EMULATE map are the same vocabulary -- `gfx` is not a
# coincidence of naming, it is the one family this backend can hand to an AMD
# assembler.
def nr.asm_ok(arch: String) -> Bool: String.starts_with(arch, "gfx")
def nr.asm_msg() -> String: "only amd supports assembly"

# ===========================================================================
# ops_null.py:55-68 -- `NullDevice`, and the device-side buffer identity rules
# the brief names.
#
#   :55-56 pm_encode -- two rules, `submit_null_{compute,copy}`, and the arg is
#           the FUNCTION NAME, so the two rows differ only in the suffix.
#   :57    host = property(lambda self: self.device) -- the IDENTITY, and the
#           opposite of `Compiled.host` (device.py:418) which answers
#           `HCQ_RUNTIME_DEV`. So NULL's host IS its own name and CPU's is not.
#   :58    timeline = link_buffer(2, dtypes.u64)
#   :61-62 the EMULATE assert and its message
#   :63-64 the renderers list, deduped
#   :66    pm_bufferize -- ONE rule, `ctx.link_buffer(b.max_numel(), b.dtype)`
#   :68    link_buffer(n, dt)
#
# `Compiled`'s `pm_bufferize` has THREE rules (device.py:403-408) and NULL
# REPLACES the table with one, so `ndev_bufferize_n` is 1 where
# `device.bend`'s `pmb_len` is 3 -- and the two rows together are the
# cross-file fact.
# ===========================================================================

# :55-56 -- the two `to_name("submit", devs[0], queue)` results. MEASURED:
# `to_name('submit','NULL','compute')` == 'submit_null_compute'.
def ndev.encode_names() -> List<&2, String>: ["submit_null_compute", "submit_null_copy"]

# :66 -- ONE rule, against `Compiled`'s THREE.
def ndev.bufferize_n() -> U32: 1
def ndev.compiled_bufferize_n() -> U32: 3

# :57 -- `host` IS the device string, so `nr_host_*` on "NULL:1" answers
# "NULL:1" and `cpu_host_*` on "CPU:1" answers "CPU" (device.py:418's
# `HCQ_RUNTIME_DEV.value`). Two rows with different sources and different
# answers, and the difference is the row.
def ndev.host(dev: String) -> String: dev

# :58 -- `link_buffer(2, dtypes.u64)`, and `device.bend` already ports the
# timeline's two uint64 slots, so this IS that call.
def ndev.timeline_n() -> U32: 2
def ndev.timeline_nbytes() -> U32: D.timeline_bytes()

# :68, `Buffer(self.device, n, dt, opaque=memoryview(bytearray(n * dt.itemsize)),
# options=BufferSpec(external_ptr=1))`. The byte size is `n * itemsize` and the
# `external_ptr=1` is what makes `_map` answer the buffer's OWN storage -- the
# two facts together ARE the NULL buffer identity rule.
def ndev.link_nbytes(n: U32, dt: S.Dt) -> U32: U32.mul(n, S.Dt.itemsize(dt))
def ndev.link_ext_ptr() -> U32: 1

# :62, `{"AMD":"gfx1100", "AMD_RDNA4":"gfx1201", "AMD_CDNA4":"gfx950"}.get(emu,
# "<arch>")`. The SAME `Ca` table shape as the CPU arch map and the SAME
# `Ca.lookup` scan, with a different table -- which is why that scan is one def.
def ndev.emulate_table() -> List<&2, C.Ca>:
  [C.Ca{1, "AMD", "gfx1100"}, C.Ca{2, "AMD_RDNA4", "gfx1201"}, C.Ca{3, "AMD_CDNA4", "gfx950"}]

def ndev.emulate_fallback() -> String: "<arch>"

# THE FALLBACK IS NOT THE KEY HERE. `Ca.lookup`'s default arm is the key itself,
# which is right for the CPU arch map (an unknown machine IS its own arch) and
# wrong here (an unknown emu is literally the five-character string "<arch>").
# So the substitution is this def's, and it is why `nr_emulate_arch_empty` and
# `nr_emulate_arch_raw` are rows: both answer the PLACEHOLDER and neither answers
# the key.
def ndev.emulate_arch(+emu: String) -> String:
  Bool.pick(String, C.Cam.hit(C.Ca.lookup(emu, ndev.emulate_table())),
            C.Cam.to(C.Ca.lookup(emu, ndev.emulate_table())), ndev.emulate_fallback())

# :61-62, the assert MESSAGE. It is USER-VISIBLE -- it is what a user sees when
# they set a deprecated env var -- and it is built from the arch map, so the
# message and the map cannot disagree.
def ndev.emulate_prefix() -> String: "EMULATE is deprecated, use DEV=NULL:HIP:"
def ndev.emulate_msg(+emu: String) -> String:
  String.concat([ndev.emulate_prefix(), ndev.emulate_arch(emu)])

# :63-64, `renderers = [NullRenderer] + [r for m in [cstyle, nir, ptx, llvmir,
# wgsl] for r in m.__dict__.values() if inspect.isclass(r) and issubclass(r,
# Renderer)]` then `dedup(renderers)`. MEASURED: the raw list is 27 long and
# `dedup` -- `list(dict.fromkeys(x))`, which RETAINS LIST ORDER (helpers.py:23) --
# makes it 20, and the twenty are the raw list with the repeats removed in
# order. `Renderer` itself appears four times in the raw list (once per module's
# `__dict__`) and once in the answer, which is the single most dedup-dependent
# row here: a port that deduped by sorting would move `nr_renderers`.
def ndev.renderers_pre() -> U32: 27

def ndev.renderers() -> List<&2, C.Cr>:
  [C.Cr{1, "NullRenderer"}, C.Cr{2, "Renderer"}, C.Cr{3, "CStyleLanguage"},
   C.Cr{4, "ClangRenderer"}, C.Cr{5, "OpenCLRenderer"}, C.Cr{6, "MetalRenderer"},
   C.Cr{7, "CUDARenderer"}, C.Cr{8, "NVCCRenderer"}, C.Cr{9, "HIPRenderer"},
   C.Cr{10, "HIPCCRenderer"}, C.Cr{11, "QCOMCLRenderer"}, C.Cr{12, "NIRRenderer"},
   C.Cr{13, "NAKRenderer"}, C.Cr{14, "LVPRenderer"}, C.Cr{15, "IR3Renderer"},
   C.Cr{16, "PTXRenderer"}, C.Cr{17, "LLVMRenderer"}, C.Cr{18, "CPULLVMRenderer"},
   C.Cr{19, "AMDLLVMRenderer"}, C.Cr{20, "WGSLRenderer"}]

# ===========================================================================
# THE ZERO TABLE, which is WALL 4's content and the reason this backend exists.
#
# A NULL kernel is NEVER RUN, so every value a kernel would have produced is
# whatever the buffer already held -- and `link_buffer` hands over
# `bytearray(n * itemsize)`, which is ZEROS. So eleven of the thirteen ops I
# measured on the real device answer all-zero, and TWO DO NOT:
#
#     rand  randn  full  add  sum  l2norm  ones  dot  neg  max  softmax -> ZERO
#     eye   [1,0,0,0]     arange [0,1,2,3]                                -> NOT
#
# MEASURED with `DEV=NULL` on the real device, one row per op. `eye` and
# `arange` answer real values because tinygrad builds them out of CONSTs on a
# host-visible buffer rather than out of a kernel, and that is a fact about the
# SCHEDULER, not about this backend -- which is exactly why it belongs in the
# gate: a port that asserted "NULL answers zero" for everything would be wrong
# on two rows and right on eleven, and eleven is enough to hide it.
#
# ONE TABLE, THIRTEEN ROWS, and the table is the content. A count row over it
# would be a second transcription of the same thirteen facts and would prove
# nothing, so there is no count row; `nr_zero_*` reads the table BY NAME.
# ===========================================================================

type Zz is Data:
  Zz{ix: U32, nm: String, z: U32}

def Zz.nm(r: Zz) -> String:
  match r:
    case Zz{ix, nm, z}: nm

def Zz.z(r: Zz) -> U32:
  match r:
    case Zz{ix, nm, z}: z

def nr.zero_table() -> List<&2, Zz>:
  [Zz{1, "rand", 1}, Zz{2, "randn", 1}, Zz{3, "full", 1}, Zz{4, "add", 1},
   Zz{5, "sum", 1}, Zz{6, "l2norm", 1}, Zz{7, "ones", 1}, Zz{8, "dot", 1},
   Zz{9, "neg", 1}, Zz{10, "max", 1}, Zz{11, "softmax", 1},
   Zz{12, "eye", 0}, Zz{13, "arange", 0}]

# FIRST-WINS over the table, and 2 is the answer for a name that is not in it --
# not 0, because 0 means "measured: not all zero" and a missing row must not be
# able to masquerade as one. `nr_zero_missing` is the row that says so.
# THE ACCUMULATOR IS "not found YET" (0) and a hit STORES `Zz.z + 2`, so the three
# answers -- found-and-zero, found-and-not, not-found -- are 3, 2 and 0 and cannot
# be confused with one another. The `+ 2` is load-bearing in a way that is easy to
# get wrong: storing `Zz.z + 1` puts "found and zero" at 2, the outer pick's own
# "not found" test is `is_zero`, and every row after a hit resets the accumulator
# -- so the fold answered 2 for every name and thirteen rows moved at once. THE
# OUTER PICK'S FALSE ARM IS `got` AND NOT `0`: `Bool.pick(T, c, a, b)` answers
# `a` when `c`, so "not yet found" means `is_zero(got)` is TRUE and the answer is
# the inner test, and "already found" means it is FALSE and the answer is `got`
# KEPT. Writing `0` there -- which reads as "reset to not-found" -- makes the fold
# forget every hit on the very next row, and all thirteen rows answer 2 at once.
# MEASURED (M53): flipping this to LAST-wins moves no row, and it cannot. The
# thirteen names are distinct -- they are thirteen separately MEASURED ops, not a
# generated set -- so at most one row ever matches and first-wins and last-wins
# are the same function on every input this def can receive. There is no
# duplicate to plant and planting one would assert a state the table cannot be
# in. See also `EvA.step`: the same argument, for the same reason.
def nr.zero_of.done(+got: U32) -> U32:
  Bool.pick(U32, U32.is_zero(got), 2, U32.sub(got, 2))

def nr.zero_of.go(n: Nat, +nm: String, rs: List<&2, Zz>, +got: U32) -> U32:
  match n:
    case 0n: nr.zero_of.done(got)
    case 1n+p:
      match rs:
        case Nil{}: nr.zero_of.done(got)
        case +h <> t:
          nr.zero_of.go(p, nm, t, Bool.pick(U32, U32.is_zero(got),
            Bool.pick(U32, String.eq(Zz.nm(h), nm), U32.add(Zz.z(h), 2), 0), got))

def nr.zero_of(+nm: String) -> U32:
  nr.zero_of.go(List.length(&2, Zz, nr.zero_table()), nm, nr.zero_table(), 0)

# ===========================================================================
# ops_null.py:60-66 -- `NullDevice.__init__` and the assert.
#
#   assert (emu:=getenv("EMULATE", "")) == "", \
#     "EMULATE is deprecated, use DEV=NULL:HIP:" + {...}.get(emu, "<arch>")
#   super().__init__(device, NullAllocator(self), dedup(renderers), NullProgram)
#   self.pm_bufferize = PatternMatcher([...])
#
# THE ASSERT IS FIRST, so a failing one means `super().__init__` NEVER RUNS and
# there is no device at all -- not a half-built one. That is what the truncation
# in the trace is for: `ndev.init` records the assert, sets `refused`, and then
# records NOTHING else, because `Tr.emit` is a no-op once refused. The failing
# assert IS still recorded, which is not a special case: it sets `refused` in the
# same breath and so on entry its own `refused` is still False.
# ===========================================================================

type Nul is Data:
  Nul{dev: String, renders: List<&2, C.Cr>, enc: List<&2, String>, bufz: U32,
      host: String, tl: U32, t: C.Tr}

def Nul.t(n: Nul) -> C.Tr:
  match n:
    case Nul{dev, renders, enc, bufz, host, tl, t}: t

def Nul.dev(n: Nul) -> String:
  match n:
    case Nul{dev, renders, enc, bufz, host, tl, t}: dev

def Nul.renders(n: Nul) -> List<&2, C.Cr>:
  match n:
    case Nul{dev, renders, enc, bufz, host, tl, t}: renders

def Nul.tl(n: Nul) -> U32:
  match n:
    case Nul{dev, renders, enc, bufz, host, tl, t}: tl

# the assert as a trace event: the call IS recorded and `refused` is set when it
# fails. `Bool.or` rather than a pick, so a SECOND failing assert cannot clear
# an earlier one.
def Tr.assert_at(+bad: Bool, t: C.Tr) -> C.Tr:
  match t:
    case C.Tr{calls, refused}:
      C.Tr{List.append(&2, C.Call, calls, [C.Call{C.CALL_ASSERT_EMULATE(), Bool.to_u32(bad)}]),
         Bool.or(refused, bad)}

def ndev.init(+dev: String, +emu: String) -> Nul:
  Nul{dev, ndev.renderers(), ndev.encode_names(), ndev.bufferize_n(), ndev.host(dev),
      ndev.timeline_nbytes(),
      Tr.assert_at(Bool.not(String.eq(emu, "")), C.Tr.of())}


# --- 6: the NULL queue -- the five ops and the four words ----------------
def subat.of(m: Maybe<&2, C.Sub>) -> String:
  match m:
    case Some{+x}: C.Sub.nm(x)
    case None{}: "?"

def subat(xs: List<&2, C.Sub>, k: Nat) -> String:
  subat.of(List.get(&2, C.Sub, xs, k))

def t_queue() -> IO(Unit):
  do IO<Unit>:
    C.urow("nr_exec", NEXEC())
    C.urow("nr_copy", NCOPY())
    C.urow("nr_wait", NWAIT())
    C.urow("nr_store", NSTORE())
    C.urow("nr_timestamp", NTIMESTAMP())
    C.urow("nr_nargs_exec", nr.nargs(NEXEC()))
    C.urow("nr_pads_exec", nr.pads(NEXEC()))
    C.urow("nr_words_exec", U32.from_nat(List.length(&2, U32, nr.exec(60, 2, 1))))
    C.urow("nr_nargs_copy", nr.nargs(NCOPY()))
    C.urow("nr_pads_copy", nr.pads(NCOPY()))
    C.urow("nr_words_copy", U32.from_nat(List.length(&2, U32, nr.copy(21, 22, 0))))
    C.urow("nr_nargs_wait", nr.nargs(NWAIT()))
    C.urow("nr_pads_wait", nr.pads(NWAIT()))
    C.urow("nr_words_wait", U32.from_nat(List.length(&2, U32, nr.wait(11, 12, False{}))))
    C.urow("nr_nargs_store", nr.nargs(NSTORE()))
    C.urow("nr_pads_store", nr.pads(NSTORE()))
    C.urow("nr_words_store", U32.from_nat(List.length(&2, U32, nr.signal(31, 32))))
    C.urow("nr_nargs_ts", nr.nargs(NTIMESTAMP()))
    C.urow("nr_pads_ts", nr.pads(NTIMESTAMP()))
    C.urow("nr_words_ts", U32.from_nat(List.length(&2, U32, nr.timestamp(20))))
    C.srow("nr_copy_dev", nr.copy_dev("PYTHON"))
    C.srow("nr_copy_name", nr.copy_name("PYTHON", "NULL:1"))
    # the WORDS of the measured stream, one row per position, so a port that
    # padded correctly and filled the pad with something else is caught
    C.lrow("nr_words_exec_all", nr.exec(60, 2, 1))
    C.lrow("nr_words_copy_all", nr.copy(21, 22, 0))
    C.lrow("nr_words_wait_all", nr.wait(11, 12, False{}))
    C.lrow("nr_words_wait_eq", nr.wait(11, 12, True{}))
    C.lrow("nr_words_store_all", nr.signal(31, 32))
    C.lrow("nr_words_ts_all", nr.timestamp(20))
    C.urow("nr_ts_offset", U32.sub(C.nth(nr.timestamp(20), 1n), 20))
    C.urow("nr_submit_n", U32.from_nat(List.length(&2, C.Sub, C.nr.submit_graph())))
    C.rlist("nr_submit_graph", C.subnames(C.nr.submit_graph()))
    C.srow("nr_submit_root", subat(C.nr.submit_graph(), 6n))
    C.urow("nr_has_local", nr.has_local())
    C.srow("nr_float4", nr.float4())
    C.srow("nr_barrier", nr.barrier())
    C.urow("nr_cstyle_n", nr.cstyle_n())
    C.urow("nr_cfop_overrides", nr.cfop_overrides())
    C.urow("nr_cfop_total", nr.cfop_total())
    C.srow("nr_cfop_threefry", nr.cfop_threefry("A", "B"))
    C.srow("nr_cfop_max", nr.cfop_max("A", "B"))
    C.urow("nr_asm_ok_gfx1100", Bool.to_u32(nr.asm_ok("gfx1100")))
    # gfx950 is the CDNA4 answer `nr_emulate_arch_cdna4` hands out, and it is the
    # fixture that separates `startswith("gfx")` from every longer prefix.
    C.urow("nr_asm_ok_gfx950", Bool.to_u32(nr.asm_ok("gfx950")))
    C.urow("nr_asm_ok_arm64", Bool.to_u32(nr.asm_ok("arm64")))
    C.srow("nr_asm_msg", nr.asm_msg())

# --- 7: the NULL DEVICE and the allocator, :48-68 ------------------------
def t_ndev() -> IO(Unit):
  do IO<Unit>:
    +n: Nul <- IO.pure(Nul, ndev.init("NULL:1", ""))
    C.srow("nr_dev", Nul.dev(n))
    C.urow("nr_dev_id", D.dev_id(Nul.dev(n)))
    C.srow("nr_host", ndev.host(Nul.dev(n)))
    C.urow("nr_has_copy_queue_inherited", nr.has_copy_queue())
    C.urow("nr_encode_n", U32.from_nat(List.length(&2, String, ndev.encode_names())))
    C.rlist("nr_encode_names", ndev.encode_names())
    C.urow("nr_bufferize_n", ndev.bufferize_n())
    C.urow("nr_compiled_bufferize_n", ndev.compiled_bufferize_n())
    C.urow("nr_renderers_pre", ndev.renderers_pre())
    C.urow("nr_renderers_n", U32.from_nat(List.length(&2, C.Cr, Nul.renders(n))))
    C.srow("nr_renderers", C.rnames(Nul.renders(n)))
    C.urow("nr_timeline_n", ndev.timeline_n())
    C.urow("nr_timeline_bytes", Nul.tl(n))
    C.urow("nr_link_ext_ptr", ndev.link_ext_ptr())
    C.urow("nr_link_2_f32", ndev.link_nbytes(2, S.single()))
    C.urow("nr_link_3_u64", ndev.link_nbytes(3, S.uint64()))
    C.nrow("nva_first", nalloc.va(0n))
    C.nrow("nva_base", nva.base())
    C.nrow("nva_step1", Nat.sub(nalloc.va(1n), nalloc.va(0n)))
    C.nrow("nva_step2", Nat.sub(nalloc.va(2n), nalloc.va(1n)))
    C.urow("nva_count3", Bool.to_u32(Bool.and(Nat.is_ne(nalloc.va(1n), nalloc.va(0n)),
         Bool.and(Nat.is_ne(nalloc.va(2n), nalloc.va(1n)), Nat.is_ne(nalloc.va(2n), nalloc.va(0n))))))
    C.urow("nalloc_copyin_nops", nalloc.copyin_nops())
    C.urow("nr_copyout_ok_0", nalloc.copyout_ok(0))
    C.srow("nr_copyout_msg", nalloc.copyout_msg())
    C.urow("nr_copyout_ok_1", nalloc.copyout_ok(1))
    C.row("nr_map_null_NULL", nalloc.map_is_null("NULL"))
    C.row("nr_map_null_NULL_1", nalloc.map_is_null("NULL:1"))
    C.row("nr_map_null_NULL_0", nalloc.map_is_null("NULL:0"))
    C.row("nr_map_null_CPU", nalloc.map_is_null("CPU"))
    C.row("nr_map_null_null", nalloc.map_is_null("null"))

# A `pack_args` FIXTURE: the itemsize list and the sum of them, which is `end`.
# `end` is a second field rather than a fold because the SAME list feeds the
# size, the offsets and the tail, and a `U32` cannot be read twice in one
# expression -- the `Amt` trick from device.bend, for a different reason.
type Pk is Data:
  Pk{ks: List<&2, U32>, e: U32}

def Pk.itemsizes(p: Pk) -> List<&2, U32>:
  match p:
    case Pk{ks, e}: ks

def Pk.nargs(p: Pk) -> U32: U32.from_nat(List.length(&2, U32, Pk.itemsizes(p)))

def Pk.end(p: Pk) -> U32:
  match p:
    case Pk{ks, e}: e

# `end` IS THE RUNNING `Cn.next`, not the sum of the itemsizes: hcq2.py:82 writes
# `end = offset + arg.dtype.itemsize` where `offset` is the ALIGNED slot, so for
# `[4, 8, 4]` the sum is 16 and the real end is 20. A tail computed from the sum
# gives 8 where CPython gives 4. `pk_tail_484` is the row.
def pkend.go(n: Nat, ks: List<&2, U32>, +off: U32, end: U32) -> U32:
  match n:
    case 0n: end
    case 1n+p:
      match ks:
        case Nil{}: end
        case +k <> t: pkend.go(p, t, C.Cn.next(C.cn_slot(off, k)), C.Cn.next(C.cn_slot(off, k)))

def pkend(+ks: List<&2, U32>) -> U32: pkend.go(List.length(&2, U32, ks), ks, 0, 0)

def fx_pk(+ks: List<&2, U32>) -> Pk: Pk{ks, pkend(ks)}

# --- 8: pack_args, hcq2.py:78-83 ----------------------------------------
def t_pack() -> IO(Unit):
  do IO<Unit>:
    +k0: Pk <- IO.pure(Pk, fx_pk(Nil{}))
    +k1: Pk <- IO.pure(Pk, fx_pk([4]))
    +k2: Pk <- IO.pure(Pk, fx_pk([4,4]))
    +k3: Pk <- IO.pure(Pk, fx_pk([4,4,4]))
    +k4: Pk <- IO.pure(Pk, fx_pk([8,4]))
    +k5: Pk <- IO.pure(Pk, fx_pk([8,8]))
    +k6: Pk <- IO.pure(Pk, fx_pk([4,4,4,4]))
    +k7: Pk <- IO.pure(Pk, fx_pk([4,8,4]))
    C.urow("pk_size_4", pk.size(Pk.nargs(k1)))
    C.urow("pk_nsrc_4", pk.nsrc(Pk.nargs(k1), pk.pads(Pk.itemsizes(k1))))
    C.urow("pk_tail_4", pk.tail(Pk.nargs(k1), Pk.end(k1)))
    C.urow("pk_pads_4", pk.pads(Pk.itemsizes(k1)))
    C.lrow("pk_offsets_4", C.pk.offsets(Pk.itemsizes(k1)))
    C.urow("pk_size_44", pk.size(Pk.nargs(k2)))
    C.urow("pk_nsrc_44", pk.nsrc(Pk.nargs(k2), pk.pads(Pk.itemsizes(k2))))
    C.urow("pk_tail_44", pk.tail(Pk.nargs(k2), Pk.end(k2)))
    C.urow("pk_pads_44", pk.pads(Pk.itemsizes(k2)))
    C.lrow("pk_offsets_44", C.pk.offsets(Pk.itemsizes(k2)))
    C.urow("pk_size_444", pk.size(Pk.nargs(k3)))
    C.urow("pk_nsrc_444", pk.nsrc(Pk.nargs(k3), pk.pads(Pk.itemsizes(k3))))
    C.urow("pk_tail_444", pk.tail(Pk.nargs(k3), Pk.end(k3)))
    C.urow("pk_pads_444", pk.pads(Pk.itemsizes(k3)))
    C.lrow("pk_offsets_444", C.pk.offsets(Pk.itemsizes(k3)))
    C.urow("pk_size_84", pk.size(Pk.nargs(k4)))
    C.urow("pk_nsrc_84", pk.nsrc(Pk.nargs(k4), pk.pads(Pk.itemsizes(k4))))
    C.urow("pk_tail_84", pk.tail(Pk.nargs(k4), Pk.end(k4)))
    C.urow("pk_pads_84", pk.pads(Pk.itemsizes(k4)))
    C.lrow("pk_offsets_84", C.pk.offsets(Pk.itemsizes(k4)))
    C.urow("pk_size_88", pk.size(Pk.nargs(k5)))
    C.urow("pk_nsrc_88", pk.nsrc(Pk.nargs(k5), pk.pads(Pk.itemsizes(k5))))
    C.urow("pk_tail_88", pk.tail(Pk.nargs(k5), Pk.end(k5)))
    C.urow("pk_pads_88", pk.pads(Pk.itemsizes(k5)))
    C.lrow("pk_offsets_88", C.pk.offsets(Pk.itemsizes(k5)))
    C.urow("pk_size_4444", pk.size(Pk.nargs(k6)))
    C.urow("pk_nsrc_4444", pk.nsrc(Pk.nargs(k6), pk.pads(Pk.itemsizes(k6))))
    C.urow("pk_tail_4444", pk.tail(Pk.nargs(k6), Pk.end(k6)))
    C.urow("pk_pads_4444", pk.pads(Pk.itemsizes(k6)))
    C.lrow("pk_offsets_4444", C.pk.offsets(Pk.itemsizes(k6)))
    C.urow("pk_size_484", pk.size(Pk.nargs(k7)))
    C.urow("pk_nsrc_484", pk.nsrc(Pk.nargs(k7), pk.pads(Pk.itemsizes(k7))))
    C.urow("pk_tail_484", pk.tail(Pk.nargs(k7), Pk.end(k7)))
    C.urow("pk_pads_484", pk.pads(Pk.itemsizes(k7)))
    C.lrow("pk_offsets_484", C.pk.offsets(Pk.itemsizes(k7)))
    # THE EMPTY CALL. MEASURED: `layout_args([])` is `[]`, `8 * max(0, 1)` is 8,
    # and `pack_args([], 8)` still emits the one 8-byte zero tail. Without these
    # five rows `pk.size` could lose its `max` and stay correct on all seven
    # non-empty layouts.
    C.urow("pk_size_0", pk.size(Pk.nargs(k0)))
    C.urow("pk_nsrc_0", pk.nsrc(Pk.nargs(k0), pk.pads(Pk.itemsizes(k0))))
    C.urow("pk_tail_0", pk.tail(Pk.nargs(k0), Pk.end(k0)))
    C.urow("pk_pads_0", pk.pads(Pk.itemsizes(k0)))
    C.lrow("pk_offsets_0", C.pk.offsets(Pk.itemsizes(k0)))

# THE MEASURED COMMAND WORD STREAM: the twelve `cmd` calls I captured off the
# real NULL device, as four-word tuples with the pads explicit. 48 words, twelve
# quads. EXEC's third argument is word 2 and its event id is word 3; TIMESTAMP's
# only argument is word 1 and its two pads are words 2 and 3.
#
# THE STREAM IS BUILT BY APPENDING, and `List.append(a, A, xs, ys)` is `xs ++ ys`,
# so the nested appends below read left to right as the command order: the
# INNERMOST is the LAST command. Consing here would put EXEC first and
# `nprog_descs` -- which is the copy-then-exec order, and the thing setdefault's
# ids depend on -- would come out reversed.
def cmds() -> List<&2, U32>:
  List.append(&2, U32, nr.wait(11, 12, False{}),
    List.append(&2, U32, nr.timestamp(20),
      List.append(&2, U32, nr.copy(21, 22, 0),
        List.append(&2, U32, nr.timestamp(30),
          List.append(&2, U32, nr.signal(31, 32),
            List.append(&2, U32, nr.wait(41, 42, False{}),
              List.append(&2, U32, nr.wait(43, 44, False{}),
                List.append(&2, U32, nr.timestamp(50),
                  List.append(&2, U32, nr.exec(60, 2, 1),
                    List.append(&2, U32, nr.timestamp(70),
                      List.append(&2, U32, nr.wait(81, 82, False{}),
                        nr.signal(83, 84))))))))))))

def zeroed(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p: zeroed(p, List.append(&2, U32, acc, [0]))

# `evids` -- the id of every key in a table, IN ORDER, which is the same list
# `setdefault`'s values are. `List.append` is in order and this walk does not
# reverse, so the ids come out ascending and the row is the whole table.
def evids.go(n: Nat, es: List<&2, Nk>, +at: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p:
      match es:
        case Nil{}: acc
        case h <> t: evids.go(p, t, U32.add(at, 1), List.append(&2, U32, acc, [at]))

def evids(+es: List<&2, Nk>) -> List<&2, U32>:
  evids.go(List.length(&2, Nk, es), es, 0, Nil{})

# the FIVE lookups the oracle runs, `k0, k1, k0, k1, k2`, with the TABLE growing
# underneath them. Two accumulators in one `Data` record because both the id and
# the grown table have to come back out, and `Ev.put` and `Ev.lookup` must both
# see the table as it was BEFORE this key -- which is the whole of `setdefault`.
type EvQ is Data:
  EvQ{tbl: List<&2, Nk>, acc: List<&2, U32>}

def EvQ.tbl(q: EvQ) -> List<&2, Nk>:
  match q:
    case EvQ{tbl, acc}: tbl

def EvQ.acc(q: EvQ) -> List<&2, U32>:
  match q:
    case EvQ{tbl, acc}: acc

def evq.go(n: Nat, ks: List<&2, Nk>, +q: EvQ) -> EvQ:
  match n:
    case 0n: q
    case 1n+p:
      match ks:
        case Nil{}: q
        case +k <> t:
          +g: EvQ = EvQ{Ev.put(k, EvQ.tbl(q)),
                        List.append(&2, U32, EvQ.acc(q), [Ev.lookup(k, EvQ.tbl(q))])}
          evq.go(p, t, g)

def evlookup(+want: List<&2, Nk>) -> List<&2, U32>:
  EvQ.acc(evq.go(List.length(&2, Nk, want), want, EvQ{Nil{}, Nil{}}))

# the table the five lookups leave behind -- `setdefault` applied to the SAME
# five keys in the SAME order, which is how `nr_event_count_after` is measured
# without a second hand-written fold. A `+` on both because `Ev.put` reads the
# table through each `Nk.same`.
def evtab5(+k0: Nk, +k1: Nk, +k2: Nk) -> List<&2, Nk>:
  Ev.put(k2, Ev.put(k1, Ev.put(k0, Ev.put(k1, Ev.put(k0, Nil{})))))

def t_prog() -> IO(Unit):
  do IO<Unit>:
    +st: St <- IO.pure(St, nprog.streams(nprog.sig7()))
    C.urow("nprog_sig_n", U32.from_nat(List.length(&2, Sg, nprog.sig7())))
    C.urow("nprog_streams_n", U32.div(U32.from_nat(List.length(&2, U32, St.pairs(st))), 2))
    C.lrow("nprog_streams", St.pairs(st))
    C.urow("nprog_stream_bytes", St.nbytes(st))
    C.urow("nprog_qwords", nprog.qwords(St.nbytes(st)))
    C.urow("nprog_quads", U32.div(nprog.qwords(St.nbytes(st)), 4))
    +ws: List<&2, U32> <- IO.pure(List<&2, U32>, cmds())
    C.urow("nprog_words_n", U32.from_nat(List.length(&2, U32, ws)))
    C.urow("nprog_quads_real", nprog.quads(ws))
    C.urow("nprog_writes_ts", nprog.writes(ws))
    +wz: List<&2, U32> <- IO.pure(List<&2, U32>, zeroed(48n, Nil{}))
    C.urow("nprog_writes_zeroed", nprog.writes(wz))
    C.urow("nprog_done_at_0", nprog.done_at(ws, 0n))
    C.urow("nprog_done_at_1", nprog.done_at(ws, 1n))
    C.urow("nprog_done_at_2", nprog.done_at(ws, 2n))
    C.urow("nprog_done_at_8", nprog.done_at(ws, 8n))
    C.urow("nprog_done_at_11", nprog.done_at(ws, 11n))
    C.urow("nprog_done_sum", nprog.done_at(ws, 12n))
    C.urow("nprog_stamp_val_1000_0", nprog.stamp_val(1000, 0))
    C.urow("nprog_stamp_val_1000_1", nprog.stamp_val(1000, 1))
    C.urow("nprog_stamp_val_7_3", nprog.stamp_val(7, 3))
    C.lrow("nprog_ent_ids_0", nprog.ent_ids(0))
    C.lrow("nprog_ent_ids_1", nprog.ent_ids(1))
    +ev0: Nk <- IO.pure(Nk, Nk{"PYTHON:SDMA:0", "PYTHON -> NULL:1", 0})
    +ev1: Nk <- IO.pure(Nk, Nk{"NULL", "E_3", 7})
    +e1: List<&2, Nk> <- IO.pure(List<&2, Nk>, List.append(&2, Nk, Ev.put(ev0, Nil{}), [ev1]))
    C.urow("nr_events_n", U32.from_nat(List.length(&2, Nk, e1)))
    C.lrow("nr_event_ids", evids(e1))
    +k5: Nk <- IO.pure(Nk, Nk{"PYTHON:SDMA:0", "E_4", 0})
    C.lrow("nr_event_lookup", evlookup([ev0, ev1, ev0, ev1, k5]))
    C.urow("nr_event_count_after", U32.from_nat(List.length(&2, Nk, evtab5(ev0, ev1, k5))))
    +ka: Nk <- IO.pure(Nk, Nk{"NULL", "E_3", 1})
    +kb: Nk <- IO.pure(Nk, Nk{"NULL", "E_3", 2})
    C.urow("nr_event_key_matters", Bool.to_u32(Bool.not(Nk.same(ka, kb))))
    +dd: List<&2, String> <- IO.pure(List<&2, String>, nprog.descs(ws, e1))
    C.urow("nprog_descs_n", U32.from_nat(List.length(&2, String, dd)))
    C.rlist("nprog_descs", dd)
    C.lrow("nprog_sigs", nprog.sigs(1000, dd))
    C.lrow("nprog_sigs_same", nprog.sigs(1000, ["A", "A", "A"]))
    C.lrow("nprog_sigs_mixed", nprog.sigs(1000, ["A", "B", "A"]))

# --- 10: the ops NULL does and does not zero, and the assert --------------
def t_zero() -> IO(Unit):
  do IO<Unit>:
    C.urow("nr_zero_rand", nr.zero_of("rand"))
    C.urow("nr_zero_randn", nr.zero_of("randn"))
    C.urow("nr_zero_full", nr.zero_of("full"))
    C.urow("nr_zero_eye", nr.zero_of("eye"))
    C.urow("nr_zero_arange", nr.zero_of("arange"))
    C.urow("nr_zero_add", nr.zero_of("add"))
    C.urow("nr_zero_sum", nr.zero_of("sum"))
    C.urow("nr_zero_l2norm", nr.zero_of("l2norm"))
    C.urow("nr_zero_ones", nr.zero_of("ones"))
    C.urow("nr_zero_dot", nr.zero_of("dot"))
    C.urow("nr_zero_neg", nr.zero_of("neg"))
    C.urow("nr_zero_max", nr.zero_of("max"))
    C.urow("nr_zero_softmax", nr.zero_of("softmax"))
    C.urow("nr_zero_missing", nr.zero_of("relu"))
    C.urow("ndev_zero_table_n", U32.from_nat(List.length(&2, Zz, nr.zero_table())))
    C.srow("nr_emulate_arch_empty", ndev.emulate_arch(""))
    C.srow("nr_emulate_msg_empty", ndev.emulate_msg(""))
    C.srow("nr_emulate_arch_amd", ndev.emulate_arch("AMD"))
    C.srow("nr_emulate_msg_amd", ndev.emulate_msg("AMD"))
    C.srow("nr_emulate_arch_rdna4", ndev.emulate_arch("AMD_RDNA4"))
    C.srow("nr_emulate_msg_rdna4", ndev.emulate_msg("AMD_RDNA4"))
    C.srow("nr_emulate_arch_cdna4", ndev.emulate_arch("AMD_CDNA4"))
    C.srow("nr_emulate_msg_cdna4", ndev.emulate_msg("AMD_CDNA4"))
    C.srow("nr_emulate_arch_raw", ndev.emulate_arch("gfx1100"))
    C.srow("nr_emulate_msg_raw", ndev.emulate_msg("gfx1100"))
    C.srow("nr_emulate_arch_junk", ndev.emulate_arch("nonsense"))
    C.srow("nr_emulate_msg_junk", ndev.emulate_msg("nonsense"))
    C.srow("nr_emulate_prefix", ndev.emulate_prefix())
    # THE REFUSAL. `assert emu == ""` is the FIRST statement, so a failing one
    # means `super().__init__` never runs and there is no device. The trace is
    # the observable: it holds the assert and NOTHING after it, and
    # `nr_assert_blocks_*` is that -- one further seam call, still unrecorded.
    +ok: Nul <- IO.pure(Nul, ndev.init("NULL:1", ""))
    +bad: Nul <- IO.pure(Nul, ndev.init("NULL:1", "AMD"))
    C.urow("nr_assert_trace_ok_n", C.seen(Nul.t(ok)))
    C.urow("nr_assert_trace_bad_n", C.seen(Nul.t(bad)))
    C.urow("nr_assert_refused_ok", Bool.to_u32(C.Tr.refused(Nul.t(ok))))
    C.urow("nr_assert_refused_bad", Bool.to_u32(C.Tr.refused(Nul.t(bad))))
    C.urow("nr_assert_post_ok", C.seen(C.Tr.emit(C.CALL_PING(), 0, Nul.t(ok))))
    C.urow("nr_assert_post_bad", C.seen(C.Tr.emit(C.CALL_PING(), 0, Nul.t(bad))))


def main() -> IO(Unit):
  do IO<Unit>:
    f : Unit <- t_queue()
    g : Unit <- t_ndev()
    h : Unit <- t_pack()
    i : Unit <- t_prog()
    j : Unit <- t_zero()
    IO.print("cn-done=1")

#   M28  `EvA.step` last-wins. A SOUND EQUIVALENCE, with a proof rather than a
#        shrug: `Nk.same` IS Python's tuple equality on `(device, name, key)`,
#        `null_events` is a DICT so it never holds two equal keys, and `Ev.put`
#        -- the only inserter, and pinned by M29's five rows -- appends on a
#        miss only. Given "no equal pair in the table", first-wins and
#        last-wins are the same function. The invariant that makes M28 sound is
#        itself the thing M29 pins.
#
#   M53  `nr.zero_of.go` last-wins. THE SAME ARGUMENT: the thirteen names are
#        thirteen separately MEASURED ops, so at most one row ever matches.
#        There is no duplicate to plant, and planting one would assert a state
#        the table cannot be in.
#
#
# THE MEASURED ENTRIES for the rules above. The other 109 - these and the
# CPU half's, which is in `ops_cpu.bend` - are filed by the def each names;
# `cn-mutate.py` walked them in order M1..M109 across the pre-split file.
#
#   M28    0  EvA.step: last-wins becomes first-wins  (argued above)
#   M53    0  nr.zero_of.go: last-wins becomes first-wins (argued above)
#   M1      5  nr.pads: `3 - arity` -> `4 - arity`
#   M2     22  nr.words: emit FIVE words (the `[:4]` slice dropped)
#   M3      4  nr.nargs: swap the TIMESTAMP and STORE arities
#   M4      2  nr.timestamp: drop the `+ 8` (the timeline value slot)
#   M5      1  nr.copy_dev: drop the `:SDMA:0` suffix
#   M28     0  Ev.lookup: last-wins instead of first-wins   ZERO -- see below
#   M29     5  Ev.put: the miss does NOT insert (setdefault -> get)
#   M30     1  Nk.same: the `key` field ignored (device+name only)
#   M31     1  nr.copy_name: the arrow becomes a comma
#   M32     1  nr.cfop_threefry: a space after the comma
#   M33     1  nr.renderers: the deduped list sorted (order no longer the policy)
#   M34     2  nalloc.va: the 1<<32 step becomes 1<<31
#   M35     2  nalloc.map_is_null: `startswith` -> equality
#   M36     1  nalloc.copyout_ok: the flag IGNORED (always refuse)
#   M37     5  nprog.sig7: the cmdbuf name at index 5 does not start with `cmdbuf`
#   M38     2  nprog.qwords: bytes divided by 4 instead of 8
#   M39     7  nprog.is_work: EXEC or COPY -> EXEC only
#   M40     3  nprog.stamp_val: microseconds, not nanoseconds
#   M41     2  nprog.done_at: the inclusive accumulate becomes exclusive
#   M42     2  nprog.lane.go: `or` becomes `and` (the count stops growing)
#   M43     3  nprog.sigs: the lane term dropped from the odd entries
#   M47     1  pkend: the sum of the itemsizes instead of the running `next`
#   M49     6  ndev.emulate_arch: the `<arch>` fallback replaced by the key
#   M50     2  ndev.emulate_table: AMD_CDNA4 maps to gfx1201 not gfx950
#   M51     1  nr.zero_table: `eye` marked as all-zero (the scheduler fact, faked)
#   M52     1  nr.zero_table: `arange` marked as all-zero
#   M53     0  nr.zero_of.go: last-wins (the hit overwrites)   ZERO -- see below
#   M58     1  nprog.streams.go: the pairs CONS (the stream order reverses)
#   M59     3  cmds(): the whole 12-command stream emitted in REVERSE
#   M68     1  nr.asm_ok: `startswith("gfx")` -> `startswith("gfx1")`
#   M69     7  ndev.emulate_prefix: DEV=NULL:HIP -> DEV=NULL:HIP2
#   M70     1  nr.cfop_max: `max(` -> `Max(`
#   M71     1  ndev.timeline_n: `link_buffer(2, uint64)` -> 3 slots
#   M72     1  ndev.link_ext_ptr: external_ptr=1 -> 0
#   M76     2  nprog.ent_ids: `2i, 2i+1` -> `2i, 2i+2`
#   M80     1  ndev.bufferize_n: the ONE NULL rule becomes Compiled`s THREE
#   M86     1  nr.zero_table: `rand` marked as NOT all-zero
#   M91     2  nr.submit_graph: the STORE root becomes a LOAD
#   M93     1  nr.float4: `float4` -> `float2`
#   M94     1  nr.barrier: `// BARRIER` -> `//barrier`
#   M95     1  nr.has_local: False -> True
#   M96     1  ndev.renderers_pre: the raw list is 27 long
#   M97     2  ndev.link_nbytes: `n * itemsize` -> `n`
#   M101   15  nr.words: the op tag is the SECOND slot, not the first
#   M102    6  nprog.done_at: EVERY work command counts, not just EXEC
#   M104    4  ndev.init: the assert is INVERTED (a non-empty EMULATE passes)
#   M105    1  nr.zero_of: a name that is NOT in the table answers 0, not 2
#   M107    1  nr.zero_table: `randn` marked as NOT all-zero (M86 does `rand`)
#   M108    1  nprog.writes: nothing is stamped
#   M109    3  nprog.stamp_val: nanoseconds, not microseconds -- and the other way
