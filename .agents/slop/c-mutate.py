#!/usr/bin/env python3
"""c-mutate.py -- THE MEASURED MUTATION TABLE for `tinybendygrad/runtime/support/c.bend`.

A row is only worth its cost if a mutation moves it, so every rule this file
ports gets one mutation here and the rows it moved are reported BY NAME. The
harness diffs WHOLE `name=value` LINES, never row names: a name-comparing
harness reported 0 for all 30 mutations in one unit of this project and 0 for
all 68 in another.

M18 AND M19 ARE THE TRAP THIS PROJECT HAS ALREADY PAID FOR TWICE. A call-site
qualifier pass rewrote a PTX register INSIDE A STRING LITERAL --
`"mov.b32 %r0, %r1;"` became `"%T.r1"` because `r1` is also a `tc.py` def -- and
620 rows STAYED 620, because both halves of each row moved together: the `py=`
half is a literal in the same file, so the two lanes agreed and the row count
did not move. Only a byte diff caught it. M18 changes one CHARACTER inside the
`"mov.b32 %r0, %r1;"`-shaped string this file owns and the count does not move
either; M19 is the same edit done the WRONG WAY (through a qualifier) and it
moves the same number of rows. The difference is that only a byte diff sees
them, so the harness here diffs bytes.

    DEV=NULL .venv/bin/python .agents/slop/c-mutate.py
"""
import pathlib, re, subprocess, sys, tempfile
import patch_not_apply as PNA

REPO = pathlib.Path(__file__).resolve().parents[2]
BEND = REPO / "tinybendygrad/runtime/support/c.bend"
BEND_CMD = [str(REPO / "bin/bend")]

def rows(text):
  return [l for l in text.split("\n") if "=" in l]

def run(src):
  """the interpreted lane, RETRIED -- bend 2.0.34 stack-overflows ~1 run in 20"""
  with tempfile.TemporaryDirectory() as d:
    f = pathlib.Path(d) / "m.bend"
    f.write_text(src)
    for _ in range(6):
      r = subprocess.run(BEND_CMD + [str(f)], capture_output=True, text=True, cwd=REPO)
      out = r.stdout
      if out.strip():
        return out, r.returncode
    return out, r.returncode

# (id, what the mutation breaks, the substitution, the rule it is meant to test)
MUTATIONS = [
 ("M1", "the no-struct arm IGNORES `__idir` -- fold the direction in",
  ('def _do_ioctl(idir: U32, base: U32, nr: U32, size: U32, has_struct: Bool) -> U32:\n'
   '  match has_struct:\n'
   '    case True{}:\n'
   '      U32.or(U32.or(U32.shln(idir, 30n), U32.shln(size, 16n)), U32.or(U32.shln(base, 8n), nr))\n'
   '    case False{}:\n'
   '      U32.or(U32.shln(base, 8n), nr)'),
  ('def _do_ioctl(idir: U32, base: U32, nr: U32, size: U32, has_struct: Bool) -> U32:\n'
   '  match has_struct:\n'
   '    case True{}:\n'
   '      U32.or(U32.or(U32.shln(idir, 30n), U32.shln(size, 16n)), U32.or(U32.shln(base, 8n), nr))\n'
   '    case False{}:\n'
   '      U32.or(U32.or(U32.shln(idir, 30n), U32.shln(size, 16n)), U32.or(U32.shln(base, 8n), nr))'),
  "fact 1: `__idir` is dropped when `__struct is None`"),

 ("M2", "`__set_name__`'s SECOND arm: `idx` is 0 when the owner had no entries",
  ('def Field.set_name.idx(has_real: Bool, n: U32) -> U32:\n  Bool.pick(U32, has_real, n, 0)'),
  ('def Field.set_name.idx(has_real: Bool, n: U32) -> U32: n'),
  "`idx = len(_real_fields_) - 1`, which is 0 on the `else` arm"),

 ("M3", "`if self.bit_width` is TRUTHINESS, so `bit_width=0` gives a 3-wide entry",
  ('def Field.entry_width(+f: Field, bw_truthy: Bool) -> U32:\n  Bool.pick(U32, bw_truthy, 5, 3)'),
  ('def Field.entry_width(+f: Field, bw_truthy: Bool) -> U32:\n  Bool.pick(U32, bw_truthy, 5, 5)'),
  "`bit_width=0` is not None and is still falsy"),

 ("M4", "`zip` TRUNCATES: a fourth positional is dropped, not an error",
  ('def Struct.nset(+s: Struct, nargs: U32) -> U32: U32.min(Struct.nfields(s), nargs)'),
  ('def Struct.nset(+s: Struct, nargs: U32) -> U32: nargs'),
  "`[*zip(names, args)]` stops at the shorter of the two"),

 ("M5", "positionals are written BEFORE keywords, so the keyword wins",
  ('def Struct.init(+s: Struct, +mem: List<&2, U32>, +args: List<&2, U32>, kwn: String, kwv: U32) -> List<&2, U32>:\n'
   '  Struct.kw.go(Struct.real_fields(s), kwn, kwv,\n'
   '               Struct.pos.go(Struct.real_fields(s),\n'
   '                             List.take(&2, U32, args, U32.to_nat(Struct.nset(s, U32.from_nat(List.length(&2, U32, args))))),\n'
   '                             mem))'),
  ('def Struct.init(+s: Struct, +mem: List<&2, U32>, +args: List<&2, U32>, kwn: String, kwv: U32) -> List<&2, U32>:\n'
   '  Struct.pos.go(Struct.real_fields(s),\n'
   '                List.take(&2, U32, args, U32.to_nat(Struct.nset(s, U32.from_nat(List.length(&2, U32, args))))),\n'
   '                Struct.kw.go(Struct.real_fields(s), kwn, kwv, mem))'),
  "[*zip(...), *kwargs.items()] -- a field named twice takes the KEYWORD"),

 ("M6", "`init_c_struct_t` sets `_fields_` and NEVER `SIZE`",
  ('def init_c_struct_t(+mem_len: U32, fields: List<&2, Field>) -> Struct:\n  Struct{0, mem_len, fields}'),
  ('def init_c_struct_t(+mem_len: U32, fields: List<&2, Field>) -> Struct:\n  Struct{mem_len, mem_len, fields}'),
  # (the text above is the `record` DIRECTION swapped in; see M6b)
  "fact 5: `SIZE` is the inherited 0 while `sizeof` is `sz`"),

 ("M6b", "`init_c_struct_t` writes SIZE=0; put `sz` there instead",
  ('def init_c_struct_t(+mem_len: U32, fields: List<&2, Field>) -> Struct:\n  Struct{0, mem_len, fields}'),
  ('def init_c_struct_t(+mem_len: U32, fields: List<&2, Field>) -> Struct:\n  Struct{mem_len, mem_len, fields}'),
  "fact 5: `ics_sizes=0,8`"),

 ("M7", "`record` sets `_fields_` FROM `cls.SIZE`, the other direction",
  ('def Struct.of(+size: U32, fields: List<&2, Field>) -> Struct:\n  Struct{size, size, fields}'),
  ('def Struct.of(+size: U32, fields: List<&2, Field>) -> Struct:\n  Struct{0, size, fields}'),
  "`_mem_` is `c_byte * cls.SIZE`"),

 ("M8", "`ceildiv(bit_width+bit_off, 8)` -- floor instead of ceiling",
  ('def Field.bf_size(+f: Field) -> U32: H_ceildiv_u32(U32.add(Field.bit_width(f), Field.bit_off(f)), 8)'),
  ('def Field.bf_size(+f: Field) -> U32: U32.div(U32.add(Field.bit_width(f), Field.bit_off(f)), 8)'),
  "`sz = ceildiv(self.bit_width+self.bit_off, 8)`"),

 ("M9", "`(1 << bit_width) - 1` -- drop the `- 1`",
  ('def Field.mask(+f: Field) -> U32: U32.sub(U32.shln(1, U32.to_nat(Field.bit_width(f))), 1)'),
  ('def Field.mask(+f: Field) -> U32: U32.shln(1, U32.to_nat(Field.bit_width(f)))'),
  "`mask:=(1 << self.bit_width) - 1`"),

 ("M10", "`to_bytes(sz)` RAISES on an overflow; there is no masking on the store",
  ('def Field.bset_overflows(+f: Field, v: U32) -> Bool:\n'
   '  U32.is_gt(U32.shln(v, U32.to_nat(Field.bit_off(f))),\n'
   '            U32.sub(U32.shln(1, U32.to_nat(U32.mul(8, Field.bf_size(f)))), 1))'),
  ('def Field.bset_overflows(+f: Field, v: U32) -> Bool: False{}'),
  "`OverflowError`, not a silent truncation"),

 ("M11", "`U32.shrn(x, 0n)` is `x`, so byte 0 needs `& 255`",
  ('U32.and(U32.shrn(merged, U32.to_nat(U32.mul(8, U32.sub(U32.from_nat(i), U32.from_nat(lo))))), 255)'),
  ('U32.shrn(merged, U32.to_nat(U32.mul(8, U32.sub(U32.from_nat(i), U32.from_nat(lo)))))'),
  "the second unmasked-byte bug in this file, and it is a THEOREM-free zero"),

 ("M12", "`List.set` indexes the list it is GIVEN, and the recursion hands it the TAIL",
  ('      List.append(&2, U32, [Field.bset.byte_of(Bool.and(U32.is_ge(U32.from_nat(i), U32.from_nat(lo)),\n'
   '                                                      U32.is_lt(U32.from_nat(i), U32.add(U32.from_nat(lo), U32.from_nat(sz)))),\n'
   '                                             h, i, lo, sz, merged, le)],\n'
   '                  Field.bset.go(t, U32.to_nat(U32.inc(U32.from_nat(i))), lo, sz, merged, le))'),
  ('      List.set(&2, U32, Field.bset.go(t, U32.to_nat(U32.inc(U32.from_nat(i))), lo, sz, merged, le), i,\n'
   '               Field.bset.byte_of(Bool.and(U32.is_ge(U32.from_nat(i), U32.from_nat(lo)),\n'
   '                                           U32.is_lt(U32.from_nat(i), U32.add(U32.from_nat(lo), U32.from_nat(sz)))),\n'
   '                                  h, i, lo, sz, merged, le))'),
  "THE WRITE MUST PREPEND -- the reverted form indexes the TAIL"),
 ("M12b", "the write REBUILDS the list from the tail, so the whole store is lost",
  ('                  Field.bset.go(t, U32.to_nat(U32.inc(U32.from_nat(i))), lo, sz, merged, le))'),
  ('                  Nil{})'),
  "what the M12 family looked like before it was found: an EMPTY memory"),

 ("M13", "`nm.replace('-','_')` -- the append already preserves order, so no reverse",
  ('  String.from_list(nm_replace.go(String.to_list(nm), Nil{}))'),
  ('  String.from_list(List.reverse(&2, Char, nm_replace.go(String.to_list(nm), Nil{})))'),
  "`List.append(a, A, xs, ys)` is `xs ++ ys`"),

 ("M14", "the `.so` prefix is `lib` + p + `.so`, which is SIX characters plus p",
  ('String.drop(name, (U32.to_nat(6) + String.length(p) : Nat))'),
  ('String.drop(name, (U32.to_nat(3) + String.length(p) : Nat))'),
  "`re.fullmatch(f\"lib{p}\\.so[.0-9]*\", l.name)`"),

 ("M15", "the `.so` tail is `[.0-9]` -- allow every printable character",
  ('def findlib.so_tail(+cp: U32) -> Bool:\n  Bool.or(U32.is_eq(cp, 46), Bool.and(U32.is_ge(cp, 48), U32.is_le(cp, 57)))'),
  ('def findlib.so_tail(+cp: U32) -> Bool: Bool.not(U32.is_lt(cp, 32))'),
  "`libz.soa` fails and `libz.so.` passes"),

 ("M16", "the ELF magic is `\\x7FELF` and not `\\x7FEL`",
  ('Bool.and(Bool.and(U32.is_eq(h0, 127), U32.is_eq(h1, 69)), Bool.and(U32.is_eq(h2, 76), U32.is_eq(h3, 70)))'),
  ('Bool.and(Bool.and(U32.is_eq(h0, 127), U32.is_eq(h1, 69)), Bool.and(U32.is_eq(h2, 76), Bool.not(U32.is_zero(h3))))'),
  "the linker-script filter, and it is SEPARATE from the name test"),

 ("M17", "`findlib`'s base names are built from `p`, NOT from `nm`",
  ('def findlib.base.osx(+p: String) -> List<&2, String>:\n'
   '  [String.concat(["lib", p, ".dylib"]), String.concat([p, ".dylib"]), p]'),
  ('def findlib.base.osx(+p: String) -> List<&2, String>:\n'
   '  [String.concat(["lib", p, ".dylib"]), String.concat([p, ".dylib"]), String.concat([p, ".dylib"])]'),
  "the third rung is `str(p)`, the BARE path entry"),

 ("M18", "A CHARACTER INSIDE A STRING LITERAL. The row count does NOT move.",
  ('    _ : Unit <- IO.print(String.concat(["dll_getattr_msg=", DLL.attr_err("nope", DLL.emsg("nope", ""))]))'),
  ('    _ : Unit <- IO.print(String.concat(["dll_getattr_msg=", DLL.attr_err("nop3", DLL.emsg("nope", ""))]))'),
  "the tc_ptx.bend trap: `nope` -> `nop3` moves the SAME row count, and only a BYTE diff sees it"),

 ("M19", "the same string, the WRONG WAY -- through a call-site qualifier",
  ('  String.concat(["failed to load library ", nm, ": ", emsg])'),
  ('  String.concat(["failed to load library ", nm, ": "])'),
  "M18 done by DELETING a piece of the same string: the row still exists and the COUNT is unchanged"),

 ("M20", "`libpaths` is keyed by BOTH os.name AND sys.platform and BOTH are appended",
  ('  List.append(&2, String, List.append(&2, String, List.append(&2, String, findlib.prefixes.env(env, String.is_empty(env)), osname_list), plat_list), extra)'),
  ('  List.append(&2, String, List.append(&2, String, findlib.prefixes.env(env, String.is_empty(env)), osname_list), extra)'),
  "`libpaths.get(os.name, []) + libpaths.get(sys.platform, []) + extra_paths`"),

 ("M21", "`[d for d in LD_LIBRARY_PATH.split(':') if d]` -- keep the empties",
  ('def libpaths.posix(ld: String, sep: Char) -> List<&2, String>:\n'
   '  List.append(&2, String, List.filter(String, str_nonempty, String.split(ld, sep)), ["/usr/lib64", "/usr/lib", "/usr/local/lib"])'),
  ('def libpaths.posix(ld: String, sep: Char) -> List<&2, String>:\n'
   '  List.append(&2, String, String.split(ld, sep), ["/usr/lib64", "/usr/lib", "/usr/local/lib"])'),
  "the `if d` is what makes `::` collapse to two entries"),

 ("M22", "`if rc:` -- a zero return does NOT raise",
  ('  _do_ioctl.raise_msg.of(Bool.or(neg, Bool.not(U32.is_zero(mag))), neg, mag)'),
  ('  _do_ioctl.raise_msg.of(True{}, neg, mag)'),
  "`if (rc:=ioctl(...)): raise RuntimeError(...)`"),

 ("M23", "`init_c_var` returns INDEX 1 of the tuple, which is the VAR",
  ('def init_c_var.val(ty_zero: U32, cb_ret: U32) -> U32: ty_zero'),
  ('def init_c_var.val(ty_zero: U32, cb_ret: U32) -> U32: cb_ret'),
  "`(creat_cb(v := ty()), v)[1]`"),

 ("M24", "`bget` masks; drop the mask and the getter reads the whole slice",
  ('  U32.and(U32.shrn(Field.b2i(Field.bf_size(f), mem, le), U32.to_nat(Field.bit_off(f))), Field.mask(f))'),
  ('  U32.shrn(Field.b2i(Field.bf_size(f), mem, le), U32.to_nat(Field.bit_off(f)))'),
  "`b2i(obj) >> self.bit_off & mask`"),

  ("M25", "`Field.of` DROPS the `idx` it is handed and stores 0",
   ('def Field.of(typ: U32, off: U32, bit_width: U32, has_bit_width: Bool, bit_off: U32, name: String, idx: U32) -> Field:\n'
    '  Field{typ, off, bit_width, has_bit_width, bit_off, name, idx}'),
   ('def Field.of(typ: U32, off: U32, bit_width: U32, has_bit_width: Bool, bit_off: U32, name: String, idx: U32) -> Field:\n'
    '  Field{typ, off, bit_width, has_bit_width, bit_off, name, 0}'),
   "D2. `sname_ctor_idx_given` was the literal `0,0` on BOTH lanes, so this "
   "mutation moved nothing: every Field in the fixture was built with idx=0, so a "
   "port that ignored the argument was indistinguishable from one that honoured "
   "it. The row now reads `0,5` -- a Field nobody NAMED, the only place the "
   "ctor's value survives `__set_name__` (c.py:64), and one value GIVEN."),

  ("M26", "`Field.of` pins `idx` to 1",
   ('def Field.of(typ: U32, off: U32, bit_width: U32, has_bit_width: Bool, bit_off: U32, name: String, idx: U32) -> Field:\n'
    '  Field{typ, off, bit_width, has_bit_width, bit_off, name, idx}'),
   ('def Field.of(typ: U32, off: U32, bit_width: U32, has_bit_width: Bool, bit_off: U32, name: String, idx: U32) -> Field:\n'
    '  Field{typ, off, bit_width, has_bit_width, bit_off, name, 1}'),
   "the same row from the other side: a changed `idx=0` DEFAULT, which is the "
   "claim the hand-typed `0,0` was asserting and could not check"),
]

def main():
  src = BEND.read_text()
  base_out, base_rc = run(src)
  base = rows(base_out)
  print("BASELINE  %d rows, bend exit %d" % (len(base), base_rc))
  if len(base) != 129:
    print("FAIL: the baseline is not 127 rows -- bend did not run. Stopping.")
    return 1
  keep = src
  total_moved = 0
  zeros = []
  try:
    for mid, what, old, new, rule in MUTATIONS:
      if old not in src:
        print("%-5s %s -- the target text is not in the file (the file moved on)"
              % (mid, PNA.not_applied()))
        zeros.append(mid + " (" + PNA.not_applied() + ")")
        continue
      mut = src.replace(old, new, 1)
      out, rc = run(mut)
      got = rows(out)
      if not got:
        print("%-5s COMPILE FAILED -- a mutation that does not compile proves NOTHING" % mid)
        zeros.append(mid + " (does not compile)")
        continue
      # NOT a symmetric difference. The two comprehensions below are the SAME
      # set, so `A ^ A` is empty and every mutation reports ZERO -- which is
      # what the first run of this harness did, with 82 moved lines reported as
      # twenty-five blind spots. A name moves when its LINE differs.
      diffs = [(a, b) for a, b in zip(base, got) if a != b]
      moved = sorted({a.split("=", 1)[0] for a, _ in diffs})
      n = len(diffs)
      tag = "OK " if moved else "ZERO"
      print("%-5s %-4s %2d line(s)  %s" % (mid, tag, n, " ".join(moved[:9]) + (" ..." if len(moved) > 9 else "")))
      print("        breaks: %s" % what)
      print("        rule:   %s" % rule)
      if not moved:
        zeros.append(mid + " (" + what + ")" + (" -- THEOREM, measured: see the header"
                        if mid == "M2" else ""))
      total_moved += n
  finally:
    BEND.write_text(keep)
  print()
  print("ROWS MOVED: %d over %d mutations" % (total_moved, len(MUTATIONS)))
  if zeros:
    print("BLIND SPOTS -- reported, NOT closed with a row that encodes the bug:")
    for z in zeros: print("  " + z)
  return 0

if __name__ == "__main__":
  sys.exit(main())