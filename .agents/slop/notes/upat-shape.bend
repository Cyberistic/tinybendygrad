import Base

# GATING PROBE 3, minimal. The only question: does a Data record nest a list
# inside a list (UPat.src is `list[tuple[UPat, ...]]`) and read it back?

type Alt is Data:
  Fixed{ys: List<&2, U32>}
  Repeat{x: U32}

type UPat is Data:
  UPat{name: Maybe<&2, String>, src: List<&2, Alt>, is_any: Bool}

type Pat is Data:
  Pat{upats: List<&2, UPat>}

def Pat.upats(pat: Pat) -> List<&2, UPat>:
  match pat:
    case Pat{upats}: upats

def UPat.srcs(u: UPat) -> List<&2, Alt>:
  match u:
    case UPat{_, src, _}: src

def UPat.is_any(u: UPat) -> Bool:
  match u:
    case UPat{_, _, b}: b

def UPat.nm(u: UPat) -> Maybe<&2, String>:
  match u:
    case UPat{n, _, _}: n

# Bend has no `if/else` value form; ops.bend's idiom is a Bool match.
def pick(b: Bool, t: U32, f: U32) -> U32:
  match b:
    case True{}: t
    case False{}: f

# count the alternatives of a pattern
def n_alts(alts: List<&2, Alt>) -> U32:
  match alts:
    case Nil{}: 0
    case _ <> t: U32.add(1, n_alts(t))

# pick the nth UPat out of the arena. `List.get` does the walk, so the counter
# is a `Nat` and only ever decremented once per call.
# a `match` scrutinee must be a PARAMETER, so the Maybe crosses a def boundary.
# a `+` prefix is the SHARE annotation: without it a value may be used once.
def nth.pick(hit: Maybe<&2, UPat>) -> UPat:
  match hit:
    case Some{u}: u
    case None{}: UPat{None{}, Nil{}, False{}}

def nth(us: List<&2, UPat>, n: Nat) -> UPat:
  nth.pick(List.get(&2, UPat, us, n))

def add_pat(ar: Pat, u: UPat) -> Pat:
  Pat{List.append(&2, UPat, Pat.upats(ar), [u])}

# 0: var.  1: cast(var).  2: any-of (cast(var), var) -- 2 alternatives.
def build(ar: Pat) -> Pat:
  a0 = add_pat(ar, UPat{None{}, [Repeat{0}], False{}})
  a1 = add_pat(a0, UPat{None{}, [Fixed{[0]}], False{}})
  add_pat(a1, UPat{None{}, [Fixed{[1, 0]}, Fixed{[0, 1]}], True{}})

# one def, one read: the count and the flag come off a single binder
# ONE read of the pattern: a `match` on the binder is the only way to get two
# facts off an affine value, and it costs one def rather than a tuple return.
def top_facts.of(src: List<&2, Alt>, is_any: Bool) -> U32:
  U32.add(U32.mul(n_alts(src), 10), pick(is_any, 1, 0))

def top_facts(u: UPat) -> U32:
  match u:
    case UPat{_, src, is_any}: top_facts.of(src, is_any)

# `+` on a QUANTIFIED parameter is the share annotation: `&2` alone bounds the
# copies, `+` says this one is deliberately read more than once.
def summarize.of(+us: List<&2, UPat>) -> U32:
  U32.add(U32.mul(U32.from_nat(List.length(&2, UPat, us)), 100),
    top_facts(nth(us, 2n)))

def summarize(pat: Pat) -> U32:
  match pat:
    case Pat{upats}: summarize.of(upats)

def main() -> U32:
  # 3 patterns, top has 2 alternatives, and it is_any
  summarize(build(Pat{[]}))

# one def, one read: the count and the flag come off a single binder