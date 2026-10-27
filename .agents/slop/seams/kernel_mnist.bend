# kernel_mnist.bend -- THE PORT's CPU-LANE KERNEL: the MNIST forward pass, in
# the port's own language, as machine code.
#
#   ./bin/bend .agents/slop/seams/kernel_mnist.bend          # compile + run
#   ./bin/bend .agents/slop/seams/kernel_mnist.bend -o k     # compile to a binary
#   ./k                                                    # run the binary
#
# WHAT IT IS. The model of `.agents/slop/mnist/model.py`, as arithmetic:
#
#     conv1  (1,4,28,28)   relu1   pool1 (1,4,14,14)
#     conv2  (1,8,14,14)   relu2   pool2 (1,8,7,7)
#     flat   (1,392)       fc     (1,10)
#
# THE INPUTS ARE BYTES ON DISK. `weights.f32` is the trained parameter file the
# host wrote (`.agents/slop/seams/mk_inputs.py`, out of
# `.agents/slop/mnist/weights.npz`) and `img0.u8` is one test image. The ORACLE
# for every number this file computes is CPython's OWN device
# (`.agents/slop/seams/oracle_stages.py`), never a hand-typed constant.
#
# THE OUTPUT IS BYTES ON DISK. `port_stages.f32` holds the eight stages in the
# order `conv1 relu1 pool1 conv2 relu2 pool2 flat logits`, float32
# little-endian, concatenated -- and `.agents/slop/seams/compare.py` compares
# those bytes against CPython's, element by element, and its EXIT STATUS is
# the verdict.
#
# IT PRINTS ITS OWN TIMES. `IO.now()` is the runtime's own clock, so the
# `stage_ms` lines are the port's measurement of itself and not the host's
# measurement of it.
#
# ---------------------------------------------------------------------------
# WHAT IS *NOT* HERE, because the distinction is the whole point and it must
# not be lost: this file is NOT the port's `Device`/`UOp`/`renderer`/`Program`
# lane.  It computes the model directly, in the port's own language, and it
# therefore BYPASSES the port's allocator, its renderer, its ELF emitter and
# its loader -- the four places where the port's device lane is walled.  It is
# a PROOF that the port's LANGUAGE and TOOLCHAIN can run this model on a CPU,
# not a claim that the port's device lane can.  The device lane's own walls
# are named in `tinybendygrad/runtime/ops_cpu.bend` and in
# `tinybendygrad/engine/realize.bend`, and they are unchanged by this file.
#
# ---------------------------------------------------------------------------
# WHY LISTS AND NOT `Array`.  MEASURED, and it is the reason this file looks
# the way it does.  A function that takes BOTH a `List` and an `Array` writes
# the array's cells wrongly: the values land in sixteen places per cell, and
# the pattern is the same in the JavaScript lane and in the native one, so it
# is not a backend artefact.  A function that takes only an `Array` writes it
# correctly.  So the kernel is written over LISTS.
#
# The price of the lists is ADDRESSING, and the price is stated rather than
# hidden: a read is `List.get`, which is a traversal, so a read of a tensor
# of n cells costs O(n).  The kernel keeps the tensors it reads most (the
# weights) in ONE list and reads them at their real offsets, so the hot
# reads are over the SHORT end of the list: conv1's weights live in cells
# 4..39 and conv2's in cells 48..335, and only the FC weights are far out.
#
# The shape of the code is BEND's AFFINITY, not taste: a recursion's counter is
# the scrutinee and NOTHING ELSE, every list that more than one expression
# reads carries `+`, and every `match` is on a PARAMETER.
# ---------------------------------------------------------------------------

import Base
import ./../../../tinybendygrad/base.bend as F

# ---- the weight file's layout, in FLOATS ----------------------------------
# conv1.bias 4 | conv1.weight 4*1*3*3=36 | conv2.bias 8 | conv2.weight
# 8*4*3*3=288 | fc.bias 10 | fc.weight 10*392=3920.  THE ORACLE CHECKS THESE:
# every stage the kernel writes is compared against CPython's own device.
def W_C1B() -> Nat: 0n
def W_C1W() -> Nat: 4n
def W_C2B() -> Nat: 40n
def W_C2W() -> Nat: 48n
def W_FCB() -> Nat: 336n
def W_FCW() -> Nat: 346n

# ===========================================================================
# READING.  `fget` is O(index): a LIST READ IS A TRAVERSAL.
# ===========================================================================
def fget.go(m: Maybe<&2, F32>) -> F32:
  match m:
    case Some{v}: v
    case None{}: 0.0

def fget(+xs: List<&2, F32>, i: Nat) -> F32: fget.go(List.get(&2, F32, xs, i))

# A ZERO IF THE COORDINATE IS OUT OF RANGE, AND ZERO OTHERWISE THE VALUE.
# The convolution's border is the ONLY place the padding shows up.
def pick(v: F32, ok: Bool) -> F32:
  match ok:
    case True{}: v
    case False{}: 0.0

# ===========================================================================
# conv1: 1 input channel, 4 output channels, 3x3, pad 1.
#   c1[o][y][x] = bias1[o] + sum_{ky,kx} w1[o][ky][kx] * img[y+ky-1][x+kx-1]
# The tap index ki runs 0..8 and IS (ky, kx) in that order.
#
# THE TAP COUNT IS THE COUNT, NOT THE LAST INDEX.  `conv1.tap(k, ki, ..)` runs
# its body while `k` is not zero and STOPS at `k == 0`, so a call with `k = 8n`
# performs EIGHT taps with ki = 0..7 and NEVER reaches ki = 8: the bottom-right
# tap is missing.  MEASURED, and it is a whole-class bug -- the first run of
# this kernel was bit-identical to an EIGHT-tap convolution on 3136 of 3136
# conv1 outputs, and the ninth tap's weight was never read.  So the call is
# `9n` for nine taps, `36n` for thirty-six, `392n` for three hundred and
# ninety-two.
# ===========================================================================
def conv1.tap(k: Nat, +ki: Nat, +w: List<&2, F32>, +im: List<&2, F32>,
              +o: Nat, +y: Nat, +x: Nat, acc: F32) -> F32:
  match k:
    case 0n: acc
    case 1n+p:
      +ky : Nat = Nat.div(ki, 3n)
      +kx : Nat = Nat.mod(ki, 3n)
      +sy1 : Nat = Nat.add(y, ky)
      +sx1 : Nat = Nat.add(x, kx)
      +ok : Bool = Bool.and(Nat.is_lt(0n, sy1), Nat.is_lt(sy1, 29n))
      +ok : Bool = Bool.and(ok, Bool.and(Nat.is_lt(0n, sx1), Nat.is_lt(sx1, 29n)))
      +sy : Nat = Nat.sub(sy1, 1n)
      +sx : Nat = Nat.sub(sx1, 1n)
      conv1.tap(p, Nat.add(ki, 1n), w, im, o, y, x,
        F32.add(acc, F32.mul(fget(w, Nat.add(Nat.add(W_C1W(), Nat.mul(o, 9n)), ki)),
                             pick(fget(im, Nat.add(Nat.mul(sy, 28n), sx)), ok))))

def conv1.px(+i: Nat, +w: List<&2, F32>, +im: List<&2, F32>) -> F32:
  +o : Nat = Nat.div(i, 784n)
  +rem : Nat = Nat.mod(i, 784n)
  +y : Nat = Nat.div(rem, 28n)
  +x : Nat = Nat.mod(rem, 28n)
  conv1.tap(9n, 0n, w, im, o, y, x, fget(w, Nat.add(W_C1B(), o)))

def conv1.go(n: Nat, +i: Nat, +w: List<&2, F32>, +im: List<&2, F32>, acc: List<&2, F32>) -> List<&2, F32>:
  match n:
    case 0n: acc
    case 1n+p:
      conv1.go(p, Nat.add(i, 1n), w, im, conv1.px(i, w, im) <> acc)

def conv1(w: List<&2, F32>, im: List<&2, F32>) -> List<&2, F32>:
  List.reverse(&2, F32, conv1.go(3136n, 0n, w, im, Nil{}))

# ===========================================================================
# relu, ELEMENTWISE.  A new list, so the pre-relu values stay available.
# ===========================================================================
def relu.go(n: Nat, +i: Nat, +xs: List<&2, F32>, acc: List<&2, F32>) -> List<&2, F32>:
  match n:
    case 0n: acc
    case 1n+p:
      match xs:
        case Nil{}: acc
        case h <> t: relu.go(p, Nat.add(i, 1n), t, F32.max(h, 0.0) <> acc)

def relu(n: Nat, xs: List<&2, F32>) -> List<&2, F32>:
  List.reverse(&2, F32, relu.go(n, 0n, xs, Nil{}))

# ===========================================================================
# pool1: (4,28,28) -> (4,14,14), a 2x2 MAX.
# ===========================================================================
def pool1.go(n: Nat, +i: Nat, +xs: List<&2, F32>, acc: List<&2, F32>) -> List<&2, F32>:
  match n:
    case 0n: acc
    case 1n+p:
      +o : Nat = Nat.div(i, 196n)
      +rem : Nat = Nat.mod(i, 196n)
      +py : Nat = Nat.div(rem, 14n)
      +px : Nat = Nat.mod(rem, 14n)
      +base : Nat = Nat.add(Nat.mul(o, 784n), Nat.add(Nat.mul(py, 56n), Nat.mul(px, 2n)))
      +a : F32 = fget(xs, base)
      +b : F32 = fget(xs, Nat.add(base, 28n))
      +c : F32 = fget(xs, Nat.add(base, 1n))
      +d : F32 = fget(xs, Nat.add(base, 29n))
      pool1.go(p, Nat.add(i, 1n), xs, F32.max(F32.max(a, b), F32.max(c, d)) <> acc)

def pool1(n: Nat, xs: List<&2, F32>) -> List<&2, F32>:
  List.reverse(&2, F32, pool1.go(n, 0n, xs, Nil{}))

# ===========================================================================
# conv2: 4 input channels, 8 output channels, 3x3, pad 1.
#   c2[o][y][x] = bias2[o] + sum_{c,ky,kx} w2[o][c][ky][kx] * p1[c][y+ky-1][x+kx-1]
# The tap index ki runs 0..35 and IS (c, ky, kx) in that order, so the
# accumulation order is c, then ky, then kx -- and it is stated here so a
# reader can check it against the oracle.
# ===========================================================================
def conv2.tap(k: Nat, +ki: Nat, +w: List<&2, F32>, +p1: List<&2, F32>,
              +o: Nat, +y: Nat, +x: Nat, acc: F32) -> F32:
  match k:
    case 0n: acc
    case 1n+p:
      +c : Nat = Nat.div(ki, 9n)
      +ky : Nat = Nat.div(Nat.mod(ki, 9n), 3n)
      +kx : Nat = Nat.mod(ki, 3n)
      +sy1 : Nat = Nat.add(y, ky)
      +sx1 : Nat = Nat.add(x, kx)
      +ok : Bool = Bool.and(Nat.is_lt(0n, sy1), Nat.is_lt(sy1, 15n))
      +ok : Bool = Bool.and(ok, Bool.and(Nat.is_lt(0n, sx1), Nat.is_lt(sx1, 15n)))
      +sy : Nat = Nat.sub(sy1, 1n)
      +sx : Nat = Nat.sub(sx1, 1n)
      +src : Nat = Nat.add(Nat.mul(c, 196n), Nat.add(Nat.mul(sy, 14n), sx))
      conv2.tap(p, Nat.add(ki, 1n), w, p1, o, y, x,
        F32.add(acc, F32.mul(fget(w, Nat.add(Nat.add(W_C2W(), Nat.mul(o, 36n)), ki)),
                             pick(fget(p1, src), ok))))

def conv2.px(+i: Nat, +w: List<&2, F32>, +p1: List<&2, F32>) -> F32:
  +o : Nat = Nat.div(i, 196n)
  +rem : Nat = Nat.mod(i, 196n)
  +y : Nat = Nat.div(rem, 14n)
  +x : Nat = Nat.mod(rem, 14n)
  conv2.tap(36n, 0n, w, p1, o, y, x, fget(w, Nat.add(W_C2B(), o)))

def conv2.go(n: Nat, +i: Nat, +w: List<&2, F32>, +p1: List<&2, F32>, acc: List<&2, F32>) -> List<&2, F32>:
  match n:
    case 0n: acc
    case 1n+p:
      conv2.go(p, Nat.add(i, 1n), w, p1, conv2.px(i, w, p1) <> acc)

def conv2(w: List<&2, F32>, p1: List<&2, F32>) -> List<&2, F32>:
  List.reverse(&2, F32, conv2.go(1568n, 0n, w, p1, Nil{}))

# ===========================================================================
# pool2: (8,14,14) -> (8,7,7), a 2x2 MAX.  This is also `flat`: the oracle's
# `flatten(1)` of an (1,8,7,7) tensor is the same 392 values in the same
# channel-major order.
# ===========================================================================
def pool2.go(n: Nat, +i: Nat, +xs: List<&2, F32>, acc: List<&2, F32>) -> List<&2, F32>:
  match n:
    case 0n: acc
    case 1n+p:
      +o : Nat = Nat.div(i, 49n)
      +rem : Nat = Nat.mod(i, 49n)
      +py : Nat = Nat.div(rem, 7n)
      +px : Nat = Nat.mod(rem, 7n)
      +base : Nat = Nat.add(Nat.mul(o, 196n), Nat.add(Nat.mul(py, 28n), Nat.mul(px, 2n)))
      +a : F32 = fget(xs, base)
      +b : F32 = fget(xs, Nat.add(base, 14n))
      +c : F32 = fget(xs, Nat.add(base, 1n))
      +d : F32 = fget(xs, Nat.add(base, 15n))
      pool2.go(p, Nat.add(i, 1n), xs, F32.max(F32.max(a, b), F32.max(c, d)) <> acc)

def pool2(n: Nat, xs: List<&2, F32>) -> List<&2, F32>:
  List.reverse(&2, F32, pool2.go(n, 0n, xs, Nil{}))

# ===========================================================================
# fc: (392) -> (10).  logit[j] = bias[j] + sum_k w[j][k] * flat[k]
# ===========================================================================
def fc.tap(k: Nat, +ki: Nat, +j: Nat, +w: List<&2, F32>, +flat: List<&2, F32>, acc: F32) -> F32:
  match k:
    case 0n: acc
    case 1n+p:
      fc.tap(p, Nat.add(ki, 1n), j, w, flat,
        F32.add(acc, F32.mul(fget(w, Nat.add(Nat.add(W_FCW(), Nat.mul(j, 392n)), ki)),
                             fget(flat, ki))))

def fc.px(+j: Nat, +w: List<&2, F32>, +flat: List<&2, F32>) -> F32:
  fc.tap(392n, 0n, j, w, flat, fget(w, Nat.add(W_FCB(), j)))

def fc.go(n: Nat, +i: Nat, +w: List<&2, F32>, +flat: List<&2, F32>, acc: List<&2, F32>) -> List<&2, F32>:
  match n:
    case 0n: acc
    case 1n+p:
      fc.go(p, Nat.add(i, 1n), w, flat, fc.px(i, w, flat) <> acc)

def fc(w: List<&2, F32>, flat: List<&2, F32>) -> List<&2, F32>:
  List.reverse(&2, F32, fc.go(10n, 0n, w, flat, Nil{}))

# ===========================================================================
# THE OUTPUT BYTES.  float32 little-endian, four bytes per value.
#
# THE BYTE ORDER IS A CONSEQUENCE OF THE REVERSAL, so it is stated here: the
# byte list is built by PREPENDING, so it comes out backwards and is reversed
# ONCE at the end -- and a whole-list reversal also reverses the four bytes
# INSIDE each value, so each value's bytes are prepended in reverse order
# (b3,b2,b1,b0) and the reversal puts them back little-endian.
# ===========================================================================
def b4(b0: U32, b1: U32, b2: U32, b3: U32, acc: List<&2, U32>) -> List<&2, U32>:
  b3 <> (b2 <> (b1 <> (b0 <> acc)))

def fbytes(f: F32, acc: List<&2, U32>) -> List<&2, U32>:
  +b : U32 = F32.bits(f)
  b4(U32.mod(b, 256),
     U32.div(U32.mod(b, 65536), 256),
     U32.div(U32.mod(b, 16777216), 65536),
     U32.div(b, 16777216), acc)

def stage_bytes(n: Nat, +xs: List<&2, F32>, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p:
      match xs:
        case Nil{}: acc
        case h <> t: stage_bytes(p, t, fbytes(h, acc))

# ONE STAGE'S BYTES, IN ORDER.
def bytes_of(xs: List<&2, F32>, n: Nat) -> List<&2, U32>:
  List.reverse(&2, U32, stage_bytes(n, xs, Nil{}))

# ---- io -------------------------------------------------------------------
def open_file(path: String) -> IO(File):
  do IO<File>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    f : File <- IO.pass(File, r)
    IO.pure(File, f)

def read_all(f: File, n: U32) -> IO(List<&2, U32>):
  do IO<List<&2, U32>>:
    m : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, n)
    bs : List<&2, U32> <- IO.pass(List<&2, U32>, Pair.snd(File, Result<&1, &1, U32 & String, List<&2, U32>>, m))
    IO.pure(List<&2, U32>, bs)

def read_bytes(path: String, n: U32) -> IO(List<&2, U32>):
  do IO<List<&2, U32>>:
    f : File <- open_file(path)
    bs : List<&2, U32> <- read_all(f, n)
    IO.pure(List<&2, U32>, bs)

def close_then.go(f: File, r: Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    c : Unit <- File.close(f)
    IO.pure(Result<&1, &1, U32 & String, Unit>, r)

def close_then(p: File & Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, U32 & String, Unit>):
  match p:
    case (f, r): close_then.go(f, r)

# THE FILE IS WRITTEN IN EIGHT APPENDS, ONE PER STAGE, AND NOT IN ONE LIST.
# MEASURED: concatenating the eight stages with `List.append` overflows the
# JavaScript lane's machine stack -- `List.append` recurses once per element of
# its FIRST argument, so the last append recurses 43 904 deep -- and the
# native lane survives it only because a C frame is small.  Eight appends are
# also the shorter program: no `cat`, no `eight`, and the file is written in
# the order the stages are produced.
def write_bytes(path: String, mode: String, data: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, mode)
    f : File <- IO.pass(File, r)
    m : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, data)
    cr : Result<&1, &1, U32 & String, Unit> <- close_then(m)
    u : Unit <- IO.pass(Unit, cr)
    IO.pure(Unit, u)

# ---- bytes -> floats ------------------------------------------------------
# float32 little-endian: four bytes at a time.  The fold PREPENDS, so the
# caller reverses once.
def to_floats(bs: List<&2, U32>, acc: List<&2, F32>) -> List<&2, F32>:
  match bs:
    case Nil{}: acc
    case b0 <> t1:
      match t1:
        case Nil{}: acc
        case b1 <> t2:
          match t2:
            case Nil{}: acc
            case b2 <> t3:
              match t3:
                case Nil{}: acc
                case b3 <> t4:
                  +bits : U32 = U32.or(U32.or(U32.or(b0, U32.shln(b1, 8n)), U32.shln(b2, 16n)), U32.shln(b3, 24n))
                  to_floats(t4, F.F32.from_bits(bits) <> acc)

# uint8 pixels -> float32 in [0,1]: the STANDARD MNIST normalisation
def to_units(bs: List<&2, U32>, acc: List<&2, F32>) -> List<&2, F32>:
  match bs:
    case Nil{}: acc
    case b <> t: to_units(t, F32.div(F32.from_nat(U32.to_nat(b)), 255.0) <> acc)

# ---- the entry point ------------------------------------------------------
def WS() -> String: ".agents/slop/seams/weights.f32"
def IS() -> String: ".agents/slop/seams/img0.u8"
def OS() -> String: ".agents/slop/seams/port_stages.f32"

# THE LOGITS, AS DECIMALS.
def show_logits(n: Nat, +xs: List<&2, F32>, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+p:
      match xs:
        case Nil{}: acc
        case h <> t: show_logits(p, t, String.concat([acc, " ", F32.show(h)]))

# THE STAGE CLOCK.  `IO.now()` is the runtime's own clock -- milliseconds in
# both lanes (`performance.now()` in JavaScript, `io_tick()/1000000` in C) --
# so the port measures ITSELF and the numbers in the report are the port's.
def main() -> IO(Unit):
  do IO<Unit>:
    +t0 : Nat <- IO.now()
    +wb : List<&2, U32> <- read_bytes(WS(), 17064)
    +ib : List<&2, U32> <- read_bytes(IS(), 784)
    +w : List<&2, F32> = List.reverse(&2, F32, to_floats(wb, Nil{}))
    +im : List<&2, F32> = List.reverse(&2, F32, to_units(ib, Nil{}))
    +t1 : Nat <- IO.now()
    +c1 : List<&2, F32> = conv1(w, im)
    +t2 : Nat <- IO.now()
    +r1 : List<&2, F32> = relu(3136n, c1)
    +t3 : Nat <- IO.now()
    +p1 : List<&2, F32> = pool1(784n, r1)
    +t4 : Nat <- IO.now()
    +c2 : List<&2, F32> = conv2(w, p1)
    +t5 : Nat <- IO.now()
    +r2 : List<&2, F32> = relu(1568n, c2)
    +t6 : Nat <- IO.now()
    +p2 : List<&2, F32> = pool2(392n, r2)
    +t7 : Nat <- IO.now()
    +lg : List<&2, F32> = fc(w, p2)
    +t8 : Nat <- IO.now()
    +s : String = show_logits(10n, lg, "")
    +o1 : Unit <- write_bytes(OS(), "w", bytes_of(c1, 3136n))
    +o2 : Unit <- write_bytes(OS(), "a", bytes_of(r1, 3136n))
    +o3 : Unit <- write_bytes(OS(), "a", bytes_of(p1, 784n))
    +o4 : Unit <- write_bytes(OS(), "a", bytes_of(c2, 1568n))
    +o5 : Unit <- write_bytes(OS(), "a", bytes_of(r2, 1568n))
    +o6 : Unit <- write_bytes(OS(), "a", bytes_of(p2, 392n))
    +o7 : Unit <- write_bytes(OS(), "a", bytes_of(p2, 392n))
    +o8 : Unit <- write_bytes(OS(), "a", bytes_of(lg, 10n))
    +t9 : Nat <- IO.now()
    IO.print(String.concat(["stage_ms read ", Nat.show(Nat.sub(t1, t0))]))
    IO.print(String.concat(["stage_ms conv1 ", Nat.show(Nat.sub(t2, t1))]))
    IO.print(String.concat(["stage_ms relu1 ", Nat.show(Nat.sub(t3, t2))]))
    IO.print(String.concat(["stage_ms pool1 ", Nat.show(Nat.sub(t4, t3))]))
    IO.print(String.concat(["stage_ms conv2 ", Nat.show(Nat.sub(t5, t4))]))
    IO.print(String.concat(["stage_ms relu2 ", Nat.show(Nat.sub(t6, t5))]))
    IO.print(String.concat(["stage_ms pool2 ", Nat.show(Nat.sub(t7, t6))]))
    IO.print(String.concat(["stage_ms fc ", Nat.show(Nat.sub(t8, t7))]))
    IO.print(String.concat(["stage_ms write ", Nat.show(Nat.sub(t9, t8))]))
    IO.print(String.concat(["logits", s]))
    IO.print(String.concat(["stages conv1 3136 relu1 3136 pool1 784 conv2 1568 relu2 1568 pool2 392 flat 392 logits 10"]))
