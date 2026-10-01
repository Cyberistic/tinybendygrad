# core.bend -- the export subject of the four-lane matrix.
#
# ONE pure f32 program: a fixed-shape two-layer forward step finishing in
# softmax + cross-entropy.  Every lane under langs/ is this file, compiled by
# Bend to C, to wasm and to JS; the lanes differ only in what hosts it.
#
# Shape, fixed at compile time:  IN=4  HID=3  CLS=3  BATCH=2
#
#   weights : 27 f32 in 32 slots, read-only, row-major, each row's last
#             column being its bias, so a bias costs no separate arithmetic:
#       [ 0..14]  W1, HID rows of width IN+1 = 5   (4 products, then the bias)
#       [15..26]  W2, CLS rows of width HID+1 = 4  (3 products, then the bias)
#   images  :  8 f32, BATCH rows of width IN.
#   labels  :  2 u32, one class index per sample.
#
# Three things about Bend 2.0.34 shape this file, and langs/NOTES.md has the
# reproducers.  Array.get -- the documented array reader -- cannot be called
# on a def parameter, so an array becomes a list.  A def may not destructure
# the result of a call, so everything that has to travel travels in a cons
# and is read back by index.  And a case arm may not hold a call under a Nat
# fuel pattern, so every walk is list-fueled.
#
# Every gated number is reported as raw f32 bits and every input crosses as
# bits rather than as a decimal, so no lane can agree by rounding and none can
# hide a disagreement behind a printed float.

import Base

# --- reading an f32 out of a u32 field --------------------------------------
# A U32 and an F32 are both 32 bits of Word, so this is a reinterpretation,
# not a conversion: the same 32 bits in every lane, by construction.

def f32_of_bits(b: U32) -> F32:
  match b:
    case U32{+w}:
      F32{w}

# --- the payload, as decimal u32 bit patterns -------------------------------
# Argument 1 is one comma separated string: the first 8 fields are images,
# the next 2 are labels, the last 32 are weights.

def parse.maybe(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{b}:
      b
    case None{}:
      0

def parse(s: String) -> U32:
  parse.maybe(U32.read(s))

def payload(args: List<String>) -> List<&2, String>:
  match args:
    case Nil{}:
      []
    case Con{_, Con{p, _}}:
      String.split(p, ',')
    case Con{_, Nil{}}:
      []

def skip(n: Nat, xs: List<&2, String>) -> List<&2, String>:
  match n xs:
    case 0n Nil{}:
      xs
    case 0n Con{h, t}:
      xs
    case 1n+p Nil{}:
      xs
    case 1n+p Con{h, t}:
      skip(p, t)

# put: copy the first ns-many fields of xs into a, walking xs.  A short payload
# leaves the zeros Array.new wrote; a long one is truncated at ns, because the
# shape is fixed and an extra field is a payload bug, not a shape to honour.

def skip_f(n: Nat, xs: List<&2, F32>) -> List<&2, F32>:
  match n xs:
    case 0n Nil{}:
      xs
    case 0n Con{h, t}:
      xs
    case 1n+p Nil{}:
      xs
    case 1n+p Con{h, t}:
      skip_f(p, t)

def put(ns: List<&2, Nat>, xs: List<&2, String>, a: Array<F32>, +i: U32)
  -> Array<F32>:
  match ns xs:
    case Nil{} Nil{}:
      a
    case Nil{} Con{h, t}:
      a
    case Con{n, ns2} Nil{}:
      a
    case Con{n, ns2} Con{h, t}:
      put(ns2, t, Array.set(F32, a, i, f32_of_bits(parse(h))), U32.inc(i))

def put_u(ns: List<&2, Nat>, xs: List<&2, String>, a: Array<U32>, +i: U32)
  -> Array<U32>:
  match ns xs:
    case Nil{} Nil{}:
      a
    case Nil{} Con{h, t}:
      a
    case Con{n, ns2} Nil{}:
      a
    case Con{n, ns2} Con{h, t}:
      put_u(ns2, t, Array.set(U32, a, i, parse(h)), U32.inc(i))

def imgs_of(+fs: List<&2, String>) -> Array<F32>:
  put(List.replicate(Nat, 8n, 0n), skip(0n, fs), Array.new(F32, 3n, 0.0), 0)

def labs_of(+fs: List<&2, String>) -> Array<U32>:
  put_u(List.replicate(Nat, 2n, 0n), skip(8n, fs), Array.new(U32, 1n, 0), 0)

def ws_of(+fs: List<&2, String>) -> Array<F32>:
  put(List.replicate(Nat, 32n, 0n), skip(10n, fs), Array.new(F32, 5n, 0.0), 0)

# --- arrays in, reusable lists out ------------------------------------------
# share copies the spine, so the result may be walked as often as the kernel
# needs; Array.to_list alone answers List<&1, F32>, which is single use.

def share_f(xs: List<F32>) -> List<&2, F32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Con{h, share_f(t)}

def share_u(xs: List<U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Con{h, share_u(t)}

# --- list walks --------------------------------------------------------------

def at_f(k: Nat, xs: List<&2, F32>) -> F32:
  match k xs:
    case 0n Nil{}:
      0.0
    case 0n Con{h, t}:
      h
    case 1n+p Nil{}:
      0.0
    case 1n+p Con{h, t}:
      at_f(p, t)

def at_u(k: Nat, xs: List<&2, U32>) -> U32:
  match k xs:
    case 0n Nil{}:
      0
    case 0n Con{h, t}:
      h
    case 1n+p Nil{}:
      0
    case 1n+p Con{h, t}:
      at_u(p, t)

def exp_sum(z: List<&2, F32>) -> F32:
  match z:
    case Nil{}:
      0.0
    case Con{v, t}:
      F32.add(F32.exp(v), exp_sum(t))

def show_f(xs: List<&2, F32>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, t}:
      U32.show(F32.bits(h)) ++ "," ++ show_f(t)

def show_u(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, t}:
      U32.show(h) ++ "," ++ show_u(t)

def bits_at(k: Nat, +xs: List<&2, F32>) -> String:
  "," ++ U32.show(F32.bits(at_f(k, xs)))

# --- the kernel --------------------------------------------------------------
# The shape is fixed, so the weights are cut into rows ONCE and every walk
# below is a plain recursion whose own list is its fuel.

# marks: n products and then the bias, as the per-element marks split reads.
# A Nat PARAMETER is not a literal pattern -- `case Con{n, ct}` matches any c
# -- so the row width travels in the list, where 0n and 1n are real literals.

def marks(n: Nat) -> List<&2, Nat>:
  List.append(&2, Nat, List.replicate(Nat, n, 1n), List.replicate(Nat, 1n, 0n))

# split: cut w into rows at every 0n mark.  marks is the fuel, so every arm
# may hold a call.  A row is consed as it fills and the rows are consed as
# they finish, so both come out backwards and rows turns each one round.

def split(marks: List<&2, Nat>, w: List<&2, F32>, +cur: List<&2, F32>,
          out: List<&2, List<&2, F32>>) -> List<&2, List<&2, F32>>:
  match marks w:
    case Nil{} Nil{}:
      out
    case Nil{} Con{h, t}:
      out
    case Con{c, md} Nil{}:
      out
    case Con{0n, md} Con{h, t}:
      split(md, t, Nil{}, Con{List.reverse(&2, F32, Con{h, cur}), out})
    case Con{1n+p, md} Con{h, t}:
      split(md, t, Con{h, cur}, out)

# cs5 and cs4: W1 is three rows of width IN+1 = 5, W2 three of width HID+1 = 4.

def cs5() -> List<&2, Nat>:
  List.append(&2, Nat, List.append(&2, Nat, marks(4n), marks(4n)), marks(4n))

def cs4() -> List<&2, Nat>:
  List.append(&2, Nat, List.append(&2, Nat, marks(3n), marks(3n)), marks(3n))

# dot: sum of r[i] * x[i].  r is one element wider than x, and that extra last
# element IS the bias: the walk runs out of x first, so the one weight left is
# added straight instead of multiplied.  A bias therefore costs no arithmetic
# and no scratch column of its own.

def dot(r: List<&2, F32>, +xs: List<&2, F32>) -> F32:
  match r xs:
    case Nil{} Nil{}:
      0.0
    case Nil{} Con{b, u}:
      0.0
    case Con{a, t} Nil{}:
      F32.add(dot(t, xs), a)
    case Con{a, t} Con{b, u}:
      F32.add(F32.mul(a, b), dot(t, u))

# rows: one output per weight row, each that row's bias-plus-dot.  split hands
# the rows over back to front, so consing each dot here turns them the right
# way round again -- and x is never advanced, because every row dots the whole
# of it.

def rows(rs: List<&2, List<&2, F32>>, +x: List<&2, F32>, out: List<&2, F32>)
  -> List<&2, F32>:
  match rs:
    case Nil{}:
      out
    case Con{r, rt}:
      rows(rt, x, Con{dot(r, x), out})

# cross_entropy: log(sum exp z) - exp z[label].  log and exp are each evaluated
# once, and z is walked twice rather than indexed.

def cross_entropy(+z: List<&2, F32>, +ls: List<&2, U32>, k: Nat) -> F32:
  F32.sub(F32.log(exp_sum(z)),
    F32.exp(at_f(U32.to_nat(at_u(k, ls)), z)))

# sample: one forward step.  W1 turns the sample's image row into h, W2 turns h
# into the logits.  It answers ONE list, [ce, h0, h1, h2, z0, z1, z2], because
# a def may not destructure the result of a call.

def sample(row: List<&2, F32>, ls: List<&2, U32>, +ws: List<&2, F32>, li: Nat)
  -> List<&2, F32>:
  +h = rows(split(cs5(), ws, Nil{}, Nil{}), row, Nil{})
  +z = rows(split(cs4(), skip_f(15n, ws), Nil{}, Nil{}), h, Nil{})
  Con{cross_entropy(z, ls, li), List.append(&2, F32, h, z)}

# batch: one sample per IN fields of the image list, losses summed.  The image
# list is the fuel, not a Nat counter: a `case 1n+pn:` arm cannot hold a call
# in 2.0.34, and this arm calls sample.

def done(acc: F32, r: List<&2, F32>) -> List<&2, F32>:
  F32.div(acc, 2.0) <> r

# batch: one sample per IN fields of the image list, losses summed.  The image
# list is the fuel -- a `case 1n+pn:` arm cannot hold a call in 2.0.34, and
# this one calls sample -- and it is peeled one level per match, because a
# nested pattern must be exhaustive at every level it names.

def batch(xs: List<&2, F32>, +li: Nat, ls: List<&2, U32>, +ws: List<&2, F32>,
          r: List<&2, F32>, acc: F32) -> List<&2, F32>:
  match xs:
    case Nil{}:
      done(acc, r)
    case Con{a, xs2}:
      match xs2:
        case Nil{}:
          done(acc, r)
        case Con{b, xs3}:
          match xs3:
            case Nil{}:
              done(acc, r)
            case Con{c, xs4}:
              match xs4:
                case Nil{}:
                  done(acc, r)
                case Con{d, xs5}:
                  match ls:
                    case Nil{}:
                      done(acc, r)
                    case Con{_, +lt}:
                      +s = sample(Con{a, Con{b, Con{c, Con{d, Nil{}}}}}, ls,
                        ws, li)
                      batch(xs5, Nat.add(li, 1n), lt, ws, s,
                        F32.add(acc, at_f(0n, s)))

# --- the exported surface ---------------------------------------------------
# core_trace answers [loss, ce, h0, h1, h2, z0, z1, z2] -- the mean
# cross-entropy over the batch, then the last sample's own numbers, which is
# what the harness reports.  core_step is the same step reading back only the
# loss: THE surface the SDK and the mnist example import.

def core_trace(images: Array<F32>, labels: Array<U32>, weights: Array<F32>)
  -> List<&2, F32>:
  batch(share_f(Array.to_list(F32, images)), 0n,
    share_u(Array.to_list(U32, labels)), share_f(Array.to_list(F32, weights)),
    Nil{}, 0.0)

def core_step(images: Array<F32>, labels: Array<U32>, weights: Array<F32>)
  -> F32:
  at_f(0n, core_trace(images, labels, weights))

# --- the harness every lane runs ---------------------------------------------
# One line goes out, in a fixed field order, and verify.sh diffs those lines.
# in= echoes the parsed images and labels, so a lane that disagreed about the
# payload says so before the loss rather than hiding inside it.

def run(+fs: List<&2, String>) -> String:
  +r = core_trace(imgs_of(fs), labs_of(fs), ws_of(fs))
  +ic = share_f(Array.to_list(F32, imgs_of(fs)))
  +lc = share_u(Array.to_list(U32, labs_of(fs)))
  +loss = at_f(0n, r)
  "loss=" ++ F32.show(loss)
    ++ " trace=" ++ bits_at(0n, r) ++ bits_at(1n, r) ++ bits_at(2n, r)
    ++ bits_at(3n, r) ++ bits_at(4n, r) ++ bits_at(5n, r) ++ bits_at(6n, r)
    ++ bits_at(7n, r)
    ++ " in=" ++ show_f(ic) ++ show_u(lc)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    IO.print(run(payload(args)))
