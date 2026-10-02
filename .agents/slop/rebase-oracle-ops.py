#!/usr/bin/env python3
"""rebase-oracle-ops.py -- the row source `rebase-gate.py` needs for `uop/ops.bend`.

WHY A WRAPPER AND NOT `ops-oracle.py` ITSELF. `ops-oracle.py` is a REAL oracle and it is
already wired to `ops-gate.sh`, which is the gate that found four wrong `AxisType.value`s
and an inverted `axis_id`/`axis_type`. It cannot be handed to `rebase-gate.py` raw, and the
reason is specific and measured:

    5 of the 76 rows it emits DISAGREE with `uop/ops.bend`, and all 5 are `rngarg_*`.

`ops-gate.sh` already knows this and already resolves it: `rngarg_*` is the `ARange` FIELD
ORDER, the pin's `(ids, at)` against upstream's `(at, ids)`. Eleven committed files
destructure `ARange` positionally, so the order cannot move in one file. `ops-gate.sh`
handles it by filtering those rows OUT, by a prefix list the ORACLE ITSELF prints as
`#bend_only_<prefix>=<reason>`.

So the filter belongs here for the same reason it belongs there, and it is DERIVED, never
typed: a row family that gains a `#bend_only_` reason gains a filter entry without anyone
editing this file. Typing the list would make the two drift, and a stale filter is a gate
that silently stops comparing.

THE THREE STATES THIS FILE CAN REPORT, because an oracle that only agrees is not an oracle:

    dead lane      the inner oracle exited non-zero            -> exit 1, reason on stderr
    empty output   the inner oracle printed no name=value rows -> exit 1, named as EMPTY
    agreement      surviving rows printed                      -> exit 0

The remaining three states (no shared row name, a shared name that differs, a malformed
baseline) belong to the DIFFER, not to a row source, and `rebase-gate-selftest.py` drives
all six against this file's own output.

    DEV=NULL .venv/bin/python .agents/slop/rebase-oracle-ops.py
"""
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
INNER = HERE / "ops-oracle.py"
PY = REPO / ".venv" / "bin" / "python"


def rows(text):
  """`name=value` rows, keyed on the WHOLE LINE's name. Index-keyed harnesses have lied
  in this repo twice; this one is the gate's own `rows()` and shares its code path."""
  out = {}
  for line in text.splitlines():
    if "=" in line and not line.startswith("#"):
      k, v = line.split("=", 1)
      out[k.strip()] = v.strip()
  return out


def bend_only_prefixes(text):
  """The `#bend_only_<prefix>=<reason>` families, read out of the ORACLE'S OWN OUTPUT.

  A typed list would be a second copy of a judgement that lives in the oracle, and the two
  would drift. Reading it back is the whole reason the oracle prints it."""
  out = {}
  for line in text.splitlines():
    if line.startswith("#bend_only_") and "=" in line:
      pfx, _, why = line[len("#bend_only_"):].partition("=")
      out[pfx.strip()] = why.strip()
  return out


def main():
  if not PY.exists():
    print(f"rebase-oracle-ops: NO VENV at {PY}; an oracle needs the tree's CPython",
          file=sys.stderr)
    return 2
  c = subprocess.run([str(PY), str(INNER)], cwd=REPO, capture_output=True, text=True,
                     env=dict(os.environ, DEV="NULL"))
  if c.returncode != 0:
    print(f"rebase-oracle-ops: DEAD LANE -- {INNER.name} exited {c.returncode}",
          file=sys.stderr)
    print((c.stderr or c.stdout)[-1500:], file=sys.stderr)
    return c.returncode or 1

  everything = rows(c.stdout)
  if not everything:
    print(f"rebase-oracle-ops: EMPTY OUTPUT -- {INNER.name} exited 0 and printed no "
          "`name=value` row, so this file would agree with nothing", file=sys.stderr)
    return 1

  pfx = bend_only_prefixes(c.stdout)
  if not pfx:
    # Not fatal: with no bend-only families the filter is the identity and the comparison
    # is strictly larger. But a filter that silently became a no-op is exactly the shape of
    # bug this repo keeps shipping, so it is said out loud.
    print("#rebase_no_bend_only_families=the inner oracle printed no #bend_only_ line; "
          "nothing was filtered, so this run compares MORE rows than ops-gate.sh")

  kept = {k: v for k, v in everything.items() if not any(k.startswith(p) for p in pfx)}
  dropped = sorted(set(everything) - set(kept))
  # Provenance as DATA, so a reader of the raw output can see what was dropped and why.
  print(f"#rebase_inner=ops-oracle.py  inner_rows={len(everything)} "
        f"bend_only_families={len(pfx)} filtered={len(dropped)} kept={len(kept)}")
  for k, v in sorted(kept.items()):
    print(f"{k}={v}")
  return 0


if __name__ == "__main__":
  sys.exit(main())