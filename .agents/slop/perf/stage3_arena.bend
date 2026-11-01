# stage3_arena.bend -- THE PORT'S ARENA SHAPE AGAINST AN IN-PLACE ARRAY, ONE NUMBER EACH.
#
#     ./bin/bend .agents/slop/perf/stage3_arena.bend --check-only
#     ./bin/bend .agents/slop/perf/stage3_arena.bend -o /tmp/arena && /usr/bin/time /tmp/arena list
#     /usr/bin/time /tmp/arena array
#
# `ops_python.bend`'s `Val.put` is `List.set(spine, i/16, List.set(chunk, i%16, e))`: a write
# REBUILDS the chunk and the spine, which is 16 + i/16 heap cells per store, and this tree already
# counted 96 584 987 such allocations in one 32x32 launch (REPORT.md 12.4). `Array.set` is Bend's
# in-place write: `Array<T>` is a `Type` with one owner, so the update happens in the slot and
# allocates NOTHING.
#
# This measures the two on the same 512-slot arena and the same 200 000 writes. It is a MODEL of
# the port's store, not the port -- the point is the factor, which decides whether rewriting the
# arena is worth a session.
import Base

type E is Data:
  E{b: U32}

def ch_at(+cs: List<&2, List<&2, E>>, +ci: U32) -> List<&2, E>:
  Maybe.default(&2, List<&2, E>, List.get(&2, List<&2, E>, cs, U32.to_nat(ci)), Nil{})

# `Val.put` verbatim: a 16-slot chunk and a chunk spine, both rebuilt
def put_l(+cs: List<&2, List<&2, E>>, +i: U32, +e: E) -> List<&2, List<&2, E>>:
  +ci = U32.shrn(i, 4n)
  List.set(&2, List<&2, E>, cs, U32.to_nat(ci),
    List.set(&2, E, ch_at(cs, ci), U32.to_nat(U32.and(i, 15)), e))

def E.b(e: E) -> U32:
  match e:
    case E{b}: b

def arr_fin(r: Array<E> & E) -> U32:
  match r:
    case (a, e): E.b(e)

def val_at.go(m: Maybe<&2, E>) -> U32:
  match m:
    case Some{e}: E.b(e)
    case None{}: 0

def val_at(+cs: List<&2, List<&2, E>>, +i: U32) -> U32:
  val_at.go(List.get(&2, E, ch_at(cs, U32.shrn(i, 4n)), U32.to_nat(U32.and(i, 15))))

def loop_l(f: Nat, cs: List<&2, List<&2, E>>, +i: U32, +acc: U32) -> U32:
  match f:
    case 0n: U32.add(acc, val_at(cs, U32.mod(i, 512)))
    case 1n+g: loop_l(g, put_l(cs, U32.mod(i, 512), E{U32.mul(i, 3)}), U32.add(i, 1), U32.add(acc, 1))

def loop_a(f: Nat, a: Array<E>, +i: U32, +acc: U32) -> U32:
  match f:
    case 0n: arr_fin(Array.get(E, a, U32.mod(i, 512)))
    case 1n+g: loop_a(g, Array.set(E, a, U32.mod(i, 512), E{U32.mul(i, 3)}), U32.add(i, 1), U32.add(acc, 1))


def list_mode() -> U32:
  # EACH CHUNK MUST BE FULL LENGTH, or `List.set` on a short list is a NO-OP and the benchmark
  # measures nothing (MEASURED: the first version wrote into Nil chunks, read back 0 and "ran" in
  # 200 ns per write because it never wrote).
  +empty = List.replicate(List<&2, E>, 32n, List.replicate(E, 16n, E{0}))
  loop_l(2000000n, empty, 0, 0)

def array_mode() -> U32: loop_a(2000000n, Array.new(E, 9n, E{0}), 0, 0)

def nth(xs: List<&1, String>, +k: Nat) -> String:
  Maybe.default(&1, String, List.get(&1, String, xs, k), "list")

def mode_of(is_array: Bool) -> U32:
  match is_array:
    case True{}: array_mode()
    case False{}: list_mode()

# `match` cannot scrutinise a String, so the mode arrives as the Bool `String.eq` produces
def pick_mode(+nm: String) -> U32: mode_of(String.eq(nm, "array"))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    nm : String = nth(args, 1n)
    IO.print(U32.show(pick_mode(nm)))
