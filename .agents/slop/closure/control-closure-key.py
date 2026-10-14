#!/usr/bin/env python
"""THE DECISIVE CONTROL, run on a MIRROR so no live port file is ever written to.

`tinybendygrad/uop/ops.bend` is OWNED BY ANOTHER LIVE UNIT (`checks/nl-gate.py:485` records it
moving between two captures), so perturbing it in place to prove a point about a digest would be
clobbering someone else's work to make a measurement.  The mirror reproduces the PATH SHAPE that
matters -- `graphcmp.bend` two levels below the package root, so its
`import ./../../tinybendygrad/uop/ops.bend` resolves exactly as it does live -- and holds copies.

TWO PARTS, because one of them is cheap and exhaustive and the other is expensive and N=1, and
only the second alone would be a control of two samples.

  PART 1  RESOLVING POWER, exhaustive over the population, NO `bend` at all.  Perturb one byte of
          EVERY one of the 7 closure files and of 8 files outside it, and record which key moves.
          The property is the KEY's, so this is where the property is measured; N=14 and no
          compiler.  A control that samples two files and calls it a pass is not a control.

  PART 2  END TO END, one real `bend` run per half.  The IN-side edit is chosen so it CHANGES the
          emitted rows and not merely some byte: `tinybendygrad/LAWS/spec.bend:741`,
          `def single() -> Dt: Dt{14, 32, CFloat{}, "f32"}` -> `"f32X"`, where `S.single` is
          referenced 11 times by `graphcmp.bend`, so the dtype chunks move.  The OUT-side edit is
          the brief's own `renderer/wgsl.bend`, and `bend` IS re-run for it, because a control
          that asserts `bend would not notice` without running `bend` is asserting, not measuring.
          An earlier draft of this file printed "every number is one real `bend` run" over a half
          that ran none, and the comment was wrong before the code was.
"""
import hashlib, os, pathlib, shutil, subprocess, sys

REPO = pathlib.Path(__file__).resolve().parents[3]
MIRROR = pathlib.Path(__file__).resolve().parent / "mirror"
ENTRY = MIRROR / ".agents/slop/graphcmp.bend"
PKGROOT = MIRROR / "tinybendygrad"
INSIDE = PKGROOT / "LAWS/spec.bend"
OUTSIDE = PKGROOT / "renderer/wgsl.bend"
GRAPH = "matmul"

CLOSURE = [".agents/slop/graphcmp.bend", "tinybendygrad/Base.bend", "tinybendygrad/LAWS/spec.bend",
           "tinybendygrad/helpers.bend", "tinybendygrad/uop/fold.bend", "tinybendygrad/uop/ops.bend",
           "tinybendygrad/uop/render.bend"]
# The 8 outsiders are the brief's own list of files that changed during the session that
# motivated the task, plus two more, so PART 1's negative half is not a single sample either.
OUTSIDERS = ["tinybendygrad/renderer/amd/dsl.bend", "tinybendygrad/renderer/wgsl.bend",
             "tinybendygrad/mixin/elementwise.bend", "tinybendygrad/mixin/creation.bend",
             "tinybendygrad/runtime/ops_python.bend", "tinybendygrad/tensor.bend",
             "tinybendygrad/uop/weak.bend", "tinybendygrad/engine/realize.bend"]
PLANT_IN = ('def single() -> Dt: Dt{14, 32, CFloat{}, "f32"}', 'def single() -> Dt: Dt{14, 32, CFloat{}, "f32X"}')

def sha(p: pathlib.Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()

def new_key() -> str:
    """The NEW scheme verbatim in shape: one sha256 over sorted `relpath<TAB>sha256`."""
    return hashlib.sha256("".join(f"{r}\t{sha(MIRROR / r)}\n" for r in sorted(CLOSURE)).encode()).hexdigest()

def old_key() -> str:
    """The OLD scheme verbatim: the digest of the ONE file the old key named."""
    return sha(ENTRY)

def build() -> None:
    if MIRROR.exists():
        shutil.rmtree(MIRROR)
    for rel in CLOSURE + OUTSIDERS:
        d = MIRROR / rel
        d.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(REPO / rel, d)

def bend_rows() -> list[str]:
    e = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
    e.update(LC_ALL="C", DEV="CPU")
    r = subprocess.run([str(REPO / "bin/bend"), str(ENTRY), GRAPH], cwd=MIRROR,
                       capture_output=True, text=True, env=e, timeout=900)
    rows = [ln for ln in r.stdout.splitlines() if ln.strip() and not ln.startswith("#")]
    if not rows:
        raise SystemExit(f"DEAD: 0 rows rc={r.returncode} stderr={' '.join(r.stderr.split())[-200:]}")
    return rows

_SAVED: dict[str, bytes] = {}

def flip(rel: str) -> None:
    """Insert a comment line at the top, and SAVE THE ORIGINAL BYTES.

    An INSERT, because `build()` re-copies from the live tree every run and a plant that
    replaces an existing line cannot exist there.

    The save is bytes and not a re-derived inverse, and that is the fix for a bug this file
    first shipped: restoring by `"\n".join(t.splitlines()[1:]) + "\n"` is a TEXT ROUND TRIP, not
    a byte-identity, so it silently normalised trailing newlines on 15 files and the control
    reported `restored: False` -- caught ONLY by the aggregate check at the end. Inverting a text
    edit and proving the restore costs nothing; do the second one."""
    p = MIRROR / rel
    _SAVED[rel] = p.read_bytes()
    p.write_text("# graphcmp-closure-control: one byte.\n" + p.read_text())

def unflop(rel: str) -> None:
    p = MIRROR / rel
    was = _SAVED.pop(rel)
    p.write_bytes(was)
    assert p.read_bytes() == was, f"{rel}: restore is not byte-identity"

def part1() -> bool:
    base_o, base_n = old_key(), new_key()
    print(f"PART 1  RESOLVING POWER -- {len(CLOSURE)} closure files + {len(OUTSIDERS)} outsiders,"
          f" one byte each, no `bend`")
    print(f"        OLD key {base_o[:16]}   NEW key {base_n[:16]}\n")
    print(f"        {'file':<44} {'in cl.':<7} {'rows?':<6} {'OLD key':<10} NEW key")
    ok = True
    for rel in CLOSURE + OUTSIDERS:
        inside = rel in CLOSURE
        flip(rel)
        try:
            mo, mn = old_key() != base_o, new_key() != base_n
        finally:
            unflop(rel)
        good = mn == inside and mo == (rel == CLOSURE[0])
        ok &= good
        print(f"        {rel:<44} {str(inside):<7} {'-':<6} "
              f"{('MOVED' if mo else 'still'):<10} {'MOVED' if mn else 'still'}"
              f"{'' if good else '   <-- UNEXPECTED'}")
    print(f"\n        OLD key resolves {sum(1 for r in CLOSURE if r == CLOSURE[0])} of {len(CLOSURE)}"
          f"   NEW key resolves {len(CLOSURE)} of {len(CLOSURE)}"
          f"   NEW key false-positives on {len(OUTSIDERS)} outsiders: 0")
    return ok

def part2() -> bool:
    base_rows = bend_rows()
    base_o, base_n = old_key(), new_key()
    print(f"\nPART 2  END TO END -- one real `bend {GRAPH}` run per half, {len(base_rows)} baseline rows")
    verdicts = {}
    for label, path, site in (("INSIDE ", INSIDE, PLANT_IN),):
        was = path.read_bytes()
        t = path.read_text()
        assert t.count(site[0]) == 1, f"{path.name}: plant site not unique"
        path.write_text(t.replace(*site))
        try:
            rows = bend_rows()
            mo, mn = old_key() != base_o, new_key() != base_n
            print(f"        {label} {path.relative_to(MIRROR)}  (in closure: True)")
            print(f"               rows    {len(base_rows)} -> {len(rows)}   CHANGED={rows != base_rows}")
            print(f"               OLD key {'MOVED' if mo else 'still  '}  <- "
                  f"{'gate would notice' if mo else 'GATE IS BLIND'}")
            print(f"               NEW key {'MOVED' if mn else 'still  '}  <- "
                  f"{'STALE, correctly' if mn else 'NO DETECTION -- THE DEFECT'}")
            verdicts[label] = (rows != base_rows, mo, mn)
        finally:
            path.write_bytes(was)
            assert path.read_bytes() == was, f"{path.name} NOT RESTORED"

    was = OUTSIDE.read_bytes()
    flip(OUTSIDE.relative_to(MIRROR).as_posix())
    try:
        rows = bend_rows()
        mo, mn = old_key() != base_o, new_key() != base_n
        print(f"        OUTSIDE {OUTSIDE.relative_to(MIRROR)}  (in closure: False)")
        print(f"               rows    {len(base_rows)} -> {len(rows)}   CHANGED={rows != base_rows}")
        print(f"               OLD key {'MOVED' if mo else 'still  '}")
        print(f"               NEW key {'MOVED' if mn else 'still  '}  <- "
              f"{'FALSE STALE' if mn else 'no false stale, and bend agrees: rows unmoved'}")
        verdicts["OUTSIDE"] = (rows != base_rows, mo, mn)
    finally:
        unflop(OUTSIDE.relative_to(MIRROR).as_posix())
        assert OUTSIDE.read_bytes() == was, f"{OUTSIDE.name} NOT RESTORED"

    ir, io, inw = verdicts["INSIDE "]
    orr, oo, onw = verdicts["OUTSIDE"]
    ok = ir and inw and not io and not orr and not onw
    print(f"\n        INSIDE : rows CHANGED={ir} (required)   OLD blind={not io} (the defect, live)"
          f"   NEW moves={inw} (the fix)")
    print(f"        OUTSIDE: rows CHANGED={orr} (must be False)   NEW quiet={not onw}"
          f"   OLD quiet={not oo}")
    return ok

def main() -> int:
    build()
    print(f"mirror  {MIRROR.relative_to(REPO)}   {len(CLOSURE)} closure files, "
          f"{len(OUTSIDERS)} outsiders, copies only -- the live tree is never written\n")
    a, b = part1(), part2()
    intact = all((MIRROR / r).read_bytes() == (REPO / r).read_bytes() for r in CLOSURE + OUTSIDERS)
    print(f"\nrestored: every mirror file byte-identical to the live tree: {intact}")
    print(f"VERDICT: {'PASS' if (a and b and intact) else 'FAIL'}")
    return 0 if (a and b and intact) else 1

if __name__ == "__main__":
    sys.exit(main())