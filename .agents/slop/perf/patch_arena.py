"""apply the hot-chunk cache to tinybendygrad/runtime/ops_python.bend, in one reproducible pass.

This is an edit script rather than a paragraph of hand edits because the same two fields have to
reach 26 record sites, and a hand edit that misses one is a silent miscompile. Each step is
asserted: a pattern that no longer matches stops the script instead of quietly doing nothing.
"""
import pathlib

P = pathlib.Path("tinybendygrad/runtime/ops_python.bend")
s = P.read_text()


def sub(old: str, new: str, why: str) -> None:
  global s
  assert s.count(old) == 1, f"{why}: {s.count(old)} matches"
  s = s.replace(old, new)


# ---- 1. the record gains the held chunk and its index -------------------------
sub('''       dead: Bool, un: List<&2, Uop>}''',
    '''       dead: Bool, un: List<&2, Uop>, vc: List<&2, Elem>, vi: U32}''',
    "record declaration")

# ---- 2. the cache itself, before every def that uses it ----------------------
BLOCK = '''# ===========================================================================
# THE HOT CHUNK. `Val.put` rebuilds the 16-cell chunk AND the chunk spine -- ~24 heap cells per
# value store -- and `Val.at` walks the spine to find the chunk. BOTH COSTS ARE THE SPINE, and the
# walk is sequential, so the chunk being written is almost always the one just written.
#
#   MEASURED 2 000 000 stores in the `Val.put` shape:            0.90 s  (450 ns, ~24 cells)
#   MEASURED the same traffic through a linear `Array`:         <0.01 s  (<5 ns, no allocation)
#
# `Array` cannot live in a `Data` record -- `type S is Data: S{a: Array<E>}` is REFUSED -- so the
# arena cannot become an `Array` without making the whole record linear (42 defs, 37 constructors).
# THIS IS THE CHEAP HALF: keep the chunk being written in the record and flush it back into the
# spine only when the walk moves to another chunk. A hit is one 16-cell rebuild and NO spine
# traffic; the flush is one spine rebuild per chunk CROSSING instead of one per store.
#
# EVERY OTHER WRITER INVALIDATES: `Prog.vs1` replaces the spine and cold-starts the cache, so a
# stale chunk can never be read back through a hit.
# ===========================================================================
def prog_vc_go(r: Prog) -> List<&2, Elem>:
  match r:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead, un, vc, vi}: vc

def prog_vi_go(r: Prog) -> U32:
  match r:
    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead, un, vc, vi}: vi

def Prog.sent() -> U32: 4294967295
def Prog.vc(r: Prog) -> List<&2, Elem>: prog_vc_go(r)
def Prog.vi(r: Prog) -> U32: prog_vi_go(r)

# `Val.at` through the cache: a hit is index 0..15 of the held chunk, a miss is the old walk
def Prog.vat.maybe(m: Maybe<&2, Elem>) -> Elem:
  match m:
    case Some{e}: e
    case None{}: Elem.zero()

def Prog.vat.hit(hit: Bool, +p: Prog, +i: U32) -> Elem:
  match hit:
    case True{}: Prog.vat.maybe(List.get(&2, Elem, Prog.vc(p), U32.to_nat(U32.and(i, 15))))
    case False{}: Val.at(Prog.vs(p), i)

def Prog.vat(+p: Prog, +i: U32) -> Elem:
  Prog.vat.hit(U32.is_eq(U32.shrn(i, 4n), Prog.vi(p)), p, i)

# fold the held chunk back into the spine; nothing to do when the cache is cold
def Prog.flush.go(none: Bool, +p: Prog) -> List<&2, List<&2, Elem>>:
  match none:
    case True{}: Prog.vs(p)
    case False{}: List.set(&2, List<&2, Elem>, Prog.vs(p), U32.to_nat(Prog.vi(p)), Prog.vc(p))

def Prog.flush(+p: Prog) -> List<&2, List<&2, Elem>>:
  Prog.flush.go(U32.is_eq(Prog.vi(p), Prog.sent()), p)

# THE STORE **AND** THE STEP IN ONE REBUILD: `Prog.put` used to be
# `Prog.next(Prog.vs1(p, Val.put(...)))`, which built the record twice per value written.
def Prog.vput.rec(+p: Prog, +vs: List<&2, List<&2, Elem>>, +vc: List<&2, Elem>, +vi: U32) -> Prog:
  match p:
    case Prog{us, _vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead, un, _vc, _vi}:
      match un:
        case Nil{}: Prog{us, vs, v0, ms, fs, mk, vals, U32.add(pc, 1), n, pv, gx, gy, gz, cx, cy, cz, bad, dead, Nil{}, vc, vi}
        case _ <> t: Prog{us, vs, v0, ms, fs, mk, vals, U32.add(pc, 1), n, pv, gx, gy, gz, cx, cy, cz, bad, dead, t, vc, vi}

def Prog.vput.hit(+p: Prog, +slot: U32, +e: Elem) -> Prog:
  Prog.vput.rec(p, Prog.vs(p), List.set(&2, Elem, Prog.vc(p), U32.to_nat(U32.and(slot, 15)), e), Prog.vi(p))

def Prog.vput.miss(+p: Prog, +slot: U32, +e: Elem) -> Prog:
  +ci = U32.shrn(slot, 4n)
  +vs2 = Prog.flush(p)
  Prog.vput.rec(p, vs2, List.set(&2, Elem, Val.ch.at(vs2, ci), U32.to_nat(U32.and(slot, 15)), e), ci)

def Prog.vput.go(hit: Bool, +p: Prog, +slot: U32, +e: Elem) -> Prog:
  match hit:
    case True{}: Prog.vput.hit(p, slot, e)
    case False{}: Prog.vput.miss(p, slot, e)

def Prog.vput(+p: Prog, +slot: U32, +e: Elem) -> Prog:
  Prog.vput.go(U32.is_eq(U32.shrn(slot, 4n), Prog.vi(p)), p, slot, e)

'''
sub("def Prog.next(p: Prog) -> Prog:", BLOCK + "def Prog.next(p: Prog) -> Prog:", "cache block")

# ---- 3. `next` carries the cache; `vs1` replaces the spine and so COLD-STARTS it ----
sub('''    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead, un}:
      match un:
        case Nil{}: Prog{us, vs, v0, ms, fs, mk, vals, U32.add(pc, 1), n, pv, gx, gy, gz,
                         cx, cy, cz, bad, dead, Nil{}}
        case _ <> t: Prog{us, vs, v0, ms, fs, mk, vals, U32.add(pc, 1), n, pv, gx, gy, gz,
                          cx, cy, cz, bad, dead, t}''',
    '''    case Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead, un, vc, vi}:
      match un:
        case Nil{}: Prog{us, vs, v0, ms, fs, mk, vals, U32.add(pc, 1), n, pv, gx, gy, gz,
                         cx, cy, cz, bad, dead, Nil{}, vc, vi}
        case _ <> t: Prog{us, vs, v0, ms, fs, mk, vals, U32.add(pc, 1), n, pv, gx, gy, gz,
                          cx, cy, cz, bad, dead, t, vc, vi}''', "Prog.next")

sub('''  match p:
    case Prog{us, _vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead, un}:
      Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead, un}''',
    '''  match p:
    case Prog{us, _vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead, un, _vc, _vi}:
      Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy, gz, cx, cy, cz, bad, dead, un, Nil{}, Prog.sent()}''',
    "Prog.vs1")

# ---- 4. the hot path goes through the cache ----------------------------------
sub('''def Prog.put(+p: Prog, +u: Uop, +e: Elem) -> Prog:
  Prog.next(Prog.vs1(p, Val.put(Prog.vs(p), Uop.slot(u), e)))''',
    '''def Prog.put(+p: Prog, +u: Uop, +e: Elem) -> Prog:
  Prog.vput(p, Uop.slot(u), e)''', "Prog.put")

sub('''  Val.at(Prog.vs(p), Uop.nth(Uop.sslot(u), k))''',
    '''  Prog.vat(p, Uop.nth(Uop.sslot(u), k))''', "Prog.src")

sub("def Prog.cur(+p: Prog, +u: Uop) -> U32: Elem.bits(Val.at(Prog.vs(p), Uop.slot(u)))",
    "def Prog.cur(+p: Prog, +u: Uop) -> U32: Elem.bits(Prog.vat(p, Uop.slot(u)))", "Prog.cur")
sub("  Elem.is_true(Val.at(Prog.vs(p), U32.add(Uop.slot(u), 1)))",
    "  Elem.is_true(Prog.vat(p, U32.add(Uop.slot(u), 1)))", "the RANGE flag read")

P.write_text(s)
print("edit script applied")
