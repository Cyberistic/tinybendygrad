#!/usr/bin/env python3
"""Mutate autogen.bend one rule at a time and record WHICH name=value ROWS move.

HARNESS RULES, both learned the hard way in this repo:
  * diff whole `name=value` LINES, never row NAMES.  A name-comparing harness
    reported 0 for all 30 mutations in one unit.  Concretely here: keying a row
    on its FIRST token collapses all eighteen `tmap N = V` rows onto the single
    key `tmap`, so eighteen of the forty mutations below reported 0 -- a harness
    bug that looks exactly like a blind spot.  The key is therefore everything
    before the LAST ` = ` when the row has one.
  * run the mutant IN THE ORIGINAL'S DIRECTORY.  A $TMPDIR copy cannot resolve
    `import Base` and reports every mutation as "did not compile".
"""
import subprocess, os, re
import patch_not_apply as PNA
ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
F = os.path.join(ROOT, "tinybendygrad/runtime/support/autogen.bend")
BEND = os.path.join(ROOT, "bin/bend")
BASE = open(os.path.join(ROOT, ".agents/slop/ag-base.txt")).read().split("\n")

def run(text):
    orig = open(F).read()
    try:
        open(F, "w").write(text)
        r = subprocess.run([BEND, F], capture_output=True, text=True, timeout=300)
        if r.returncode != 0 or "SOME PROOFS FAIL" in r.stdout + r.stderr: return None
        return r.stdout.split("\n")
    except subprocess.TimeoutExpired: return None
    finally: open(F, "w").write(orig)

def key(l):
    if " = " in l: return l.rsplit(" = ", 1)[0]
    if l.startswith("rule "): return " ".join(l.split(" ", 2)[:2])
    return l.split(" ", 1)[0] if " " in l else l

def moved(a, b):
    if a is None or b is None: return None
    da, db = {key(l): l for l in a}, {key(l): l for l in b}
    return [k for k in sorted(set(da) | set(db)) if da.get(k) != db.get(k)]

MUTS = [
 ("M1",  "tmap: Void answers c_char instead of None", 'TE{ty_void(), "None"}', 'TE{ty_void(), "ctypes.c_char"}', "the void row -- tmap.miss* rows cannot see it"),
 ("M2",  "tmap: Char_S answers c_byte instead of c_char", 'TE{ty_char_s(), "ctypes.c_char"}', 'TE{ty_char_s(), "ctypes.c_byte"}', "c_char/c_byte are ADJACENT kinds (13/14); a swap is one digit"),
 ("M3",  "tmap: ULong answers int64 instead of uint64", 'TE{ty_ulong(), "ctypes.c_uint64"}', 'TE{ty_ulong(), "ctypes.c_int64"}', "the SIGN of a 64-bit word"),
 ("MM4", "tmap: ULongLong loses the `u`", 'TE{ty_ulonglong(), "ctypes.c_uint64"}', 'TE{ty_ulonglong(), "ctypes.cint64"}', "a missing character -- the exact shape of ops_rdma's BNXT_VENDOR"),
 ("M5",  "tmap: an EXTRA row for Char16 and Char32, which upstream does NOT have", '   TE{ty_bool(), "ctypes.c_bool"},\n', '   TE{ty_bool(), "ctypes.c_bool"},\n   TE{ty_char16(), "ctypes.c_uint16"},\n   TE{ty_char32(), "ctypes.c_uint32"},\n', "a MISSING row must show as an EXTRA row"),
 ("M6",  "uints: swap UChar and Char_U", "[ty_char_u(), ty_uchar(), ty_ushort()", "[ty_uchar(), ty_char_u(), ty_ushort()", "the order of a six-element list"),
 ("M7",  "ints: drop LongLong from the signed tail", "[ty_char_s(), ty_schar(), ty_short(), ty_int(), ty_long(), ty_longlong()]", "[ty_char_s(), ty_schar(), ty_short(), ty_int(), ty_long()]", "a missing element in the concatenation"),
 ("M8",  "ints: the signed tail goes BEFORE uints", "List.append(&2, U32, uints(), ints_tail())", "List.append(&2, U32, ints_tail(), uints())", "a reordering -- `ints` is NOT sorted and must not be"),
 ("M9",  "fps: swap proto and no-proto", "[ty_functionproto(), ty_functionnoproto()]", "[ty_functionnoproto(), ty_functionproto()]", "an unsorted two-tuple"),
 ("M10", "specs: ObjCSuperClassRef 40 -> ObjCProtocolRef 41", "[cur_objcsuperclassref()]", "[cur_objcprotocolref()]", "an adjacent constant"),
 ("M11", "arc_families: drop `mutableCopy`", '["alloc", "copy", "mutableCopy", "new"]', '["alloc", "copy", "new"]', "a missing element"),
 ("M12", "arc_families: `alloc` -> `allloc`", '["alloc", "copy"', '["allloc", "copy"', "a doubled character"),
 ("M13", "base_rules: rule 9 loses the `enum` alternative", '"(struct|union|enum)\\\\s*([a-zA-Z_][a-zA-Z0-9_]*\\\\b)"', '"(struct|union)\\\\s*([a-zA-Z_][a-zA-Z0-9_]*\\\\b)"', "one alternative of a three-alternative group"),
 ("M14", "base_rules: rule 4's backreference becomes \\9", '[uUlL]+\\\\b", "\\\\1"', '[uUlL]+\\\\b", "\\\\9"', "the backreference"),
 ("M15", "base_rules: rule 11's `\\d+:\\d+` becomes `\\d+-\\d+`", '"^.*\\\\d+:\\\\d+.*$"', '"^.*\\\\d+-\\\\d+.*$"', "one character in a two-character class"),
 ("M16", "normalize: drop `while` from the keyword table", '"with", "yield"]', '"with"]', "a keyword going MISSING"),
 ("M17", "normalize: add the SOFT keyword `match`", '["False", "None", "True", "and"', '["False", "None", "True", "match", "and"', "`softkwlist` used by mistake -- the row that pins it"),
 ("M18", "attrs: `< 500` becomes `<= 441`", "U32.is_lt(k, cur_lastattr())", "U32.is_le(k, cur_lastattr())", "the upper bound, off by one"),
 ("M19", "attrs: `>= 400` becomes `> 400`", "U32.is_ge(k, cur_firstattr())", "U32.is_gt(k, cur_firstattr())", "the lower bound, off by one"),
 ("M20", "typehint: Char_S answers int instead of bytes", 'TH{ty_char_s(), "bytes"}', 'TH{ty_char_s(), "int"}', "THE dict-literal overwrite -- the row that caught a real bug"),
 ("M21", "typehint: LAST-WINS becomes NEVER-HITS", "Bool.pick(Maybe<&2, TH>, U32.is_eq(kind, k), th_some(kind, hint), th_last(k, rest))", "th_last(k, rest)", "the hit arm of the dict-literal lookup; FIRST-WINS cannot be expressed as a one-line edit because it needs `th_last(k, xs)`, which does not decrease"),
 ("M22", "typehint: WChar answers int instead of str", 'TH{ty_wchar(), "str"}', 'TH{ty_wchar(), "int"}', "a scalar type annotation"),
 ("M23", "typehint: LongDouble answers float instead of double", 'TH{ty_longdouble(), "float"}', 'TH{ty_longdouble(), "double"}', "the float group"),
 ("M24", "emit_record_pass: c.Struct -> C.Struct", '["class ", tnm, "(c.Struct): pass"]', '["class ", tnm, "(C.Struct): pass"]', "one character of a template"),
 ("M25", "emit_field_line: the two-space indent is lost", 'String.concat(["  ", fname, ": ", hint])', 'String.concat([fname, ": ", hint])', "the indent -- a lost indent is a silently misaligned register write"),
 ("M26", "emit_reg_cell: the quote pair becomes a bare comma", 'String.concat(["(\'", fname, "\', ", String.join(args, ", "), ")"])', 'String.concat([fname, ", ", String.join(args, ", "), ")"])', "the tuple spelling"),
 ("M27", "emit_enum_cell: `:=` becomes `=`", 'String.concat(["(", name, ":=", value, "): \'", name, "\'"])', 'String.concat(["(", name, "=", value, "): \'", name, "\'"])', "the walrus, which is what makes an enum dict self-documenting"),
 ("M28", "anon_name: the counter is 2 instead of 1", 'anon_name(G{Nil{}, Nil{}, 1n, False{}}, "enum")', 'anon_name(G{Nil{}, Nil{}, 2n, False{}}, "enum")', "the ONE counter shared by struct/enum/dynamic"),
 ("M29", "colons_to_underscores: the accumulator is reversed", "    case Nil{}: rep_flush2(acc)", "    case Nil{}: List.reverse(&2, Char, rep_flush2(acc))", "the ORDER of the output -- the bug the differ caught"),
 ("M30", "colons_to_underscores: a lone trailing ':' is dropped", "Bool.pick(List<&2, Char>, pend, List.append(&2, Char, cs, [colon()]), cs)", "cs", "the trailing-colon case, which Python's replace also keeps"),
 ("M31", "emit_dll_line: the paths comma becomes unconditional", 'Bool.pick(String, String.is_empty(paths), "", String.concat([", ", paths]))', 'String.concat([", ", paths])', "a trailing comma when paths is empty"),
 ("M32", "emit_macro_fn: the space after `lambda` always appears", 'Bool.pick(String, List.is_empty(&2, String, args), "", " ")', '" "', "the `' ' * bool(_args)` trick"),
 ("M33", "emit_in_dll: the `# type: ignore` comment is dropped", "# type: ignore\\n\"", "\\n\"", "the mypy suppression"),
 ("M34", "emit_cfunctype: c.CFUNCTYPE -> c.FunctionType", 'String.concat(["c.CFUNCTYPE[", ret', 'String.concat(["c.FunctionType[", ret', "the template name"),
 ("M35", "emit_array: `Literal[N]` -> `Literal(n)`", '"c.Array[", elem, ", Literal[", U32.show(n), "]]"', '"c.Array[", elem, ", Literal(", U32.show(n), ")]"', "bracket vs paren"),
 ("M36", "emit_def_line: the return annotation is dropped", '") -> ", ret, ": ..."', '") ..."', "a bound function's return type"),
 ("M37", "emit_typealias: TypeAlias -> Alias", '": TypeAlias = "', '": Alias = "', "the annotation name"),
 ("M38", "emit_returns_retained: the argument is dropped", 'String.concat([nm, " = objc.returns_retained(", nm, ")"])', 'String.concat([nm, " = objc.returns_retained()"])', "the argument"),
 ("M39", "gtn_is_reserved: `__` -> `_`", 'String.starts_with(n, "__")', 'String.starts_with(n, "_")', "the implementation-reserved test of autogen.py:128"),
 ("M40", "record_nm: the two rewrites swap order", "colons_to_underscores(spaces_to_underscores(n))", "spaces_to_underscores(colons_to_underscores(n))", "the ORDER of autogen.py:142's two replaces"),
 ("M41", "emit_dll_bind: the @ is lost", 'String.concat(["@dll.bind(", String.join(names, ", "), ")"])', 'String.concat(["dll.bind(", String.join(names, ", "), ")"])', "the decorator sigil"),
 ("M42", "emit_enum_dict: the type annotation is dropped", 'String.concat([enm, ": dict[int, str] = {"', 'String.concat([enm, " = {"', "the `dict[int, str]` annotation"),
 ("M43", "emit_reg_fields: `register_fields` -> `fields`", 'String.concat([tnm, ".register_fields(["', 'String.concat([tnm, ".fields(["', "the method name every generated record carries"),
 ("M44", "emit_record_head: SIZE becomes SIZ", 'String.concat(["  SIZE = ", U32.show(size)])', 'String.concat(["  SIZ = ", U32.show(size)])', "the SIZE line -- a lost SIZE makes every offset unverifiable"),
]

src = open(F).read()
rows = []
for mid, desc, find, repl, why in MUTS:
    if find not in src:
        rows.append((mid, desc, why, PNA.not_applied("the anchor text is not in the file"))); continue
    mv = moved(BASE, run(src.replace(find, repl, 1)))
    if mv is None: rows.append((mid, desc, why, "DID NOT COMPILE / PROOFS FAILED"))
    elif not mv:  rows.append((mid, desc, why, "0  <-- BLIND SPOT"))
    else: rows.append((mid, desc, why, f"{len(mv)}  {', '.join(mv[:7])}" + (" ..." if len(mv) > 7 else "")))
w = max(len(r[0]) for r in rows)
out = ["| id | ported rule | rows it moves |", "|---|---|---|"]
for mid, desc, why, res in rows:
    out.append(f"| {mid} | {desc} | {res} |")
    out.append(f"| | _why it should move:_ | {why} |")
live = [r for r in rows if r[3][0].isdigit() and not r[3].startswith("0")]
print("\n".join(out))
print(f"\n{len(rows)} mutations, {len(live)} move rows, {len(rows)-len(live)} do not")
print("NOT MOVING:")
for m, d, w2, r in rows:
    if (m, d, w2, r) not in live: print(f"  {m}: {r}  [{d}]")
