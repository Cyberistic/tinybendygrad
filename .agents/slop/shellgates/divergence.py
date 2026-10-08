#!/usr/bin/env python3
"""HOW MANY OF THE 17 SHELL ENTRY POINTS GIVE A DIFFERENT ANSWER UNDER THE INTERPRETER THEY
DECLARE, THAN UNDER THE ONE `gates/gate-surface.py:311` WOULD USE.

    .venv/bin/python .agents/slop/shellgates/divergence.py            # rows to stdout
    .venv/bin/python .agents/slop/shellgates/divergence.py --rows out.rows

THE VERDICT IS THE TOKEN, NEVER THE EXIT CODE. Every row carries `gates/gatekit.py`'s own word
for the code (`PASS`/`FAIL`/`REFUSED`/`SKIP`/`DEAD`) and, for a code the owner does not spell,
the name of what actually happened -- 127 is `COMMAND-NOT-FOUND`, the SHELL's own fourth state,
and `gatekit.charge()` would fold it into `REFUSED`, i.e. call a gate that could not run at all
"a precondition was absent" about the TREE.

THE THREE ARMS, AND WHY THERE ARE THREE.
  SHEBANG  the interpreter the file's own `#!` line declares -- what the kernel would exec.
  BASH     the arm `.agents/slop/exitsurvey/shellentry.py:65` measured with. It is a CONTROL,
           not the truth: **8 of the 17 declare `#!/bin/zsh`**, and `bash` is not the interpreter
           any of them asked for. A control that disagrees with the subject is the point.
  PY       `.venv/bin/python <gate>`, which is exactly what `gate-surface.py:311` builds --
           `cmd = [str(PY), str(gate), *argv]`, PYTHON for every entry point in the population.

ARGV IS `[]` FOR EVERY GATE, UNIFORMLY. Giving some gates their documented argument and others
none would be a HAND LIST, and the two arms would differ by their argv rather than by their
interpreter. A gate that answers `USAGE` at `argv=[]` is recorded as `USAGE` -- that is a
statement about the invocation, not about the gate's surface, and the row says so.

EVERY RUN IS CAPPED, AND AN OVER-CAP RUN IS `SKIP`, WHICH IS NOT A PASS.
"""
from __future__ import annotations

import argparse
import contextlib
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def load(path, name):
    import importlib.util

    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


I = load(HERE / "interp.py", "interp_under_divergence")
G = load(ROOT / "gates" / "gates-pop.py", "gates_pop_under_divergence")


def run(argv0, gate, cap):
    """`(token, rc, head, secs)` for one execution. A TIMEOUT IS `SKIP` AND IS NOT A PASS:
    an unrun plant measured nothing, and this instrument refuses to call that agreement."""
    t0 = time.monotonic()
    try:
        r = subprocess.run([argv0, str(gate)], cwd=str(ROOT), capture_output=True, text=True,
                           timeout=cap, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return "SKIP", "OVER-CAP", f"over {cap}s: cost UNKNOWN, and an unrun plant is not a verdict", time.monotonic() - t0
    except OSError as e:
        return "NOT-EXECUTABLE", None, f"{type(e).__name__}: {e}", time.monotonic() - t0
    out = ((r.stdout or "") + (r.stderr or ""))
    head = next((l.strip() for l in out.splitlines() if l.strip()), "<SILENT>")
    return I.token_of(r.returncode), r.returncode, head, time.monotonic() - t0


def usage_or_silent(head):
    """Is this head a refusal to be *invoked*? Named, not scored: it is the one row shape that
    is about the harness rather than the gate, and folding it into the gate's verdict would be
    the same error as reading an interpreter error as a verdict."""
    h = head.lower()
    return any(k in h for k in ("usage:", "usage\n", "no files given", "not enough arguments"))


def main():
    ap = argparse.ArgumentParser(prog="divergence.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cap", type=float, default=90.0, help="seconds per run per arm")
    ap.add_argument("--rows", default=None, help="also write the `.rows` table here")
    ap.add_argument("--only", default=None, help="substring filter on the gate name")
    a = ap.parse_args()

    vocab = I.shipped_vocabulary()
    entries, _libs = G.discover(ROOT)
    shell = [p for p in sorted(entries) if I.declared_interpreter(p).kind == "SHELL"]
    if a.only:
        shell = [p for p in shell if a.only in str(p)]

    print(f"I  POPULATION, BY SHEBANG OVER `gates-pop.discover()`: {len(shell)} entry point(s) of "
          f"{len(entries)} declare a SHELL interpreter in their own `#!` line.")
    print(f"I  OWNER `gates/gatekit.py` VERDICT: "
          f"{', '.join(f'{c}={w}' for c, w in sorted(vocab.items()))}, and 127="
          f"{I.COMMAND_NOT_FOUND} = {I.token_of(I.COMMAND_NOT_FOUND, vocab)} -- a FOURTH kind "
          f"`charge()` folds into REFUSED.\n")
    print(f"{'GATE':26}{'SHEBANG':10}{'SHEBANG-ARM':>26}{'BASH-ARM':>22}{'PY-ARM':>16}  FLIP")
    print("-" * 100)

    rows, flips, same, skipped = [], [], [], []
    for p in shell:
        rel = str(p.relative_to(ROOT))
        d = I.declared_interpreter(p)
        sh_tok, sh_rc, sh_head, sh_s = run(d.argv0, p, a.cap)
        ba_tok, ba_rc, ba_head, _ = run("bash", p, a.cap)
        py_tok, py_rc, py_head, _ = run(I._py_interpreter(), p, a.cap)
        flip = sh_tok != py_tok
        (flips if flip else same).append(rel)
        if sh_tok == "SKIP":
            skipped.append(rel)
        rows.append((rel, d.declared, sh_tok, sh_rc, ba_tok, ba_rc, py_tok, py_rc,
                     "YES" if flip else "no", f"{sh_s:.1f}", sh_head[:90]))
        print(f"{p.name:26}{d.declared.replace('/bin/', ''):10}"
              f"{sh_tok + (f' (rc {sh_rc})' if sh_rc is not None else ''):>26}"
              f"{ba_tok + (f' (rc {ba_rc})' if ba_rc is not None else ''):>22}"
              f"{py_tok + (f' (rc {py_rc})' if ba_rc is not None else ''):>16}  "
              f"{'YES' if flip else 'no'}")
        if flip:
            print(f"{'':36}  shebang-arm said: {sh_head[:74]}")
            print(f"{'':36}  py-arm       said: {py_head[:74]}")
        if usage_or_silent(sh_head):
            print(f"{'':36}  INVOCATION: refused its OWN usage at argv=[] -- this row is about the "
                  f"invocation, not the gate's surface")
    print("-" * 100)
    print(f"I  DENOMINATOR {len(shell)} shell entry point(s): {len(flips)} FLIP between the "
          f"shebang arm and the python arm, {len(same)} AGREE.\n")

    real = [r for r in rows if r[2] != "SKIP"]
    pyth = [r for r in real if r[7] not in (None,)]
    p_shell_pass = [r for r in real if r[3] == 0 and r[7] == 1]
    print(f"I  OF THE {len(real)} THAT RAN UNDER BOTH (SKIP excluded, and SKIP is not a pass): "
          f"{len(p_shell_pass)} PASS under the declared shell and FAIL under python "
          f"({', '.join(r[0] for r in p_shell_pass) or 'none'})")
    refus = [r for r in real if r[3] == 3]
    print(f"I  REFUSED-3 VISIBLE ONLY IN THE SHELL ARM: "
          f"{sum(1 for r in refus if r[7] != 3)} of {len(refus)} ({', '.join(r[0] for r in refus) or 'none'})")
    n_sh = sum(1 for p in shell if I.declared_interpreter(p).declared.rsplit("/", 1)[-1] == "zsh")
    print(f"I  BASH-CONTROL DISAGREES WITH THE SHEBANG ON: "
          f"{sum(1 for r in real if r[2] != r[4])} of {len(real)} -- and {n_sh} of {len(shell)} "
          f"declare `#!/bin/zsh`, so `bash` was never the interpreter any of them asked for.")

    if a.rows:
        Path(a.rows).write_text(
            "gate\tshebang\tshebang_arm\tshebang_rc\tbash_arm\tbash_rc\tpy_arm\tpy_rc\tflip\ts"
            "hebang_secs\thead\n"
            + "".join("\t".join(str(c) for c in r) + "\n" for r in rows))
        print(f"\n== {len(rows)} row(s) written to {a.rows}")
    return 0


if __name__ == "__main__":
    with contextlib.suppress(KeyboardInterrupt):
        sys.exit(main())