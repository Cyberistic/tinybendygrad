"""Re-derive the three port-population numbers BY DISCOVERY. No literals.
Rule for the volume ratio is stated here once and applied to both sides:
  non-comment line = a line whose `strip()` is non-empty and does not start with '#'."""
import os, sys, pathlib, importlib.util

ROOT = pathlib.Path(__file__).resolve().parents[3]
os.chdir(ROOT)

def nondir_lines(path):
    try:
        return path.read_text(errors="replace").splitlines()
    except OSError:
        return []

def noncomment(paths):
    n = 0
    for p in paths:
        for ln in nondir_lines(p):
            s = ln.strip()
            if s and not s.startswith("#"):
                n += 1
    return n

def walk(root, suffix=None):
    out = []
    for dp, _d, fs in os.walk(root):
        for f in fs:
            if suffix is None or f.endswith(suffix):
                out.append(pathlib.Path(dp) / f)
    return sorted(out)

# 1. find tinybendygrad -name '*.bend'
bend = walk("tinybendygrad", ".bend")
print("N1 find tinybendygrad -name '*.bend' =", len(bend))

# 2. checks/sweep.py port_files() -- RUN it, not a literal
spec = importlib.util.spec_from_file_location("sweep", "checks/sweep.py")
sweep = importlib.util.module_from_spec(spec); spec.loader.exec_module(sweep)
pf = sweep.port_files()
print("N2 sweep.port_files() =", len(pf))

# 3. volume ratio
port_files_all = walk("tinybendygrad")  # all files, but the ratio method is port-pop
pin = [p for p in walk("tinygrad", ".py") if "/test/" not in str(p) and not str(p).startswith("tinygrad/test")]
port_nc = noncomment(bend)
pin_nc = noncomment(pin)
print("N3 port non-comment (.bend) =", port_nc, "of", sum(len(nondir_lines(p)) for p in bend))
print("N3 pin non-comment (tinygrad/**.py excl test/) =", pin_nc)
print("N3 ratio = %.2f%%" % (100.0*port_nc/pin_nc))
# alt: all files under port, non-comment
port_all_nc = noncomment(port_files_all)
print("N3-alt port all-files non-comment =", port_all_nc, "ratio %.2f%%" % (100.0*port_all_nc/pin_nc))
# relocated (4 moved) non-comment
rel = walk(".agents/slop/portzz/relocated", ".bend")
print("relocated non-comment =", noncomment(rel), "files", len(rel))
