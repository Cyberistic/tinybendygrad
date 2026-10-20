# scratch probe -- DELETE.
#
# SUBSTRATE RULES, all MEASURED here:
#   * a `List` PARAMETER is AFFINE -- "consumed more than once".
#   * `r = expr` inside a `do` block is not a pattern; the bind is `r : T <- eff`.
#   * recursive args are read LEFT TO RIGHT and the call must be DECREASING, so the
#     fuel `n` must LEAD, and a two-column `match ms n:` is REFUSED outright.
#   * a LIST carries its depth: `List<&1, U32>` is not `List<&2, U32>`, and
#     `List.append(&2, U32, Nil{}, bs)` does not convert one -- the error names
#     `bs` as still `&1`. The conversion is a FOLD, which is exactly why
#     `ops_python.bend` has `Prog.chars1`/`Prog.bytes1` for the same hop.
import ../helpers.bend as H
import ./ops_python.bend as OP

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def urow(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

# the &1 -> &2 hop, one fold. This is `Prog.bytes1` verbatim in shape.
def up(bs: List<&1, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match bs:
    case Nil{}: List.reverse(&2, U32, acc)
    case h <> t: up(t, List.append(&2, U32, acc, [h]))

def scan(+work: List<&2, U32>, +nbytes: U32, +b0: U32, +ld: U32) -> IO(Unit):
  match work:
    case Nil{}:
      do IO<Unit>:
        urow("p_nbytes", nbytes)
        urow("p_byte0", b0)
        urow("p_ld4", ld)
    case h <> t:
      scan(t, U32.add(nbytes, 1), h,
        Bool.pick(U32, U32.is_eq(nbytes, 0), OP.Mem.ld4(List.append(&2, U32, Nil{}, [h]), 0), ld))

def do_scan(bs: List<U32>) -> IO(Unit): scan(up(bs, Nil{}), 0, 0, 0)

def say_ok(ok: Bool) -> IO(Unit): srow("p_bytesok", Bool.show(ok))

# `(ok, bytes) = r` DESTRUCTURES ONCE -- the pair is affine, so reading it twice
# is "consumed more than once". This is `ops_python.bend`'s `bytes_ok`/`list_of`
# pair, and here they are one def instead of two.
def go(bs: (Bool & List<U32>)) -> IO(Unit):
  (ok, bytes) = bs
  do IO<Unit>:
    say_ok(ok)
    do_scan(bytes)

# `bytes_of` wants a `List<&1, Char>` and `String.to_list` answers `&2`, so the
# hop is `OP.Prog.chars1` -- `ops_python.bend`'s own def for exactly this, reused
# rather than rewritten. THAT is what "one .bend per upstream .py" buys.
def shim(s: String) -> List<&1, Char>: OP.Prog.chars1(String.to_list(s), Nil{})

def main() -> IO(Unit):
  do IO<Unit>:
    srow("p_hex2_64", OP.hex_str2(64))
    urow("p_hexdig0", OP.hexdig_val(48))
    srow("p_hxstr_4", OP.hexdig_str(4))
    srow("p_hxstr_15", OP.hexdig_str(15))
    bs : (Bool & List<U32>) <- IO.pure(Bool & List<U32>, OP.bytes_of(shim("efbeadde")))
    go(bs)