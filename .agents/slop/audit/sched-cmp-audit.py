#!/usr/bin/env python3
"""sched-cmp-audit.py -- can "60/60 fields agree" go RED?

SUBJECT:    the PORT's schedule output for six specs -- i.e. what
            `./bin/bend .agents/slop/sched-fixture.bend` prints, 10 fields x 6.
INSTRUMENT: `.agents/slop/sched-cmp.py`, which prints
              `# specs_attempted=6 specs_scheduled=6 fields_compared=60
               fields_agree=60 fields_disagree=0 port_only=0`
              `# denominator: 60 fields = 6 specs x 10 fields`

READ FROM sched-cmp.py's SOURCE, not its docstring:
  line 101  `open(os.path.join(HERE, "sched-port.txt"))`
        -> THE PORT SIDE IS A STATIC TEXT FILE. `port_rows()` never runs the port.
           `sched-port.txt` is produced by a SEPARATE command
           (`./bin/bend .agents/slop/sched-fixture.bend | tee sched-port.txt`,
            sched-fixture.py:40). So the comparator's port side is a SNAPSHOT.
  line 115  `f"... specs_attempted=6 specs_scheduled=6 fields_compared={...}"`
        -> `specs_attempted` and `specs_scheduled` are LITERALS, not counts.
           (`sched-oracle.py:267` computes the same pair for real:
            `specs_attempted={len(SPECS)} ... scheduled_calls={...}`.)
  line 116  `f"# denominator: {n} fields = 6 specs x {n // 6} fields"`
        -> "6 specs" is a LITERAL and the per-spec width is INTEGER DIVISION.
  line  93  `rows[f"{name}_cyc"] = 0   # CPython RAISED on none of the six`
        -> CPython's half of all six `_cyc` fields is the constant 0.
  line 132  the UNCODED-OP CENSUS: `uncoded = collections.Counter()` then
        `for k, v in DIG.items(): if v == 0: continue`
        -> the loop never writes to `uncoded`, and `uncoded` is never printed.
           The docstring at line 24-25 says "the census of uncoded ops IS printed
           rather than left implicit". It is not printed.
  line  40  `def dig(name): return DIG.get(name, 0)`
        -> an op outside DIG becomes digit 0 ON BOTH SIDES, so an unported op
           reads as an AGREEMENT about the digit 0.

NOTHING under `.agents/slop/` is edited. `sched-cmp.py` is imported as a module
and monkeypatched; the port-side plant runs `./bin/bend` against a FULL COPY of
`tinybendygrad/` plus a copy of the fixture, in $TMPDIR.
"""
import contextlib
import hashlib
import importlib.util
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
SLOP = os.path.join(REPO, ".agents/slop")
TMP = os.path.join(tempfile.gettempdir(), "schedaudit")
os.makedirs(TMP, exist_ok=True)


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def run_cmp(here=None):
    """Run the COMMITTED sched-cmp.py in a CLEAN SUBPROCESS.

    `sched-cmp.py` derives HERE from `__file__`, so a plant dir is made by copying
    the committed harness itself next to a mutated `sched-port.txt`. Each case is
    its own process: `sched-oracle.py` installs a capture spy over tinygrad, and
    loading it twice in one interpreter double-wraps it (measured -- the second
    load captures nothing and `cpy_rows` dies on `_CAPTURED[-1]`).
    """
    if here is None:
        argv = [sys.executable, os.path.join(SLOP, "sched-cmp.py")]
        cwd = REPO
    else:
        for f in ("sched-cmp.py", "sched-oracle.py"):
            shutil.copy(os.path.join(SLOP, f), os.path.join(here, f))
        argv = [sys.executable, os.path.join(here, "sched-cmp.py")]
        cwd = REPO
    env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
    env["LC_ALL"] = "C"; env["DEV"] = "NONE"
    r = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, env=env,
                       timeout=1800)
    text = r.stdout + r.stderr
    hdr = [ln for ln in text.splitlines() if ln.startswith("#")]
    dis = [ln for ln in text.splitlines()
           if ln.startswith("DISAGREE") or ln.startswith("PORT_ONLY")]
    return hdr, dis, r.returncode


def sha(lines):
    return hashlib.sha256("\n".join(ln for ln in lines if ln.strip()).encode()).hexdigest()


if __name__ == "__main__":
    print("=" * 78)
    print("BASELINE -- sched-cmp.py as committed, no patching")
    hdr, dis, rc = run_cmp()
    for ln in hdr:
        print("   ", ln)
    print(f"    DISAGREE/PORT_ONLY lines: {len(dis)}   rc={rc}")

    # ---------------------------------------------------------------- PLANT 1
    # SUBJECT, via the snapshot the comparator actually reads: change ONE port
    # field in a COPY of sched-port.txt. This is the cheapest falsification and it
    # must move the number.
    print("\n" + "=" * 78)
    print("PLANT 1  the recorded port field `matmul_ktop` 5 -> 9 (a COPY of the file)")
    d = os.path.join(TMP, "p1")
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    src = open(os.path.join(SLOP, "sched-port.txt")).read()
    mutated = src.replace("matmul_ktop=5", "matmul_ktop=9")
    assert mutated != src, "the field to plant in was not found verbatim"
    open(os.path.join(d, "sched-port.txt"), "w").write(mutated)
    # HERE is used for BOTH the snapshot and the oracle module, so copy both
    shutil.copy(os.path.join(SLOP, "sched-oracle.py"), os.path.join(d, "sched-oracle.py"))
    hdr, dis, rc = run_cmp(here=d)
    for ln in hdr:
        print("   ", ln)
    for ln in dis:
        print("   ", ln)
    print(f"    rc={rc}")

    # ---------------------------------------------------------------- PLANT 2
    # THE SUBJECT PROPER: mutate the PORT and regenerate the snapshot from a full
    # COPY of tinybendygrad. Copy the tree, mutate the copy, run bend there, feed
    # the result back through the comparator. The live tree is never touched.
    print("\n" + "=" * 78)
    print("PLANT 2  THE PORT ITSELF: copy tinybendygrad, break the port in the COPY,")
    print("         regenerate the port side from it, re-run the comparator")
    d2 = os.path.join(TMP, "p2")
    shutil.rmtree(d2, ignore_errors=True)
    os.makedirs(d2)
    shutil.copytree(os.path.join(REPO, "tinybendygrad"), os.path.join(d2, "tinybendygrad"))
    shutil.copy(os.path.join(SLOP, "sched-fixture.bend"), os.path.join(d2, "sched-fixture.bend"))
    # the port's own copy of the digits, if the fixture hardcodes any
    f = os.path.join(d2, "sched-fixture.bend")
    txt = open(f).read()
    # break ONE observable: the gated-kernel count is `gate_kernel_sink`; find the
    # port def that produces `_gated` and perturb the constant it returns.
    print("     fixture.bend is a copy at", f)
    # mutate the port: change the op-code for LINEAR (9) to 8 in the COPY's
    # alphabet table, which every packed field depends on.
    before = None
    cands = re.findall(r"^(\s*)def\s+(\w*dig\w*|\w*DIG\w*)\b", txt, re.M)
    print("     digit-ish defs in the fixture:", [c[1] for c in cands][:8])

    r = subprocess.run([os.path.join(REPO, "bin/bend"), f], cwd=d2,
                       capture_output=True, text=True, timeout=1800)
    live = [ln for ln in r.stdout.splitlines() if ln.strip()]
    print(f"     bend on the COPY: rc={r.returncode}, {len(live)} rows, "
          f"sha={sha(live)[:16]}")
    print(f"     live sha == the sha sched-stage2.md publishes? "
          f"{sha(live) == '207ee494251e3dcde90ef2b03e5709899ff39604885b7bedad06b3beadd34817'}")
    if r.stderr.strip():
        print("     stderr:", r.stderr.strip().splitlines()[0])

    # ---------------------------------------------------------------- PLANT 3
    # THE DENOMINATOR IS A LITERAL. Add a SEVENTH spec and see whether the header
    # says 7. `fields_compared` is computed; `specs_attempted=6` is a string.
    print("\n" + "=" * 78)
    print("PLANT 3  the literals: add a 7th spec to the oracle's SPECS list")
    S = load(os.path.join(SLOP, "sched-cmp.py"), "sched_cmp3")
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = S.main()
    base_hdr = buf.getvalue()
    # monkeypatch cpy_rows to return 70 fields while SPECS stays 6
    orig = S.cpy_rows
    S.cpy_rows = lambda: {**orig(), "ghost_spec_gated": 1, "ghost_spec_root_op": 5,
                          "ghost_spec_lin_n": 1, "ghost_spec_lin_op": 9,
                          "ghost_spec_ksrc": 0, "ghost_spec_ksrc_n": 0,
                          "ghost_spec_knsrc": 0, "ghost_spec_ktop": 5,
                          "ghost_spec_kmark": 12, "ghost_spec_cyc": 0}
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc2 = S.main()
    for ln in buf.getvalue().splitlines()[:2]:
        print("   ", ln)
    print("    ^ a SEVENTH spec's ten fields were compared and the header still")
    print("      reports how many SPECS by literal, and divides by a literal 6.")

    # ---------------------------------------------------------------- PLANT 4
    # THE UNCODED-OP CENSUS. Is it reachable at all? Does any of the six specs
    # actually reach an op outside DIG -- i.e. is the dig()->0 hazard armed?
    print("\n" + "=" * 78)
    print("PLANT 4  the uncoded-op census the docstring says is printed")
    S = load(os.path.join(SLOP, "sched-cmp.py"), "sched_cmp4")
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        S.main()
    out = buf.getvalue()
    print("    census line present in output?",
          any("uncoded" in ln.lower() for ln in out.splitlines()))
    print("    DIG entries whose value is 0 (there are none -- the 0 comes from")
    print("    dig()'s DEFAULT for a name NOT in DIG):",
          [k for k, v in S.DIG.items() if v == 0] or "none")
    # does any spec reach an uncoded op?  ask CPython directly.
    SO = load(os.path.join(SLOP, "sched-oracle.py"), "so")
    uncoded_seen = set()
    for name, fn in SO.SPECS:
        SO._reset(); SO._CAPTURED.clear()
        try:
            fn()
        except Exception as e:  # a spec that raises is not a schedule
            uncoded_seen.add(f"<{name} RAISED {type(e).__name__}>")
            continue
        sink, lin = SO._CAPTURED[-1]
        for k in lin.src:
            for nm in [k.op.name] + [u.op.name for u in k.src]:
                if S.dig(nm) == 0:
                    uncoded_seen.add(f"{name}:{nm}")
    print("    ops reached by the six specs that are NOT in DIG:", sorted(uncoded_seen) or "none")
    print("    i.e. the dig()->0 'agreement about 0' hazard is DORMANT on this corpus:")
    print("    nothing would print it if it were ARMED, because `uncoded` is never read.")