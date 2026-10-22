"""The substrate digest, and the ATTRIBUTED delta for ONE file.

Calls `checks/differ.py`'s PURE function `substrate_digest()` -- the module is imported, never
edited -- and computes the same digest twice on the SAME tree: once as the working copy stands,
and once with `tinybendygrad/tensor.bend` swapped IN MEMORY for another revision's bytes (the
entries list is rebuilt, the file on disk is NOT touched). The difference between the two is
MY change and nothing else, even while other units are writing the tree.

    python digest.py [<rev>]     # <rev> supplies the "before" bytes; default HEAD

AFTER the commit, `HEAD:<target>` IS my bytes, so the default reports UNCHANGED -- which is
the right answer for "is the tree as HEAD says?" and the wrong answer for "what did I move?".
Pass the PARENT (`<rev>^`) to get the attributed delta.
"""
import hashlib, importlib.util, subprocess, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
spec = importlib.util.spec_from_file_location("differ", os.path.join(ROOT, "checks", "differ.py"))
differ = importlib.util.module_from_spec(spec)
spec.loader.exec_module(differ)

TARGET = "tinybendygrad/tensor.bend"
REV = sys.argv[1] if len(sys.argv) > 1 else "HEAD"

def digest_with(target_bytes):
  real = differ.substrate_entries
  def patched():
    out = []
    for rel, blob in real():
      out.append((rel, hashlib.sha256(target_bytes).hexdigest() if rel == TARGET else blob))
    return out
  differ.substrate_entries = patched
  try:
    return differ.substrate_digest()
  finally:
    differ.substrate_entries = real

head_bytes = subprocess.run(["git", "show", REV + ":" + TARGET], cwd=ROOT, capture_output=True, check=True).stdout
live = differ.substrate_digest()
head = digest_with(head_bytes)
print("live-digest      = %s" % live)
print("before-digest (%s)= %s" % (REV, head))
print("attributed-delta = %s" % ("MOVED" if live != head else "UNCHANGED"))
print("before bytes len  = %d" % len(head_bytes))
