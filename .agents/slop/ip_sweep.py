#!/usr/bin/env python3
"""EXHAUSTIVE, MEASURED mutation sweep over the LEAF rules of ip.bend.

ip_mutate.sh covers the LOGIC rules by hand. This covers the other two
families mechanically, so that "over every rule" is a measurement rather than
a claim. Three sweeps, each perturbing one leaf at a time:

  CONST:<name>   every `def f(...) -> <num>: <literal>` def, perturbed by one
                 unit. This is the numeric table: PTE/VM/MTYPE shifts, the
                 doorbell arithmetic, the PSP fw-type ids, the smu column
                 indices, the PM4 masks, the IH masks.
  REG:<n>        `Row.of(<n>, "<field>", [<bitfields>])` -> `Row.of(<n+1>, ...)`.
                 Tests the claim "WHICH REGISTER": the row is keyed on the line
                 number, so moving the line must move the row.
  REG:<n>@name   the same def with the FIELD NAME replaced by its neighbour's.
                 Tests the claim "WHICH FIELD NAME": identical for every row in
                 the table, so it isolates the name from the register.

Each perturbation is written to a SCRATCH COPY BESIDE the real file, because the
relative imports are three levels up and a copy at any other depth cannot
resolve them. The INTERPRETED lane is re-run and the reported number is rows
MOVED.

A perturbation that moves nothing is NOT closed by adding a gate row that
encodes the bug. It is printed in the MOVES-0 section and belongs in the
blind-spot list.
"""
import io, os, re, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, 'tinybendygrad/runtime/support/am/ip.bend')
SCRATCH = os.path.join(ROOT, 'tinybendygrad/runtime/support/am/ip_scratch_sweep.bend')
BEND = os.path.join(ROOT, 'bin/bend')
RE = re.compile(r'^def ([\w.]+)\([^()]*\) -> ([^:]+): *(\S+)$')
ROW_RE = re.compile(r'^(def (amp_reg_\w+)\(\) -> Row:\s*Row\.of\()(\d+)', re.M)


def consts(src):
  """(name, literal) for every numeric-literal def."""
  out = []
  for line in src.split('\n'):
    m = RE.match(line)
    if m and re.fullmatch(r'-?\d+n?', m.group(3)):
      out.append((m.group(1), m.group(3)))
  return out


def rows(src):
  """(def name, register line, field name) for every generated register row.

  The generator wraps `Row.of(...)` onto the following line once the bitfield
  list is long, so the pattern spans the newline and the field name is read off
  the tail rather than captured.
  """
  out = []
  for m in ROW_RE.finditer(src):
    out.append((m.group(2), int(m.group(3)), re.match(r', "([^"]*)"', src[m.end():]).group(1)))
  return out


def bump(body):
  """+1 on the literal, preserving the Nat suffix. None if not perturbable."""
  m = re.fullmatch(r'(-?)(\d+)(n?)', body)
  return f'{m.group(1)}{int(m.group(2)) + 1}{m.group(3)}' if m else None


def main():
  src = io.open(SRC, encoding='utf-8').read()
  cs, rs = consts(src), rows(src)
  # The literal is its OWN capture group and the substitution rebuilds the line
  # from group 1 plus the new literal. A string `.replace` over group 1 would
  # rewrite the FIRST match of the digits, which is inside the def's own NAME
  # whenever the name ends in a digit -- `def PM4_TYPE3() -> U32: 3` would
  # become `def PM4_TYPE4() -> U32: 4`, which then reads as COMPILE-FAIL.
  muts = [(f'CONST:{n}', re.compile(rf'^(def {re.escape(n)}\([^()]*\) -> [^:]+: *)(-?\d+n?)$', re.M),
           lambda m, n=bump(v): m.group(1) + n)
          for n, v in cs if bump(v)]
  muts += [(f'REG:{d}', re.compile(rf'^(def {re.escape(d)}\(\) -> Row:\s*Row\.of\()\d+', re.M),
            lambda m, v=l: m.group(1) + str(v + 1))
           for d, l, _ in rs]
  # each row's field name is replaced by the NEXT row's, wrapping at the end
  nxt = [r[2] for r in rs[1:]] + rs[:1]
  muts += [(f'REG:{d}@name', re.compile(rf'^(def {re.escape(d)}\(\) -> Row:\s*Row\.of\(\d+, )"[^"]*"', re.M),
            lambda m, v=v: m.group(1) + f'"{v}"')
           for (d, _, _), v in zip(rs, nxt)]

  base = subprocess.run([BEND, SRC], capture_output=True, text=True)
  assert 'ip-done=1' in base.stdout, 'base lane does not reach ip-done=1'
  base_rows = base.stdout.strip().split('\n')
  print(f'base rows: {len(base_rows)}   CONST: {len(cs)}   REG rows: {len(rs)}   total: {len(muts)}')
  print('mutation|||rows moved')

  zero, cf = [], []
  try:
    for label, pat, edit in muts:
      assert pat.search(src), f'SWEEP TARGET NOT FOUND: {label}'
      io.open(SCRATCH, 'w', encoding='utf-8').write(pat.sub(edit, src, count=1))
      r = subprocess.run([BEND, SCRATCH], capture_output=True, text=True)
      if 'ip-done=1' not in r.stdout:
        print(f'{label}|||COMPILE-FAIL'); cf.append(label); continue
      n = sum(1 for a, b in zip(base_rows, r.stdout.strip().split('\n')) if a != b)
      print(f'{label}|||{n}')
      if n == 0:
        zero.append(label)
  finally:
    if os.path.exists(SCRATCH):
      os.remove(SCRATCH)

  print(f'== MOVES-0: {len(zero)}')
  for z in zero:
    print('  ', z)
  print(f'== COMPILE-FAIL: {len(cf)}')
  for c in cf:
    print('  ', c)


main()