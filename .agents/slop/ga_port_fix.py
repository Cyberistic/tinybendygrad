#!/usr/bin/env python3
"""Every SCRIPTED edit that took generate.bend from the inherited file to a
compiling one, as one idempotent patch.

WHY A FILE AND NOT A HISTORY.  The inherited `generate.bend` had never compiled,
and the fixes are not cosmetic: they are arg-order swaps, five mutual-recursion
restructures, a missing-`out` term in the replace engine, and three accessors
that were never written.  Keeping them as one runnable patch means the next
person can re-derive the file from `.agents/slop/ga-pre-topo.bak.bend` (the
inherited state, byte for byte) instead of trusting a prose report.

Every substitution is asserted, so a patch that no longer applies FAILS LOUDLY
rather than silently doing half the work.

Run:  python3 .agents/slop/ga_port_fix.py <file.bend>
"""
import pathlib
import re
import sys

SUBS = []


def sub(old, new, why=""):
    SUBS.append((old, new, why))


# ------------------------------------------------------- 1. write_enum rebuild
sub("""# `f"class {name}(ReprEnum):" if name in ("HWREG","MSG") else f"class {name}Op(ReprEnum):"`

def enum_members(fmt: String, eos: List<&2, EO>) -> List<&2, String>:
  enum_members.go(ops_of(fmt, eos), fmt, Nil{})

""", "", "dead entry")

sub("""def write_enum.cells(fmt: String, os_: List<&2, OP>) -> List<&2, String>:
  List.append(&2, String, ["class " ++ class_name(fmt) ++ "(ReprEnum):"],
    write_enum.aliases(fmt, os_))

""", "", "wrong-order duplicate")

sub("""def write_enum.go2(fmt: String, os_: List<&2, OP>, acc: List<&2, String>) -> List<&2, String>:
  List.append(&2, String,
    List.append(&2, String, write_enum.aliases(fmt, sort_ops(os_)),
      write_enum.cells(fmt, sort_ops(os_))),
    List.append(&2, String, ["", "class " ++ class_name(fmt) ++ "(ReprEnum):"], acc))

def write_enum.one(fmt: String, os_: List<&2, OP>, acc: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, acc,
    List.append(&2, String,
      List.append(&2, String, ["class " ++ class_name(fmt) ++ "(ReprEnum):"],
        write_enum.cells(fmt, os_)),
      List.append(&2, String, write_enum.aliases(fmt, os_), [""])))


def write_enum.cells.go(os_: List<&2, OP>, +fmt: String, acc: List<&2, String>) -> List<&2, String>:
  match os_:
    case Nil{}: acc
    case o <> t:
      write_enum.cells.go(t, fmt, List.append(&2, String, acc,
        ["  " ++ OP.nm(o) ++ op_msuf(fmt, OP.op(o)) ++ " = " ++ U32.show(OP.op(o))]))

def write_enum.go(eos: List<&2, EO>, acc: List<&2, String>) -> List<&2, String>:
  match eos:
    case Nil{}: acc
    case e <> t: write_enum.hit(e, t, acc, List.is_empty(&2, OP, EO.ops(e)))

# `if not ops: continue` -- AN ENUM WITH NO OPCODES EMITS NOTHING AT ALL, not even
# a class line and not even the blank separator.  A fixture with one such format
# is what makes that a gated row rather than a reading of the source.
def write_enum.hit(e: EO, t: List<&2, EO>, acc: List<&2, String>, empty: Bool) -> List<&2, String>:
  match empty:
    case True{}: write_enum.go(t, acc)
    case False{}: write_enum.go(t, write_enum.one(EO.fmt(e), sort_ops(EO.ops(e)), acc))""",
    """# ONE CLASS = HEADER, VALUE CELLS, ALIAS CELLS, BLANK, in that order.  The
# value walk (`enum_members.go`) and the alias walk (`write_enum.aliases.go`)
# are separate folds over the SAME sorted opcode list, and the alias walk emits
# only for the ops that received a suffix.
def write_enum.one(fmt: String, os_: List<&2, OP>, acc: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, acc, List.append(&2, String,
    List.append(&2, String, ["class " ++ class_name(fmt) ++ "(ReprEnum):"],
      enum_members.go(os_, fmt, Nil{})),
    List.append(&2, String, write_enum.aliases(fmt, os_), [""])))

# `if not ops: continue` -- AN ENUM WITH NO OPCODES EMITS NOTHING AT ALL, not
# even a class line and not even the blank separator.  A fixture with one such
# format is what makes that a gated row rather than a reading of the source.
def write_enum.go(eos: List<&2, EO>, acc: List<&2, String>) -> List<&2, String>:
  match eos:
    case Nil{}: acc
    case +e <> t: write_enum.go(t, Bool.pick(List<&2, String>, List.is_empty(&2, OP, EO.ops(e)), acc,
      write_enum.one(EO.fmt(e), sort_ops(EO.ops(e)), acc)))""",
    "write_enum: three dead/wrong-order variants merged into one")

# ---------------------------------------------------------- 2. fmt_allowed
sub("""def fmt_allowed.names.go(os_: List<&2, OP>, +base: String, eos: List<&2, EO>,
                         acc: List<&2, String>) -> List<&2, String>:
  match os_:
    case Nil{}: acc
    case o <> t:
      fmt_allowed.names.go(t, base, eos, List.append(&2, String, acc,
        [OP.nm(op_named(base, OP.op(o), eos))]))""",
    """# `f"{op_enum}.{enums[op_enum.removesuffix('Op')][op]}"` -- the PREFIX is the
# enum class name and the LOOKUP is the stripped format, which are two different
# strings over one table.  The opcode set is SORTED first: `fmt_allowed` receives
# a Python `set` and the emission order is the opcode order.
def fmt_allowed.names.go(os_: List<&2, OP>, +op_enum: String, eos: List<&2, EO>,
                         acc: List<&2, String>) -> List<&2, String>:
  match os_:
    case Nil{}: acc
    case +o <> t:
      fmt_allowed.names.go(t, op_enum, eos, List.append(&2, String, acc,
        [op_enum ++ "." ++ op_named(remsuffix(op_enum, "Op"), OP.op(o), eos)]))""",
    "fmt_allowed: the member is a STRING, not `OP.nm(...)`")

sub("""def fmt_allowed.names(os_: List<&2, OP>, +base: String, eos: List<&2, EO>) -> List<&2, String>:
  fmt_allowed.names.go(os_, base, eos, Nil{})""",
    """def fmt_allowed.names(os_: List<&2, OP>, op_enum: String, eos: List<&2, EO>) -> List<&2, String>:
  fmt_allowed.names.go(os_, op_enum, eos, Nil{})""", "fmt_allowed names")

sub('''  "{" ++ String.join(fmt_allowed.names(sort_ops(os_), remsuffix(op_enum, "Op"), eos), ", ") ++ "}"''',
    '''  "{" ++ String.join(fmt_allowed.names(sort_ops(os_), op_enum, eos), ", ") ++ "}"''',
    "fmt_allowed")

sub('  op_named.of(op_find(ops_of(base, eos), U32.show(op)), "")',
    '  op_named.of(op_find_nm(ops_of(base, eos), U32.show(op)), "")',
    "op_named searches by NAME, not by opcode")

# ------------------------------------------------------- 3. ty_le comparator
sub("""def ty_le(a: TY, b: TY) -> Bool:
  ty_le.pair(String.is_lt(TY.name(a), TY.name(b)), String.eq(TY.name(a), TY.name(b)),
    TY.base(a), TY.base(b))""",
    """# `sorted(types.items())` -- the key is the (name, enc_base) TUPLE, so the name
# is compared first and `base` only breaks a tie.  BORROWED, like `fld_le`:
# `List.sort` hands `le` borrowed elements.
def ty_le.b(t: TY, +a_name: String, +a_base: String) -> Bool:
  match t:
    case TY{+name, base, flds}: ty_le.pair(String.is_lt(a_name, name), String.eq(a_name, name), a_base, base)

def ty_le(a: TY, b: TY) -> Bool:
  match a:
    case TY{name, base, flds}: ty_le.b(b, name, base)""", "ty_le borrowed comparator")

# --------------------------------------------------------- 4. write_common
sub("  List.append(&2, String, write_common.tail(sort_fbs(fbs), sort_strs(ots)), write_common.head())",
    "  List.append(&2, String, write_common.head(), write_common.tail(sort_fbs(fbs), sort_strs(ots)))",
    "`List.append(x, A, xs, ys)` is `xs ++ ys`: the head was emitted LAST")


# ---------------------------------------------------- 5. the field-kind ladder
sub("""def field_kind.step(r: R, rest: List<&2, R>, +nm: String, width: U32, +base_fmt: String,
                    +fmt: String, cur: U32) -> U32:
  field_kind.step.of(r_ok(r, nm, width, base_fmt, fmt), r, rest, nm, width, base_fmt, fmt, cur)

def field_kind.step.of(hit: Bool, r: R, rest: List<&2, R>, +nm: String, width: U32,
                       +base_fmt: String, +fmt: String, cur: U32) -> U32:
  match hit:
    case True{}: R.kind(r)
    case False{}: field_kind.go(rest, nm, width, base_fmt, fmt, cur)

def field_kind.go(rs: List<&2, R>, +nm: String, width: U32, +base_fmt: String, +fmt: String,
                  cur: U32) -> U32:
  match rs:
    case Nil{}: cur
    case r <> rest: field_kind.step(r, rest, nm, width, base_fmt, fmt, cur)""",
    """# FIRST RULE THAT MATCHES WINS.  One def, not `go` -> `step` -> `step.of` ->
# `go`: that is mutual recursion, which bend refuses.  `Bool.pick` CHOOSES and
# bend evaluates both arms, which is free because both are pure and `rest` is
# strictly shorter -- so the ladder is one self-call per rule examined.
def field_kind.go(rs: List<&2, R>, +nm: String, width: U32, +base_fmt: String, +fmt: String,
                  cur: U32) -> U32:
  match rs:
    case Nil{}: cur
    case +r <> rest: Bool.pick(U32, r_ok(r, nm, width, base_fmt, fmt), R.kind(r),
      field_kind.go(rest, nm, width, base_fmt, fmt, cur))""", "field_kind ladder")

sub("def r_ok(r: R, +nm: String, width: U32, +base_fmt: String, +fmt: String) -> Bool:",
    "def r_ok(+r: R, +nm: String, width: U32, +base_fmt: String, +fmt: String) -> Bool:",
    "`r_ok` reads `r` twice")

sub("def r_pk(pk: U32, pa: String, +nm: String) -> Bool:",
    """def R.pk(r: R) -> U32:
  match r:
    case R{pk, pa, pb, pc, kind}: pk

def R.pa(r: R) -> String:
  match r:
    case R{pk, pa, pb, pc, kind}: pa

def R.pb(r: R) -> U32:
  match r:
    case R{pk, pa, pb, pc, kind}: pb

def R.pc(r: R) -> U32:
  match r:
    case R{pk, pa, pb, pc, kind}: pc

def R.kind(r: R) -> U32:
  match r:
    case R{pk, pa, pb, pc, kind}: kind

def r_pk(pk: U32, pa: String, +nm: String) -> Bool:""", "R accessors")

sub("field_def.fix_of(fd_find(fixed, fmt, nm), nm, hi, lo, fmt, encs, enums)",
    "field_def.fix_of(field_def.fd_find(fixed, fmt, nm), nm, hi, lo, fmt, encs, enums)",
    "renamed search")

sub("        case 1np: str_at(t, p)", "        case 1n+p: str_at(t, p)", "nat literal arm")
sub('String.repeat("0", pad_n(U32.sub(width, U32.to_nat(String.length(fixed_bits)))))',
    'String.repeat("0", pad_n(U32.to_nat(U32.sub(width, slen(fixed_bits)))))', "slen")
sub('String.take(s, U32.to_nat(U32.sub(String.length(s), String.length(p))))',
    'String.take(s, U32.to_nat(U32.sub(slen(s), slen(p))))', "slen")
sub('''      RS{out,
         Bool.pick(List<&2, Char>, rep.hit(oh, c), orest, Nil{}),
         Bool.pick(List<&2, Char>, rep.hit(oh, c), [c], Nil{}),
         old, new}''',
    '''      RS{Bool.pick(List<&2, Char>, rep.hit(oh, c), out, List.append(&2, Char, out, [c])),
         Bool.pick(List<&2, Char>, rep.hit(oh, c), orest, Nil{}),
         Bool.pick(List<&2, Char>, rep.hit(oh, c), [c], Nil{}),
         old, new}''',
    "THE BUG: a non-matching char is literal text and was being dropped")

for _T in ("Fld", "OP", "EC", "EO", "FB", "OI", "String", "TY"):
    sub("List.sort(&2, %s, " % _T, "List.sort(%s, " % _T, "List.sort arity")



# the closing brace of FMT_BITS is emitted by `tail`, not by the fold
sub("""def write_common.fmt_bits(fbs: List<&2, FB>) -> List<&2, String>:
  List.append(&2, String, write_common.fmt_bits.go(fbs, Nil{}), ["}"])""",
    """def write_common.fmt_bits(fbs: List<&2, FB>) -> List<&2, String>:
  write_common.fmt_bits.go(fbs, Nil{})""", "FMT_BITS closing brace emitted twice")



# --------------------------------------------------- 7. enum value-cell indent
sub("""        [OP.nm(o) ++ op_msuf(fmt, OP.op(o)) ++ " = " ++ U32.show(OP.op(o))]))

def write_enum.aliases.go""",
    """        ["  " ++ OP.nm(o) ++ op_msuf(fmt, OP.op(o)) ++ " = " ++ U32.show(OP.op(o))]))

def write_enum.aliases.go""", "every enum member is INDENTED two spaces")


def main(path):
    p = pathlib.Path(path)
    s = p.read_text()
    missing = []
    for old, new, why in SUBS:
        if new and new in s:
            continue            # already applied: idempotent by construction
        if old not in s:
            missing.append((why, old.split("\n")[0][:70]))
            continue
        s = s.replace(old, new, 1)
    if missing:
        for why, head in missing:
            print("MISSING (%s): %s" % (why, head))
        sys.exit("%d substitutions did not apply" % len(missing))
    # AFTER the substitutions, not before: a substituted block may still contain
    # `case o <> t:`, and rewriting it first is what made two of them unmatchable.
    s = re.sub(r"(?<![.\w])op\(", "OP.of(", s)
    for old, new in (("case o <> t:", "case +o <> t:"), ("case e <> t:", "case +e <> t:"),
                     ("case k <> r:", "case +k <> r:"), ("case k <> t:", "case +k <> t:"),
                     ("case e <> r:", "case +e <> r:"), ("case h <> t:", "case +h <> t:"),
                     ("case y <> t:", "case +y <> t:"), ("case oh <> orest:", "case +oh <> +orest:"),
                     ("case nh <> nr:", "case +nh <> +nr:"), ("case c <> rest:", "case +c <> +rest:"),
                     ("case f <> t:", "case +f <> +t:"), ("case t <> rest:", "case +t <> +rest:")):
        s = s.replace(old, new)
    p.write_text(s)
    print("applied %d substitutions" % len(SUBS))


if __name__ == "__main__":
    main(sys.argv[1])