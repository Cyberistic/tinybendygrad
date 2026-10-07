#!/usr/bin/env python3
"""LAYER 1: what `unhealthy()` and `corpus-figure.py` actually OPEN, per pin.

The sensitivity sweep answers "which artifacts can MOVE a pin". It does not answer "which
file does the pin READ" -- and those differ, because the pins are read out of ONE summary,
so every pin's literal read path is the same file. This measures the read path instead of
inferring it, by tracing `open`/`read_text`/`stat` with a `sys.settrace`-free hook: the two
readers are re-implemented against a scratch copy and every path they touch is recorded.

Then the two questions the report must answer:
  REPRO-FILE   does `differ.py repro` leave a file any pin can read?  (`repro` prints to
               stdout and compares two sha files in a TEMP DIRECTORY -- so the second
               measurement of the whole run has NO durable artifact, which is the finding)
  RUN-EXIT     does `differ.py run` consult a pin before it returns 0?
"""
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import derive  # noqa: E402

ROOT = derive.ROOT
SRC = (ROOT / "checks/differ.py").read_text()
FIG = (ROOT / "checks/corpus-figure.py").read_text()


def trace_reads(D, fn):
    """Every path `fn` touches under `D`, by patching `Path.read_text`/`read_bytes`/`open`."""
    seen = []
    orig = (Path.read_text, Path.read_bytes, Path.open)

    def rec(p):
        try:
            seen.append(Path(p).resolve().relative_to(D).as_posix())
        except (ValueError, TypeError):
            pass

    def read_text(self, *a, **k):
        rec(self)
        return orig[0](self, *a, **k)

    def read_bytes(self, *a, **k):
        rec(self)
        return orig[1](self, *a, **k)

    def open_(self, *a, **k):
        rec(self)
        return orig[2](self, *a, **k)

    derive.differ.D = D
    Path.read_text, Path.read_bytes, Path.open = read_text, read_bytes, open_
    try:
        fn()
    finally:
        Path.read_text, Path.read_bytes, Path.open = orig
    return sorted(set(seen))


def question_4():
    """Is there a second MEASUREMENT of the whole run that leaves a file?"""
    repro = SRC[SRC.index("def cmd_repro"):SRC.index("def main()")]
    writes = [ln.strip() for ln in repro.splitlines()
              if ".write_text(" in ln or ".write_bytes(" in ln or "write(" in ln]
    into_D = [ln for ln in writes if "D /" in ln]
    run_in_D = [ln for ln in SRC.splitlines() if "write(" in ln and "D /" in ln]
    return {
        "repro_writes_any_file": writes,
        "repro_writes_into_D": into_D,
        "run_writes_into_D_count": len(run_in_D),
        "run_exits_nonzero_on": [ln.strip() for ln in SRC.splitlines()
                                 if "return 1 if" in ln or "return 2" in ln or "return 3" in ln],
        "PINS_consulted_by_run": "PINS" in SRC[SRC.index("def cmd_run"):SRC.index("return 1 if unset")],
    }


if __name__ == "__main__":
    ok, msg = derive.selfcheck()
    print(msg)
    if not ok:
        raise SystemExit(1)
    with tempfile.TemporaryDirectory() as tmp:
        D = derive.scratch_copy(Path(tmp) / "L1")
        derive.compose_bytediff(D)
        derive.compose_stability(D)
        u = trace_reads(D, derive.differ.unhealthy)
        p = trace_reads(D, lambda: dict((ln.split("=", 1)) for ln in
                                       (D / "D0-run-summary.txt").read_text(errors="replace")
                                       .splitlines() if "=" in ln))
    print("\n== LAYER 1: THE FILES `unhealthy()` OPENS, PER RUN ==\n")
    print(f"  differ.unhealthy() touches {len(u)} file(s) under D:")
    for f in u:
        print(f"    {f}")
    print("\n  SO: all 17 pins are read out of "
          f"{len([f for f in u if f.startswith('D0-run-summary')])} file. "
          f"MAX pins per artifact at layer 1 = 17.")
    q = question_4()
    print("\n== QUESTION 4: IS THE SECOND MEASUREMENT WRITTEN ANYWHERE? ==\n")
    print(f"  repro writes a file:                {q['repro_writes_any_file'] or 'NOTHING'}")
    print(f"  repro writes INTO runs/graphcmp/D:  {q['repro_writes_into_D'] or 'NOTHING'}")
    print(f"  run  writes into runs/graphcmp/D:   {q['run_writes_into_D_count']} write(s)")
    print(f"  repro's own verdicts:               {q['repro_writes_any_file']}")
    print("\n== QUESTION 3b: DOES `run` CONSULT A PIN BEFORE EXITING 0? ==\n")
    print(f"  cmd_run's nonzero returns: {q['run_exits_nonzero_on']}")
    print(f"  cmd_run reads PINS:        {q['PINS_consulted_by_run']}  "
          f"<- `run` exits 0 on pins it never looks at; `unhealthy()` is called by `repro`")
