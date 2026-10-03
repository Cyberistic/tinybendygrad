"""How many of bend_e2e.py's fixtures actually invoke BendRenderer.render?

A fixture built from CONSTANTS (T([...]), arange(...)) is constant-folded by tinygrad, so no
kernel is rendered and the fixture gates nothing through the BEND renderer -- while still printing a
correct answer. That is a VACUOUS fixture: it passes, and it would pass if the renderer were broken.
"""
import sys, io, contextlib
sys.path.insert(0, ".")

from tinygrad import Device
R = type(Device["BEND"].renderer)
n = {"c": 0}
_orig = R.render
def _spy(self, *a, **k):
    n["c"] += 1
    return _orig(self, *a, **k)
R.render = _spy

sys.argv = ["bend_e2e.py"]
buf = io.StringIO()
try:
    with contextlib.redirect_stdout(buf):
        exec(open(".agents/slop/bend_e2e.py").read(), {"__name__": "__main__", "__file__": ".agents/slop/bend_e2e.py"})
except SystemExit:
    pass
except Exception as e:
    print(f"  (harness raised {type(e).__name__}: {str(e)[:70]})")

out = buf.getvalue()
cases = [l for l in out.splitlines() if "=" in l and not l.strip().startswith("#")]
print(f"  BendRenderer.render calls during the WHOLE artefact: {n['c']}")
print(f"  lines the artefact printed                          : {len(cases)}")
print("\n  first 12 lines of artefact output:")
for l in out.splitlines()[:12]:
    print("   ", l[:92])