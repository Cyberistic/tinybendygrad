# tinybendygrad/runtime/support/amd.bend -- port of tinygrad/runtime/support/amd.py
#
# ===========================================================================
# FORTY-SEVEN LINES, AND THE WHOLE FILE IS PURE. No FFI, no process spawn, no
# environment read -- which makes it the cleanest instrument in this unit:
# everything below is arithmetic and set membership, and every row is a number
# the oracle computed by CALLING the real Python against the real
# `tinygrad.runtime.autogen.am` package.
#
# The four things that are load bearing, in the order they bite:
#
#   1. `AMDReg.__post_init__` SHADOWS ITS OWN FIELD.
#        self.addr = { inst: bases[self.segment] + self.offset
#                      for inst, bases in self.bases.items() }
#      `bases` is the comprehension's LOOP VARIABLE, so the right hand side is
#      `instance_tuple[segment] + offset`, NOT `self.bases[segment] + offset`.
#      It reads as if the field won and it does not. `AMDReg.addr` indexes the
#      INSTANCE tuple; `amd_asic_*.addr_0` is the row, and `addr_ok_1` is the
#      IndexError when `segment` is past the end of that tuple.
#
#   2. `import_module` returns `children[-1]` -- the LAST of `mod.__all__`, in
#      `__all__` ORDER. Not the greatest version, not sorted. So the answer is a
#      property of the autogen module's declaration order, which is WALL 1; what
#      is ported is the FILTER and the `[-1]`. `amd_fake_gc_9_4_3.last` is the
#      row: `gc_9_4_3` is in the fixture, `gc_9_4_2` sorts lower, and the
#      fixture lists `gc_9_4_2` last -- so the answer is `gc_9_4_2`, NOT
#      `gc_9_4_3`, and `amd_fake_gc_9_4_3.sorted_last` is the row that names the
#      difference.
#
#   3. The VERSION OVERRIDE table has two entries and both are keyed on the NAME
#      `smu`, so `("smu", (13, 0, 7))` and `("smu", (13, 0, 10))` both collapse
#      to `(13, 0, 0)`. MEASURED against the real
#      `tinygrad.runtime.autogen.am.regs.__all__`, which contains NO `smu_*` at
#      all, so both override cases raise `ImportError` -- and WITHOUT the
#      override (13, 0, 10) would have selected `smu_13_0_6`. The override
#      changes the answer; the rows are `amd_ovr_*` and `amd_mod_*_13_0_10`.
#
#   4. `import_pmc` formats the gfx key with `{ip[1]:x}` and `{ip[2]:x}` --
#      lowercase hex, NO ZERO PADDING, NO SEPARATOR. So `(9,4,3)` is `gfx943`
#      and `(9,15,255)` is `gfx9fff`, while `(11,0,0)` is `gfx11`.
#      `amd_ip_*.key` is the row set, and a padded or uppercase formatter moves
#      every one of them.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF, with the CPython line it covers. Def names are
# UPSTREAM names: `AMDReg.encode`, `import_module.override`, `import_pmc.key`.
#
#   :5-8   AMDReg             PORTED `AMDReg.addr` `AMDReg.addr_ok` (the shadow)
#   :10    AMDReg.encode      PORTED `AMDReg.encode` -- the `int.__or__` fold
#                                        over `value << fields[name][0]`
#   :11    AMDReg.decode      PORTED `getbits` `AMDReg.decode` -- the join
#                                        ORDER is the field order
#   :13-14 AMDReg.fields_mask PORTED `AMDReg.width` `AMDReg.fields_mask`
#   :17-21 AMDIP              PORTED `import_asic_regs.n` `AMDReg.fields`
#   :23-26 AMDIP.__getattr__  PORTED `AMDIP.name10` `AMDIP.ga` -- the
#                                        `reg` -> `mm` rewrite, which replaces
#                                        EVERY occurrence, and the refusal
#   :31-37 import_module      PORTED `import_module.override` `import_module.vers`
#                                        `import_module.vle` `import_module.kids`
#                                        `import_module.pick_last` `import_module.err`
#   :39    import_soc         PORTED `import_soc.name`
#   :41-44 import_pmc         PORTED `import_pmc.key` `import_pmc.hex2`
#   :46-47 import_asic_regs   PORTED `import_asic_regs.n` `import_asic_regs.first`
#
# ===========================================================================
# THE FOUR WALLS, each with its Python line.
#
# WALL 1 -- the autogen tables. `import_module` reads `mod.__all__`, and for
#   `submod="regs"` each child IS a dict of `{reg: (offset, segment, fields)}`.
#   MEASURED: 28 children, and gc_9_4_3 alone has 1025 registers. bend has no
#   autogen package to read, so `amd_mod_all` carries the DECLARED
#   `regs.__all__` and every filter row is computed from it -- the shape the
#   landed `compiler_amd.bend` uses for its comgr enum constants.
#   TODO(p3) amd.py:34 -- `getattr(tinygrad.runtime.autogen.am, submod)`.
#   TODO(p3) amd.py:36 -- `getattr(mod, children[-1])` over the real `__all__`.
#   TODO(p3) amd.py:47 -- the `{reg: (off, seg, fields)}` tables themselves.
#
# WALL 2 -- the register TABLES, for the same reason. `import_asic_regs`
#   materialises 1025 `AMDReg` objects; the field table of four registers
#   (2, 1 and 14 fields) is transcribed as a literal the gate diffs, which is
#   where a wrong `(start, end)` shows.
#   TODO(p3) amd.py:47 -- `import_module(...).items()` for every child.
#
# WALL 3 -- `functools.cached_property` (`AMDIP.regs`) and `functools.partial`
#   (`cls=functools.partial(AMDReg, bases=self.bases)`). There is no laziness
#   and no keyword-argument partial in bend, so `AMDReg.fields` takes the table
#   as parameters. The `cls` DEFAULT is separately a refusal: `AMDReg` has a
#   REQUIRED `bases` field, so `import_asic_regs(prefix, version)` with the
#   default `cls` raises `TypeError` -- `amd_asic_*.default_cls`.
#   TODO(p3) amd.py:20 -- `@functools.cached_property def regs`.
#   TODO(p3) amd.py:21 -- `functools.partial(AMDReg, bases=self.bases)`.
#
# WALL 4 -- exceptions. bend has none, so every refusal in this file is a
#   TRUNCATED ANSWER: an empty string, a marker number, or a Bool. The case
#   that makes this load bearing is `import_module`: `v[0]` on the EMPTY tuple
#   of a child with no `_` is an IndexError that is NOT caught, so the whole
#   comprehension raises rather than skipping the child -- `amd_fakebad_*`.
#   TODO(p3) amd.py:26 -- `raise AttributeError(...)`.
#   TODO(p3) amd.py:37 -- `raise ImportError(...)`.
import Base

# ===========================================================================
# `helpers.getbits(value, start, end)` is
# `(value >> start) & ((1 << (end - start + 1)) - 1)`.
#
# The width is 32 for a whole register (`content:0-31` in mp_11_0_0), and a
# `U32` cannot compute `1 << 32`: `U32.shln` SATURATES to 0, and `0 - 1` wraps
# to 4294967295 -- the right answer by ACCIDENT. An accidental right answer is
# an answer no mutation can move, so `getbits.mask` takes the width-32 case
# explicitly rather than relying on the wrap.
# ===========================================================================
def getbits.width(end: U32, start: U32) -> U32: U32.add(U32.sub(end, start), 1)

def getbits.mask(+width: U32) -> U32:
  Bool.pick(U32, U32.is_ge(width, 32), 4294967295, U32.sub(U32.shln(1, U32.to_nat(width)), 1))

def getbits(+val: U32, +start: U32, +end: U32) -> U32:
  U32.and(U32.shrn(val, U32.to_nat(start)), getbits.mask(getbits.width(end, start)))

def u32.of.rd(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}: v
    case None{}: 4294967295

# `int()` on a non-numeric element is a ValueError (WALL 4); 4294967295 is the
# marker, and it can never be a version component.
def u32.of(+s: String) -> U32: u32.of.rd(U32.read(s))

def hd(+xs: List<&2, U32>) -> U32: Maybe.default(&2, U32, List.head(&2, U32, xs), 0)

def tl(+xs: List<&2, U32>) -> List<&2, U32>: List.tail(&2, U32, xs)

# ===========================================================================
# `AMDReg.encode(**kwargs)`: `functools.reduce(int.__or__, (value <<
# fields[name][0] for name, value in kwargs.items()), 0)`. The fold is over the
# KWARGUMENT ORDER, which Python preserves, so two OVERLAPPING fields would
# depend on it. `amd_enc_rev` is the row for the reordering and
# `amd_enc_same` for the disjoint-fields case where the order cannot show.
# ===========================================================================
def enc.go(+vals: List<&2, U32>, +starts: List<&2, U32>, +acc: U32) -> U32:
  match vals:
    case Nil{}: acc
    case +v <> vs:
      match starts:
        case Nil{}: acc
        case +s <> ss: enc.go(vs, ss, U32.or(acc, U32.shln(v, U32.to_nat(s))))

def AMDReg.encode(+vals: List<&2, U32>, +starts: List<&2, U32>) -> U32: enc.go(vals, starts, 0)

# ===========================================================================
# `AMDReg.decode(val)`: `{name: getbits(val, start, end) for ...}`, joined in
# FIELD ORDER. Four parallel lists rather than a record: the table is data, and
# a record would need `+` for the reads the walk does.
# ===========================================================================
def dec.go(+names: List<&2, String>, +starts: List<&2, U32>, +ends: List<&2, U32>,
           +val: U32, +acc: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}: acc
    case +h <> nms:
      match starts:
        case Nil{}: acc
        case +s <> ss:
          match ends:
            case Nil{}: acc
            case +e <> es: dec.go(nms, ss, es, val, List.append(&2, String, acc,
              [String.concat([h, ":", U32.show(getbits(val, s, e))])]))

def AMDReg.decode(+val: U32, +names: List<&2, String>, +starts: List<&2, U32>, +ends: List<&2, U32>) -> String:
  String.join(dec.go(names, starts, ends, val, []), ",")

# ===========================================================================
# `AMDReg.fields_mask(*names)`: `reduce(int.__or__, ((((1 << (hi - lo + 1)) - 1)
# << lo) for nm in names), 0)`. The NAME selection is `self.fields[nm]`, a dict
# lookup, so what is gated here is the mask ARITHMETIC over the chosen ranges.
# ===========================================================================
def AMDReg.width(+start: U32, +end: U32) -> U32: getbits.mask(getbits.width(end, start))

def msk.go(+starts: List<&2, U32>, +ends: List<&2, U32>, +acc: U32) -> U32:
  match starts:
    case Nil{}: acc
    case +s <> ss:
      match ends:
        case Nil{}: acc
        case +e <> es: msk.go(ss, es, U32.or(acc, U32.shln(AMDReg.width(s, e), U32.to_nat(s))))

def AMDReg.fields_mask(+starts: List<&2, U32>, +ends: List<&2, U32>) -> U32: msk.go(starts, ends, 0)

def fld.go(+names: List<&2, String>, +starts: List<&2, U32>, +ends: List<&2, U32>,
           +acc: List<&2, String>) -> List<&2, String>:
  match names:
    case Nil{}: acc
    case +h <> nms:
      match starts:
        case Nil{}: acc
        case +s <> ss:
          match ends:
            case Nil{}: acc
            case +e <> es: fld.go(nms, ss, es, List.append(&2, String, acc,
              [String.concat([h, ":", U32.show(s), "-", U32.show(e)])]))

# the field table as `name:start-end,...` -- the shape a wrong range changes
def AMDReg.fields(+names: List<&2, String>, +starts: List<&2, U32>, +ends: List<&2, U32>) -> String:
  String.join(fld.go(names, starts, ends, []), ",")

# ===========================================================================
# `__post_init__`. `AMDReg.addr` is `instance_tuple[segment] + offset` -- the
# comprehension's loop variable shadowing the field -- so it takes the instance
# TUPLES, not the field. `jget` answers 0 out of range, which is why
# `AMDReg.addr_ok` exists: the Python raises IndexError there, and a port that
# answered a number instead would look fine and be wrong.
# ===========================================================================
def jget(+xs: List<&2, U32>, +j: U32) -> U32:
  match xs:
    case Nil{}: 0
    case +h <> t: Bool.pick(U32, U32.is_eq(j, 0), h, jget(t, U32.sub(j, 1)))

def AMDReg.addr_ok(+tup: List<&2, U32>, +segment: U32) -> Bool:
  Bool.not(List.is_empty(&2, U32, List.drop(&2, U32, tup, U32.to_nat(segment))))

# `__post_init__` builds the dict over EVERY instance, so ONE tuple that is too
# short aborts the whole comprehension -- which is why the predicate is over the
# TUPLE LIST and not over one instance. `amd.addr_ok_1` is the row.
def aok.go(+tups: List<&2, List<&2, U32>>, +segment: U32, +acc: Bool) -> Bool:
  match tups:
    case Nil{}: acc
    case +h <> t: aok.go(t, segment, Bool.and(acc, AMDReg.addr_ok(h, segment)))

def AMDReg.addr_all_ok(+tups: List<&2, List<&2, U32>>, +segment: U32) -> Bool: aok.go(tups, segment, True{})

def AMDReg.addr(+tup: List<&2, U32>, +segment: U32, +offset: U32) -> U32: U32.add(jget(tup, segment), offset)

def ar.go(+tups: List<&2, List<&2, U32>>, +segment: U32, +offset: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match tups:
    case Nil{}: acc
    case +h <> t: ar.go(t, segment, offset, List.append(&2, U32, acc, [AMDReg.addr(h, segment, offset)]))

def AMDReg.addr_all(+tups: List<&2, List<&2, U32>>, +segment: U32, +offset: U32) -> List<&2, U32>: ar.go(tups, segment, offset, [])

# the `bases` fixture: instance 0 has TWO base addresses and instance 3 has ONE,
# so segment 1 is in range for the first and out of range for the second.
def P_TUPS() -> List<&2, List<&2, U32>>: [[69632, 71680], [12288]]

# a bases table where EVERY instance has two addresses, so segment 1 is in
# range everywhere. Without it `AMDReg.addr`'s segment index is unobservable:
# the mutation that replaces `jget(tup, segment)` with `hd(tup)` moved NO row.
def P_TUPS2() -> List<&2, List<&2, U32>>: [[69632, 71680], [12288, 40960]]

def hx2.digit(+d: U32) -> Char: Char.from_u32(U32.add(48, Bool.pick(U32, U32.is_gt(d, 9), U32.add(39, d), d)))

# `{v:x}`. The fuel is a `Nat` and not the `U32`: bend only recognises a `Nat`
# as decreasing (MEASURED -- `hx2.go(+n: U32, ...)` with `U32.div(n, 16)`
# is refused as "expected a decreasing self-call"), so `Nat.div(n, 16n)` is the
# recursion and the digit is taken from the same `n`.
# `{v:x}`. MEASURED: bend's decreasing-self-call check wants the COUNTDOWN in
# the first argument and the VALUE passed unchanged -- `Nat.div(p, 16n)` in the
# fuel slot is refused, and so is `U32.div(n, 16)`. So this is `Nat.show.go`'s
# shape: a `Nat` countdown from `U32.log2`, and the magnitude travelling beside
# it. Eight digits at most, so `log2/4 + 1` is exactly the digit count.
# the digit COUNT, by shifting right until zero rather than by `log2`: a
# magnitude like 0x11020 has `log2/4 + 1 == 5` nibbles' worth of BITS but only
# 5 significant digits here, while 0x10000 would need 4 and `log2/4 + 1` gives
# 5 -- so `log2` pads and `hx2.len` does not.
def hx2.len(+k: Nat, +n: U32) -> U32:
  match k:
    case 0n: 0
    case 1n+p: Bool.pick(U32, U32.is_zero(n), 0,
      U32.add(1, hx2.len(p, U32.from_nat(Nat.div(U32.to_nat(n), 16n)))))

def hx2.count(+n: U32) -> Nat: U32.to_nat(hx2.len(8n, n))

# The digits come out LOWEST first, so the accumulated string is REVERSED at the
# end -- `String.reverse`, not a second walk. `f"{0x11020:x}"` is `11020` and the
# walk produces `02011`, which is the same digits in the other order.
def hx2.go(+k: Nat, +n: U32, +acc: String) -> String:
  match k:
    case 0n: String.reverse(acc)
    case 1n+p: hx2.go(p, U32.from_nat(Nat.div(U32.to_nat(n), 16n)),
      String.append(acc, String.from_list([hx2.digit(U32.mod(n, 16))])))

# `{v:x}`: lowercase, no padding, and `0` is `0` -- not the empty string
def hex.of(+n: U32) -> String: Bool.pick(String, U32.is_zero(n), "0", hx2.go(hx2.count(n), n, ""))

def hx2.oflist.go(+xs: List<&2, U32>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case h <> t: hx2.oflist.go(t, Bool.pick(String, String.is_empty(acc),
      String.concat(["0x", hex.of(h)]), String.concat([acc, ",", "0x", hex.of(h)])))

def hx2.oflist(+xs: List<&2, U32>) -> String: hx2.oflist.go(xs, "")

# NOTE ON A NAME. `import_module.pick_last` and `SRT.greatest` are NOT upstream
# names because upstream has NO name for either: `children[-1]` and
# `sorted(...)[-1]` are EXPRESSIONS. `last` is also one of the TWO bend keywords
# (`match` and `where`), so it cannot head a def and is not the reason for the
# rename -- the rename is because there is nothing to match.
#
# ===========================================================================
# `AMDIP.__getattr__`: `name.replace('reg', 'mm')` replaces EVERY occurrence,
# not the first -- so `regregMM_A` becomes `mmmmMM_A` and is NOT found, which
# is why `amd_ga_*_rewrite_regregMM_A` sits BESIDE `amd_ga_*_regregMM_A`. The
# arm position is load bearing: `rep.at` is checked at the HEAD of the remaining
# string, and a scan that checked at the TAIL would replace differently.
# ===========================================================================
def hc(+cs: List<&2, Char>) -> Char: Maybe.default(&2, Char, List.head(&2, Char, cs), ' ')

def rep.at(+cs: List<&2, Char>, +needle: List<&2, Char>) -> Bool:
  Bool.and(Bool.not(List.is_empty(&2, Char, cs)), Bool.and(Bool.not(List.is_empty(&2, Char, needle)),
    Char.is_eq(hc(cs), hc(needle))))

# `str.replace(needle, repl)`: at the match, emit the replacement and continue
# after the needle. `case h <> t` has already consumed the needle's FIRST
# character, so `m` is `len(needle) - 1` and not `len(needle)` -- the two
# off-by-ones are the two ports that produced `mmegMM_A` and `mmM_A`.
#
# The fuel is the countdown `k` and not the character list, because
# `List.drop` behind a `def` is invisible to bend's decreasing-self-call check
# (MEASURED: `vle.go` with `tl(a)` was refused until the countdown came first).
def rep.drop(+cs: List<&2, Char>, +m: Nat) -> List<&2, Char>: List.drop(&2, Char, cs, m)

def rep.scan(+k: Nat, +m: Nat, +cs: List<&2, Char>, +needle: List<&2, Char>,
             +repl: List<&2, Char>, +acc: List<&2, Char>) -> List<&2, Char>:
  match k:
    case 0n: acc
    case 1n+p: match cs:
      case Nil{}: acc
      case h <> t: Bool.pick(List<&2, Char>, rep.at(cs, needle),
        rep.scan(p, m, rep.drop(t, m), needle, repl, List.append(&2, Char, acc, repl)),
        rep.scan(p, m, t, needle, repl, List.append(&2, Char, acc, [h])))

def AMDIP.name10(+name: String) -> String:
  String.from_list(rep.scan(String.length(name), Nat.sub(String.length("reg"), 1n),
    String.to_list(name), String.to_list("reg"), String.to_list("mm"), []))

# `AMDIP.__getattr__`: the direct lookup first, then the `reg` -> `mm` rewrite,
# then the refusal. `AMDIP.ga` is which of the THREE happened, and the refusal
# carries the upper-cased IP name from `f"{self.name.upper()} has no register ..."`
def AMDIP.ga(+found_direct: Bool, +found_rewrite: Bool) -> U32:
  Bool.pick(U32, found_direct, 1, Bool.pick(U32, found_rewrite, 2, 0))

def AMDIP.ga_err(+ipname: String, +query: String) -> String:
  String.concat(["AttributeError: ", String.to_upper(ipname), " has no register ", query])

# ===========================================================================
# `import_module`. Three conjuncts, and the second is a TUPLE comparison against
# a variable-length tuple -- so `gc_9` (v=(9,)) is `<=` (9,4,3) while `gc_10` is
# not. `import_module.vle` is that comparison and `import_module.vers` is
# `tuple(map(int, c.split('_')[1:]))`.
# ===========================================================================
def t3.eq3(a: U32, b: U32, c: U32, x: U32, y: U32, z: U32) -> Bool:
  Bool.and(U32.is_eq(a, x), Bool.and(U32.is_eq(b, y), U32.is_eq(c, z)))

def t3.of(major: U32, minor: U32, patch: U32) -> String:
  String.concat([U32.show(major), ".", U32.show(minor), ".", U32.show(patch)])

def import_module.override(+name: String, +major: U32, +minor: U32, +patch: U32) -> String:
  Bool.pick(String,
    Bool.and(String.eq(name, "smu"), Bool.or(t3.eq3(major, minor, patch, 13, 0, 7),
      t3.eq3(major, minor, patch, 13, 0, 10))),
    "13.0.0", t3.of(major, minor, patch))

# `c.split('_')[1:]` -- the tail after the FIRST separator, keeping empties.
# `String.drop(c, 1n)` is NOT the slice: it drops ONE CHARACTER, so it leaves
# the head of the name in front of the first version number and every filter
# row came back empty. `[1:]` is the TAIL of the split list.
def tl2(+xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: []
    case h <> t: t

def import_module.tail(+c: String) -> List<&2, String>: tl2(String.split(c, '_'))

def vv.go2(+parts: List<&2, String>, +acc: List<&2, U32>) -> List<&2, U32>:
  match parts:
    case Nil{}: acc
    case h <> t: vv.go2(t, List.append(&2, U32, acc, [u32.of(h)]))

def import_module.vers(+c: String) -> List<&2, U32>: vv.go2(import_module.tail(c), [])

# `v[0]` on the empty tuple is the IndexError that is NOT caught (WALL 4), and
# it aborts the WHOLE comprehension rather than skipping the child
def import_module.vfirst_ok(+v: List<&2, U32>) -> Bool: Bool.not(List.is_empty(&2, U32, v))

# the fuel is a `Nat` COUNTDOWN beside the two lists, which is
# `Nat.show.go`'s shape again: bend's check is structural, so `U32.sub(n, 1)`
# in a `U32` slot and `List.tail` behind a `def` are both invisible to it.
# Python's tuple comparison: element-wise over the SHORTER length, and when one
# is a PREFIX of the other the SHORTER is the smaller. That tiebreak is load
# bearing and its absence is a silent over-match: without it (9,4,3,1) `<=`
# (9,4,3), and `amd.fake_gc_9_4_3.kids` answers FOUR children instead of three.
def vle.go(+k: Nat, +a: List<&2, U32>, +b: List<&2, U32>, +la: Nat, +lb: Nat) -> Bool:
  match k:
    case 0n: Nat.is_le(la, lb)
    case 1n+p: Bool.and(U32.is_le(hd(a), hd(b)),
      Bool.or(U32.is_ne(hd(a), hd(b)), vle.go(p, tl(a), tl(b), Nat.sub(la, 1n), Nat.sub(lb, 1n))))

def min.nat(+a: Nat, +b: Nat) -> Nat: Bool.pick(Nat, Nat.is_le(a, b), a, b)

def import_module.vle(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
  vle.go(min.nat(List.length(&2, U32, a), List.length(&2, U32, b)), a, b,
    List.length(&2, U32, a), List.length(&2, U32, b))

# the second conjunct needs BOTH the override applied AND the parse
def u32.tail(+s: String) -> List<&2, U32>: vv.go2(String.split(s, '.'), [])

# the filter's target is the OVERRIDDEN version, so applying the table is part
# of the filter and not a separate step: without it (13, 0, 10) would match
# `smu_13_0_6` as well as `smu_13_0_0`.
def import_module.target(+name: String, +major: U32, +minor: U32, +patch: U32) -> String:
  import_module.override(name, major, minor, patch)

def import_module.keep(+c: String, +name: String, +target: List<&2, U32>) -> Bool:
  Bool.and(String.starts_with(c, name),
    Bool.and(import_module.vfirst_ok(import_module.vers(c)),
      Bool.and(U32.is_eq(hd(import_module.vers(c)), hd(target)),
        import_module.vle(import_module.vers(c), target))))

def kd.go(+all: List<&2, String>, +name: String, +target: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match all:
    case Nil{}: acc
    case +c <> t: kd.go(t, name, target,
      Bool.pick(List<&2, String>, import_module.keep(c, name, target), List.append(&2, String, acc, [c]), acc))

def import_module.kids(+all: List<&2, String>, +name: String, +target: String) -> List<&2, String>:
  kd.go(all, name, u32.tail(target), [])

# the version OVERRIDE is a 3-tuple table, so a FOUR-component target can never
# match it -- `amd.fake_gc_9_4_3_1.kids` is the row that shows (9,4,3,1)
# answering differently from (9,4,3) for exactly that reason.
def import_module.kids3(+all: List<&2, String>, +name: String, +major: U32, +minor: U32, +patch: U32) -> List<&2, String>:
  import_module.kids(all, name, import_module.target(name, major, minor, patch))

def import_module.pick_last(+xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case h <> t: Bool.pick(String, List.is_empty(&2, String, t), h, import_module.pick_last(t))

def import_module.n(+xs: List<&2, String>) -> U32: U32.from_nat(List.length(&2, String, xs))

def import_module.err(+submod: String, +name: String, +major: U32, +minor: U32, +patch: U32) -> String:
  String.concat([submod, ".", name, " ", U32.show(major), ".", U32.show(minor), ".", U32.show(patch)])

def import_soc.name(+major: U32) -> String: String.concat(["soc_", U32.show(major)])

# `{ip[1]:x}` is lowercase hex with NO padding, so `15` is `f` and `255` is `ff`
def import_pmc.hex2(+v: U32) -> String: hex.of(v)

def import_pmc.key(+major: U32, +minor: U32, +patch: U32) -> String:
  Bool.pick(String, U32.is_eq(major, 9),
    String.concat(["gfx", U32.show(major), import_pmc.hex2(minor), import_pmc.hex2(patch)]),
    String.concat(["gfx", U32.show(major)]))

def import_asic_regs.n(+regs: List<&2, String>) -> U32: U32.from_nat(List.length(&2, String, regs))

def import_asic_regs.first(+regs: List<&2, String>) -> String:
  match regs:
    case Nil{}: ""
    case h <> t: h

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def u32s.go(+xs: List<&2, U32>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case h <> t: u32s.go(t, Bool.pick(String, String.is_empty(acc),
      String.concat([U32.show(h)]), String.concat([acc, ",", U32.show(h)])))

def u32s.of(+xs: List<&2, U32>) -> String: u32s.go(xs, "")

# `sorted(kids)[-1]` -- the GREATEST child, which is NOT what `import_module`
# returns. `SRT.greatest` exists so the difference between "last of __all__" and
# "greatest version" is a ROW rather than a claim in a comment.
def SRT.go(+xs: List<&2, String>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case h <> t: SRT.go(t, Bool.pick(String, String.is_gt(h, acc), h, acc))

def SRT.greatest(+xs: List<&2, String>) -> String: SRT.go(xs, "")

# the ORDER of a hand-built `regs.__all__` fixture, which is what makes
# `children[-1]` answer `gc_9_4_2`. The real 28-entry list is WALL 1.
def FAKE_ALL() -> List<&2, String>:
  ["gc_9_4_3", "gc_9_0_0", "gc_11_0_0", "gc_9_4_2", "gc_9_4_3_1", "gfx_9_4_3"]

# ===========================================================================
# THE GATE. Every `amd_` row is a row of `.agents/slop/ext_oracle.py` section
# `am`, which calls the real `amd.py` against the real autogen package.
# ===========================================================================
def t_getbits() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("amd.getbits_0_0_31", U32.show(getbits(0, 0, 31)))
    b : Unit <- srow("amd.getbits_1_0_0", U32.show(getbits(1, 0, 0)))
    c : Unit <- srow("amd.getbits_3735928559_0_31", U32.show(getbits(3735928559, 0, 31)))
    d : Unit <- srow("amd.getbits_3735928559_4_7", U32.show(getbits(3735928559, 4, 7)))
    e : Unit <- srow("amd.getbits_4294967295_0_31", U32.show(getbits(4294967295, 0, 31)))
    f : Unit <- srow("amd.getbits_5_3_3", U32.show(getbits(5, 3, 3)))
    g : Unit <- srow("amd.getbits_0_31_31", U32.show(getbits(0, 31, 31)))
    h : Unit <- srow("amd.width_0_31", U32.show(getbits.width(31, 0)))
    i : Unit <- srow("amd.mask_32", U32.show(getbits.mask(32)))
    j : Unit <- srow("amd.mask_31", U32.show(getbits.mask(31)))
    IO.print("amd_getbits_done=1")

def t_addr() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("amd.addrlist_0", hx2.oflist(AMDReg.addr_all([[69632, 71680], [12288]], 0, 32)))
    c : Unit <- srow("amd.addr_ok_0", U32.show(Bool.to_u32(AMDReg.addr_all_ok(P_TUPS, 0))))
    d : Unit <- srow("amd.addr_ok_1", U32.show(Bool.to_u32(AMDReg.addr_all_ok(P_TUPS, 1))))
    e : Unit <- srow("amd.addr_ok_2", U32.show(Bool.to_u32(AMDReg.addr_all_ok(P_TUPS, 2))))
    f : Unit <- srow("amd.addr_ok_empty", U32.show(Bool.to_u32(AMDReg.addr_ok([], 0))))
    g2 : Unit <- srow("amd.addrlist_1", hx2.oflist(AMDReg.addr_all(P_TUPS2, 1, 32)))
    g3 : Unit <- srow("amd.addr_ok_3", U32.show(Bool.to_u32(AMDReg.addr_all_ok(P_TUPS2, 1))))
    g : Unit <- srow("amd.addr_one", hex.of(AMDReg.addr([69632, 71680], 0, 32)))
    h : Unit <- srow("amd.addr_one_off", hex.of(AMDReg.addr([69632, 71680], 0, 0)))
    IO.print("amd_addr_done=1")

def t_enc() -> IO(Unit):
  do IO<Unit>:
    # regGRBM_CNTL: read_timeout(0,7) and report_last_rderr(31,31), disjoint
    a : Unit <- srow("amd.asic_gc_9_4_3.enc1", U32.show(AMDReg.encode([255], [0])))
    b : Unit <- srow("amd.asic_gc_9_4_3.enc2", U32.show(AMDReg.encode([255, 1], [0, 31])))
    c : Unit <- srow("amd.asic_gc_9_4_3.enc_rev", U32.show(AMDReg.encode([1, 255], [31, 0])))
    d : Unit <- srow("amd.asic_gc_9_4_3.enc_same", U32.show(Bool.to_u32(U32.is_eq(
      AMDReg.encode([255], [0]), AMDReg.encode([255], [31])))))
    # regHDP_MEM_POWER_CTRL: two one-bit fields, so the order CANNOT show
    e : Unit <- srow("amd.asic_hdp_6_0_0.enc1", U32.show(AMDReg.encode([1], [0])))
    f : Unit <- srow("amd.asic_hdp_6_0_0.enc2", U32.show(AMDReg.encode([1, 1], [0, 1])))
    g : Unit <- srow("amd.asic_hdp_6_0_0.enc_rev", U32.show(AMDReg.encode([1, 1], [0, 1])))
    # the SAME value at TWO different fields, which is what the oracle's
    # `encode(**{n0: v0}) == encode(**{n1: v0})` asks: 1 at bit 0 against 1 at
    # bit 1
    h : Unit <- srow("amd.asic_hdp_6_0_0.enc_same", U32.show(Bool.to_u32(U32.is_eq(
      AMDReg.encode([1], [0]), AMDReg.encode([1], [1])))))
    # OVERLAPPING fields: 4 bits at 0 and 4 bits at 2, so the order shows
    i : Unit <- srow("amd.encode_ovl_a", U32.show(AMDReg.encode([15, 15], [0, 2])))
    j : Unit <- srow("amd.encode_ovl_b", U32.show(AMDReg.encode([15, 15], [2, 0])))
    k : Unit <- srow("amd.encode_ovl_same", U32.show(Bool.to_u32(U32.is_eq(
      AMDReg.encode([15, 15], [0, 2]), AMDReg.encode([15, 15], [2, 0])))))
    l : Unit <- srow("amd.encode_empty", U32.show(AMDReg.encode([], [])))
    IO.print("amd_enc_done=1")

def t_dec() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("amd.asic_gc_9_4_3.dec_str", AMDReg.decode(1048831, ["read_timeout", "report_last_rderr"], [0, 31], [7, 31]))
    b : Unit <- srow("amd.dec_hdp", AMDReg.decode(1073741827,
      ["atomic_mem_power_ctrl_en", "atomic_mem_idle_hysteresis", "rc_mem_idle_hysteresis"],
      [0, 4, 20], [0, 6, 22]))
    c : Unit <- srow("amd.dec_w32", AMDReg.decode(305419896, ["content"], [0], [31]))
    d : Unit <- srow("amd.dec_empty", AMDReg.decode(7, [], [], []))
    e : Unit <- srow("amd.asic_gc_9_4_3.fields", AMDReg.fields(["read_timeout", "report_last_rderr"], [0, 31], [7, 31]))
    f : Unit <- srow("amd.asic_mp_11_0_0.fields", AMDReg.fields(["content"], [0], [31]))
    IO.print("amd_dec_done=1")

def t_mask() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("amd.asic_gc_9_4_3.mask1", U32.show(AMDReg.fields_mask([0], [7])))
    b : Unit <- srow("amd.asic_gc_9_4_3.mask2", U32.show(AMDReg.fields_mask([0, 31], [7, 31])))
    c : Unit <- srow("amd.asic_gc_9_4_3.mask_rev", U32.show(AMDReg.fields_mask([31, 0], [31, 7])))
    d : Unit <- srow("amd.asic_hdp_6_0_0.mask2", U32.show(AMDReg.fields_mask([0, 1], [0, 1])))
    e : Unit <- srow("amd.mask_w32", U32.show(AMDReg.fields_mask([0], [31])))
    f : Unit <- srow("amd.mask_empty", U32.show(AMDReg.fields_mask([], [])))
    g : Unit <- srow("amd.asic_gc_9_4_3.mask_hex", String.concat(["0x", hex.of(AMDReg.fields_mask([0, 31], [7, 31]))]))
    IO.print("amd_mask_done=1")

def t_mod() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("amd.ovr_smu_13_0_7", import_module.override("smu", 13, 0, 7))
    b : Unit <- srow("amd.ovr_smu_13_0_10", import_module.override("smu", 13, 0, 10))
    c : Unit <- srow("amd.ovr_smu_13_0_6", import_module.override("smu", 13, 0, 6))
    d : Unit <- srow("amd.ovr_smu_14_0_2", import_module.override("smu", 14, 0, 2))
    e : Unit <- srow("amd.ovr_gc_13_0_7", import_module.override("gc", 13, 0, 7))
    f : Unit <- srow("amd.ovr_smu13_13_0_7", import_module.override("smu13", 13, 0, 7))
    g : Unit <- srow("amd.vers_gc-9-4-3", u32s.of(import_module.vers("gc_9_4_3")))
    h : Unit <- srow("amd.vers_gc-9", u32s.of(import_module.vers("gc_9")))
    i : Unit <- srow("amd.vers_gc", u32s.of(import_module.vers("gc")))
    j : Unit <- srow("amd.vfirst_gc", U32.show(Bool.to_u32(import_module.vfirst_ok(import_module.vers("gc")))))
    k : Unit <- srow("amd.vfirst_gc-9", U32.show(Bool.to_u32(import_module.vfirst_ok(import_module.vers("gc_9")))))
    l : Unit <- srow("amd.vfirst_smu-13-0-12", U32.show(Bool.to_u32(import_module.vfirst_ok(import_module.vers("smu_13_0_12")))))
    m : Unit <- srow("amd.vers_smu-13-0-12", u32s.of(import_module.vers("smu_13_0_12")))
    n : Unit <- srow("amd.vers_gc-9-4-3-1", u32s.of(import_module.vers("gc_9_4_3_1")))
    IO.print("amd_mod_done=1")

def t_fake() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("amd.fake_gc_9_4_3.kids", String.join(import_module.kids3(FAKE_ALL, "gc", 9, 4, 3), ","))
    b : Unit <- srow("amd.fake_gc_9_4_3.last", import_module.pick_last(import_module.kids3(FAKE_ALL, "gc", 9, 4, 3)))
    c : Unit <- srow("amd.fake_gc_9_4_3.n", U32.show(import_module.n(import_module.kids3(FAKE_ALL, "gc", 9, 4, 3))))
    d : Unit <- srow("amd.fake_gc_9_4_3.sorted_last", SRT.greatest(import_module.kids3(FAKE_ALL, "gc", 9, 4, 3)))
    e : Unit <- srow("amd.fake_gc_9_0_0.kids", String.join(import_module.kids3(FAKE_ALL, "gc", 9, 0, 0), ","))
    f : Unit <- srow("amd.fake_gc_12_0_0.kids", String.join(import_module.kids3(FAKE_ALL, "gc", 12, 0, 0), ","))
    g : Unit <- srow("amd.fake_gc_12_0_0.last", import_module.pick_last(import_module.kids3(FAKE_ALL, "gc", 12, 0, 0)))
    h : Unit <- srow("amd.fake_gc_9_4_3_1.kids", String.join(import_module.kids(FAKE_ALL, "gc", "9.4.3.1"), ","))
    i : Unit <- srow("amd.fake_gc_13_0_0.kids", String.join(import_module.kids3(FAKE_ALL, "gc", 13, 0, 0), ","))
    j : Unit <- srow("amd.fake_gc_13_0_0.last", import_module.pick_last(import_module.kids3(FAKE_ALL, "gc", 13, 0, 0)))
    IO.print("amd_fake_done=1")

def t_ga() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("amd.ga_gc_rewrite_mmMM_A", AMDIP.name10("regMM_A"))
    b : Unit <- srow("amd.ga_gc_rewrite_reg_", AMDIP.name10("reg_"))
    c : Unit <- srow("amd.ga_gc_rewrite_reg", AMDIP.name10("reg"))
    d : Unit <- srow("amd.ga_gc_rewrite_regregMM_A", AMDIP.name10("regregMM_A"))
    f : Unit <- srow("amd.ga_gc_rewrite_none", AMDIP.name10("nope"))
    g : Unit <- srow("amd.ga_gc_direct", U32.show(AMDIP.ga(True{}, False{})))
    h : Unit <- srow("amd.ga_gc_rewrite", U32.show(AMDIP.ga(False{}, True{})))
    i : Unit <- srow("amd.ga_gc_none", U32.show(AMDIP.ga(False{}, False{})))
    j : Unit <- srow("amd.ga_gc_err", AMDIP.ga_err("gc", "nope"))
    k : Unit <- srow("amd.ga_gc_err_reg", AMDIP.ga_err("gc", "regMMFOO"))
    l : Unit <- srow("amd.ga_SMU_err_reg", AMDIP.ga_err("smu", "regMMFOO"))
    IO.print("amd_ga_done=1")

def t_ip() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("amd.ip_9_0_0.key", import_pmc.key(9, 0, 0))
    b : Unit <- srow("amd.ip_11_0_0.key", import_pmc.key(11, 0, 0))
    c : Unit <- srow("amd.ip_12_0_0.key", import_pmc.key(12, 0, 0))
    d : Unit <- srow("amd.ip_9_4_3.key", import_pmc.key(9, 4, 3))
    e : Unit <- srow("amd.ip_10_10_0.key", import_pmc.key(10, 10, 0))
    f : Unit <- srow("amd.ip_0_0_0.key", import_pmc.key(0, 0, 0))
    g : Unit <- srow("amd.ip_9_15_255.key", import_pmc.key(9, 15, 255))
    h : Unit <- srow("amd.ip_9_16_0.key", import_pmc.key(9, 16, 0))
    i : Unit <- srow("amd.ip_9_0_0.soc", import_soc.name(9))
    j : Unit <- srow("amd.ip_11_0_0.soc", import_soc.name(11))
    k : Unit <- srow("amd.ip_12_0_0.soc", import_soc.name(12))
    l : Unit <- srow("amd.ip_0_0_0.soc", import_soc.name(0))
    m : Unit <- srow("amd.ip_10_10_0.soc", import_soc.name(10))
    n : Unit <- srow("amd.hex_15", import_pmc.hex2(15))
    o : Unit <- srow("amd.hex_255", import_pmc.hex2(255))
    IO.print("amd_ip_done=1")

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_getbits()
    b : Unit <- t_addr()
    c : Unit <- t_enc()
    d : Unit <- t_dec()
    e : Unit <- t_mask()
    f : Unit <- t_mod()
    g : Unit <- t_fake()
    h : Unit <- t_ga()
    i : Unit <- t_ip()
    IO.print("amd-done=1")