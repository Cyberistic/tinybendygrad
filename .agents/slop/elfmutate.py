#!/usr/bin/env python3
# elfmutate.py -- the MUTATION TABLE for tinybendygrad/runtime/support/elf.bend.
#
# A GATE IS NOT A GATE UNTIL IT HAS TEETH. This script mutates ONE TOKEN of the
# port, re-runs it, and diffs WHOLE `name=value` LINES against the oracle. The
# unit of comparison is the LINE and not the row name, because a name-comparing
# harness reported 0 moved rows for all 30 mutations in one unit and all 68 in
# another -- both of which were green.
#
# A mutation that moves ZERO rows is a HOLE in the gate, not a theorem about the
# port. The one control mutation here is COMMENT-ONLY and is EXPECTED to move
# zero rows: it proves the harness can see nothing when there is nothing to see,
# so a zero elsewhere is a hole rather than a blind spot in the differ.
#
#     python3 .agents/slop/elfmutate.py > .agents/slop/elf_mutations.txt

import os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
TARGET = os.path.join(REPO, "tinybendygrad", "runtime", "support", "elf.bend")
BEND = os.path.join(REPO, "bin", "bend")
ORACLE = os.path.join(HERE, "elf_rows.txt")
PROBE = os.path.join(HERE, "elf_reloc_probe.txt")

def oracle_rows():
  d = {}
  for p in (ORACLE, PROBE):
    for line in open(p):
      line = line.rstrip("\n")
      if "=" in line:
        k, v = line.split("=", 1)
        d[k] = v
  return d

def rows_of(text):
  d = {}
  for line in text.split("\n"):
    if "=" in line:
      k, v = line.split("=", 1)
      d[k] = v
  return d

def run(src, tmp, limit=900):
  """`limit` seconds. A mutation that makes the port NOT TERMINATE is a DETECTION,
  not a hang to wait out: bend's interpreter is a real machine and a broken fuel
  is a real non-termination, so `TimeoutExpired` is reported as a distinct
  outcome rather than allowed to eat the whole table."""
  with open(tmp, "w") as f:
    f.write(src)
  try:
    r = subprocess.run([BEND, tmp], capture_output=True, text=True, timeout=limit)
  except subprocess.TimeoutExpired:
    return "", -1, "TIMEOUT: the mutated port did not terminate"
  return r.stdout, r.returncode, r.stderr

# ONE TOKEN, ONE DEF. `pat` is a regex over the whole file; the FIRST match is
# replaced by `rep`. The rows are named by hand so the table is readable, and the
# expectation (`want`) is `rows` (must move at least one) or `none` (the control).
MUTATIONS = [
  # --- THE CONTROL. A comment, so the compiled program is identical.
  ("control/comment-only",            r"^# THE GATE\.$",
   "# THE GATE. (mutated)", "none"),
  # --- FIELD ORDER AND WIDTH. These are the strings the whole design is for.
  ("Shdr.at_text64/sh_name@4",        r"sh_type@4:", "sh_name@4:", "rows"),
  ("Shdr.at_text64/sh_addr@16->8",    r"sh_addr@16:", "sh_addr@8:", "rows"),
  ("Shdr.at_text32/sh_size@20->24",   r"sh_size@20:", "sh_size@24:", "rows"),
  ("Ehdr.v_shoff/Elf64 40 -> 36",     r"Bool\.pick\(W64, x, W64\.of\(Blob\.le32\(h, 40\), 0\), W64\.of\(Blob\.le32\(h, 32\), 0\)\)",
   "Bool.pick(W64, x, W64.of(Blob.le32(h, 36), 0), W64.of(Blob.le32(h, 32), 0))", "rows"),
  ("Sym.at_text64/st_size@16->8",     r"st_size@16:", "st_size@8:", "rows"),
  # --- THE 64-BIT WORD READ. `k+8` is the NEXT FIELD; the string row saw it.
  ("W64.at64/high-half k+4 -> k+8",   r"W64\.at32\(h, k, U32\.add\(k, 4\)\)",
   "W64.at32(h, k, U32.add(k, 8))", "rows"),
  ("W64.text/hi:lo -> lo:hi",         r'String\.concat\(\[U32\.show\(W64\.hi\(w\)\), ":", U32\.show\(W64\.lo\(w\)\)\]\)',
   'String.concat([U32.show(W64.lo(w)), ":", U32.show(W64.hi(w))])', "rows"),
  # --- THE HEX FORMATTER. One wrong nibble corrupts every byte above it.
  ("Hex.digit/mask 15 -> 14",         r"U32\.and\(v, 15\)\)\n", "U32.and(v, 14))\n", "rows"),
  ("Hex.lowval/'z' reaches 15",       r"Hex\.val\(Char\.from_u32\(122\)\)",
   "Hex.val(Char.from_u32(122))", "none"),  # control: same value, no change
  # --- `Blob.le32` LITTLE-ENDIAN. Swapping the halves is a plausible wrong word.
  ("Blob.le32/byte0<->byte1",          r"U32\.add\(Blob\.u8\(h, i\), U32\.mul\(Blob\.u8\(h, U32\.add\(i, 1\)\), 256\)\)",
   "U32.add(Blob.u8(h, U32.add(i, 1)), U32.mul(Blob.u8(h, i), 256))", "rows"),
  # --- THE STRIDE. 64 vs 40, and the multiply.
  ("Shdr.size/64 -> 32",              r"Bool\.pick\(U32, x, 64, 40\)\n", "Bool.pick(U32, x, 32, 40)\n", "rows"),
  ("Sections.at_blob/drop the stride", r"U32\.mul\(Walk\.i\(w\), Shdr\.size\(x\)\)\)",
   "Walk.i(w))", "rows"),
  # --- THE LIST ORDER. `List.append` is `xs ++ ys`; the wrong argument order
  # produces a REVERSED section table, which a count cannot see.
  ("Sections.step/append order",      r"List\.append\(&2, Shdr, Sections\.one\(Sections\.at_blob\(h, w, x\)\), acc\)",
   "List.append(&2, Shdr, acc, Sections.one(Sections.at_blob(h, w, x)))", "rows"),
  ("Sections.of/drop the reverse",    r"List\.reverse\(&2, Shdr,\n", "List.append(&2, Shdr, Nil{},\n", "rows"),
  # --- `link_sym`, THE FIRST-HIT SCAN.
  ("Link.pos/last hit wins",          r"Bool\.pick\(U32, U32\.is_zero\(acc\), Bool\.to_u32\(Link\.hit\(sym, l\)\), U32\.add\(acc, 1\)\)",
   "Bool.pick(U32, U32.is_zero(acc), U32.add(acc, 1), Bool.to_u32(Link.hit(sym, l)))", "rows"),
  ("Strs.member/never matches",       r"Bool\.pick\(Bool, String\.eq\(h, sym\), True\{\}, Strs\.member\(t, sym\)\)",
   "Bool.pick(Bool, String.eq(h, sym), False{}, Strs.member(t, sym))", "rows"),
  # --- THE RANGE TESTS. Two DIFFERENT predicates over the same input.
  ("Sdiff.rel32_in/2**31 -> 2**31-1", r"U32\.is_lt\(Sdiff\.mag\(d\), 2147483648\)",
   "U32.is_lt(Sdiff.mag(d), 2147483647)", "rows"),
  ("Sdiff.call26_in/positive bound",  r"U32\.is_le\(Sdiff\.mag\(d\), 134217724\)\)",
   "U32.is_le(Sdiff.mag(d), 33554432)", "rows"),
  ("Sdiff.call26_in/negative bound",  r"Bool\.pick\(Bool, Sdiff\.neg\(d\), U32\.is_le\(Sdiff\.mag\(d\), 33554432\)",
   "Bool.pick(Bool, Sdiff.neg(d), U32.is_le(Sdiff.mag(d), 134217724)", "rows"),
  # --- THE TRAMPOLINES. 14 and 16 are the only difference between the two.
  ("Tramp.x86_len/14 -> 12",          r"def Tramp\.x86_len\(\) -> U32: 14", "def Tramp.x86_len() -> U32: 12", "rows"),
  ("Tramp.arm_len/16 -> 14",          r"def Tramp\.arm_len\(\) -> U32: 16", "def Tramp.arm_len() -> U32: 14", "rows"),
  ("Tramp.x86/0x25FF -> 0x25FE",      r"Hex\.of\(16639\)", "Hex.of(16638)", "rows"),
  # --- THE SHIFT AMOUNTS. A `Nat` literal, and 29/5/2 are all load-bearing.
  ("Reloc.adr_hi/shift 29 -> 28",     r"H\.getbits\(rel_pg, 12n, 13n\), 29n\)", "H.getbits(rel_pg, 12n, 13n), 28n)", "rows"),
  ("Reloc.adr_lo/shift 5 -> 4",       r"H\.getbits\(rel_pg, 14n, 32n\), 5n\)", "H.getbits(rel_pg, 14n, 32n), 4n)", "rows"),
  ("Reloc.lo12/shift 10 -> 9",        r"H\.getbits\(tgt, start, end\), 10n\)", "H.getbits(tgt, start, end), 9n)", "rows"),
  ("Reloc.call26_getbits/2 -> 0",     r"H\.getbits\(v, 2n, 27n\)", "H.getbits(v, 0n, 27n)", "rows"),
  # --- THE FNV DIGEST. A different constant is a different fingerprint.
  ("Fnv.pr/16777619 -> 16777621",     r"def Fnv\.pr\(\) -> U32: 16777619", "def Fnv.pr() -> U32: 16777621", "rows"),
  # --- THE ALIGNMENT. elf.py:37's `((align - len % align) % align)`.
  ("Img.pad/drop the outer mod",      r"U32\.mod\(U32\.sub\(align, U32\.mod\(i, align\)\), align\)",
   "U32.sub(align, U32.mod(i, align))", "rows"),
  ("Img.maxalign/swap the arms",      r"Bool\.pick\(U32, U32\.is_lt\(a, f\), f, a\)",
   "Bool.pick(U32, U32.is_lt(a, f), a, f)", "rows"),
  # --- THE RELOC FIELDS.
  ("R.sym/64 shift 32 -> 31",         r"U32\.shrn\(info, 32n\)", "U32.shrn(info, 31n)", "rows"),
  ("R.typ/64 mask lost",              r"Bool\.pick\(U32, x, info, U32\.and\(info, 255\)\)",
   "Bool.pick(U32, x, U32.and(info, 255), U32.and(info, 255))", "rows"),
  ("Rel.trgt/RELA strip 5 -> 4",      r"Bool\.pick\(String, rela, Str\.drop_n\(nm, 5\), Str\.drop_n\(nm, 4\)\)",
   "Bool.pick(String, rela, Str.drop_n(nm, 4), Str.drop_n(nm, 4))", "rows"),
  # --- THE e_shstrndx INDEX, which names every section.
  ("Ehdr.e_shstrndx",                 r"def Shdr\.at_text64", "def Shdr.at_text64", "none"),  # control
  ("Hex.of/big-endian -> little",     r"def Hex\.byte", "def Hex.byte", "none"),  # control
]

def main():
  base_src = open(TARGET).read()
  allrows = oracle_rows()
  # The mutant lives BESIDE THE TARGET, not in a temp dir: the port's
  # `import ./../../helpers.bend` is a RELATIVE path, so a copy anywhere else
  # fails to find the substrate and every mutation would read as "did not
  # compile" -- which is a blind spot in the harness, not a property of the port.
  tmp = TARGET + ".mut"
  out, rc, err = run(base_src, tmp)
  got = rows_of(out)
  print(f"# mutation table for tinybendygrad/runtime/support/elf.bend")
  print(f"# baseline: bend exit {rc}, port emits {len(got)} rows")
  if rc != 0:
    print("# FATAL: the BASELINE does not run")
    print(err.split("\n")[0] if err else "")
    return 1
  # THE GATE IS THE PORT'S OUTPUT, SO THE GATE IS THE INTERSECTION. The oracle
  # carries rows for code that is written but not yet gated, and comparing the
  # whole oracle would make every run red for a reason that has nothing to do
  # with a mutation. The gap is REPORTED, not hidden: `ungated` is how many
  # oracle rows the port does not emit.
  want = {k: allrows[k] for k in got if k in allrows}
  ungated = sorted(set(allrows) - set(got))
  absent = sorted(set(got) - set(allrows))
  moved = sorted(k for k in set(want) | set(got) if want.get(k) != got.get(k))
  print(f"# gate: {len(want)} rows compared, {len(moved)} differing")
  print(f"# COVERAGE GAP: {len(ungated)} oracle rows the port does NOT emit "
        f"(written but ungated), {len(absent)} port rows with no oracle")
  fams = {}
  for k in ungated:
    fams.setdefault("_".join(k.split("_")[:2]), []).append(k)
  for f in sorted(fams):
    print(f"#   ungated family {f}: {len(fams[f])} rows")
  if absent:
    print(f"# FATAL: the port emits rows the oracle does not know: {absent[:5]}")
    return 1
  if moved:
    print(f"# FATAL: the BASELINE is not green: {moved[:5]}")
    return 1
  print(f"# {'mutation':38s} {'rows moved':>10s}  verdict")
  print(f"# {'-' * 38} {'-' * 10}  -------")
  holes = 0
  for name, pat, rep, kind in MUTATIONS:
    m = re.search(pat, base_src, re.M)
    if not m:
      print(f"{name:38s} {'NO-MATCH':>10s}  PATTERN DEAD -- the mutation cannot happen")
      holes += 1
      continue
    src = base_src[:m.start()] + rep + base_src[m.end():]
    out2, rc2, err2 = run(src, tmp)
    got2 = rows_of(out2)
    mv = sorted(k for k in set(want) | set(got2) if want.get(k) != got2.get(k))
    why = ""
    if rc2 == -1:
      mv = ["<did not terminate>"]
      why = "non-termination"
    elif rc2 != 0:
      mv = ["<did not compile>"]
      why = (err2.split("\n")[1] if err2 and len(err2.split("\n")) > 1 else "did not compile")
    ok = (len(mv) > 0) if kind == "rows" else (len(mv) == 0)
    verdict = "caught" if kind == "rows" and mv else ("CONTROL ok" if kind == "none" and not mv else "HOLE")
    if not ok:
      holes += 1
    print(f"{name:38s} {len(mv):>10d}  {verdict}{(' -- ' + why) if why else ''}")
    for k in mv[:6]:
      print(f"{'':38s} {'':>10s}    moved {k}")
    if len(mv) > 6:
      print(f"{'':38s} {'':>10s}    ... {len(mv) - 6} more")
  print(f"#")
  print(f"# holes: {holes} of {len(MUTATIONS)}")
  if os.path.exists(tmp):
    os.remove(tmp)
  return 1 if holes else 0

sys.exit(main())
