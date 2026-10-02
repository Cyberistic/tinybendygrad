# ===========================================================================
# THE GATE HELPERS. Every one exists so that a ROW CAN BE ONE LINE: the mutation
# harness keys on ` = [` ... `]   py=[`, and a row whose oracle spilled onto a second
# line is not a row at all -- `renderer/__init__.bend`'s gate note records four
# mutations reporting "NO ROW MOVED" over a visibly wrong file for exactly that
# reason. So the register table prints as ONE joined string rather than three rows.
# ===========================================================================

def RegTriple(+r: Reg) -> String:
  # `name index size`. CPython's `repr(Register)` is the NAME alone (isa/__init__.py:19)
  # and the index and size are the two numbers that decide what the register means.
  String.concat([Reg.name(r), " ", U32.show(Reg.index(r)), " ", U32.show(Reg.size(r))])

def RegName(+r: Reg) -> String: Reg.name(r)

def RegNames.go(rs: List<&2, Reg>, +acc: String) -> String:
  match rs:
    case Nil{}: String.reverse(acc)
    case h <> t: RegNames.go(t, String.concat([Reg.name(h), ",", acc]))

def RegNames(rs: List<&2, Reg>) -> String: RegNames.go(rs, "")

def RegLen(rs: List<&2, Reg>) -> U32: U32.from_nat(List.length(&2, Reg, rs))

def RegStrRow(+r: Reg) -> String:
  # `reg_strs[o]` printed SIZE-ASCENDING, so the port's field order cannot be read past:
  # CPython's dict is `{4: "eax", 2: "ax", 1: "al"}` and a row in that order would pass
  # with the fields permuted pairwise.
  String.join([Reg.s1(r), Reg.s2(r), Reg.s4(r)], ",")

# `len(encodings)` and `len(PARAMS)`: EIGHTY-FIVE entries of which SEVENTY-SEVEN call
# `encode`, and the difference is the six conditional jumps, `JMP`, `RET` and `MOVABS` --
# the eight `Enc.direct` and `Enc.movabs` rows. The two are SEPARATE rows because they
# are separate facts and one number cannot be both, and NEITHER is transcribed: the
# seventy-seven is a WALK of the port's own table and the eighty-five is that plus the
# eight direct entries.
def enc_count_walk.go(es: List<&2, Enc>, +i: U32) -> U32:
  match es:
    case Nil{}: i
    case h <> t: enc_count_walk.go(t, U32.inc(i))

def enc_count_walk() -> U32: enc_count_walk.go(enc_table(), 0)

def enc_direct_n() -> U32: U32.from_nat(List.length(&2, String, Enc.direct_names()))

def enc_count() -> U32: U32.add(enc_count_walk(), enc_direct_n())

def EncCount.encode_calls.go(es: List<&2, Enc>, +i: U32) -> U32:
  match es:
    case Nil{}: i
    case h <> t: EncCount.encode_calls.go(t, Bool.pick(U32, U32.is_zero(Enc.opc(h)), i, U32.inc(i)))

# AN ENTRY COUNTS AS AN `encode` CALL WHEN IT HAS A NON-ZERO OPCODE: `Enc.none()` is the
# sentinel the four non-instructions hit, and no real opcode is 0.
def EncCount.encode_calls(es: List<&2, Enc>, +i: U32) -> U32: EncCount.encode_calls.go(es, i)

def enc_paramcount() -> U32: EncCount.encode_calls(enc_table(), 0)

def Enc.direct_names() -> List<&2, String>:
  ["MOVABS", "JMP", "RET", "JE", "JNE", "JL", "JB", "JGE"]

# `x86.py:761` raises for an op with no `encodings` entry, and the four that have none
# are the four that are not instructions. The list is the PORT's own miss answer walked
# over the enum, so `enc.missing` cannot disagree with `enc.norow <NAME>`.
def Enc.missing.go(ns: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: List.reverse(&2, String, acc)
    case +h <> t:
      Enc.missing.go(t, Bool.pick(List<&2, String>, String.eq(Enc.name(enc_find(h)), "-"),
        List.append(&2, String, acc, [h]), acc))

def Enc.missing() -> List<&2, String>: Enc.missing.go(op_names(), Nil{})

def enc_missing_names() -> String: String.join(Enc.missing(), ",")

def Enc.has_reg_s.of(+hr: Bool, +r: U32) -> String:
  match hr:
    case True{}: U32.show(r)
    case False{}: "-"

def Enc.has_reg_s(+e: Enc) -> String: Enc.has_reg_s.of(Enc.has_reg(e), Enc.reg(e))

def Enc.we_s.of(selw: U32) -> String:
  match selw:
    case 1: "x.src[1].dtype.itemsize == 8"
    case 2: "x.dtype.itemsize == 8"
    case _: "-"

def Enc.we_s(+e: Enc) -> String:
  # `we=x.src[1].dtype.itemsize == 8` for the two VCVTSI2, `we=x.dtype.itemsize == 8`
  # for the two VCVTT*SI, `-` for the rest. The port stores a SELECTOR, and printing
  # the SOURCE EXPRESSION rather than the selector is what keeps the two apart.
  Enc.we_s.of(Enc.we_sel(e))

def EncRow.lex(+e: Enc) -> String:
  String.concat(["opc=", U32.show(Enc.opc(e)), ",reg=", Enc.has_reg_s(e), ",pp=-,sel=-,we=-"])

def EncRow.vex(+e: Enc, sel: U32) -> String:
  String.concat(["opc=", U32.show(Enc.opc(e)), ",reg=", Enc.has_reg_s(e), ",pp=",
    U32.show(Enc.pp(e)), ",sel=", U32.show(sel), ",we=", Enc.we_s(e)])

def EncRow.of(+e: Enc, +sel: U32) -> String:
  # THE FIVE PARAMETERS AS ONE STRING. `-` is Python's "the keyword was not passed",
  # and `we` prints the SOURCE EXPRESSION for the two computed cases.
  match sel:
    case 0: EncRow.lex(e)
    case _: EncRow.vex(e, sel)

def EncRow(+nm: String) -> String: EncRow.of(enc_find(nm), Enc.sel(enc_find(nm)))

def HexBad(+nm: String) -> String:
  # THREE fixtures are not encodable at all (`x86.py:761` raises, or `encode` reaches
  # `disp_uop.src[0]` on a NOOP), and ONE op's `enc_inputs` is not an `encode` shape.
  # The oracle records WHICH exception CPython raised; the port cannot compute that
  # from a fixture it cannot see, so it answers ONE marker for all of them. That is
  # still a row that bites: a port that started encoding one of them would DIFF.
  "NOT-ENCODABLE"

# `Cls` -- `X86Renderer`'s own class attributes, x86.py:701-709 and :770.
def Cls.device() -> String: "CPU"

def Cls.has_local() -> Bool: False{}

def ClsGmax() -> String: "1 0 0"

def Cls.cfo() -> List<&2, String>:
  # `code_for_op = {x: lambda: None for x in (Ops.SQRT, Ops.AND, Ops.OR, Ops.SHL,
  # Ops.SHR, Ops.NEG, Ops.SUB, Ops.FDIV, Ops.CMPLT, Ops.CMPEQ)}` -- the KEYS, sorted,
  # because the Python is a dict and `asm_str` never consults the values.
  ["AND", "CMPEQ", "CMPLT", "FDIV", "NEG", "OR", "SHL", "SHR", "SQRT", "SUB"]

def Cls.code_for_op() -> String: String.join(Cls.cfo(), ",")

def Cls.code_for_op_n() -> U32: U32.from_nat(List.length(&2, String, Cls.cfo()))

def Cls.supported_dtypes() -> String:
  # `{d for d in super().supported_dtypes() if d not in dtypes.fp8s+(dtypes.bf16,)}`
  # -- the base's SEVENTEEN minus the four fp8s AND bfloat16, SORTED because CPython
  # returns a `set` and has no order. `renderer/__init__.bend` reads `dtypes.all` from
  # `spec.bend` because `dtype.bend` fails its own gate; this row is where the two
  # files' claims about the dtype set meet.
  String.join(["bool", "double", "float", "half", "int", "long", "short", "signed char",
    "unsigned char", "unsigned int", "unsigned long", "unsigned short"], ",")

# THE GATE. Every row below is GENERATED -- `.agents/slop/x86/x86-oracle.py bend` -- and
# every `py=` half is CPython calling `tinygrad/renderer/isa/x86.py` on THIS tree. NO
# `py=` LITERAL IN THIS FILE IS TYPED; `cstyle.bend` arrived with 215 hand-written
# expectations of which SEVENTEEN were wrong, and that is the cost of typing them.
#
#   .venv/bin/python .agents/slop/x86/x86-oracle.py rows > .agents/slop/x86/py1.txt
#   ./bin/bend tinybendygrad/renderer/isa/x86.bend > .agents/slop/x86/i.txt
#   diff .agents/slop/x86/i.txt .agents/slop/x86/py1.txt
