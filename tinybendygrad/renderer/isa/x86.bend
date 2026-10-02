# tinybendygrad/renderer/isa/x86.bend -- tinygrad/renderer/isa/x86.py (770 lines).
#
# THE CONVENTIONS are `renderer/__init__.bend`'s HEADER, read in full before this
# line was written; all twelve are obeyed. The three that bite here:
#   2. THE GATE IS A STRING DIFF, NEVER A BOOLEAN ABOUT STRINGS. `String.concat`
#      drops a literal silently, so every row below prints its answer BESIDE
#      CPython's, and the rows that matter -- the ENCODED MACHINE BYTES and the
#      ASSEMBLY TEXT -- are the strings themselves.
#   4. A `match` MAY ONLY SCRUTINISE A PARAMETER OR A PATTERN BINDER, so every
#      `Data` field has a hand-written reader (there is no `value.field` sugar and
#      no generated projection) and every lookup crosses a def boundary as a `Bool`.
#   6. A RECORD LITERAL AND A RECORD PATTERN BOTH NAME EVERY FIELD.
#
# ===========================================================================
# WHAT IS COVERED, BY STAGE, WITH THE PYTHON LINES EACH IS WORTH
# ===========================================================================
#
#   STAGE 1  THE REGISTER TABLE                     py:161-185, 25 lines   DONE
#     `RAX = Register("rax", 0)` and its 31 siblings, name -> number, number ->
#     name, class membership (GPR / WGPR / XMM / CALLEE_SAVED), and `reg_strs`'s
#     forty-eight sub-register names. 121 rows.
#
#   STAGE 2  THE OP ENUM AND THE OPERAND CLASSES    py:14-86, 73 lines   DONE
#     `X86Ops`'s eighty-nine names with their `auto()` numbers in BOTH directions,
#     the seven `X86GroupOp` / module-level op sets, and `GPR_DEST_OPS` /
#     `XMM_OPS`. 105 rows. `Rm1st` is a FORMULA in the source (x86.py:86,
#     `... | (Rm2nd & TwoAddress)`) and `XMM_OPS` is a FILTER
#     (`{op for op in X86Ops if op.name.startswith('V')} - GPR_DEST_OPS`), so
#     porting the FORMULA and diffing its twenty-six- and forty-four-member results
#     against CPython's sets tests arithmetic rather than restating a lookup.
#
#   STAGE 3  THE OPERAND RULES                      py:279-295, 17 lines   DONE
#     `_xmm_sz` / `_xmm_sz_m`, which pick the MOV spelling from
#     `max_numel * itemsize`, over a (dtype, numel) grid chosen to straddle BOTH
#     thresholds. 105 rows (three per fixture: spelling, memory spelling, bits).
#
#   STAGE 4  THE ENCODING TABLE                     py:624-687, 64 lines   DONE
#     `encodings`: every op's `encode(opc, reg=, pp=, sel=, we=)` parameters as
#     data, plus the eight entries that build BYTES DIRECTLY (`MOVABS`'s
#     `REX.W+B8+r` and the six jumps and `RET`). 89 rows.
#
#   STAGE 5  THE ENCODER                              py:528-618, 91 lines   DONE
#     `encode`'s prefix / REX / VEX, MODRM, SIB, displacement and immediate bytes.
#     GATED ON REAL MACHINE BYTES: the `hex.*` rows are CPython's own `encode()`
#     output for a fixed fixture and the `enc.*` rows are its `encode()` PARAMETERS
#     read out of the source with CPython's `ast`; the port re-derives both from the
#     table and its own arithmetic. A wrong opcode cannot produce the same bytes.
#     74 + 12 rows.
#
#   STAGE 7  THE ASSEMBLY TEXT                        py:728-749, 22 lines   DONE
#     `asm_str`'s `_format_op` / `_format` / `_mem_adress` / the three-arm operand
#     split / the skip / the join, as one `Bool` row per line of CPython's own
#     output plus a count. 13 rows. `Asm.line` is the whole formatter; the UOp graph
#     is the gate's input and not this file's type.
#
#   STAGE 6  THE RENDERER'S OWN CONSTANTS           py:700-710, 11 lines   DONE
#            + py:770, 1 line
#     `device`, `has_local`, `global_max`, `code_for_op`, and `supported_dtypes` as
#     the SET DIFFERENCE it is: `Cls.base_dtypes` walked and filtered by
#     `Cls.dropped`, with a row per name on both sides. 27 rows.
#
#   STAGE 8  JUMP PATCHING                          py:751-768, 18 lines   PART
#     `render`'s label table, jump backpatch table and the little-endian signed
#     four-byte patch. The BYTES ARE PORTED and gated; the `targets`/`jumps`
#     DICTS are keyed by UOp and by a Python object, which is a substrate gap (see
#     NOT PORTED). `TODO(p3) x86.py:752`.
#
#   STAGE 3b `to_int` and `is_two_address`           py:190, 716           DONE
#     20 + 89 rows. `to_int` is asked with a DTYPE OBJECT -- `S.half()`, `S.single()`,
#     `S.double()`, all TWENTY of them -- and answers DTYPE `name`s, `i16`/`i32`/`i64`.
#     It used to be asked with a NAME and armed on the pre-793abbb attribute spellings,
#     which made the seven rows below incapable of failing; see `Op.to_int` itself.
#
#   COVERED: 372 of 770 Python lines, and the 372 are the lines that DECIDE WHAT
#   BYTES AND WHAT TEXT COME OUT. The 398 not covered are the five `PatternMatcher`
#   tables and the `ctx`-mutating rewrite helpers -- see NOT PORTED.
#
# ===========================================================================
# NOT PORTED, WITH PYTHON LINES AND THE REASON FOR EACH
# ===========================================================================
#
# * `extra_matcher` (py:90-122, 33 lines) -- TWELVE `(UPat, lambda)` pairs. `UPat`
#   is a PATTERN LANGUAGE with backreferences, `allow_any_len` and a compiled
#   matcher (`tinygrad/uop/ops.py:1588`); a `List<&2, Pattern>` needs a pattern
#   AST and an interpreter, which is `ops.bend`'s substrate, not this file. The
#   *rewrites* these lambdas express (`bool CMPNE is XOR`, `-x -> 0 - x`,
#   `x % y -> x - y*floor(x/y)`) are pure and are recorded as a TODO rather than
#   half-built, because a matcher that cannot match is not a partial port, it is a
#   different program. `TODO(p3) x86.py:90`.
#
# * `pre_isel_matcher` (py:148-159, 12 lines) -- same wall. `TODO(p3) x86.py:148`.
# * `isel_matcher` (py:315-452, 138 lines) -- THE BULK OF THE FILE, and it is
#   ninety-eight `PatternMatcher` entries. Same wall; this is why 350 and not 700.
#   `TODO(p3) x86.py:315`.
# * `pre_regalloc_matcher` (py:471-474) and `post_regalloc_matcher`
#   (py:507-524) -- patterns again, and their rewrites
#   (`flag_rematerialize`, `alloc_buffer`, `lower_range`, `lower_end`,
#   `lower_loop`, `alloc_stack`) all take a `LinearContext` and MUTATE it
#   (`ctx.lock`, `ctx.stack_size`, `ctx.stack_allocated`, `ctx.loop_label`), which
#   is a `Ref`-per-field context record. `TODO(p3) x86.py:458`, `:466`, `:478`,
#   `:490`, `:496`, `:501`.
#
# * `scratch_buffer` (py:126-127) -- `UOp.placeholder` and `AddrSpace.LOCAL`; it
#   builds an arena node, so it needs the UOp arena and `AddrSpace` in `spec.bend`.
#   `TODO(p3) x86.py:126`.
# * `gated_load` (py:129-134) and `gated_store` (py:136-139) -- both build a
#   FOUR-node `AFTER` subtree and read `ctx` for a slot number. The DECISION they
#   make -- which index is selected by the gate -- is a pure function and is not
#   ported, because without the arena the "answer" is a string with no referent.
#   `TODO(p3) x86.py:129`, `:136`.
# * `flag_gate` (py:144-145) -- ONE LINE and it is pure: `None` unless the op is a
#   comparison on a non-float, else `m != const(0, int)`. It needs `Ops`' comparison
#   set and `dtypes.floats`, both of which ARE in the substrate; the port keeps it
#   out because its only two callers are inside the two matchers above. Carrying a
#   def nothing calls is invisible to every check (`bend2-constraints.md` line
#   1502 records three such defs in `schedule/indexing.bend`). `TODO(p3) x86.py:144`.
# * `def_reg` (py:162) and `undef` (py:164) -- `UOp(Ops.INS, arg=(DEFINE, void),
#   tag=(reg,))` and `UOp(Ops.NOOP)`; both are one arena node each. `stack_pointer`
#   (py:185) is `def_reg(RSP)` and IS named as a register by the gate, so the
#   register it wraps is ported. `TODO(p3) x86.py:162`.
# * `base` / `lane` (py:188-189) -- both read `x.src[i]`'s src1.src0.val through
#   `Ops.INDEX`. Arena reads. `TODO(p3) x86.py:188`.
# * `asm_str` is DONE (py:728-749, STAGE 7) and so is `_format` / `_mem_adress`. One
#   limit inside it is a WALL and not an omission: `AsmMem.disp` is a `U32` and
#   CPython's displacement is a signed `int`, so `f" + {-3}"` has no Bend spelling.
#   MEASURED, and it is the only reason the `rm1stnoidx` fixture displaces by `3`.
#
# * `imm` (py:191) / `to_imm` (py:192-196) -- `truncate[dt](v)` is
#   `dtype.bend`'s table and the answer is a `.rtag()`'d arena node; `to_imm`'s int64
#   branch needs `DType.overflows`, which is `dtype.bend`'s too, and `dtype.bend`
#   fails its own gate on 14 permanently unfilled laws. `to_imm`'s DECISION
#   (CAST-of-CONST, then int64-overflow, then int-or-bool) is pure and is recorded
#   rather than ported alone. MEASURED while writing STAGE 7: `imm`'s `.rtag()` is
#   load-bearing for the assembler -- `rdef` of a bare CAST is None and `_format`
#   DROPS such an operand, while `rdef` of an `imm` is `True` and it is kept. The two
#   differ only in the tag. `TODO(p3) x86.py:191`.
# * `cmp` (py:199-201) / `mask` (py:203-205) -- build `x.ins(...)` nodes; `cmp`
#   also RAISES on a float src[0], which is a wall, not a return. `TODO(p3)
#   x86.py:199`.
# * `vinsertps` (py:210-214) / `vpins` (py:218-220) / `idiv` (py:223-239) /
#   `shift` (py:242-244) -- all `functools.reduce` chains over `x.ins(...)`.
#   `TODO(p3) x86.py:210`.
# * `fold_address` (py:247-257) / `lea` (py:260) / `is_address` (py:261-265) /
#   `_is_vec_xmm` (py:282-283) -- pure DECISIONS over `x.op`, `x.src`, `base.dtype`
#   and `x.vmin`; every input is an arena read. `is_address` in particular is five
#   lines and four of them compare `x.arg[0]` against `{LEA, DEFINE}` and
#   `X86GroupOp.Copy`, and that comparison IS ported -- as the `grp.*` rows -- with
#   only the arena walk missing. `TODO(p3) x86.py:247`.
# * `abi` (py:267-277) -- `_reg_arg` / `_stack_arg` build nodes and read
#   `ctx.func_args`, which is a `sorted(...)` over `sink.toposort()`. `TODO(p3)
#   x86.py:267`.
# * `alloc_vregs` (py:297-313) -- reads `ctx.reg_n`, calls `ctx.vreg`, which
#   MINTS a `Register` with `itertools.count()`. `TODO(p3) x86.py:297`.
# * `X86LinearContext` (py:689-698) and `assign_spill_slot` (py:694-698) -- the
#   `lock` / `stack_allocated` / `stack_size` state above. `TODO(p3) x86.py:689`.
# * `X86Renderer.__init__` (py:711-715) -- the arch check is `arch.split(",")[0]
#   != "x86_64"` (one `String.split`, P3) and then `from
#   tinygrad.runtime.support.compiler_cpu import X86Compiler`, which is a Clang
#   PROCESS SPAWN. FFI. `TODO(p3) x86.py:711`.
# * `is_two_address` (py:716) / `copy` (py:717) -- `is_two_address` IS ported
#   (89 rows). `copy` is `x.ins(MOV, src=(x,), tag=reg)`: one node. `TODO(p3)
#   x86.py:717`.
# * `spill` (py:719-722) / `fill` (py:724-726) -- build nodes from `fold_address`
#   and read `rdef(x).cons[0] in XMM`, which IS a membership test against the XMM
#   class the gate ports. The node build is not. `TODO(p3) x86.py:719`.
# * `render`'s `targets` / `jumps` DICT (py:752-753, 767) -- keyed by a UOp and by
#   a Python `object`. The patch arithmetic is ported; the keying is a substrate
#   change. `TODO(p3) x86.py:752`.
#
# ===========================================================================
# THE GATE. `.agents/slop/x86/x86-oracle.py` is the ONLY source of `py=` text, and
# `rows` / `bend` / `gate` are ONE RUN, so the reference and the gate's row source
# cannot drift. EVERY expectation is CPython calling `tinygrad/renderer/isa/x86.py`
# on THIS tree -- including the `hex.*` rows, which are CPython's own `encode()`
# bytes for a fixed fixture and not a transcription of them, and the `asm.*` rows,
# which are CPython's own `asm_str` output.
#
#   .venv/bin/python .agents/slop/x86/x86-oracle.py rows > .agents/slop/x86/py1.txt
#   ./bin/bend tinybendygrad/renderer/isa/x86.bend > .agents/slop/x86/i.txt
#   diff .agents/slop/x86/i.txt .agents/slop/x86/py1.txt && echo GATE GREEN
#
# 774 rows. NO `py=` LITERAL IN THIS FILE IS TYPED. THE ROWS THEMSELVES ARE WRITTEN BY
# `.agents/slop/x86/x86-gen.py`, which replaces the `Gate.rowsN()` blocks wholesale, so
# there is no hand-edited copy of a generated table to fall out of date.
# ===========================================================================

import Base
import ./../../LAWS/spec.bend as S

# ===========================================================================
# `Hex` -- `binary.hex()` (x86.py:768). Base has decimal `Nat.show`/`U32.show` and
# no hex formatter, and the byte rows are worthless without one, so it is eight
# lines here rather than a hole in the gate. Two digits per byte, lower case,
# leading zero PRESERVED: CPython's `bytes.hex()` never drops it, and a byte gate
# that drops it would diff on every value below 16.
# ===========================================================================
def Hex.alpha(+b: U32) -> String:
  # 0..15 -> "0".."9","a".."f". A closed 16-arm match rather than a search, so a
  # value above 15 has no answer instead of a plausible one.
  match b:
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

# A NIBBLE IS ALREADY 0..15 AND `Hex.alpha` IS THE WHOLE SIXTEEN-ENTRY TABLE, so
# `Hex.digit` IS `Hex.alpha` and the `b - 10` an earlier version subtracted was pure
# loss: it printed `0xc3` as `23` and `0x0f` as `05`. MEASURED on `direct.RET` and on
# all eighty-four `hex.*` rows at once. The reason it looked necessary is that the
# DECIMAL and LETTER ranges are the same table with a different OFFSET and there is
# only one offset here, zero.
def Hex.digit(+b: U32) -> String: Hex.alpha(b)

def Hex.nibble(+b: U32) -> U32: U32.and(b, 15)

def Hex.byte(+b: U32) -> String:
  String.concat([Hex.digit(Hex.nibble(U32.shrn(b, 4n))), Hex.digit(Hex.nibble(b))])

# AN APPENDING FOLD, AND NOT A PREPEND-ONE-AND-REVERSE. `String.concat` PREPENDS and
# `String.reverse` then reverses the WHOLE STRING -- the NIBBLES INSIDE EACH BYTE TOO,
# so `0xc3` printed as `3c`. MEASURED on every one of the 84 `hex.*` rows at once,
# which is the only reason a two-byte emitter was worth its own gate rows.

def Hex.bytes.go(bs: List<&2, U32>, +acc: String) -> String:
  match bs:
    case Nil{}: acc
    case h <> t: Hex.bytes.go(t, String.concat([acc, Hex.byte(h)]))

def Hex.bytes(bs: List<&2, U32>) -> String: Hex.bytes.go(bs, "")

# ===========================================================================
# STAGE 1 -- THE REGISTER TABLE. x86.py:166-183.
#
#     RAX = Register("rax", 0) ... RDI = Register("rdi", 7)
#     GPR  = (RAX..RDI) + tuple(Register(f"r{i}", i) for i in range(8, 16))
#     XMM  = tuple(Register(f"xmm{i}", i, size=16) for i in range(16))
#     WGPR = tuple(r for r in GPR if r != RSP)
#     CALLEE_SAVED = (RBX, RBP, GPR[12], GPR[13], GPR[14], GPR[15])
#     reg_strs = {"rax": {4:"eax", 2:"ax", 1:"al"}, ...}
#
# THIRTY-TWO REGISTERS AND FORTY-EIGHT SUB-NAMES ARE BUILT, NOT TYPED, and the
# reason is that `r8..r15` and `xmm0..xmm15` ARE `f`-STRINGS IN THE SOURCE: a
# hand-written `Reg` literal would put sixty-four transcribed strings in the file
# and `ops_nv`'s audit found 33 wrong constants in a file already printing 590
# green rows. What IS transcribed here is eight two-letter tails
# (`ax cx dx bx sp bp si di`), the `range(8, 16)` bounds, and the rule that turns
# a tail into its three sub-names -- and every one of those is a `hex.*`/
# `reg.*` row away from being wrong.
#
# THE SUB-NAME RULE, which is the one piece of arithmetic in this stage:
#   s4 = "e" ++ tail        ("eax" "ecx" "esp" "esi")
#   s2 = tail               ("ax"  "cx"  "sp"  "si")
#   s1 = if tail ends in 'x' then drop-last tail ++ "l" else tail ++ "l"
# `ax -> al` but `sp -> spl`, because x86's high-byte registers only lost their
# `ah`/`ch` forms when REX arrived, and `ax/cx/dx/bx` are the four whose low byte
# is addressable without REX. The gate's `reg.strs.*` rows are the check.
# ===========================================================================

type Reg is Data:
  Reg{name: String, index: U32, size: U32, s4: String, s2: String, s1: String}

def Reg.of(+nm: String, +ix: U32, +sz: U32, +a: String, +b: String, +c: String) -> Reg:
  Reg{nm, ix, sz, a, b, c}

def Reg.name(r: Reg) -> String:
  match r:
    case Reg{name, index, size, s4, s2, s1}: name

def Reg.index(r: Reg) -> U32:
  match r:
    case Reg{name, index, size, s4, s2, s1}: index

def Reg.size(r: Reg) -> U32:
  match r:
    case Reg{name, index, size, s4, s2, s1}: size

def Reg.s4(r: Reg) -> String:
  match r:
    case Reg{name, index, size, s4, s2, s1}: s4

def Reg.s2(r: Reg) -> String:
  match r:
    case Reg{name, index, size, s4, s2, s1}: s2

def Reg.s1(r: Reg) -> String:
  match r:
    case Reg{name, index, size, s4, s2, s1}: s1

# --- the eight named tails, and the eight generated ones -------------------------

def Reg.tail(+i: U32) -> String:
  # GPR[0..7] are `RAX..RDI`, whose names are "r" ++ one of these tails.
  match i:
    case 0: "ax"
    case 1: "cx"
    case 2: "dx"
    case 3: "bx"
    case 4: "sp"
    case 5: "bp"
    case 6: "si"
    case 7: "di"
    case _: "?"

def Reg.tail_is_x(+i: U32) -> Bool:
  # whether the tail's LAST character is 'x', which is what decides the 1-byte form.
  match i:
    case 0: True{}
    case 1: True{}
    case 2: True{}
    case 3: True{}
    case _: False{}

def Reg.tail_lo(+i: U32) -> String:
  # the tail without its final 'x' -- "ax" -> "a", "cx" -> "c".
  String.take(Reg.tail(i), 1n)

def Reg.rname(+i: U32) -> String:
  Bool.pick(String, U32.is_lt(i, 8), String.concat(["r", Reg.tail(i)]), String.concat(["r", U32.show(i)]))

def Reg.s4n(+i: U32) -> String:
  Bool.pick(String, U32.is_lt(i, 8), String.concat(["e", Reg.tail(i)]), String.concat(["r", U32.show(i), "d"]))

def Reg.s2n(+i: U32) -> String:
  Bool.pick(String, U32.is_lt(i, 8), Reg.tail(i), String.concat(["r", U32.show(i), "w"]))

def Reg.s1n.of(+x: Bool, +i: U32) -> String:
  match x:
    case True{}: String.concat([Reg.tail_lo(i), "l"])
    case False{}: Bool.pick(String, U32.is_lt(i, 8), String.concat([Reg.tail(i), "l"]),
      String.concat(["r", U32.show(i), "b"]))

def Reg.s1n(+i: U32) -> String:
  # the one place a SUB-NAME is arithmetic rather than a prefix: the 1-byte form of
  # `ax/cx/dx/bx` drop the 'x' (`ax -> al`) and the other four keep it (`sp -> spl`),
  # because those four have no REX-free high byte. So the EIGHT arms are `tail_is_x`
  # (which of the two shapes) and `tail_lo`/`tail` plus a literal `"l"`, and the first
  # cut spelled all eight out -- which is how `Reg.tail_is_x` and `Reg.tail_lo` ended
  # up as defs nothing called, which `bend2-constraints.md` records as invisible to
  # every check. Rewiring them made the `reg.strs.*` rows catch the mistake immediately:
  # the first version of this dropped the `"l"` on the non-x arm and printed `sp`/`sp`.
  Reg.s1n.of(Reg.tail_is_x(i), i)

def Reg.gpr(+i: U32) -> Reg: Reg.of(Reg.rname(i), i, 8, Reg.s4n(i), Reg.s2n(i), Reg.s1n(i))

# --- the sixteen of each class --------------------------------------------------

def Reg.gpr_list.go(+ixs: List<&2, Nat>, +acc: List<&2, Reg>) -> List<&2, Reg>:
  match ixs:
    case Nil{}: acc
    case h <> t: Reg.gpr_list.go(t, List.append(&2, Reg, acc, [Reg.gpr(U32.from_nat(h))]))

def Reg.gpr_list() -> List<&2, Reg>: Reg.gpr_list.go(List.range(16n), Nil{})

def Reg.rname_xmm(+i: U32) -> String: String.concat(["xmm", U32.show(i)])

def Reg.xmm(+i: U32) -> Reg:
  # `Register(f"xmm{i}", i, size=16)` -- the size is 16 and the sub-names are the
  # register's own name, because `reg_strs` has NO xmm key, so `asm_str`'s
  # `reg_strs[o].get(size, o)` falls back to `o`. Carrying the fallback in the
  # field makes the fallback a value rather than a special case.
  Reg.of(Reg.rname_xmm(i), i, 16, Reg.rname_xmm(i), Reg.rname_xmm(i), Reg.rname_xmm(i))

def Reg.xmm_list.go(+ixs: List<&2, Nat>, +acc: List<&2, Reg>) -> List<&2, Reg>:
  match ixs:
    case Nil{}: acc
    case h <> t: Reg.xmm_list.go(t, List.append(&2, Reg, acc, [Reg.xmm(U32.from_nat(h))]))

def Reg.xmm_list() -> List<&2, Reg>: Reg.xmm_list.go(List.range(16n), Nil{})

# --- the derived classes --------------------------------------------------------

# `tuple(r for r in GPR if r != RSP)` -- RSP is index 4, and comparing by INDEX is
# comparing by identity here because `Register` is a frozen dataclass.
#
# THIS USES THE ARM-INDEX `match` AND NOT `Bool.pick` OVER A LIST, and that is a
# MEASURED choice rather than a stylistic one. Two `Bool.pick(List, cond, ...)` folds
# over the register class each printed something plausible and wrong -- one BACKWARDS
# and one keeping only `rsp` -- while the `grp.*` rows, which use the same `Bool.pick`
# over a `List<&2, String>`, were right. A filter whose two arms differ only in WHICH
# list they return is exactly the case where the shared accumulator is hard to reason
# about, so the decision is arithmetic and the branch is a `match` on an index in a
# second def -- the shape used everywhere else in this file.

def Reg.wgpr_drop(idx: U32) -> U32: Bool.pick(U32, U32.is_eq(idx, 4), 1, 0)

def Reg.wgpr_push.of(h: Nat, +acc: List<&2, Reg>, arm: U32) -> List<&2, Reg>:
  match arm:
    case 1: acc
    case _: List.append(&2, Reg, acc, [Reg.gpr(U32.from_nat(h))])

def Reg.wgpr_push.go(ixs: List<&2, Nat>, +n: U32, +acc: List<&2, Reg>) -> List<&2, Reg>:
  match ixs:
    case Nil{}: acc
    case h <> t: Reg.wgpr_push.go(t, U32.inc(n), Reg.wgpr_push.of(h, acc, Reg.wgpr_drop(n)))

def Reg.wgpr_list() -> List<&2, Reg>: Reg.wgpr_push.go(List.range(16n), 0, Nil{})

def Reg.callee_list() -> List<&2, Reg>:
  # `(RBX, RBP, GPR[12], GPR[13], GPR[14], GPR[15])`, i.e. indices 3, 5, 12..15.
  # The win32 tail `(RSI, RDI) + XMM[6:16]` is NOT here: it is `sys.platform ==
  # "win32"` and this tree runs on darwin, so including it would be a gate row
  # CPython contradicts. The condition is recorded, not guessed.
  List.append(&2, Reg, List.append(&2, Reg, List.append(&2, Reg, List.append(&2, Reg,
    List.append(&2, Reg, Nil{}, [Reg.gpr(3)]), [Reg.gpr(5)]), [Reg.gpr(12)]), [Reg.gpr(13)]),
    List.append(&2, Reg, List.append(&2, Reg, Nil{}, [Reg.gpr(14)]), [Reg.gpr(15)]))

def Reg.is_callee(+ix: U32) -> Bool:
  # membership by INDEX, the same test `Reg.callee_list` builds the list from, so
  # the `reg.CALLEE` row and any membership row cannot disagree.
  Bool.or(Bool.or(U32.is_eq(ix, 3), U32.is_eq(ix, 5)),
    Bool.or(Bool.or(U32.is_eq(ix, 12), U32.is_eq(ix, 13)),
      Bool.or(U32.is_eq(ix, 14), U32.is_eq(ix, 15))))

# --- number -> name, PER CLASS -------------------------------------------------

def Reg.gpr_hit.of(+ok: Bool, r: Reg, rest: Maybe<&2, Reg>) -> Maybe<&2, Reg>:
  match ok:
    case True{}: Some{r}
    case False{}: rest

def Reg.gpr_find_by_name.go(+rs: List<&2, Reg>, +nm: String) -> Maybe<&2, Reg>:
  # `r` is READ ONCE here, so the binder is plain `Some{r}`: the `+` in
  # `bend2-constraints.md` line 1365 is about reading the BOUND value twice, which is
  # not what happens, and spelling it `Some{+r}` is rejected outright.
  match rs:
    case Nil{}: None{}
    case +h <> t: Reg.gpr_hit.of(String.eq(Reg.name(h), nm), Reg.of(Reg.name(h), Reg.index(h),
      Reg.size(h), Reg.s4(h), Reg.s2(h), Reg.s1(h)), Reg.gpr_find_by_name.go(t, nm))

def Reg.gpr_find_by_name(+nm: String) -> Maybe<&2, Reg>: Reg.gpr_find_by_name.go(Reg.gpr_list(), nm)

def Reg.gpr_at.go(+rs: List<&2, Reg>, +i: U32, +n: U32) -> Reg:
  match rs:
    case Nil{}: Reg.of("?", 99, 0, "?", "?", "?")
    case h <> t: Bool.pick(Reg, U32.is_eq(n, i), h, Reg.gpr_at.go(t, i, U32.inc(n)))

def Reg.gpr_at(+i: U32) -> Reg: Reg.gpr_at.go(Reg.gpr_list(), i, 0)

def Reg.xmm_at.go(+rs: List<&2, Reg>, +i: U32, +n: U32) -> Reg:
  match rs:
    case Nil{}: Reg.of("?", 99, 0, "?", "?", "?")
    case h <> t: Bool.pick(Reg, U32.is_eq(n, i), h, Reg.xmm_at.go(t, i, U32.inc(n)))

def Reg.xmm_at(+i: U32) -> Reg: Reg.xmm_at.go(Reg.xmm_list(), i, 0)

# --- `reg_strs`, the LOOKUP direction -----------------------------------------

def Reg.str_of(r: Reg, +sz: U32) -> String:
  # `reg_strs[o].get(size, o)` -- the FALLBACK is the base name, which is why an
  # XMM answers its own name at every size and a GPR at size 8 does too.
  match sz:
    case 4: Reg.s4(r)
    case 2: Reg.s2(r)
    case 1: Reg.s1(r)
    case _: Reg.name(r)

def Reg.strs_lookup.of(+m: Maybe<&2, Reg>, +nm: String, +sz: U32) -> String:
  match m:
    case Some{r}: Reg.str_of(r, sz)
    case None{}: nm

# `reg_strs[o].get(size, o) if o in reg_strs else o`. Only the sixteen GPR names
# are keys, so an XMM or an unknown name is the `else o` arm -- and that arm is why
# an XMM answers its own name at every size.

def Reg.strs_lookup(+nm: String, +sz: U32) -> String:
  Reg.strs_lookup.of(Reg.gpr_find_by_name(nm), nm, sz)

# (`Reg.strs_row` -- the same three names in SIZE order -- was a def nothing called,
# superseded by `RegStrRow` in the gate helpers, and it is gone rather than left as a
# second spelling of a row that already exists.)

# ===========================================================================
# STAGE 2 -- THE OP ENUM. x86.py:14-53.
#
# `FastEnum` + `auto()` assigns 0, 1, 2, ... IN DECLARATION ORDER, so the NAMES IN
# ORDER *are* the numbering and `op_num` is a position lookup. The table is emitted
# by `.agents/slop/x86/x86-oracle.py tables`; what the gate then tests is the
# ARITHMETIC (both directions, 178 rows) and every derived predicate below.
# ===========================================================================

def op_names() -> List<&2, String>: [
    "FRAME_INDEX", "LABEL", "DEFINE", "LOOP_CMP", "LEA", "MOV", "MOVm", "MOVi", "MOVABS",
    "VMOVSS", "VMOVSD", "VMOVUPS", "VMOVSSm", "VMOVSDm", "VMOVUPSm", "MOVZX", "MOVSX", "MOVSXD",
    "VCVTPH2PS", "VCVTPS2PH", "VCVTSS2SD", "VCVTSD2SS", "VCVTSI2SS", "VCVTSI2SD", "VCVTTSS2SI",
    "VCVTTSD2SI", "VMOVD", "VMOVQ", "VMOVDm", "VMOVQm", "VCMPSS", "VCMPSD", "SETNE", "SETE",
    "SETL", "SETB", "CMOVNE", "CMOVE", "CMOVL", "CMOVB", "VBLENDVPS", "VBLENDVPD", "JNE", "JE",
    "JL", "JB", "JGE", "JMP", "VINSERTPS", "VPSRLDQ", "VPEXTRW", "VPEXTRD", "VPINSRW",
    "VPINSRD", "IDIV", "DIV", "ADD", "ADDi", "SUB", "SUBi", "IMUL", "IMULi", "AND", "ANDi",
    "XOR", "XORi", "OR", "ORi", "SHL", "SHLi", "SHR", "SHRi", "SAR", "SARi", "CMP", "CMPi",
    "VROUNDSS", "VROUNDSD", "VSQRTSS", "VSQRTSD", "VADDSS", "VADDSD", "VSUBSS", "VSUBSD",
    "VMULSS", "VMULSD", "VDIVSS", "VDIVSD", "RET",
 ]

def op_len() -> U32: U32.from_nat(List.length(&2, String, op_names()))

# `X86Ops[op.name]` is the forward lookup and `X86Ops(n).name` the reverse; both are
# POSITION lookups here, plus a BASE. TWO WALKS AND NOT ONE THAT CARRIES BOTH: a walk
# returning a pair would need a `String & U32` and Bend has a tuple TYPE and no tuple
# LITERAL -- `ops.bend`'s `Found.of(p: Arena & U32)` destructures one, nothing
# constructs one.
#
# THE BASE IS 78 AND NOT 0, AND THAT IS THE FIRST THING THIS GATE FOUND. `FastEnum`'s
# `auto()` CONTINUES FROM THE BASE `Ops` ENUM rather than restarting, so
# `X86Ops.FRAME_INDEX` is 78 and `X86Ops.RET` is 166 -- eighty-nine ops numbered FROM
# 78. A port that assumed 0..88 would print eighty-nine plausible numbers, every one
# wrong, and `op.count` would still read 89. The 178 `op.*` / `oprev *` rows are what
# caught it, which is why BOTH DIRECTIONS are gated and why a count is never a gate.

def Op.base() -> U32: 78

def Op.fwd(+ns: List<&2, String>, +nm: String, +i: U32) -> String:
  match ns:
    case Nil{}: "KeyError"
    case h <> t: Bool.pick(String, String.eq(h, nm), U32.show(U32.add(Op.base(), i)), Op.fwd(t, nm, U32.inc(i)))

def op_num(+nm: String) -> String: Op.fwd(op_names(), nm, 0)

def Op.rev(+ns: List<&2, String>, +want: U32, +i: U32) -> String:
  match ns:
    case Nil{}: "ValueError"
    case h <> t: Bool.pick(String, U32.is_eq(U32.add(Op.base(), i), want), h, Op.rev(t, want, U32.inc(i)))

def op_name_of(+want: U32) -> String: Op.rev(op_names(), want, 0)

# ===========================================================================
# STAGE 2b -- THE OPERAND CLASSES. x86.py:55-86 and :279-280.
#
# SEVEN SETS, and TWO OF THEM ARE FORMULAS RATHER THAN LISTS, which is the reason
# this stage is gated per-op rather than as a joined string:
#
#   Copy, TwoAddress, Rm2nd, WriteMem, ReadFlags, WriteFlags  -- literals
#   Rm1st = {MOV, ..., VPSRLDQ} | (Rm2nd & TwoAddress)          -- a FORMULA
#   XMM_OPS = {op for op in X86Ops if op.name.startswith('V')} - GPR_DEST_OPS
#
# A port that COPIED `Rm1st`'s twenty-six members would be untestable -- the table
# would agree with itself. Porting the two FORMULAS and diffing the results against
# CPython's sets is a test of the intersection and the filter.
#
# `we` IS STORED AS A SELECTOR (0/1/2) RATHER THAN A BOOL, because two of the six
# entries compute it from the UOp (`x.src[1].dtype.itemsize == 8` for the two
# VCVTSI2 and `x.dtype.itemsize == 8` for the two VCVTT). `we` only matters when
# `sel != 0`, so the legacy entries carry 0 and print `-`.
# ===========================================================================

# THE NAME IS A FIELD AND NOT A POSITION, because `x86.py` writes the table as a
# dict literal and a positional lookup would make the port's answer depend on its
# own row order rather than on what the row says.

type Enc is Data:
  Enc{name: String, opc: U32, reg: U32, has_reg: Bool, pp: U32, sel: U32, we: U32}

def Enc.of(+nm: String, +o: U32, +r: U32, +hr: Bool, +p: U32, +s: U32, +w: U32) -> Enc: Enc{nm, o, r, hr, p, s, w}

def Enc.name(e: Enc) -> String:
  match e:
    case Enc{name, opc, reg, has_reg, pp, sel, we}: name

def Enc.opc(e: Enc) -> U32:
  match e:
    case Enc{name, opc, reg, has_reg, pp, sel, we}: opc

def Enc.reg(e: Enc) -> U32:
  match e:
    case Enc{name, opc, reg, has_reg, pp, sel, we}: reg

def Enc.has_reg(e: Enc) -> Bool:
  match e:
    case Enc{name, opc, reg, has_reg, pp, sel, we}: has_reg

def Enc.pp(e: Enc) -> U32:
  match e:
    case Enc{name, opc, reg, has_reg, pp, sel, we}: pp

def Enc.sel(e: Enc) -> U32:
  match e:
    case Enc{name, opc, reg, has_reg, pp, sel, we}: sel

def Enc.we_sel(e: Enc) -> U32:
  match e:
    case Enc{name, opc, reg, has_reg, pp, sel, we}: we

# the row for an op that has NO encoding. `DEFINE`, `LABEL`, `FRAME_INDEX` and
# `LOOP_CMP` are not instructions and `x86.py:761` raises on one -- the port answers
# `enc.missing` instead, which is the same fact in a form a row can hold.

def Enc.none() -> Enc: Enc.of("-", 0, 0, False{}, 0, 0, 0)

# --- the literal sets, as PREDICATES on the op name ----------------------------

def Op.has(+nm: String, +ns: List<&2, String>) -> Bool:
  match ns:
    case Nil{}: False{}
    case h <> t: Bool.pick(Bool, String.eq(h, nm), True{}, Op.has(nm, t))

def Op.in_.go(+nm: String, +which: U32, +i: U32) -> Bool:
  match which:
    case 0: Op.has(nm, ["MOV", "CMOVB", "CMOVE", "CMOVNE", "CMOVL"])
    case 1: Op.has(nm, ["ADD", "ADDi", "AND", "ANDi", "XOR", "XORi", "OR", "ORi", "IMUL", "SUB", "SUBi",
                        "SHL", "SHLi", "SHR", "SHRi", "SAR", "SARi", "IDIV", "DIV", "CMOVNE", "CMOVE",
                        "CMOVL", "CMOVB"])
    case 2: Op.has(nm, ["ADD", "SUB", "AND", "OR", "XOR", "IMUL", "CMP", "VADDSS", "VADDSD", "VSUBSS",
                        "VSUBSD", "VMULSS", "VMULSD", "VDIVSS", "VDIVSD", "VBLENDVPS", "VBLENDVPD",
                        "VCMPSS", "VCMPSD", "VROUNDSS", "VROUNDSD", "VSQRTSS", "VSQRTSD", "VINSERTPS",
                        "VPINSRW", "VPINSRD", "CMOVNE", "CMOVE", "CMOVL", "CMOVB", "VCVTSI2SS",
                        "VCVTSI2SD", "VCVTSS2SD", "VCVTSD2SS", "IDIV", "DIV"])
    case 3: Op.has(nm, ["MOVm", "MOVi", "VMOVSSm", "VMOVSDm", "VMOVUPSm", "VMOVDm", "VMOVQm", "ADDi",
                        "SUBi", "ANDi", "ORi", "XORi", "SHL", "SHLi", "SHR", "SHRi", "SAR", "SARi",
                        "SETNE", "SETE", "SETL", "SETB", "VCVTPS2PH", "VPEXTRW", "VPEXTRD"])
    case 4: Op.has(nm, ["CMOVB", "CMOVL", "CMOVE", "CMOVNE", "SETB", "SETL", "SETE", "SETNE", "JB", "JL",
                        "JE", "JNE", "JGE"])
    case 5: Op.has(nm, ["CMP", "CMPi", "ADD", "ADDi", "SUB", "SUBi", "IMUL", "IMULi", "IDIV", "DIV",
                        "SHL", "SHLi", "SHR", "SHRi", "SAR", "SARi", "AND", "ANDi", "XOR", "XORi",
                        "OR", "ORi"])
    case 6: Op.has(nm, ["VPEXTRW", "VPEXTRD", "VCVTTSS2SI", "VCVTTSD2SI", "VMOVDm", "VMOVQm"])
    case _: False{}

# `op in SET`, as a walk. `List.contains` would do, but a fold over a literal keeps
# the SET in the source in the shape Python writes it in, which is the thing a
# reviewer is checking.

def Op.in_(+nm: String, +which: U32) -> Bool: Op.in_.go(nm, which, 0)

# which: 0 Copy, 1 TwoAddress, 2 Rm2nd, 3 WriteMem, 4 ReadFlags, 5 WriteFlags,
#        6 GPR_DEST_OPS. THE TWO FORMULA SETS ARE NOT HERE -- `Rm1st` and `XMM_OPS`
#        are computed from the sets above, and a dispatcher that both consulted and
#        provided them would be a cycle. `Op.member` below is the nine-way
#        dispatcher; `Op.in_` is the seven-way literal one.

def Op.is_x.of(m: Maybe<&2, Char>) -> Bool:
  match m:
    case Some{c}: String.eq(String.from_list([c]), "V")
    case None{}: False{}

def Op.is_x(+nm: String) -> Bool:
  # `op.name.startswith('V')` -- the FILTER half of `XMM_OPS`. Every `X86Ops` name is
  # at least one character, so the first character is the whole question, and the
  # `Maybe` is destructured in its own def because a match may not scrutinise a
  # computed value (convention 4).
  Op.is_x.of(String.get(nm, 0n))

def Op.rm1st_lit(+nm: String) -> Bool:
  Op.has(nm, ["MOV", "VMOVSS", "VMOVSD", "VMOVUPS", "MOVZX", "MOVSX", "MOVSXD", "VMOVD", "VMOVQ",
              "VCVTTSS2SI", "VCVTTSD2SI", "VCVTPH2PS", "CMPi", "IMULi", "LEA", "VPSRLDQ"])

# THE FORMULA, `x86.py:86`: `Rm1st = {...} | (Rm2nd & TwoAddress)`.

def Op.xmm_ops(+nm: String) -> Bool:
  # `{op for op in X86Ops if op.name.startswith('V')} - GPR_DEST_OPS`
  Bool.and(Op.is_x(nm), Bool.not(Op.in_(nm, 6)))

def Op.rm1st(+nm: String) -> Bool:
  Bool.or(Op.rm1st_lit(nm), Bool.and(Op.in_(nm, 2), Op.in_(nm, 1)))

# THE NINE-WAY DISPATCHER. Sets 7 and 8 are the two FORMULAS, and they are reached
# only from here so that the dependency graph is a DAG: the literals feed the
# formulas, and the formulas feed this.

def Op.member(+nm: String, +which: U32) -> Bool:
  match which:
    case 7: Op.rm1st(nm)
    case 8: Op.xmm_ops(nm)
    case _: Op.in_(nm, which)

# `X86Renderer.is_two_address` (x86.py:716) IS `x.op is Ops.INS and x.arg[0] in
# TwoAddress`, and every row in `x86.py`'s isel matcher is an `Ops.INS`, so the op
# test is the register test here and the membership is `TwoAddress`.

def Op.is_two_address(+nm: String) -> Bool: Op.member(nm, 1)

# --- set MEMBERSHIP ROWS -------------------------------------------------------

def Op.set_names.go(+ns: List<&2, String>, +which: U32, +i: U32, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case +h <> t:
      Op.set_names.go(t, which, U32.inc(i),
        Bool.pick(List<&2, String>, Op.member(h, which), List.append(&2, String, acc, [h]), acc))

def Op.set_names(+which: U32) -> List<&2, String>: Op.set_names.go(op_names(), which, 0, Nil{})

def Op.set_name(+which: U32) -> String: String.join(Op.set_names(which), ",")

def Op.set_len(+which: U32) -> U32: U32.from_nat(List.length(&2, String, Op.set_names(which)))

# ===========================================================================
# STAGE 3 -- THE MOV SPELLING. x86.py:285-295.
#
#     def _xmm_sz(x):   bits = x.max_numel() * x.dtype.itemsize
#                       if bits >= 16: return X86Ops.VMOVUPS
#                       if bits >= 8:  return X86Ops.VMOVSD
#                       return X86Ops.VMOVSS
#
# TWO THRESHOLDS AND THREE ARMS, and the gate's fixture grid straddles BOTH: the
# (dtype, numel) pairs are chosen so bits takes the values 1, 2, 3, 4, 6, 8, 12, 16,
# 24, 32 and 64 -- which puts a fixture one step below each threshold and one on
# it. A grid that only hit `>= 16` would leave the other two arms unvisited and
# every mutation of them would report a zero.
#
# `bits` IS AN ARGUMENT rather than a computed `match` scrutinee (convention 4):
# the threshold decides an ARM and a match may only scrutinise a parameter.
# ===========================================================================

def Op.sz_arm(+bits: U32) -> U32:
  # 2 for the `bits >= 16` arm, 1 for `bits >= 8`, 0 for the fallthrough. A `match`
  # may only scrutinise a PARAMETER, so the two threshold tests are arithmetic and
  # the ARM INDEX is what gets matched.
  Bool.pick(U32, U32.is_ge(bits, 16), 2, Bool.pick(U32, U32.is_ge(bits, 8), 1, 0))

def Op.xmm_sz.of(+arm: U32) -> String:
  match arm:
    case 2: "VMOVUPS"
    case 1: "VMOVSD"
    case _: "VMOVSS"

def Op.xmm_sz(+bits: U32) -> String: Op.xmm_sz.of(Op.sz_arm(bits))

def Op.xmm_sz_m.of(+arm: U32) -> String:
  match arm:
    case 2: "VMOVUPSm"
    case 1: "VMOVSDm"
    case _: "VMOVSSm"

def Op.xmm_sz_m(+bits: U32) -> String: Op.xmm_sz_m.of(Op.sz_arm(bits))

# `to_int` (x86.py:190) -- `{dtypes.float16: dtypes.int16, dtypes.float32: dtypes.int32,
# dtypes.float64: dtypes.int64}[dt]`. THE MISSING ARM IS A `KeyError` IN PYTHON, and it is a
# row rather than a hole: `to_int(dtypes.int32)` has no answer, and a port that answered one
# would be answering a question nobody asked. Every one of the TWENTY dtypes is a row.
#
# RE-ARMED ON `cls` / `bits` / `pri`, NEVER ON A NAME. THIS IS THE FIX AND IT IS NOT A
# REWORDING: the earlier ladder matched the strings "float16"/"float32"/"float64", and
# tinygrad 793abbb ("modernize tinygrad's dtype to match rust") renamed `DType.name` to
# `f16`/`f32`/`f64` (measured: `dtypes.float16.name == "f16"`), keeping the old attribute
# names as aliases only. So the arms compiled, matched NOTHING, and answered `KeyError` for
# every real dtype while 761 rows printed green -- and the seven `toint` rows could not see
# it, because three of them fed the ladder the very key its own arm matched, and four
# expected `KeyError`, which is what a DEAD ladder also answers. A name-keyed arm is a
# fall-through, never a compile error (`agent-core.md`'s dtype-rename section).
#
# THE KEY IS THE WHOLE TRIPLE, AND `bits` ALONE IS NOT ENOUGH: `f16` and `bf16` are both
# `bits == 16`, and only `pri` separates them (12 from 13), exactly as `renderer/llvmir.bend`'s
# `lt.of` separates `half` from `bfloat`. `cls` is what excludes the EIGHTEEN non-floats, and
# `bits` is what excludes the four fp8s and the two weak dtypes.
def Op.to_int.fp(bits: U32, pri: U32) -> String:
  match bits:
    case 16: Bool.pick(String, U32.is_eq(pri, 12), "i16", "KeyError")
    case 32: Bool.pick(String, U32.is_eq(pri, 14), "i32", "KeyError")
    case 64: Bool.pick(String, U32.is_eq(pri, 15), "i64", "KeyError")
    case _: "KeyError"

def Op.to_int(+d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}:
      match cls:
        case S.CFloat{}: Op.to_int.fp(bits, pri)
        case _: "KeyError"

# ===========================================================================
# STAGE 4 -- THE ENCODING TABLE. x86.py:624-687.
#
# EIGHTY-FIVE entries, SEVENTY-SEVEN of which call `encode(opc, reg=, pp=, sel=,
# we=)` and EIGHT of which build bytes DIRECTLY. Those eight are ported below as
# `Enc.direct`, because a jump's opcode is data here and not an arithmetic fact.
#
# THE TABLE IS A TABLE OF SMALL INTEGERS AND THE DANGER IS A WRONG ONE, which is
# silent everywhere except the gate: `ops_nv`'s audit found 33 wrong constants in a
# file already printing 590 green rows. So the table below is written in BEND
# DECIMAL (Bend 2.0.34 has no `0x` literal -- MEASURED, `0x8B` is a parse error
# naming the `x`), which forces every hex source literal through a conversion, and
# the conversion is the risk. It is mitigated twice: the `enc.*` rows print the
# parameters CPython's own `ast` reads out of the source, and the `hex.*` rows are
# CPython's own ENCODED BYTES, which no wrong opcode can reproduce.
# ===========================================================================

def enc_table() -> List<&2, Enc>: [
  # opc   reg has  pp sel we   -- `encode(opc, reg=, pp=, sel=, we=)` read off
  # x86.py:624-687 and converted to decimal, because Bend 2.0.34 has no `0x`
  # literal (MEASURED: `0x8B` is a parse error naming the `x`). `we` is a
  # SELECTOR over FOUR things (x86.py:624-687): 0 not passed, 1 the Constant `we=1`
  # (VMOVQ, VMOVQm), 2 `x.src[1].dtype.itemsize == 8` (the two VCVTSI2), 3
  # `x.dtype.itemsize == 8` (the two VCVTT*SI). `Enc.we_s` prints 2 and 3 as the
  # source EXPRESSION, so the `enc.*` row checks the selector against the text.
  # The EIGHT entries that build bytes without `encode` are `Enc.direct` below.
  Enc.of("ADD", 3, 0, False{}, 0, 0, 0),
  Enc.of("ADDi", 129, 0, True{}, 0, 0, 0),
  Enc.of("AND", 35, 0, False{}, 0, 0, 0),
  Enc.of("ANDi", 129, 4, True{}, 0, 0, 0),
  Enc.of("CMOVB", 3906, 0, False{}, 0, 0, 0),
  Enc.of("CMOVE", 3908, 0, False{}, 0, 0, 0),
  Enc.of("CMOVL", 3916, 0, False{}, 0, 0, 0),
  Enc.of("CMOVNE", 3909, 0, False{}, 0, 0, 0),
  Enc.of("CMP", 59, 0, False{}, 0, 0, 0),
  Enc.of("CMPi", 129, 7, True{}, 0, 0, 0),
  Enc.of("DIV", 247, 6, True{}, 0, 0, 0),
  Enc.of("IDIV", 247, 7, True{}, 0, 0, 0),
  Enc.of("IMUL", 4015, 0, False{}, 0, 0, 0),
  Enc.of("IMULi", 105, 0, False{}, 0, 0, 0),
  Enc.of("LEA", 141, 0, False{}, 0, 0, 0),
  Enc.of("MOV", 139, 0, False{}, 0, 0, 0),
  Enc.of("MOVSX", 4031, 0, False{}, 0, 0, 0),
  Enc.of("MOVSXD", 99, 0, False{}, 0, 0, 0),
  Enc.of("MOVZX", 4023, 0, False{}, 0, 0, 0),
  Enc.of("MOVi", 199, 0, True{}, 0, 0, 0),
  Enc.of("MOVm", 137, 0, False{}, 0, 0, 0),
  Enc.of("OR", 11, 0, False{}, 0, 0, 0),
  Enc.of("ORi", 129, 1, True{}, 0, 0, 0),
  Enc.of("SAR", 211, 7, True{}, 0, 0, 0),
  Enc.of("SARi", 193, 7, True{}, 0, 0, 0),
  Enc.of("SETB", 3986, 0, True{}, 0, 0, 0),
  Enc.of("SETE", 3988, 0, True{}, 0, 0, 0),
  Enc.of("SETL", 3996, 0, True{}, 0, 0, 0),
  Enc.of("SETNE", 3989, 0, True{}, 0, 0, 0),
  Enc.of("SHL", 211, 4, True{}, 0, 0, 0),
  Enc.of("SHLi", 193, 4, True{}, 0, 0, 0),
  Enc.of("SHR", 211, 5, True{}, 0, 0, 0),
  Enc.of("SHRi", 193, 5, True{}, 0, 0, 0),
  Enc.of("SUB", 43, 0, False{}, 0, 0, 0),
  Enc.of("SUBi", 129, 5, True{}, 0, 0, 0),
  Enc.of("VADDSD", 88, 0, False{}, 3, 1, 0),
  Enc.of("VADDSS", 88, 0, False{}, 2, 1, 0),
  Enc.of("VBLENDVPD", 75, 0, False{}, 1, 3, 0),
  Enc.of("VBLENDVPS", 74, 0, False{}, 1, 3, 0),
  Enc.of("VCMPSD", 194, 0, False{}, 3, 1, 0),
  Enc.of("VCMPSS", 194, 0, False{}, 2, 1, 0),
  Enc.of("VCVTPH2PS", 19, 0, False{}, 1, 2, 0),
  Enc.of("VCVTPS2PH", 29, 0, False{}, 1, 3, 0),
  Enc.of("VCVTSD2SS", 90, 0, False{}, 3, 1, 0),
  Enc.of("VCVTSI2SD", 42, 0, False{}, 3, 1, 2),
  Enc.of("VCVTSI2SS", 42, 0, False{}, 2, 1, 2),
  Enc.of("VCVTSS2SD", 90, 0, False{}, 2, 1, 0),
  Enc.of("VCVTTSD2SI", 44, 0, False{}, 3, 1, 3),
  Enc.of("VCVTTSS2SI", 44, 0, False{}, 2, 1, 3),
  Enc.of("VDIVSD", 94, 0, False{}, 3, 1, 0),
  Enc.of("VDIVSS", 94, 0, False{}, 2, 1, 0),
  Enc.of("VINSERTPS", 33, 0, False{}, 1, 3, 0),
  Enc.of("VMOVD", 110, 0, False{}, 1, 1, 0),
  Enc.of("VMOVDm", 126, 0, False{}, 1, 1, 0),
  Enc.of("VMOVQ", 110, 0, False{}, 1, 1, 1),
  Enc.of("VMOVQm", 126, 0, False{}, 1, 1, 1),
  Enc.of("VMOVSD", 16, 0, False{}, 3, 1, 0),
  Enc.of("VMOVSDm", 17, 0, False{}, 3, 1, 0),
  Enc.of("VMOVSS", 16, 0, False{}, 2, 1, 0),
  Enc.of("VMOVSSm", 17, 0, False{}, 2, 1, 0),
  Enc.of("VMOVUPS", 16, 0, False{}, 0, 1, 0),
  Enc.of("VMOVUPSm", 17, 0, False{}, 0, 1, 0),
  Enc.of("VMULSD", 89, 0, False{}, 3, 1, 0),
  Enc.of("VMULSS", 89, 0, False{}, 2, 1, 0),
  Enc.of("VPEXTRD", 22, 0, False{}, 1, 3, 0),
  Enc.of("VPEXTRW", 21, 0, False{}, 1, 3, 0),
  Enc.of("VPINSRD", 34, 0, False{}, 1, 3, 0),
  Enc.of("VPINSRW", 196, 0, False{}, 1, 1, 0),
  Enc.of("VPSRLDQ", 115, 3, True{}, 1, 1, 0),
  Enc.of("VROUNDSD", 11, 0, False{}, 1, 3, 0),
  Enc.of("VROUNDSS", 10, 0, False{}, 1, 3, 0),
  Enc.of("VSQRTSD", 81, 0, False{}, 3, 1, 0),
  Enc.of("VSQRTSS", 81, 0, False{}, 2, 1, 0),
  Enc.of("VSUBSD", 92, 0, False{}, 3, 1, 0),
  Enc.of("VSUBSS", 92, 0, False{}, 2, 1, 0),
  Enc.of("XOR", 51, 0, False{}, 0, 0, 0),
  Enc.of("XORi", 129, 6, True{}, 0, 0, 0),
 ]

def enc_find.go(+es: List<&2, Enc>, +nm: String) -> Enc:
  match es:
    case Nil{}: Enc.none()
    case +h <> t: Bool.pick(Enc, String.eq(Enc.name(h), nm), h, enc_find.go(t, nm))

# --- the EIGHT entries that build bytes without `encode` ---------------------

def enc_find(+nm: String) -> Enc: enc_find.go(enc_table(), nm)

def Enc.is_direct(+nm: String) -> Bool:
  # the eight `encodings` entries that do NOT call `encode`: `MOVABS` and the six
  # jumps plus `RET`. Membership is by NAME, because "does this op call encode" is a
  # property of the table's shape and not of any operand-class set.
  Op.has(nm, ["MOVABS", "JMP", "RET", "JE", "JNE", "JL", "JB", "JGE"])

def Enc.direct_op1(+nm: String) -> U32:
  # 0x0F for the six conditional jumps, 0xE9 for `JMP`. `RET` never reaches here.
  match nm:
    case "JMP": 233
    case _: 15

def Enc.direct_op2(+nm: String) -> U32:
  # `JMP` is 0xE9 ALONE, so its second byte is absent and CPython writes `0x00` here.
  # The six conditional jumps are all `0x0F <op>`, and the six second bytes are
  # 0x84 JE, 0x85 JNE, 0x8C JL, 0x82 JB, 0x8D JGE.
  match nm:
    case "JE": 132
    case "JNE": 133
    case "JL": 140
    case "JB": 130
    case "JGE": 141
    case _: 0

def Enc.disp_arm(+disp_sz: U32) -> U32: Bool.pick(U32, U32.is_eq(disp_sz, 1), 1, 0)

def Enc.disp_bytes.of(+disp_val: U32, +arm: U32) -> List<&2, U32>:
  # `struct.pack(unwrap(disp_uop.dtype.fmt), disp_uop.src[0].val)` -- ONE byte for an
  # int8 and FOUR little-endian bytes for an int32, in TWO'S COMPLEMENT, which
  # `U32.and`/`U32.shrn` give for free and which is why a negative displacement is
  # not a special case here.
  match arm:
    case 1: [U32.and(disp_val, 255)]
    case _: [U32.and(disp_val, 255), U32.and(U32.shrn(disp_val, 8n), 255),
            U32.and(U32.shrn(disp_val, 16n), 255), U32.and(U32.shrn(disp_val, 24n), 255)]

def Enc.disp_bytes(+disp_val: U32, +disp_sz: U32) -> List<&2, U32>: Enc.disp_bytes.of(disp_val, Enc.disp_arm(disp_sz))

# THE BYTE EXTRACT, and `U32.shln`'s second argument is a `Nat` -- a `U32` there is a
# type error, not a coercion (`bend2-constraints.md` line 1381).
# BOTH `U32.shln` and `U32.shrn` TAKE A `Nat` SHIFT AMOUNT, and a byte offset in bits
# is `8 * i`, so the multiplication is on the `Nat` and not on the `U32`
# (`bend2-constraints.md` line 1381 -- a `Nat` literal only binds in a `Nat` context).

def Enc.imm_byte(+imm: U32, +i: Nat) -> U32: U32.and(U32.shrn(imm, Nat.mul(8n, i)), 255)

# `n` little-endian bytes of `imm`. THE COUNTDOWN IS A `Nat` AND `k` IS THE FIRST
# PARAMETER: a self-call is read left to right and each argument passes unchanged
# until one shrinks, and Bend recognises a shrinking `Nat` and not `U32.inc(i)` on a
# `U32` (`bend2-constraints.md` line 1285, and line 1381 for why a `Nat` literal only
# binds in a `Nat` context). The byte index is `n - k`, so byte 0 is emitted FIRST.

def Enc.imm_int(+k: Nat, +n: Nat, +imm: U32) -> List<&2, U32>:
  # LITTLE-ENDIAN: `struct.pack('<i', v)` puts byte 0 FIRST, so the byte for index
  # `n - k` is PREPENDED and the countdown tail follows it. Appending it instead (the
  # first cut of this def) builds the same bytes in the opposite order, which every
  # 4- and 8-byte immediate row diffed on -- `MOVABS 0` came out
  # `48b80000000000001234` where CPython emits `48b83412000000000000`, so the whole
  # immediate was reversed and the row was a bare string concatenation nobody read.
  # THE COUNTDOWN `k` AND THE TOTAL `n` ARE BOTH `Nat`, and the byte index is
  # `n - k` in `Nat` too, because the byte offset feeds `Nat.mul` in `Enc.imm_byte`.
  match k:
    case 0n: Nil{}
    case 1n+p: List.append(&2, U32, [Enc.imm_byte(imm, Nat.sub(n, k))], Enc.imm_int(p, n, imm))

def Enc.or2(+a: U32, +b: U32) -> U32: U32.or(a, b)

# `List.concat` takes a LIST OF LISTS (`base.bend:829`), so every join of two byte
# lists is one of these. Writing `List.concat(.., a, b)` is a TYPE error naming
# `List<&2, List<&2, List<&2, U32>>>`, which is how Bend says so.

def Enc.cat(+a: List<&2, U32>, +b: List<&2, U32>) -> List<&2, U32>:
  List.concat(&2, U32, [a, b])

def Enc.cat3(+a: List<&2, U32>, +b: List<&2, U32>, +c: List<&2, U32>) -> List<&2, U32>:
  List.concat(&2, U32, [a, b, c])

# FOUR terms because that is how many a MODRM or VEX byte needs, and writing a
# three-term helper and passing a fourth argument is a PARSE error rather than a
# type error -- Bend says "expected : a function type" and names no arity.

def Enc.or4(+a: U32, +b: U32, +c: U32, +d: U32) -> U32: U32.or(U32.or(a, b), U32.or(c, d))

def Enc.pick3(+bit: Bool, +w: U32) -> U32: Bool.pick(U32, bit, w, 0)

# --- VEX, x86.py:548-551 --------------------------------------------------------

def Enc.shl(+v: U32, +n: Nat) -> U32: U32.shln(v, n)

def Enc.b1(+v: U32) -> U32: Bool.pick(U32, U32.is_lt(v, 1), 1, 0)

def Enc.b4(+v: U32) -> U32: U32.sub(15, v)

def Enc.vex_bytes(+small: Bool, +r: U32, +x: U32, +b: U32, +vvvv: U32, +we: U32, +sel: U32, +pp: U32) -> List<&2, U32>:
  # `if sel == 1 and _x == b == we == 0` is the TWO-BYTE C5 form; everything else is
  # the three-byte C4 form, INCLUDING `sel == 2` and `sel == 3`, for which no two-byte
  # VEX exists. Losing this test costs a whole byte and shifts every later byte, which
  # is why it is its own def and its own row.
  match small:
    case True{}: [197, Enc.or4(Enc.shl(Enc.b1(r), 7n), Enc.shl(Enc.b4(vvvv), 3n), pp, 0)]
    case False{}: [196, Enc.or4(Enc.shl(Enc.b1(r), 7n), Enc.shl(Enc.b1(x), 6n),
                        Enc.shl(Enc.b1(b), 5n), sel),
                   Enc.or4(Enc.shl(we, 7n), Enc.shl(Enc.b4(vvvv), 3n), pp, 0)]

# --- PREFIX, x86.py:554 ---------------------------------------------------------

def Enc.arm16(+sz: U32) -> U32: Bool.pick(U32, U32.is_eq(sz, 2), 1, 0)

def Enc.prefix_byte.of(+sz: U32, +arm: U32) -> List<&2, U32>:
  # `if sz == 2: inst += bytes([0x66])` -- the 16-bit operand-size prefix, and the
  # ONLY prefix this encoder emits.
  match arm:
    case 1: [102]
    case _: Nil{}

# THE ARM-INDEX PATTERN, USED BY EVERY THRESHOLD IN THIS FILE. A `match` may only
# scrutinise a PARAMETER, so the comparison is arithmetic that yields an INDEX and the
# branch is a `match` on that index, in a second def that takes it as a parameter.
# `Bool.pick` evaluates BOTH arms (bend2-constraints.md line 1389), so this shape also
# never drops work the way an `if` around a recursive call would.

def Enc.prefix_byte(+sz: U32) -> List<&2, U32>: Enc.prefix_byte.of(sz, Enc.arm16(sz))

# --- demote, REX, x86.py:556-562 ------------------------------------------------

def Enc.demote_of(+rm_sz: U32, +reg_sz: U32, +no_demote: Bool) -> Bool:
  # `(rm_sz == 1 or reg_sz == 1) and x.arg[0] not in X86GroupOp.ReadFlags | {LEA}`,
  # which in the encoder means "there is a prefix-free one-byte form" -- the 8-bit
  # opcodes are one LESS than the 16/32/64-bit ones (x86.py:557). `no_demote` is the
  # `arg[0] not in ReadFlags | {LEA}` test and is a GATE ROW of its own.
  #
  # NOTHING ELSE IS IN IT. The first cut also ANDed in `disp_uop is None`, which is
  # the THIRD clause of the REX test at x86.py:560 and not of `demote`: a one-byte
  # store to a displacement therefore lost its opcode demotion. `has_disp` and `rm`
  # are gone from the signature rather than defaulted, because a parameter nothing
  # reads is how a second reading of the source creeps back in.
  Bool.and(Bool.or(U32.is_eq(rm_sz, 1), U32.is_eq(reg_sz, 1)), Bool.not(no_demote))

def Enc.ge4(+v: U32) -> Bool: U32.is_ge(v, 4)

def Enc.gt0(+v: U32) -> Bool: U32.is_gt(v, 0)

def Enc.rex_bit2(+sz: U32, +r: U32) -> Bool:
  # `reg_sz == 1 & reg >> 2` READS AS `reg_sz == 1 and reg >= 4`, AND IT IS NOT.
  # In Python `&` binds TIGHTER than `==`, so it parses as `reg_sz == (1 & (reg >> 2))`
  # -- a test for `reg_sz` being ZERO for regs 0-3 and 8-11 and ONE for 4-7 and 12-15.
  # That is a real clause of the REX test, and it is the reason `MOVi` and all four
  # `SET*` carry a null `0x40` REX byte (x86.py:560): their `reg_sz` is 0 and their
  # `reg` is 0. Written as `== 1 and >= 4` the clause is false there, the `0x40`
  # disappears, and every byte after it shifts.
  U32.is_eq(sz, U32.and(U32.shrn(r, 2n), 1))

def Enc.needs_rex(+w: Bool, +r: U32, +x: U32, +b: U32, +reg_sz: U32, +reg: U32, +rm_sz: U32, +rm: U32, +demote: Bool, +has_disp: Bool) -> Bool:
  # `w | r | x | b | (reg_sz == 1 & reg >> 2) | (rm_sz == 1 & rm >> 2) | (demote and
  # disp_uop is None and rm >= 4)`. THE LAST CLAUSE IS THE ONE THAT IS EASY TO LOSE:
  # without it a one-byte `mov rsp, rcx` gets no REX and cannot address the low byte
  # of rsp at all. The two `& >> 2` clauses are `Enc.rex_bit2`, which is NOT the same
  # predicate as `== 1 and >= 4`.
  Bool.or(Bool.or(Bool.or(w, Enc.gt0(r)), Bool.or(Enc.gt0(x), Enc.gt0(b))),
    Bool.or(Bool.or(Enc.rex_bit2(reg_sz, reg), Enc.rex_bit2(rm_sz, rm)),
      Bool.and(Bool.and(demote, Bool.not(has_disp)), Enc.ge4(rm))))

def Enc.opc_arm(+opc: U32) -> U32: Bool.pick(U32, U32.is_gt(opc, 255), 1, 0)

def Enc.opcode_bytes.of(+opc: U32, +arm: U32) -> List<&2, U32>:
  # `opc.to_bytes((opc.bit_length() + 7) // 8, 'big')` -- a two-byte opcode when the
  # opcode is over 0xFF (the 0F-map ones: MOVZX, IMUL, SET*, CMOV*), else one. The
  # test is `opc > 255` and not `opc.bit_length() > 8`: for every opcode in the table
  # the two agree, and `> 255` is the one Bend can write.
  match arm:
    case 1: [U32.shrn(opc, 8n), U32.and(opc, 255)]
    case _: [opc]

def Enc.opcode_bytes(+opc: U32) -> List<&2, U32>: Enc.opcode_bytes.of(opc, Enc.opc_arm(opc))

def Enc.modrm_of(+disp_val: U32, +disp_sz: U32, +has_disp: Bool, +rm: U32) -> U32:
  # `if disp_uop.src[0].val != 0 or rm == 0b101: mod = 1 if itemsize == 1 else 2`
  # -- rbp/r13 ALWAYS require a displacement, because 0b101 is the disp32-no-disp
  # encoding of rbp, which is why a ZERO displacement off rbp is still mod=1. That is
  # the `rm == 5` clause and it is a gate row of its own.
  match has_disp:
    case True{}: Bool.pick(U32, Bool.or(U32.is_ne(disp_val, 0), U32.is_eq(rm, 5)),
      Bool.pick(U32, U32.is_eq(disp_sz, 1), 1, 2), 0)
    case False{}: 3

def Enc.no_index(+idx3: U32, +x: U32) -> Bool:
  # `idx == 0b100 and _x == 0b0` -- index 4 IS rsp, so this is the "NO INDEX"
  # condition, and it is the one that decides whether a SIB byte is needed at all.
  Bool.and(U32.is_eq(idx3, 4), U32.is_zero(x))

def Enc.rm3.of(+rm3: U32, +noidx: Bool) -> U32:
  # rm stays in the low three bits when there is no index; otherwise rm moves into the
  # SIB base field and the MODRM rm field becomes 0b100.
  match noidx:
    case True{}: rm3
    case False{}: 4

def Enc.rm3(+idx3: U32, +x: U32, +rm3: U32) -> U32: Enc.rm3.of(rm3, Enc.no_index(idx3, x))

def Enc.modrm_byte(+mod: U32, +reg3: U32, +rm_field: U32) -> U32:
  Enc.or4(Enc.shl(mod, 6n), Enc.shl(reg3, 3n), rm_field, 0)

# --- SIB, x86.py:584-586 -------------------------------------------------------

def Enc.log2b(+v: U32) -> U32:
  # `{1: 0b00, 2: 0b01, 4: 0b10, 8: 0b11}` -- the SIB scale field IS log2(element
  # size), so an eight-byte element sets 3 and a one-byte element sets 0.
  match v:
    case 1: 0
    case 2: 1
    case 4: 2
    case 8: 3
    case _: 0

def Enc.sib_scale.of(+rm_sz: U32, +has_index: Bool) -> U32:
  # `{...}[1 if idx == 0b100 and _x == 0b0 else rm_sz]` -- with NO INDEX the scale is
  # 1 (encoded 0) whatever the element size, because there is nothing to scale.
  match has_index:
    case True{}: Enc.log2b(rm_sz)
    case False{}: 0

def Enc.sib_scale(+rm_sz: U32, +has_index: Bool) -> U32:
  # (`Enc.sib_field.of` reached past this wrapper to `.of` directly, which left the
  # wrapper a def nothing called; it calls the wrapper now.)
  Enc.sib_scale.of(rm_sz, has_index)

def Enc.sib_byte(+scale: U32, +idx3: U32, +rm3: U32) -> U32:
  # `scale << 6 | idx << 3 | rm` -- and rm here is the FULL three-bit register, not the
  # `rm3` MODRM carried, which is the whole reason the byte exists.
  Enc.or4(Enc.shl(scale, 6n), Enc.shl(idx3, 3n), rm3, 0)

def Enc.want_sib(+noidx: Bool, +mod: U32) -> Bool: Bool.and(Bool.not(noidx), Bool.not(U32.is_eq(mod, 3)))

def Enc.legacy_head.of(+pfx: List<&2, U32>, +need: Bool, +rex: U32) -> List<&2, U32>:
  # `inst += bytes([0x66])` then OPTIONALLY the REX. THIS IS EVERYTHING BEFORE THE
  # OPCODE and nothing else: the prefix and the REX are the only two bytes that can
  # precede it and they are both optional, so this is a two-arm shape rather than three.
  #
  # IT USED TO END IN THE OPCODE, and `Enc.emit.tail` appended the opcode again -- so
  # `LEA` came out `488d8d948c`: the prefix/REX head, the opcode, the opcode AGAIN, and
  # then the displacement LOST. Every byte def was individually right, which is why the
  # defect survived a green gate and why the eighty `hex.*`/`direct.*` rows were bare
  # string concatenations nobody could read a failure out of. The opcode is now
  # appended exactly once, by `Enc.emit`, from the DEMOTED value.
  match need:
    case True{}: Enc.cat(pfx, [rex])
    case False{}: pfx

def Enc.rex_byte(+w: Bool, +r: U32, +x: U32, +b: U32) -> U32:
  # `0b0100 << 4 | w << 3 | r << 2 | x << 1 | b`. The leading `64` is that shift.
  Enc.or4(64, Enc.pick3(w, 8), Enc.pick3(Enc.gt0(r), 4), Enc.or2(Enc.pick3(Enc.gt0(x), 2), b))

# --- OPCODE, x86.py:564 ---------------------------------------------------------

def Enc.legacy_head(+nm: String, +r: U32, +x: U32, +b: U32, +sz: U32, +rm: U32, +reg: U32, +rm_sz: U32, +reg_sz: U32, +has_disp: Bool, +no_demote: Bool) -> List<&2, U32>:
  Enc.legacy_head.of(Enc.prefix_byte(sz),
    Enc.needs_rex(U32.is_eq(sz, 8), r, x, b, reg_sz, reg, rm_sz, rm,
      Enc.demote_of(rm_sz, reg_sz, no_demote), has_disp),
    Enc.rex_byte(U32.is_eq(sz, 8), r, x, b))

def Enc.pp_of(+nm: String) -> U32: Enc.pp(enc_find(nm))

# THE WHOLE ENCODER, in the order x86.py emits it: VEX OR PREFIX+REX, the OPCODE,
# MODRM, SIB, DISPLACEMENT, IMMEDIATE. Fourteen numbers are what `_encode`'s closure
# captures, and `nm` supplies the rest from the table. `sel != 0` IS the `if sel:`
# fork -- a VEX-encoded opcode never emits a REX and a legacy one never emits a VEX, so
# the two arms are disjoint and no byte is emitted twice.

# `mod` needs only the MASKED rm: the `rm == 0b101` test is about rbp/r13, and both are
# inside three bits already.

def mod_of(+nm: String, +rm: U32, +has_disp: Bool, +disp_val: U32, +disp_sz: U32) -> U32:
  Enc.modrm_of(disp_val, disp_sz, has_disp, U32.and(rm, 7))

# MODRM, then SIB, then DISPLACEMENT, then IMMEDIATE. `reg` and `rm` are MASKED to three
# bits HERE (x86.py:567) while the SIB carries the FULL three, which is why the same two
# numbers mean different things in the two bytes -- and why `rm` is computed once and
# read by both.

def Enc.emit.head.of(+sel: U32, +nm: String, +reg: U32, +rm: U32, +idx: U32, +rm_sz: U32, +reg_sz: U32, +vvvv: U32, +has_disp: Bool, +no_demote: Bool, +r: U32, +x: U32, +b: U32, +sz: U32, +we: U32) -> List<&2, U32>:
  # `r, _x, b = reg >> 3, idx >> 3, rm >> 3` and `sz = reg_sz or rm_sz` -- both are
  # read by every downstream byte, so they are computed ONCE here. `sz = reg_sz or
  # rm_sz` is a PYTHON `or` over integers, which is `reg_sz if reg_sz else rm_sz`, and
  # `Enc.emit.head` spells it with `Bool.pick` rather than a truthiness test on a
  # number, which Bend has none of.
  match sel:
    case 0: Enc.legacy_head(nm, r, x, b, sz, rm, reg, rm_sz, reg_sz, has_disp, no_demote)
    case _: Enc.vex_bytes(Bool.pick(Bool, Bool.and(U32.is_eq(sel, 1), Bool.and(U32.is_zero(x),
      Bool.and(U32.is_zero(b), U32.is_zero(we)))), True{}, False{}), r, x, b, vvvv, we, sel, Enc.pp_of(nm))

def Enc.demoted_opc.of(+opc: U32, +arm: U32) -> U32:
  match arm:
    case 1: U32.sub(opc, 1)
    case _: opc

# `if demote: opc -= 1` -- the ONLY arithmetic in the opcode byte.

def Enc.demoted_opc(+nm: String, +rm: U32, +rm_sz: U32, +reg_sz: U32, +has_disp: Bool, +no_demote: Bool) -> U32:
  Enc.demoted_opc.of(Enc.opc(enc_find(nm)),
    Bool.pick(U32, Enc.demote_of(rm_sz, reg_sz, no_demote), 1, 0))

# --- MODRM, x86.py:566-582 ------------------------------------------------------

def Enc.we_of.of(+selw: U32, +xsz: U32, +src1sz: U32) -> U32:
  # `we` is ONE OF FOUR THINGS, and the selector says which (x86.py:624-687):
  # 0 not passed; 1 the Constant `we=1` (VMOVQ, VMOVQm); 2
  # `x.src[1].dtype.itemsize == 8` (the two VCVTSI2); 3 `x.dtype.itemsize == 8`
  # (the two VCVTT*2SI).
  #
  # 2 AND 3 READ DIFFERENT NUMBERS, and neither of them is `reg_sz` or `rm_sz`:
  # `x.src[1]` is the rm operand of an Rm2nd op, whose `rm_sz` is the REGISTER's 16,
  # while the expression reads its DTYPE's 4. Substituting `rm_sz` for selector 2 is
  # what the first cut did and it is wrong by construction; the two sizes are now
  # `Enc.emit`'s own parameters, handed over by the gate as measured numbers.
  match selw:
    case 1: 1
    case 2: Bool.pick(U32, U32.is_eq(src1sz, 8), 1, 0)
    case 3: Bool.pick(U32, U32.is_eq(xsz, 8), 1, 0)
    case _: 0

def Enc.we_of(+nm: String, +xsz: U32, +src1sz: U32) -> U32:
  Enc.we_of.of(Enc.we_sel(enc_find(nm)), xsz, src1sz)

def Enc.emit.head(+nm: String, +reg: U32, +rm: U32, +idx: U32, +rm_sz: U32, +reg_sz: U32, +vvvv: U32, +has_disp: Bool, +no_demote: Bool, +we: U32) -> List<&2, U32>:
  Enc.emit.head.of(Enc.sel(enc_find(nm)), nm, reg, rm, idx, rm_sz, reg_sz, vvvv, has_disp,
    no_demote, U32.shrn(reg, 3n), U32.shrn(idx, 3n), U32.shrn(rm, 3n),
    Bool.pick(U32, U32.is_zero(reg_sz), rm_sz, reg_sz), we)

def Enc.sib_field.of(+noidx: Bool, +idx3: U32, +rm3: U32, +rm_sz: U32, +want: Bool) -> List<&2, U32>:
  # `_rm == 0b100 and mod != 0b11` is the SIB condition: a memory operand whose rm
  # field came out as 0b100. It is NOT "there is a memory operand" -- mod=00 with no
  # index is `[rsp]`, and mod=00 with an index is `[rsp+rcx*4]`, and BOTH need the
  # SIB byte, while a register operand never does.
  match want:
    case True{}: [Enc.sib_byte(Enc.sib_scale(rm_sz, Bool.not(noidx)), idx3, rm3)]
    case _: Nil{}

def Enc.sib_field(+has_disp: Bool, +mod: U32, +noidx: Bool, +idx3: U32, +rm3: U32, +rm_sz: U32) -> List<&2, U32>:
  Enc.sib_field.of(noidx, idx3, rm3, rm_sz, Enc.want_sib(noidx, mod))

def Enc.imm_bytes(+kind: U32, +n: Nat, +imm: U32) -> List<&2, U32>:
  # kind 0: no immediate. kind 1: `imm_uop.op is Ops.CAST`, packed per its dtype's
  # `fmt`. kind 2: `isinstance(rdef(imm_uop), Register)`, ONE byte
  # `(index & 0b1111) << 4` -- the ModRM-style reg-field nibble a VEX-encoded
  # immediate ride carries, and the only immediate here that is not a little-endian
  # integer.
  match kind:
    case 1: Enc.imm_int(n, n, imm)
    case 2: [Enc.shl(U32.and(imm, 15), 4n)]
    case _: Nil{}

# --- bit helpers. EVERY `~` IN x86.py SURVIVES AS A BOUNDED COMPLEMENT, AND WRITING
# `U32.not` INSTEAD WOULD ZERO EVERY OTHER BIT -- the VEX byte would lose its map bits
# and the gate would say so on eighty rows. `~r & 0b1` is `1 - r`; `~vvvv & 0b1111` is
# `15 - vvvv`.

def Enc.tail_bytes.of(+want: Bool, +dsp: List<&2, U32>) -> List<&2, U32>:
  match want:
    case True{}: dsp
    case False{}: Nil{}

def Enc.tail_bytes(+mod: U32, +has_disp: Bool, +disp_val: U32, +disp_sz: U32) -> List<&2, U32>:
  # `if mod == 0b01 or mod == 0b10` -- mod is 0, 1, 2 or 3 and the DISPLACEMENT rides
  # on 1 and 2, so `mod < 3` is the test. The first cut wrote `mod == 0` and named the
  # flag `nod`, which is wrong TWICE OVER: it emits the displacement for `[rax]` and
  # drops it for `[rbx+8]`. Every row with a displacement lost four bytes.
  Enc.tail_bytes.of(U32.is_lt(mod, 3), Enc.disp_bytes(disp_val, disp_sz))

# --- the eight direct-byte entries, x86.py:680-686 ----------------------------
#     JE: bytes([0x0F, 0x84]) + int(0).to_bytes(4)      JMP: bytes([0xE9]) + ...
#     RET: bytes([0xC3])
# `int(0).to_bytes(4)` is FOUR ZERO BYTES for EVERY jump -- there is no second opcode
# for `JMP`, whose placeholder is 0xE9 alone -- and `RET` is the one entry with
# NOTHING after its opcode. Two arms, because `Enc.is_direct` has already answered
# that `nm` is one of the eight, and a third arm would be a case Python does not have.

def Enc.emit.tail.of(+head: List<&2, U32>, +opcs: List<&2, U32>, +reg: U32, +rm: U32, +idx: U32,
    +rm_sz: U32, +has_disp: Bool, +disp_val: U32, +disp_sz: U32, +imm_kind: U32, +imm_n: Nat,
    +imm: U32, +mod: U32) -> List<&2, U32>:
  # MODRM, then SIB, then DISPLACEMENT, then IMMEDIATE. `reg` and `rm` are MASKED to three
  # bits HERE (x86.py:567) while the SIB carries the FULL three, which is why the same two
  # numbers mean different things in the two bytes -- and why `rm` is computed once and
  # read by both. `opcs` is the DEMOTED opcode byte(s), handed in rather than read from
  # the table: the table's `opc` is the un-demoted one, and `x86.py:562` subtracts one
  # before it is emitted.
  Enc.cat3(Enc.cat(head, opcs),
    [Enc.modrm_byte(mod, U32.and(reg, 7), Enc.rm3(U32.and(idx, 7), U32.shrn(idx, 3n), U32.and(rm, 7)))],
    Enc.cat(Enc.sib_field(has_disp, mod, Enc.no_index(U32.and(idx, 7), U32.shrn(idx, 3n)),
      U32.and(idx, 7), U32.and(rm, 7), rm_sz),
      Enc.cat(Enc.tail_bytes(mod, has_disp, disp_val, disp_sz), Enc.imm_bytes(imm_kind, imm_n, imm))))

def Enc.emit.tail(+nm: String, +head: List<&2, U32>, +opcs: List<&2, U32>, +reg: U32, +rm: U32, +idx: U32,
    +rm_sz: U32, +has_disp: Bool, +disp_val: U32, +disp_sz: U32, +imm_kind: U32, +imm_n: Nat,
    +imm: U32) -> List<&2, U32>:
  Enc.emit.tail.of(head, opcs, reg, rm, idx, rm_sz, has_disp, disp_val, disp_sz, imm_kind, imm_n,
    imm, mod_of(nm, rm, has_disp, disp_val, disp_sz))

def Enc.emit(+nm: String, +reg: U32, +rm: U32, +idx: U32, +rm_sz: U32, +reg_sz: U32,
    +vvvv: U32, +has_disp: Bool, +disp_val: U32, +disp_sz: U32, +imm_kind: U32,
    +imm_n: Nat, +imm: U32, +no_demote: Bool, +xsz: U32, +src1sz: U32) -> List<&2, U32>:
  # THE SIXTEEN NUMBERS `_encode` READS OUT OF ITS SIX PARAMETERS AND THE NODE `x`,
  # in x86.py:533-544 order with the table's `opc`/`pp`/`sel`/`we` resolved from `nm`.
  # `xsz` and `src1sz` are the last two because the two computed `we=` expressions read
  # them (x86.py:641-644) and neither is any of the other fourteen.
  #
  # THE OPCODE IS APPENDED HERE, ONCE. `Enc.emit.head` returns only what precedes it --
  # the 0x66 prefix, the REX, or the VEX pair -- and `Enc.emit.tail` receives the byte.
  # Splitting it that way is what makes "the opcode is emitted twice" impossible rather
  # than merely absent: there is one call site for it in the whole encoder.
  Enc.emit.tail(nm, Enc.emit.head(nm, reg, rm, idx, rm_sz, reg_sz, vvvv, has_disp, no_demote,
      Enc.we_of(nm, xsz, src1sz)),
    Enc.opcode_bytes(Enc.demoted_opc(nm, rm, rm_sz, reg_sz, has_disp, no_demote)),
    reg, rm, idx, rm_sz, has_disp, disp_val, disp_sz, imm_kind, imm_n, imm)

def Enc.direct.of(+nm: String) -> List<&2, U32>:
  # `int(0).to_bytes(4)` is FOUR ZERO BYTES for every jump, and `JMP` HAS ONE OPCODE
  # where the other five have two (x86.py:680-686), so `JMP` is FIVE bytes and the rest
  # are six. The first cut appended the same four zeros to both, which made
  # `Enc.direct("JMP")` six bytes -- `e90000000000` where CPython emits `e900000000` --
  # and `Enc.direct_op2` answers 0 for JMP already, so the shape is one arm for the
  # single-opcode jump and one for the five two-byte ones.
  match nm:
    case "RET": [195]
    case "JMP": [Enc.direct_op1(nm), 0, 0, 0, 0]
    case _: [Enc.direct_op1(nm), Enc.direct_op2(nm), 0, 0, 0, 0]

def Enc.direct(+nm: String) -> List<&2, U32>: Enc.direct.of(nm)

# `MOVABS` (x86.py:627) --
#     bytes([0b0100 << 4 | 0b1 << 3 | 0b00 << 2 | r.index >> 3,
#            0xB8 + (r.index & 0b111)]) + struct.pack(x.dtype.fmt, v)
# THE ONLY ENTRY WHOSE SECOND BYTE IS AN OPCODE PLUS A REGISTER NUMBER rather than a
# fixed constant, and the only one whose FIRST byte carries `r.index >> 3` in the REX
# position. `64 | 8` is the `0b0100 << 4 | 0b1 << 3`, and `0b00 << 2` contributes
# nothing -- so the REX is 0x48 or 0x49 depending on the register's top bit.

def Enc.movabs(+reg: U32, +imm: U32) -> List<&2, U32>:
  Enc.cat([U32.or(72, U32.shrn(reg, 3n)), U32.add(184, U32.and(reg, 7))], Enc.imm_int(8n, 8n, imm))

# ===========================================================================
# STAGE 7 -- `asm_str`. x86.py:728-749. THE ASSEMBLY TEXT.
#
# THE PORT IS THE FORMAT AND NOT THE GRAPH. `asm_str` reads a `list[UOp]`, and a UOp
# graph is not this file's type: `ops.bend`'s `Arena` is a different representation with
# different provenance, so the gate hands this port one `AsmOp` per `uops` entry, carrying
# only the facts the FORMATTER reads -- `str(x.arg[0])`, `str(rdef(s))`, `rdef(s).size`,
# `s.src[0].val`, `base.dtype.itemsize`, `disp.src[0].val`, `str(u.tag)` -- and the port
# does every part of `_format_op` / `_format` / `_mem_adress` / the three-arm operand
# split / the skip / the join. The oracle reads those facts off the SAME UOps CPython
# formats, so a wrong formatter byte is a diff.
#
# WHAT THE ORACLE DOES AND DOES NOT DECIDE. It decides which uop is a LABEL, which is a
# RET and which is skipped, because that is `u.op is not Ops.INS or u.arg[0] is
# X86Ops.DEFINE` -- a property of the graph. It does NOT decide how a mnemonic is
# spelled, how wide it is padded, which of the four operand arms fires, or where the
# commas go: `Asm.line` is the whole of that and it is the thing under test.
# ===========================================================================

type AsmArg is Data: AsmArg{nm: String, sz: U32, val: U32, imm: Bool}
type AsmMem is Data: AsmMem{base: String, idx: String, scale: U32, disp: U32}
type AsmOp is Data: AsmOp{kind: U32, mn: String, tag: String, dsts: List<&2, AsmArg>, has_mem: Bool, mem: AsmMem, srcs: List<&2, AsmArg>}

# KIND 0 an instruction with operands, 1 `RET` (mnemonic only, x86.py:747), 2 a LABEL
# (`f"{str(u.tag)}:"`, x86.py:746), 3 skipped (`u.op is not Ops.INS or arg[0] is DEFINE`).
def AsmOp.of(+k: U32, +mn: String, +tag: String, +dsts: List<&2, AsmArg>, +has_mem: Bool, +mem: AsmMem, +srcs: List<&2, AsmArg>) -> AsmOp:
  AsmOp{k, mn, tag, dsts, has_mem, mem, srcs}

def AsmMem.of(+base: String, +idx: String, +scale: U32, +disp: U32) -> AsmMem: AsmMem{base, idx, scale, disp}

def Asm.none() -> AsmMem: AsmMem.of("", "", 0, 0)

def Asm.reg(+nm: String, +sz: U32) -> AsmArg: AsmArg{nm, sz, 0, False{}}
def Asm.imm(+v: U32) -> AsmArg: AsmArg{"", 0, v, True{}}

def Asm.ins(+mn: String, +dsts: List<&2, AsmArg>, +has_mem: Bool, +mem: AsmMem, +srcs: List<&2, AsmArg>) -> AsmOp:
  AsmOp.of(0, mn, "", dsts, has_mem, mem, srcs)

def Asm.ret(+mn: String) -> AsmOp: AsmOp.of(1, mn, "", Nil{}, False{}, Asm.none(), Nil{})
def Asm.label(+tag: String) -> AsmOp: AsmOp.of(2, "", tag, Nil{}, False{}, Asm.none(), Nil{})
def Asm.skip() -> AsmOp: AsmOp.of(3, "", "", Nil{}, False{}, Asm.none(), Nil{})

# THERE IS NO `value.field` SUGAR AND NO GENERATED PROJECTION (convention 4), so every
# field of both records gets a hand-written `match` reader. Seven for `AsmOp` and four
# for each of `AsmArg` and `AsmMem`, and `AsmOp.of` is the only writer.
def AsmOp.kind(o: AsmOp) -> U32:
  match o:
    case AsmOp{kind, mn, tag, dsts, has_mem, mem, srcs}: kind

def AsmOp.mn(o: AsmOp) -> String:
  match o:
    case AsmOp{kind, mn, tag, dsts, has_mem, mem, srcs}: mn

def AsmOp.tag(o: AsmOp) -> String:
  match o:
    case AsmOp{kind, mn, tag, dsts, has_mem, mem, srcs}: tag

def AsmOp.dsts(o: AsmOp) -> List<&2, AsmArg>:
  match o:
    case AsmOp{kind, mn, tag, dsts, has_mem, mem, srcs}: dsts

def AsmOp.has_mem(o: AsmOp) -> Bool:
  match o:
    case AsmOp{kind, mn, tag, dsts, has_mem, mem, srcs}: has_mem

def AsmOp.mem(o: AsmOp) -> AsmMem:
  match o:
    case AsmOp{kind, mn, tag, dsts, has_mem, mem, srcs}: mem

def AsmOp.srcs(o: AsmOp) -> List<&2, AsmArg>:
  match o:
    case AsmOp{kind, mn, tag, dsts, has_mem, mem, srcs}: srcs

def AsmArg.nm(a: AsmArg) -> String:
  match a:
    case AsmArg{nm, sz, val, imm}: nm

def AsmArg.sz(a: AsmArg) -> U32:
  match a:
    case AsmArg{nm, sz, val, imm}: sz

def AsmArg.val(a: AsmArg) -> U32:
  match a:
    case AsmArg{nm, sz, val, imm}: val

def AsmArg.imm(a: AsmArg) -> Bool:
  match a:
    case AsmArg{nm, sz, val, imm}: imm

def AsmMem.base(m: AsmMem) -> String:
  match m:
    case AsmMem{base, idx, scale, disp}: base

def AsmMem.idx(m: AsmMem) -> String:
  match m:
    case AsmMem{base, idx, scale, disp}: idx

def AsmMem.scale(m: AsmMem) -> U32:
  match m:
    case AsmMem{base, idx, scale, disp}: scale

def AsmMem.disp(m: AsmMem) -> U32:
  match m:
    case AsmMem{base, idx, scale, disp}: disp

def AsmArg.text(+a: AsmArg) -> String:
  # `str(s.src[0].val) if s.op is Ops.CAST else reg_strs[o].get(rdef(s).size, o) if
  # (o:=str(rdef(s))) in reg_strs else o`, and `Reg.strs_lookup` IS the last two
  # clauses -- which is why an XMM prints its own name at every size.
  Bool.pick(String, AsmArg.imm(a), U32.show(AsmArg.val(a)), Reg.strs_lookup(AsmArg.nm(a), AsmArg.sz(a)))

def AsmArgs_text(+as: List<&2, AsmArg>) -> List<&2, String>:
  # THE HEAD GOES FIRST. `List.append(a, A, xs, ys)` is `xs ++ ys`, so the recursive tail
  # MUST be the SECOND argument or every operand list comes out reversed -- and it did,
  # and `asm.L3` printed `rcx, rsp, rdx` where CPython prints `rdx, rsp, rcx`.
  match as:
    case Nil{}: Nil{}
    case h <> t: List.append(&2, String, [AsmArg.text(h)], AsmArgs_text(t))

def AsmMem.idx_part(+m: AsmMem) -> String:
  # `f" + {rdef(idx)}*{base.dtype.itemsize}" if rdef(idx) else ""` -- the index is the
  # EMPTY STRING when there is none, which is exactly `rdef(idx)` being falsy, and
  # `base.dtype.itemsize` is the SCALE, not `x.dtype.itemsize`.
  Bool.pick(String, String.is_empty(AsmMem.idx(m)), "",
    String.concat([" + ", AsmMem.idx(m), "*", U32.show(AsmMem.scale(m))]))

def AsmMem.disp_part(+m: AsmMem) -> String:
  # `f" + {d}" if (d:=disp.src[0].val) else ""` -- a displacement of ZERO prints as
  # nothing, so `U32.is_zero` is the test and not a "has a displacement" flag.
  Bool.pick(String, U32.is_zero(AsmMem.disp(m)), "", String.concat([" + ", U32.show(AsmMem.disp(m))]))

def AsmMem.text(+m: AsmMem) -> String:
  # `f"[{rdef(base)}" + index + disp + "]"` -- note that `_mem_adress` is spelled with
  # an `s` in the source and with a `d` here, which is the source's own typo carried over
  # rather than corrected, so a reader can match the two.
  String.concat(["[", AsmMem.base(m), AsmMem.idx_part(m), AsmMem.disp_part(m), "]"])

def AsmOp.mid(+o: AsmOp) -> List<&2, String>:
  # THE FOUR ARMS OF `_format_operands`, all of which end in `+ _format(x.src[n:])`:
  # WriteMem puts the memory FIRST and Rm1st/Rm2nd put it AFTER the destination
  # register(s), so a destination list and a memory flag express all three and the
  # fourth (`_format((x,) + x.src`) is the flagless case. `List.concat` flattens ONE
  # level, so each arm is a list of GROUPS.
  List.concat(&2, String, Bool.pick(List<&2, List<&2, String>>, AsmOp.has_mem(o),
    [List.append(&2, String, AsmArgs_text(AsmOp.dsts(o)), [AsmMem.text(AsmOp.mem(o))]),
      AsmArgs_text(AsmOp.srcs(o))],
    [List.concat(&2, String, [AsmArgs_text(AsmOp.dsts(o)), AsmArgs_text(AsmOp.srcs(o))])]))

def Asm.droplast(+s: String) -> String:
  # `s[:-1]`. REVERSE, DROP THE HEAD, REVERSE BACK: `String.drop` drops from the front and
  # is total on every length, whereas counting down to the last character needs either a
  # `Nat` subtraction with a proof obligation or a hand-written walk -- and the first
  # hand-written walk here counted down one with the input, so it dropped nothing at all
  # and `Asm.mnem("X86Ops.MOVm")` answered `movm`.
  String.reverse(String.drop(String.reverse(s), 1n))

def Asm.mnem.of(+trim: Bool, +n: String) -> String:
  # `(o[7:-1] if (o:=str(x.arg[0]))[-1] in ('i', 'm') else o[7:]).lower()`, and `o[7:]`
  # is the `X86Ops.` enum-repr prefix -- SEVEN characters. `o[7:-1]` is NOT "drop eight":
  # `String.drop` drops from the FRONT, and dropping eight off `"X86Ops.MOVm"` leaves
  # `"OVm"`, so the `i`/`m` case has to be `droplast(drop(n, 7))`.
  String.to_lower(Bool.pick(String, trim, Asm.droplast(String.drop(n, 7n)), String.drop(n, 7n)))

def Asm.mnem(+n: String) -> String:
  # `[-1] in ('i', 'm')` IS "ends with i or m", and `String.ends_with` says so without
  # indexing the last character, which Bend's `String` cannot do directly.
  Asm.mnem.of(Bool.or(String.ends_with(n, "i"), String.ends_with(n, "m")), n)

def Asm.pad.of(+w: U32, +s: String) -> String:
  # `f"{mnem:7s}"` pads on the RIGHT with `7 - len` spaces, and a mnemonic of seven or
  # more is UNPADDED.
  #
  # `U32.sub` WRAPS -- it is `Word.sub(32n, x, y)`, measured on `Base` -- so `7 - 9` is
  # 4294967294 and `String.repeat(" ", 4294967294)` is not a padding, it is a hang. The
  # first cut wrote `U32.min(7, w)`, which is the other wrong answer (it padded to
  # `min(7, len)`, three spaces too few for every short mnemonic), and the FIXTURES had
  # no mnemonic over seven characters, so `VCVTSI2SS` -- NINE of them -- would have been
  # the first thing to hang. `asm.L*` now includes it.
  String.concat([s, String.repeat(" ", U32.to_nat(Bool.pick(U32, U32.is_ge(w, 7), 0, U32.sub(7, w))))])

def Asm.pad(+s: String) -> String: Asm.pad.of(U32.from_nat(String.length(s)), s)

def AsmOp.head(+o: AsmOp) -> String:
  String.concat(["    ", Asm.pad(Asm.mnem(AsmOp.mn(o)))])

def AsmOp.line.of(+k: U32, +o: AsmOp) -> String:
  match k:
    case 0: String.concat([AsmOp.head(o), " ", String.join(AsmOp.mid(o), ", ")])
    case 1: AsmOp.head(o)
    case 2: String.concat([AsmOp.tag(o), ":"])
    case _: ""

def AsmOp.line(+o: AsmOp) -> String: AsmOp.line.of(AsmOp.kind(o), o)

def Asm.go(+os: List<&2, AsmOp>, +acc: List<&2, String>) -> List<&2, String>:
  # ONE self-call per arm and the accumulator is CHOSEN before it, because Bend refuses
  # mutual recursion: a helper that chose between "append this line" and "append
  # nothing" and then called back here would be a cycle.
  match os:
    case Nil{}: acc
    case h <> t:
      Asm.go(t, Bool.pick(List<&2, String>, U32.is_eq(AsmOp.kind(h), 3), acc,
        List.append(&2, String, acc, [AsmOp.line(h)])))

def AsmLines(+os: List<&2, AsmOp>) -> List<&2, String>: Asm.go(os, Nil{})

def AsmLines_n(+os: List<&2, AsmOp>) -> U32: U32.from_nat(List.length(&2, String, AsmLines(os)))

# THE INDEX AND THE COUNT ARE ROWS OF THEIR OWN so that a mutation which drops a LINE
# moves a count rather than silently renumbering every line after it -- and a count is
# what says "the join lost an entry" instead of "line 7 reads differently".
def AsmN(+ls: List<&2, String>) -> U32: U32.from_nat(List.length(&2, String, ls))

def AsmLine.at(+ls: List<&2, String>, +n: Nat) -> String:
  # A miss answers the empty string, which no assembly line can be, so a row reading a
  # line past the end is a diff and not a silent empty.
  Maybe.default(&2, String, List.get(&2, String, ls, n), "")

def asm_str(+fn: String, +os: List<&2, AsmOp>) -> List<&2, String>:
  # `asm = [f".{function_name}:"]` then one entry per uop, `"\n".join(asm)`. A LIST and
  # not a String: a row per line is what the mutation harness can NAME, and the join is
  # one `IO` call in `main`. The header goes in FRONT, and `List.append(a, A, xs, ys)`
  # is `xs ++ ys`, so the header list is the first argument.
  List.append(&2, String, [String.concat([".", fn, ":"])], AsmLines(os))


# ===========================================================================
# STAGE 8 -- `render`'s JUMP PATCH. x86.py:766-767.
#
# `for u in uops: if (t:=jumps.get(u)) is not None:
#  binary[t-4:t] = (targets[u.tag] - t).to_bytes(4, 'little', signed=True)`.
#
# THE PATCH IS THE PORT AND THE DICTS ARE NOT. `targets` is keyed by a UOp's `tag` (a
# Python object) and `jumps` by the UOp itself, and the substrate's `Map` is keyed by a
# `Nat`/`String`. Two lists in `render`'s own recording order plus a scan by tag name is
# the whole of what the dicts hold, and the walk that fills them is not here either:
# `render`'s loop is `raise`-on-unencodable and `LOOP_CMP`-skipping over the uops.
# `TODO(p3) x86.py:752`.
#
# WHAT IS PORTED IS THE PART THAT HAD A REAL QUESTION IN IT: the delta is SIGNED and it
# is packed little-endian, so a BACKWARD jump produces a negative delta and
# `to_bytes(4, 'little', signed=True)` is two's complement. `U32.sub` WRAPS -- it is
# `Word.sub(32n, x, y)` -- so the arithmetic agrees, and the `render.*` rows exist to
# SAY SO rather than to leave it as a claim. `Render.target` was an identity with a name
# on it and is gone.
# ===========================================================================

def Render.delta(+target: U32, +t: U32) -> U32:
  # `(targets[u.tag] - t)` -- and `U32.sub` wraps, which is what `signed=True` asks for.
  U32.sub(target, t)

def Render.le4(+v: U32) -> String:
  # `.to_bytes(4, 'little')` -- byte 0 first, so `Hex.byte` of the low word first. It is
  # not `Hex.bytes(Enc.imm_int(4n, 4n, v))`, though the two agree, and saying so is
  # cheaper than proving it.
  String.concat([Hex.byte(v), Hex.byte(U32.shrn(v, 8n)), Hex.byte(U32.shrn(v, 16n)),
    Hex.byte(U32.shrn(v, 24n))])

def RegTriple(+r: Reg) -> String:
  # `name index size`. CPython's `repr(Register)` is the NAME alone (isa/__init__.py:19)
  # and the index and size are the two numbers that decide what the register means.
  String.concat([Reg.name(r), " ", U32.show(Reg.index(r)), " ", U32.show(Reg.size(r))])

def RegName(+r: Reg) -> String: Reg.name(r)

def RegNames.go(rs: List<&2, Reg>, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}: acc
    case h <> t: RegNames.go(t, List.append(&2, String, acc, [Reg.name(h)]))

def RegNames(rs: List<&2, Reg>) -> String: String.join(RegNames.go(rs, Nil{}), ",")

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

def RegLen(rs: List<&2, Reg>) -> U32: U32.from_nat(List.length(&2, Reg, rs))

def Enc.has_reg_s.of(+hr: Bool, +r: U32) -> String:
  match hr:
    case True{}: U32.show(r)
    case False{}: "-"

def Enc.has_reg_s(+e: Enc) -> String: Enc.has_reg_s.of(Enc.has_reg(e), Enc.reg(e))

def EncRow.lex(+e: Enc) -> String:
  String.concat(["opc=", U32.show(Enc.opc(e)), ",reg=", Enc.has_reg_s(e), ",pp=-,sel=-,we=-"])

# FOUR SELECTORS AND NOT THREE: `we=1` on `VMOVQ`/`VMOVQm` is a CONSTANT, and
# `we=x.src[1].dtype.itemsize == 8` on the two `VCVTSI2` is a different expression from
# `we=x.dtype.itemsize == 8` on the two `VCVTT*SI`. MEASURED: with three selectors the
# `VMOVQ` row printed `x.dtype.itemsize == 8` where CPython's `ast` read a literal `1`,
# because the constant and the `src[1]` expression had been collapsed together.

def Enc.we_s.of(selw: U32) -> String:
  match selw:
    case 1: "1"
    case 2: "x.src[1].dtype.itemsize == 8"
    case 3: "x.dtype.itemsize == 8"
    case _: "-"

def Enc.we_s(+e: Enc) -> String:
  # `we=x.src[1].dtype.itemsize == 8` for the two VCVTSI2, `we=x.dtype.itemsize == 8`
  # for the two VCVTT*SI, `-` for the rest. The port stores a SELECTOR, and printing
  # the SOURCE EXPRESSION rather than the selector is what keeps the two apart.
  Enc.we_s.of(Enc.we_sel(e))

def EncRow.vex(+e: Enc, sel: U32) -> String:
  String.concat(["opc=", U32.show(Enc.opc(e)), ",reg=", Enc.has_reg_s(e), ",pp=",
    U32.show(Enc.pp(e)), ",sel=", U32.show(sel), ",we=", Enc.we_s(e)])

def EncRow.of(+e: Enc, +sel: U32) -> String:
  match sel:
    case 0: EncRow.lex(e)
    case _: EncRow.vex(e, sel)

def Enc.is_none(e: Enc) -> Bool: String.eq(Enc.name(e), "-")

def EncRow.none.of(+e: Enc, isnone: Bool) -> String:
  match isnone:
    case True{}: "none"
    case False{}: EncRow.of(e, Enc.sel(e))

# THE FIVE PARAMETERS AS ONE STRING. `-` is Python's "the keyword was not passed", and
# `we` prints the SOURCE EXPRESSION for the two computed cases and the LITERAL for the
# two that carry one.

def EncRow(+nm: String) -> String:
  EncRow.none.of(enc_find(nm), Enc.is_none(enc_find(nm)))

def enc_count_walk.go(es: List<&2, Enc>, +i: U32) -> U32:
  match es:
    case Nil{}: i
    case h <> t: enc_count_walk.go(t, U32.inc(i))

def enc_count_walk() -> U32: enc_count_walk.go(enc_table(), 0)

def Enc.direct_names() -> List<&2, String>:
  ["MOVABS", "JMP", "RET", "JE", "JNE", "JL", "JB", "JGE"]

# `x86.py:761` raises for an op with no `encodings` entry, and the four that have none
# are the four that are not instructions. The list is the PORT's own miss answer walked
# over the enum, so `enc.missing` cannot disagree with `enc.norow <NAME>`.

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

# THE FOUR THAT MISS, AND NOT THE TWELVE THAT LOOK LIKE IT. An op has no `encode`
# PARAMETERS either because it is not an instruction (`DEFINE`, `LABEL`,
# `FRAME_INDEX`, `LOOP_CMP`) or because it builds its BYTES DIRECTLY (the six jumps,
# `JMP`, `RET`, `MOVABS`) -- and the second group IS in `encodings`. Walking
# `enc_find`'s miss without the `is_direct` test listed all twelve, which is what the
# `enc.missing` row showed on the first run.

def Enc.is_miss(+nm: String) -> U32:
  # AN ARM INDEX AND NOT A `Bool`, because a `match` may only scrutinise a PARAMETER
  # and `Enc.is_miss(nm)` is computed -- convention 4, and the compiler says so.
  Bool.pick(U32, Bool.and(String.eq(Enc.name(enc_find(nm)), "-"), Bool.not(Enc.is_direct(nm))), 1, 0)

def Enc.missing.of(+nm: String, +acc: List<&2, String>, arm: U32) -> List<&2, String>:
  match arm:
    case 1: List.append(&2, String, acc, [nm])
    case _: acc

def Enc.missing.go(ns: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case +h <> t: Enc.missing.go(t, Enc.missing.of(h, acc, Enc.is_miss(h)))

def Enc.missing() -> List<&2, String>: Enc.missing.go(op_names(), Nil{})

def enc_missing_names() -> String: String.join(Enc.missing(), ",")

# THERE ARE NO `hex.*` ROWS FOR `VMOVDm`, `VMOVQm` OR `VCVTPS2PH`, and there is a reason
# that is CPython's and not this port's: their fixtures make `encode` RAISE -- the last
# two hit `TypeError` in CPython's own `_encode` call, whose arity is exhausted by the
# four-src WriteMem shape, and `VCVTPS2PH` reaches `rdef(reg_uop).index` on a None --
# so there is no byte string to assert and no numbers to hand the port. Their ENCODING
# PARAMETERS are gated anyway, as the `enc.*` rows for those three names.
#
# The first cut gave them a row reading `NOT-ENCODABLE`, which was a string
# concatenation: `HexBad` returned a literal for every input, so the row asserted nothing
# and three of them were as unfalsifiable as the eighty `hex.*` rows. `HexBad` is GONE.

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

def Cls.base_dtypes_list() -> List<&2, String>:
  # `Renderer.supported_dtypes()` (renderer/__init__.py:85) -- SEVENTEEN names. That
  # set lives in ANOTHER file, so it is DATA here and not a derivation, and it is gated
  # because the filter below is only interesting over a real input.
  ["bf16", "bool", "f16", "f32", "f64", "fp8e4m3", "fp8e4m3fnuz", "fp8e5m2",
    "fp8e5m2fnuz", "i16", "i32", "i64", "i8", "u16", "u32", "u64", "u8"]

def Cls.base_dtypes() -> String: String.join(Cls.base_dtypes_list(), ",")

def Cls.base_dtypes_n() -> U32: U32.from_nat(List.length(&2, String, Cls.base_dtypes_list()))

def Cls.drop_dtypes_list() -> List<&2, String>:
  # `dtypes.fp8s + (dtypes.bfloat16,)` -- the FOUR fp8 flavours and bfloat16, SORTED
  # because CPython builds a set and has no order.
  ["bf16", "fp8e4m3", "fp8e4m3fnuz", "fp8e5m2", "fp8e5m2fnuz"]

def Cls.drop_dtypes() -> String: String.join(Cls.drop_dtypes_list(), ",")

def Cls.dropped.go(+ds: List<&2, String>, +nm: String) -> Bool:
  match ds:
    case Nil{}: False{}
    case h <> t: Bool.or(String.eq(nm, h), Cls.dropped.go(t, nm))

def Cls.dropped(+nm: String) -> Bool:
  # `d not in dtypes.fp8s+(dtypes.bfloat16,)` -- a MEMBERSHIP test over `drop_dtypes`,
  # which is itself a gated row, so the two halves of the set difference are separate
  # facts and neither is hardcoded into the answer.
  Cls.dropped.go(Cls.drop_dtypes_list(), nm)

def Cls.keep.go(+ns: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  # ONE self-call, and the accumulator is CHOSEN by `Bool.pick` before the call: Bend
  # refuses mutual recursion, so the branch cannot live in a helper that calls back.
  match ns:
    case Nil{}: acc
    case h <> t:
      Cls.keep.go(t, Bool.pick(List<&2, String>, Cls.dropped(h), acc, List.append(&2, String, acc, [h])))

def Cls.supported_dtypes_list() -> List<&2, String>:
  Cls.keep.go(Cls.base_dtypes_list(), Nil{})

def Cls.supported_dtypes() -> String:
  # `{d for d in super().supported_dtypes() if d not in dtypes.fp8s+(dtypes.bfloat16,)}`
  # -- a SET DIFFERENCE walked over `Cls.base_dtypes`. The input is sorted and the walk
  # keeps order, so the answer is sorted, which is what CPython's `sorted()` asks for.
  # THE FIRST CUT RETURNED THE ANSWER AS A LITERAL, so the filter asserted NOTHING, and
  # it spelled the names "short"/"int"/"long"/"double" -- the C spellings tinygrad moved
  # off in 793abbb (see the head of `LAWS/spec.bend`'s `Dt` and `Op.to_int` above).
  String.join(Cls.supported_dtypes_list(), ",")

def Cls.supported_dtypes_n() -> U32:
  U32.from_nat(List.length(&2, String, Cls.supported_dtypes_list()))

# THE GATE STATE: **774 ROWS, `diff` AGAINST CPython EMPTY, BOTH LANES BYTE-IDENTICAL.**
# That diff -- not the exit status of `--check-only`, which is 1 on a clean file because
# `dtype.bend` has 14 unfilled laws -- is the acceptance test for this file, and it is
# STRONGER than "ALL PROOFS CHECK", which is what the previous 723-row version printed
# while eighty of its rows disagreed with CPython.
#
# WHY THE ROWS ARE NOW STRONGER. The eighty `hex.*` and `direct.*` rows were BARE STRING
# CONCATENATIONS: `"hex.LEA = [" ++ Hex.bytes(Enc.emit(...)) ++ "]   py=[488d948c08000000]"`.
# Nothing in the file asserted anything about them; their correctness lived only in a
# human running a diff, and all eighty disagreed. Every one of them is a `Bool` row now --
# `Bool.show(String.eq(Hex.bytes(Enc.emit(...)), "<CPython's bytes>"))` -- with the
# expected bytes carried in the ROW NAME so the mutation harness still names what it
# moved. A row that cannot fail is worse than no row in this project: that is how
# `device.bend` shipped `sig=0 4 5`.
#
# WHAT WAS ACTUALLY WRONG IN THE ENCODER, since every individual byte def was correct:
#   * `Enc.legacy_head` ENDED IN THE OPCODE and `Enc.emit.tail` appended it AGAIN, so
#     every instruction carried its opcode twice and lost its displacement and immediate.
#     The head is prefix/REX/VEX only now, and there is ONE call site for the opcode.
#   * `Enc.imm_int` APPENDED byte `n-k` after the tail, building the immediate in BIG
#     endian order. `MOVABS 0` came out `48b80000000000001234` for CPython's
#     `48b83412000000000000`.
#   * `Enc.tail_bytes` emitted the displacement when `mod == 0` and dropped it otherwise
#     -- wrong predicate AND inverted flag. It is `mod < 3`.
#   * `Enc.needs_rex` read `reg_sz == 1 and reg >= 4` for `reg_sz == 1 & reg >> 2`. In
#     Python `&` binds tighter than `==`, so that is `reg_sz == (1 & (reg >> 2))`, which
#     is why `MOVi` and the four `SET*` carry a null `0x40` REX byte and the port dropped
#     it. `Enc.rex_bit2` is that predicate now.
#   * `Enc.demote_of` ANDed in `disp_uop is None`, which is the third clause of the REX
#     test and not of `demote`.
#   * `Enc.we_of` read `rm_sz` for `x.src[1].dtype.itemsize` and `reg_sz` for
#     `x.dtype.itemsize`, and treated `we=1` as a size test. `Enc.emit` takes `xsz` and
#     `src1sz` now -- the two numbers those expressions read and neither of which is
#     `reg_sz` or `rm_sz` -- and selector 1 is the Constant it is.
#   * `Enc.direct("JMP")` emitted six bytes. `JMP` has ONE opcode and FIVE bytes; the
#     other five jumps have two opcodes and SIX.
#   * `Enc.opcode_bytes` was fed the table's UNdemoted opcode rather than the demoted one.
#   * THE ORACLE WAS ALSO WRONG, and that is the finding worth keeping. `enc_inputs` used
#     to RE-TRANSCRIBE `encode`'s three arms and was wrong three ways at once: it inverted
#     the Rm2nd `x.dtype is not void` test, it ignored the `if reg is None` fork on every
#     arm, and it hardcoded a four-name list for `vvvv`. So the port was handed SHL's
#     `reg` as 0 where CPython keeps the table's 4, CMP's as 5 where CPython has 2, and
#     VPSRLDQ's `vvvv` as 0 where CPython has 2. `enc_inputs` now READS THE LIVE FRAME of
#     `encode`/`_encode` through a line tracer -- the fourth route into agent-core.md's
#     "a row that re-transcribes agrees with a port that misread it". The `py=` halves
#     were never touched: they were always CPython's own bytes.
#
# THE GATE. Every row below is GENERATED -- `.agents/slop/x86/x86-oracle.py gate`, written
# in place by `.agents/slop/x86/x86-gen.py` -- and every `py=` half is CPython calling
# `tinygrad/renderer/isa/x86.py` on THIS tree. NO `py=` LITERAL IN THIS FILE IS TYPED.
#
#   .venv/bin/python .agents/slop/x86/x86-oracle.py rows > .agents/slop/x86/py1.txt
#   ./bin/bend tinybendygrad/renderer/isa/x86.bend > .agents/slop/x86/i.txt
#   diff .agents/slop/x86/i.txt .agents/slop/x86/py1.txt && echo GATE GREEN

def Gate.rows0() -> List<&2, String>: [
   "reg.gpr rax = [" ++ RegTriple(Reg.gpr(0)) ++ "]   py=[rax 0 8]"
   "reg.gpr rcx = [" ++ RegTriple(Reg.gpr(1)) ++ "]   py=[rcx 1 8]"
   "reg.gpr rdx = [" ++ RegTriple(Reg.gpr(2)) ++ "]   py=[rdx 2 8]"
   "reg.gpr rbx = [" ++ RegTriple(Reg.gpr(3)) ++ "]   py=[rbx 3 8]"
   "reg.gpr rsp = [" ++ RegTriple(Reg.gpr(4)) ++ "]   py=[rsp 4 8]"
   "reg.gpr rbp = [" ++ RegTriple(Reg.gpr(5)) ++ "]   py=[rbp 5 8]"
   "reg.gpr rsi = [" ++ RegTriple(Reg.gpr(6)) ++ "]   py=[rsi 6 8]"
   "reg.gpr rdi = [" ++ RegTriple(Reg.gpr(7)) ++ "]   py=[rdi 7 8]"
   "reg.gpr r8 = [" ++ RegTriple(Reg.gpr(8)) ++ "]   py=[r8 8 8]"
   "reg.gpr r9 = [" ++ RegTriple(Reg.gpr(9)) ++ "]   py=[r9 9 8]"
   "reg.gpr r10 = [" ++ RegTriple(Reg.gpr(10)) ++ "]   py=[r10 10 8]"
   "reg.gpr r11 = [" ++ RegTriple(Reg.gpr(11)) ++ "]   py=[r11 11 8]"
   "reg.gpr r12 = [" ++ RegTriple(Reg.gpr(12)) ++ "]   py=[r12 12 8]"
   "reg.gpr r13 = [" ++ RegTriple(Reg.gpr(13)) ++ "]   py=[r13 13 8]"
   "reg.gpr r14 = [" ++ RegTriple(Reg.gpr(14)) ++ "]   py=[r14 14 8]"
   "reg.gpr r15 = [" ++ RegTriple(Reg.gpr(15)) ++ "]   py=[r15 15 8]"
   "reg.xmm xmm0 = [" ++ RegTriple(Reg.xmm(0)) ++ "]   py=[xmm0 0 16]"
   "reg.xmm xmm1 = [" ++ RegTriple(Reg.xmm(1)) ++ "]   py=[xmm1 1 16]"
   "reg.xmm xmm2 = [" ++ RegTriple(Reg.xmm(2)) ++ "]   py=[xmm2 2 16]"
   "reg.xmm xmm3 = [" ++ RegTriple(Reg.xmm(3)) ++ "]   py=[xmm3 3 16]"
   "reg.xmm xmm4 = [" ++ RegTriple(Reg.xmm(4)) ++ "]   py=[xmm4 4 16]"
   "reg.xmm xmm5 = [" ++ RegTriple(Reg.xmm(5)) ++ "]   py=[xmm5 5 16]"
   "reg.xmm xmm6 = [" ++ RegTriple(Reg.xmm(6)) ++ "]   py=[xmm6 6 16]"
   "reg.xmm xmm7 = [" ++ RegTriple(Reg.xmm(7)) ++ "]   py=[xmm7 7 16]"
   "reg.xmm xmm8 = [" ++ RegTriple(Reg.xmm(8)) ++ "]   py=[xmm8 8 16]"
   "reg.xmm xmm9 = [" ++ RegTriple(Reg.xmm(9)) ++ "]   py=[xmm9 9 16]"
   "reg.xmm xmm10 = [" ++ RegTriple(Reg.xmm(10)) ++ "]   py=[xmm10 10 16]"
   "reg.xmm xmm11 = [" ++ RegTriple(Reg.xmm(11)) ++ "]   py=[xmm11 11 16]"
   "reg.xmm xmm12 = [" ++ RegTriple(Reg.xmm(12)) ++ "]   py=[xmm12 12 16]"
   "reg.xmm xmm13 = [" ++ RegTriple(Reg.xmm(13)) ++ "]   py=[xmm13 13 16]"
   "reg.xmm xmm14 = [" ++ RegTriple(Reg.xmm(14)) ++ "]   py=[xmm14 14 16]"
   "reg.xmm xmm15 = [" ++ RegTriple(Reg.xmm(15)) ++ "]   py=[xmm15 15 16]"
   "reg.gprrev 0 = [" ++ RegName(Reg.gpr_at(0)) ++ "]   py=[rax]"
   "reg.gprrev 1 = [" ++ RegName(Reg.gpr_at(1)) ++ "]   py=[rcx]"
   "reg.gprrev 2 = [" ++ RegName(Reg.gpr_at(2)) ++ "]   py=[rdx]"
   "reg.gprrev 3 = [" ++ RegName(Reg.gpr_at(3)) ++ "]   py=[rbx]"
   "reg.gprrev 4 = [" ++ RegName(Reg.gpr_at(4)) ++ "]   py=[rsp]"
   "reg.gprrev 5 = [" ++ RegName(Reg.gpr_at(5)) ++ "]   py=[rbp]"
   "reg.gprrev 6 = [" ++ RegName(Reg.gpr_at(6)) ++ "]   py=[rsi]"
   "reg.gprrev 7 = [" ++ RegName(Reg.gpr_at(7)) ++ "]   py=[rdi]"
   "reg.gprrev 8 = [" ++ RegName(Reg.gpr_at(8)) ++ "]   py=[r8]"
   "reg.gprrev 9 = [" ++ RegName(Reg.gpr_at(9)) ++ "]   py=[r9]"
   "reg.gprrev 10 = [" ++ RegName(Reg.gpr_at(10)) ++ "]   py=[r10]"
   "reg.gprrev 11 = [" ++ RegName(Reg.gpr_at(11)) ++ "]   py=[r11]"
   "reg.gprrev 12 = [" ++ RegName(Reg.gpr_at(12)) ++ "]   py=[r12]"
   "reg.gprrev 13 = [" ++ RegName(Reg.gpr_at(13)) ++ "]   py=[r13]"
   "reg.gprrev 14 = [" ++ RegName(Reg.gpr_at(14)) ++ "]   py=[r14]"
   "reg.gprrev 15 = [" ++ RegName(Reg.gpr_at(15)) ++ "]   py=[r15]"
   "reg.xmmrev 0 = [" ++ RegName(Reg.xmm_at(0)) ++ "]   py=[xmm0]"
   "reg.xmmrev 1 = [" ++ RegName(Reg.xmm_at(1)) ++ "]   py=[xmm1]"
   "reg.xmmrev 2 = [" ++ RegName(Reg.xmm_at(2)) ++ "]   py=[xmm2]"
   "reg.xmmrev 3 = [" ++ RegName(Reg.xmm_at(3)) ++ "]   py=[xmm3]"
   "reg.xmmrev 4 = [" ++ RegName(Reg.xmm_at(4)) ++ "]   py=[xmm4]"
   "reg.xmmrev 5 = [" ++ RegName(Reg.xmm_at(5)) ++ "]   py=[xmm5]"
   "reg.xmmrev 6 = [" ++ RegName(Reg.xmm_at(6)) ++ "]   py=[xmm6]"
   "reg.xmmrev 7 = [" ++ RegName(Reg.xmm_at(7)) ++ "]   py=[xmm7]"
   "reg.xmmrev 8 = [" ++ RegName(Reg.xmm_at(8)) ++ "]   py=[xmm8]"
   "reg.xmmrev 9 = [" ++ RegName(Reg.xmm_at(9)) ++ "]   py=[xmm9]"
   "reg.xmmrev 10 = [" ++ RegName(Reg.xmm_at(10)) ++ "]   py=[xmm10]"
   "reg.xmmrev 11 = [" ++ RegName(Reg.xmm_at(11)) ++ "]   py=[xmm11]"
   "reg.xmmrev 12 = [" ++ RegName(Reg.xmm_at(12)) ++ "]   py=[xmm12]"
   "reg.xmmrev 13 = [" ++ RegName(Reg.xmm_at(13)) ++ "]   py=[xmm13]"
   "reg.xmmrev 14 = [" ++ RegName(Reg.xmm_at(14)) ++ "]   py=[xmm14]"
   "reg.xmmrev 15 = [" ++ RegName(Reg.xmm_at(15)) ++ "]   py=[xmm15]"
   "reg.GPR = [" ++ RegNames(Reg.gpr_list()) ++ "]   py=[rax,rcx,rdx,rbx,rsp,rbp,rsi,rdi,r8,r9,r10,r11,r12,r13,r14,r15]"
   "reg.WGPR = [" ++ RegNames(Reg.wgpr_list()) ++ "]   py=[rax,rcx,rdx,rbx,rbp,rsi,rdi,r8,r9,r10,r11,r12,r13,r14,r15]"
   "reg.XMM = [" ++ RegNames(Reg.xmm_list()) ++ "]   py=[xmm0,xmm1,xmm2,xmm3,xmm4,xmm5,xmm6,xmm7,xmm8,xmm9,xmm10,xmm11,xmm12,xmm13,xmm14,xmm15]"
   "reg.CALLEE = [" ++ RegNames(Reg.callee_list()) ++ "]   py=[rbx,rbp,r12,r13,r14,r15]"
   "reg.strs.rax = [" ++ RegStrRow(Reg.gpr(0)) ++ "]   py=[al,ax,eax]"
   "reg.strs.rcx = [" ++ RegStrRow(Reg.gpr(1)) ++ "]   py=[cl,cx,ecx]"
   "reg.strs.rdx = [" ++ RegStrRow(Reg.gpr(2)) ++ "]   py=[dl,dx,edx]"
   "reg.strs.rbx = [" ++ RegStrRow(Reg.gpr(3)) ++ "]   py=[bl,bx,ebx]"
   "reg.strs.rsp = [" ++ RegStrRow(Reg.gpr(4)) ++ "]   py=[spl,sp,esp]"
   "reg.strs.rbp = [" ++ RegStrRow(Reg.gpr(5)) ++ "]   py=[bpl,bp,ebp]"
   "reg.strs.rsi = [" ++ RegStrRow(Reg.gpr(6)) ++ "]   py=[sil,si,esi]"
   "reg.strs.rdi = [" ++ RegStrRow(Reg.gpr(7)) ++ "]   py=[dil,di,edi]"
   "reg.strs.r8 = [" ++ RegStrRow(Reg.gpr(8)) ++ "]   py=[r8b,r8w,r8d]"
   "reg.strs.r12 = [" ++ RegStrRow(Reg.gpr(12)) ++ "]   py=[r12b,r12w,r12d]"
   "reg.strs.r15 = [" ++ RegStrRow(Reg.gpr(15)) ++ "]   py=[r15b,r15w,r15d]"
   "reg.strs.xmm0 = [" ++ RegStrRow(Reg.xmm(0)) ++ "]   py=[xmm0,xmm0,xmm0]"
   "reg.stackptr = [" ++ RegTriple(Reg.gpr_at(4)) ++ "]   py=[rsp 4 8]"
   "reg.WGPRn = [" ++ U32.show(RegLen(Reg.wgpr_list())) ++ "]   py=[15]"
   "reg.get rax 1 = [" ++ Reg.strs_lookup("rax", 1) ++ "]   py=[al]"
   "reg.get rax 2 = [" ++ Reg.strs_lookup("rax", 2) ++ "]   py=[ax]"
   "reg.get rax 4 = [" ++ Reg.strs_lookup("rax", 4) ++ "]   py=[eax]"
   "reg.get rax 8 = [" ++ Reg.strs_lookup("rax", 8) ++ "]   py=[rax]"
   "reg.get rax 16 = [" ++ Reg.strs_lookup("rax", 16) ++ "]   py=[rax]"
   "reg.get rsp 1 = [" ++ Reg.strs_lookup("rsp", 1) ++ "]   py=[spl]"
 ]

def Gate.rows1() -> List<&2, String>: [
   "reg.get rsp 2 = [" ++ Reg.strs_lookup("rsp", 2) ++ "]   py=[sp]"
   "reg.get rsp 4 = [" ++ Reg.strs_lookup("rsp", 4) ++ "]   py=[esp]"
   "reg.get rsp 8 = [" ++ Reg.strs_lookup("rsp", 8) ++ "]   py=[rsp]"
   "reg.get rsp 16 = [" ++ Reg.strs_lookup("rsp", 16) ++ "]   py=[rsp]"
   "reg.get r12 1 = [" ++ Reg.strs_lookup("r12", 1) ++ "]   py=[r12b]"
   "reg.get r12 2 = [" ++ Reg.strs_lookup("r12", 2) ++ "]   py=[r12w]"
   "reg.get r12 4 = [" ++ Reg.strs_lookup("r12", 4) ++ "]   py=[r12d]"
   "reg.get r12 8 = [" ++ Reg.strs_lookup("r12", 8) ++ "]   py=[r12]"
   "reg.get r12 16 = [" ++ Reg.strs_lookup("r12", 16) ++ "]   py=[r12]"
   "reg.get xmm0 1 = [" ++ Reg.strs_lookup("xmm0", 1) ++ "]   py=[xmm0]"
   "reg.get xmm0 2 = [" ++ Reg.strs_lookup("xmm0", 2) ++ "]   py=[xmm0]"
   "reg.get xmm0 4 = [" ++ Reg.strs_lookup("xmm0", 4) ++ "]   py=[xmm0]"
   "reg.get xmm0 8 = [" ++ Reg.strs_lookup("xmm0", 8) ++ "]   py=[xmm0]"
   "reg.get xmm0 16 = [" ++ Reg.strs_lookup("xmm0", 16) ++ "]   py=[xmm0]"
   "reg.get nope 1 = [" ++ Reg.strs_lookup("nope", 1) ++ "]   py=[nope]"
   "reg.get nope 2 = [" ++ Reg.strs_lookup("nope", 2) ++ "]   py=[nope]"
   "reg.get nope 4 = [" ++ Reg.strs_lookup("nope", 4) ++ "]   py=[nope]"
   "reg.get nope 8 = [" ++ Reg.strs_lookup("nope", 8) ++ "]   py=[nope]"
   "reg.get nope 16 = [" ++ Reg.strs_lookup("nope", 16) ++ "]   py=[nope]"
   "reg.callee 0 = [" ++ Bool.show(Reg.is_callee(0)) ++ "]   py=[False]"
   "reg.callee 1 = [" ++ Bool.show(Reg.is_callee(1)) ++ "]   py=[False]"
   "reg.callee 2 = [" ++ Bool.show(Reg.is_callee(2)) ++ "]   py=[False]"
   "reg.callee 3 = [" ++ Bool.show(Reg.is_callee(3)) ++ "]   py=[True]"
   "reg.callee 4 = [" ++ Bool.show(Reg.is_callee(4)) ++ "]   py=[False]"
   "reg.callee 5 = [" ++ Bool.show(Reg.is_callee(5)) ++ "]   py=[True]"
   "reg.callee 6 = [" ++ Bool.show(Reg.is_callee(6)) ++ "]   py=[False]"
   "reg.callee 7 = [" ++ Bool.show(Reg.is_callee(7)) ++ "]   py=[False]"
   "reg.callee 8 = [" ++ Bool.show(Reg.is_callee(8)) ++ "]   py=[False]"
   "reg.callee 9 = [" ++ Bool.show(Reg.is_callee(9)) ++ "]   py=[False]"
   "reg.callee 10 = [" ++ Bool.show(Reg.is_callee(10)) ++ "]   py=[False]"
   "reg.callee 11 = [" ++ Bool.show(Reg.is_callee(11)) ++ "]   py=[False]"
   "reg.callee 12 = [" ++ Bool.show(Reg.is_callee(12)) ++ "]   py=[True]"
   "reg.callee 13 = [" ++ Bool.show(Reg.is_callee(13)) ++ "]   py=[True]"
   "reg.callee 14 = [" ++ Bool.show(Reg.is_callee(14)) ++ "]   py=[True]"
   "reg.callee 15 = [" ++ Bool.show(Reg.is_callee(15)) ++ "]   py=[True]"
   "op.FRAME_INDEX = [" ++ op_num("FRAME_INDEX") ++ "]   py=[78]"
   "op.LABEL = [" ++ op_num("LABEL") ++ "]   py=[79]"
   "op.DEFINE = [" ++ op_num("DEFINE") ++ "]   py=[80]"
   "op.LOOP_CMP = [" ++ op_num("LOOP_CMP") ++ "]   py=[81]"
   "op.LEA = [" ++ op_num("LEA") ++ "]   py=[82]"
   "op.MOV = [" ++ op_num("MOV") ++ "]   py=[83]"
   "op.MOVm = [" ++ op_num("MOVm") ++ "]   py=[84]"
   "op.MOVi = [" ++ op_num("MOVi") ++ "]   py=[85]"
   "op.MOVABS = [" ++ op_num("MOVABS") ++ "]   py=[86]"
   "op.VMOVSS = [" ++ op_num("VMOVSS") ++ "]   py=[87]"
   "op.VMOVSD = [" ++ op_num("VMOVSD") ++ "]   py=[88]"
   "op.VMOVUPS = [" ++ op_num("VMOVUPS") ++ "]   py=[89]"
   "op.VMOVSSm = [" ++ op_num("VMOVSSm") ++ "]   py=[90]"
   "op.VMOVSDm = [" ++ op_num("VMOVSDm") ++ "]   py=[91]"
   "op.VMOVUPSm = [" ++ op_num("VMOVUPSm") ++ "]   py=[92]"
   "op.MOVZX = [" ++ op_num("MOVZX") ++ "]   py=[93]"
   "op.MOVSX = [" ++ op_num("MOVSX") ++ "]   py=[94]"
   "op.MOVSXD = [" ++ op_num("MOVSXD") ++ "]   py=[95]"
   "op.VCVTPH2PS = [" ++ op_num("VCVTPH2PS") ++ "]   py=[96]"
   "op.VCVTPS2PH = [" ++ op_num("VCVTPS2PH") ++ "]   py=[97]"
   "op.VCVTSS2SD = [" ++ op_num("VCVTSS2SD") ++ "]   py=[98]"
   "op.VCVTSD2SS = [" ++ op_num("VCVTSD2SS") ++ "]   py=[99]"
   "op.VCVTSI2SS = [" ++ op_num("VCVTSI2SS") ++ "]   py=[100]"
   "op.VCVTSI2SD = [" ++ op_num("VCVTSI2SD") ++ "]   py=[101]"
   "op.VCVTTSS2SI = [" ++ op_num("VCVTTSS2SI") ++ "]   py=[102]"
   "op.VCVTTSD2SI = [" ++ op_num("VCVTTSD2SI") ++ "]   py=[103]"
   "op.VMOVD = [" ++ op_num("VMOVD") ++ "]   py=[104]"
   "op.VMOVQ = [" ++ op_num("VMOVQ") ++ "]   py=[105]"
   "op.VMOVDm = [" ++ op_num("VMOVDm") ++ "]   py=[106]"
   "op.VMOVQm = [" ++ op_num("VMOVQm") ++ "]   py=[107]"
   "op.VCMPSS = [" ++ op_num("VCMPSS") ++ "]   py=[108]"
   "op.VCMPSD = [" ++ op_num("VCMPSD") ++ "]   py=[109]"
   "op.SETNE = [" ++ op_num("SETNE") ++ "]   py=[110]"
   "op.SETE = [" ++ op_num("SETE") ++ "]   py=[111]"
   "op.SETL = [" ++ op_num("SETL") ++ "]   py=[112]"
   "op.SETB = [" ++ op_num("SETB") ++ "]   py=[113]"
   "op.CMOVNE = [" ++ op_num("CMOVNE") ++ "]   py=[114]"
   "op.CMOVE = [" ++ op_num("CMOVE") ++ "]   py=[115]"
   "op.CMOVL = [" ++ op_num("CMOVL") ++ "]   py=[116]"
   "op.CMOVB = [" ++ op_num("CMOVB") ++ "]   py=[117]"
   "op.VBLENDVPS = [" ++ op_num("VBLENDVPS") ++ "]   py=[118]"
   "op.VBLENDVPD = [" ++ op_num("VBLENDVPD") ++ "]   py=[119]"
   "op.JNE = [" ++ op_num("JNE") ++ "]   py=[120]"
   "op.JE = [" ++ op_num("JE") ++ "]   py=[121]"
   "op.JL = [" ++ op_num("JL") ++ "]   py=[122]"
   "op.JB = [" ++ op_num("JB") ++ "]   py=[123]"
   "op.JGE = [" ++ op_num("JGE") ++ "]   py=[124]"
   "op.JMP = [" ++ op_num("JMP") ++ "]   py=[125]"
   "op.VINSERTPS = [" ++ op_num("VINSERTPS") ++ "]   py=[126]"
   "op.VPSRLDQ = [" ++ op_num("VPSRLDQ") ++ "]   py=[127]"
   "op.VPEXTRW = [" ++ op_num("VPEXTRW") ++ "]   py=[128]"
   "op.VPEXTRD = [" ++ op_num("VPEXTRD") ++ "]   py=[129]"
   "op.VPINSRW = [" ++ op_num("VPINSRW") ++ "]   py=[130]"
   "op.VPINSRD = [" ++ op_num("VPINSRD") ++ "]   py=[131]"
   "op.IDIV = [" ++ op_num("IDIV") ++ "]   py=[132]"
   "op.DIV = [" ++ op_num("DIV") ++ "]   py=[133]"
   "op.ADD = [" ++ op_num("ADD") ++ "]   py=[134]"
   "op.ADDi = [" ++ op_num("ADDi") ++ "]   py=[135]"
   "op.SUB = [" ++ op_num("SUB") ++ "]   py=[136]"
   "op.SUBi = [" ++ op_num("SUBi") ++ "]   py=[137]"
   "op.IMUL = [" ++ op_num("IMUL") ++ "]   py=[138]"
   "op.IMULi = [" ++ op_num("IMULi") ++ "]   py=[139]"
   "op.AND = [" ++ op_num("AND") ++ "]   py=[140]"
   "op.ANDi = [" ++ op_num("ANDi") ++ "]   py=[141]"
   "op.XOR = [" ++ op_num("XOR") ++ "]   py=[142]"
   "op.XORi = [" ++ op_num("XORi") ++ "]   py=[143]"
   "op.OR = [" ++ op_num("OR") ++ "]   py=[144]"
   "op.ORi = [" ++ op_num("ORi") ++ "]   py=[145]"
   "op.SHL = [" ++ op_num("SHL") ++ "]   py=[146]"
 ]

def Gate.rows2() -> List<&2, String>: [
   "op.SHLi = [" ++ op_num("SHLi") ++ "]   py=[147]"
   "op.SHR = [" ++ op_num("SHR") ++ "]   py=[148]"
   "op.SHRi = [" ++ op_num("SHRi") ++ "]   py=[149]"
   "op.SAR = [" ++ op_num("SAR") ++ "]   py=[150]"
   "op.SARi = [" ++ op_num("SARi") ++ "]   py=[151]"
   "op.CMP = [" ++ op_num("CMP") ++ "]   py=[152]"
   "op.CMPi = [" ++ op_num("CMPi") ++ "]   py=[153]"
   "op.VROUNDSS = [" ++ op_num("VROUNDSS") ++ "]   py=[154]"
   "op.VROUNDSD = [" ++ op_num("VROUNDSD") ++ "]   py=[155]"
   "op.VSQRTSS = [" ++ op_num("VSQRTSS") ++ "]   py=[156]"
   "op.VSQRTSD = [" ++ op_num("VSQRTSD") ++ "]   py=[157]"
   "op.VADDSS = [" ++ op_num("VADDSS") ++ "]   py=[158]"
   "op.VADDSD = [" ++ op_num("VADDSD") ++ "]   py=[159]"
   "op.VSUBSS = [" ++ op_num("VSUBSS") ++ "]   py=[160]"
   "op.VSUBSD = [" ++ op_num("VSUBSD") ++ "]   py=[161]"
   "op.VMULSS = [" ++ op_num("VMULSS") ++ "]   py=[162]"
   "op.VMULSD = [" ++ op_num("VMULSD") ++ "]   py=[163]"
   "op.VDIVSS = [" ++ op_num("VDIVSS") ++ "]   py=[164]"
   "op.VDIVSD = [" ++ op_num("VDIVSD") ++ "]   py=[165]"
   "op.RET = [" ++ op_num("RET") ++ "]   py=[166]"
   "oprev 78 = [" ++ op_name_of(78) ++ "]   py=[FRAME_INDEX]"
   "oprev 79 = [" ++ op_name_of(79) ++ "]   py=[LABEL]"
   "oprev 80 = [" ++ op_name_of(80) ++ "]   py=[DEFINE]"
   "oprev 81 = [" ++ op_name_of(81) ++ "]   py=[LOOP_CMP]"
   "oprev 82 = [" ++ op_name_of(82) ++ "]   py=[LEA]"
   "oprev 83 = [" ++ op_name_of(83) ++ "]   py=[MOV]"
   "oprev 84 = [" ++ op_name_of(84) ++ "]   py=[MOVm]"
   "oprev 85 = [" ++ op_name_of(85) ++ "]   py=[MOVi]"
   "oprev 86 = [" ++ op_name_of(86) ++ "]   py=[MOVABS]"
   "oprev 87 = [" ++ op_name_of(87) ++ "]   py=[VMOVSS]"
   "oprev 88 = [" ++ op_name_of(88) ++ "]   py=[VMOVSD]"
   "oprev 89 = [" ++ op_name_of(89) ++ "]   py=[VMOVUPS]"
   "oprev 90 = [" ++ op_name_of(90) ++ "]   py=[VMOVSSm]"
   "oprev 91 = [" ++ op_name_of(91) ++ "]   py=[VMOVSDm]"
   "oprev 92 = [" ++ op_name_of(92) ++ "]   py=[VMOVUPSm]"
   "oprev 93 = [" ++ op_name_of(93) ++ "]   py=[MOVZX]"
   "oprev 94 = [" ++ op_name_of(94) ++ "]   py=[MOVSX]"
   "oprev 95 = [" ++ op_name_of(95) ++ "]   py=[MOVSXD]"
   "oprev 96 = [" ++ op_name_of(96) ++ "]   py=[VCVTPH2PS]"
   "oprev 97 = [" ++ op_name_of(97) ++ "]   py=[VCVTPS2PH]"
   "oprev 98 = [" ++ op_name_of(98) ++ "]   py=[VCVTSS2SD]"
   "oprev 99 = [" ++ op_name_of(99) ++ "]   py=[VCVTSD2SS]"
   "oprev 100 = [" ++ op_name_of(100) ++ "]   py=[VCVTSI2SS]"
   "oprev 101 = [" ++ op_name_of(101) ++ "]   py=[VCVTSI2SD]"
   "oprev 102 = [" ++ op_name_of(102) ++ "]   py=[VCVTTSS2SI]"
   "oprev 103 = [" ++ op_name_of(103) ++ "]   py=[VCVTTSD2SI]"
   "oprev 104 = [" ++ op_name_of(104) ++ "]   py=[VMOVD]"
   "oprev 105 = [" ++ op_name_of(105) ++ "]   py=[VMOVQ]"
   "oprev 106 = [" ++ op_name_of(106) ++ "]   py=[VMOVDm]"
   "oprev 107 = [" ++ op_name_of(107) ++ "]   py=[VMOVQm]"
   "oprev 108 = [" ++ op_name_of(108) ++ "]   py=[VCMPSS]"
   "oprev 109 = [" ++ op_name_of(109) ++ "]   py=[VCMPSD]"
   "oprev 110 = [" ++ op_name_of(110) ++ "]   py=[SETNE]"
   "oprev 111 = [" ++ op_name_of(111) ++ "]   py=[SETE]"
   "oprev 112 = [" ++ op_name_of(112) ++ "]   py=[SETL]"
   "oprev 113 = [" ++ op_name_of(113) ++ "]   py=[SETB]"
   "oprev 114 = [" ++ op_name_of(114) ++ "]   py=[CMOVNE]"
   "oprev 115 = [" ++ op_name_of(115) ++ "]   py=[CMOVE]"
   "oprev 116 = [" ++ op_name_of(116) ++ "]   py=[CMOVL]"
   "oprev 117 = [" ++ op_name_of(117) ++ "]   py=[CMOVB]"
   "oprev 118 = [" ++ op_name_of(118) ++ "]   py=[VBLENDVPS]"
   "oprev 119 = [" ++ op_name_of(119) ++ "]   py=[VBLENDVPD]"
   "oprev 120 = [" ++ op_name_of(120) ++ "]   py=[JNE]"
   "oprev 121 = [" ++ op_name_of(121) ++ "]   py=[JE]"
   "oprev 122 = [" ++ op_name_of(122) ++ "]   py=[JL]"
   "oprev 123 = [" ++ op_name_of(123) ++ "]   py=[JB]"
   "oprev 124 = [" ++ op_name_of(124) ++ "]   py=[JGE]"
   "oprev 125 = [" ++ op_name_of(125) ++ "]   py=[JMP]"
   "oprev 126 = [" ++ op_name_of(126) ++ "]   py=[VINSERTPS]"
   "oprev 127 = [" ++ op_name_of(127) ++ "]   py=[VPSRLDQ]"
   "oprev 128 = [" ++ op_name_of(128) ++ "]   py=[VPEXTRW]"
   "oprev 129 = [" ++ op_name_of(129) ++ "]   py=[VPEXTRD]"
   "oprev 130 = [" ++ op_name_of(130) ++ "]   py=[VPINSRW]"
   "oprev 131 = [" ++ op_name_of(131) ++ "]   py=[VPINSRD]"
   "oprev 132 = [" ++ op_name_of(132) ++ "]   py=[IDIV]"
   "oprev 133 = [" ++ op_name_of(133) ++ "]   py=[DIV]"
   "oprev 134 = [" ++ op_name_of(134) ++ "]   py=[ADD]"
   "oprev 135 = [" ++ op_name_of(135) ++ "]   py=[ADDi]"
   "oprev 136 = [" ++ op_name_of(136) ++ "]   py=[SUB]"
   "oprev 137 = [" ++ op_name_of(137) ++ "]   py=[SUBi]"
   "oprev 138 = [" ++ op_name_of(138) ++ "]   py=[IMUL]"
   "oprev 139 = [" ++ op_name_of(139) ++ "]   py=[IMULi]"
   "oprev 140 = [" ++ op_name_of(140) ++ "]   py=[AND]"
   "oprev 141 = [" ++ op_name_of(141) ++ "]   py=[ANDi]"
   "oprev 142 = [" ++ op_name_of(142) ++ "]   py=[XOR]"
   "oprev 143 = [" ++ op_name_of(143) ++ "]   py=[XORi]"
   "oprev 144 = [" ++ op_name_of(144) ++ "]   py=[OR]"
   "oprev 145 = [" ++ op_name_of(145) ++ "]   py=[ORi]"
   "oprev 146 = [" ++ op_name_of(146) ++ "]   py=[SHL]"
   "oprev 147 = [" ++ op_name_of(147) ++ "]   py=[SHLi]"
   "oprev 148 = [" ++ op_name_of(148) ++ "]   py=[SHR]"
   "oprev 149 = [" ++ op_name_of(149) ++ "]   py=[SHRi]"
   "oprev 150 = [" ++ op_name_of(150) ++ "]   py=[SAR]"
   "oprev 151 = [" ++ op_name_of(151) ++ "]   py=[SARi]"
   "oprev 152 = [" ++ op_name_of(152) ++ "]   py=[CMP]"
   "oprev 153 = [" ++ op_name_of(153) ++ "]   py=[CMPi]"
   "oprev 154 = [" ++ op_name_of(154) ++ "]   py=[VROUNDSS]"
   "oprev 155 = [" ++ op_name_of(155) ++ "]   py=[VROUNDSD]"
   "oprev 156 = [" ++ op_name_of(156) ++ "]   py=[VSQRTSS]"
   "oprev 157 = [" ++ op_name_of(157) ++ "]   py=[VSQRTSD]"
   "oprev 158 = [" ++ op_name_of(158) ++ "]   py=[VADDSS]"
   "oprev 159 = [" ++ op_name_of(159) ++ "]   py=[VADDSD]"
   "oprev 160 = [" ++ op_name_of(160) ++ "]   py=[VSUBSS]"
   "oprev 161 = [" ++ op_name_of(161) ++ "]   py=[VSUBSD]"
   "oprev 162 = [" ++ op_name_of(162) ++ "]   py=[VMULSS]"
   "oprev 163 = [" ++ op_name_of(163) ++ "]   py=[VMULSD]"
   "oprev 164 = [" ++ op_name_of(164) ++ "]   py=[VDIVSS]"
   "oprev 165 = [" ++ op_name_of(165) ++ "]   py=[VDIVSD]"
   "oprev 166 = [" ++ op_name_of(166) ++ "]   py=[RET]"
   "op.count = [" ++ U32.show(op_len()) ++ "]   py=[89]"
   "op.unknown = [" ++ op_num("NOSUCH") ++ "]   py=[KeyError]"
 ]

def Gate.rows3() -> List<&2, String>: [
   "op.revbad = [" ++ op_name_of(200) ++ "]   py=[ValueError]"
   "grp.Copy = [" ++ Op.set_name(0) ++ "]   py=[MOV,CMOVNE,CMOVE,CMOVL,CMOVB]"
   "grpn.Copy = [" ++ U32.show(Op.set_len(0)) ++ "]   py=[5]"
   "grp.TwoAddress = [" ++ Op.set_name(1) ++ "]   py=[CMOVNE,CMOVE,CMOVL,CMOVB,IDIV,DIV,ADD,ADDi,SUB,SUBi,IMUL,AND,ANDi,XOR,XORi,OR,ORi,SHL,SHLi,SHR,SHRi,SAR,SARi]"
   "grpn.TwoAddress = [" ++ U32.show(Op.set_len(1)) ++ "]   py=[23]"
   "grp.Rm2nd = [" ++ Op.set_name(2) ++ "]   py=[VCVTSS2SD,VCVTSD2SS,VCVTSI2SS,VCVTSI2SD,VCMPSS,VCMPSD,CMOVNE,CMOVE,CMOVL,CMOVB,VBLENDVPS,VBLENDVPD,VINSERTPS,VPINSRW,VPINSRD,IDIV,DIV,ADD,SUB,IMUL,AND,XOR,OR,CMP,VROUNDSS,VROUNDSD,VSQRTSS,VSQRTSD,VADDSS,VADDSD,VSUBSS,VSUBSD,VMULSS,VMULSD,VDIVSS,VDIVSD]"
   "grpn.Rm2nd = [" ++ U32.show(Op.set_len(2)) ++ "]   py=[36]"
   "grp.WriteMem = [" ++ Op.set_name(3) ++ "]   py=[MOVm,MOVi,VMOVSSm,VMOVSDm,VMOVUPSm,VCVTPS2PH,VMOVDm,VMOVQm,SETNE,SETE,SETL,SETB,VPEXTRW,VPEXTRD,ADDi,SUBi,ANDi,XORi,ORi,SHL,SHLi,SHR,SHRi,SAR,SARi]"
   "grpn.WriteMem = [" ++ U32.show(Op.set_len(3)) ++ "]   py=[25]"
   "grp.ReadFlags = [" ++ Op.set_name(4) ++ "]   py=[SETNE,SETE,SETL,SETB,CMOVNE,CMOVE,CMOVL,CMOVB,JNE,JE,JL,JB,JGE]"
   "grpn.ReadFlags = [" ++ U32.show(Op.set_len(4)) ++ "]   py=[13]"
   "grp.WriteFlags = [" ++ Op.set_name(5) ++ "]   py=[IDIV,DIV,ADD,ADDi,SUB,SUBi,IMUL,IMULi,AND,ANDi,XOR,XORi,OR,ORi,SHL,SHLi,SHR,SHRi,SAR,SARi,CMP,CMPi]"
   "grpn.WriteFlags = [" ++ U32.show(Op.set_len(5)) ++ "]   py=[22]"
   "grp.GPR_DEST_OPS = [" ++ Op.set_name(6) ++ "]   py=[VCVTTSS2SI,VCVTTSD2SI,VMOVDm,VMOVQm,VPEXTRW,VPEXTRD]"
   "grpn.GPR_DEST_OPS = [" ++ U32.show(Op.set_len(6)) ++ "]   py=[6]"
   "grp.Rm1st = [" ++ Op.set_name(7) ++ "]   py=[LEA,MOV,VMOVSS,VMOVSD,VMOVUPS,MOVZX,MOVSX,MOVSXD,VCVTPH2PS,VCVTTSS2SI,VCVTTSD2SI,VMOVD,VMOVQ,CMOVNE,CMOVE,CMOVL,CMOVB,VPSRLDQ,IDIV,DIV,ADD,SUB,IMUL,IMULi,AND,XOR,OR,CMPi]"
   "grpn.Rm1st = [" ++ U32.show(Op.set_len(7)) ++ "]   py=[28]"
   "grp.XMM_OPS = [" ++ Op.set_name(8) ++ "]   py=[VMOVSS,VMOVSD,VMOVUPS,VMOVSSm,VMOVSDm,VMOVUPSm,VCVTPH2PS,VCVTPS2PH,VCVTSS2SD,VCVTSD2SS,VCVTSI2SS,VCVTSI2SD,VMOVD,VMOVQ,VCMPSS,VCMPSD,VBLENDVPS,VBLENDVPD,VINSERTPS,VPSRLDQ,VPINSRW,VPINSRD,VROUNDSS,VROUNDSD,VSQRTSS,VSQRTSD,VADDSS,VADDSD,VSUBSS,VSUBSD,VMULSS,VMULSD,VDIVSS,VDIVSD]"
   "grpn.XMM_OPS = [" ++ U32.show(Op.set_len(8)) ++ "]   py=[34]"
   "isz int 1 = [" ++ Op.xmm_sz(4) ++ "]   py=[VMOVSS]"
   "iszm int 1 = [" ++ Op.xmm_sz_m(4) ++ "]   py=[VMOVSSm]"
   "iszbits int 1 = [" ++ U32.show(4) ++ "]   py=[4]"
   "isz int 2 = [" ++ Op.xmm_sz(8) ++ "]   py=[VMOVSD]"
   "iszm int 2 = [" ++ Op.xmm_sz_m(8) ++ "]   py=[VMOVSDm]"
   "iszbits int 2 = [" ++ U32.show(8) ++ "]   py=[8]"
   "isz int 3 = [" ++ Op.xmm_sz(12) ++ "]   py=[VMOVSD]"
   "iszm int 3 = [" ++ Op.xmm_sz_m(12) ++ "]   py=[VMOVSDm]"
   "iszbits int 3 = [" ++ U32.show(12) ++ "]   py=[12]"
   "isz int 4 = [" ++ Op.xmm_sz(16) ++ "]   py=[VMOVUPS]"
   "iszm int 4 = [" ++ Op.xmm_sz_m(16) ++ "]   py=[VMOVUPSm]"
   "iszbits int 4 = [" ++ U32.show(16) ++ "]   py=[16]"
   "isz int 6 = [" ++ Op.xmm_sz(24) ++ "]   py=[VMOVUPS]"
   "iszm int 6 = [" ++ Op.xmm_sz_m(24) ++ "]   py=[VMOVUPSm]"
   "iszbits int 6 = [" ++ U32.show(24) ++ "]   py=[24]"
   "isz int 8 = [" ++ Op.xmm_sz(32) ++ "]   py=[VMOVUPS]"
   "iszm int 8 = [" ++ Op.xmm_sz_m(32) ++ "]   py=[VMOVUPSm]"
   "iszbits int 8 = [" ++ U32.show(32) ++ "]   py=[32]"
   "isz int 16 = [" ++ Op.xmm_sz(64) ++ "]   py=[VMOVUPS]"
   "iszm int 16 = [" ++ Op.xmm_sz_m(64) ++ "]   py=[VMOVUPSm]"
   "iszbits int 16 = [" ++ U32.show(64) ++ "]   py=[64]"
   "isz float 1 = [" ++ Op.xmm_sz(4) ++ "]   py=[VMOVSS]"
   "iszm float 1 = [" ++ Op.xmm_sz_m(4) ++ "]   py=[VMOVSSm]"
   "iszbits float 1 = [" ++ U32.show(4) ++ "]   py=[4]"
   "isz float 2 = [" ++ Op.xmm_sz(8) ++ "]   py=[VMOVSD]"
   "iszm float 2 = [" ++ Op.xmm_sz_m(8) ++ "]   py=[VMOVSDm]"
   "iszbits float 2 = [" ++ U32.show(8) ++ "]   py=[8]"
   "isz float 3 = [" ++ Op.xmm_sz(12) ++ "]   py=[VMOVSD]"
   "iszm float 3 = [" ++ Op.xmm_sz_m(12) ++ "]   py=[VMOVSDm]"
   "iszbits float 3 = [" ++ U32.show(12) ++ "]   py=[12]"
   "isz float 4 = [" ++ Op.xmm_sz(16) ++ "]   py=[VMOVUPS]"
   "iszm float 4 = [" ++ Op.xmm_sz_m(16) ++ "]   py=[VMOVUPSm]"
   "iszbits float 4 = [" ++ U32.show(16) ++ "]   py=[16]"
   "isz float 6 = [" ++ Op.xmm_sz(24) ++ "]   py=[VMOVUPS]"
   "iszm float 6 = [" ++ Op.xmm_sz_m(24) ++ "]   py=[VMOVUPSm]"
   "iszbits float 6 = [" ++ U32.show(24) ++ "]   py=[24]"
   "isz float 8 = [" ++ Op.xmm_sz(32) ++ "]   py=[VMOVUPS]"
   "iszm float 8 = [" ++ Op.xmm_sz_m(32) ++ "]   py=[VMOVUPSm]"
   "iszbits float 8 = [" ++ U32.show(32) ++ "]   py=[32]"
   "isz float 16 = [" ++ Op.xmm_sz(64) ++ "]   py=[VMOVUPS]"
   "iszm float 16 = [" ++ Op.xmm_sz_m(64) ++ "]   py=[VMOVUPSm]"
   "iszbits float 16 = [" ++ U32.show(64) ++ "]   py=[64]"
   "isz int8 1 = [" ++ Op.xmm_sz(1) ++ "]   py=[VMOVSS]"
   "iszm int8 1 = [" ++ Op.xmm_sz_m(1) ++ "]   py=[VMOVSSm]"
   "iszbits int8 1 = [" ++ U32.show(1) ++ "]   py=[1]"
   "isz int8 2 = [" ++ Op.xmm_sz(2) ++ "]   py=[VMOVSS]"
   "iszm int8 2 = [" ++ Op.xmm_sz_m(2) ++ "]   py=[VMOVSSm]"
   "iszbits int8 2 = [" ++ U32.show(2) ++ "]   py=[2]"
   "isz int8 3 = [" ++ Op.xmm_sz(3) ++ "]   py=[VMOVSS]"
   "iszm int8 3 = [" ++ Op.xmm_sz_m(3) ++ "]   py=[VMOVSSm]"
   "iszbits int8 3 = [" ++ U32.show(3) ++ "]   py=[3]"
   "isz int8 4 = [" ++ Op.xmm_sz(4) ++ "]   py=[VMOVSS]"
   "iszm int8 4 = [" ++ Op.xmm_sz_m(4) ++ "]   py=[VMOVSSm]"
   "iszbits int8 4 = [" ++ U32.show(4) ++ "]   py=[4]"
   "isz int8 6 = [" ++ Op.xmm_sz(6) ++ "]   py=[VMOVSS]"
   "iszm int8 6 = [" ++ Op.xmm_sz_m(6) ++ "]   py=[VMOVSSm]"
   "iszbits int8 6 = [" ++ U32.show(6) ++ "]   py=[6]"
   "isz int8 8 = [" ++ Op.xmm_sz(8) ++ "]   py=[VMOVSD]"
   "iszm int8 8 = [" ++ Op.xmm_sz_m(8) ++ "]   py=[VMOVSDm]"
   "iszbits int8 8 = [" ++ U32.show(8) ++ "]   py=[8]"
   "isz int8 16 = [" ++ Op.xmm_sz(16) ++ "]   py=[VMOVUPS]"
   "iszm int8 16 = [" ++ Op.xmm_sz_m(16) ++ "]   py=[VMOVUPSm]"
   "iszbits int8 16 = [" ++ U32.show(16) ++ "]   py=[16]"
   "isz double 1 = [" ++ Op.xmm_sz(8) ++ "]   py=[VMOVSD]"
   "iszm double 1 = [" ++ Op.xmm_sz_m(8) ++ "]   py=[VMOVSDm]"
   "iszbits double 1 = [" ++ U32.show(8) ++ "]   py=[8]"
   "isz double 2 = [" ++ Op.xmm_sz(16) ++ "]   py=[VMOVUPS]"
 ]

def Gate.rows4() -> List<&2, String>: [
   "iszm double 2 = [" ++ Op.xmm_sz_m(16) ++ "]   py=[VMOVUPSm]"
   "iszbits double 2 = [" ++ U32.show(16) ++ "]   py=[16]"
   "isz double 3 = [" ++ Op.xmm_sz(24) ++ "]   py=[VMOVUPS]"
   "iszm double 3 = [" ++ Op.xmm_sz_m(24) ++ "]   py=[VMOVUPSm]"
   "iszbits double 3 = [" ++ U32.show(24) ++ "]   py=[24]"
   "isz double 4 = [" ++ Op.xmm_sz(32) ++ "]   py=[VMOVUPS]"
   "iszm double 4 = [" ++ Op.xmm_sz_m(32) ++ "]   py=[VMOVUPSm]"
   "iszbits double 4 = [" ++ U32.show(32) ++ "]   py=[32]"
   "isz double 6 = [" ++ Op.xmm_sz(48) ++ "]   py=[VMOVUPS]"
   "iszm double 6 = [" ++ Op.xmm_sz_m(48) ++ "]   py=[VMOVUPSm]"
   "iszbits double 6 = [" ++ U32.show(48) ++ "]   py=[48]"
   "isz double 8 = [" ++ Op.xmm_sz(64) ++ "]   py=[VMOVUPS]"
   "iszm double 8 = [" ++ Op.xmm_sz_m(64) ++ "]   py=[VMOVUPSm]"
   "iszbits double 8 = [" ++ U32.show(64) ++ "]   py=[64]"
   "isz double 16 = [" ++ Op.xmm_sz(128) ++ "]   py=[VMOVUPS]"
   "iszm double 16 = [" ++ Op.xmm_sz_m(128) ++ "]   py=[VMOVUPSm]"
   "iszbits double 16 = [" ++ U32.show(128) ++ "]   py=[128]"
   "isz half 1 = [" ++ Op.xmm_sz(2) ++ "]   py=[VMOVSS]"
   "iszm half 1 = [" ++ Op.xmm_sz_m(2) ++ "]   py=[VMOVSSm]"
   "iszbits half 1 = [" ++ U32.show(2) ++ "]   py=[2]"
   "isz half 2 = [" ++ Op.xmm_sz(4) ++ "]   py=[VMOVSS]"
   "iszm half 2 = [" ++ Op.xmm_sz_m(4) ++ "]   py=[VMOVSSm]"
   "iszbits half 2 = [" ++ U32.show(4) ++ "]   py=[4]"
   "isz half 3 = [" ++ Op.xmm_sz(6) ++ "]   py=[VMOVSS]"
   "iszm half 3 = [" ++ Op.xmm_sz_m(6) ++ "]   py=[VMOVSSm]"
   "iszbits half 3 = [" ++ U32.show(6) ++ "]   py=[6]"
   "isz half 4 = [" ++ Op.xmm_sz(8) ++ "]   py=[VMOVSD]"
   "iszm half 4 = [" ++ Op.xmm_sz_m(8) ++ "]   py=[VMOVSDm]"
   "iszbits half 4 = [" ++ U32.show(8) ++ "]   py=[8]"
   "isz half 6 = [" ++ Op.xmm_sz(12) ++ "]   py=[VMOVSD]"
   "iszm half 6 = [" ++ Op.xmm_sz_m(12) ++ "]   py=[VMOVSDm]"
   "iszbits half 6 = [" ++ U32.show(12) ++ "]   py=[12]"
   "isz half 8 = [" ++ Op.xmm_sz(16) ++ "]   py=[VMOVUPS]"
   "iszm half 8 = [" ++ Op.xmm_sz_m(16) ++ "]   py=[VMOVUPSm]"
   "iszbits half 8 = [" ++ U32.show(16) ++ "]   py=[16]"
   "isz half 16 = [" ++ Op.xmm_sz(32) ++ "]   py=[VMOVUPS]"
   "iszm half 16 = [" ++ Op.xmm_sz_m(32) ++ "]   py=[VMOVUPSm]"
   "iszbits half 16 = [" ++ U32.show(32) ++ "]   py=[32]"
   "iszthr 0 = [" ++ Op.xmm_sz(0) ++ "]   py=[VMOVSS]"
   "iszthrm 0 = [" ++ Op.xmm_sz_m(0) ++ "]   py=[VMOVSSm]"
   "iszthr 1 = [" ++ Op.xmm_sz(1) ++ "]   py=[VMOVSS]"
   "iszthrm 1 = [" ++ Op.xmm_sz_m(1) ++ "]   py=[VMOVSSm]"
   "iszthr 7 = [" ++ Op.xmm_sz(7) ++ "]   py=[VMOVSS]"
   "iszthrm 7 = [" ++ Op.xmm_sz_m(7) ++ "]   py=[VMOVSSm]"
   "iszthr 8 = [" ++ Op.xmm_sz(8) ++ "]   py=[VMOVSD]"
   "iszthrm 8 = [" ++ Op.xmm_sz_m(8) ++ "]   py=[VMOVSDm]"
   "iszthr 15 = [" ++ Op.xmm_sz(15) ++ "]   py=[VMOVSD]"
   "iszthrm 15 = [" ++ Op.xmm_sz_m(15) ++ "]   py=[VMOVSDm]"
   "iszthr 16 = [" ++ Op.xmm_sz(16) ++ "]   py=[VMOVUPS]"
   "iszthrm 16 = [" ++ Op.xmm_sz_m(16) ++ "]   py=[VMOVUPSm]"
   "iszthr 17 = [" ++ Op.xmm_sz(17) ++ "]   py=[VMOVUPS]"
   "iszthrm 17 = [" ++ Op.xmm_sz_m(17) ++ "]   py=[VMOVUPSm]"
   "iszthr 32 = [" ++ Op.xmm_sz(32) ++ "]   py=[VMOVUPS]"
   "iszthrm 32 = [" ++ Op.xmm_sz_m(32) ++ "]   py=[VMOVUPSm]"
   "toint void = [" ++ Op.to_int(S.void()) ++ "]   py=[KeyError]"
   "toint bool = [" ++ Op.to_int(S.boolean()) ++ "]   py=[KeyError]"
   "toint weakint = [" ++ Op.to_int(S.weakint()) ++ "]   py=[KeyError]"
   "toint i8 = [" ++ Op.to_int(S.int8()) ++ "]   py=[KeyError]"
   "toint u8 = [" ++ Op.to_int(S.uint8()) ++ "]   py=[KeyError]"
   "toint i16 = [" ++ Op.to_int(S.int16()) ++ "]   py=[KeyError]"
   "toint u16 = [" ++ Op.to_int(S.uint16()) ++ "]   py=[KeyError]"
   "toint i32 = [" ++ Op.to_int(S.int32()) ++ "]   py=[KeyError]"
   "toint u32 = [" ++ Op.to_int(S.uint32()) ++ "]   py=[KeyError]"
   "toint i64 = [" ++ Op.to_int(S.int64()) ++ "]   py=[KeyError]"
   "toint u64 = [" ++ Op.to_int(S.uint64()) ++ "]   py=[KeyError]"
   "toint weakfloat = [" ++ Op.to_int(S.weakfloat()) ++ "]   py=[KeyError]"
   "toint fp8e4m3 = [" ++ Op.to_int(S.fp8e4m3fnuz()) ++ "]   py=[KeyError]"
   "toint fp8e5m2 = [" ++ Op.to_int(S.fp8e5m2fnuz()) ++ "]   py=[KeyError]"
   "toint fp8e4m3fnuz = [" ++ Op.to_int(S.fp8e4m3fnuz()) ++ "]   py=[KeyError]"
   "toint fp8e5m2fnuz = [" ++ Op.to_int(S.fp8e5m2fnuz()) ++ "]   py=[KeyError]"
   "toint f16 = [" ++ Op.to_int(S.half()) ++ "]   py=[i16]"
   "toint bf16 = [" ++ Op.to_int(S.bfloat16()) ++ "]   py=[KeyError]"
   "toint f32 = [" ++ Op.to_int(S.single()) ++ "]   py=[i32]"
   "toint f64 = [" ++ Op.to_int(S.double()) ++ "]   py=[i64]"
   "2a.FRAME_INDEX = [" ++ Bool.show(Op.is_two_address("FRAME_INDEX")) ++ "]   py=[False]"
   "2a.LABEL = [" ++ Bool.show(Op.is_two_address("LABEL")) ++ "]   py=[False]"
   "2a.DEFINE = [" ++ Bool.show(Op.is_two_address("DEFINE")) ++ "]   py=[False]"
   "2a.LOOP_CMP = [" ++ Bool.show(Op.is_two_address("LOOP_CMP")) ++ "]   py=[False]"
   "2a.LEA = [" ++ Bool.show(Op.is_two_address("LEA")) ++ "]   py=[False]"
   "2a.MOV = [" ++ Bool.show(Op.is_two_address("MOV")) ++ "]   py=[False]"
   "2a.MOVm = [" ++ Bool.show(Op.is_two_address("MOVm")) ++ "]   py=[False]"
   "2a.MOVi = [" ++ Bool.show(Op.is_two_address("MOVi")) ++ "]   py=[False]"
   "2a.MOVABS = [" ++ Bool.show(Op.is_two_address("MOVABS")) ++ "]   py=[False]"
   "2a.VMOVSS = [" ++ Bool.show(Op.is_two_address("VMOVSS")) ++ "]   py=[False]"
   "2a.VMOVSD = [" ++ Bool.show(Op.is_two_address("VMOVSD")) ++ "]   py=[False]"
   "2a.VMOVUPS = [" ++ Bool.show(Op.is_two_address("VMOVUPS")) ++ "]   py=[False]"
   "2a.VMOVSSm = [" ++ Bool.show(Op.is_two_address("VMOVSSm")) ++ "]   py=[False]"
   "2a.VMOVSDm = [" ++ Bool.show(Op.is_two_address("VMOVSDm")) ++ "]   py=[False]"
   "2a.VMOVUPSm = [" ++ Bool.show(Op.is_two_address("VMOVUPSm")) ++ "]   py=[False]"
   "2a.MOVZX = [" ++ Bool.show(Op.is_two_address("MOVZX")) ++ "]   py=[False]"
   "2a.MOVSX = [" ++ Bool.show(Op.is_two_address("MOVSX")) ++ "]   py=[False]"
   "2a.MOVSXD = [" ++ Bool.show(Op.is_two_address("MOVSXD")) ++ "]   py=[False]"
   "2a.VCVTPH2PS = [" ++ Bool.show(Op.is_two_address("VCVTPH2PS")) ++ "]   py=[False]"
   "2a.VCVTPS2PH = [" ++ Bool.show(Op.is_two_address("VCVTPS2PH")) ++ "]   py=[False]"
   "2a.VCVTSS2SD = [" ++ Bool.show(Op.is_two_address("VCVTSS2SD")) ++ "]   py=[False]"
 ]

def Gate.rows5() -> List<&2, String>: [
   "2a.VCVTSD2SS = [" ++ Bool.show(Op.is_two_address("VCVTSD2SS")) ++ "]   py=[False]"
   "2a.VCVTSI2SS = [" ++ Bool.show(Op.is_two_address("VCVTSI2SS")) ++ "]   py=[False]"
   "2a.VCVTSI2SD = [" ++ Bool.show(Op.is_two_address("VCVTSI2SD")) ++ "]   py=[False]"
   "2a.VCVTTSS2SI = [" ++ Bool.show(Op.is_two_address("VCVTTSS2SI")) ++ "]   py=[False]"
   "2a.VCVTTSD2SI = [" ++ Bool.show(Op.is_two_address("VCVTTSD2SI")) ++ "]   py=[False]"
   "2a.VMOVD = [" ++ Bool.show(Op.is_two_address("VMOVD")) ++ "]   py=[False]"
   "2a.VMOVQ = [" ++ Bool.show(Op.is_two_address("VMOVQ")) ++ "]   py=[False]"
   "2a.VMOVDm = [" ++ Bool.show(Op.is_two_address("VMOVDm")) ++ "]   py=[False]"
   "2a.VMOVQm = [" ++ Bool.show(Op.is_two_address("VMOVQm")) ++ "]   py=[False]"
   "2a.VCMPSS = [" ++ Bool.show(Op.is_two_address("VCMPSS")) ++ "]   py=[False]"
   "2a.VCMPSD = [" ++ Bool.show(Op.is_two_address("VCMPSD")) ++ "]   py=[False]"
   "2a.SETNE = [" ++ Bool.show(Op.is_two_address("SETNE")) ++ "]   py=[False]"
   "2a.SETE = [" ++ Bool.show(Op.is_two_address("SETE")) ++ "]   py=[False]"
   "2a.SETL = [" ++ Bool.show(Op.is_two_address("SETL")) ++ "]   py=[False]"
   "2a.SETB = [" ++ Bool.show(Op.is_two_address("SETB")) ++ "]   py=[False]"
   "2a.CMOVNE = [" ++ Bool.show(Op.is_two_address("CMOVNE")) ++ "]   py=[True]"
   "2a.CMOVE = [" ++ Bool.show(Op.is_two_address("CMOVE")) ++ "]   py=[True]"
   "2a.CMOVL = [" ++ Bool.show(Op.is_two_address("CMOVL")) ++ "]   py=[True]"
   "2a.CMOVB = [" ++ Bool.show(Op.is_two_address("CMOVB")) ++ "]   py=[True]"
   "2a.VBLENDVPS = [" ++ Bool.show(Op.is_two_address("VBLENDVPS")) ++ "]   py=[False]"
   "2a.VBLENDVPD = [" ++ Bool.show(Op.is_two_address("VBLENDVPD")) ++ "]   py=[False]"
   "2a.JNE = [" ++ Bool.show(Op.is_two_address("JNE")) ++ "]   py=[False]"
   "2a.JE = [" ++ Bool.show(Op.is_two_address("JE")) ++ "]   py=[False]"
   "2a.JL = [" ++ Bool.show(Op.is_two_address("JL")) ++ "]   py=[False]"
   "2a.JB = [" ++ Bool.show(Op.is_two_address("JB")) ++ "]   py=[False]"
   "2a.JGE = [" ++ Bool.show(Op.is_two_address("JGE")) ++ "]   py=[False]"
   "2a.JMP = [" ++ Bool.show(Op.is_two_address("JMP")) ++ "]   py=[False]"
   "2a.VINSERTPS = [" ++ Bool.show(Op.is_two_address("VINSERTPS")) ++ "]   py=[False]"
   "2a.VPSRLDQ = [" ++ Bool.show(Op.is_two_address("VPSRLDQ")) ++ "]   py=[False]"
   "2a.VPEXTRW = [" ++ Bool.show(Op.is_two_address("VPEXTRW")) ++ "]   py=[False]"
   "2a.VPEXTRD = [" ++ Bool.show(Op.is_two_address("VPEXTRD")) ++ "]   py=[False]"
   "2a.VPINSRW = [" ++ Bool.show(Op.is_two_address("VPINSRW")) ++ "]   py=[False]"
   "2a.VPINSRD = [" ++ Bool.show(Op.is_two_address("VPINSRD")) ++ "]   py=[False]"
   "2a.IDIV = [" ++ Bool.show(Op.is_two_address("IDIV")) ++ "]   py=[True]"
   "2a.DIV = [" ++ Bool.show(Op.is_two_address("DIV")) ++ "]   py=[True]"
   "2a.ADD = [" ++ Bool.show(Op.is_two_address("ADD")) ++ "]   py=[True]"
   "2a.ADDi = [" ++ Bool.show(Op.is_two_address("ADDi")) ++ "]   py=[True]"
   "2a.SUB = [" ++ Bool.show(Op.is_two_address("SUB")) ++ "]   py=[True]"
   "2a.SUBi = [" ++ Bool.show(Op.is_two_address("SUBi")) ++ "]   py=[True]"
   "2a.IMUL = [" ++ Bool.show(Op.is_two_address("IMUL")) ++ "]   py=[True]"
   "2a.IMULi = [" ++ Bool.show(Op.is_two_address("IMULi")) ++ "]   py=[False]"
   "2a.AND = [" ++ Bool.show(Op.is_two_address("AND")) ++ "]   py=[True]"
   "2a.ANDi = [" ++ Bool.show(Op.is_two_address("ANDi")) ++ "]   py=[True]"
   "2a.XOR = [" ++ Bool.show(Op.is_two_address("XOR")) ++ "]   py=[True]"
   "2a.XORi = [" ++ Bool.show(Op.is_two_address("XORi")) ++ "]   py=[True]"
   "2a.OR = [" ++ Bool.show(Op.is_two_address("OR")) ++ "]   py=[True]"
   "2a.ORi = [" ++ Bool.show(Op.is_two_address("ORi")) ++ "]   py=[True]"
   "2a.SHL = [" ++ Bool.show(Op.is_two_address("SHL")) ++ "]   py=[True]"
   "2a.SHLi = [" ++ Bool.show(Op.is_two_address("SHLi")) ++ "]   py=[True]"
   "2a.SHR = [" ++ Bool.show(Op.is_two_address("SHR")) ++ "]   py=[True]"
   "2a.SHRi = [" ++ Bool.show(Op.is_two_address("SHRi")) ++ "]   py=[True]"
   "2a.SAR = [" ++ Bool.show(Op.is_two_address("SAR")) ++ "]   py=[True]"
   "2a.SARi = [" ++ Bool.show(Op.is_two_address("SARi")) ++ "]   py=[True]"
   "2a.CMP = [" ++ Bool.show(Op.is_two_address("CMP")) ++ "]   py=[False]"
   "2a.CMPi = [" ++ Bool.show(Op.is_two_address("CMPi")) ++ "]   py=[False]"
   "2a.VROUNDSS = [" ++ Bool.show(Op.is_two_address("VROUNDSS")) ++ "]   py=[False]"
   "2a.VROUNDSD = [" ++ Bool.show(Op.is_two_address("VROUNDSD")) ++ "]   py=[False]"
   "2a.VSQRTSS = [" ++ Bool.show(Op.is_two_address("VSQRTSS")) ++ "]   py=[False]"
   "2a.VSQRTSD = [" ++ Bool.show(Op.is_two_address("VSQRTSD")) ++ "]   py=[False]"
   "2a.VADDSS = [" ++ Bool.show(Op.is_two_address("VADDSS")) ++ "]   py=[False]"
   "2a.VADDSD = [" ++ Bool.show(Op.is_two_address("VADDSD")) ++ "]   py=[False]"
   "2a.VSUBSS = [" ++ Bool.show(Op.is_two_address("VSUBSS")) ++ "]   py=[False]"
   "2a.VSUBSD = [" ++ Bool.show(Op.is_two_address("VSUBSD")) ++ "]   py=[False]"
   "2a.VMULSS = [" ++ Bool.show(Op.is_two_address("VMULSS")) ++ "]   py=[False]"
   "2a.VMULSD = [" ++ Bool.show(Op.is_two_address("VMULSD")) ++ "]   py=[False]"
   "2a.VDIVSS = [" ++ Bool.show(Op.is_two_address("VDIVSS")) ++ "]   py=[False]"
   "2a.VDIVSD = [" ++ Bool.show(Op.is_two_address("VDIVSD")) ++ "]   py=[False]"
   "2a.RET = [" ++ Bool.show(Op.is_two_address("RET")) ++ "]   py=[False]"
   "enc.ADD = [" ++ EncRow("ADD") ++ "]   py=[opc=3,reg=-,pp=-,sel=-,we=-]"
   "enc.ADDi = [" ++ EncRow("ADDi") ++ "]   py=[opc=129,reg=0,pp=-,sel=-,we=-]"
   "enc.AND = [" ++ EncRow("AND") ++ "]   py=[opc=35,reg=-,pp=-,sel=-,we=-]"
   "enc.ANDi = [" ++ EncRow("ANDi") ++ "]   py=[opc=129,reg=4,pp=-,sel=-,we=-]"
   "enc.CMOVB = [" ++ EncRow("CMOVB") ++ "]   py=[opc=3906,reg=-,pp=-,sel=-,we=-]"
   "enc.CMOVE = [" ++ EncRow("CMOVE") ++ "]   py=[opc=3908,reg=-,pp=-,sel=-,we=-]"
   "enc.CMOVL = [" ++ EncRow("CMOVL") ++ "]   py=[opc=3916,reg=-,pp=-,sel=-,we=-]"
   "enc.CMOVNE = [" ++ EncRow("CMOVNE") ++ "]   py=[opc=3909,reg=-,pp=-,sel=-,we=-]"
   "enc.CMP = [" ++ EncRow("CMP") ++ "]   py=[opc=59,reg=-,pp=-,sel=-,we=-]"
   "enc.CMPi = [" ++ EncRow("CMPi") ++ "]   py=[opc=129,reg=7,pp=-,sel=-,we=-]"
   "enc.DIV = [" ++ EncRow("DIV") ++ "]   py=[opc=247,reg=6,pp=-,sel=-,we=-]"
 ]

def Gate.rows6() -> List<&2, String>: [
   "enc.IDIV = [" ++ EncRow("IDIV") ++ "]   py=[opc=247,reg=7,pp=-,sel=-,we=-]"
   "enc.IMUL = [" ++ EncRow("IMUL") ++ "]   py=[opc=4015,reg=-,pp=-,sel=-,we=-]"
   "enc.IMULi = [" ++ EncRow("IMULi") ++ "]   py=[opc=105,reg=-,pp=-,sel=-,we=-]"
   "enc.LEA = [" ++ EncRow("LEA") ++ "]   py=[opc=141,reg=-,pp=-,sel=-,we=-]"
   "enc.MOV = [" ++ EncRow("MOV") ++ "]   py=[opc=139,reg=-,pp=-,sel=-,we=-]"
   "enc.MOVSX = [" ++ EncRow("MOVSX") ++ "]   py=[opc=4031,reg=-,pp=-,sel=-,we=-]"
   "enc.MOVSXD = [" ++ EncRow("MOVSXD") ++ "]   py=[opc=99,reg=-,pp=-,sel=-,we=-]"
   "enc.MOVZX = [" ++ EncRow("MOVZX") ++ "]   py=[opc=4023,reg=-,pp=-,sel=-,we=-]"
   "enc.MOVi = [" ++ EncRow("MOVi") ++ "]   py=[opc=199,reg=0,pp=-,sel=-,we=-]"
   "enc.MOVm = [" ++ EncRow("MOVm") ++ "]   py=[opc=137,reg=-,pp=-,sel=-,we=-]"
   "enc.OR = [" ++ EncRow("OR") ++ "]   py=[opc=11,reg=-,pp=-,sel=-,we=-]"
   "enc.ORi = [" ++ EncRow("ORi") ++ "]   py=[opc=129,reg=1,pp=-,sel=-,we=-]"
   "enc.SAR = [" ++ EncRow("SAR") ++ "]   py=[opc=211,reg=7,pp=-,sel=-,we=-]"
   "enc.SARi = [" ++ EncRow("SARi") ++ "]   py=[opc=193,reg=7,pp=-,sel=-,we=-]"
   "enc.SETB = [" ++ EncRow("SETB") ++ "]   py=[opc=3986,reg=0,pp=-,sel=-,we=-]"
   "enc.SETE = [" ++ EncRow("SETE") ++ "]   py=[opc=3988,reg=0,pp=-,sel=-,we=-]"
   "enc.SETL = [" ++ EncRow("SETL") ++ "]   py=[opc=3996,reg=0,pp=-,sel=-,we=-]"
   "enc.SETNE = [" ++ EncRow("SETNE") ++ "]   py=[opc=3989,reg=0,pp=-,sel=-,we=-]"
   "enc.SHL = [" ++ EncRow("SHL") ++ "]   py=[opc=211,reg=4,pp=-,sel=-,we=-]"
   "enc.SHLi = [" ++ EncRow("SHLi") ++ "]   py=[opc=193,reg=4,pp=-,sel=-,we=-]"
   "enc.SHR = [" ++ EncRow("SHR") ++ "]   py=[opc=211,reg=5,pp=-,sel=-,we=-]"
   "enc.SHRi = [" ++ EncRow("SHRi") ++ "]   py=[opc=193,reg=5,pp=-,sel=-,we=-]"
   "enc.SUB = [" ++ EncRow("SUB") ++ "]   py=[opc=43,reg=-,pp=-,sel=-,we=-]"
   "enc.SUBi = [" ++ EncRow("SUBi") ++ "]   py=[opc=129,reg=5,pp=-,sel=-,we=-]"
   "enc.VADDSD = [" ++ EncRow("VADDSD") ++ "]   py=[opc=88,reg=-,pp=3,sel=1,we=-]"
   "enc.VADDSS = [" ++ EncRow("VADDSS") ++ "]   py=[opc=88,reg=-,pp=2,sel=1,we=-]"
   "enc.VBLENDVPD = [" ++ EncRow("VBLENDVPD") ++ "]   py=[opc=75,reg=-,pp=1,sel=3,we=-]"
   "enc.VBLENDVPS = [" ++ EncRow("VBLENDVPS") ++ "]   py=[opc=74,reg=-,pp=1,sel=3,we=-]"
   "enc.VCMPSD = [" ++ EncRow("VCMPSD") ++ "]   py=[opc=194,reg=-,pp=3,sel=1,we=-]"
   "enc.VCMPSS = [" ++ EncRow("VCMPSS") ++ "]   py=[opc=194,reg=-,pp=2,sel=1,we=-]"
   "enc.VCVTPH2PS = [" ++ EncRow("VCVTPH2PS") ++ "]   py=[opc=19,reg=-,pp=1,sel=2,we=-]"
   "enc.VCVTPS2PH = [" ++ EncRow("VCVTPS2PH") ++ "]   py=[opc=29,reg=-,pp=1,sel=3,we=-]"
   "enc.VCVTSD2SS = [" ++ EncRow("VCVTSD2SS") ++ "]   py=[opc=90,reg=-,pp=3,sel=1,we=-]"
   "enc.VCVTSI2SD = [" ++ EncRow("VCVTSI2SD") ++ "]   py=[opc=42,reg=-,pp=3,sel=1,we=x.src[1].dtype.itemsize == 8]"
   "enc.VCVTSI2SS = [" ++ EncRow("VCVTSI2SS") ++ "]   py=[opc=42,reg=-,pp=2,sel=1,we=x.src[1].dtype.itemsize == 8]"
   "enc.VCVTSS2SD = [" ++ EncRow("VCVTSS2SD") ++ "]   py=[opc=90,reg=-,pp=2,sel=1,we=-]"
   "enc.VCVTTSD2SI = [" ++ EncRow("VCVTTSD2SI") ++ "]   py=[opc=44,reg=-,pp=3,sel=1,we=x.dtype.itemsize == 8]"
   "enc.VCVTTSS2SI = [" ++ EncRow("VCVTTSS2SI") ++ "]   py=[opc=44,reg=-,pp=2,sel=1,we=x.dtype.itemsize == 8]"
   "enc.VDIVSD = [" ++ EncRow("VDIVSD") ++ "]   py=[opc=94,reg=-,pp=3,sel=1,we=-]"
   "enc.VDIVSS = [" ++ EncRow("VDIVSS") ++ "]   py=[opc=94,reg=-,pp=2,sel=1,we=-]"
   "enc.VINSERTPS = [" ++ EncRow("VINSERTPS") ++ "]   py=[opc=33,reg=-,pp=1,sel=3,we=-]"
   "enc.VMOVD = [" ++ EncRow("VMOVD") ++ "]   py=[opc=110,reg=-,pp=1,sel=1,we=-]"
   "enc.VMOVDm = [" ++ EncRow("VMOVDm") ++ "]   py=[opc=126,reg=-,pp=1,sel=1,we=-]"
   "enc.VMOVQ = [" ++ EncRow("VMOVQ") ++ "]   py=[opc=110,reg=-,pp=1,sel=1,we=1]"
   "enc.VMOVQm = [" ++ EncRow("VMOVQm") ++ "]   py=[opc=126,reg=-,pp=1,sel=1,we=1]"
   "enc.VMOVSD = [" ++ EncRow("VMOVSD") ++ "]   py=[opc=16,reg=-,pp=3,sel=1,we=-]"
   "enc.VMOVSDm = [" ++ EncRow("VMOVSDm") ++ "]   py=[opc=17,reg=-,pp=3,sel=1,we=-]"
   "enc.VMOVSS = [" ++ EncRow("VMOVSS") ++ "]   py=[opc=16,reg=-,pp=2,sel=1,we=-]"
   "enc.VMOVSSm = [" ++ EncRow("VMOVSSm") ++ "]   py=[opc=17,reg=-,pp=2,sel=1,we=-]"
   "enc.VMOVUPS = [" ++ EncRow("VMOVUPS") ++ "]   py=[opc=16,reg=-,pp=0,sel=1,we=-]"
   "enc.VMOVUPSm = [" ++ EncRow("VMOVUPSm") ++ "]   py=[opc=17,reg=-,pp=0,sel=1,we=-]"
   "enc.VMULSD = [" ++ EncRow("VMULSD") ++ "]   py=[opc=89,reg=-,pp=3,sel=1,we=-]"
   "enc.VMULSS = [" ++ EncRow("VMULSS") ++ "]   py=[opc=89,reg=-,pp=2,sel=1,we=-]"
   "enc.VPEXTRD = [" ++ EncRow("VPEXTRD") ++ "]   py=[opc=22,reg=-,pp=1,sel=3,we=-]"
   "enc.VPEXTRW = [" ++ EncRow("VPEXTRW") ++ "]   py=[opc=21,reg=-,pp=1,sel=3,we=-]"
   "enc.VPINSRD = [" ++ EncRow("VPINSRD") ++ "]   py=[opc=34,reg=-,pp=1,sel=3,we=-]"
   "enc.VPINSRW = [" ++ EncRow("VPINSRW") ++ "]   py=[opc=196,reg=-,pp=1,sel=1,we=-]"
   "enc.VPSRLDQ = [" ++ EncRow("VPSRLDQ") ++ "]   py=[opc=115,reg=3,pp=1,sel=1,we=-]"
   "enc.VROUNDSD = [" ++ EncRow("VROUNDSD") ++ "]   py=[opc=11,reg=-,pp=1,sel=3,we=-]"
   "enc.VROUNDSS = [" ++ EncRow("VROUNDSS") ++ "]   py=[opc=10,reg=-,pp=1,sel=3,we=-]"
   "enc.VSQRTSD = [" ++ EncRow("VSQRTSD") ++ "]   py=[opc=81,reg=-,pp=3,sel=1,we=-]"
   "enc.VSQRTSS = [" ++ EncRow("VSQRTSS") ++ "]   py=[opc=81,reg=-,pp=2,sel=1,we=-]"
   "enc.VSUBSD = [" ++ EncRow("VSUBSD") ++ "]   py=[opc=92,reg=-,pp=3,sel=1,we=-]"
   "enc.VSUBSS = [" ++ EncRow("VSUBSS") ++ "]   py=[opc=92,reg=-,pp=2,sel=1,we=-]"
   "enc.XOR = [" ++ EncRow("XOR") ++ "]   py=[opc=51,reg=-,pp=-,sel=-,we=-]"
   "enc.XORi = [" ++ EncRow("XORi") ++ "]   py=[opc=129,reg=6,pp=-,sel=-,we=-]"
   "enc.count = [" ++ U32.show(enc_count()) ++ "]   py=[85]"
   "enc.paramcount = [" ++ U32.show(enc_paramcount()) ++ "]   py=[77]"
   "enc.missing = [" ++ enc_missing_names() ++ "]   py=[FRAME_INDEX,LABEL,DEFINE,LOOP_CMP]"
   "enc.none FRAME_INDEX = [" ++ Bool.show(Enc.is_direct("FRAME_INDEX")) ++ "]   py=[False]"
   "enc.norow FRAME_INDEX = [" ++ EncRow("FRAME_INDEX") ++ "]   py=[none]"
   "enc.none LABEL = [" ++ Bool.show(Enc.is_direct("LABEL")) ++ "]   py=[False]"
   "enc.norow LABEL = [" ++ EncRow("LABEL") ++ "]   py=[none]"
   "enc.none DEFINE = [" ++ Bool.show(Enc.is_direct("DEFINE")) ++ "]   py=[False]"
   "enc.norow DEFINE = [" ++ EncRow("DEFINE") ++ "]   py=[none]"
 ]

def Gate.rows7() -> List<&2, String>: [
   "enc.none LOOP_CMP = [" ++ Bool.show(Enc.is_direct("LOOP_CMP")) ++ "]   py=[False]"
   "enc.norow LOOP_CMP = [" ++ EncRow("LOOP_CMP") ++ "]   py=[none]"
   "direct.JE.0f8400000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.direct("JE")), "0f8400000000")) ++ "]   py=[True]"
   "direct.JNE.0f8500000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.direct("JNE")), "0f8500000000")) ++ "]   py=[True]"
   "direct.JL.0f8c00000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.direct("JL")), "0f8c00000000")) ++ "]   py=[True]"
   "direct.JB.0f8200000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.direct("JB")), "0f8200000000")) ++ "]   py=[True]"
   "direct.JGE.0f8d00000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.direct("JGE")), "0f8d00000000")) ++ "]   py=[True]"
   "direct.JMP.e900000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.direct("JMP")), "e900000000")) ++ "]   py=[True]"
   "direct.RET.c3 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.direct("RET")), "c3")) ++ "]   py=[True]"
   "direct.MOVABS 0.48b83412000000000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.movabs(0, 4660)), "48b83412000000000000")) ++ "]   py=[True]"
   "direct.MOVABS 1.48b93412000000000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.movabs(1, 4660)), "48b93412000000000000")) ++ "]   py=[True]"
   "direct.MOVABS 7.48bf3412000000000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.movabs(7, 4660)), "48bf3412000000000000")) ++ "]   py=[True]"
   "direct.MOVABS 8.49b83412000000000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.movabs(8, 4660)), "49b83412000000000000")) ++ "]   py=[True]"
   "direct.MOVABS 15.49bf3412000000000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.movabs(15, 4660)), "49bf3412000000000000")) ++ "]   py=[True]"
   "hex.LEA.488d948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("LEA", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, True{}, 4, 0)), "488d948c08000000")) ++ "]   py=[True]"
   "hex.MOV.488b948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("MOV", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 4, 0)), "488b948c08000000")) ++ "]   py=[True]"
   "hex.MOVm.4889948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("MOVm", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 0, 0)), "4889948c08000000")) ++ "]   py=[True]"
   "hex.MOVi.40c7848c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("MOVi", 0, 4, 1, 4, 0, 0, True{}, 8, 4, 0, 0n, 0, False{}, 0, 0)), "40c7848c08000000")) ++ "]   py=[True]"
   "hex.VMOVSS.c5fa10948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VMOVSS", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 4, 0)), "c5fa10948c08000000")) ++ "]   py=[True]"
   "hex.VMOVSD.c5fb10948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VMOVSD", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 8, 0)), "c5fb10948c08000000")) ++ "]   py=[True]"
   "hex.VMOVUPS.c5f810948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VMOVUPS", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 4, 0)), "c5f810948c08000000")) ++ "]   py=[True]"
   "hex.VMOVSSm.c5fa11948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VMOVSSm", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 0, 0)), "c5fa11948c08000000")) ++ "]   py=[True]"
   "hex.VMOVSDm.c5fb11948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VMOVSDm", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 0, 0)), "c5fb11948c08000000")) ++ "]   py=[True]"
   "hex.VMOVUPSm.c5f811948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VMOVUPSm", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 0, 0)), "c5f811948c08000000")) ++ "]   py=[True]"
   "hex.MOVZX.480fb7948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("MOVZX", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 4, 0)), "480fb7948c08000000")) ++ "]   py=[True]"
   "hex.MOVSX.480fbf948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("MOVSX", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 4, 0)), "480fbf948c08000000")) ++ "]   py=[True]"
   "hex.MOVSXD.4863948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("MOVSXD", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 4, 0)), "4863948c08000000")) ++ "]   py=[True]"
   "hex.VCVTPH2PS.c4e27913948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VCVTPH2PS", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 4, 0)), "c4e27913948c08000000")) ++ "]   py=[True]"
   "hex.VCVTSS2SD.c5f25ac2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VCVTSS2SD", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 8, 0)), "c5f25ac2")) ++ "]   py=[True]"
   "hex.VCVTSD2SS.c5f35ac2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VCVTSD2SS", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "c5f35ac2")) ++ "]   py=[True]"
   "hex.VCVTSI2SS.c5f22ac2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VCVTSI2SS", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "c5f22ac2")) ++ "]   py=[True]"
   "hex.VCVTSI2SD.c5f32ac2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VCVTSI2SD", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 8, 0)), "c5f32ac2")) ++ "]   py=[True]"
   "hex.VCVTTSS2SI.c5fa2c948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VCVTTSS2SI", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 4, 0)), "c5fa2c948c08000000")) ++ "]   py=[True]"
   "hex.VCVTTSD2SI.c5fb2c948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VCVTTSD2SI", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 4, 0)), "c5fb2c948c08000000")) ++ "]   py=[True]"
   "hex.VMOVD.c5f96e948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VMOVD", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 4, 0)), "c5f96e948c08000000")) ++ "]   py=[True]"
   "hex.VMOVQ.c4e1f96e948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VMOVQ", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 4, 0)), "c4e1f96e948c08000000")) ++ "]   py=[True]"
   "hex.VCMPSS.c5f2c2c2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VCMPSS", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "c5f2c2c2")) ++ "]   py=[True]"
 ]

def Gate.rows8() -> List<&2, String>: [
   "hex.VCMPSD.c5f3c2c2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VCMPSD", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 8, 0)), "c5f3c2c2")) ++ "]   py=[True]"
   "hex.SETNE.400f95848c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("SETNE", 0, 4, 1, 4, 0, 0, True{}, 8, 4, 0, 0n, 0, True{}, 1, 0)), "400f95848c08000000")) ++ "]   py=[True]"
   "hex.SETE.400f94848c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("SETE", 0, 4, 1, 4, 0, 0, True{}, 8, 4, 0, 0n, 0, True{}, 1, 0)), "400f94848c08000000")) ++ "]   py=[True]"
   "hex.SETL.400f9c848c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("SETL", 0, 4, 1, 4, 0, 0, True{}, 8, 4, 0, 0n, 0, True{}, 1, 0)), "400f9c848c08000000")) ++ "]   py=[True]"
   "hex.SETB.400f92848c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("SETB", 0, 4, 1, 4, 0, 0, True{}, 8, 4, 0, 0n, 0, True{}, 1, 0)), "400f92848c08000000")) ++ "]   py=[True]"
   "hex.CMOVNE.480f45d5 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("CMOVNE", 2, 5, 4, 8, 8, 0, False{}, 0, 4, 0, 0n, 0, True{}, 4, 0)), "480f45d5")) ++ "]   py=[True]"
   "hex.CMOVE.480f44d5 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("CMOVE", 2, 5, 4, 8, 8, 0, False{}, 0, 4, 0, 0n, 0, True{}, 4, 0)), "480f44d5")) ++ "]   py=[True]"
   "hex.CMOVL.480f4cd5 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("CMOVL", 2, 5, 4, 8, 8, 0, False{}, 0, 4, 0, 0n, 0, True{}, 4, 0)), "480f4cd5")) ++ "]   py=[True]"
   "hex.CMOVB.480f42d5 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("CMOVB", 2, 5, 4, 8, 8, 0, False{}, 0, 4, 0, 0n, 0, True{}, 4, 0)), "480f42d5")) ++ "]   py=[True]"
   "hex.VBLENDVPS.c4e3714ac2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VBLENDVPS", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "c4e3714ac2")) ++ "]   py=[True]"
   "hex.VBLENDVPD.c4e3714bc2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VBLENDVPD", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "c4e3714bc2")) ++ "]   py=[True]"
   "hex.VINSERTPS.c4e37121c2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VINSERTPS", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "c4e37121c2")) ++ "]   py=[True]"
   "hex.VPSRLDQ.c5e9739c8c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VPSRLDQ", 3, 4, 1, 4, 0, 2, True{}, 8, 4, 0, 0n, 0, False{}, 4, 0)), "c5e9739c8c08000000")) ++ "]   py=[True]"
   "hex.VPEXTRW.c4e37915948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VPEXTRW", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 1, 0)), "c4e37915948c08000000")) ++ "]   py=[True]"
   "hex.VPEXTRD.c4e37916948c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VPEXTRD", 2, 4, 1, 4, 8, 0, True{}, 8, 4, 0, 0n, 0, False{}, 1, 0)), "c4e37916948c08000000")) ++ "]   py=[True]"
   "hex.VPINSRW.c5f1c4c2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VPINSRW", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "c5f1c4c2")) ++ "]   py=[True]"
   "hex.VPINSRD.c4e37122c2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VPINSRD", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "c4e37122c2")) ++ "]   py=[True]"
   "hex.IDIV.48f7fd = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("IDIV", 7, 5, 4, 8, 0, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "48f7fd")) ++ "]   py=[True]"
   "hex.DIV.48f7f5 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("DIV", 6, 5, 4, 8, 0, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "48f7f5")) ++ "]   py=[True]"
   "hex.ADD.4803d5 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("ADD", 2, 5, 4, 8, 8, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "4803d5")) ++ "]   py=[True]"
   "hex.ADDi.4881c2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("ADDi", 0, 2, 4, 8, 0, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 4)), "4881c2")) ++ "]   py=[True]"
   "hex.SUB.482bd5 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("SUB", 2, 5, 4, 8, 8, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "482bd5")) ++ "]   py=[True]"
   "hex.SUBi.4881ea = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("SUBi", 5, 2, 4, 8, 0, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 4)), "4881ea")) ++ "]   py=[True]"
   "hex.IMUL.480fafd5 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("IMUL", 2, 5, 4, 8, 8, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "480fafd5")) ++ "]   py=[True]"
   "hex.IMULi.4869d103000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("IMULi", 2, 1, 4, 8, 8, 0, False{}, 0, 4, 1, 4n, 3, False{}, 4, 4)), "4869d103000000")) ++ "]   py=[True]"
   "hex.AND.4823d5 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("AND", 2, 5, 4, 8, 8, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "4823d5")) ++ "]   py=[True]"
   "hex.ANDi.4881e2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("ANDi", 4, 2, 4, 8, 0, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 4)), "4881e2")) ++ "]   py=[True]"
   "hex.XOR.4833d5 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("XOR", 2, 5, 4, 8, 8, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "4833d5")) ++ "]   py=[True]"
   "hex.XORi.4881f2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("XORi", 6, 2, 4, 8, 0, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 4)), "4881f2")) ++ "]   py=[True]"
   "hex.OR.480bd5 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("OR", 2, 5, 4, 8, 8, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "480bd5")) ++ "]   py=[True]"
   "hex.ORi.4881ca = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("ORi", 1, 2, 4, 8, 0, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 4)), "4881ca")) ++ "]   py=[True]"
   "hex.SHL.48d3e2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("SHL", 4, 2, 4, 8, 0, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "48d3e2")) ++ "]   py=[True]"
   "hex.SHLi.48c1e2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("SHLi", 4, 2, 4, 8, 0, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 4)), "48c1e2")) ++ "]   py=[True]"
   "hex.SHR.48d3ea = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("SHR", 5, 2, 4, 8, 0, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "48d3ea")) ++ "]   py=[True]"
   "hex.SHRi.48c1ea = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("SHRi", 5, 2, 4, 8, 0, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 4)), "48c1ea")) ++ "]   py=[True]"
 ]

def Gate.rows9() -> List<&2, String>: [
   "hex.SAR.48d3fa = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("SAR", 7, 2, 4, 8, 0, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "48d3fa")) ++ "]   py=[True]"
   "hex.SARi.48c1fa = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("SARi", 7, 2, 4, 8, 0, 0, False{}, 0, 4, 0, 0n, 0, False{}, 4, 4)), "48c1fa")) ++ "]   py=[True]"
   "hex.CMP.493bd6 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("CMP", 2, 14, 4, 8, 8, 5, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "493bd6")) ++ "]   py=[True]"
   "hex.CMPi.81bc8c08000000 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("CMPi", 7, 4, 1, 4, 0, 0, True{}, 8, 4, 0, 0n, 0, False{}, 4, 0)), "81bc8c08000000")) ++ "]   py=[True]"
   "hex.VROUNDSS.c4e3710ac2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VROUNDSS", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "c4e3710ac2")) ++ "]   py=[True]"
   "hex.VROUNDSD.c4e3710bc2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VROUNDSD", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 8, 0)), "c4e3710bc2")) ++ "]   py=[True]"
   "hex.VSQRTSS.c5f251c2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VSQRTSS", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "c5f251c2")) ++ "]   py=[True]"
   "hex.VSQRTSD.c5f351c2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VSQRTSD", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 8, 0)), "c5f351c2")) ++ "]   py=[True]"
   "hex.VADDSS.c5f258c2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VADDSS", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "c5f258c2")) ++ "]   py=[True]"
   "hex.VADDSD.c5f358c2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VADDSD", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 8, 0)), "c5f358c2")) ++ "]   py=[True]"
   "hex.VSUBSS.c5f25cc2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VSUBSS", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "c5f25cc2")) ++ "]   py=[True]"
   "hex.VSUBSD.c5f35cc2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VSUBSD", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 8, 0)), "c5f35cc2")) ++ "]   py=[True]"
   "hex.VMULSS.c5f259c2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VMULSS", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "c5f259c2")) ++ "]   py=[True]"
   "hex.VMULSD.c5f359c2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VMULSD", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 8, 0)), "c5f359c2")) ++ "]   py=[True]"
   "hex.VDIVSS.c5f25ec2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VDIVSS", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 4, 0)), "c5f25ec2")) ++ "]   py=[True]"
   "hex.VDIVSD.c5f35ec2 = [" ++ Bool.show(String.eq(Hex.bytes(Enc.emit("VDIVSD", 0, 2, 4, 16, 16, 1, False{}, 0, 4, 0, 0n, 0, False{}, 8, 0)), "c5f35ec2")) ++ "]   py=[True]"
   "cls.device = [" ++ Cls.device() ++ "]   py=[CPU]"
   "cls.has_local = [" ++ Bool.show(Cls.has_local()) ++ "]   py=[False]"
   "cls.global_max = [" ++ ClsGmax() ++ "]   py=[1 0 0]"
   "cls.code_for_op = [" ++ Cls.code_for_op() ++ "]   py=[AND,CMPEQ,CMPLT,FDIV,NEG,OR,SHL,SHR,SQRT,SUB]"
   "cls.code_for_op_n = [" ++ U32.show(Cls.code_for_op_n()) ++ "]   py=[10]"
   "cls.base_dtypes = [" ++ Cls.base_dtypes() ++ "]   py=[bf16,bool,f16,f32,f64,fp8e4m3,fp8e4m3fnuz,fp8e5m2,fp8e5m2fnuz,i16,i32,i64,i8,u16,u32,u64,u8]"
   "cls.base_dtypes_n = [" ++ U32.show(Cls.base_dtypes_n()) ++ "]   py=[17]"
   "cls.drop_dtypes = [" ++ Cls.drop_dtypes() ++ "]   py=[bf16,fp8e4m3,fp8e4m3fnuz,fp8e5m2,fp8e5m2fnuz]"
   "cls.supported_dtypes = [" ++ Cls.supported_dtypes() ++ "]   py=[bool,f16,f32,f64,i16,i32,i64,i8,u16,u32,u64,u8]"
   "cls.supported_dtypes_n = [" ++ U32.show(Cls.supported_dtypes_n()) ++ "]   py=[12]"
   "cls.drop bf16 = [" ++ Bool.show(Cls.dropped("bf16")) ++ "]   py=[True]"
   "cls.drop bool = [" ++ Bool.show(Cls.dropped("bool")) ++ "]   py=[False]"
   "cls.drop f16 = [" ++ Bool.show(Cls.dropped("f16")) ++ "]   py=[False]"
   "cls.drop f32 = [" ++ Bool.show(Cls.dropped("f32")) ++ "]   py=[False]"
   "cls.drop f64 = [" ++ Bool.show(Cls.dropped("f64")) ++ "]   py=[False]"
   "cls.drop fp8e4m3 = [" ++ Bool.show(Cls.dropped("fp8e4m3")) ++ "]   py=[True]"
   "cls.drop fp8e4m3fnuz = [" ++ Bool.show(Cls.dropped("fp8e4m3fnuz")) ++ "]   py=[True]"
   "cls.drop fp8e5m2 = [" ++ Bool.show(Cls.dropped("fp8e5m2")) ++ "]   py=[True]"
   "cls.drop fp8e5m2fnuz = [" ++ Bool.show(Cls.dropped("fp8e5m2fnuz")) ++ "]   py=[True]"
   "cls.drop i16 = [" ++ Bool.show(Cls.dropped("i16")) ++ "]   py=[False]"
   "cls.drop i32 = [" ++ Bool.show(Cls.dropped("i32")) ++ "]   py=[False]"
   "cls.drop i64 = [" ++ Bool.show(Cls.dropped("i64")) ++ "]   py=[False]"
   "cls.drop i8 = [" ++ Bool.show(Cls.dropped("i8")) ++ "]   py=[False]"
   "cls.drop u16 = [" ++ Bool.show(Cls.dropped("u16")) ++ "]   py=[False]"
   "cls.drop u32 = [" ++ Bool.show(Cls.dropped("u32")) ++ "]   py=[False]"
   "cls.drop u64 = [" ++ Bool.show(Cls.dropped("u64")) ++ "]   py=[False]"
   "cls.drop u8 = [" ++ Bool.show(Cls.dropped("u8")) ++ "]   py=[False]"
   "asm.lines = [" ++ U32.show(AsmLines_n([Asm.skip(), Asm.skip(), Asm.label("L1"), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.MOVi", [Asm.reg("rdx", 8), Asm.reg("rsp", 8), Asm.reg("rcx", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.MOV", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rcx", 4, 16), []), Asm.ins("X86Ops.MOVSX", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rbx", 4, 3), []), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 0), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm1", 16)], True{}, AsmMem.of("rsp", "xmm2", 4, 4), [Asm.reg("xmm0", 16)]), Asm.ins("X86Ops.ADDi", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.imm(3)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm3", 16), Asm.reg("rdi", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.ADDi", [Asm.reg("rdx", 8), Asm.imm(5), Asm.reg("rsi", 8)], False{}, Asm.none(), Nil{}), Asm.ret("X86Ops.RET"), Asm.ins("X86Ops.VCVTSI2SS", [Asm.reg("xmm0", 16), Asm.reg("xmm2", 16), Asm.reg("xmm1", 16)], False{}, Asm.none(), Nil{})])) ++ "]   py=[12]"
 ]

def Gate.rows10() -> List<&2, String>: [
   "asm.total = [" ++ U32.show(AsmN(asm_str("kern", [Asm.skip(), Asm.skip(), Asm.label("L1"), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.MOVi", [Asm.reg("rdx", 8), Asm.reg("rsp", 8), Asm.reg("rcx", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.MOV", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rcx", 4, 16), []), Asm.ins("X86Ops.MOVSX", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rbx", 4, 3), []), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 0), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm1", 16)], True{}, AsmMem.of("rsp", "xmm2", 4, 4), [Asm.reg("xmm0", 16)]), Asm.ins("X86Ops.ADDi", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.imm(3)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm3", 16), Asm.reg("rdi", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.ADDi", [Asm.reg("rdx", 8), Asm.imm(5), Asm.reg("rsi", 8)], False{}, Asm.none(), Nil{}), Asm.ret("X86Ops.RET"), Asm.ins("X86Ops.VCVTSI2SS", [Asm.reg("xmm0", 16), Asm.reg("xmm2", 16), Asm.reg("xmm1", 16)], False{}, Asm.none(), Nil{})]))) ++ "]   py=[13]"
   "asm.L0..kern: = [" ++ Bool.show(String.eq(AsmLine.at(asm_str("kern", [Asm.skip(), Asm.skip(), Asm.label("L1"), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.MOVi", [Asm.reg("rdx", 8), Asm.reg("rsp", 8), Asm.reg("rcx", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.MOV", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rcx", 4, 16), []), Asm.ins("X86Ops.MOVSX", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rbx", 4, 3), []), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 0), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm1", 16)], True{}, AsmMem.of("rsp", "xmm2", 4, 4), [Asm.reg("xmm0", 16)]), Asm.ins("X86Ops.ADDi", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.imm(3)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm3", 16), Asm.reg("rdi", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.ADDi", [Asm.reg("rdx", 8), Asm.imm(5), Asm.reg("rsi", 8)], False{}, Asm.none(), Nil{}), Asm.ret("X86Ops.RET"), Asm.ins("X86Ops.VCVTSI2SS", [Asm.reg("xmm0", 16), Asm.reg("xmm2", 16), Asm.reg("xmm1", 16)], False{}, Asm.none(), Nil{})]), 0n), ".kern:")) ++ "]   py=[True]"
   "asm.L1.L1: = [" ++ Bool.show(String.eq(AsmLine.at(asm_str("kern", [Asm.skip(), Asm.skip(), Asm.label("L1"), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.MOVi", [Asm.reg("rdx", 8), Asm.reg("rsp", 8), Asm.reg("rcx", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.MOV", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rcx", 4, 16), []), Asm.ins("X86Ops.MOVSX", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rbx", 4, 3), []), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 0), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm1", 16)], True{}, AsmMem.of("rsp", "xmm2", 4, 4), [Asm.reg("xmm0", 16)]), Asm.ins("X86Ops.ADDi", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.imm(3)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm3", 16), Asm.reg("rdi", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.ADDi", [Asm.reg("rdx", 8), Asm.imm(5), Asm.reg("rsi", 8)], False{}, Asm.none(), Nil{}), Asm.ret("X86Ops.RET"), Asm.ins("X86Ops.VCVTSI2SS", [Asm.reg("xmm0", 16), Asm.reg("xmm2", 16), Asm.reg("xmm1", 16)], False{}, Asm.none(), Nil{})]), 1n), "L1:")) ++ "]   py=[True]"
   "asm.L2.    mov     [rsp + rcx*4 + 8], rdx = [" ++ Bool.show(String.eq(AsmLine.at(asm_str("kern", [Asm.skip(), Asm.skip(), Asm.label("L1"), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.MOVi", [Asm.reg("rdx", 8), Asm.reg("rsp", 8), Asm.reg("rcx", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.MOV", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rcx", 4, 16), []), Asm.ins("X86Ops.MOVSX", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rbx", 4, 3), []), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 0), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm1", 16)], True{}, AsmMem.of("rsp", "xmm2", 4, 4), [Asm.reg("xmm0", 16)]), Asm.ins("X86Ops.ADDi", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.imm(3)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm3", 16), Asm.reg("rdi", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.ADDi", [Asm.reg("rdx", 8), Asm.imm(5), Asm.reg("rsi", 8)], False{}, Asm.none(), Nil{}), Asm.ret("X86Ops.RET"), Asm.ins("X86Ops.VCVTSI2SS", [Asm.reg("xmm0", 16), Asm.reg("xmm2", 16), Asm.reg("xmm1", 16)], False{}, Asm.none(), Nil{})]), 2n), "    mov     [rsp + rcx*4 + 8], rdx")) ++ "]   py=[True]"
 ]

def Gate.rows11() -> List<&2, String>: [
   "asm.L3.    mov     rdx, rsp, rcx = [" ++ Bool.show(String.eq(AsmLine.at(asm_str("kern", [Asm.skip(), Asm.skip(), Asm.label("L1"), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.MOVi", [Asm.reg("rdx", 8), Asm.reg("rsp", 8), Asm.reg("rcx", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.MOV", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rcx", 4, 16), []), Asm.ins("X86Ops.MOVSX", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rbx", 4, 3), []), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 0), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm1", 16)], True{}, AsmMem.of("rsp", "xmm2", 4, 4), [Asm.reg("xmm0", 16)]), Asm.ins("X86Ops.ADDi", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.imm(3)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm3", 16), Asm.reg("rdi", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.ADDi", [Asm.reg("rdx", 8), Asm.imm(5), Asm.reg("rsi", 8)], False{}, Asm.none(), Nil{}), Asm.ret("X86Ops.RET"), Asm.ins("X86Ops.VCVTSI2SS", [Asm.reg("xmm0", 16), Asm.reg("xmm2", 16), Asm.reg("xmm1", 16)], False{}, Asm.none(), Nil{})]), 3n), "    mov     rdx, rsp, rcx")) ++ "]   py=[True]"
   "asm.L4.    mov     rdx, [rsp + rcx*4 + 16] = [" ++ Bool.show(String.eq(AsmLine.at(asm_str("kern", [Asm.skip(), Asm.skip(), Asm.label("L1"), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.MOVi", [Asm.reg("rdx", 8), Asm.reg("rsp", 8), Asm.reg("rcx", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.MOV", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rcx", 4, 16), []), Asm.ins("X86Ops.MOVSX", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rbx", 4, 3), []), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 0), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm1", 16)], True{}, AsmMem.of("rsp", "xmm2", 4, 4), [Asm.reg("xmm0", 16)]), Asm.ins("X86Ops.ADDi", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.imm(3)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm3", 16), Asm.reg("rdi", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.ADDi", [Asm.reg("rdx", 8), Asm.imm(5), Asm.reg("rsi", 8)], False{}, Asm.none(), Nil{}), Asm.ret("X86Ops.RET"), Asm.ins("X86Ops.VCVTSI2SS", [Asm.reg("xmm0", 16), Asm.reg("xmm2", 16), Asm.reg("xmm1", 16)], False{}, Asm.none(), Nil{})]), 4n), "    mov     rdx, [rsp + rcx*4 + 16]")) ++ "]   py=[True]"
   "asm.L5.    movsx   rdx, [rsp + rbx*4 + 3] = [" ++ Bool.show(String.eq(AsmLine.at(asm_str("kern", [Asm.skip(), Asm.skip(), Asm.label("L1"), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.MOVi", [Asm.reg("rdx", 8), Asm.reg("rsp", 8), Asm.reg("rcx", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.MOV", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rcx", 4, 16), []), Asm.ins("X86Ops.MOVSX", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rbx", 4, 3), []), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 0), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm1", 16)], True{}, AsmMem.of("rsp", "xmm2", 4, 4), [Asm.reg("xmm0", 16)]), Asm.ins("X86Ops.ADDi", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.imm(3)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm3", 16), Asm.reg("rdi", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.ADDi", [Asm.reg("rdx", 8), Asm.imm(5), Asm.reg("rsi", 8)], False{}, Asm.none(), Nil{}), Asm.ret("X86Ops.RET"), Asm.ins("X86Ops.VCVTSI2SS", [Asm.reg("xmm0", 16), Asm.reg("xmm2", 16), Asm.reg("xmm1", 16)], False{}, Asm.none(), Nil{})]), 5n), "    movsx   rdx, [rsp + rbx*4 + 3]")) ++ "]   py=[True]"
   "asm.L6.    mov     [rsp + rcx*4], rdx = [" ++ Bool.show(String.eq(AsmLine.at(asm_str("kern", [Asm.skip(), Asm.skip(), Asm.label("L1"), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.MOVi", [Asm.reg("rdx", 8), Asm.reg("rsp", 8), Asm.reg("rcx", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.MOV", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rcx", 4, 16), []), Asm.ins("X86Ops.MOVSX", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rbx", 4, 3), []), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 0), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm1", 16)], True{}, AsmMem.of("rsp", "xmm2", 4, 4), [Asm.reg("xmm0", 16)]), Asm.ins("X86Ops.ADDi", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.imm(3)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm3", 16), Asm.reg("rdi", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.ADDi", [Asm.reg("rdx", 8), Asm.imm(5), Asm.reg("rsi", 8)], False{}, Asm.none(), Nil{}), Asm.ret("X86Ops.RET"), Asm.ins("X86Ops.VCVTSI2SS", [Asm.reg("xmm0", 16), Asm.reg("xmm2", 16), Asm.reg("xmm1", 16)], False{}, Asm.none(), Nil{})]), 6n), "    mov     [rsp + rcx*4], rdx")) ++ "]   py=[True]"
 ]

def Gate.rows12() -> List<&2, String>: [
   "asm.L7.    vaddss  xmm0, xmm1, [rsp + xmm2*4 + 4], xmm0 = [" ++ Bool.show(String.eq(AsmLine.at(asm_str("kern", [Asm.skip(), Asm.skip(), Asm.label("L1"), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.MOVi", [Asm.reg("rdx", 8), Asm.reg("rsp", 8), Asm.reg("rcx", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.MOV", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rcx", 4, 16), []), Asm.ins("X86Ops.MOVSX", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rbx", 4, 3), []), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 0), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm1", 16)], True{}, AsmMem.of("rsp", "xmm2", 4, 4), [Asm.reg("xmm0", 16)]), Asm.ins("X86Ops.ADDi", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.imm(3)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm3", 16), Asm.reg("rdi", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.ADDi", [Asm.reg("rdx", 8), Asm.imm(5), Asm.reg("rsi", 8)], False{}, Asm.none(), Nil{}), Asm.ret("X86Ops.RET"), Asm.ins("X86Ops.VCVTSI2SS", [Asm.reg("xmm0", 16), Asm.reg("xmm2", 16), Asm.reg("xmm1", 16)], False{}, Asm.none(), Nil{})]), 7n), "    vaddss  xmm0, xmm1, [rsp + xmm2*4 + 4], xmm0")) ++ "]   py=[True]"
   "asm.L8.    add     [rsp + rcx*4 + 8], 3 = [" ++ Bool.show(String.eq(AsmLine.at(asm_str("kern", [Asm.skip(), Asm.skip(), Asm.label("L1"), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.MOVi", [Asm.reg("rdx", 8), Asm.reg("rsp", 8), Asm.reg("rcx", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.MOV", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rcx", 4, 16), []), Asm.ins("X86Ops.MOVSX", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rbx", 4, 3), []), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 0), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm1", 16)], True{}, AsmMem.of("rsp", "xmm2", 4, 4), [Asm.reg("xmm0", 16)]), Asm.ins("X86Ops.ADDi", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.imm(3)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm3", 16), Asm.reg("rdi", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.ADDi", [Asm.reg("rdx", 8), Asm.imm(5), Asm.reg("rsi", 8)], False{}, Asm.none(), Nil{}), Asm.ret("X86Ops.RET"), Asm.ins("X86Ops.VCVTSI2SS", [Asm.reg("xmm0", 16), Asm.reg("xmm2", 16), Asm.reg("xmm1", 16)], False{}, Asm.none(), Nil{})]), 8n), "    add     [rsp + rcx*4 + 8], 3")) ++ "]   py=[True]"
   "asm.L9.    vaddss  xmm0, xmm3, rdi = [" ++ Bool.show(String.eq(AsmLine.at(asm_str("kern", [Asm.skip(), Asm.skip(), Asm.label("L1"), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.MOVi", [Asm.reg("rdx", 8), Asm.reg("rsp", 8), Asm.reg("rcx", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.MOV", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rcx", 4, 16), []), Asm.ins("X86Ops.MOVSX", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rbx", 4, 3), []), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 0), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm1", 16)], True{}, AsmMem.of("rsp", "xmm2", 4, 4), [Asm.reg("xmm0", 16)]), Asm.ins("X86Ops.ADDi", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.imm(3)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm3", 16), Asm.reg("rdi", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.ADDi", [Asm.reg("rdx", 8), Asm.imm(5), Asm.reg("rsi", 8)], False{}, Asm.none(), Nil{}), Asm.ret("X86Ops.RET"), Asm.ins("X86Ops.VCVTSI2SS", [Asm.reg("xmm0", 16), Asm.reg("xmm2", 16), Asm.reg("xmm1", 16)], False{}, Asm.none(), Nil{})]), 9n), "    vaddss  xmm0, xmm3, rdi")) ++ "]   py=[True]"
   "asm.L10.    add     rdx, 5, rsi = [" ++ Bool.show(String.eq(AsmLine.at(asm_str("kern", [Asm.skip(), Asm.skip(), Asm.label("L1"), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.MOVi", [Asm.reg("rdx", 8), Asm.reg("rsp", 8), Asm.reg("rcx", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.MOV", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rcx", 4, 16), []), Asm.ins("X86Ops.MOVSX", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rbx", 4, 3), []), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 0), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm1", 16)], True{}, AsmMem.of("rsp", "xmm2", 4, 4), [Asm.reg("xmm0", 16)]), Asm.ins("X86Ops.ADDi", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.imm(3)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm3", 16), Asm.reg("rdi", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.ADDi", [Asm.reg("rdx", 8), Asm.imm(5), Asm.reg("rsi", 8)], False{}, Asm.none(), Nil{}), Asm.ret("X86Ops.RET"), Asm.ins("X86Ops.VCVTSI2SS", [Asm.reg("xmm0", 16), Asm.reg("xmm2", 16), Asm.reg("xmm1", 16)], False{}, Asm.none(), Nil{})]), 10n), "    add     rdx, 5, rsi")) ++ "]   py=[True]"
 ]

def Gate.rows13() -> List<&2, String>: [
   "asm.L11.    ret     = [" ++ Bool.show(String.eq(AsmLine.at(asm_str("kern", [Asm.skip(), Asm.skip(), Asm.label("L1"), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.MOVi", [Asm.reg("rdx", 8), Asm.reg("rsp", 8), Asm.reg("rcx", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.MOV", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rcx", 4, 16), []), Asm.ins("X86Ops.MOVSX", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rbx", 4, 3), []), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 0), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm1", 16)], True{}, AsmMem.of("rsp", "xmm2", 4, 4), [Asm.reg("xmm0", 16)]), Asm.ins("X86Ops.ADDi", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.imm(3)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm3", 16), Asm.reg("rdi", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.ADDi", [Asm.reg("rdx", 8), Asm.imm(5), Asm.reg("rsi", 8)], False{}, Asm.none(), Nil{}), Asm.ret("X86Ops.RET"), Asm.ins("X86Ops.VCVTSI2SS", [Asm.reg("xmm0", 16), Asm.reg("xmm2", 16), Asm.reg("xmm1", 16)], False{}, Asm.none(), Nil{})]), 11n), "    ret    ")) ++ "]   py=[True]"
   "asm.L12.    vcvtsi2ss xmm0, xmm2, xmm1 = [" ++ Bool.show(String.eq(AsmLine.at(asm_str("kern", [Asm.skip(), Asm.skip(), Asm.label("L1"), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.MOVi", [Asm.reg("rdx", 8), Asm.reg("rsp", 8), Asm.reg("rcx", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.MOV", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rcx", 4, 16), []), Asm.ins("X86Ops.MOVSX", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rbx", 4, 3), []), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 0), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm1", 16)], True{}, AsmMem.of("rsp", "xmm2", 4, 4), [Asm.reg("xmm0", 16)]), Asm.ins("X86Ops.ADDi", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.imm(3)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm3", 16), Asm.reg("rdi", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.ADDi", [Asm.reg("rdx", 8), Asm.imm(5), Asm.reg("rsi", 8)], False{}, Asm.none(), Nil{}), Asm.ret("X86Ops.RET"), Asm.ins("X86Ops.VCVTSI2SS", [Asm.reg("xmm0", 16), Asm.reg("xmm2", 16), Asm.reg("xmm1", 16)], False{}, Asm.none(), Nil{})]), 12n), "    vcvtsi2ss xmm0, xmm2, xmm1")) ++ "]   py=[True]"
   "asm.fn = [" ++ Bool.show(String.eq(AsmLine.at(asm_str("mykern", [Asm.skip(), Asm.skip(), Asm.label("L1"), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.MOVi", [Asm.reg("rdx", 8), Asm.reg("rsp", 8), Asm.reg("rcx", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.MOV", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rcx", 4, 16), []), Asm.ins("X86Ops.MOVSX", [Asm.reg("rdx", 8)], True{}, AsmMem.of("rsp", "rbx", 4, 3), []), Asm.ins("X86Ops.MOVm", [], True{}, AsmMem.of("rsp", "rcx", 4, 0), [Asm.reg("rdx", 8)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm1", 16)], True{}, AsmMem.of("rsp", "xmm2", 4, 4), [Asm.reg("xmm0", 16)]), Asm.ins("X86Ops.ADDi", [], True{}, AsmMem.of("rsp", "rcx", 4, 8), [Asm.imm(3)]), Asm.ins("X86Ops.VADDSS", [Asm.reg("xmm0", 16), Asm.reg("xmm3", 16), Asm.reg("rdi", 8)], False{}, Asm.none(), Nil{}), Asm.ins("X86Ops.ADDi", [Asm.reg("rdx", 8), Asm.imm(5), Asm.reg("rsi", 8)], False{}, Asm.none(), Nil{}), Asm.ret("X86Ops.RET"), Asm.ins("X86Ops.VCVTSI2SS", [Asm.reg("xmm0", 16), Asm.reg("xmm2", 16), Asm.reg("xmm1", 16)], False{}, Asm.none(), Nil{})]), 0n), ".mykern:")) ++ "]   py=[True]"
   "render.0-0.00000000 = [" ++ Bool.show(String.eq(Render.le4(Render.delta(0, 0)), "00000000")) ++ "]   py=[True]"
   "render.12-12.00000000 = [" ++ Bool.show(String.eq(Render.le4(Render.delta(12, 12)), "00000000")) ++ "]   py=[True]"
   "render.0-16.f0ffffff = [" ++ Bool.show(String.eq(Render.le4(Render.delta(0, 16)), "f0ffffff")) ++ "]   py=[True]"
   "render.40-12.1c000000 = [" ++ Bool.show(String.eq(Render.le4(Render.delta(40, 12)), "1c000000")) ++ "]   py=[True]"
   "render.0-1048576.0000f0ff = [" ++ Bool.show(String.eq(Render.le4(Render.delta(0, 1048576)), "0000f0ff")) ++ "]   py=[True]"
 ]
# THE TABLE, IN CHUNKS. `String.concat` is ONE `IO.print` over 700 arguments and the
# parser refuses it, and a fold over a list of row-strings would cost a step per row.
# 14 list literals joined by `List.concat` is the shape that compiles and is one
# `IO.print`.

def Gate.rows() -> List<&2, String>:
  List.concat(&2, String, [Gate.rows0(), Gate.rows1(), Gate.rows2(), Gate.rows3(), Gate.rows4(), Gate.rows5(), Gate.rows6(), Gate.rows7(), Gate.rows8(), Gate.rows9(), Gate.rows10(), Gate.rows11(), Gate.rows12(), Gate.rows13()])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.join(Gate.rows(), "\n"))

