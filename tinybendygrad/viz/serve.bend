# tinybendygrad/viz/serve.bend -- port of tinygrad/viz/serve.py
#
# ===========================================================================
# WHAT THIS FILE IS: viz's LOGIC, without viz's SERVER.
#
# `serve.py` is 771 lines and 18 of them mention http/socket/handler/do_GET/
# send_header. The other 753 are a profiler, a graph labeler and a binary
# encoder, and none of it needs a socket. That is the shape of this port: the
# logic is here and it is gated; the server is named, and named only.
#
# THE HTML/JS PAYLOAD -- WHERE IT ACTUALLY LIVES, MEASURED.
#
# `serve.py` contains NO HTML and NO JavaScript: no `<script>`, no `<div`, no
# `onclick`. `do_GET` opens the payload BY PATH and writes it to a socket.
#
#   serve.py:707  open(os.path.join(os.path.dirname(__file__), "index.html"))
#   serve.py:710  open(os.path.join(os.path.dirname(__file__), self.path))
#
#   tinygrad/viz/index.html            451 lines
#   tinygrad/viz/js/index.js         1,202 lines
#   tinygrad/viz/js/worker.js          122 lines
#   tinygrad/viz/assets/...          1,883 lines of vendored CDN blobs
#                                     (highlight.min.js alone is 1,231)
#
# So the payload is not "transcribed" or "declared" -- it is ALREADY A SEAM
# upstream. There is nothing in `serve.py` to port for it, and 1,775 lines of
# hand-written browser code plus 1,883 lines of minified vendor, in a language
# whose only consumer is a browser, would be strictly worse than the two
# `open()` calls that already name it. `Handler.do_GET` below keeps the routing
# ladder that decides WHICH file, because that ladder IS logic and it is the
# part a reviewer can check.
#
# THE SEAMS. Same shape as `dtype.bend`'s 14 C calls and `compiler_*.bend`'s
# FFI calls: named, located, and NOT executed.
#
#   serve.py:16-20   TCPServerWithReuse      socketserver.TCPServer
#   serve.py:22-40   HTTPRequestHandler       http.server.BaseHTTPRequestHandler
#   serve.py:302-307 soft_err                 contextmanager + traceback
#   serve.py:379-464 sqtt_timeline            a FUNCTION-LOCAL `from
#                                              tinygrad.renderer.amd.sqtt import
#                                              ...` of 22 names, then `map_insts`
#                                              over the raw SQTT stream
#   serve.py:517-526 load_nv_counters         ProfilePMAEvent selected by
#                                              `type(e).__name__`, so the type is
#                                              in no import
#   serve.py:528-542 pma_timeline             `from extra.nv_pma.decode import`
#   serve.py:546-550 get_stdout                io.StringIO + redirect_stdout
#   serve.py:553-555 get_elf_section           `from ...support.elf import`
#   serve.py:559-571 amd_decode                `from ...autogen.amd.rdna3.ins import`
#   serve.py:579-586 is_acc_operand            `Reg` (renderer/amd/dsl.py) and
#                                              `OpType` (runtime/autogen/amd)
#   serve.py:589-645 amdgpu_cfg                Inst._fields, Inst.operands,
#                                              amdgpu_kd (autogen)
#   serve.py:730-736 reloader                 os.stat + os.execv
#   serve.py:741-743 load_pickle               pickle.load, under @Context(DEBUG=0)
#   serve.py:745-771 __main__                  argparse + socket + multiprocessing
#                                              + threading + signal
#
# TWO MORE SEAMS THAT ARE NOT SOCKETS, and both are measured facts about
# ANOTHER FILE rather than choices:
#
#   serve.py:78-96    load_rewrites    needs `RewriteTrace` (uop/ops.py:1735)
#   serve.py:177-208  _reconstruct,    needs `TrackedGraphRewrite`
#                     get_full_rewrite,  (uop/ops.py:1632)
#                     get_sink_at
#     `grep -rn 'TrackedGraphRewrite\|RewriteTrace' tinybendygrad` returns SEVEN
#     hits and every one is a comment or a `# TODO(p3)`: ops.bend has no def, no
#     type and no inventory row for either. `trace_num` -- the ENCODING
#     `_reconstruct` mirrors -- is `ops.bend:3519 # TODO(p3) ops.py:544`. So this
#     file ports the graph logic it CAN and names the four defs that wait on
#     ops.bend's trace, which is a P3 row, not a wall in this file.
#
#   serve.py:108,137 `srender` and `word_wrap`
#     `srender` is `ops.bend:3455 # TODO(p3) ops.py:76`. `word_wrap` has NO row
#     in helpers.bend at all. `shape_to_str` is PORTED over `sint` rendered as
#     its integer form, which is `srender`'s answer for every `sint` that is an
#     int -- and the gate's fixtures are exactly those.
#
# ===========================================================================
# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of one device call (pure; the gate checks it) OR records that call in the
# trace (the gate checks ORDER). There is no third kind. THIS FILE IS THE FIRST
# KIND ENTIRELY: no trace, no `@extern`, no `import "./x.c"`. viz emits no calls;
# it encodes bytes.
#
# ===========================================================================
# THE GATE, and its shape.
#
# viz answers are BYTES and STRINGS, so the gate compares them as text: one
# `name=value` per line, and the harness diffs whole lines (never row names --
# a name-comparing harness reported 0 for 30 mutations in one unit and 0 for all
# 68 in another). Every expectation is produced by CALLING CPython on
# `tinygrad/viz/serve.py`, never typed: `.agents/slop/vz/viz_oracle.py` imports
# the module and calls `row_tuple`, `device_sort_fn`, `timeline_layout`,
# `encode_mem_free`, `graph_layout` and `get_profile`, printing the same lines.
#
# THE FIXTURES ARE DELIBERATELY NON-UNIFORM. An all-equal fixture cannot detect
# order, and viz is nothing BUT ordered lists: the string table's insertion
# order, per-device event order, `toposort` order, `range` order. Every fixture
# below has at least three distinct values in every ordered position it can.
#
# ONE WALL IN THE ENCODER, MEASURED, and it is a Bend one.
# `struct.pack("<IIIIfI", ...)` writes a 32-bit IEEE-754 float. bend 2.0.34's
# base has NO `F32.to_bits`: `F32{data: Word(32n)}` and `U32{data: Word(32n)}`
# have the SAME representation, but `match u { case U32{data: w}: }` is a PARSE
# ERROR ("expected a term, observed ':'"), so the field is not matchable and the
# two cannot be converted between. Base defines exactly ten `F32.*` and none is
# a bit cast. So the float's four bytes are the ONE thing this port cannot
# produce, and `tl_row` SAYS SO IN THE ROW: five packable fields as hex, then
# `st_ns=<et-st>`, then the sixth, and the CPython oracle projects the same six
# out of the real 20 bytes IT packed. The integer the float is computed from is
# checked; the float's bit pattern is not, and nothing here pretends otherwise.
#
# TWO MORE NUMBERS, both stated so a reader can subtract them.
#   * TIMESTAMPS. Python's are `Decimal` and `rel_ts`/`flatten_events` do
#     `int(...)`, which truncates toward zero; every profile timestamp is a
#     positive integer microsecond count, so `H.I64` is that integer exactly.
#   * `dur`. Python's is `float(en-ts)`. It is carried as an `F32` for the pack
#     and as `H.I64` for the gate, and the two are related by nothing in this
#     file -- see the wall above.

import Base
import ./../uop/ops.bend as O
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S

# ===========================================================================
# SECTION 1 -- BYTES. `struct.pack`'s little-endian field writers.
#
# `List.append(&2, T, xs, ys)` is `xs ++ ys` (bend2-constraints INDEX row at
# line 1590: it does NOT preserve the order its arguments were WRITTEN in, so
# the accumulator is always the FIRST argument here). `<>` conses at the FRONT,
# which is why nothing packs with it: a nested `pack(pack(acc, a), b)` puts b
# BEFORE a. MEASURED: `pack_u32(pack_u32([], 1), 0)` answered
# `0000000001000000`, i.e. the second field landed first.
#
# The shift amounts are `8n`/`16n`/`24n` and NOT `1n`/`2n`/`3n`: `U32.shl` is a
# ONE-BIT shift and only `U32.shln` takes a width.
# ===========================================================================

def pack_u8(acc: List<&2, U32>, +v: U32) -> List<&2, U32>: List.append(&2, U32, acc, [U32.and(v, 255)])

def pack_u32(acc: List<&2, U32>, +v: U32) -> List<&2, U32>:
  List.append(&2, U32, acc, [U32.and(v, 255), U32.and(U32.shrn(v, 8n), 255), U32.and(U32.shrn(v, 16n), 255), U32.and(U32.shrn(v, 24n), 255)])

# `<Q` is eight bytes. `H.I64` is the only 64-bit type in the tree and it
# exposes its own halves, so this is `struct`'s 8-byte write in the same order:
# lo32 first, then hi32.
def pack_u64(acc: List<&2, U32>, +v: H.I64) -> List<&2, U32>: pack_u32(pack_u32(acc, H.lo32(v)), H.hi32(v))

# `bytes.hex()` in Python, this in Bend: two lowercase digits per byte, in stream
# order. A packer that emits one byte too many or too few is a LENGTH diff,
# which is why no row truncates.
def hexdig(n: Nat) -> String:
  match n:
    case 0n: "0"
    case 1n: "1"
    case 2n: "2"
    case 3n: "3"
    case 4n: "4"
    case 5n: "5"
    case 6n: "6"
    case 7n: "7"
    case 8n: "8"
    case 9n: "9"
    case 10n: "a"
    case 11n: "b"
    case 12n: "c"
    case 13n: "d"
    case 14n: "e"
    case _: "f"

def hexdig_of(v: U32) -> String: hexdig(U32.to_nat(v))

def hexbyte(+b: U32) -> String: String.concat([hexdig_of(U32.shrn(b, 4n)), hexdig_of(U32.and(b, 15))])

def hex_of(bs: List<&2, U32>) -> String:
  match bs:
    case Nil{}: ""
    case +b <> t: hexbyte(b) ++ hex_of(t)

# ===========================================================================
# SECTION 2 -- STRINGS. Everything viz emits is a string, so these are the
# workhorses. `String.concat` wants `List<&2, String>` and `String.split` answers
# `List<&1, String>`, which do not meet; `jcat` is not a convenience, it is the
# only bridge.
# ===========================================================================

def jcat(ss: List<&1, String>) -> String:
  match ss:
    case Nil{}: ""
    case h <> t: h ++ jcat(t)

# `",".join(...)`, in three places, and the separator is never a field.
def comma(ss: List<&2, String>) -> String:
  match ss:
    case Nil{}: ""
    case h <> Nil{}: h
    case h <> t: h ++ "," ++ comma(t)

def jcat2(ss: List<&2, String>) -> String:
  match ss:
    case Nil{}: ""
    case h <> t: h ++ jcat2(t)

def s1(s: String) -> List<&2, String>: [s]

# `String.split(s, sep)` on a separator that may be absent returns a one-element
# list, and viz relies on that in three places (`k.replace`, `row_tuple`,
# `graph_layout`'s `"LINE:"` test), so the wrapper is not redundant.
# `String.split` in base 2.0.34 takes a single `Char`, while Python's takes a
# string. Every separator viz uses is one character (" ", ":") except
# `row.split()`, which `ws_split` answers separately.
def splitc(s: String, c: Char) -> List<&2, String>: String.split(s, c)
def sp(s: String) -> List<&2, String>: String.split(s, Char.from_u32(32))
def cl(s: String) -> List<&2, String>: String.split(s, Char.from_u32(58))

# `str.split()` with no argument: every whitespace-separated run, empties dropped.
# `String.split` DOES emit an empty part for a doubled separator, so the drop is
# load-bearing -- `row_tuple` and `device_sort_fn` both index the result.
def ws_step(+h: String, +t: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(h), t, List.append(&2, String, [h], t))

def ws_split.go(cs: List<&2, String>) -> List<&2, String>:
  match cs:
    case Nil{}: Nil{}
    case h <> t: ws_step(String.trim(h), ws_split.go(t))

def ws_split(s: String) -> List<&2, String>: ws_split.go(sp(s))

# `int(x)` on a decimal string. STRING.TO_U32 DOES NOT EXIST in bend 2.0.34 --
# MEASURED, and `runtime/ops_cpu.bend:114` records the same wall for
# `int(parts[2])`. So this is a parse, and Python's `int()` raises on a
# non-digit while this answers `None`; every caller (`row_tuple`,
# `device_sort_fn`, `get_int`) reaches it either after a digit test or with a
# fixture that is digits, so the two arms cannot be told apart by a row and the
# refusal is stated rather than exercised.
# A `match` may not scrutinise a CALL, so the digit test is a `Bool.pick` and
# the run's accumulator is a RECORD: a `Data` record can carry a growing value
# beside a flag, and two `Bool`s cannot.
type P is Data:
  P{n: U32, ok: Bool}

def P.num(+p: P) -> U32:
  match p:
    case P{n, ok}: n

def P.live(+p: P) -> Bool:
  match p:
    case P{n, ok}: ok

def head_of(cs: List<&2, Char>) -> Char:
  match cs:
    case Nil{}: Char.from_u32(48)
    case w <> _r: w

def digit_val(h: Char) -> U32: U32.sub(Char.to_u32(h), 48)

# THE HEAD IS THE DIGIT. `cs` is the list the CHARACTER was taken from: a first
# probe passed the TAIL, and every multi-digit number came back with its leading
# digit dropped -- invisible on a one-digit fixture, which is why the
# `parse_branch` rows below are two and three digits.
def parse_step(isdig: Bool, +acc: P, h: Char) -> P:
  Bool.pick(P, isdig, P{U32.add(U32.mul(P.num(acc), 10), digit_val(h)), P.live(acc)}, P{P.num(acc), False{}})

def parse_go(cs: List<&2, Char>, +acc: P) -> P:
  match cs:
    case Nil{}: acc
    case +h <> t: parse_go(t, parse_step(Char.is_digit(h), acc, h))

def parse(s: String) -> P: parse_go(String.to_list(s), P{0, True{}})

# `case "":` followed by another String arm makes bend 2.0.34 believe String is
# already matched ("expected a constructor of String"), so EVERY emptiness test
# on a String here is `Bool.pick` and the empty arm is never a `match` arm.
def alldig(cs: List<&2, Char>, +ok: Bool) -> Bool:
  match cs:
    case Nil{}: ok
    case +h <> t: alldig(t, Bool.and(ok, Char.is_digit(h)))

def is_digits(+s: String) -> Bool: Bool.pick(Bool, String.is_empty(s), False{}, alldig(String.to_list(s), True{}))

# `ord(ss[0][0])` -- the CODEPOINT OF THE FIRST CHARACTER, not the string. That is
# why `row_tuple('GPC:0 ...')` is 71 and not `GPC`, and why a port that passed the
# whole prefix to a numeric parse would answer something else entirely. MEASURED:
# `row_tuple.'GPC:0 TPC:1 SM:2 WAVE:3'` is `[[71, 0], [84, 1], [83, 2], [87, 3]]`.
def ord1(cs: List<&2, Char>) -> U32:
  match cs:
    case Nil{}: 0
    case h <> _t: Char.to_u32(h)

def ord_of(s: String) -> U32: ord1(String.to_list(s))

# ===========================================================================
# SECTION 3 -- JSON. `json.dumps` appears three times in the encoder and
# `json.loads` once, and both shapes are known: a flat object whose values are an
# int, a float or a string, with PYTHON'S SPACING (`", "` between items, `": "`
# after the key) which is a byte difference, not a style one.
# ===========================================================================

type Kv is Data:
  Kv{k: String, v: String}

def Kv.key(+kv: Kv) -> String:
  match kv:
    case Kv{k, v}: k

def Kv.val(+kv: Kv) -> String:
  match kv:
    case Kv{k, v}: v

# A `match` scrutinises a PARAMETER or a FIELD, never a call, so the codepoint
# arrives as the parameter -- AND as a `Nat`, because a `U32` LITERAL PATTERN IS
# A PREFIX MATCH in bend 2.0.34 (`case 34n` on a `U32` expands into 64 arms and
# the compiler reports the whole ladder). `U32.to_nat` at the call site is the
# fix, and `hexdig` below is the same story.
def esc_char(c: Nat) -> String:
  match c:
    case 34n: "\\\""
    case 92n: "\\\\"
    case 10n: "\\n"
    case 9n: "\\t"
    case 13n: "\\r"
    case _: String.from_list([Char.from_u32(U32.from_nat(c))])

def json_esc(cs: List<&2, Char>) -> String:
  match cs:
    case Nil{}: ""
    case h <> t: esc_char(U32.to_nat(Char.to_u32(h))) ++ json_esc(t)

def json_str(s: String) -> String: String.concat(["\"", json_esc(String.to_list(s)), "\""])

# `json.dumps` of a dict is `{` + the items joined by `", "` + `}`, and the
# recursion is over the ITEMS, not over a braced object -- Python has one brace
# pair per dict, not one per item.
def json_rest(kvs: List<&2, Kv>) -> String:
  match kvs:
    case Nil{}: ""
    case +h <> Nil{}: String.concat([json_str(Kv.key(h)), ": ", Kv.val(h)])
    case h <> t: String.concat([json_str(Kv.key(h)), ": ", Kv.val(h), ", ", json_rest(t)])

def json_obj(+kvs: List<&2, Kv>) -> String:
  Bool.pick(String, List.is_empty(&2, Kv, kvs), "{}", String.concat(["{", json_rest(kvs), "}"]))

# ===========================================================================
# SECTION 4 -- THE COLOUR TABLES.
#
# `uops_colors` is a DICT LITERAL with two `**` expansions, and a Python dict
# literal is LAST-WINS. So the port is a ladder in the OPPOSITE order of the
# source: the step-5 explicit entries, then THREEFRY, then the ALU expansion,
# then the Movement expansion, then the step-1 explicit entries, then the
# `#ffffff` default. MEASURED consequences, and both are rows:
#
#   * `Ops.UNSHARD` is spelled out as "#f6ccff" at source position 14 and the
#     Movement expansion is position 15, so IF UNSHARD were in GroupOp.Movement
#     the expansion would win. `op_color.UNSHARD=#f6ccff` -- so it is not, and
#     `ops.bend`'s `GroupOp.movement` agrees (RESHAPE/EXPAND/PERMUTE/PAD/SHRINK/FLIP).
#   * `Ops.WMMA` is "#efefc0" and `Ops.INS` is "#eec4ff", both spelled out before
#     the ALU expansion. `op_color.WMMA=#efefc0` -- so neither is in GroupOp.ALU.
#
# A CHANGE TO `GroupOp.movement` OR `GroupOp.alu` IS A SILENT CHANGE HERE, and it
# is the `x86.bend` trap from the brief: an arm that stops matching falls
# through to whatever is next. So the two group tests are ARGS, computed by the
# caller, and the gate carries all 77 ops -- a set of 77 rows cannot hide one op
# quietly changing colour.
# ===========================================================================


# THE TWO EXPANSIONS, in the order the `**` appear: Movement is written first and
# ALU second, so an op in BOTH takes ALU's colour.
# THE STEP-1 EXPLICIT ENTRIES: the earliest writers, so anything in a group
# overwrote them, which is why they are tested LAST.
# THE TWO EXPANSIONS, in the order the `**` appear: Movement is written first and
# ALU second, so an op in BOTH takes ALU's colour.

# THE STEP-5 EXPLICIT ENTRIES AND THREEFRY: the writers with nothing after them.


def uops_color.tail(mv: Bool, +al: Bool) -> String:
  Bool.pick(String, mv, Bool.pick(String, al, "#ffffc0", "#D8F9E4"), Bool.pick(String, al, "#ffffc0", "#ffffff"))

def uops_color.grp(op: O.Op, mv: Bool, al: Bool) -> String:
  match op:
    case O.OpsLOAD{}: "#ffc0c0"
    case O.OpsSTORE{}: "#87CEEB"
    case O.OpsCONST{}: "#e0e0e0"
    case O.OpsREDUCE{}: "#FF5B5B"
    case O.OpsRANGE{}: "#c8a0e0"
    case O.OpsBARRIER{}: "#ff8080"
    case O.OpsIF{}: "#c8b0c0"
    case O.OpsSPECIAL{}: "#c0c0ff"
    case O.OpsINDEX{}: "#CEF9B7"
    case O.OpsSTACK{}: "#D8F9E4"
    case O.OpsWMMA{}: "#efefc0"
    case O.OpsUNSHARD{}: "#f6ccff"
    case O.OpsINS{}: "#eec4ff"
    case _p: uops_color.tail(mv, al)

def uops_color.ex(op: O.Op, mv: Bool, al: Bool) -> String:
  match op:
    case O.OpsBUFFER{}: "#B0BDFF"
    case O.OpsGETADDR{}: "#9DB1F0"
    case O.OpsCOPY{}: "#ff90c0"
    case O.OpsCUSTOM_FUNCTION{}: "#bf71b6"
    case O.OpsCALL{}: "#00B7C8"
    case O.OpsPARAM{}: "#14686F"
    case O.OpsSOURCE{}: "#c0c0c0"
    case O.OpsBINARY{}: "#404040"
    case O.OpsLINEAR{}: "#7DF4FF"
    case O.OpsALLOC{}: "#C07788"
    case O.OpsALLREDUCE{}: "#ff40a0"
    case O.OpsMSELECT{}: "#d040a0"
    case O.OpsMSTACK{}: "#d040a0"
    case O.OpsSTAGE{}: "#FFC14D"
    case O.OpsREWRITE_ERROR{}: "#1a1b26"
    case O.OpsAFTER{}: "#8A7866"
    case O.OpsEND{}: "#524C46"
    case O.OpsBACKEDGE{}: "#464752"
    case O.OpsTHREEFRY{}: "#ffff80"
    case _p: uops_color.grp(op, mv, al)

def uops_color(+op: O.Op) -> String:
  uops_color.ex(op, O.GroupOp.movement(op), O.GroupOp.alu(op))

# `addrspace_colors` -- four entries and no expansion, so it is a plain ladder.
def addrspace_color(a: S.Addr) -> String:
  match a:
    case S.ALocal{}: "#e7c86a"
    case S.AReg{}: "#e68181"
    case S.Aalu{}: "#AAAAAA"
    case _p: "#75bd7b"

# `wave_colors` -- `{**{x:"#1F7857" for x in ["WMMA","MFMA"]}, **{x:"#ffffc0" for
# x in ["VALU","VINTERP"]}, "SALU": ..., ...}`. viz reads it by SUBSTRING
# (`next((v for k,v in viz.wave_colors.items() if k in op_name), None)`,
# cli.py:161) so the LOOKUP is `name.contains(k)` and first-key-wins is what
# Python's `.items()` gives; both are in `wave_color_of`.
# `List.head`/`List.tail` answer a `Maybe`/a list at a DIFFERENT usage depth than
# the `&2` list a pair fold carries, so the two one-line readers are named here
# rather than spelled three times.
def vs.tail(vs: List<&2, String>) -> List<&2, String>:
  match vs:
    case Nil{}: Nil{}
    case _v <> t: t

def vs.head(vs: List<&2, String>) -> Maybe<&1, String>:
  match vs:
    case Nil{}: None{}
    case v <> _r: Some{v}

def wave_color_of.step(+name: String, ks: List<&2, String>, +vs: List<&2, String>) -> Maybe<&1, String>:
  match ks:
    case Nil{}: None{}
    case +k <> t: Bool.pick(Maybe<&1, String>, String.contains(name, k),
                             vs.head(vs), wave_color_of.step(name, t, vs.tail(vs)))

def wave_color_of(name: String) -> Maybe<&1, String>:
  wave_color_of.step(name, ["WMMA", "MFMA", "VALU", "VINTERP", "SALU", "SMEM", "STORE", "VMEM",
                          "SGMEM", "LDS", "IMMEDIATE", "BARRIER", "JUMP_NO", "JUMP", "WAVERDY"],
                   ["#1F7857", "#1F7857", "#ffffc0", "#ffffc0", "#cef263", "#ffc0c0", "#4fa3cc",
                    "#b2b7c9", "#b2b7c9", "#9fb4a6", "#f3b44a", "#d00000", "#fb8500", "#ffb703", "#1a2a2a"])

# ===========================================================================
# SECTION 5 -- STEPS. `create_step`'s answer is a PYTHON DICT and dict order is
# INSERTION order, which is load-bearing twice over: `/ctxs` serialises the steps
# as JSON and the browser reads them positionally, and `filter_keys` preserves
# it. So a step is an ORDERED `List<Kv>`, not a map, and `create_step` appends in
# the source's order: `name`, `query`, `_data`, `depth`, then `**kwargs` in the
# order the caller passed them.
# ===========================================================================

# `Kv` is Section 3's pair -- it is the JSON object's item AND the step's item,
# because Python's `json.dumps(fmt)` and Python's step dict are both the same
# thing: an ordered str->value mapping.
def Kv.is_private(+kv: Kv) -> Bool: String.starts_with(Kv.key(kv), "_")

def Kv.of(k: String, v: String) -> Kv: Kv{k, v}

# `v` is the RENDERED value, quoted the way `json.dumps` would. `None` is `null`,
# an int is bare, and a string is quoted -- so `step._data=None` and
# `step._data="D"` are different rows and a swapped one is a diff.
def is_some(m: Maybe<&2, String>) -> Bool:
  match m:
    case Some{s}: True{}
    case None{}: False{}

def maybe_json(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "null"

# `+` needs a Data type and a `Maybe` is a Type, so this is a match on the
# Maybe and NOT a `Bool.pick` on `is_some`.
# `None` is `json.dumps(None)` == `null` and a string is `json.dumps(s)` ==
# the quoted form, so `Kv.v` holds the JSON TEXT for both. MEASURED: CPython's
# `step._data` row is `None|'D'` and the `/ctxs` JSON is `null` / `"D"`, so a row
# that stored the bare string would print `D` and be wrong.
def Kv.maybe_kv(k: String, m: Maybe<&2, String>) -> Kv:
  match m:
    case Some{s}: Kv{k, json_str(s)}
    case None{}: Kv{k, "null"}
def Kv.ofu(k: String, v: U32) -> Kv: Kv{k, U32.show(v)}
def Kv.ofi(k: String, v: H.I64) -> Kv: Kv{k, H.i64_text(v)}

# `f"{query[0]}?ctx={query[1]}&step={query[2]}"` -- serve.py:67. The THREE parts
# of the query tuple each land in a different place, so a swapped ctx/step is a
# diff and not a length change.
def step_query(path: String, ctx: U32, st: U32) -> String:
  String.concat([path, "?ctx=", U32.show(ctx), "&step=", U32.show(st)])

def create_step(name: String, path: String, ctx: U32, st: U32, data: Maybe<&2, String>, depth: U32, extra: List<&2, Kv>) -> List<&2, Kv>:
  # `Kv.v` HOLDS THE JSON TEXT of the value, which is why `name` and `query` are
  # quoted here and `depth` is not: MEASURED, `json.dumps` of the step is
  # `{"name": "Name", ..., "depth": 0}` and a row that stored the bare string
  # would print `Name` and be wrong. It is the same convention `tl_fmt` uses.
  List.append(&2, Kv, [Kv.of("name", json_str(name)),
                       Kv.of("query", json_str(step_query(path, ctx, st))),
                       Kv.maybe_kv("_data", data),
                       Kv.ofu("depth", depth)], extra)

# THE STEP AS JSON, which is what `/ctxs` actually serves. `filter_keys` has
# already dropped the `_`-prefixed keys, so what is left is an ORDERED list of
# `(name, value)` pairs and `json.dumps` of a dict keeps that order -- so the row
# is a byte-for-byte check on BOTH the order and the private-key filter, which is
# the whole of `do_GET`'s `/ctxs` branch.



# An int value is stored RENDERED, so the type is gone and this cannot tell `5`
# from `"5"`. Upstream cannot either -- `json.dumps` sees the same thing -- and
# MEASURED: `create_step(..., match_count=5)` and `code_line="5"` serialise
# identically. That is a real property of the format and not a gap in the row.

# `filter_keys` -- `{k:v for k,v in data.items() if not k.startswith("_")}`.
def filter_keys.step(+h: Kv, +t: List<&2, Kv>) -> List<&2, Kv>:
  Bool.pick(List<&2, Kv>, Kv.is_private(h), t, List.append(&2, Kv, [h], t))

def filter_keys(kvs: List<&2, Kv>) -> List<&2, Kv>:
  match kvs:
    case Nil{}: Nil{}
    case +h <> t: filter_keys.step(h, filter_keys(t))

# ===========================================================================
# SECTION 6 -- SHAPES. `shape_to_str` is `"(" + ",".join(srender(x) for x in s)
# + ")"` and `mask_to_str` is the same one level down.
#
# `srender` IS NOT CALLED. It is `ops.bend:3455 # TODO(p3) ops.py:76`, and
# `uop/render.bend`'s `sint_show` is NOT imported either: render.bend pulls in
# fold.bend, which is mid-edit by another unit, and a viz gate that dies on a
# cold fold.bend compile is a gate that reports nothing. So `sint_str` answers
# the `SI` arm -- which is `srender`'s answer for every `sint` that is an int,
# and is every `sint` the gate builds -- and NAMES the `SU` arm as `srender`'s
# job. `shape_to_str.sym` is that seam and it is not called by any row.
# ===========================================================================

# `srender` of an `SI` is the INTEGER, in decimal. `H.i64_text` is `hi:lo` --
# helpers.bend:1303 says so and gives the reason -- so a decimal renderer is
# needed and it is only honest for a value that FITS: `hi == 0` is checked and the
# `hi:lo` form is the fallback, which is a stated limit and not a silent one.
def v_of(hi: U32, lo: U32) -> H.I64: H.i64_of_hi_lo(hi, lo)

def dec_of.at(+hi: U32, +lo: U32) -> String: Bool.pick(String, U32.is_zero(hi), U32.show(lo), H.i64_text(v_of(hi, lo)))

def dec_of(+v: H.I64) -> String: dec_of.at(H.hi32(v), H.lo32(v))

def sint_str(s: O.Sint) -> String:
  match s:
    case O.SI{i}: dec_of(i)
    # `srender`'s answer for a UOp-typed shape element is ops.bend's to give.
    case O.SU{u}: String.concat(["#u", U32.show(u)])

def sint_list(ss: List<&2, O.Sint>) -> List<&2, String>:
  match ss:
    case Nil{}: Nil{}
    case +h <> t: List.append(&2, String, [sint_str(h)], sint_list(t))

def shape_to_str(ss: List<&2, O.Sint>) -> String:
  String.concat(["(", comma(sint_list(ss)), ")"])

def mask_list(ms: List<&2, List<&2, O.Sint>>) -> List<&2, String>:
  match ms:
    case Nil{}: Nil{}
    case +h <> t: List.append(&2, String, [shape_to_str(h)], mask_list(t))

def mask_to_str(ms: List<&2, List<&2, O.Sint>>) -> String:
  String.concat(["(", comma(mask_list(ms)), ")"])

# `fmt_colored(s) = ansistrip(s) if NO_COLOR else s`. `NO_COLOR` is helpers.bend's
# `Flags.no_color`, a `Bool`, so this is one `Bool.pick` and NOT a re-derivation.
def nc_of(+f: H.Flags) -> Bool:
  match f:
    case H.Flags{no_color, default_float, default_int, sum_dtype}: no_color

def fmt_colored(f: H.Flags, +s: String) -> String: Bool.pick(String, nc_of(f), H.ansistrip(s), s)

# `canonicalize_ast(u) = u.replace(arg=KernelInfo()) if u.op is Ops.SINK and
# isinstance(u.arg, KernelInfo) else u`. It needs a `UOp.replace`, which is
# `ops.bend`'s and not written, and its ONLY two callers are `load_rewrites`
# (line 95) and `uop_to_json` (lines 163 and 172) -- both of which are behind the
# `RewriteTrace` wall above. So it is PORTED as the PREDICATE, which is the half
# with a decision in it, and the rebuild is named.
def canonicalize_ast_is(op: O.Op, is_ki: Bool) -> Bool:
  match op:
    case O.OpsSINK{}: is_ki
    case _p: False{}# ===========================================================================
# SECTION 7 -- THE STRING TABLE. `enum_str(s, cache)` is
#
#     if (cret := cache.get(s)) is not None: return cret
#     cache[s] = ret = len(cache)
#     return ret
#
# so the answer is an INDEX INTO FIRST-SEEN ORDER and the table is STATE. There
# is no `enum_str` that threads a table; the table is a parameter and comes back
# in a pair, which is the same shape `Map.get` uses in this repo.
#
# The `.get`-with-`None`-default detail is load-bearing in the other direction
# too: index 0 is a FALSY int, and `cret is not None` (not `if cret`) is what
# makes index 0 come back as itself. MEASURED: `enum_str.seq=0,1,0,2,1,3,4`.
# ===========================================================================

# ONE FOLD, NO `Maybe`. A `match` may not scrutinise a CALL, so the usual
# `match tbl_pos(...)` is refused; and `Maybe` is a Type, not a Data, so it
# cannot ride in a record either. The position walk therefore RETURNS THE ANSWER
# and appends on the empty branch, which is `cache[s] = len(cache)` exactly.
def u32n(i: Nat) -> U32: U32.from_nat(i)

def enum_pos(ss: List<&2, String>, +s: String) -> (List<&2, String> & U32):
  match ss:
    case Nil{}: (List.append(&2, String, ss, [s]), 0)
    case +h <> +t: Bool.pick((List<&2, String> & U32), String.eq(h, s),
                            (ss, u32n(Nat.sub(List.length(&2, String, ss), 1n))), enum_pos(t, s))

def enum_str(ss: List<&2, String>, s: String) -> (List<&2, String> & U32): enum_pos(ss, s)

# THE TABLE, as text. The gate's row is this plus the index sequence, and an
# index is only meaningful against the table it indexes -- so both are printed
# and the harness compares the whole line.
def tbl_text(+ss: List<&2, String>) -> String: String.concat([jcat2(ss), "|", Nat.show(List.length(&2, String, ss))])

# `option(s) = 0 if s is None else s+1`. The DECODER (`cli.decode_profile`) calls
# this `option` too and inverts it, which is why the two directions are one def
# each and not one def with a sign.
def option(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}: U32.add(v, 1)
    case None{}: 0

# `rel_ts(ts, start_ts, ctx)`: `val = int(ts) - start_ts; if val < 0 or val >
# 0xFFFFFFFF: raise ValueError(...); return val`. So the port's answer is a
# `Maybe`: `None` is Python's raise. MEASURED, all five boundaries, including
# the two that REFUSE (`rel_ts.4294967296.0` and `rel_ts.5.10`).
# The test is `val < 0 or val > 0xFFFFFFFF`, and with `val >= 0` the second is
# exactly "the HIGH WORD is nonzero" -- so the whole predicate is `neg or hi!=0`.
# That is why the two facts arrive as PARAMETERS rather than as an `H.I64` the
# arms would have to decompose.
# The three facts are ONE `Word`-shaped view of `ts - start`, so they are carried
# in a `Data` record: `+` on an `H.I64` is available but `H.i64_sub` would then be
# computed three times, and the record says what the predicate reads.
type Rel is Data:
  Rel{neg: Bool, hi: U32, lo: U32}

def rel_view(+ts: H.I64, +start: H.I64) -> Rel:
  Rel{H.i64_is_neg(H.i64_sub(ts, start)), H.hi32(H.i64_sub(ts, start)), H.lo32(H.i64_sub(ts, start))}

def rel_ts.at(r: Rel) -> Maybe<&2, U32>:
  match r:
    case Rel{neg, hi, lo}: Bool.pick(Maybe<&2, U32>, Bool.or(neg, U32.is_ne(hi, 0)), None{}, Some{lo})

def rel_ts(ts: H.I64, start: H.I64) -> Maybe<&2, U32>: rel_ts.at(rel_view(ts, start))

# ===========================================================================
# SECTION 8 -- THE EVENT MODEL.
#
# `flatten_events`, `timeline_layout`, `graph_layout`, `encode_mem_free`,
# `unpack_pmc` and `get_profile` all take one of three Python event classes.
# `device.bend` has NONE of them -- `grep -n Profile tinybendygrad/device.bend`
# returns two COMMENT hits (:450 names `ProfileGraphEntry` in prose, :752 says
# `trace_num` is PORTED as the length of a list of `ProfilePointEvent`s) -- so
# the shape viz reads is declared here, and only the fields viz reads.
#
#   ProfileRangeEvent   device, name:str|TracingKey, st:Decimal, en:Decimal|None, profile_key
#   ProfilePointEvent   device, name:str, key:Any, arg, ts:Decimal
#   ProfileGraphEvent   ents:list[ProfileGraphEntry], deps, sigs:list[Decimal]
#   ProfileGraphEntry   device, name, st_id:int, en_id:int, profile_key
#
# `sigs` is a LIST indexed by id, not a dict (device.py:84), which is why
# `GEnt` carries two `U32` indices and `sig_at` is a list position.
#
# TIMESTAMPS ARE `H.I64`. Python's are `Decimal` and both `rel_ts` and
# `flatten_events` do `int(...)`, which truncates toward zero; every profile
# timestamp is a positive integer microsecond count, so the two agree exactly.
# ===========================================================================

type Ret is Data:
  RNone{}
  RStr{s: String}
  RInt{n: H.I64, f: F32}
  RTb{rows: List<&2, String>}

type Tk is Data:
  Tk{display: String, keys: List<&2, String>, ret: Ret}

type Name is Data:
  NStr{s: String}
  NTk{t: Tk}

type Ev is Data:
  EvRange{st: H.I64, en: Maybe<&2, H.I64>, name: Name, dev: String, pk: Maybe<&2, String>}
  EvPoint{ts: H.I64, nm: String, key: String, dev: String}
  EvGraph{ents: List<&2, GEnt>, sigs: List<&2, H.I64>}

type GEnt is Data:
  GEnt{dev: String, nm: String, st_id: U32, en_id: U32}

# The `(st, en, dur, e)` FOUR-TUPLE `get_profile` builds at serve.py:493. A
# record and not a 4-tuple because Bend's Sigma nests to the left and every
# reader of a nested tuple needs its own accessor; four accessors for one tuple
# is more code than one record and its four accessors, which is what it is.
type DevEv is Data:
  DevEv{st: H.I64, en: H.I64, dur: F32, ev: Ev}

# `cpu_ts_diff(device_ts_diffs, device) = device_ts_diffs.get(device, Decimal(0))`
type Td is Data:
  Td{dev: String, diff: H.I64}

# `device_ts_diffs.get(device, Decimal(0))` -- the default is a PARAMETER, so
# the walk is a `Bool.pick` and not a `Maybe`.
def td_at(tds: List<&2, Td>, +dev: String, d: H.I64) -> H.I64:
  match tds:
    case Nil{}: d
    case Td{k, v} <> +t: Bool.pick(H.I64, String.eq(k, dev), v, td_at(t, dev, d))

def cpu_ts_diff(tds: List<&2, Td>, dev: String) -> H.I64: td_at(tds, dev, H.i64_of_i32(0))

def Ev.ts(e: Ev) -> H.I64:
  match e:
    case EvRange{st, en, name, dev, pk}: st
    case EvPoint{ts, nm, key, dev}: ts
    case EvGraph{ents, sigs}: H.i64_of_i32(0)

# `e.sigs[id]` over a LIST (device.py:84 types `sigs` as `list[Decimal]`, not a
# dict), and an out-of-range index is an IndexError in Python, so the default is
# a PARAMETER and 0 stands for it.
def sig_at.go(sigs: List<&2, H.I64>, +id: Nat, d: H.I64) -> H.I64:
  match sigs:
    case Nil{}: d
    case +h <> t: Bool.pick(H.I64, Nat.is_eq(id, 0n), h, sig_at.go(t, Nat.sub(id, 1n), d))

def sig_at(sigs: List<&2, H.I64>, id: U32) -> H.I64: sig_at.go(sigs, U32.to_nat(id), H.i64_of_i32(0))

type FlatEv is Data:
  FlatEv{st: H.I64, en: H.I64, ev: Ev}

def ev_en(m: Maybe<&2, H.I64>, st: H.I64) -> H.I64:
  match m:
    case Some{v}: v
    case None{}: st

# ===========================================================================
# SECTION 9 -- `timeline_layout` -- serve.py:240-263.
#
#   struct.pack("<BI", 0, len(events)) + b"".join(events)
#   each event: struct.pack("<IIIIfI", enum_str(name), option(ref), option(key),
#                            rel_ts(st, start_ts, ...), dur, enum_str(json.dumps(fmt)))
#
# THE `f` FIELD IS THE WALL (see the header). Every other byte is exact and the
# row says so: `tl_row` prints the hex of bytes 0..15 and 20..23 with the INTEGER
# the float came from between them, so a wrong name index, a wrong `option`, a
# wrong `rel_ts` or a wrong fmt index is a diff. Only the four float bytes are
# unverified, and only because bend 2.0.34 cannot turn an F32 into bits.
#
# `if dur == 0 or isinstance(e, ProfilePointEvent): continue` -- BOTH tests, and
# the fixture has a point event with dur 0 AND a range event with dur 0, so a
# port that implements only one of the two tests keeps a row the other drops.
#
# TWO SCOPE REDUCTIONS, each with its reason rather than a shrug.
#
#   1. THE `ref_map` BRANCH IS NOT PORTED. `if (ref := data.ref_map.get(
#      e.profile_key)) is not None and ref < len(data.ctxs):` needs `data.ref_map`
#      AND `data.ctxs`, and both are populated by exactly ONE def -- `load_rewrites`
#      -- which is behind the `RewriteTrace` wall in the header (`ops.bend` has no
#      def, no type and no inventory row for `RewriteTrace` or
#      `TrackedGraphRewrite`). `option(ref)` and `option(key)` are therefore
#      answered 0 on both sides, which is `None`, and `tl_ref` is the named seam.
#
#   2. `json.loads` IS NOT PORTED. `ret.startswith("JSON")` takes a branch that
#      re-parses a JSON string, and viz's only producer of that string is
#      `json.dumps({"pc": ...})` / `json.dumps({"link": ...})` two functions away
#      (serve.py:397, 418, 430). A tokenizer over UNKNOWN input is a different
#      shape from every other def here and it would be untestable without one, so
#      it is NAMED at `tl_fmt.str` and the `{"metadata": ret}` arm -- which needs
#      no parse -- is ported and gated.
# ===========================================================================

# The accumulator. `scache` is the only thing `timeline_layout` mutates and it
# mutates it THROUGH `enum_str` twice per kept event, so the table, the two
# indices and the event count all ride in ONE record that every step returns.
type TlAcc is Data:
  TlAcc{bs: List<&2, U32>, scache: List<&2, String>, ni: U32, fi: U32, n: U32, start: H.I64}

# `enum_str` answers a Sigma `(table, index)`. This is the ONLY place in bend
# 2.0.34 a Sigma can be taken apart: `case a & b` is refused ("expected a
# pattern") and `(a, b) = some_call(...)` is refused ("a match cannot
# scrutinize a computed value"), but a Sigma AS A PARAMETER destructures with
# `(a, b) = t`. Three defs and one idiom, applied everywhere below.

# NO `value.field` SUGAR IN BEND 2.0.34 -- the brief records this as the thing
# that killed `cstyle.bend` (43 reads, 22 hand-written readers), and it is
# measured again here: `acc.bs` is "expected a defined name", so every field of
# every record in this file is read through a NAMED READER and there is no
# `x.f` anywhere in it.
def TlAcc.bs(+a: TlAcc) -> List<&2, U32>:
  match a:
    case TlAcc{bs, scache, ni, fi, n, start}: bs

def TlAcc.sc(+a: TlAcc) -> List<&2, String>:
  match a:
    case TlAcc{bs, scache, ni, fi, n, start}: scache

def TlAcc.ni(+a: TlAcc) -> U32:
  match a:
    case TlAcc{bs, scache, ni, fi, n, start}: ni

def TlAcc.fi(+a: TlAcc) -> U32:
  match a:
    case TlAcc{bs, scache, ni, fi, n, start}: fi

def TlAcc.n(+a: TlAcc) -> U32:
  match a:
    case TlAcc{bs, scache, ni, fi, n, start}: n

def TlAcc.start(+a: TlAcc) -> H.I64:
  match a:
    case TlAcc{bs, scache, ni, fi, n, start}: start

def TlAcc.of(bs: List<&2, U32>, scache: List<&2, String>, ni: U32, fi: U32, n: U32, start: H.I64) -> TlAcc:
  TlAcc{bs, scache, ni, fi, n, start}

def enum_at.at(+tbl: List<&2, String>, +idx: U32, +acc: TlAcc, name: Bool) -> TlAcc:
  Bool.pick(TlAcc, name, TlAcc.of(TlAcc.bs(acc), tbl, idx, TlAcc.fi(acc), TlAcc.n(acc), TlAcc.start(acc)),
            TlAcc.of(TlAcc.bs(acc), tbl, TlAcc.ni(acc), idx, TlAcc.n(acc), TlAcc.start(acc)))

def enum_at(t: (List<&2, String> & U32), +acc: TlAcc, name: Bool) -> TlAcc:
  (tbl, idx) = t
  enum_at.at(tbl, idx, acc, name)


# `if dur == 0 or isinstance(e, ProfilePointEvent): continue` -- the two tests
# are PARAMETERS of one `Bool` so the fold reads them and does not recompute them.
# `DevEv`'s two readers, same rule as `TlAcc`'s six.
def Dur.dev(d: DevEv) -> F32:
  match d:
    case DevEv{st, en, dur, ev}: dur

def St.t(d: DevEv) -> H.I64:
  match d:
    case DevEv{st, en, dur, ev}: st

def Dur.dur(d: DevEv) -> F32:
  match d:
    case DevEv{st, en, dur, ev}: dur

def Ev.of(d: DevEv) -> Ev:
  match d:
    case DevEv{st, en, dur, ev}: ev

def is_point(e: Ev) -> Bool:
  match e:
    case EvRange{st, en, name, dev, pk}: False{}
    case EvPoint{ts, nm, key, dev}: True{}
    case EvGraph{ents, sigs}: False{}

def tl_keep(dur: F32, e: Ev) -> Bool: Bool.not(Bool.or(U32.is_zero(F32.to_u32(dur)), is_point(e)))



# `rel_ts` RAISES in Python and `timeline_layout` does NOT catch it, so a refusal
# propagates out of the WHOLE function. Here it propagates as the accumulator
# unchanged, which is the same "no answer" and emphatically not a zero event.






# `enum_str(name, scache)` runs BEFORE `enum_str(json.dumps(fmt), scache)` in the
# same statement list, so the table grows name, fmt, name, fmt ... and the SECOND
# call must start from the table the FIRST one produced. Three nested `enum_at`s
# and `enum_pos` is what makes that ordering visible in the source.


# `<I` name, `<I` option(ref), `<I` option(key), `<I` rel_ts, [WALL float],
# `<I` fmt. The two zeros are the un-ported `ref_map` branch and are 0 because
# that branch's answer is `None`, which `option` maps to 0 -- see the header.
def tl_pack5(d: DevEv, st: U32, ni: U32, fi: U32, +acc: TlAcc) -> List<&2, U32>:
  pack_u32(pack_u32(pack_u32(pack_u32(pack_u32(TlAcc.bs(acc), ni), 0), 0), st), fi)





















# `name = e.name; ...; elif isinstance(e.name, TracingKey): name = display_name`.
# A `str` name is used verbatim and the fmt is EMPTY; a `TracingKey` name takes
# its `display_name` and one of THREE `ret` arms.





# `ret: str -> json.loads(ret[4:]) if ret.startswith("JSON") else {"metadata": ret}`
# `ret: int -> {"B/s": int(ret/(dur*1e-6)), "B": ret}`
# `ret: tb   -> {"tb": tb}`

# The `JSON`-prefixed arm is the `json.loads` WALL named in the header; this is
# the `{"metadata": ret}` arm, and it is a whole line of the gate.

# `int(x / (dur*1e-6))`. `F32.to_u32` truncates toward zero, which is `int()`'s
# rule for a non-negative quotient, and `<I` cannot hold 2^32 anyway, so U32 is
# the right domain and not a narrowing. MEASURED: `ret=20000, dur=5.0` gives
# `{"B/s": 4000000000, "B": 20000}`, which OVERFLOWS a signed 32-bit int and is
# exactly why the format is `<I` and not `<i`.

# `RInt` CARRIES BOTH FORMS because Python's `ret` is an int and the division
# FLOATS it: `"B"` is the exact integer and `"B/s"` is computed from the float.
# `H.I64` has no `to_f32` in this tree, so the float half is a parameter and the
# int half is the one this file can prove.

def Tk.display(t: Tk) -> String:
  match t:
    case Tk{display, keys, ret}: display

def Tk.keys(t: Tk) -> List<&2, String>:
  match t:
    case Tk{display, keys, ret}: keys

def Tk.ret(t: Tk) -> Ret:
  match t:
    case Tk{display, keys, ret}: ret

def rate(v: F32, dur: F32) -> U32: F32.to_u32(F32.div(v, F32.mul(dur, 0.000001)))

def tl_fmt.str(s: String) -> List<&2, Kv>: [Kv.of("metadata", json_str(s))]

def tl_fmt.num(n: H.I64, f: F32, dur: F32) -> List<&2, Kv>:
  List.append(&2, Kv, [Kv.ofu("B/s", rate(f, dur))], [Kv.ofi("B", n)])

def tl_fmt.ret(r: Ret, dur: F32) -> List<&2, Kv>:
  match r:
    case RStr{s}: tl_fmt.str(s)
    case RInt{n, f}: tl_fmt.num(n, f, dur)
    case RTb{rows}: [Kv.ofu("tb", u32n(List.length(&2, String, rows)))]
    case RNone{}: Nil{}

def tl_fmt(e: Ev, dur: F32) -> List<&2, Kv>:
  match e:
    case EvRange{st, en, NTk{t}, dev, pk}: tl_fmt.ret(Tk.ret(t), dur)
    case _p: Nil{}

def tl_name(e: Ev) -> String:
  match e:
    case EvRange{st, en, NStr{s}, dev, pk}: s
    case EvRange{st, en, NTk{t}, dev, pk}: Tk.display(t)
    case EvPoint{ts, nm, key, dev}: nm
    case EvGraph{ents, sigs}: "batched"

def tl_emit(d: DevEv, st: U32, +ni: U32, +fi: U32, +acc: TlAcc) -> TlAcc:
  TlAcc.of(tl_pack5(d, st, ni, fi, acc), TlAcc.sc(acc), ni, fi, U32.add(TlAcc.n(acc), 1), TlAcc.start(acc))

# `enum_str(name, scache)` runs BEFORE `enum_str(json.dumps(fmt), scache)` in the
# same statement list, so the table grows name, fmt, name, fmt ... and the SECOND
# call must start from the table the FIRST one produced. Two defs make that
# ordering visible in the source instead of leaving it to the reader.
def tl_emit.fmt(d: DevEv, st: U32, fj: String, +acc: TlAcc) -> TlAcc:
  tl_emit(d, st, TlAcc.ni(acc), TlAcc.fi(acc), enum_at(enum_pos(TlAcc.sc(acc), fj), acc, False{}))

def tl_emit.all(d: DevEv, st: U32, +nm: String, +fmt: List<&2, Kv>, +acc: TlAcc) -> TlAcc:
  tl_emit.fmt(d, st, json_obj(fmt), enum_at(enum_pos(TlAcc.sc(acc), nm), acc, True{}))

def rel_lo(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}: v
    case None{}: 0

def tl_step.put.emit(st: Maybe<&2, U32>, d: DevEv, +nm: String, +fmt: List<&2, Kv>, +acc: TlAcc) -> TlAcc:
  tl_emit.all(d, rel_lo(st), nm, fmt, acc)

def tl_step.put.at(st: Maybe<&2, U32>, +d: DevEv, +acc: TlAcc) -> TlAcc:
  tl_step.put.emit(st, d, tl_name(Ev.of(d)), tl_fmt(Ev.of(d), Dur.dur(d)), acc)

def tl_step.put(+d: DevEv, +acc: TlAcc) -> TlAcc: tl_step.put.at(rel_ts(St.t(d), TlAcc.start(acc)), d, acc)




# NO MUTUAL RECURSION. `Bool.pick` is EAGER, so "skip or emit" wants the tail
# fold on one arm and `continue` on the other -- and `continue` IS the tail fold,
# which is exactly the cycle Bend refuses. So the tail is folded FIRST and handed
# in as a parameter, and the decision is a `Bool` PARAMETER rather than a
# recomputation. The fold is pure and total, so evaluating a skipped event's tail
# eagerly changes nothing observable.
def keep_of(+d: DevEv) -> Bool: tl_keep(Dur.dev(d), Ev.of(d))



def tl_step(keep: Bool, +d: DevEv, tail: TlAcc, +acc: TlAcc) -> TlAcc:
  Bool.pick(TlAcc, keep, tail, tl_step.put(d, acc))

def tl_go(evs: List<&2, DevEv>, +acc: TlAcc) -> TlAcc:
  match evs:
    case Nil{}: acc
    case +h <> t: tl_step(keep_of(h), h, tl_go(t, acc), acc)

# `struct.pack("<BI", 0, len(events))` -- a `B` and an `I`, in that order, in
# FRONT of the records. `tl_row` prints them as the row's first two hex blocks.
def tl_header.at(bs: List<&2, U32>, +acc: TlAcc) -> TlAcc:
  TlAcc.of(bs, TlAcc.sc(acc), TlAcc.ni(acc), TlAcc.fi(acc), TlAcc.n(acc), TlAcc.start(acc))

def tl_header(+acc: TlAcc) -> TlAcc:
  tl_header.at(pack_u32(pack_u8(Nil{}, 0), TlAcc.n(acc)), acc)

def timeline_layout(evs: List<&2, DevEv>, start: H.I64) -> TlAcc:
  tl_header(tl_go(evs, TlAcc.of(Nil{}, Nil{}, 0, 0, 0, start)))


# THE ROW. Bytes 0..15 and 20..23 as hex, then `ns=<et-st>` -- the integer
# `float(en-ts)` is computed from -- then the byte count. A packer that emits one
# byte too many or too few is a LENGTH diff and no row truncates.
def tl_row(+acc: TlAcc, ns: H.I64) -> String:
  String.concat([hex_of(TlAcc.bs(acc)), "/ns", H.i64_text(ns), "/", Nat.show(List.length(&2, U32, TlAcc.bs(acc)))])

# SECTION 10 -- `encode_mem_free` -- serve.py:265-271.
#
#   struct.pack("<BIII", 0, ts, key, len(ei_encoding))
#     + b"".join(struct.pack("<IIIB", run_id, name_id, num, mode) for ...)
#   mode: 2 = read+write, 1 = write, 0 = read
#
# NO FLOAT, SO EVERY BYTE HERE IS EXACT, and the fixture puts all three modes one
# row from each other so a swapped `1` and `2` is a diff and not a coincidence.
# `num` is the POSITION of the key in `arg["bufs"]`, so it is a 0-based index and
# an off-by-one shows up as a wrong byte in the middle of a record.
# ===========================================================================

# `mode = 2 if (num in inputs and num in outputs) else 1 if (num in outputs) else 0`
def in_list(xs: List<&2, U32>, +v: U32) -> Bool:
  match xs:
    case Nil{}: False{}
    case +h <> t: Bool.pick(Bool, U32.is_eq(h, v), True{}, in_list(t, v))

def buf_mode(+num: U32, +ins: List<&2, U32>, +outs: List<&2, U32>) -> U32:
  Bool.pick(U32, in_list(ins, num),
            Bool.pick(U32, in_list(outs, num), 2, 1),
            Bool.pick(U32, in_list(outs, num), 1, 0))

# `next(i for i,k in enumerate(e.arg["bufs"]) if k == key)` -- `next()` with no
# default, so an absent key is a StopIteration. `buf_num` answers `Maybe` and
# `memfree` reports the refusal as a row of its own rather than as a zero: the
# gate prints `NONE` where CPython printed `StopIteration`.
def buf_num.go(bufs: List<&2, U32>, +key: U32, +i: U32) -> Maybe<&2, U32>:
  match bufs:
    case Nil{}: None{}
    case +h <> t: Bool.pick(Maybe<&2, U32>, U32.is_eq(h, key), Some{i}, buf_num.go(t, key, U32.add(i, 1)))

def buf_num(bufs: List<&2, U32>, key: U32) -> Maybe<&2, U32>: buf_num.go(bufs, key, 0)

# `ProfilePointEvent.arg` as the five fields `encode_mem_free` reads out of it.
# `bufs`, `inputs` and `outputs` are all LISTS OF BUFFER NUMBERS, and the function
# compares a NUMBER against a position in `bufs`, so they are `U32` lists and not
# a set or a bitset.
type Exec is Data:
  Exec{n: U32, bufs: List<&2, U32>, ins: List<&2, U32>, outs: List<&2, U32>, nm: String}

def Exec.of(n: U32, bufs: List<&2, U32>, ins: List<&2, U32>, outs: List<&2, U32>, nm: String) -> Exec:
  Exec{n, bufs, ins, outs, nm}

def Exec.num(+u: Exec) -> U32:
  match u:
    case Exec{n, bufs, ins, outs, nm}: n

def Exec.bufs(+u: Exec) -> List<&2, U32>:
  match u:
    case Exec{n, bufs, ins, outs, nm}: bufs

def Exec.ins(+u: Exec) -> List<&2, U32>:
  match u:
    case Exec{n, bufs, ins, outs, nm}: ins

def Exec.outs(+u: Exec) -> List<&2, U32>:
  match u:
    case Exec{n, bufs, ins, outs, nm}: outs

def Exec.nm(+u: Exec) -> String:
  match u:
    case Exec{n, bufs, ins, outs, nm}: nm

# ONE EXEC ROW. `<I` run id, `<I` name id, `<I` num, `<B` mode.




# THE SAME NON-MUTUAL SHAPE AS `tl_go`: the tail is folded first and handed in,
# because `Bool.pick` is eager and "skip this row" IS the tail fold.
def memfree_row.pack(t: (List<&2, String> & U32), run: U32, num: U32, mode: U32) -> (List<&2, U32> & List<&2, String> & Bool):
  (tbl, nid) = t
  (pack_u32(pack_u32(pack_u32(pack_u8(Nil{}, U32.and(mode, 255)), run), nid), num), tbl, True{})

def memfree_row.mk(+num: U32, +u: Exec, +sc: List<&2, String>) -> (List<&2, U32> & List<&2, String> & Bool):
  memfree_row.pack(enum_pos(sc, Exec.nm(u)), Exec.num(u), num, buf_mode(num, Exec.ins(u), Exec.outs(u)))

def memfree_row.at(m: Maybe<&2, U32>, u: Exec, sc: List<&2, String>) -> (List<&2, U32> & List<&2, String> & Bool):
  match m:
    case Some{num}: memfree_row.mk(num, u, sc)
    case None{}: (Nil{}, sc, False{})

def memfree_row(+u: Exec, +key: U32, sc: List<&2, String>) -> (List<&2, U32> & List<&2, String> & Bool):
  memfree_row.at(buf_num(Exec.bufs(u), key), u, sc)

# `b"".join(...)` over a LIST OF LISTS OF BYTES.
def concat_bytes(bs: List<&2, U32>, more: List<&2, U32>) -> List<&2, U32>:
  match bs:
    case Nil{}: more
    case +h <> t: List.append(&2, U32, [h], concat_bytes(t, more))

def memfree_go.at(t: (List<&2, U32> & List<&2, String> & Bool), more: (List<&2, U32> & List<&2, String> & Bool)) -> (List<&2, U32> & List<&2, String> & Bool):
  (bs, sc, ok) = t
  (mb, msc, mok) = more
  Bool.pick((List<&2, U32> & List<&2, String> & Bool), Bool.and(ok, mok),
            (concat_bytes(bs, mb), msc, True{}), (Nil{}, sc, False{}))

def memfree_go(execs: List<&2, Exec>, +key: U32, +sc: List<&2, String>) -> (List<&2, U32> & List<&2, String> & Bool):
  match execs:
    case Nil{}: (Nil{}, sc, True{})
    case +h <> t: memfree_go.at(memfree_row(h, key, sc), memfree_go(t, key, sc))

# `struct.pack("<BIII", 0, ts, key, len(ei_encoding))` -- a `B` then THREE `I`s.
def count(bs: List<&2, U32>, acc: U32) -> U32:
  match bs:
    case Nil{}: acc
    case _h <> t: count(t, U32.add(acc, 1))

def memfree_head(t: (List<&2, U32> & List<&2, String> & Bool), key: U32, ts: U32) -> (List<&2, U32> & List<&2, String> & Bool):
  (bs, sc, ok) = t
  (pack_u32(pack_u32(pack_u32(pack_u8(Nil{}, 0), ts), key), count(bs, 0)), sc, ok)

def encode_mem_free(execs: List<&2, Exec>, +key: U32, ts: U32, sc: List<&2, String>) -> (List<&2, U32> & List<&2, String> & Bool):
  memfree_head(memfree_go(execs, key, sc), key, ts)





# The row prints the hex AND the string table the indices point into, because an
# index is only meaningful against the table it indexes -- and a table printed on
# its own would be a row with no bytes to check.
def memfree_hex.at(bs: List<&2, U32>, sc: List<&2, String>, ok: Bool) -> String:
  String.concat([Bool.pick(String, ok, hex_of(bs), "NONE"), "/", tbl_text(sc)])

def memfree_hex(t: (List<&2, U32> & List<&2, String> & Bool)) -> String:
  (bs, sc, ok) = t
  memfree_hex.at(bs, sc, ok)

# ===========================================================================
# SECTION 11 -- `graph_layout` -- serve.py:273-299. TWO BRANCHES on
# `k.startswith("LINE:")`, and they share NOTHING: the LINE branch packs
# `<BIBQ` plus `<IQ` pairs and appends `max(y)` to `peaks`; the MEMORY branch
# packs `<BIIIQ` per alloc and a nested `encode_mem_free` per free.
# ===========================================================================























def mem_suffix(+k: String) -> Bool: String.ends_with(k, " Memory")

def dev_mem(+k: String) -> String: Bool.pick(String, mem_suffix(k), "true", "false")

def first_of_str(ss: List<&2, String>) -> String:
  match ss:
    case Nil{}: ""
    case +h <> _t: h

def second_of(ss: List<&2, String>) -> String:
  match ss:
    case Nil{}: ""
    case _h <> t: first_of_str(t)

def dev_base.digit(+p1: String) -> Bool: Bool.and(Bool.not(Bool.pick(Bool, String.is_empty(p1), True{}, False{})), is_digits(p1))

def dev_base.at2(+parts: List<&2, String>, +p1: String) -> String:
  Bool.pick(String, dev_base.digit(p1), String.concat([first_of_str(parts), ":", p1]), first_of_str(parts))

def dev_base.at(+parts: List<&2, String>) -> String: dev_base.at2(parts, second_of(parts))

def dev_base(+k: String) -> String: dev_base.at(cl(first_of_str(sp(k))))

def special_of(+p0: String) -> U32:
  Bool.pick(U32, String.eq(p0, "GC"), 0,
    Bool.pick(U32, String.eq(p0, "USER"), 1,
      Bool.pick(U32, String.eq(p0, "TINY"), 2,
        Bool.pick(U32, String.eq(p0, "DISK"), 999, 100))))

def ds_k(+k: String) -> String: k

def ds_join(+k: String, +sp0: U32, +base: String) -> String:
  String.concat([dev_mem(k), "/", U32.show(sp0), "/", base, "/", ds_k(k)])

def device_sort_fn.at(+k: String, +sp0: U32) -> String: ds_join(ds_k(k), sp0, dev_base(ds_k(k)))

def device_sort_fn(+k: String) -> String:
  device_sort_fn.at(k, special_of(first_of_str(cl(first_of_str(sp(k))))))

# `p = k.split(" ")[0].split(":")` and `dev_base = p[0] if len(p) < 2 or not
# p[1].isdigit() else f"{p[0]}:{p[1]}"`. So `GPU:007` KEEPS its three digits
# (`"007".isdigit()` is True) while `AMD:x` collapses to `AMD`. MEASURED, both.















# `special = {"GC": 0, "USER": 1, "TINY": 2, "ALLDEVS": 100, "DISK": 999}` and
# `special.get(p[0], special['ALLDEVS'])`. The DEFAULT is 100, which is also
# `special["ALLDEVS"]` -- so a key that is not in the table and the key
# `"ALLDEVS"` itself are indistinguishable, and the gate says so.

# `return (is_memory, special.get(p[0], special['ALLDEVS']), dev_base, k)` -- a
# FOUR-TUPLE and Python compares it elementwise, so the row prints all four in
# order and a swapped second and third component is a diff.


# `k.endswith(" Memory")`


# `get_arch(target) = "rdna3" if target.startswith("gfx11") else "rdna4" if
# target.startswith("gfx12") else "cdna"`. A chained conditional, so the SECOND
# test is only reached when the first failed -- which is why `gfx11` is rdna3 and
# `gfx12` is rdna4 and `gfx10` is cdna, and a port that tests them in the other
# order answers rdna4 for `gfx1100`.

# `parse_branch(inst)`: `if "branch" in getattr(inst, "op_name", "").lower(): x =
# inst.simm16 & 0xffff; return (x - 0x10000 if x & 0x8000 else x) * 4`.
# THE SIGN EXTENSION IS THE WHOLE FUNCTION and it is why the answer is an `H.I64`:
# MEASURED, simm16=0x8000 answers -131072 and 0xFFF0 answers -64, and `U32.sub`
# wraps -- `4294836224` and `4294967288` -- which is a byte offset that is wrong by
# 2^32 and would silently pack as a huge positive. So the subtraction, the
# multiply and the ROW are all 64-bit, and `simm16` stays a `U32` because
# `& 0xffff` is what upstream does.


# `x - 0x10000` where `x` is 0..65535, in 64-bit so the underflow is a negative.




# `* 4` by doubling: `H.i64_mul` does not exist in helpers.bend, and a shift is a
# multiply for a power of two -- but ONLY while it stays positive, which is why
# this is the LAST step and the sign extension above it is not itself a shift.













def branch_sub_neg(+x0: U32) -> H.I64: H.i64_sub(H.i64_of_i32(U32.and(x0, 65535)), H.i64_of_i32(65536))

def branch_sub_pos(+x0: U32) -> H.I64: H.i64_of_i32(U32.and(x0, 65535))

def dbl(+v: H.I64) -> H.I64: H.i64_add(v, v)

def mul4(+v: H.I64) -> H.I64: dbl(dbl(v))

def branch_hi(x0: U32) -> Bool: U32.is_ne(U32.and(x0, 32768), 0)

def branch_scale.neg(+x0: U32) -> H.I64: mul4(branch_sub_neg(x0))

def branch_scale.pos(+x0: U32) -> H.I64: mul4(branch_sub_pos(x0))

def branch_scale(+x0: U32) -> H.I64: Bool.pick(H.I64, branch_hi(x0), branch_scale.neg(x0), branch_scale.pos(x0))

def is_branch(+op_name: String) -> Bool: String.contains(String.to_lower(op_name), "branch")

def branch_off(+op_name: String, simm16: U32) -> Maybe<&2, H.I64>:
  Bool.pick(Maybe<&2, H.I64>, is_branch(op_name), Some{branch_scale(simm16)}, None{})

def parse_branch_row.at(m: Maybe<&2, H.I64>) -> String:
  match m:
    case Some{v}: H.i64_text(v)
    case None{}: "null"

def parse_branch_row(+op_name: String, +simm16: U32) -> String:
  parse_branch_row.at(branch_off(op_name, simm16))

# `get_arch(target) = "rdna3" if target.startswith("gfx11") else "rdna4" if
# target.startswith("gfx12") else "cdna"`. A CHAINED conditional, so the second test
# is only reached when the first failed -- which is why `gfx11` is rdna3, `gfx12`
# is rdna4 and `gfx10` is cdna, and a port that tested them in the other order
# answers rdna4 for `gfx1100`. MEASURED, and the fixture has `gfx11` (which starts
# with neither `gfx12` nor a longer form) next to `gfx1100`.
def get_arch(+t: String) -> String:
  Bool.pick(String, String.starts_with(t, "gfx11"), "rdna3",
            Bool.pick(String, String.starts_with(t, "gfx12"), "rdna4", "cdna"))

def q_at.go(qs: List<&2, Kv>, +k: String, +d: String) -> String:
  match qs:
    case Nil{}: d
    case +h <> t: Bool.pick(String, String.eq(Kv.key(h), k), Kv.val(h), q_at.go(t, k, d))

def q_at(+qs: List<&2, Kv>, +k: String) -> String:
  q_at.go(qs, k, "0")

def get_int_row.at(+first: String) -> String:
  String.concat([first, "|", U32.show(P.num(parse(first)))])

def get_int_row(+qs: List<&2, Kv>, +k: String) -> String:
  get_int_row.at(q_at(qs, k))

# `p = k.split(" ")[0].split(":")` and `dev_base = p[0] if len(p) < 2 or not
# p[1].isdigit() else f"{p[0]}:{p[1]}"`. So `GPU:007` KEEPS its three digits
# (`"007".isdigit()` is True) while `AMD:x` collapses to `AMD`. MEASURED, both,
# and they sit one row apart in the fixture for exactly that reason.

# `k.endswith(" Memory")` -- the FIRST component, and the only one that is a
# Bool rather than a number. MEASURED: `"GPU Memory "` (trailing space) is
# FALSE, and the fixture has it next to `"GPU Memory"` so a `trim` somewhere
# upstream of this test would be a diff.









# `special = {"GC": 0, "USER": 1, "TINY": 2, "ALLDEVS": 100, "DISK": 999}` and
# `special.get(p[0], special['ALLDEVS'])`. The DEFAULT is 100, which is also
# `special["ALLDEVS"]` -- so an absent key and the key `"ALLDEVS"` itself are
# indistinguishable by the answer, and the fixture prints both rows side by side.

# `return (is_memory, special.get(p[0], special['ALLDEVS']), dev_base, k)` -- a
# FOUR-TUPLE and Python compares it elementwise, so the row prints all four in
# order and a swapped second and third component is a diff.
# The FOURTH component is `k` itself. `String.concat` reads `k` once here and
# once inside `dev_base(k)`, so the two answers are named and joined -- the same
# reason `wave_of` and `row_one` each get an `.at`.




def is_clock(+row: String) -> Bool: String.contains(row, "Clock")

# `len(ss := x.split(":")) > 1` -- AT LEAST TWO parts, so `"plain"` (one part)
# takes the `(999, 999)` arm and `"x:0:1"` (three) takes the pair arm and reads
# only `ss[1]`. MEASURED: both are rows, and a `>= 1` test gets the first wrong.
def row_one.pair(+ss: List<&2, String>) -> Bool:
  match ss:
    case Nil{}: False{}
    case _h <> Nil{}: False{}
    case _h <> _t <> _r: True{}

def row_one.mk(+ss: List<&2, String>) -> String:
  String.concat(["[", U32.show(ord_of(first_of_str(ss))), ", ", U32.show(P.num(parse(second_of(ss)))), "]"])

def row_one.at(+ss: List<&2, String>) -> String:
  Bool.pick(String, row_one.pair(ss), row_one.mk(ss), "[999, 999]")

def row_one(+x: String) -> String:
  row_one.at(cl(x))



# THE WHOLE ANSWER IS A LIST, so it is bracketed even when it is empty:
# MEASURED, `row_tuple('')` is `[]` and not the empty string.



# ===========================================================================
# SECTION 12 -- `row_tuple` -- serve.py:309-310. This is the sharpest function
# in the file for a gate and the fixture is built for it:
#
#   return ((0, 0),) if "Clock" in row else tuple(
#     (ord(ss[0][0]), int(ss[1])) if len(ss := x.split(":")) > 1 else (999, 999)
#     for x in row.split())
#
# FOUR things are checkable at once: the `Clock` short-circuit (a one-element
# answer for a row with FOUR tokens), the number of tokens (the answer's LENGTH),
# the `ord` of the first character (NOT the whole prefix -- `"GPC"` gives 71, not
# `GPC`), and `(999, 999)` for a token with no colon. MEASURED: `row_tuple.'x:0:1'`
# is `[[120, 0]]` -- a THREE-part split still takes only `ss[1]`, so a port that
# joined the rest would answer `0:1`.
# ===========================================================================








# `len(ss := x.split(":")) > 1`


# ===========================================================================
# SECTION 13 -- THE GATE.
#
# One `name=value` line per row, and the harness diffs WHOLE LINES. A
# name-comparing harness reported 0 for all 30 mutations in one unit of this repo
# and 0 for all 68 in another, so the row NAME is a label and never the thing
# compared.
#
# THE EXPECTATIONS ARE NOT IN THIS FILE. `.agents/slop/vz/viz_oracle.py` imports
# `tinygrad/viz/serve.py`, builds the SAME fixtures, CALLS the module's own
# functions and prints the same lines. Nothing here is a transcribed constant:
# `op_color.WMMA=#efefc0` and `dev_sort.'GPU:007'=[false, 100, "GPU:007",
# "GPU:007"]` were both read off a CPython run, and the values most likely to be
# wrong the quiet way -- the colour ladder's dict-literal order, `ord()` of a
# prefix, `0xFFF0` sign extension -- were chosen as fixtures for exactly that.
# ===========================================================================

def row(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

# THE OP COLOUR LADDER, ALL SEVENTY-SEVEN OPS, and not a sample. `uops_colors` is
# a dict literal with two `**` expansions whose whole job is LAST-WINS ordering,
# so a handful of rows could not see one op quietly changing colour while every
# other row stayed green. 77 rows, one per op, plus the dict LENGTH -- and the
# length is what catches an op that gained or lost an entry.
def op_row(nm: String, py: String, op: O.Op) -> IO(Unit):
  row(nm, String.concat([uops_color(op), "|", py]))

# THE OP ENUMERATION, in the order `Op` is declared in ops.bend, which is also the
# order `uop/__init__.py` says controls the toposort -- so this list is not only
# a fixture, it is the file's own statement of which ops exist. MEASURED: the
# seventy-seven names here and the seventy-seven `Ops` members CPython enumerates
# are the SAME SET with no member on either side, which is what makes
# `uops_color` total rather than partial.
def op_list() -> List<&2, O.Op>:
  List.concat(&2, O.Op, [
    [O.OpsSPECIAL{}, O.OpsBUFFER{}, O.OpsALLOC{}, O.OpsNOOP{}, O.OpsREWRITE_ERROR{}, O.OpsPARAM{}, O.OpsCALL{}, O.OpsPROGRAM{}],
    [O.OpsLINEAR{}, O.OpsSOURCE{}, O.OpsBINARY{}, O.OpsSINK{}, O.OpsAFTER{}, O.OpsGROUP{}, O.OpsSTACK{}, O.OpsGETADDR{}],
    [O.OpsINDEX{}, O.OpsSHRINK{}, O.OpsLOAD{}, O.OpsSTORE{}, O.OpsWMMA{}, O.OpsCAST{}, O.OpsBITCAST{}, O.OpsEXP2{}],
    [O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsRECIPROCAL{}, O.OpsNEG{}, O.OpsTRUNC{}, O.OpsADD{}, O.OpsMUL{}],
    [O.OpsSHL{}, O.OpsSHR{}, O.OpsCDIV{}, O.OpsMAX{}, O.OpsCMOD{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}],
    [O.OpsXOR{}, O.OpsOR{}, O.OpsAND{}, O.OpsTHREEFRY{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsFLOORDIV{}],
    [O.OpsFLOORMOD{}, O.OpsWHERE{}, O.OpsMULACC{}, O.OpsBARRIER{}, O.OpsRANGE{}, O.OpsIF{}, O.OpsEND{}, O.OpsENDIF{}],
    [O.OpsBACKEDGE{}, O.OpsCONST{}, O.OpsCUSTOM{}, O.OpsCUSTOMI{}, O.OpsINS{}, O.OpsCONTIGUOUS_BACKWARD{}, O.OpsDETACH{}, O.OpsSTAGE{}],
    [O.OpsCOPY{}, O.OpsMSELECT{}, O.OpsMSTACK{}, O.OpsCUSTOM_FUNCTION{}, O.OpsRESHAPE{}, O.OpsPERMUTE{}, O.OpsEXPAND{}, O.OpsPAD{}],
    [O.OpsFLIP{}, O.OpsUNSHARD{}, O.OpsREDUCE{}, O.OpsALLREDUCE{}, O.OpsPYLITERAL{}]])

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

# `len(uops_colors)` is 65, NOT 77: twelve ops carry no entry and answer the
# `.get(op, "#ffffff")` DEFAULT. So the row counts the NON-DEFAULT colours, and
# that is the number a gained or lost dict entry would move.
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


















def json_take(kvs: List<&2, Kv>) -> String: json_obj(kvs)










































































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

def option_row(m: Maybe<&2, U32>) -> String: U32.show(option(m))


def rel_ts_row.at(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{v}: U32.show(v)
    case None{}: "REFUSED"

def rel_ts_row(ts: H.I64, st: H.I64) -> String: rel_ts_row.at(rel_ts(ts, st))

# `\x1b[31mred\x1b[0m` EXACTLY: ESC, `[`, `31`, `m`, the text, ESC, `[`, `0`, `m`.
# The `[`, the digits and the `m` are three separate pieces in CPython's string and
# gluing them wrong is invisible in the STRIPPED answer -- MEASURED, a first probe
# built `\x1b[91m` and `fmt_colored(NO_COLOR=1)` answered `e` for `red`, which is how
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

def step_val(+kv: Kv) -> String: Kv.val(kv)

def kv_two() -> List<&2, Kv>: [Kv.ofu("match_count", 5), Kv.of("code_line", json_str("f.py:9"))]

def step_items(kvs: List<&2, Kv>) -> String:
  match kvs:
    case Nil{}: ""
    case +h <> Nil{}: String.concat([json_str(Kv.key(h)), ": ", step_val(h)])
    case +h <> t: String.concat([json_str(Kv.key(h)), ": ", step_val(h), ", ", step_items(t)])

def step_json(kvs: List<&2, Kv>) -> String: String.concat(["{", step_items(kvs), "}"])

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
    op_row("op_color.GROUP", "#ffffff", O.OpsGROUP{})
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
    op_row("op_color.RECIPROCAL", "#ffffc0", O.OpsRECIPROCAL{})
    op_row("op_color.NEG", "#ffffc0", O.OpsNEG{})
    op_row("op_color.TRUNC", "#ffffc0", O.OpsTRUNC{})
    op_row("op_color.ADD", "#ffffc0", O.OpsADD{})
    op_row("op_color.MUL", "#ffffc0", O.OpsMUL{})
    op_row("op_color.SHL", "#ffffc0", O.OpsSHL{})
    op_row("op_color.SHR", "#ffffc0", O.OpsSHR{})
    op_row("op_color.CDIV", "#ffffc0", O.OpsCDIV{})
    op_row("op_color.MAX", "#ffffc0", O.OpsMAX{})
    op_row("op_color.CMOD", "#ffffc0", O.OpsCMOD{})
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
    op_row("op_color.FLOORDIV", "#ffffc0", O.OpsFLOORDIV{})
    op_row("op_color.FLOORMOD", "#ffffc0", O.OpsFLOORMOD{})
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
    op_row("op_color.FLIP", "#D8F9E4", O.OpsFLIP{})
    op_row("op_color.UNSHARD", "#f6ccff", O.OpsUNSHARD{})
    op_row("op_color.REDUCE", "#FF5B5B", O.OpsREDUCE{})
    op_row("op_color.ALLREDUCE", "#ff40a0", O.OpsALLREDUCE{})
    op_row("op_color.PYLITERAL", "#ffffff", O.OpsPYLITERAL{})
    row("op_color_len", String.concat([op_color_len(), "|65"]))
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
    row("get_arch.gfx11", get_arch("gfx11"))
    row("get_arch.gfx1100", get_arch("gfx1100"))
    row("get_arch.gfx12", get_arch("gfx12"))
    row("get_arch.gfx1201", get_arch("gfx1201"))
    row("get_arch.gfx10", get_arch("gfx10"))
    row("get_arch.gfx9", get_arch("gfx9"))
    row("get_arch.rdna3", get_arch("rdna3"))
    row("get_arch.gfx110", get_arch("gfx110"))
    row("get_arch.empty", get_arch(""))
    row("parse_branch.S_BRANCH.0010", parse_branch_row("S_BRANCH", 16))
    row("parse_branch.S_BRANCH.fff0", parse_branch_row("S_BRANCH", 65520))
    row("parse_branch.S_BRANCH.8000", parse_branch_row("S_BRANCH", 32768))
    row("parse_branch.branch.0004", parse_branch_row("branch", 4))
    row("parse_branch.S_CBRANCH_VCCZ.fffe", parse_branch_row("S_CBRANCH_VCCZ", 65534))
    row("parse_branch.V_ADD_F32.0001", parse_branch_row("V_ADD_F32", 1))
    row("parse_branch.branch_x.0002", parse_branch_row("branch_x", 2))
    row("parse_branch.s_branch.0010", parse_branch_row("s_branch", 16))
    row("enum_str.seq", enum_idx_row(enum_names(), enum_table(), 0))
    row("enum_str.table", comma(enum_table()))
    row("option", String.concat([option_row(None{}), ",", option_row(Some{0}), ",", option_row(Some{5}), ",", option_row(Some{123})]))
    row("rel_ts.100.0", rel_ts_row(H.i64_of_i32(100), H.i64_of_i32(0)))
    row("rel_ts.0.0", rel_ts_row(H.i64_of_i32(0), H.i64_of_i32(0)))
    row("rel_ts.4294967295.0", rel_ts_row(H.i64_of_hi_lo(0, 4294967295), H.i64_of_i32(0)))
    row("rel_ts.4294967296.0", rel_ts_row(H.i64_of_hi_lo(1, 0), H.i64_of_i32(0)))
    row("rel_ts.5.10", rel_ts_row(H.i64_of_i32(5), H.i64_of_i32(10)))
    row("step.query1", step_query("/graph-rewrites", 3, 7))
    row("step.query2", step_query("/code", 0, 12))
    row("step.filter1", step_json(filter_keys(create_step("Name", "/graph-rewrites", 3, 7, None{}, 0, Nil{}))))
    row("step.filter2", step_json(filter_keys(create_step("N", "/code", 0, 12, Some{"D"}, 2, kv_two))))
    row("shape_str.(4,)", shape_to_str(sint_list_of([H.i64_of_i32(4)])))
    row("shape_str.(4, 8)", shape_to_str(sint_list_of([H.i64_of_i32(4), H.i64_of_i32(8)])))
    row("shape_str.()", shape_to_str(Nil{}))
    row("shape_str.(1, 2, 3, 4)", shape_to_str(sint_list_of([H.i64_of_i32(1), H.i64_of_i32(2), H.i64_of_i32(3), H.i64_of_i32(4)])))
    row("shape_str.(0,)", shape_to_str(sint_list_of([H.i64_of_i32(0)])))
    row("shape_str.(7,)", shape_to_str(sint_list_of([H.i64_of_i32(7)])))
    row("mask_str.((4,),)", mask_to_str(sint_arr2([[H.i64_of_i32(4)]])))
    row("mask_str.((4, 8),)", mask_to_str(sint_arr2([[H.i64_of_i32(4), H.i64_of_i32(8)]])))
    row("mask_str.((),)", mask_to_str(sint_arr2([[]])))
    row("mask_str.((4,), (1, 2))", mask_to_str(sint_arr2([[H.i64_of_i32(4)], [H.i64_of_i32(1), H.i64_of_i32(2)]])))
    row("mask_str.((0, 0), (9, 9, 9))", mask_to_str(sint_arr2([[H.i64_of_i32(0), H.i64_of_i32(0)], [H.i64_of_i32(9), H.i64_of_i32(9), H.i64_of_i32(9)]])))
    row("fmt_colored.off", fmt_colored(H.Flags.defaults(), ansi_red()))
    row("fmt_colored.on", fmt_colored(H.Flags.of("1", "float32", "int32", "float32"), ansi_red()))
    row("fmt_colored.on2", fmt_colored(H.Flags.of("1", "float32", "int32", "float32"), "plain"))
