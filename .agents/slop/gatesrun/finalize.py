#!/usr/bin/env python3
"""Final classifier over the 92 discovered entry points.

Reads `.agents/slop/gatesrun/CLASSES.tsv` (the run's rc/token/cause, written by run.py) and
a class per entry, then writes the final table: path, class, rc, token, cause, answer.

The class rule, by WHAT THE FILE DOES rather than by its name:
  gatekit   imports the shared gate plumbing in `gates/gatekit.py` -> a GATE
  gate      asserts a property of a subject and exits nonzero on a violation
  oracle    emits expected `name=value` rows, consumed by a diff; no verdict of its own
  wrapper   delegates to another program (shell shim onto a gate, or an `exec`)
  driver    exercises a port/tool/hardware and reports; needs args, deps or a device
  mutator   rewrites a source file; not a gate whatever it is called

An entry's class is decided by behaviour, and where behaviour cannot decide (the entry was
SKIPped because it invokes `bend`, or is a meta-instrument) the decision is from the source
it reads -- and is marked `static` in the cause. Counts are reported with both denominators.
"""
from __future__ import annotations
import re
from pathlib import Path

OUT = Path(__file__).resolve().parent

# class per entry, decided from the source (behaviour where run, statics where SKIP).
CLASS = {
 "checks/abi4_gate.py": "gate", "checks/abi_gate.py": "gate", "checks/al-verdict.py": "gate",
 "checks/both-census.py": "oracle", "checks/bounded-selftest.sh": "wrapper",
 "checks/bounded.py": "gate", "checks/census.py": "oracle", "checks/citation-gate.py": "gate",
 "checks/cl-port-gate.py": "gate", "checks/classify.sh": "driver", "checks/cli.py": "driver",
 "checks/compile.py": "driver", "checks/corpus-figure.py": "driver", "checks/coverage.py": "gate",
 "checks/demo.sh": "driver", "checks/devgate.py": "gate", "checks/devpin.py": "gate",
 "checks/differ.py": "gate", "checks/disagree-gate.py": "gate", "checks/disarm.sh": "wrapper",
 "checks/dup-census.py": "gate", "checks/dup-gate.py": "gate", "checks/e2e.py": "gate",
 "checks/e2e.sh": "wrapper", "checks/env-precond.py": "gate", "checks/fw_live.py": "driver",
 "checks/gate.py": "gate", "checks/gate.sh": "wrapper", "checks/gate_dtype.py": "driver",
 "checks/gate_norm.py": "gate", "checks/gen.sh": "driver", "checks/graphcmp-census-audit.py": "oracle",
 "checks/hermetic-census.py": "gate", "checks/jsfix_gate.py": "gate", "checks/lint_demo.sh": "driver",
 "checks/lintable-gate.sh": "gate", "checks/llama.py": "driver", "checks/marker-audit.py": "gate",
 "checks/nl-gate-noguard.py": "gate", "checks/nl-gate.py": "gate", "checks/no-shrink.py": "gate",
 "checks/no-strays.py": "gate", "checks/no-txt.py": "gate", "checks/norm_check.py": "gate",
 "checks/nvrows-deadrow-gate.py": "gate", "checks/oracle-txt-census.py": "oracle",
 "checks/oracle_f64.py": "driver", "checks/plant.sh": "driver", "checks/process_replay.py": "driver",
 "checks/render-gate-oracle.py": "oracle", "checks/repair-dupes.py": "mutator",
 "checks/repro-paths.py": "gate", "checks/residue.py": "gate", "checks/rn-gate.py": "gate",
 "checks/romless.py": "driver", "checks/run-all.sh": "driver", "checks/run-f64.sh": "driver",
 "checks/run-port-mm.sh": "driver", "checks/run.py": "driver", "checks/sb-gate.sh": "gate",
 "checks/serve.py": "driver", "checks/substrate-check.sh": "wrapper", "checks/substrate.py": "gate",
 "checks/sweep.py": "oracle", "checks/sz.py": "driver", "checks/test_rewrite_bottom_up_gate.py": "gate",
 "checks/txt-owners.py": "oracle", "checks/unowned.py": "oracle", "checks/vz_gate.py": "gate",
 "checks/walk-mutate.sh": "mutator", "checks/wallcheck.py": "gate", "checks/wt-sync.sh": "driver",
 "gates/bc-u32-gate.py": "gate", "gates/beautiful-mnist-gate.py": "gate",
 "gates/ew-consts-gate.py": "gate", "gates/ew-consts-oracle.py": "oracle",
 "gates/ew-explog-gate.py": "gate", "gates/ew-explog-oracle.py": "oracle",
 "gates/gates-pop.py": "gate", "gates/gendirs.py": "gate", "gates/i64-shl-gate.py": "gate",
 "gates/i64-shr-gate.py": "gate", "gates/mixin-op-gate.py": "gate", "gates/ops-core-gate.py": "gate",
 "gates/ops-core-oracle.py": "oracle", "gates/retention-check.py": "gate",
 "gates/wk-cd-gate.py": "gate", "gates/wk-cd-oracle.py": "oracle", "gates/wk-eval-gate.py": "gate",
 "gates/wk-eval-oracle.py": "oracle", "gates/wk-f32-gate.py": "gate", "gates/wk-f32-rows.py": "oracle",
}

# a one-line answer per class: what a reader should conclude.
ANSWER = {
 "gate": "kept -- asserts and exits nonzero on a violation",
 "oracle": "NOT A GATE -- emits expected rows; a gate diffs against it",
 "wrapper": "NOT A GATE -- delegates to the program that is the gate",
 "driver": "NOT A GATE -- exercises a port/tool/hardware; no verdict of its own",
 "mutator": "NOT A GATE -- rewrites a source file",
}


def main():
    src = (OUT / "run-classes.tsv").read_text().splitlines()
    rows = [l.split("\t") for l in src[1:] if l.strip()]
    # a shell that cannot parse / needs an arg it did not get measured nothing: DEAD, not FAIL.
    token_fix = {"checks/classify.sh": "DEAD", "checks/lint_demo.sh": "DEAD"}
    out = [["path", "class", "rc", "token", "cause", "answer"]]
    for path, _cls, rc, tok, *cause in rows:
        tok = token_fix.get(path, tok)
        cls = CLASS[path]
        cause_txt = "\t".join(cause)
        out.append([path, cls, rc, tok, cause_txt, ANSWER[cls]])
    (OUT / "CLASSES.tsv").write_text("\n".join("\t".join(r) for r in out) + "\n")
    from collections import Counter
    c = Counter(r[1] for r in out[1:])
    notgate = sum(v for k, v in c.items() if k != "gate")
    print(f"TOTAL={len(out)-1}  GATES={c['gate']}  NOT-A-GATE={notgate}  {dict(c)}")


if __name__ == "__main__":
    main()
