#!/usr/bin/env python3
"""Mutation driver for tinybendygrad/renderer/ptx.bend.

One textual edit at a time; each is measured by diffing the WHOLE `name=value`
line set against the unmutated baseline, never by row NAME -- two units in this
repo reported 0 for every mutation with a name-comparing harness.

Also runs a CONSTANT SWEEP (`+1` per numeric literal in a non-fixture def).
`x86`'s measured result is that a constants sweep finds NONE of the logic
defects and a rules sweep finds all of them, so both are run and the constants
blind list is reported as the deliverable rather than as coverage.
"""
import sys, os, subprocess, difflib
SRC = 'tinybendygrad/renderer/ptx.bend'
OUT = '.agents/slop/ptxown'
PY = OUT + '/s3py.txt'
BIN = './bin/bend'

# THE COPY GOES BESIDE THE FILE, never into a scratch dir: ptx.bend IMPORTS
# ./tc_ptx.bend by a RELATIVE path and a copy in $TMPDIR cannot resolve it (agent
# --core: 22 phantom blind spots in one unit came from exactly that).
COPY = 'tinybendygrad/renderer/_ptxs3mut.bend'   # NOT _ptxmut.bend: that one is COMMITTED and another agent's

def run(src, tag):
  open(COPY, 'w').write(src)
  r = subprocess.run([BIN, COPY], capture_output=True, text=True)
  return r.stdout

def moved(a, b):
  if a == b: return 0, []
  la = {l.split(' = [', 1)[0]: l for l in a.splitlines() if ' = [' in l}
  lb = {l.split(' = [', 1)[0]: l for l in b.splitlines() if ' = [' in l}
  ch = [k for k in lb if la.get(k) != lb[k]]
  return len(ch), sorted(ch)[:4]

BASE = open(SRC).read()
REF = open(PY).read()
assert run(BASE, 'base') == REF, "the unmutated file does not match the oracle"

# (tag, old, new, what it is)
MUT = [
 ("M01", 'def pkey(+prefix: String, +ty: String) -> String: String.concat([prefix, "_", ty, "_"])',
         'def pkey(+prefix: String, +ty: String) -> String: String.concat([prefix, ty, "_"])',
         "the counter KEY loses a separator"),
 ("M02", 'def ssa_name(+key: String, n: U32) -> String: String.concat(["%", key, U32.show(n)])',
         'def ssa_name(+key: String, n: U32) -> String: String.concat([key, U32.show(n)])',
         "the register loses its `%`"),
 ("M03", 'U32.add(Cnt.n(c), k)', 'U32.add(Cnt.n(c), 1)', "the bump is 1 per key, not k per ssa call"),
 ("M05", 'Bool.or(Bool.or(Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)),',
         'Bool.or(Bool.or(Bool.or(U32.is_ge(c, 48), U32.is_le(c, 57)),',
         "`to_function_name`'s digit range is or(not and)"),
 ("M06", 'P.hex1(U32.shrn(Char.to_u32(c), 4n)), P.hex1(Char.to_u32(c))',
         'P.hex1(Char.to_u32(c)), P.hex1(U32.shrn(Char.to_u32(c), 4n))',
         "%02X prints the LOW nibble first"),
 ("M07", 'pf1("pred", "pred", 1, False{})', 'pf1("pred", "", 1, False{})',
         "END's table dtype is the dtype, not the literal `pred`"),
 ("M08", 'pf1("local", "u64", 1, False{})', 'pf1("local", pf.ty_of("", dt), 1, False{})',
         "BUFFER's table dtype is the dtype, not the literal `u64`"),
 ("M09", 'pf1("bidx", "u64", 1, False{})', 'pf1("bidx", pf.ty_of("", dt), 1, False{})',
         "INDEX/SHRINK's table dtype is the dtype, not `u64`"),
 ("M10", 'pf1("dat", Bool.pick(String, is_global(addr), "u64", pf.ty_of("", dt)), 1, False{})',
          'pf1("dat", pf.ty_of("", dt), 1, False{})',
         "PARAM is never `u64`, GLOBAL or not"),
 ("M11", 'pf1("reg", pf.ty_of("", dt), nmn, True{})', 'pf1("reg", pf.ty_of("", dt), nmn, False{})',
         "a REG buffer is a LIST even with one element"),
 ("M12", 'pf1("val", pf.ty_of("", dt), nmn, U32.is_gt(nmn, 1))', 'pf1("val", pf.ty_of("", dt), nmn, True{})',
         "a LOAD is a LIST even with one element"),
 ("M13", 'Bool.or(Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)), U32.is_eq(c, 95))',
         'Bool.or(Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)), U32.is_eq(c, 96))',
         "to_function_name keeps `@` instead of `_`"),
 ("M14", 'O.eq_dt(dt, S.void()), no_pf(), pf1("ridx", pf.ty_of("", dt), 1, False{})',
          'O.eq_dt(dt, S.void()), no_pf(), pf1("ridx", pf.ty_of("", dt), 2, False{})',
          "a RANGE allocates TWO registers"),
 ("M15", 'List.append(&2, String, [P.fmt(line)], Wal.kern(w))', 'List.append(&2, String, Wal.kern(w), [P.fmt(line)])',
         "the SPECIAL `.reg .u32` line is APPENDED, not PREPENDED"),
 ("M16", 'List.concat(&2, String, [reg_go(Wal.c(w), Nil{}), Wal.kern(w)])',
          'List.concat(&2, String, [Wal.kern(w), reg_go(Wal.c(w), Nil{})])',
         "the `.reg` block is `kern ++ decls`, not `decls ++ kern`"),
 ("M17", 'String.join(Rg.p(r), ", ")', 'String.join(Rg.p(r), ",")',
         "a register LIST joins with `,` not `, `"),
 ("M18", 'Maybe.default(&2, String, List.get(&2, String, Rg.p(r), 0n), "")',
          'Maybe.default(&2, String, List.get(&2, String, Rg.p(r), 1n), "")',
         "a scalar register renders its SECOND part"),
 ("M19", 'Bool.pick(U32, is_op(op, O.OpsLOAD{}), A_ALIAS(),', 'Bool.pick(U32, is_op(op, O.OpsLOAD{}), A_PICK(),',
         "on a REG src0 a LOAD PICKS instead of copying"),
 ("M20", 'Bool.pick(U32, idx_ok, A_PICK(), A_REFUSE())', 'Bool.pick(U32, idx_ok, A_PICK(), A_PICK())',
         "the dynamic-register-indexing REFUSAL is gone"),
 ("M21", 'List.append(&2, Rg, Wal.r(w), [r])', 'List.append(&2, Rg, [r], Wal.r(w))',
         "`Wal.rput` PREPENDS instead of appending"),
 ("M23", 'def rg_pick(w: Wal, +s: Wk) -> Rg:\n  rg_pick.pick(List.get(&2, String, Rg.p(rg_at(w, 0)), U32.to_nat(Wk.idx(s))))',
          'def rg_pick(w: Wal, +s: Wk) -> Rg:\n  rg_pick.pick(List.get(&2, String, Rg.p(rg_at(w, 0)), U32.to_nat(U32.add(Wk.idx(s), 1))))',
         "an INDEX's subscript is off by one"),
 ("M24", 'def st_walk(+rs: List<&2, Rg>, +ii: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:',
          'def st_walk(+rs: List<&2, Rg>, +ii: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:',
         "CONTROL: whitespace-only edit"),
 ("M25", 'String.concat([".reg .", ty, " %", key, "<", U32.show(n), ">;"])',
          'String.concat([".reg .", key, " %", ty, "<", U32.show(n), ">;"])',
         "the `.reg` line puts the KEY where the DTYPE goes"),
 ("M26", 'U32.add(U32.from_nat(List.length(&2, String, gots.happy(ss, w))), 1)',
          'U32.from_nat(List.length(&2, String, gots.happy(ss, w)))',
         "the row count forgets to count ITSELF"),
 ("M27", 'Bool.pick(List<&2, Cnt>, Cnt.is(c, key),', 'Bool.pick(List<&2, Cnt>, Bool.not(Cnt.is(c, key)),',
         "the counter's hit and miss arms are SWAPPED"),
 ("M28", 'is_reg(op, addr), A_ALLOC(),', 'is_reg(op, addr), A_SPEC(),',
         "a REG buffer takes the SPECIAL arm"),
 ("M29", 'is_any3(op, [O.OpsNOOP{}, O.OpsGROUP{}, O.OpsCONST{}])', 'is_any3(op, [O.OpsNOOP{}, O.OpsGROUP{}])',
         "CONST is no longer a skip"),
 ("M30", 'is_op(op, O.OpsSINK{}), A_NAME(),', 'is_op(op, O.OpsSINK{}), A_SKIP(),',
         "a SINK no longer renames the entry point"),
]

def apply(tag, old, new):
  if old == new: return BASE
  assert old in BASE, "M%s: pattern not found" % tag
  return BASE.replace(old, new, 1)

print("MUTATION TABLE  (one textual edit at a time, whole-line diff)")
print("%-5s %6s  %s" % ("id", "moved", "what"))
blind = []
for tag, old, new, what in MUT:
  if tag == "M22":      # a real one, not a no-op: `mk` is unused in this file
    src = BASE.replace('def dropn(+xs: List<&2, String>, +n: U32) -> List<&2, String>:',
                       'def dropn(+xs: List<&2, String>, +n: U32) -> List<&2, String>:  # M22')
  elif tag == "M13":
    src = BASE.replace('Bool.pick(Pf, is_op(op, O.OpsRANGE{}), pf.rng(dt),', 'Bool.pick(Pf, is_op(op, O.OpsRANGE{}), no_pf(),')
    what = "a void RANGE still allocates a register"
  else:
    src = apply(tag, old, new)
  out = run(src, tag.lower())
  n, sample = moved(REF, out)
  flag = '  <-- BLIND' if n == 0 and 'CONTROL' not in what else ''
  if n == 0 and 'CONTROL' not in what: blind.append((tag, what))
  print("%-5s %6d  %s%s" % (tag, n, what, flag))
  if n: print("            moved: %s" % ", ".join(sample))

print("\nCONSTANT SWEEP: +1 on every numeric literal outside the generated fixtures")
GEN0 = BASE.index("# ==== BEGIN GENERATED FIXTURES")
GEN1 = BASE.index("# ==== END GENERATED FIXTURES")
import re
cblind = []
hits = []
# A LITERAL INSIDE A COMMENT IS PROSE, NOT CODE: the first sweep reported 119
# sites and 0 moved, and every one of them was a line number or a Python line
# number in a comment. Only CODE is swept, and the sweep drops 0/1/2 because they
# are indices, flags and the one-element list, not constants.
CODE = BASE[:GEN0] + BASE[GEN1:]
def code_of(line):
  h = line.find('#')
  return line if h < 0 else line[:h]
# THE OFFSET MUST BE INTO `CODE`, NOT INTO THE LINE: the first version used the
# per-line `m.start(1)` and rewrote byte 0 of the file every time, which is why
# all seventeen sites reported 0. Caught by hand: bumping `A_STACK` to 9 moves
# seven rows when the edit lands and none when it does not.
BASE_OFF = 0
for ln, line in enumerate(CODE.split("\n"), 1):
  here = BASE_OFF
  BASE_OFF += len(line) + 1
  for m in re.finditer(r'(?<![\w."])(\d+)(?![\w"])', code_of(line)):
    lit = m.group(1)
    if lit in ("0", "1", "2"): continue
    # THE EDIT GOES BACK INTO THE WHOLE FILE: splicing the generated region OUT
    # and running that left `r_all()` calling defs that no longer exist, so every
    # site reported 0 for a compile error rather than for insensitivity. Same
    # lesson as the scratch-copy import failure, one layer over.
    off = here + m.start(1)
    src = BASE[:off + len(lit)] + str(int(lit) + 1) + BASE[off + len(lit):]
    out = run(src, "const%d" % int(lit))
    n, sample = moved(REF, out)
    hits.append((ln, lit, n))
    if n == 0: cblind.append((ln, lit, line.strip()[:70]))
print("literal sites swept (excluding 0/1/2): %d" % len(hits))
print("moved > 0: %d   moved == 0 (BLIND): %d" % (sum(1 for h in hits if h[2] > 0), len(cblind)))
print("\nCONSTANTS BLIND LIST (a literal nothing notices -- these are the")
print("deliverable, not a coverage claim):")
for ln, lit, txt in cblind: print("  line ~%d  %s   %s" % (ln, lit, txt))
print("\nMUTATION BLIND LIST: %s" % ([b[0] for b in blind] or "none"))
try: os.remove(COPY)
except OSError: pass