#!/usr/bin/env python3
"""Is `checks/differ.py`'s `declared()` COMPLETE? Answer by RUNNING the driver, not by reading it.

THE QUESTION NOBODY ASKED. `.agents/slop/difftxt/DECISION.md` rests the carve-out on
"103 of 103, 0 orphan match" -- which is evidence about ONE run's tree, not about the FUNCTION.
`declared()` is derived from `WANT`/`CONTROLS`/`PLANTS`/`STAB`/`LITERALS`, and a derivation can
drift from what those tables actually produce.

SO: run `cmd_run` with `D` pointed at a throwaway directory and every subprocess stubbed to
`rc=0` and 0 bytes, then enumerate what the driver WROTE and diff that against `declared()`.

Why the stub is honest here. This measures the driver's NAME REACHABILITY, not its verdicts: the
questions are "does `cmd_run` ever write a `.txt` outside `declared()`" and "does it ever declare
one it cannot write". Both are answered by which names the code path reaches, and stubbing
subprocesses removes the cost and the nondeterminism of a real 24-graph bend run. A stub that
returns `rc=0` also takes the HAPPY branch everywhere, which is the branch that produces the MOST
names -- so a name reachable only on a failure path would be missed, and the residual set below
names anything of the sort it found.

usage: .venv/bin/python .agents/slop/txtgen/declared-completeness.py

Writes nothing outside its temp directory. Exits 0 if `declared()` is exactly what the driver
writes, 1 otherwise.
"""
import importlib.util
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]


def load_differ():
    spec = importlib.util.spec_from_file_location("differ", ROOT / "checks/differ.py")
    d = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(d)
    return d


def main() -> int:
    d = load_differ()
    declared = d.declared()

    written = {}
    with tempfile.TemporaryDirectory(prefix="declared-") as td:
        d.D = pathlib.Path(td)          # every artifact write lands in the sandbox
        real_run = subprocess.run

        def stub_run(args, **kw):
            """`rc=0` and 0 bytes: the child succeeds having printed nothing."""
            sink = kw.get("stdout")
            if hasattr(sink, "write"):
                sink.write(b"")
            return subprocess.CompletedProcess(args, 0, b"", b"")

        d.subprocess.run = stub_run     # covers both `gc()` and `capture()`
        try:
            d.cmd_run(None)
        except ValueError as e:
            # ONLY the final `print(f"wrote {D.relative_to(ROOT)}")`, which cannot hold once `D`
            # is a sandbox outside the repo. Every artifact write happens BEFORE that line, so
            # the run is complete; and the message is asserted rather than swallowed, because a
            # ValueError from anywhere else would mean the measurement is not the one claimed.
            if "not in the subpath of" not in str(e):
                raise
        finally:
            d.subprocess.run = real_run
        for p in sorted(d.D.iterdir()):
            if p.is_file():
                written[p.name] = p.stat().st_size

    produced = {n for n in written if n.endswith(".txt")}
    extra = produced - declared
    missing = declared - produced

    print(f"declared()          {len(declared)}")
    print(f"produced by cmd_run {len(produced)}  (of {len(written)} files total, incl .err/.tmp)")
    print()
    print(f"PRODUCED BUT NOT DECLARED  {len(extra)}   <- each would be an UNEXCUSED .txt")
    for n in sorted(extra):
        print(f"    {n}  ({written[n]} bytes)")
    print(f"DECLARED BUT NOT PRODUCED  {len(missing)}   <- each would be an UNEXCUSED .txt")
    for n in sorted(missing):
        print(f"    {n}")
    ok = not extra and not missing
    print()
    print("VERDICT: declared() is EXACTLY what cmd_run writes." if ok
          else "VERDICT: declared() DIVERGES from what cmd_run writes.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())