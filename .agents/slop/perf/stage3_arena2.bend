# stage3_arena2.bend -- THE ARENA PRIMITIVE, IN THE SHAPE THE INTERPRETER USES IT.
#
#     ./bin/bend .agents/slop/perf/stage3_arena2.bend -o /tmp/arena2
#     /usr/bin/time -p /tmp/arena2 list        # the port's shape today
#     /usr/bin/time -p /tmp/arena2 cache       # + the held chunk
#     /usr/bin/time -p /tmp/arena2 array       # Array<Elem> in a linear record
#
# Every mode runs the same 200 000 interpreter STEPS, and a step is what the executor does for one
# ALU uop: three arena reads and one arena write on a 512-slot arena. The values are consumed, so
# nothing can be optimised away, and each mode prints the same checksum -- a mode that answers a
# different number is not being compared.
#
# THIS IS THE NUMBER THE REFACTOR HAS TO CLEAR. REPORT.md 38 estimated ~1.35x from the Array by
# counting allocations; this measures it.
import Base

type E is Data:
  E{b: U32}

def E.b(e: E) -> U32:
  match e:
    case E{b}: b

def i_of(+k: U32) -> U32: U32.mod(k, 512)

# ---------------- the port's shape: chunked spine, no held chunk ------------------------------
def ch_at(+cs: List<&2, List<&2, E>>, +ci: U32) -> List<&2, E>:
  Maybe.default(&2, List<&2, E>, List.get(&2, List<&2, E>, cs, U32.to_nat(ci)), Nil{})

def L.at(+cs: List<&2, List<&2, E>>, +i: U32) -> E:
  Maybe.default(&2, E, List.get(&2, E, ch_at(cs, U32.shrn(i, 4n)), U32.to_nat(U32.and(i, 15))),
    E{0})

def L.put(+cs: List<&2, List<&2, E>>, +i: U32, +e: E) -> List<&2, List<&2, E>>:
  List.set(&2, List<&2, E>, cs, U32.to_nat(U32.shrn(i, 4n)),
    List.set(&2, E, ch_at(cs, U32.shrn(i, 4n)), U32.to_nat(U32.and(i, 15)), e))

# ---------------- the held chunk (what the port does now) -------------------------------------
type C is Data:
  C{sp: List<&2, List<&2, E>>, vc: List<&2, E>, vi: U32}

def C.sent() -> U32: 4294967295

def C.sp(c: C) -> List<&2, List<&2, E>>:
  match c:
    case C{sp, vc, vi}: sp

def C.vc(c: C) -> List<&2, E>:
  match c:
    case C{sp, vc, vi}: vc

def C.vi(c: C) -> U32:
  match c:
    case C{sp, vc, vi}: vi

def C.at.hit(hit: Bool, +c: C, +i: U32) -> E:
  match hit:
    case True{}: Maybe.default(&2, E, List.get(&2, E, C.vc(c), U32.to_nat(U32.and(i, 15))), E{0})
    case False{}: L.at(C.sp(c), i)

def C.at(+c: C, +i: U32) -> E: C.at.hit(U32.is_eq(U32.shrn(i, 4n), C.vi(c)), c, i)

def C.flush.go(none: Bool, +c: C) -> List<&2, List<&2, E>>:
  match none:
    case True{}: C.sp(c)
    case False{}: List.set(&2, List<&2, E>, C.sp(c), U32.to_nat(C.vi(c)), C.vc(c))

def C.flush(+c: C) -> List<&2, List<&2, E>>:
  C.flush.go(U32.is_eq(C.vi(c), C.sent()), c)

def C.put.hit(+c: C, +i: U32, +e: E) -> C:
  C{C.sp(c), List.set(&2, E, C.vc(c), U32.to_nat(U32.and(i, 15)), e), C.vi(c)}

def C.put.miss.x(+sp: List<&2, List<&2, E>>, +ci: U32, +co: U32, +e: E) -> C:
  C{sp, List.set(&2, E, ch_at(sp, ci), U32.to_nat(co), e), ci}

def C.put.miss(+c: C, +i: U32, +e: E) -> C:
  C.put.miss.x(C.flush(c), U32.shrn(i, 4n), U32.and(i, 15), e)

def C.put.go(hit: Bool, +c: C, +i: U32, +e: E) -> C:
  match hit:
    case True{}: C.put.hit(c, i, e)
    case False{}: C.put.miss(c, i, e)

def C.put(+c: C, +i: U32, +e: E) -> C:
  C.put.go(U32.is_eq(U32.shrn(i, 4n), C.vi(c)), c, i, e)

# ---------------- Array<Elem> in a linear record ---------------------------------------------
type R is Type:
  R{a: Array<E>, n: U32}

def R.put(r: R, +i: U32, +e: E) -> R:
  match r:
    case R{a, n}: R{Array.set(E, a, i, e), n}

def R.get.k(x: Array<E> & E, +n: U32) -> R & E:
  match x:
    case (a, e): (R{a, n}, e)

def R.get(r: R, +i: U32) -> R & E:
  match r:
    case R{a, n}: R.get.k(Array.get(E, a, i), n)

def R.acc(x: R & E) -> U32:
  match x:
    case (r, e): E.b(e)

def R.step.d(x: R & E, +k: U32, +a: E, +b: E) -> R:
  match x:
    case (r, c): R.put(r, i_of(k), E{U32.add(E.b(a), U32.add(E.b(b), E.b(c)))})

def R.step.c(x: R & E, +k: U32, +a: E) -> R:
  match x:
    case (r, b): R.step.d(R.get(r, i_of(U32.add(k, 2))), k, a, b)

def R.step.b(x: R & E, +k: U32) -> R:
  match x:
    case (r, a): R.step.c(R.get(r, i_of(U32.add(k, 1))), k, a)

def R.step(r: R, +k: U32) -> R:
  R.step.b(R.get(r, i_of(k)), k)

def arr_loop(f: Nat, r: R, +k: U32, +acc: U32) -> U32:
  match f:
    case 0n: U32.add(acc, R.acc(R.get(r, 0)))
    case 1n+g: arr_loop(g, R.step(r, k), U32.add(k, 4), U32.add(acc, 1))

# ---------------- the incremental modes -------------------------------------------------------
def list_loop(f: Nat, +cs: List<&2, List<&2, E>>, +k: U32, +acc: U32) -> U32:
  match f:
    case 0n: U32.add(acc, E.b(L.at(cs, 0)))
    case 1n+g:
      +a = L.at(cs, i_of(k))
      +b = L.at(cs, i_of(U32.add(k, 1)))
      +c = L.at(cs, i_of(U32.add(k, 2)))
      list_loop(g, L.put(cs, i_of(k), E{U32.add(E.b(a), U32.add(E.b(b), E.b(c)))}),
        U32.add(k, 4), U32.add(acc, 1))

def cache_loop(f: Nat, +c: C, +k: U32, +acc: U32) -> U32:
  match f:
    case 0n: U32.add(acc, E.b(C.at(c, 0)))
    case 1n+g:
      +a = C.at(c, i_of(k))
      +b = C.at(c, i_of(U32.add(k, 1)))
      +cc = C.at(c, i_of(U32.add(k, 2)))
      cache_loop(g, C.put(c, i_of(k), E{U32.add(E.b(a), U32.add(E.b(b), E.b(cc)))}),
        U32.add(k, 4), U32.add(acc, 1))

def blank() -> List<&2, List<&2, E>>:
  List.replicate(List<&2, E>, 32n, List.replicate(E, 16n, E{0}))

def mode_list() -> U32: list_loop(2000000n, blank(), 0, 0)
def mode_cache() -> U32: cache_loop(2000000n, C{blank(), Nil{}, C.sent()}, 0, 0)
def mode_array() -> U32: arr_loop(2000000n, R{Array.new(E, 9n, E{0}), 0}, 0, 0)

def mode_of2(which: Bool) -> U32:
  match which:
    case True{}: mode_cache()
    case False{}: mode_array()

def mode_of(which: Bool, which2: Bool) -> U32:
  match which:
    case True{}: mode_list()
    case False{}: mode_of2(which2)

def nth(xs: List<&1, String>, +k: Nat) -> String:
  Maybe.default(&1, String, List.get(&1, String, xs, k), "list")

def pick(+nm: String) -> U32: mode_of(String.eq(nm, "list"), String.eq(nm, "cache"))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    nm : String = nth(args, 1n)
    IO.print(U32.show(pick(nm)))
