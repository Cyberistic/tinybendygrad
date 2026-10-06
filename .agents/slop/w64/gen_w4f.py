#!/usr/bin/env python3
"""W-4: ONE f64 add, bit for bit against CPython.

THE QUESTION. `bend base --types` ships Nat, U32 and F32 and NO F64/I64/U64, and
every F32 arithmetic name is a `law` with no body -- F32.add is an
uninterpreted AXIOM, so Bend has no float arithmetic of its own at any width.
W-3 measured that the 64-bit CONTAINER is fine (Word(64n) does correct 64-bit
integer add). So the wall, if there is one, is about IEEE-754 SEMANTICS and not
about 64-bit width. This decides it.

HOW. The double is reassembled inside C from two U32 halves and written back out
as two U32 halves, so no `double` type ever crosses the boundary. That is what
makes this probe the answer to the brief's libclang question rather than another
instance of it.

PRE-REGISTERED EXPECTATION: CPython says
  1.5 + 2.25 = 3.75            -> 0x400E000000000000, hi=0x400E0000 lo=0x00000000
  1.0 + 0.5  = 1.5             -> 0x3FF8000000000000, hi=0x3FF80000 lo=0x00000000
  0.0 + 0.0  = 0.0             -> 0x0000000000000000, hi=0 lo=0
I EXPECT all three to match. The third row is the DISARM: a harness stuck
returning a constant would pass row one and fail rows two and three, so all
three are required. Row two is the PLANT: a different sum must move the answer.

Every expectation below is CALLED from CPython, never transcribed.
"""
import subprocess, pathlib, struct

REPO = pathlib.Path(__file__).resolve().parents[3]
OUT = REPO / ".agents/slop/w64"
BEND = REPO / "bin/bend"


def halves(x: float) -> tuple[int, int]:
    v = struct.unpack("<Q", struct.pack("<d", x))[0]
    return v >> 32, v & 0xFFFFFFFF


FIXTURES = [
    ("1.5", "2.25", 1.5, 2.25),     # the asked-for add
    ("1.0", "0.5", 1.0, 0.5),       # PLANT: a different sum must move the answer
    ("0.0", "0.0", 0.0, 0.0),       # DISARM: a constant-returning harness fails here
]

exp = []
for na, nb, a, b in FIXTURES:
    ah, al = halves(a)
    bh, bl = halves(b)
    sh, sl = halves(a + b)
    exp.append((na, nb, ah, al, bh, bl, sh, sl, a + b))
    print(f"# {na}+{nb} = {a + b!r}  operands {ah:#010x}/{al:#010x} "
          f"{bh:#010x}/{bl:#010x}  sum {sh:#010x}/{sl:#010x}")

body = ['''import Base

# THE FOREIGN-DEF SHAPE, measured the hard way. A `.c` effect source is bound
# by an UNTYPED `def`; the types live on a separate `law` of the same name.
# A typed `def ... -> IO(U32)` with a `.c` import is rejected with "a foreign
# def without a .js import", and a `.js` effect source must call
# io_eff(CID(name), name_run, need) itself. And a foreign def cannot be RUN by
# `bend <file>` at all: it needs `bend <file> -o out.c` and then `cc`.
law f64_add:
  U32 -> U32 -> U32 -> U32 -> IO(U32)

def f64_add(a, b, c, d):
  import "./f4_add.c"

law f64_add_lo:
  IO(U32)

def f64_add_lo():
  import "./f4_add.c"

def main() -> IO(Unit):
  do IO<Unit>:
''']
for i, (na, nb, ah, al, bh, bl, sh, sl, _) in enumerate(exp):
    # No Nat->U32 coercion exists: `(0n : U32)` gives "expected : U32 / observed
    # : Nat" pointing at the literal. U32.from_nat is the only route, and being
    # a def it cannot be bound inside a `do` block -- it goes inline.
    body.append(f'    h{i} : U32 <- f64_add(U32.from_nat({ah}n), U32.from_nat({al}n),'
                f' U32.from_nat({bh}n), U32.from_nat({bl}n))\n')
    body.append(f'    l{i} : U32 <- f64_add_lo()\n')
for i, (_, _, _, _, _, _, sh, sl, _) in enumerate(exp):
    body.append(f'    IO.print("W-4 row{i} hi=" ++ Nat.show(U32.to_nat(h{i}))'
                f' ++ " lo=" ++ Nat.show(U32.to_nat(l{i})))\n')

(OUT / "w4_f64add.bend").write_text("".join(body))
print()

import os
gen_c = OUT / "w4.gen.c"
r = subprocess.run([str(BEND), str(OUT / "w4_f64add.bend"), "-o", str(gen_c)],
                   capture_output=True, text=True)
if r.returncode != 0:
    print("bend -o failed:")
    for line in (r.stdout + r.stderr).splitlines():
        if line.strip() and "available: run bend update" not in line:
            print(line)
    raise SystemExit(1)
exe = OUT / "w4.out"
c = subprocess.run(["cc", str(gen_c), "-o", str(exe)], capture_output=True, text=True)
if c.returncode != 0:
    print("cc failed:")
    for line in (c.stdout + c.stderr).splitlines()[:20]:
        print(line)
    raise SystemExit(1)
r = subprocess.run([str(exe)], capture_output=True, text=True)
out = [l for l in (r.stdout + r.stderr).splitlines() if l.strip()]
for line in out:
    print(line)
print(f"rc={r.returncode}")

rows = {}
for line in out:
    if line.startswith("W-4 row") and "hi=" in line:
        parts = dict(p.split("=", 1) for p in line.split(" ", 2)[2].split(" "))
        rows[line.split(" ")[1]] = (int(parts["hi"]), int(parts["lo"]))

print("--- gate (all three rows required: row0 alone cannot fail a constant) ---")
checks = []
for i, (na, nb, _, _, _, _, sh, sl, _) in enumerate(exp):
    got = rows.get(f"row{i}")
    ok = got == (sh, sl)
    checks.append(ok)
    print(f"{'PASS' if ok else 'FAIL'}  row{i} {na}+{nb}: got {got} want {(sh, sl)}")
print(f"{'PASS' if r.returncode == 0 else 'FAIL'}  bend exited 0 (got {r.returncode})")
(OUT / "w4_f64add.out.txt").write_text(
    "# ./bin/bend .agents/slop/w64/w4_f64add.bend\n"
    + "\n".join(f"# {na}+{nb} -> hi={sh:#010x} lo={sl:#010x} (CPython)"
                for na, nb, _, _, _, _, sh, sl, _ in exp)
    + "\n" + "\n".join(out) + "\n")
raise SystemExit(0 if all(checks) and r.returncode == 0 else 1)