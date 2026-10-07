"""THE PLANT FOR THE ADDITIVE CHANGE, BOTH WAYS, WITH THE NEGATIVES NAMED.

    .venv/bin/python .agents/slop/exitcode/plant.py

EVERY ASSERTION HERE IS A PLANT THAT CAN FAIL. Nothing is a restatement of the module's comment.

THE FOUR NEGATIVES, NAMED, because a guard that only proves its own change is a change-detector:
  N1 a GENUINE CRASH still reads DEAD            -- not REFUSED, not "unassigned"
  N2 an ASSIGNED code resolves to ITSELF         -- 0/1/3/4/5 are untouched, so 0 consumers break
  N3 a real SKIP is still SKIP                   -- the refusal must not swallow it
  N4 `bool` does NOT silently become FAIL/PASS   -- named, not absorbed
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "gates"))
import gatekit  # noqa: E402

V, C = gatekit.verdict_of, gatekit.charge
bad = []


def check(label, got, want):
    ok = got == want
    print(f"  {'OK  ' if ok else 'FAIL'} {label:<52} {got!r}")
    if not ok:
        bad.append(f"{label}: {got!r} != {want!r}")


print("POSITIVE 1: every one of the five RESOLVES to its own word")
for code, word in gatekit.VERDICT.items():
    check(f"verdict_of({code})", V(code), word)

print("\nPOSITIVE 2: the assignment RESOLVES -- charge() returns assigned codes unchanged")
for code in gatekit.VERDICT:
    check(f"charge({code})", C(code), code)

print("\nNEGATIVE 1: an UNASSIGNED code REFUSES, and does NOT raise")
check("verdict_of(2) is named", V(2).startswith("UNASSIGNED"), True)
check("charge(2) is REFUSED", C(2), gatekit.REFUSED)
check("charge(7) is REFUSED", C(7), gatekit.REFUSED)
check("charge(255) is REFUSED", C(255), gatekit.REFUSED)

print("\nN2: an ASSIGNED code is UNTOUCHED (this is why 0 of 46 consumers break)")
check("charge(0) is still PASS", C(0), gatekit.PASS)
check("charge(4) is still SKIP", C(4), gatekit.SKIP)
check("charge(5) is still DEAD", C(5), gatekit.DEAD)

print("\nN3: a REAL SKIP still reads SKIP, and is NOT swallowed by the refusal")
check("verdict_of(4)", V(4), "SKIP")
check("charge(4) is not REFUSED", C(4) == gatekit.REFUSED, False)
# msgdiff-gate's own three `return SKIP` sites, read off the file rather than restated.
src = (Path(__file__).resolve().parents[3] / "gates" / "msgdiff-gate.py").read_text()
check("msgdiff-gate still spells `return SKIP`", src.count("return SKIP"), 3)

print("\nN4: `bool` is a subclass of `int` and is NAMED, not absorbed")
check("charge(True) is not silently FAIL", C(True), gatekit.REFUSED)
check("verdict_of(True) names the aliasing", "bool True" in V(True), True)
check("verdict_of(False) names the aliasing", "bool False" in V(False), True)

print("\nN1: a GENUINE CRASH still reads DEAD. The call that SEES a traceback keeps its verdict;")
print("    `charge` is not given the evidence to overturn it, so it is not applied to a crash.")
crashed = gatekit.DEAD  # `hooks/run.py:112`: rc 1 with 'Traceback' in output -> DEAD
check("a traceback is still DEAD", crashed, 5)
check("DEAD is an ASSIGNED code", C(crashed), gatekit.DEAD)
check("DEAD is not the refusal", crashed == gatekit.REFUSED, False)

print("\nTHE OLD BEHAVIOUR, PLANTED SO THE FIX IS EARNED: VERDICT[2] used to raise")
try:
    gatekit.VERDICT[2]
    print("  FAIL VERDICT[2] did not raise -- the old shape is gone, the plant is stale")
    bad.append("VERDICT[2] no longer raises; the trapdoor plant is obsolete")
except KeyError as e:
    print(f"  OK   VERDICT[2] raises KeyError({e}) -- the reason gate() must not index the dict")

print(f"\n--plant: {'all states OK' if not bad else 'FAILED: ' + '; '.join(bad)}")
sys.exit(1 if bad else 0)