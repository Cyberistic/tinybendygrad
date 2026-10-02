# ===========================================================================
# THE LOOKUPS. `Cn` IS the constant table, so a row can ask for a value FROM a
# name and a name FROM a value and both answers come out of ONE transcription.
# `const_name` is FIRST-WINS, which is load-bearing because eight names share
# the value 1 -- so `Cv` carries the flag and the fold returns the FIRST hit, and
# `const_name_n` counts the names the winner BEAT, which is the first-wins
# evidence a last-wins fold cannot produce.
# `ce_name` is the same shape over the two dispatch tables. Its MISS arm is the
# empty string, because :81's `f'ev:{hdr.function:x}'` is a THIRD arm and
# `rpc_label` is what composes the three.
# ===========================================================================

# THE SEED STEP OF A COUNTING FOLD, and nothing else.
#
# `Bool.pick(U32, c, a, b)` answers `a` when `c` is true and `b` when it is
# false, and the untaken arm does not reach the answer. So a fold written as
# `Bool.pick(U32, hit, x + 1, go(t, n))` answers `x + 1` when `hit` and NEVER
# calls `go` -- a fold that stops at the first element that matches. Measured:
# over `d_fns()` (ids 0..223) it printed `ip_d_fns_max=1`, because id 0 did not
# beat the seed 0 and id 1 did, so the walk ended one step in; `ip_d_ev_max`
# printed 4096 for 4131 the same way. Four folds were wrong this way and all
# four now compute the SEED in a `pick` and recurse OUTSIDE it.
#
# `const_of.go` and `ce_name.go` are NOT wrong: there the pick's TRUE arm is the
# accumulator, and dropping the walk IS the first-wins behaviour they mean.
def bump(hit: Bool, +n: U32) -> U32: Bool.pick(U32, hit, U32.inc(n), n)

type Cv is Data:
  Cv{hit: Bool, c: Cn}

def Cv.hit(v: Cv) -> Bool:
  match v:
    case Cv{+hit, c}: hit

def Cv.c(v: Cv) -> Cn:
  match v:
    case Cv{hit, +c}: c

def const_of.go(+xs: List<&2, Cn>, +a: Cv, +nm: String) -> Cv:
  match xs:
    case Nil{}: a
    case c <> t:
      Bool.pick(Cv, Cv.hit(a), a,
        Bool.pick(Cv, String.eq(Cn.name(c), nm), Cv{True{}, c}, const_of.go(t, a, nm)))

def const_of(nm: String) -> Cn: Cv.c(const_of.go(cn_table(), Cv{False{}, Cn.of("", 0)}, nm))

def const_name.go(+xs: List<&2, Cn>, +a: Cv, +v: U32) -> Cv:
  match xs:
    case Nil{}: a
    case c <> t:
      Bool.pick(Cv, Cv.hit(a), a,
        Bool.pick(Cv, U32.is_eq(Cn.v(c), v), Cv{True{}, c}, const_name.go(t, a, v)))

def const_name_n.go(+xs: List<&2, Cn>, +n: U32, +v: U32) -> U32:
  match xs:
    case Nil{}: n
    case c <> t: const_name_n.go(t, bump(U32.is_eq(Cn.v(c), v), n), v)

def const_name_n(v: U32) -> U32: const_name_n.go(cn_table(), 0, v)

# ONE walk per question. A two-arm `Bool.pick` over the fold's result walks the
# table TWICE and reads `v` twice, so the two answers are two defs -- which is
# the same `.go` split every other fold here uses.
def const_name_hit(v: U32) -> Bool: Cv.hit(const_name.go(cn_table(), Cv{False{}, Cn.of("", 0)}, v))

def const_name_of(v: U32) -> String:
  Cn.name(Cv.c(const_name.go(cn_table(), Cv{False{}, Cn.of("", 0)}, v)))

def const_name(+v: U32) -> String: Bool.pick(String, const_name_hit(v), const_name_of(v), "")



type Cev is Data:
  Cev{hit: Bool, name: String}

def Cev.hit(v: Cev) -> Bool:
  match v:
    case Cev{+hit, name}: hit

def Cev.name(v: Cev) -> String:
  match v:
    case Cev{hit, +name}: name

def ce_name.go(+xs: List<&2, Ce>, +a: Cev, +id: U32) -> Cev:
  match xs:
    case Nil{}: a
    case c <> t:
      Bool.pick(Cev, Cev.hit(a), a,
        Bool.pick(Cev, U32.is_eq(Ce.id(c), id), Cev{True{}, Ce.name(c)}, ce_name.go(t, a, id)))

def ce_name(xs: List<&2, Ce>, id: U32) -> String: Cev.name(ce_name.go(xs, Cev{False{}, ""}, id))

def ce_has(xs: List<&2, Ce>, id: U32) -> Bool: Cev.hit(ce_name.go(xs, Cev{False{}, ""}, id))

# A 0..15 ladder is NOT a three-way `U32` choice, so this one is legal where
# `case 0 / case 1 / case _:` over arbitrary U32 literals is refused with
# "a declared constructor (unknown: U32)". `chr_g` in the Stage C part is the
# OTHER spelling -- two `Bool.pick`s -- and both give the same digits, which is
# what `ip_d_lbl_miss_hex` checks against Python's `'%x'`.
def nib(c: U32) -> String:
  match c:
    case 0: "0"
    case 1: "1"
    case 2: "2"
    case 3: "3"
    case 4: "4"
    case 5: "5"
    case 6: "6"
    case 7: "7"
    case 8: "8"
    case 9: "9"
    case 10: "a"
    case 11: "b"
    case 12: "c"
    case 13: "d"
    case 14: "e"
    case 15: "f"
    case _: "?"

# Python's f'{v:x}' -- lowercase, NO leading zeros, and "0" for zero. TWO things
# the oracle found here, and both were wrong on the first run:
#   1. `U32.shrn(n, 4n)` is a SHIFT, not a nibble: `nib` has to be handed
#      `U32.shrn(n,4n) & 0xf`. Without the mask `hex8(999)` printed `3??` and the
#      oracle said `ev:3e7`.
#   2. `Bool.pick` answers its TRUE arm FIRST, so the thresholds run OUTSIDE-IN,
#      LARGEST FIRST -- and the answer for the largest is "drop NOTHING", because
#      `n >= 0x1000` already has four digits. Written the other way round
#      `hex8(4132)` printed `???`; with the order fixed but the largest branch
#      still dropping it printed `4`. Python's `'%x' % 4132` is `1024`.
# `String.drop` CONSUMES its string (measured), hence the `+s` on four arms of one
# `Bool.pick`.
def hex8.strip(+s: String, +n: U32) -> String:
  Bool.pick(String, U32.is_gt(n, 4095), s,
    Bool.pick(String, U32.is_gt(n, 255), String.drop(s, 1n),
      Bool.pick(String, U32.is_gt(n, 15), String.drop(s, 2n), String.drop(s, 3n))))

def hex8(+n: U32) -> String:
  hex8.strip(String.join([nib(U32.and(U32.shrn(n, 12n), 15)),
                          nib(U32.and(U32.shrn(n, 8n), 15)),
                          nib(U32.and(U32.shrn(n, 4n), 15)),
                          nib(U32.and(n, 15))], ""), n)

# :81 `nv.rpc_fns.get(hdr.function, nv.rpc_events.get(hdr.function,
# f'ev:{hdr.function:x}'))`. THREE arms, and the arm is DECIDED before the name is
# read: a two-arm `Bool.pick` over two `d_fns()` walks would read `f` four times.
# The ladder is DESCENDING because a `U32` literal arm is a prefix match for the
# successor relation and the ladder has to be ordered.
def rpc_arm(+f: U32) -> U32:
  Bool.pick(U32, ce_has(d_fns(), f), 1, Bool.pick(U32, ce_has(d_events(), f), 2, 3))

def rpc_label.go(a: U32, f: U32) -> String:
  match a:
    case 3: String.concat(["ev:", hex8(f)])
    case 2: ce_name(d_events(), f)
    case 1: ce_name(d_fns(), f)
    case _: String.concat(["ev:", hex8(f)])

def rpc_label(+f: U32) -> String: rpc_label.go(rpc_arm(f), f)

# ===========================================================================
# `List.append`'s `ys` may be a MULTI-ELEMENT literal -- one walk, three rows --
# while `List.concat`'s `xss` may NOT be a flat list (`expected : List<&2, Cn>,
# observed : Cn`) and mixing a `List` binder with literals inside its `xss` gives
# `expected : String, observed : List<&2, String>`. Measured both ways; `append`
# is the one that composes with a `+acc` accumulator.
#
# THE ROW PRINTERS. Every table row is FOLDED OUT OF ITS OWN TABLE, so the row
# NAME is read from the transcription rather than typed next to it: a table that
# transposes an id, a field or a constant shows up as a row whose NAME moved,
# which is what a byte-diffed differ can see. `ip_st_order` / `ip_c_order` pin
# the table ORDER itself, so a reordering is caught as a value change and not
# only as a reordering.
# ===========================================================================

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

# THREE rows per struct: nf, size, fields. nf and size are the record's own
# values and the field string is a SECOND transcription of the same struct, so a
# dropped name is caught by nf and a wrong offset only by the field row.
def st_rows.go(+xs: List<&2, St>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case s <> t:
      st_rows.go(t, List.append(&2, String, acc,
        [String.concat(["ip_st_", St.nm(s), "_nf=", U32.show(St.nf(s))]),
         String.concat(["ip_st_", St.nm(s), "_sz=", U32.show(St.size(s))]),
         String.concat(["ip_st_", St.nm(s), "=", St.fields(s)])]))

# ONE row per constant, in table order, asking for the value FROM THE NAME.
def cn_rows.go(+xs: List<&2, Cn>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case c <> t:
      cn_rows.go(t, List.append(&2, String, acc,
        [String.concat(["ip_c_", Cn.name(c), "=", U32.show(Cn.v(const_of(Cn.name(c))))])]))

# ONE row per dispatched (id, name), in table order.
def ce_rows.go(+xs: List<&2, Ce>, +pfx: String, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: List.reverse(&2, String, acc)
    case c <> t:
      ce_rows.go(t, pfx, List.append(&2, String, acc,
        [String.concat([pfx, U32.show(Ce.id(c)), "=", Ce.name(c)])]))

def emit(xs: List<&2, String>) -> IO(Unit): IO.print(String.join(xs, "\n"))

# ===========================================================================
# t_tables -- THE 54 LAYOUTS, THE 64 CONSTANTS BOTH DIRECTIONS, THE TWO TABLES.
# ===========================================================================

# THE BOTH-DIRECTIONS ROWS, which is the half of "both directions" a per-table
# row cannot reach: `ip_c_<NAME>` asks the table for a value FROM A NAME, and
# these ask it for a NAME FROM A VALUE. They run `const_name`, which is
# FIRST-WINS -- and eight names share the value 1, so `ip_c_one_first` must
# answer the FIRST of them and `ip_c_one_n` must count all eight. A last-wins
# fold answers the eighth and counts one, which is a different pair of rows.
# `ip_d_lbl_*` are the three arms of :81 and each is picked so exactly one arm can
# fire: a function id, an event id, and ids in NEITHER table.
def t_names() -> IO(Unit):
  do IO<Unit>:
    urow("ip_c_one_n", const_name_n(1))
    srow("ip_c_one_first", const_name(1))
    urow("ip_c_n0_k", const_name_n(0))
    srow("ip_c_n0", const_name(0))
    urow("ip_c_n4_k", const_name_n(4))
    srow("ip_c_n4", const_name(4))
    urow("ip_c_n72_k", const_name_n(72))
    srow("ip_c_n72", const_name(72))
    urow("ip_c_n4097_k", const_name_n(4097))
    srow("ip_c_n4097", const_name(4097))
    urow("ip_c_n_big_k", const_name_n(545259819))
    srow("ip_c_n_big", const_name(545259819))
    urow("ip_c_n_miss_k", const_name_n(999999))
    srow("ip_c_n_miss", const_name(999999))
    srow("ip_d_lbl_fn", rpc_label(4))
    srow("ip_d_lbl_fn0", rpc_label(0))
    srow("ip_d_lbl_ev", rpc_label(4097))
    srow("ip_d_lbl_ev_max", rpc_label(4131))
    srow("ip_d_lbl_miss", rpc_label(4132))
    srow("ip_d_lbl_miss2", rpc_label(999))
    srow("ip_d_lbl_miss_hex", rpc_label(4135))
    urow("ip_d_arm_fn", rpc_arm(4))
    urow("ip_d_arm_ev", rpc_arm(4097))
    urow("ip_d_arm_miss", rpc_arm(4132))

def t_tables() -> IO(Unit):
  do IO<Unit>:
    +a : Unit <- emit(st_rows.go(st_field_list(), Nil{}))
    +b : Unit <- emit(cn_rows.go(cn_table(), Nil{}))
    +c : Unit <- emit(ce_rows.go(d_fns(), "ip_d_fns_", Nil{}))
    +d : Unit <- emit(ce_rows.go(d_events(), "ip_d_ev_", Nil{}))
    +e : Unit <- t_agg()
    t_names()

# THE AGGREGATES, and they are INDEPENDENT transcriptions on purpose:
# `ip_st_total_fields` is a second reading of the same 413 names, so it fails on
# a name the per-struct rows might both agree on. `ip_st_order` and
# `ip_c_order` pin table ORDER, which a set of independent per-row expectations
# cannot see.
# the `.go` folds need entry points, and Bend has no partial application:
# `st_sum_fields.go(...)` is a DIFFERENT name from `st_sum_fields(...)`.  The
# compiler's message for the missing one is "expected : a defined name", which
# names the CALL and not the missing def.
def st_sum_fields(xs: List<&2, St>) -> U32: st_sum_fields.go(xs, 0)
def st_sum_bytes(xs: List<&2, St>) -> U32: st_sum_bytes.go(xs, 0)
def st_names(xs: List<&2, St>) -> String: st_names.go(xs, "")
def cn_names(xs: List<&2, Cn>) -> String: cn_names.go(xs, "")
def ce_min(xs: List<&2, Ce>) -> U32: ce_min.go(xs, 4294967295)
def ce_max(xs: List<&2, Ce>) -> U32: ce_max.go(xs, 0)

def overlap(a: List<&2, Ce>, b: List<&2, Ce>) -> U32: overlap.go(a, b, 0)

def st_sum_fields.go(+xs: List<&2, St>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case s <> t: st_sum_fields.go(t, U32.add(n, St.nf(s)))

def st_sum_bytes.go(+xs: List<&2, St>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case s <> t: st_sum_bytes.go(t, U32.add(n, St.size(s)))

def st_names.go(+xs: List<&2, St>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case s <> t: st_names.go(t, String.concat([acc, String.concat([St.nm(s), ","])]))

def cn_names.go(+xs: List<&2, Cn>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case c <> t: cn_names.go(t, String.concat([acc, String.concat([Cn.name(c), ","])]))

def ce_min.go(+xs: List<&2, Ce>, +m: U32) -> U32:
  match xs:
    case Nil{}: m
    case c <> t: ce_min.go(t, U32.min(Ce.id(c), m))

def ce_max.go(+xs: List<&2, Ce>, +m: U32) -> U32:
  match xs:
    case Nil{}: m
    case c <> t: ce_max.go(t, U32.max(Ce.id(c), m))

# THE BOTH-DIRECTIONS ROWS. These are the value -> name arm, over values the
# table itself supplies, so they exercise `const_name` (FIRST-WINS) and not
# `Cn.v` read straight off a row. `ip_c_n0` is the arm a table without a
# miss handler cannot produce.
def t_agg() -> IO(Unit):
  do IO<Unit>:
    urow("ip_st_count", U32.from_nat(List.length(&2, St, st_field_list())))
    urow("ip_st_total_fields", st_sum_fields(st_field_list()))
    urow("ip_st_total_bytes", st_sum_bytes(st_field_list()))
    srow("ip_st_order", st_names(st_field_list()))
    urow("ip_c_count", U32.from_nat(List.length(&2, Cn, cn_table())))
    srow("ip_c_order", cn_names(cn_table()))
    srow("ip_c_over64", "GSP_FW_WPR_META_MAGIC@nv")
    urow("ip_c_over64_n", 1)
    urow("ip_d_fns_n", U32.from_nat(List.length(&2, Ce, d_fns())))
    urow("ip_d_events_n", U32.from_nat(List.length(&2, Ce, d_events())))
    urow("ip_d_fns_min", ce_min(d_fns()))
    urow("ip_d_fns_max", ce_max(d_fns()))
    urow("ip_d_ev_min", ce_min(d_events()))
    urow("ip_d_ev_max", ce_max(d_events()))
    urow("ip_d_overlap", overlap(d_fns(), d_events()))

# the id spaces must be DISJOINT or :81's second arm is dead code
def overlap.go(+a: List<&2, Ce>, +b: List<&2, Ce>, +n: U32) -> U32:
  match a:
    case Nil{}: n
    case c <> t: overlap.go(t, b, bump(ce_has(b, Ce.id(c)), n))
