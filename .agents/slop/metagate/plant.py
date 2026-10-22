"""THE PLANT, run against the SCRATCH copy of `tinybendygrad/tensor.bend`.

Four named failure modes, each a ONE-OR-TWO-LINE edit to the port, each
compiled and each ROW-DIFFED against the pristine output. A plant that moves
nothing is a row that cannot fail, and the task's own rule is that the arms
nobody plants are the ones that bite.

THE FOUR ARMS, from the brief:
  P1  "metadata read as absent vs set-to-None" -- and its sharpest form, an
      EMPTY-NAMED metadata read as ABSENT. THE ROW NOBODY PLANTS.
  P2  "a ContextVar read before it is set" -- the read returns a DEFAULT
      instead of the cell's state.
  P3  "a metadata key silently renamed" -- the port and CPython name the
      same method differently.
  P4  "one tensor's metadata leaking into another's" -- in its PORT form: the
      installed metadata SURVIVES the call, so the next call sees it.

The real file is NEVER edited: every plant is applied to the scratch copy, and
the scratch copy is restored from the real file between plants.
"""
import os, subprocess, sys, shutil, difflib

ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
SCRATCH = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/scratch"
RUN = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/runbend.sh"
REAL = os.path.join(ROOT, "tinybendygrad", "tensor.bend")
SCR = os.path.join(SCRATCH, "tinybendygrad", "tensor.bend")
OUT = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/metaprobe"

PLANTS = [
  ("P1", "an EMPTY-NAMED metadata is read as ABSENT (the sentinel mistake)",
   "case Some{m}: True{}\n    case None{}: False{}",
   'case Some{m}: Bool.not(String.eq(md_name(m), ""))\n    case None{}: False{}'),
  ("P2", "the ContextVar READ returns a DEFAULT instead of the cell's state",
   "def tn_meta_get(c: MetaCell) -> Maybe<&2, O.Metadata>:\n  match c:\n    case MetaCell{st}: st",
   'def tn_meta_default(st: Maybe<&2, O.Metadata>) -> Maybe<&2, O.Metadata>:\n'
   '  match st:\n'
   '    case Some{m}: Some{m}\n'
   '    case None{}: Some{O.Metadata{"default", False{}}}\n\n'
   'def tn_meta_get(+c: MetaCell) -> Maybe<&2, O.Metadata>:\n  match c:\n    case MetaCell{st}: tn_meta_default(st)'),
  ("P3", "the metadata KEY is silently renamed (the port and CPython disagree)",
   't_srow("tn_meta_enter", md_show(MetaScope.eff(tn_meta_enter(1, MetaCell{None{}}, "alu"))))',
   't_srow("tn_meta_enter", md_show(MetaScope.eff(tn_meta_enter(1, MetaCell{None{}}, "alu_v2"))))'),
  ("P4", "the installed metadata SURVIVES the call (the token is the EFFECT)",
   "def MetaScope.token(s: MetaScope) -> Maybe<&2, O.Metadata>:\n  match s:\n    case MetaScope{eff, token}: token",
   "def MetaScope.token(s: MetaScope) -> Maybe<&2, O.Metadata>:\n  match s:\n    case MetaScope{eff, token}: eff"),
]

def bend(path):
  r = subprocess.run(["sh", RUN, path], capture_output=True, text=True)
  return r.returncode, r.stdout, r.stderr

def main():
  ref_path = os.path.join(OUT, "after-bend.txt")
  ref = open(ref_path).read().splitlines()
  for tag, what, old, new in PLANTS:
    src = open(REAL).read()
    if src.count(old) != 1:
      print("%s: PATTERN NOT UNIQUE (%d) -- the plant did not run" % (tag, src.count(old)))
      continue
    open(SCR, "w").write(src.replace(old, new))
    rc, out, err = bend(SCR)
    if rc != 0:
      print("%s: COMPILE FAILED" % tag)
      print("\n".join(err.splitlines()[:12]))
      continue
    got = out.splitlines()
    moved = [l for l in difflib.unified_diff(ref, got, lineterm="", n=0)
             if l.startswith(("+", "-")) and not l.startswith(("+++", "---"))]
    print("%s  %s" % (tag, what))
    if not moved:
      print("    MOVED NOTHING  <-- the row cannot fail")
    else:
        for l in moved:
            print("    " + l)
    print("")
  shutil.copy(REAL, SCR)
  print("scratch restored from the real file")

main()
