#!/usr/bin/env python3
"""EVERY DECLARING GATE'S FULL `VERDICTS`, plus the `.agents/slop` reading the brief's census
would have had.

    .venv/bin/python .agents/slop/synonyms/tables.py

`twelfth.py` showed the name<-code SHAPE is far too broad -- it reads `WARP_SIZE = 32` in
`tinygrad/llm/kernels/amd.py` as a verdict vocabulary. So the population is gates that ship a
`VERDICTS` DECLARATION, which is the marker `gate-surface.declaration()` keys on, and this
prints all of them side by side so the twelve (or the eleven) are COUNTABLE BY EYE and not
only by a program.
"""
import importlib.util
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SURFACE = ROOT / "gates" / "gate-surface.py"


def loaded(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    sf = loaded(SURFACE, "gate_surface_under_tables")
    vocab = sf.vocabulary()
    entries, _libs = sf.population(ROOT)
    print(f"OWNER gates/gatekit.py: {', '.join(f'{c}={n}' for c, n in sorted(vocab.items()))}")
    print(f"HOMES = {('checks', 'gates')}  (gates-pop.py:103 calls this A LIST)\n")
    print(f"{'GATE':46} {'DECLARED':44} RENAMED")
    print("-" * 120)
    tot = 0
    for p in sorted(entries):
        got = sf.declaration(p)
        if len(got) == 3:
            print(f"{str(p.relative_to(ROOT)):46} {'<UNPARSEABLE, 3-tuple>':44}")
            continue
        v, _p, _r, note = got
        if not isinstance(v, dict):
            continue
        bad = {int(c): (t, vocab[int(c)]) for c, t in sorted(v.items())
               if int(c) in vocab and str(t).upper() != vocab[int(c)].upper()}
        tot += len(bad)
        decl = ", ".join(f"{c}:{t}" for c, t in sorted(v.items()))
        print(f"{str(p.relative_to(ROOT)):46} {decl:44} "
              + (", ".join(f"{c} {a}->{b}" for c, (a, b) in sorted(bad.items())) or "-"))
    print("-" * 120)
    print(f"RENAMED (gate, code) pairs: {tot}")

    # The scratch tree, which the brief's census may have walked. `.agents/slop` is pruned, so
    # this is read as DATA and never proposed as a home for a gate.
    print("\nSAME READING OVER `.agents/slop` -- SCRATCH, pruned, shown because the brief's "
          "denominator is 12 and this is where a twelfth could be:\n")
    n = 0
    for dirpath, dirnames, filenames in os.walk(ROOT / ".agents" / "slop"):
        dirnames[:] = [d for d in dirnames if d != "__pycache__"]
        for fn in sorted(filenames):
            if not fn.endswith(".py"):
                continue
            p = Path(dirpath) / fn
            try:
                got = sf.declaration(p)
            except Exception as e:                        # noqa: BLE001 - a scratch file may be junk
                print(f"  {p.relative_to(ROOT)}  reader raised {type(e).__name__}: {e}")
                continue
            if len(got) == 3:
                continue
            v, _p, _r, _n = got
            if not isinstance(v, dict):
                continue
            bad = {int(c): (t, vocab[int(c)]) for c, t in sorted(v.items())
                   if int(c) in vocab and str(t).upper() != vocab[int(c)].upper()}
            if not bad:
                continue
            n += len(bad)
            print(f"  {str(p.relative_to(ROOT)):56} " + ", ".join(
                f"{c} {a}->{b}" for c, (a, b) in sorted(bad.items())))
    print(f"\n  RENAMED in .agents/slop: {n}")
    return 0


if __name__ == "__main__":
    with __import__("contextlib").suppress(KeyboardInterrupt):
        sys.exit(main())