import os
os.environ["DEV"]="CPU"
import tinygrad, tinygrad.uop.ops as opm
print("tree:", tinygrad.__file__)
import subprocess
print("git rev:", subprocess.run(["git","rev-parse","--short","HEAD"],capture_output=True,text=True).stdout.strip())
print("AxisType members:", [(m.name, m.value) for m in opm.AxisType])
print("type:", type(opm.AxisType).__mro__[:3])
for n in ("PLACEHOLDER","REDUCE","UNROLL","LOOP","UPCAST","WEAK","DEVICE","GLOBAL","LOCAL","WARP"):
    print(f"  {n:12} upstream={hasattr(opm.AxisType,n)}")
