"""The substrate digest, and the ATTRIBUTED delta for ONE file.

Calls `checks/differ.py`'s PURE function `substrate_digest()` -- the module is imported, never
edited -- and computes the same digest twice on the SAME tree: once as the working copy stands,
and once with `tinybendygrad/tensor.bend` swapped for HEAD's bytes IN MEMORY (the entries list
is rebuilt, the file on disk is NOT touched). The difference between the two is MY change and
nothing else, even while other units are writing the tree.
"""
import hashlib, importlib.util, subprocess, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
spec = importlib.util.spec_from_file_location("differ", os.path.join(ROOT, "checks", "differ.py"))
differ = importlib.util.module_from_spec(spec)
spec.loader.exec_module(differ)

TARGET = "tinybendygrad/tensor.bend"

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

head_bytes = subprocess.run(["git", "show", "HEAD:" + TARGET], cwd=ROOT, capture_output=True, check=True).stdout
live = differ.substrate_digest()
head = digest_with(head_bytes)
print("live-digest      = %s" % live)
print("head-bytes-digest= %s" % head)
print("attributed-delta = %s" % ("MOVED" if live != head else "UNCHANGED"))
print("head-bytes len   = %d" % len(head_bytes))
