#!/usr/bin/env python3
"""MUTATION TABLE for tinybendygrad/renderer/nir.bend.

One entry per ported rule, measured, and reported WITH THE ROWS IT MOVED BY
NAME. The harness diffs WHOLE `name=value` LINES, not row names --
`agent-core.md`'s `__init__.bend` note, where a name-comparing harness reported
0 for all 30 mutations in one unit and 0 for all 68 in another.

Plus the CONSTANT SWEEP: `+1` on every constant arm, one at a time, and the
blind ones are reported with reasons rather than closed with rows that encode the
bug.

  .venv/bin/python .agents/slop/nir/nir_mutate.py            # all mutations
  .venv/bin/python .agents/slop/nir/nir_mutate.py 7          # one, by index
  .venv/bin/python .agents/slop/nir/nir_mutate.py --const   # the +1 sweep
"""
import sys, os, re, subprocess, pathlib, tempfile, shutil, time

ROOT = pathlib.Path(__file__).resolve().parents[3]
SRC = ROOT / "tinybendygrad" / "renderer" / "nir.bend"
BASE = None          # the pristine gate text, captured once

def gate(src_text, tmpdir):
  """Run `src_text` through bend and return its gate lines. The file is written
  INSIDE the repo (not `$TMPDIR`) because a scratch copy cannot resolve a
  relative import -- which cost one unit 22 phantom blind spots."""
  work = ROOT / "tinybendygrad" / "renderer" / ("_mut_%s.bend" % tmpdir)
  shutil.copy(SRC, work)
  try:
    work.write_text(src_text)
    out = subprocess.run(["./bin/bend", str(work)], cwd=ROOT, capture_output=True, text=True)
    if out.returncode != 0 or "Error" in out.stdout[:400] or not out.stdout.strip():
      return None, (out.stdout + out.stderr)[:300]
    return [l for l in out.stdout.splitlines() if " = [" in l], ""
  finally:
    work.unlink(missing_ok=True)

def settled(want, tries=40, nap=20):
  """WAIT FOR THE SUBSTRATE. Another agent was mid-edit through one whole run of
  this table and twenty-two mutations came back "DID NOT COMPILE: expected :
  'def', 'type'" -- a top-level parse error in a file that is not this unit's.
  `agent-core.md` says to capture a baseline before a run AND wait for the
  substrate to settle BETWEEN steps; this is the second half. The check is the
  BASELINE reproducing, so a changed substrate is detected by the thing it
  changes rather than by a guess about which file moved.
  """
  for i in range(tries):
    got, _err = gate(SRC.read_text(), "settle")
    if got == want: return True
    time.sleep(nap)
  return False

def moved_rows(a, b):
  if a is None or b is None: return None
  am = {l.split(" = [", 1)[0]: l for l in a}
  bm = {l.split(" = [", 1)[0]: l for l in b}
  return sorted(n for n in set(am) | set(bm) if am.get(n) != bm.get(n))

# ---------------------------------------------------------------------------
# M1..Mn: (id, what it is, a regex with one capture group, the replacement)
MUTATIONS = [
 ("M01", "c: uint arm -> i",                 r'^    case True\{\}: "u"$',            '    case True{}: "i"',            "op_const"),
 ("M02", "c: i arm -> f",                    r'^    case True\{\}: "i"$',            '    case True{}: "f"',            "c.arm2"),
 ("M03", "c: f arm -> b (bool never reaches)", r'^    case True\{\}: "f"$',          '    case True{}: "b"',            "c.arm3"),
 ("M04", "c: `and u` dropped",               r'Bool\.and\(c\.in_uints\(d\), unsigned\)', 'c.in_uints(d)',                 "c"),
 ("M05", "c: `ints` widened to `S.Dt.is_int` (weakint!)", r'^def c\.in_ints\(d: S\.Dt\) -> Bool:\n  match d:\n    case S\.Dt\{pri, bits, cls, nm\}: c\.cls_int\(cls\)$', 'def c.in_ints(d: S.Dt) -> Bool: S.Dt.is_int(d)', "c.in_ints"),
 ("M06", "u_aop: ADD -> uadd",               r'^    case O\.OpsADD\{\}: "iadd"$',    '    case O.OpsADD{}: "uadd"',      "u_aop"),
 ("M07", "s_aop: MAX imax -> umax",          r'^    case O\.OpsMAX\{\}: "imax"$',    '    case O.OpsMAX{}: "umax"',      "s_aop"),
 ("M08", "f_aop: FDIV -> rcp",               r'^    case O\.OpsFDIV\{\}: "fdiv"$',   '    case O.OpsFDIV{}: "rcp"',       "f_aop"),
 ("M09", "f_aop: CMPEQ feq -> fneu",         r'^    case O\.OpsCMPEQ\{\}: "feq"$',   '    case O.OpsCMPEQ{}: "fneu"',    "f_aop"),
 ("M10", "u_aop.rev: ishl swapped with ushr", r'^    case "ishl": "SHL"\n    case "ushr": "SHR"$', '    case "ishl": "SHR"\n    case "ushr": "SHL"', "u_aop.rev"),
 ("M11", "f_aop.rev: ftrunc dropped",        r'^    case "ftrunc": "TRUNC"\n',        '',                               "f_aop.rev"),
 ("M12", "aop_kind: bool no longer unsigned", r'aop_kind\.u\(Bool\.or\(c\.in_uints\(d\), S\.Dt\.is_bool\(d\)\)\)', 'aop_kind.u(c.in_uints(d))', "aop_kind"),
 ("M13", "aop_kind: float class becomes 1",  r'^    case True\{\}: 2$',              '    case True{}: 1',               "aop_kind.f"),
 ("M14", "op_of: WHERE -> OpsCONST",         r'^    case "WHERE": O\.OpsWHERE\{\}$',  '    case "WHERE": O.OpsCONST{}',    "op_of"),
 ("M15", "glsl_sym_int: `glsl_type_builtin_` head dropped", r'String\.concat\(\["glsl_type_builtin_", Bool\.pick', 'String.concat([Bool.pick', "glsl_sym_int"),
 ("M16", "glsl_sym_int: `itemsize == 4` exception dropped", r'Bool\.pick\(String, U32\.is_eq\(S\.Dt\.bits\(d\), 32\), "", ', 'Bool.pick(String, False{}, "", ', "glsl_sym_int"),
 ("M17", "glsl_keyed: `bool` stops being a key", r'R\.is_named\(d, "half"\) \|\| R\.is_named\(d, "bool"\)', 'R.is_named(d, "half")', "glsl_keyed.of"),
 ("M18", "ncast: two-way condition `and` -> `or`", r'Bool\.and\(c\.in_ints\(it\), c\.in_ints\(ot\)\)\)', 'Bool.or(c.in_ints(it), c.in_ints(ot)))', "ncast_mid"),
 # A THEOREM, NOT A BLIND SPOT: `nir.py:28` writes `c(ot, ot == dtypes.bool)` and
 # `c`'s first arm is `t in dtypes.uints and u`. `bool` is NOT in `dtypes.uints`,
 # so for the only `t` that can make `u` true, `u` cannot matter -- `c(bool, x)`
 # is `"b"` for both `x`. `c bool u=True` and `c bool u=False` are the rows that
 # PROVE it, and no fixture can separate the two spellings.
 ("M18b", "ncast: second prefix taken from the DESTINATION's signedness only [THEOREM]", r'c\(ot, R\.is_named\(ot, "bool"\)\)', 'c(ot, False{})', "ncast_mid"),
 ("M19", "ncast: destination bitsize -> source", r'String\.concat\(\[c\(it, True\{\}\), "2", ncast_mid\(it, ot\), U32\.show\(S\.Dt\.bits\(ot\)\)\]\)', 'String.concat([c(it, True{}), "2", ncast_mid(it, ot), U32.show(S.Dt.bits(it))])', "ncast_name"),
 ("M20", "scope: ALU given its own case",    r'^    case S\.Aalu\{\}: "deref"$',     '    case S.Aalu{}: "local"',       "scope"),
 ("M21", "nstore: REG srcs no longer reversed", r'^    case True\{\}: \["addr","val"\]$', '    case True{}: ["val","addr"]', "nstore_srcs.of"),
 ("M22", "nstore: ALIGN_MUL becomes REG-only", r'^def nstore_align_str\.of\(is_reg: Bool, bits: U32, n: U32\) -> String:\n  match is_reg:\n    case True\{\}: "ABSENT"\n    case False\{\}: U32\.show\(nstore_align\.of\(False\{\}, bits, n\)\)', 'def nstore_align_str.of(is_reg: Bool, bits: U32, n: U32) -> String:\n  U32.show(nstore_align.of(True{}, bits, n))', "nstore_align_str"),
 ("M23", "nstore: WRITE_MASK off by one",    r'def nstore_mask\(n: U32\) -> U32: U32\.sub\(U32\.shln\(1, U32\.to_nat\(n\)\), 1\)', 'def nstore_mask(n: U32) -> U32: U32.shln(1, U32.to_nat(n))', "nstore_mask"),
 ("M24", "nload: ACCESS for every space",    r'^def nload_has_access\(space: S\.Addr\) -> Bool: is_global\(space\)$', 'def nload_has_access(space: S.Addr) -> Bool: True{}', "nload_has_access"),
 ("M25", "padded_idx: the extra `+ size` dropped", r'def padded_idx\(\+p: U32, \+s: U32\) -> U32: U32\.add\(round_up\(p, s\), s\)', 'def padded_idx(+p: U32, +s: U32) -> U32: round_up(p, s)', "padded_idx"),
 ("M26", "round_up: multiply BEFORE dividing", r'U32\.mul\(U32\.div\(U32\.add\(x, U32\.sub\(y, 1\)\), y\), y\)', 'U32.div(U32.mul(x, y), y)', "round_up"),
 ("M27", "sd: NAK's arch test `>= 53` becomes `> 53`", r'U32\.is_lt\(arch, 53\)', 'U32.is_le(arch, 53)', "sd"),
 ("M28", "sd: bfloat16 stops being dropped", r'R\.is_named\(d, "fp8e5m2fnuz"\), R\.is_named\(d, "bf16"\)\)', 'R.is_named(d, "fp8e5m2fnuz"), False{})', "sd.drop_base"),
 ("M28b", "sd: one fp8 stops being dropped", r'R\.is_named\(d, "fp8e4m3fnuz"\) \|\| R\.is_named\(d, "fp8e5m2fnuz"\)', 'R.is_named(d, "fp8e5m2fnuz")', "sd.drop_base"),
 ("M29", "cfo: EXP2 no longer dropped by LVP", r'Bool\.and\(cfo\.is\(nm\), Bool\.or\(Bool\.not\(Nir\.drops_exp2\(n\)\), Bool\.not\(String\.eq\(nm, "EXP2"\)\)\)\)', 'cfo.is(nm)', "cfo.has"),
 ("M30", "Nir: LVP's global_max 1 -> 2147483647", r'Nir\{"LVP", False\{\}, False\{\}, 1, 0, 0,', 'Nir{"LVP", False{}, False{}, 2147483647, 65535, 65535,', "Nir.lvp"),
 ("M31", "Nir: shared_max 49152 -> 32768 (the BASE value)", r', 49152, False\{\}, False\{\}, 0\}', ', 32768, False{}, False{}, 0}', "Nir.base"),
 ("M32", "arch_off: the offset becomes 2",   r'^    case "sm_53": "53"$',            '    case "sm_53": "3"',            "arch_off"),
 ("M33", "build_alu: a fifth arity invented", r'^    case 4: "nir_build_alu4"$',     '    case 4: "nir_build_alu4"\n    case 5: "nir_build_alu5"', "build_alu"),
 ("M34", "aop_keys: insertion order float-first (`dtypes.all`'s, not `aop`'s)", r'def aop_keys\(\) -> List<&2, S\.Dt>:\n  List\.append\(&2, S\.Dt, List\.append\(&2, S\.Dt, List\.append\(&2, S\.Dt, \[S\.boolean\(\)\], all_uint\(\)\), all_sint\(\)\), all_float\(\)\)', 'def aop_keys() -> List<&2, S.Dt>:\n  all_of()', "aop_keys"),
 ("M35", "cfo: WHERE dropped from the op set", r'^    case "WHERE": True\{\}$', '    case _: False{}', "cfo.is"),
]

CONST_SWEEP = re.compile(r'^(\s*case "[^"]+": )(\d+)$')

def sweep_consts(tmp):
  """`+1` on every constant arm, one at a time."""
  src = SRC.read_text()
  hits, results = [], []
  for i, line in enumerate(src.splitlines(), 1):
    m = CONST_SWEEP.match(line)
    if m: hits.append((i, m))
  for n, (i, m) in enumerate(hits):
    if not settled(BASE):
      print("SUBSTRATE NEVER SETTLED before K%02d -- stopping" % (n + 1)); break
    txt = src.splitlines()
    txt[i-1] = "%s%d" % (m.group(1), int(m.group(2)) + 1)
    got, err = gate("\n".join(txt) + "\n", "%sconst%d" % (tmp, n))
    rows = moved_rows(BASE, got)
    results.append(("K%02d" % (n+1), i, m.group(0).strip(), rows, err))
  return results

def main():
  global BASE
  src = SRC.read_text()
  BASE, err = gate(src, "base")
  if BASE is None:
    print("BASELINE FAILED TO RUN:\n" + err); return 1
  print("baseline: %d rows\n" % len(BASE))

  if "--const" in sys.argv:
    res = sweep_consts("k")
    blind = [r for r in res if r[3] == []]
    crash = [r for r in res if r[3] is None]
    print("%-6s %-6s %-34s %s" % ("ID", "LINE", "ARM", "ROWS MOVED"))
    print("-" * 100)
    for tag, ln, arm, rows, _e in res:
      print("%-6s %-6d %-34s %s" % (tag, ln, arm[:34], ", ".join(rows) if rows else
                                    ("DID NOT COMPILE" if rows is None else "*** NOTHING MOVED ***")))
    print("\nconstant sweep: %d arms, %d blind, %d did-not-compile"
          % (len(res), len(blind), len(crash)))
    return 0

  only = [a for a in sys.argv[1:] if a.isdigit()]
  print("%-5s %-46s %s" % ("ID", "WHAT", "ROWS MOVED (BY NAME)"))
  print("-" * 110)
  nblind = 0
  for mid, what, pat, rep, target in MUTATIONS:
    if only and mid not in [("M%02d" % int(o)) for o in only]: continue
    if not settled(BASE):
      print("SUBSTRATE NEVER SETTLED before %s -- stopping rather than reporting "
            "another agent's parse error as this file's blind spot" % mid)
      break
    new, n = re.subn(pat, rep, src, count=1, flags=re.M)
    if n == 0:
      print("%-5s %-46s *** PATTERN DID NOT MATCH ***" % (mid, what)); nblind += 1; continue
    got, err = gate(new + "\n", mid.lower())
    rows = moved_rows(BASE, got)
    if rows is None:
      print("%-5s %-46s DID NOT COMPILE: %s" % (mid, what, err.replace("\n", " ")[:50])); nblind += 1
    elif rows == []:
      print("%-5s %-46s *** NOTHING MOVED ***" % (mid, what)); nblind += 1
    else:
      print("%-5s %-46s %s" % (mid, what, ", ".join(rows)))
  print("\n%d mutations, %d blind" % (len(MUTATIONS), nblind))
  return 0

if __name__ == "__main__": main()
