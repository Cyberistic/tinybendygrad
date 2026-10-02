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
#   STAGE 5  THE ENCODER AND THE ASSEMBLY TEXT      py:528-618, 91 lines   DONE
#            + py:728-749, 22 lines
#     `encode`'s prefix / REX / VEX, MODRM, SIB, displacement and immediate bytes,
#     and `asm_str`'s `_format_op` / `_format` / `_mem_adress`. GATED ON REAL
#     MACHINE BYTES: eighty-four `hex.*` rows are CPython's own `encode()` output
#     and one hundred and one `enc.*` rows are its `encode()` PARAMETERS read out
#     of the source with CPython's `ast`; the port re-derives both from the table
#     and its own arithmetic. A wrong opcode cannot produce the same bytes.
#
#   STAGE 6  THE RENDERER'S OWN CONSTANTS           py:700-710, 11 lines   DONE
#            + py:770, 1 line
#     `device`, `has_local`, `global_max`, `code_for_op`, `supported_dtypes`.
#     6 rows.
#
#   STAGE 7  JUMP PATCHING                          py:751-768, 18 lines   PART
#     `render`'s label table, jump backpatch table and the little-endian signed
#     four-byte patch. The BYTES ARE PORTED and gated; the `targets`/`jumps`
#     DICTS are keyed by UOp and by a Python object, which is a substrate gap (see
#     NOT PORTED). `TODO(p3) x86.py:752`.
#
#   STAGE 3b `to_int` and `is_two_address`           py:190, 716           DONE
#     4 + 89 rows.
#
#   COVERED: 350 of 770 Python lines, and the 350 are the lines that DECIDE WHAT
#   BYTES COME OUT. The 420 not covered are the five `PatternMatcher` tables and
#   the `ctx`-mutating rewrite helpers -- see NOT PORTED.
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
# * `imm` (py:191) / `to_imm` (py:192-196) -- `truncate[dt](v)` is
#   `dtype.bend`'s table and the answer is a `.rtag()`'d arena node. `to_imm`'s
#   DECISION (CAST-of-CONST, then int64-overflow, then int-or-bool) is pure and is
#   recorded rather than ported alone. `TODO(p3) x86.py:191`.
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
# THE GATE. `.agents/slop/x86/x86-oracle.py` is the ONLY source of `py=` text,
# and it produces the reference AND the gate's row source FROM ONE RUN, so the two
# cannot drift. EVERY expectation is CPython calling `tinygrad/renderer/isa/x86.py`
# on THIS tree -- including the eighty-four `hex.*` rows, which are CPython's own
# `encode()` bytes for a fixed register fixture, not a transcription of them.
#
#   .venv/bin/python .agents/slop/x86/x86-oracle.py rows > .agents/slop/x86/py1.txt
#   ./bin/bend tinybendygrad/renderer/isa/x86.bend > .agents/slop/x86/i.txt
#   diff .agents/slop/x86/i.txt .agents/slop/x86/py1.txt && echo GATE GREEN
#
# 793 rows. NO `py=` LITERAL IN THIS FILE IS TYPED.
# ===========================================================================

import Base

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

def Hex.digit(+b: U32) -> String:
  Bool.pick(String, U32.is_lt(b, 10), Hex.alpha(U32.sub(b, 10)), Hex.alpha(b))

def Hex.nibble(+b: U32) -> U32: U32.and(b, 15)

def Hex.byte(+b: U32) -> String:
  String.concat([Hex.digit(Hex.nibble(U32.shrn(b, 4n))), Hex.digit(Hex.nibble(b))])

def Hex.bytes.go(bs: List<&2, U32>, +acc: String) -> String:
  # the accumulator is PREPENDED and the result reversed, because `List.append`
  # and a `+` on String are both built for the front and a 250-byte instruction
  # is 250 recursive steps.
  match bs:
    case Nil{}: String.reverse(acc)
    case h <> t: Hex.bytes.go(t, String.concat([Hex.byte(h), acc]))

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

def Reg.s1n(+i: U32) -> String:
  # the one place a SUB-NAME is arithmetic rather than a prefix: the 1-byte form of
  # `ax/cx/dx/bx` drops the 'x' (`ax -> al`) and the other four keep it
  # (`sp -> spl`), because those four have no REX-free high byte.
  match i:
    case 0: "al"
    case 1: "cl"
    case 2: "dl"
    case 3: "bl"
    case 4: "spl"
    case 5: "bpl"
    case 6: "sil"
    case 7: "dil"
    case _: String.concat(["r", U32.show(i), "b"])

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
def Reg.wgpr_idxs.go(+ixs: List<&2, Nat>, +n: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  # `tuple(r for r in GPR if r != RSP)` -- RSP is index 4. The filter runs on
  # INDICES and accumulates PREPENDED, because `List.append` spends the list it is
  # given and a fold written the other way round accumulated in REVERSE and
  # typechecked (`bend2-constraints.md` line 1590).
  match ixs:
    case Nil{}: List.reverse(&2, U32, acc)
    case h <> t:
      Reg.wgpr_idxs.go(t, U32.inc(n), Bool.pick(List<&2, U32>, U32.is_eq(n, 4), acc,
        List.append(&2, U32, acc, [n])))

def Reg.wgpr_idxs() -> List<&2, U32>: Reg.wgpr_idxs.go(List.range(16n), 0, Nil{})

def Reg.wgpr_map(ixs: List<&2, U32>) -> List<&2, Reg>:
  match ixs:
    case Nil{}: Nil{}
    case h <> t: List.append(&2, Reg, Reg.wgpr_map(t), [Reg.gpr(h)])

def Reg.wgpr_list() -> List<&2, Reg>: Reg.wgpr_map(Reg.wgpr_idxs())

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

def Reg.maybe_name(m: Maybe<&2, Reg>) -> String:
  match m:
    case Some{r}: Reg.name(r)
    case None{}: "?"

def Reg.maybe_index(m: Maybe<&2, Reg>) -> U32:
  match m:
    case Some{r}: Reg.index(r)
    case None{}: 99

def Reg.maybe_size(m: Maybe<&2, Reg>) -> U32:
  match m:
    case Some{r}: Reg.size(r)
    case None{}: 0

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

def Reg.strs_row(+r: Reg) -> String:
  String.join([Reg.s4(r), Reg.s2(r), Reg.s1(r)], ",")

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
    "VCVTPH2PS", "VCVTPS2PH", "VCVTSI2SD", "VCVTSD2SS", "VCVTSI2SS", "VCVTSI2SD", "VCVTTSS2SI",
    "VCVTTSD2SI", "VMOVD", "VMOVQ", "VMOVDm", "VMOVQm", "VCMPSS", "VCMPSD", "SETNE", "SETE",
    "SETL", "SETB", "CMOVNE", "CMOVE", "CMOVL", "CMOVB", "VBLENDVPS", "VBLENDVPD", "JNE", "JE",
    "JL", "JB", "JGE", "JMP", "VINSERTPS", "VPSRLDQ", "VPEXTRW", "VPEXTRD", "VPINSRW",
    "VPINSRD", "IDIV", "DIV", "ADD", "ADDi", "SUB", "SUBi", "IMUL", "IMULi", "AND", "ANDi",
    "XOR", "XORi", "OR", "ORi", "SHL", "SHLi", "SHR", "SHRi", "SAR", "SARi", "CMP", "CMPi",
    "VROUNDSS", "VROUNDSD", "VSQRTSS", "VSQRTSD", "VADDSS", "VADDSD", "VSUBSS", "VSUBSD",
    "VMULSS", "VMULSD", "VDIVSS", "VDIVSD", "RET",
 ]

def op_len() -> U32: U32.from_nat(List.length(&2, String, op_names()))

# `X86Ops[op.name]` is the forward lookup and `X86Ops(n).name` the reverse; both
# are POSITION lookups here, and `?"` is the answer for a name or number that is
# not in the enum, which is what a Python `KeyError` would raise. TWO WALKS AND NOT
# ONE THAT CARRIES BOTH: a walk returning a pair would need a `String & U32` and
# Bend has a tuple TYPE and no tuple LITERAL -- `ops.bend`'s `Found.of(p: Arena &
# U32)` destructures one, nothing constructs one.
def Op.fwd(+ns: List<&2, String>, +nm: String, +i: U32) -> String:
  match ns:
    case Nil{}: "?"
    case h <> t: Bool.pick(String, String.eq(h, nm), U32.show(i), Op.fwd(t, nm, U32.inc(i)))


def op_num(+nm: String) -> String: Op.fwd(op_names(), nm, 0)

def Op.rev(+ns: List<&2, String>, +want: U32, +i: U32) -> String:
  match ns:
    case Nil{}: "?"
    case h <> t: Bool.pick(String, U32.is_eq(i, want), h, Op.rev(t, want, U32.inc(i)))


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
                        "VCVTSI2SD", "VCVTS2SD", "VCVTSD2SS", "IDIV", "DIV"])
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
    case Nil{}: List.reverse(&2, String, acc)
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

# `to_int` (x86.py:190) -- `{float16: int16, float32: int32, float64: int64}[dt]`.
# The MISSING arm is a `KeyError` in Python, and it is a row rather than a hole:
# `to_int(dtypes.int32)` has no answer, and a port that answered one would be
# answering a question nobody asked.
def Op.to_int(+nm: String) -> String:
  match nm:
    case "float16": "short"
    case "float32": "int"
    case "float64": "long"
    case _: "KEYERROR"

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
  # literal (MEASURED: `0x8B` is a parse error naming the `x`). `we` 1 and 2 are
  # SELECTORS -- 1 is `x.src[1].dtype.itemsize == 8` (the two VCVTSI2) and 2 is
  # `x.dtype.itemsize == 8` (the two VCVTT*SI) -- and `we` is read only when
  # `sel != 0`, so every legacy entry carries 0 and prints `-`.
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
  Enc.of("VCVTSI2SD", 42, 0, False{}, 3, 1, 1),
  Enc.of("VCVTSI2SS", 42, 0, False{}, 2, 1, 1),
  Enc.of("VCVTSS2SD", 90, 0, False{}, 2, 1, 0),
  Enc.of("VCVTTSD2SI", 44, 0, False{}, 3, 1, 2),
  Enc.of("VCVTTSS2SI", 44, 0, False{}, 2, 1, 2),
  Enc.of("VDIVSD", 94, 0, False{}, 3, 1, 0),
  Enc.of("VDIVSS", 94, 0, False{}, 2, 1, 0),
  Enc.of("VINSERTPS", 33, 0, False{}, 1, 3, 0),
  Enc.of("VMOVD", 110, 0, False{}, 1, 1, 0),
  Enc.of("VMOVDm", 126, 0, False{}, 1, 1, 0),
  Enc.of("VMOVQ", 110, 0, False{}, 1, 1, 2),
  Enc.of("VMOVQm", 126, 0, False{}, 1, 1, 2),
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
  # the first opcode byte of the six conditional jumps and `JMP`
  match nm:
    case "JE": 132
    case "JNE": 133
    case "JL": 140
    case "JB": 130
    case "JGE": 141
    case "JMP": 233
    case _: 15

def Enc.direct_op2(+nm: String) -> U32:
  match nm:
    case "JE": 0
    case "JNE": 0
    case "JL": 0
    case "JB": 0
    case "JGE": 0
    case "JMP": 0
    case _: 132

def Enc.direct_count(+nm: String) -> U32:
  # how many bytes follow the opcode. `Enc.is_direct` has already answered that `nm`
  # is one of the eight, so this is TWO arms and not eight: a jump is
  # `opcode + int(0).to_bytes(4)` and `RET` is the single byte 0xC3 with NOTHING
  # after it -- the one entry here that is not a jump.
  match nm:
    case "RET": 0
    case _: 4

# --- the whole instruction, in order. x86.py:543-595 ---------------------------
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
  # THE COUNTDOWN `k` AND THE TOTAL `n` ARE BOTH `Nat`, and the byte index is
  # `n - k` in `Nat` too, because the byte offset feeds `Nat.mul` in `Enc.imm_byte`.
  match k:
    case 0n: Nil{}
    case 1n+p: List.append(&2, U32, Enc.imm_int(p, n, imm), [Enc.imm_byte(imm, Nat.sub(n, k))])

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
def Enc.demote_of(+rm_sz: U32, +reg_sz: U32, +no_demote: Bool, +has_disp: Bool, +rm: U32) -> Bool:
  # `(rm_sz == 1 or reg_sz == 1) and x.arg[0] not in X86GroupOp.ReadFlags | {LEA}`,
  # which in the encoder means "there is a prefix-free one-byte form" -- the 8-bit
  # opcodes are one LESS than the 16/32/64-bit ones (x86.py:557). `no_demote` is the
  # `arg[0] not in ReadFlags | {LEA}` test and is a GATE ROW of its own.
  Bool.and(Bool.or(U32.is_eq(rm_sz, 1), U32.is_eq(reg_sz, 1)),
    Bool.and(Bool.not(no_demote), Bool.not(has_disp)))

def Enc.ge4(+v: U32) -> Bool: U32.is_ge(v, 4)

def Enc.gt0(+v: U32) -> Bool: U32.is_gt(v, 0)

def Enc.needs_rex(+w: Bool, +r: U32, +x: U32, +b: U32, +reg_sz: U32, +reg: U32, +rm_sz: U32, +rm: U32, +demote: Bool, +has_disp: Bool) -> Bool:
  # `w | r | x | b | (reg_sz == 1 & reg >> 2) | (rm_sz == 1 & rm >> 2) | (demote and
  # disp_uop is None and rm >= 4)`. THE LAST CLAUSE IS THE ONE THAT IS EASY TO LOSE:
  # without it a one-byte `mov rsp, rcx` gets no REX and cannot address the low byte
  # of rsp at all.
  Bool.or(Bool.or(Bool.or(w, Enc.gt0(r)), Bool.or(Enc.gt0(x), Enc.gt0(b))),
    Bool.or(Bool.or(Bool.and(U32.is_eq(reg_sz, 1), Enc.ge4(reg)),
      Bool.and(U32.is_eq(rm_sz, 1), Enc.ge4(rm))),
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

def Enc.sib_scale(+rm_sz: U32, +has_index: Bool) -> U32: Enc.sib_scale.of(rm_sz, has_index)

def Enc.sib_byte(+scale: U32, +idx3: U32, +rm3: U32) -> U32:
  # `scale << 6 | idx << 3 | rm` -- and rm here is the FULL three-bit register, not the
  # `rm3` MODRM carried, which is the whole reason the byte exists.
  Enc.or4(Enc.shl(scale, 6n), Enc.shl(idx3, 3n), rm3, 0)

def Enc.want_sib(+noidx: Bool, +mod: U32) -> Bool: Bool.and(Bool.not(noidx), Bool.not(U32.is_eq(mod, 3)))

def Enc.legacy_head.of(+pfx: List<&2, U32>, +need: Bool, +rex: U32, +opc: U32) -> List<&2, U32>:
  # `inst += bytes([0x66])` then OPTIONALLY the REX, then the opcode. The prefix and
  # the REX are the only two bytes before the opcode and they are both optional, so
  # this is a two-arm shape rather than three.
  match need:
    case True{}: Enc.cat(pfx, [rex, opc])
    case False{}: Enc.cat(pfx, [opc])


def Enc.rex_byte(+w: Bool, +r: U32, +x: U32, +b: U32) -> U32:
  # `0b0100 << 4 | w << 3 | r << 2 | x << 1 | b`. The leading `64` is that shift.
  Enc.or4(64, Enc.pick3(w, 8), Enc.pick3(Enc.gt0(r), 4), Enc.or2(Enc.pick3(Enc.gt0(x), 2), b))

# --- OPCODE, x86.py:564 ---------------------------------------------------------

def Enc.legacy_head(+nm: String, +r: U32, +x: U32, +b: U32, +sz: U32, +opc: U32, +rm: U32, +reg: U32, +rm_sz: U32, +reg_sz: U32, +has_disp: Bool, +no_demote: Bool) -> List<&2, U32>:
  Enc.legacy_head.of(Enc.prefix_byte(sz),
    Enc.needs_rex(U32.is_eq(sz, 8), r, x, b, reg_sz, reg, rm_sz, rm,
      Enc.demote_of(rm_sz, reg_sz, no_demote, has_disp, rm), has_disp),
    Enc.rex_byte(U32.is_eq(sz, 8), r, x, b),
    opc)


def Enc.pp_of(+nm: String) -> U32: Enc.pp(enc_find(nm))



def Enc.emit.head.of(+sel: U32, +nm: String, +reg: U32, +rm: U32, +idx: U32, +rm_sz: U32, +reg_sz: U32, +vvvv: U32, +has_disp: Bool, +no_demote: Bool, +r: U32, +x: U32, +b: U32, +sz: U32, +opc: U32, +we: U32) -> List<&2, U32>:
  # `r, _x, b = reg >> 3, idx >> 3, rm >> 3` and `sz = reg_sz or rm_sz` -- both are
  # read by every downstream byte, so they are computed ONCE here.
  match sel:
    case 0: Enc.legacy_head(nm, r, x, b, sz, opc, rm, reg, rm_sz, reg_sz, has_disp, no_demote)
    case _: Enc.vex_bytes(Bool.pick(Bool, Bool.and(U32.is_eq(sel, 1), Bool.and(U32.is_zero(x),
      Bool.and(U32.is_zero(b), U32.is_zero(we)))), True{}, False{}), r, x, b, vvvv, we, sel, Enc.pp_of(nm))


def Enc.demoted_opc.of(+opc: U32, +arm: U32) -> U32:
  match arm:
    case 1: U32.sub(opc, 1)
    case _: opc

# `if demote: opc -= 1` -- the ONLY arithmetic in the opcode byte.

def Enc.demoted_opc(+nm: String, +rm: U32, +rm_sz: U32, +reg_sz: U32, +has_disp: Bool, +no_demote: Bool) -> U32:
  Enc.demoted_opc.of(Enc.opc(enc_find(nm)),
    Bool.pick(U32, Enc.demote_of(rm_sz, reg_sz, no_demote, has_disp, rm), 1, 0))

# --- MODRM, x86.py:566-582 ------------------------------------------------------

def Enc.we_of.of(+selw: U32, +rm_sz: U32, +reg_sz: U32) -> U32:
  match selw:
    case 1: Bool.pick(U32, U32.is_eq(reg_sz, 8), 1, 0)
    case 2: Bool.pick(U32, U32.is_eq(rm_sz, 8), 1, 0)
    case _: 0


def Enc.we_of(+nm: String, +rm_sz: U32, +reg_sz: U32) -> U32:
  Enc.we_of.of(Enc.we_sel(enc_find(nm)), rm_sz, reg_sz)


def Enc.emit.head(+nm: String, +reg: U32, +rm: U32, +idx: U32, +rm_sz: U32, +reg_sz: U32, +vvvv: U32, +has_disp: Bool, +no_demote: Bool) -> List<&2, U32>:
  Enc.emit.head.of(Enc.sel(enc_find(nm)), nm, reg, rm, idx, rm_sz, reg_sz, vvvv, has_disp,
    no_demote, U32.shrn(reg, 3n), U32.shrn(idx, 3n), U32.shrn(rm, 3n),
    Bool.pick(U32, U32.is_zero(reg_sz), rm_sz, reg_sz), Enc.demoted_opc(nm, rm, rm_sz, reg_sz, has_disp, no_demote),
    Enc.we_of(nm, rm_sz, reg_sz))


def mod_of(+nm: String, +rm: U32, +has_disp: Bool, +disp_val: U32, +disp_sz: U32) -> U32:
  # `mod` needs only the MASKED rm: the `rm == 0b101` test is about rbp/r13, and both
  # are inside three bits already.
  Enc.modrm_of(disp_val, disp_sz, has_disp, U32.and(rm, 7))


def Enc.emit.tail(+head: List<&2, U32>, +nm: String, +reg: U32, +rm: U32, +idx: U32,
    +rm_sz: U32, +has_disp: Bool, +disp_val: U32, +disp_sz: U32, +imm_kind: U32, +imm_n: Nat,
    +imm: U32) -> List<&2, U32>:
  Enc.emit.tail.of(head, nm, reg, rm, idx, rm_sz, has_disp, disp_val, disp_sz, imm_kind, imm_n,
    imm, mod_of(nm, rm, has_disp, disp_val, disp_sz))


def Enc.emit(+nm: String, +reg: U32, +rm: U32, +idx: U32, +rm_sz: U32, +reg_sz: U32, +vvvv: U32, +has_disp: Bool, +disp_val: U32, +disp_sz: U32, +imm_kind: U32, +imm_n: U32, +imm: U32, +no_demote: Bool) -> List<&2, U32>:
  # THE WHOLE ENCODER, in the order x86.py emits it: VEX OR PREFIX+REX, the OPCODE,
  # MODRM, SIB, DISPLACEMENT, IMMEDIATE.
  #
  # The eleven numbers are what `_encode`'s closure captures; `nm` supplies the rest
  # from the table. `sel != 0` IS the `if sel:` fork -- a VEX-encoded opcode never
  # emits a REX and a legacy one never emits a VEX, so the two arms are disjoint and
  # no byte is emitted twice.
  Enc.emit.tail(Enc.emit.head(nm, reg, rm, idx, rm_sz, reg_sz, vvvv, has_disp, no_demote),
    nm, reg, rm, idx, rm_sz, has_disp, disp_val, disp_sz, imm_kind, imm_n, imm)

def Enc.tail_bytes(+mod: U32, +has_disp: Bool, +disp_val: U32, +disp_sz: U32) -> List<&2, U32>:
  Enc.tail_bytes.of(U32.is_eq(mod, 0), Enc.disp_bytes(disp_val, disp_sz))

# --- the eight direct-byte entries ---------------------------------------------

def Enc.sib_field(+has_disp: Bool, +mod: U32, +noidx: Bool, +idx3: U32, +rm3: U32, +rm_sz: U32) -> List<&2, U32>:
  Enc.sib_field.of(noidx, idx3, rm3, rm_sz, Enc.want_sib(noidx, mod))


def Enc.sib_field.of(+noidx: Bool, +idx3: U32, +rm3: U32, +rm_sz: U32, +want: Bool) -> List<&2, U32>:
  # `_rm == 0b100 and mod != 0b11` is the SIB condition: a memory operand whose rm
  # field came out as 0b100. It is NOT "there is a memory operand" -- mod=00 with no
  # index is `[rsp]`, and mod=00 with an index is `[rsp+rcx*4]`, and BOTH need the
  # SIB byte, while a register operand never does.
  match want:
    case True{}: [Enc.sib_byte(Enc.sib_scale.of(rm_sz, Bool.not(noidx)), idx3, rm3)]
    case _: Nil{}


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

def Enc.emit.tail.of(+head: List<&2, U32>, +nm: String, +reg: U32, +rm: U32, +idx: U32,
    +rm_sz: U32, +has_disp: Bool, +disp_val: U32, +disp_sz: U32, +imm_kind: U32, +imm_n: Nat,
    +imm: U32, +mod: U32) -> List<&2, U32>:
  # MODRM, then SIB, then DISPLACEMENT, then IMMEDIATE. `reg` and `rm` are MASKED to
  # three bits HERE (x86.py:567) and the SIB carries the FULL three, which is why the
  # same two numbers mean different things in the two bytes -- and why `rm` is
  # computed once and read by both.
  Enc.cat3(Enc.cat(head, Enc.opcode_bytes(Enc.opc(enc_find(nm)))),
    [Enc.modrm_byte(mod, U32.and(reg, 7), Enc.rm3(U32.and(idx, 7), U32.shrn(idx, 3n), U32.and(rm, 7)))],
    Enc.cat(Enc.sib_field(has_disp, mod, Enc.no_index(U32.and(idx, 7), U32.shrn(idx, 3n)),
      U32.and(idx, 7), U32.and(rm, 7), rm_sz),
      Enc.cat(Enc.tail_bytes(mod, has_disp, disp_val, disp_sz), Enc.imm_bytes(imm_kind, imm_n, imm))))


def Enc.tail_bytes.of(+nod: Bool, +dsp: List<&2, U32>) -> List<&2, U32>:
  match nod:
    case True{}: dsp
    case False{}: Nil{}


def Enc.direct.of(+nm: String, +reg: U32, +imm: U32) -> List<&2, U32>:
  # the six jumps, `JMP` and `RET`. `int(0).to_bytes(4)` is FOUR ZERO BYTES that
  # `render` later overwrites with a signed little-endian offset (x86.py:767), so
  # the placeholder is not a guess -- it is the value the patcher looks for.
  match nm:
    case "RET": [195]
    case _: Enc.direct.go(nm, reg, imm, Enc.direct_count(nm))

def Enc.direct.go(+nm: String, +reg: U32, +imm: U32, +n: U32) -> List<&2, U32>:
  Enc.direct.fin(n, [Enc.direct_op1(nm), Enc.direct_op2(nm)], reg, imm)

def Enc.direct.fin(+n: U32, head: List<&2, U32>, +reg: U32, +imm: U32) -> List<&2, U32>:
  match n:
    case 0: head
    case _: List.append(&2, U32, Enc.direct.fin(U32.sub(n, 1), head, reg, imm), [U32.and(imm, 255)])

# `MOVABS` (x86.py:627) -- REX.W + B8+r, then the register index, then the EIGHT
# little-endian bytes of the value. The only entry whose second byte is the opcode
# plus a register number rather than a fixed constant.
def Enc.movabs(+reg: U32, +imm: U32) -> List<&2, U32>:
  List.append(&2, U32, List.append(&2, U32, [72, U32.add(184, U32.and(reg, 7))],
    Enc.imm_int(8n, 8, imm)), [U32.shrn(U32.shrn(reg, 3n), 0n)])

# ===========================================================================
# STAGE 5b -- `render`'s JUMP PATCHING. x86.py:755-767.
#
# `for u in uops: ... binary.extend(l); if jump: jumps[u] = len(binary)` and then
# `binary[t-4:t] = (targets[u.tag] - t).to_bytes(4, 'little', signed=True)`.
#
# THE ARITHMETIC IS THE PORT. The DICTS ARE NOT: `targets` is keyed by a UOp's `tag`
# (a Python object) and `jumps` by the UOp itself, and the substrate's `Map` is
# keyed by a `Nat`/`String`. The port therefore takes the LABEL POSITIONS AND THE
# JUMP POSITIONS as LISTS, in the order `render` records them, which is the whole of
# what the dicts hold. `TODO(p3) x86.py:752`.
# ===========================================================================
def Render.target(+pos: U32) -> U32: pos

def Render.delta(+target: U32, +t: U32) -> U32:
  # `(targets[u.tag] - t)` as a SIGNED little-endian 32-bit word, wrapped. `U32.sub`
  # wraps the same way CPython's `signed=True` does, and `Hex.byte` of its four bytes
  # is the whole four-byte patch -- which is why the gate's `render.*` rows are HEX
  # and not decimal.
  U32.sub(target, t)

def Render.le4(+v: U32) -> String:
  String.concat([Hex.byte(v), Hex.byte(U32.shrn(v, 8n)), Hex.byte(U32.shrn(v, 16n)),
    Hex.byte(U32.shrn(v, 24n))])



