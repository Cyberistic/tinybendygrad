# scratch probe -- DELETE.
#
# SUBSTRATE RULES, all MEASURED here:
#   * a `List` PARAMETER is AFFINE -- "consumed more than once".
#   * `r = expr` inside a `do` block is not a pattern; the bind is `r : T <- eff`.
#   * recursive args are read LEFT TO RIGHT and the call must be DECREASING: the
#     first argument that shrinks is the fuel, so the destructured tail must be
#     the LEADING argument -- `scan(n, ms, ...)` not `scan(ms, n, ...)`.
import ../helpers.bend as H
import ./ops_python.bend as OP

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def urow(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def scan(n: Nat, ms: List<&2, U32>, +nbytes: U32, +b0: U32, +ld: U32) -> IO(Unit):
  match ms n:
    case Nil{} _:
      do IO<Unit>:
        urow("p_nbytes", nbytes)
        urow("p_byte0", b0)
        urow("p_ld4", ld)
    case h <> t _:
      scan(Nat.sub(n, 1n), t, U32.add(nbytes, 1), h,
        Bool.pick(U32, U32.is_eq(nbytes, 0), OP.Mem.ld4(List.append(&2, U32, Nil{}, [h]), 0), ld))

def do_bytes(r: (Bool & List<U32>)) -> IO(Unit):
  do IO<Unit>:
    srow("p_bytesok", Bool.show(OP.bytes_ok(r)))
    scan(16n, OP.list_of(r), 0, 0, 0)

def main() -> IO(Unit):
  do IO<Unit>:
    srow("p_hex2_64", OP.hex_str2(64))
    urow("p_hexdig0", OP.hexdig_val(48))
    srow("p_hxstr_4", OP.hexdig_str(4))
    srow("p_hxstr_15", OP.hexdig_str(15))
    r : (Bool & List<U32>) <- IO.pure(Bool & List<U32>, OP.bytes_of(String.to_list("efbeadde")))
    do_bytes(r)