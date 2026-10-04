#!/usr/bin/env python3
"""W-4: ONE f64 add, or the measured wall.

THE QUESTION. `bend base --types` ships Nat, U32 and F32 and NO F64/I64/U64.
Every F32 arithmetic name is declared as a `law` with no body -- F32.add is an
uninterpreted AXIOM, not a computation. So Bend has no float arithmetic of its
own at any width. W-3 established that the 64-BIT CONTAINER is fine: Word(64n)
is a Bool list with working add/sub/mul/shl/cmp, and `type F64 is Data:
F64{data: Word(64n)}` typechecks as a user declaration. So if f64 add is
blocked, it is blocked by the ABSENCE OF IEEE-754 SEMANTICS, not by the absence
of 64 bits. This probe measures which.

The foreign symbol must be spelled exactly like the Bend def, so each shape
gets its OWN C file -- sharing one C file would have made every shape fail for
a name-mismatch reason and told me nothing.

  SHAPE A  law f4add: ... import "./f4_a.c"
      EXPECTATION: REFUSED. A law is a proved total function; a foreign import
      inside one should not be admissible. If this COMPILES then f64 add is a
      handful of lines and the "no f64 in Bend" story collapses -- the outcome
      worth being wrong about.

  SHAPE B  def f4add(...) with C `double f4add(double, double)`
      EXPECTATION: this is the brief's claim generalised from libclang. Not
      inherited -- measured. The Bend-side signature has to be Word(64n)
      because Bend has no `double` type to declare, so a rejection here would
      be ambiguous between "no double" and "signature mismatch"; that ambiguity
      is why SHAPE C exists.

  SHAPE C  def f4add(...) with C `u64 f4add(u64, u64)`, the double living only
      inside the C body as a local.
      EXPECTATION: COMPILES AND RUNS. This is the row that decides the wall. If
      C passes, 64-bit transport works and the ONLY missing thing is float
      semantics -- and the f64 add is a C function, not a Bend defect.

CPython ground truth, computed not transcribed.
"""
import subprocess, pathlib, struct

REPO = pathlib.Path(__file__).resolve().parents[3]
OUT = REPO / ".agents/slop/w64"
BEND = REPO / "bin/bend"

A_BITS = struct.unpack("<Q", struct.pack("<d", 1.5))[0]
B_BITS = struct.unpack("<Q", struct.pack("<d", 2.25))[0]
S_BITS = struct.unpack("<Q", struct.pack("<d", 1.5 + 2.25))[0]
EXP_LSB = "".join("1" if (S_BITS >> i) & 1 else "0" for i in range(64))
print(f"# CPython: 1.5={A_BITS:#018x} 2.25={B_BITS:#018x} sum={S_BITS:#018x} "
      f"value={1.5 + 2.25!r}")
print(f"# CPython: expected LSB-first bits = {EXP_LSB}")
print()


def wl(v: int) -> str:
    return f"def w{v:016x}() -> Word(64n):\n  " + _wl(v) + "\n"


def _wl(v: int) -> str:
    s = "WNil{}"
    for i in range(63, -1, -1):
        s = f"WCon{{{'True{}' if (v >> i) & 1 else 'False{}'}, {s}}}"
    return s


# The 64-deep WCon spine is emitted into NAMED defs rather than inlined at the
# call site. Inlined, every compile error printed a 4000-character literal and
# buried the one line that mattered; three of this unit's bugs were only
# identifiable because the error tail was still on screen.
FIXTURES = (
    f"def wa() -> Word(64n):\n  {_wl(A_BITS)}\n\n"
    f"def wb() -> Word(64n):\n  {_wl(B_BITS)}\n\n"
)


COMMON = '''import Base

type F64 is Data:
  F64{data: Word(64n)}

def bch(b: Bool) -> Char:
  match b:
    case False{}:
      Chr{U32.from_nat(48n)}
    case True{}:
      Chr{U32.from_nat(49n)}

def bits(k: Nat, w: Word(k)) -> String:
  match k:
    case 0n:
      ""
    case 1n+kk:
      match w:
        case WCon{b, t}:
          Char.show(bch(b)) ++ bits(kk, t)

'''

(OUT / "f4_b.c").write_text(
    'double f4add(double a, double b) { return a + b; }\n')
(OUT / "f4_c.c").write_text('''typedef unsigned long long u64;
u64 f4add(u64 a, u64 b) {
  double x, y, z; u64 r;
  __builtin_memcpy(&x, &a, 8);
  __builtin_memcpy(&y, &b, 8);
  z = x + y;
  __builtin_memcpy(&r, &z, 8);
  return r;
}
''')
(OUT / "f4_a.c").write_text(
    'typedef unsigned long long u64;\nu64 f4add(u64 a, u64 b);\n')

# SHAPE B: a foreign def must import a .js file, not a .c one. Measured:
# `import "./f4_b.c"` on a `def` gives "a foreign def without a .js import".
# So the question "does double survive the FFI" is asked in JS, which is where
# a double is actually native -- a JS Number IS an IEEE-754 binary64.
(OUT / "f4_b.js").write_text('''// Operands arrive as 64-bit LSB-first bit lists; the double lives only inside.
export function f4add(a, b) {
  const x = bitsToF64(a);
  const y = bitsToF64(b);
  return f64ToBits(x + y);
}

function bitsToF64(bits) {
  // bits is an array of Bool in LSB-first order.
  let v = 0n;
  for (let i = bits.length - 1; i >= 0; i--) {
    v = (v << 1n) | (bits[i] ? 1n : 0n);
  }
  const buf = new ArrayBuffer(8);
  new DataView(buf).setBigUint64(0, v, true);
  return new DataView(buf).getFloat64(0, true);
}

function f64ToBits(x) {
  const buf = new ArrayBuffer(8);
  new DataView(buf).setFloat64(0, x, true);
  let v = new DataView(buf).getBigUint64(0, true);
  const out = new Array(64);
  for (let i = 0; i < 64; i++) { out[i] = (v & 1n) === 1n; v >>= 1n; }
  return out;
}
''')

results = {}


def run(name: str, src: str) -> None:
    (OUT / name).write_text(src)
    print(f"=== {name} ===")
    r = subprocess.run([str(BEND), str(OUT / name)], capture_output=True, text=True)
    body = [l for l in (r.stdout + r.stderr).splitlines()
            if l.strip() and "available: run bend update" not in l]
    for line in body:
        print("  " + line)
    print(f"  rc={r.returncode}")
    results[name] = (r.returncode, "\n".join(body))
    print()


run("w4_a_law.bend", COMMON + '''law f4add:
  for a: F64
  for b: F64
  F64
  import "./f4_a.c"

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("W-4 A unreachable")
''')

run("w4_b_double.bend", COMMON + FIXTURES + '''def f4add(a: Word(64n), b: Word(64n)) -> IO(Word(64n)):
  import "./f4_b.js"

def main() -> IO(Unit):
  do IO<Unit>:
    r : Word(64n) <- f4add(wa(), wb())
    IO.print("W-4 B sum =" ++ bits(64n, r))
''')

run("w4_c_bits.bend", COMMON + FIXTURES + '''def f4add(a: Word(64n), b: Word(64n)) -> IO(Word(64n)):
  import "./f4_c.js"

def main() -> IO(Unit):
  do IO<Unit>:
    r : Word(64n) <- f4add(wa(), wb())
    IO.print("W-4 C sum =" ++ bits(64n, r))
''')

print("--- gate ---")
rc, body = results["w4_c_bits.bend"]
got = next((l.split("=", 1)[1].strip() for l in body.splitlines()
            if l.startswith("W-4 C sum")), "")
print(f"{'PASS' if rc == 0 and got == EXP_LSB else 'FAIL'}  "
      f"SHAPE C returns CPython's 1.5+2.25 bit pattern")
print(f"  got    = {got}")
print(f"  expect = {EXP_LSB}")
(OUT / "w4_c_bits.out.txt").write_text(
    f"# ./bin/bend .agents/slop/w64/w4_c_bits.bend\n"
    f"# 1.5={A_BITS:#018x} 2.25={B_BITS:#018x} 1.5+2.25={S_BITS:#018x} (CPython)\n"
    + body + "\n")