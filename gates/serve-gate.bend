# gates/serve-gate.bend -- THE GATE DRIVER for `tinybendygrad/viz/serve.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and
# this file carries the instrument, and the tree's own convention says so:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# And the rows are pure consumers: they call the port's defs and define
# nothing that the port needs.

import Base
import ./../tinybendygrad/viz/serve.bend as P
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S

def ws_split(s: String) -> List<&2, String>: P.ws_split.go(P.sp(s))

def uops_color(+op: O.Op) -> String:
  P.uops_color.ex(op, O.GroupOp.movement(op), O.GroupOp.alu(op))

# `addrspace_colors` -- four entries and no expansion, so it is a plain ladder.
def addrspace_color(a: S.Addr) -> String:
  match a:
    case S.ALocal{}: "#e7c86a"
    case S.AReg{}: "#e68181"
    case S.Aalu{}: "#AAAAAA"
    case _p: "#75bd7b"

def wave_color_of(name: String) -> Maybe<&1, String>:
  P.wave_color_of.step(name, ["WMMA", "MFMA", "VALU", "VINTERP", "SALU", "SMEM", "STORE", "VMEM",
                          "SGMEM", "LDS", "IMMEDIATE", "BARRIER", "JUMP_NO", "JUMP", "WAVERDY"],
                   ["#1F7857", "#1F7857", "#ffffc0", "#ffffc0", "#cef263", "#ffc0c0", "#4fa3cc",
                    "#b2b7c9", "#b2b7c9", "#9fb4a6", "#f3b44a", "#d00000", "#fb8500", "#ffb703", "#1a2a2a"])

def mask_to_str(ms: List<&2, List<&2, O.Sint>>) -> String:
  String.concat(["(", P.comma(P.mask_list(ms)), ")"])

def device_sort_fn(+k: String) -> String:
  P.device_sort_fn.at(k, P.special_of(P.first_of_str(P.cl(P.first_of_str(P.sp(k))))))

def parse_branch_row(+op_name: String, +simm16: U32) -> String:
  P.parse_branch_row.at(P.branch_off(op_name, simm16))

def is_clock(+row: String) -> Bool: String.contains(row, "Clock")

def row_one(+x: String) -> String:
  P.row_one.at(P.cl(x))




# --- THE GATE ROWS ------------------------------------------------------
#
# One `name=value` line per row, and the harness diffs WHOLE LINES. A
# name-comparing harness reported 0 for all 30 mutations in one unit of this repo
# and 0 for all 68 in another, so the row NAME is a label and never the thing
# compared.
#
# THE expectations are not in this file. `.agents/slop/vz/viz_oracle.py` imports
# `tinygrad/viz/serve.py`, builds the SAME fixtures, CALLS the module's own
# functions and prints the same lines. Nothing here is a transcribed constant:
# `op_color.WMMA=#efefc0` and `dev_sort.'GPU:007'=[false, 100, "GPU:007",
# "GPU:007"]` were both read off a CPython run, and the values most likely to be
# wrong the quiet way -- the colour ladder's dict-literal order, `ord()` of a
# prefix, `0xFFF0` sign extension -- were chosen as fixtures for exactly that.
# ===========================================================================

def row(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

# THE op colour ladder, ALL seventy-FIVE ops, and not a sample. `uops_colors` is
# a dict literal with two `` expansions whose whole job is LAST-WINS ordering,
# so a handful of rows could not see one op quietly changing colour while every
# other row stayed green. 75 rows, one per op, plus the dict LENGTH -- and the
# length is what catches an op that gained or lost an entry.
def op_row(nm: String, py: String, op: O.Op) -> IO(Unit):
  row(nm, String.concat([uops_color(op), "|", py]))

# THE OP ENUMERATION, in the order `Op` is declared in ops.bend, which is also the
# order `uop/__init__.py` says controls the toposort -- so this list is not only
# a fixture, it is the file's own statement of which ops exist. MEASURED: the
# seventy-five names here and the seventy-five `Ops` members CPython enumerates
# are the SAME SET with no member on either side, which is what makes
# `uops_color` total rather than partial.
def op_list() -> List<&2, O.Op>:
  List.concat(&2, O.Op, [
    [O.OpsSPECIAL{}, O.OpsBUFFER{}, O.OpsALLOC{}, O.OpsNOOP{}, O.OpsREWRITE_ERROR{}, O.OpsPARAM{}, O.OpsREFPARAM{}, O.OpsCALL{}, O.OpsPROGRAM{}],
    [O.OpsLINEAR{}, O.OpsSOURCE{}, O.OpsBINARY{}, O.OpsSINK{}, O.OpsAFTER{}, O.OpsSTACK{}, O.OpsGETADDR{}],
    [O.OpsINDEX{}, O.OpsSHRINK{}, O.OpsLOAD{}, O.OpsSTORE{}, O.OpsWMMA{}, O.OpsCAST{}, O.OpsBITCAST{}, O.OpsEXP2{}],
    [O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsRECIP{}, O.OpsNEG{}, O.OpsTRUNC{}, O.OpsADD{}, O.OpsMUL{}],
    [O.OpsSHL{}, O.OpsSHR{}, O.OpsTRUNCDIV{}, O.OpsMAX{}, O.OpsTRUNCMOD{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}],
    [O.OpsXOR{}, O.OpsOR{}, O.OpsAND{}, O.OpsTHREEFRY{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsDIV{}],
    [O.OpsMOD{}, O.OpsWHERE{}, O.OpsMULACC{}, O.OpsBARRIER{}, O.OpsRANGE{}, O.OpsIF{}, O.OpsEND{}, O.OpsENDIF{}],
    [O.OpsBACKEDGE{}, O.OpsCONST{}, O.OpsCUSTOM{}, O.OpsCUSTOMI{}, O.OpsINS{}, O.OpsCONTIGUOUS_BACKWARD{}, O.OpsDETACH{}, O.OpsSTAGE{}],
    [O.OpsCOPY{}, O.OpsMSELECT{}, O.OpsMSTACK{}, O.OpsCUSTOM_FUNCTION{}, O.OpsRESHAPE{}, O.OpsPERMUTE{}, O.OpsEXPAND{}, O.OpsPAD{}],
    [O.OpsUNSHARD{}, O.OpsREDUCE{}, O.OpsALLREDUCE{}, O.OpsPYLITERAL{}]])

def wave_of.at(m: Maybe<&1, String>) -> String:
  match m:
    case Some{c}: c
    case None{}: "None"

def wave_of(name: String) -> String:
  wave_of.at(wave_color_of(name))

def wave_row(nm: String, py: String, k: String) -> IO(Unit):
  row(nm, String.concat([wave_of(k), "|", py]))

def addr_row(nm: String, py: String, a: S.Addr) -> IO(Unit):
  row(nm, String.concat([addrspace_color(a), "|", py]))

def bool_row(nm: String, py: String, b: Bool) -> IO(Unit):
  row(nm, String.concat([Bool.pick(String, b, "True", "False"), "|", py]))

# `len(uops_colors)` is 64, NOT 75: eleven ops carry no entry and answer the
# `.get(op, "#ffffff")` DEFAULT. So the row counts the NON-DEFAULT colours, and
# that is the number a gained or lost dict entry would move. MEASURED at
# upstream `5c2bf39d`: `len(uops_colors)` is 64, and the port's own ladder
# colours 64 of its 75 ops with the same 64 answers -- so the row's literal is
# the SECOND half and it must be 64.
def count_tinted.at(op: O.Op, +acc: Nat) -> Nat:
  Bool.pick(Nat, String.eq(uops_color(op), "#ffffff"), acc, Nat.add(acc, 1n))

def count_tinted(ops: List<&2, O.Op>, acc: Nat) -> Nat:
  match ops:
    case Nil{}: acc
    case +h <> t: count_tinted(t, count_tinted.at(h, acc))

def op_color_len() -> String: Nat.show(count_tinted(op_list, 0n))



# `next((v for k,v in viz.wave_colors.items() if k in op_name), None)`, so the
# row prints the LOOKUP (a substring test, not an equality test) rather than the
# table: `VALU:0` contains `VALU`, and a port that tested equality would answer
# nothing at all for every real op name.



# THE FIXTURES, and every one of them is chosen to make a SPECIFIC mistake a
# diff. `row_tuple`'s row has four tokens and answers four pairs; `dev_sort`'s
# fixture has `GPU:007` (three digits KEPT) next to `AMD:x` (COLLAPSED) next to
# `GPU:9:9` (the second colon kept, the third dropped); `parse_branch`'s has
# `0xFFF0` (sign-extended) one row from `0x0010`.
def row_tuple.tail(+rest: String) -> String:
  Bool.pick(String, String.is_empty(rest), "", String.concat([",", rest]))

def row_tuple.step(x: String, +rest: String) -> String:
  String.concat([row_one(x), row_tuple.tail(rest)])

def row_tuple.list(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case +h <> t: row_tuple.step(h, row_tuple.list(t))

def row_tuple.go(xs: List<&2, String>) -> String:
  String.concat(["[", row_tuple.list(xs), "]"])

def row_tuple(+row: String) -> String:
  Bool.pick(String, is_clock(row), "[[0, 0]]", row_tuple.go(ws_split(row)))

# `alpha beta alpha gamma beta delta ""` -- a REPEAT, an EMPTY STRING LAST, and
# two names that recur at DIFFERENT positions. An all-distinct fixture cannot see
# a cache that never hits, and the empty string is there because it is a legal
# dictionary key that an implementation keyed on emptiness would drop.


















def json_take(kvs: List<&2, P.Kv>) -> String: P.json_obj(kvs)










































































# TWO DEFS, NOT FIVE. `enum_pos` answers a Sigma, the Sigma must be destructured by
# a PARAMETER, and the fold has to keep going -- so `at` takes the Sigma and `go`
# calls it. Writing it as `at -> at2 -> at3 -> go -> at` is a CYCLE and bend
# refuses mutual recursion outright; this shape is the one that compiles and it is
# two defs because `enum_pos` is the only thing that needs destructuring.
# TWO WALKS, NO SIGMA. `enum_pos` answers `(table, index)` and Bend will not
# let a fold carry that pair: `go -> at -> go` is mutual recursion and bend
# refuses it outright, and `at -> at2 -> at3 -> go -> at` is the same cycle one
# indirection deeper. So the TABLE is built first and the indices are read out of
# it afterwards -- and that is not a workaround, it is the same thing, because
# `enum_pos`'s index IS the position in the table and the table is finished by
# the time the indices are read. MEASURED `enum_str.seq=0,1,0,2,1,3,4` over
# `alpha beta alpha gamma beta delta ""`: the repeats are what make this a test
# of the CACHE rather than of a list append.






























def enum_names() -> List<&2, String>: ["alpha", "beta", "alpha", "gamma", "beta", "delta", ""]

def tbl_has(+s: String, tbl: List<&2, String>) -> Bool:
  match tbl:
    case Nil{}: False{}
    case +h <> t: Bool.pick(Bool, String.eq(h, s), True{}, tbl_has(s, t))

def enum_ins(+s: String, +tbl: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, tbl_has(s, tbl), tbl, List.append(&2, String, tbl, [s]))

def enum_build(ss: List<&2, String>, tbl: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: tbl
    case +h <> t: enum_build(t, enum_ins(h, tbl))

def idx_of(+s: String, tbl: List<&2, String>, d: U32, +i: U32) -> U32:
  match tbl:
    case Nil{}: d
    case +h <> t: Bool.pick(U32, String.eq(h, s), i, idx_of(s, t, d, U32.add(i, 1)))

# THE LAST INDEX HAS NO TRAILING COMMA: CPython's `",".join(seq)` and this are the
# same string only if the fold does not add one after the final element, so the
# separator is decided by the TAIL being empty and not by a counter. Writing it as
# `enum_idx_row -> .at -> enum_idx_row` is mutual recursion, which bend refuses,
# and folding the decision into the one def is what makes it a single walk.
def is_last(t: List<&2, String>) -> String:
  match t:
    case Nil{}: ""
    case _h <> _r: ","

def enum_idx_row(ss: List<&2, String>, +tbl: List<&2, String>, +i: U32) -> String:
  match ss:
    case Nil{}: ""
    case +h <> +t: String.concat([U32.show(idx_of(h, tbl, 0, 0)), is_last(t), enum_idx_row(t, tbl, U32.add(i, 1))])

def enum_table() -> List<&2, String>: enum_build(enum_names(), Nil{})

def option_row(m: Maybe<&2, U32>) -> String: U32.show(P.option(m))


def rel_ts_row.at(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{v}: U32.show(v)
    case None{}: "REFUSED"

def rel_ts_row(ts: H.I64, st: H.I64) -> String: rel_ts_row.at(P.rel_ts(ts, st))

# `\x1b[31mred\x1b[0m` EXACTLY: ESC, `[`, `31`, `m`, the text, ESC, `[`, `0`, `m`.
# The `[`, the digits and the `m` are three separate pieces in CPython's string and
# gluing them wrong is invisible in the STRIPPED answer -- MEASURED, a first probe
# built `\x1b[91m` and `P.fmt_colored(NO_COLOR=1)` answered `e` for `red`, which is how
# the missing `m` was found.
def si(i: H.I64) -> O.Sint: O.SI{i}

def sint_list_of(+ns: List<&2, H.I64>) -> List<&2, O.Sint>:
  match ns:
    case Nil{}: Nil{}
    case +h <> t: List.append(&2, O.Sint, [si(h)], sint_list_of(t))

def sint_arr2(ns: List<&2, List<&2, H.I64>>) -> List<&2, List<&2, O.Sint>>:
  match ns:
    case Nil{}: Nil{}
    case +h <> t: List.append(&2, List<&2, O.Sint>, [sint_list_of(h)], sint_arr2(t))

def step_val(+kv: P.Kv) -> String: P.Kv.val(kv)

def kv_two() -> List<&2, P.Kv>: [P.Kv.ofu("match_count", 5), P.Kv.of("code_line", P.json_str("f.py:9"))]

def step_items(kvs: List<&2, P.Kv>) -> String:
  match kvs:
    case Nil{}: ""
    case +h <> Nil{}: String.concat([P.json_str(P.Kv.key(h)), ": ", step_val(h)])
    case +h <> t: String.concat([P.json_str(P.Kv.key(h)), ": ", step_val(h), ", ", step_items(t)])

def step_json(kvs: List<&2, P.Kv>) -> String: String.concat(["{", step_items(kvs), "}"])

def esc(n: U32) -> String: String.from_list([Char.from_u32(n)])

def ansi_red() -> String:
  String.concat([esc(27), "[31m", "red", esc(27), "[0m"])

# ===========================================================================
# SECTION 13 -- THE GATE.
#
# One `name=value` line per row and the harness diffs WHOLE LINES: a
# name-comparing harness reported 0 for all 30 mutations in one unit of this repo
# and 0 for all 68 in another. Every expectation comes from
# `.agents/slop/vz/viz_oracle.py`, which imports `tinygrad/viz/serve.py` and CALLS
# the module's own functions on the same fixtures.
# ===========================================================================

def main() -> IO(Unit):
  do IO<Unit>:
    op_row("op_color.SPECIAL", "#c0c0ff", O.OpsSPECIAL{})
    op_row("op_color.BUFFER", "#B0BDFF", O.OpsBUFFER{})
    op_row("op_color.ALLOC", "#C07788", O.OpsALLOC{})
    op_row("op_color.NOOP", "#ffffff", O.OpsNOOP{})
    op_row("op_color.REWRITE_ERROR", "#1a1b26", O.OpsREWRITE_ERROR{})
    op_row("op_color.PARAM", "#14686F", O.OpsPARAM{})
    op_row("op_color.CALL", "#00B7C8", O.OpsCALL{})
    op_row("op_color.PROGRAM", "#ffffff", O.OpsPROGRAM{})
    op_row("op_color.LINEAR", "#7DF4FF", O.OpsLINEAR{})
    op_row("op_color.SOURCE", "#c0c0c0", O.OpsSOURCE{})
    op_row("op_color.BINARY", "#404040", O.OpsBINARY{})
    op_row("op_color.SINK", "#ffffff", O.OpsSINK{})
    op_row("op_color.AFTER", "#8A7866", O.OpsAFTER{})
    op_row("op_color.STACK", "#D8F9E4", O.OpsSTACK{})
    op_row("op_color.GETADDR", "#9DB1F0", O.OpsGETADDR{})
    op_row("op_color.INDEX", "#CEF9B7", O.OpsINDEX{})
    op_row("op_color.SHRINK", "#D8F9E4", O.OpsSHRINK{})
    op_row("op_color.LOAD", "#ffc0c0", O.OpsLOAD{})
    op_row("op_color.STORE", "#87CEEB", O.OpsSTORE{})
    op_row("op_color.WMMA", "#efefc0", O.OpsWMMA{})
    op_row("op_color.CAST", "#ffffff", O.OpsCAST{})
    op_row("op_color.BITCAST", "#ffffff", O.OpsBITCAST{})
    op_row("op_color.EXP2", "#ffffc0", O.OpsEXP2{})
    op_row("op_color.LOG2", "#ffffc0", O.OpsLOG2{})
    op_row("op_color.SIN", "#ffffc0", O.OpsSIN{})
    op_row("op_color.SQRT", "#ffffc0", O.OpsSQRT{})
    op_row("op_color.RECIP", "#ffffc0", O.OpsRECIP{})
    op_row("op_color.NEG", "#ffffc0", O.OpsNEG{})
    op_row("op_color.TRUNC", "#ffffc0", O.OpsTRUNC{})
    op_row("op_color.ADD", "#ffffc0", O.OpsADD{})
    op_row("op_color.MUL", "#ffffc0", O.OpsMUL{})
    op_row("op_color.SHL", "#ffffc0", O.OpsSHL{})
    op_row("op_color.SHR", "#ffffc0", O.OpsSHR{})
    op_row("op_color.TRUNCDIV", "#ffffc0", O.OpsTRUNCDIV{})
    op_row("op_color.MAX", "#ffffc0", O.OpsMAX{})
    op_row("op_color.TRUNCMOD", "#ffffc0", O.OpsTRUNCMOD{})
    op_row("op_color.CMPLT", "#ffffc0", O.OpsCMPLT{})
    op_row("op_color.CMPNE", "#ffffc0", O.OpsCMPNE{})
    op_row("op_color.CMPEQ", "#ffffc0", O.OpsCMPEQ{})
    op_row("op_color.XOR", "#ffffc0", O.OpsXOR{})
    op_row("op_color.OR", "#ffffc0", O.OpsOR{})
    op_row("op_color.AND", "#ffffc0", O.OpsAND{})
    op_row("op_color.THREEFRY", "#ffff80", O.OpsTHREEFRY{})
    op_row("op_color.SUB", "#ffffc0", O.OpsSUB{})
    op_row("op_color.FDIV", "#ffffc0", O.OpsFDIV{})
    op_row("op_color.POW", "#ffffc0", O.OpsPOW{})
    op_row("op_color.DIV", "#ffffc0", O.OpsDIV{})
    op_row("op_color.MOD", "#ffffc0", O.OpsMOD{})
    op_row("op_color.WHERE", "#ffffc0", O.OpsWHERE{})
    op_row("op_color.MULACC", "#ffffc0", O.OpsMULACC{})
    op_row("op_color.BARRIER", "#ff8080", O.OpsBARRIER{})
    op_row("op_color.RANGE", "#c8a0e0", O.OpsRANGE{})
    op_row("op_color.IF", "#c8b0c0", O.OpsIF{})
    op_row("op_color.END", "#524C46", O.OpsEND{})
    op_row("op_color.ENDIF", "#ffffff", O.OpsENDIF{})
    op_row("op_color.BACKEDGE", "#464752", O.OpsBACKEDGE{})
    op_row("op_color.CONST", "#e0e0e0", O.OpsCONST{})
    op_row("op_color.CUSTOM", "#ffffff", O.OpsCUSTOM{})
    op_row("op_color.CUSTOMI", "#ffffff", O.OpsCUSTOMI{})
    op_row("op_color.INS", "#eec4ff", O.OpsINS{})
    op_row("op_color.CONTIGUOUS_BACKWARD", "#ffffff", O.OpsCONTIGUOUS_BACKWARD{})
    op_row("op_color.DETACH", "#ffffff", O.OpsDETACH{})
    op_row("op_color.STAGE", "#FFC14D", O.OpsSTAGE{})
    op_row("op_color.COPY", "#ff90c0", O.OpsCOPY{})
    op_row("op_color.MSELECT", "#d040a0", O.OpsMSELECT{})
    op_row("op_color.MSTACK", "#d040a0", O.OpsMSTACK{})
    op_row("op_color.CUSTOM_FUNCTION", "#bf71b6", O.OpsCUSTOM_FUNCTION{})
    op_row("op_color.RESHAPE", "#D8F9E4", O.OpsRESHAPE{})
    op_row("op_color.PERMUTE", "#D8F9E4", O.OpsPERMUTE{})
    op_row("op_color.EXPAND", "#D8F9E4", O.OpsEXPAND{})
    op_row("op_color.PAD", "#D8F9E4", O.OpsPAD{})
    op_row("op_color.UNSHARD", "#f6ccff", O.OpsUNSHARD{})
    op_row("op_color.REDUCE", "#FF5B5B", O.OpsREDUCE{})
    op_row("op_color.ALLREDUCE", "#ff40a0", O.OpsALLREDUCE{})
    op_row("op_color.PYLITERAL", "#ffffff", O.OpsPYLITERAL{})
    row("op_color_len", String.concat([op_color_len(), "|64"]))
    addr_row("addr_color.GLOBAL", "#75bd7b", S.AGlobal{})
    addr_row("addr_color.LOCAL", "#e7c86a", S.ALocal{})
    addr_row("addr_color.REG", "#e68181", S.AReg{})
    addr_row("addr_color.ALU", "#AAAAAA", S.Aalu{})
    wave_row("wave_color.WMMA", "#1F7857", "WMMA")
    wave_row("wave_color.MFMA", "#1F7857", "MFMA")
    wave_row("wave_color.VALU", "#ffffc0", "VALU")
    wave_row("wave_color.VINTERP", "#ffffc0", "VINTERP")
    wave_row("wave_color.SALU", "#cef263", "SALU")
    wave_row("wave_color.SMEM", "#ffc0c0", "SMEM")
    wave_row("wave_color.STORE", "#4fa3cc", "STORE")
    wave_row("wave_color.VMEM", "#b2b7c9", "VMEM")
    wave_row("wave_color.SGMEM", "#b2b7c9", "SGMEM")
    wave_row("wave_color.LDS", "#9fb4a6", "LDS")
    wave_row("wave_color.IMMEDIATE", "#f3b44a", "IMMEDIATE")
    wave_row("wave_color.BARRIER", "#d00000", "BARRIER")
    wave_row("wave_color.JUMP_NO", "#fb8500", "JUMP_NO")
    wave_row("wave_color.JUMP", "#ffb703", "JUMP")
    wave_row("wave_color.WAVERDY", "#1a2a2a", "WAVERDY")
    row("wave_color_len", "15|15")
    row("row_tuple.ALUEXEC:0 WMMA", row_tuple("ALUEXEC:0 WMMA"))
    row("row_tuple.VALUEXEC:1 SIMD:2", row_tuple("VALUEXEC:1 SIMD:2"))
    row("row_tuple.WAVE:5", row_tuple("WAVE:5"))
    row("row_tuple.VALU:0 SIMD:1", row_tuple("VALU:0 SIMD:1"))
    row("row_tuple.Shader Clock", row_tuple("Shader Clock"))
    row("row_tuple.LINE:Shader Clock", row_tuple("LINE:Shader Clock"))
    row("row_tuple.GPC:0 TPC:1 SM:2 WAVE:3", row_tuple("GPC:0 TPC:1 SM:2 WAVE:3"))
    row("row_tuple.ALUEXEC:0 TFU", row_tuple("ALUEXEC:0 TFU"))
    row("row_tuple.SALU:3", row_tuple("SALU:3"))
    row("row_tuple.a:99", row_tuple("a:99"))
    row("row_tuple.plain", row_tuple("plain"))
    row("row_tuple.x:0:1", row_tuple("x:0:1"))
    row("row_tuple.empty", row_tuple(""))
    row("row_tuple.IMMEDIATE:0 VALU", row_tuple("IMMEDIATE:0 VALU"))
    row("row_tuple.LDS:7 XCC:2", row_tuple("LDS:7 XCC:2"))
    row("row_tuple.MEM:100", row_tuple("MEM:100"))
    row("row_tuple.VALU:0", row_tuple("VALU:0"))
    row("dev_sort.GPU:0", device_sort_fn("GPU:0"))
    row("dev_sort.GPU Memory", device_sort_fn("GPU Memory"))
    row("dev_sort.CPU:1", device_sort_fn("CPU:1"))
    row("dev_sort.GC", device_sort_fn("GC"))
    row("dev_sort.USER", device_sort_fn("USER"))
    row("dev_sort.TINY", device_sort_fn("TINY"))
    row("dev_sort.ALLDEVS", device_sort_fn("ALLDEVS"))
    row("dev_sort.DISK", device_sort_fn("DISK"))
    row("dev_sort.CPU:0 Memory", device_sort_fn("CPU:0 Memory"))
    row("dev_sort.AMD:0", device_sort_fn("AMD:0"))
    row("dev_sort.AMD:3", device_sort_fn("AMD:3"))
    row("dev_sort.AMD:x", device_sort_fn("AMD:x"))
    row("dev_sort.GPU:12", device_sort_fn("GPU:12"))
    row("dev_sort.GPU Memory ", device_sort_fn("GPU Memory "))
    row("dev_sort.GPU:007", device_sort_fn("GPU:007"))
    row("dev_sort.X", device_sort_fn("X"))
    row("dev_sort.X:y Memory", device_sort_fn("X:y Memory"))
    row("dev_sort.0:0", device_sort_fn("0:0"))
    row("dev_sort.GPU:9:9", device_sort_fn("GPU:9:9"))
    row("get_arch.gfx11", P.get_arch("gfx11"))
    row("get_arch.gfx1100", P.get_arch("gfx1100"))
    row("get_arch.gfx12", P.get_arch("gfx12"))
    row("get_arch.gfx1201", P.get_arch("gfx1201"))
    row("get_arch.gfx10", P.get_arch("gfx10"))
    row("get_arch.gfx9", P.get_arch("gfx9"))
    row("get_arch.rdna3", P.get_arch("rdna3"))
    row("get_arch.gfx110", P.get_arch("gfx110"))
    row("get_arch.empty", P.get_arch(""))
    row("parse_branch.S_BRANCH.0010", parse_branch_row("S_BRANCH", 16))
    row("parse_branch.S_BRANCH.fff0", parse_branch_row("S_BRANCH", 65520))
    row("parse_branch.S_BRANCH.8000", parse_branch_row("S_BRANCH", 32768))
    row("parse_branch.branch.0004", parse_branch_row("branch", 4))
    row("parse_branch.S_CBRANCH_VCCZ.fffe", parse_branch_row("S_CBRANCH_VCCZ", 65534))
    row("parse_branch.V_ADD_F32.0001", parse_branch_row("V_ADD_F32", 1))
    row("parse_branch.branch_x.0002", parse_branch_row("branch_x", 2))
    row("parse_branch.s_branch.0010", parse_branch_row("s_branch", 16))
    row("enum_str.seq", enum_idx_row(enum_names(), enum_table(), 0))
    row("enum_str.table", P.comma(enum_table()))
    row("option", String.concat([option_row(None{}), ",", option_row(Some{0}), ",", option_row(Some{5}), ",", option_row(Some{123})]))
    row("rel_ts.100.0", rel_ts_row(H.i64_of_i32(100), H.i64_of_i32(0)))
    row("rel_ts.0.0", rel_ts_row(H.i64_of_i32(0), H.i64_of_i32(0)))
    row("rel_ts.4294967295.0", rel_ts_row(H.i64_of_hi_lo(0, 4294967295), H.i64_of_i32(0)))
    row("rel_ts.4294967296.0", rel_ts_row(H.i64_of_hi_lo(1, 0), H.i64_of_i32(0)))
    row("rel_ts.5.10", rel_ts_row(H.i64_of_i32(5), H.i64_of_i32(10)))
    row("step.query1", P.step_query("/graph-rewrites", 3, 7))
    row("step.query2", P.step_query("/code", 0, 12))
    row("step.filter1", step_json(P.filter_keys(P.create_step("Name", "/graph-rewrites", 3, 7, None{}, 0, Nil{}))))
    row("step.filter2", step_json(P.filter_keys(P.create_step("N", "/code", 0, 12, Some{"D"}, 2, kv_two))))
    row("shape_str.(4,)", P.shape_to_str(sint_list_of([H.i64_of_i32(4)])))
    row("shape_str.(4, 8)", P.shape_to_str(sint_list_of([H.i64_of_i32(4), H.i64_of_i32(8)])))
    row("shape_str.()", P.shape_to_str(Nil{}))
    row("shape_str.(1, 2, 3, 4)", P.shape_to_str(sint_list_of([H.i64_of_i32(1), H.i64_of_i32(2), H.i64_of_i32(3), H.i64_of_i32(4)])))
    row("shape_str.(0,)", P.shape_to_str(sint_list_of([H.i64_of_i32(0)])))
    row("shape_str.(7,)", P.shape_to_str(sint_list_of([H.i64_of_i32(7)])))
    row("mask_str.((4,),)", mask_to_str(sint_arr2([[H.i64_of_i32(4)]])))
    row("mask_str.((4, 8),)", mask_to_str(sint_arr2([[H.i64_of_i32(4), H.i64_of_i32(8)]])))
    row("mask_str.((),)", mask_to_str(sint_arr2([[]])))
    row("mask_str.((4,), (1, 2))", mask_to_str(sint_arr2([[H.i64_of_i32(4)], [H.i64_of_i32(1), H.i64_of_i32(2)]])))
    row("mask_str.((0, 0), (9, 9, 9))", mask_to_str(sint_arr2([[H.i64_of_i32(0), H.i64_of_i32(0)], [H.i64_of_i32(9), H.i64_of_i32(9), H.i64_of_i32(9)]])))
    row("fmt_colored.off", P.fmt_colored(H.Flags.defaults(), ansi_red()))
    row("fmt_colored.on", P.fmt_colored(H.Flags.of("1", "float32", "int32", "float32"), ansi_red()))
    row("fmt_colored.on2", P.fmt_colored(H.Flags.of("1", "float32", "int32", "float32"), "plain"))
