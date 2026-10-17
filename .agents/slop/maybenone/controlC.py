#!/usr/bin/env python3
r"""CONTROL C, THE ONE THAT USES THE COMPILER.  The seven entries whose `find` still matches,
and nothing else -- so the run has no refusal and no unexpected zero and MUST exit PASS(0).
If it did not, the fix would be "always red" and the real run's 3 would prove nothing."""
import importlib.util, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
s = importlib.util.spec_from_file_location("hc", ROOT / "gates/optim-nop-mutate.py")
m = importlib.util.module_from_spec(s); sys.modules["hc"] = m; s.loader.exec_module(m)
GOOD = {"M1", "M2", "M3", "M4", "P1", "P3", "Z2"}
m.MUTATIONS = [e for e in m.MUTATIONS if e[0].split()[0] in GOOD]
rc = m.main()
print(f"CONTROL C: {len(GOOD)} entries, no stale pattern -> rc={rc} "
      f"{m.gatekit.VERDICT.get(rc, 'UNASSIGNED')}", file=sys.stderr)
sys.exit(0 if rc == 0 else 1)
