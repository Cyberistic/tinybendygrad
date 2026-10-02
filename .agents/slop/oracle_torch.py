#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/nn/torch.bend -- prints the SAME rows the
Bend gate prints, so `diff` is the third lane. Run from the repo root:

    python3 .agents/slop/oracle_torch.py
"""
import sys, pathlib
sys.path.insert(0, '.')

PARENT_DEPTH = 2
MODULE_NAME = "extra.torch_backend.backend"
MSG_HEAD = "torch frontend not in release"
MSG_TAIL = "To fix, install tinygrad from a git checkout with pip install -e ."
MSG = MSG_HEAD + "\n" + MSG_TAIL
MSG_NEWLINE_AT = 29
MSG_LINES = 2
CALL_PATH_APPEND, CALL_IMPORT, CALL_RAISE = 0, 1, 2
FROM_E = 1


def as_posix(s):
  return s.replace("\\", "/")


def root_of(f):
  return as_posix(pathlib.Path(f).parent.parent.as_posix())


def run(f, ok):
  """nn/torch.py:3-5 as the port models it. Truncated at the raise."""
  tr = [(CALL_PATH_APPEND, 0), (CALL_IMPORT, 0)]
  if not ok:
    tr = tr + [(CALL_RAISE, FROM_E)]
  return [root_of(f)], tr, (not ok)


def has(tr, pat):
  """a real subsequence test -- ops_webgpu's Tr.has, with the fuel bug FIXED."""
  n = 0
  for c in tr:
    if n < len(pat) and c == pat[n]:
      n += 1
  return n == len(pat)


def cnt(tr, k):
  return sum(1 for c in tr if c[0] == k)


def args(tr, k):
  return [c[1] for c in tr if c[0] == k]


R = []
p, t, ref = run("tinygrad/nn/torch.py", True)
b, tb, refb = run("tinygrad/nn/torch.py", False)

R.append(("torch_root_rel", root_of("tinygrad/nn/torch.py")))
R.append(("torch_root_abs", root_of("/abs/tinygrad/nn/torch.py")))
R.append(("torch_root_deep", root_of("a/b/c/d.py")))
R.append(("torch_root_one", root_of("torch.py")))
R.append(("torch_root_two", root_of("nn/torch.py")))
R.append(("torch_root_rooted", root_of("/torch.py")))
R.append(("torch_depth", str(PARENT_DEPTH)))
R.append(("torch_root_is_prefix", "True" if root_of("/abs/tinygrad/nn/torch.py").startswith("/") else "False"))
R.append(("torch_posix_posix", as_posix("a/b/c.py")))
R.append(("torch_posix_win", as_posix("a\\b\\c.py")))
R.append(("torch_posix_mixed", as_posix("C:\\x/y\\z.py")))
R.append(("torch_posix_idem", "True" if as_posix(root_of("tinygrad/nn/torch.py")) == "tinygrad" else "False"))
R.append(("torch_has_rejects_reverse", "True" if not has(t, [(CALL_IMPORT, 0), (CALL_PATH_APPEND, 0)]) else "False"))
R.append(("torch_has_rejects_absent", "True" if not has(t, [(CALL_RAISE, FROM_E)]) else "False"))
R.append(("torch_order", "True" if has(t, [(CALL_PATH_APPEND, 0), (CALL_IMPORT, 0)]) else "False"))
R.append(("torch_order_rev", "True" if not has(t, [(CALL_IMPORT, 0), (CALL_PATH_APPEND, 0)]) else "False"))
R.append(("torch_n_ok", str(len(t))))
R.append(("torch_append_n", str(cnt(t, CALL_PATH_APPEND))))
R.append(("torch_import_n", str(cnt(t, CALL_IMPORT))))
R.append(("torch_raise_n_ok", str(cnt(t, CALL_RAISE))))
R.append(("torch_refused_ok", "True" if not ref else "False"))
R.append(("torch_dep_y", "True" if PARENT_DEPTH == 2 else "False"))
R.append(("torch_n_bad", str(len(tb))))
R.append(("torch_raise_n_bad", str(cnt(tb, CALL_RAISE))))
R.append(("torch_refused_bad", "True" if refb else "False"))
R.append(("torch_raise_last", "True" if has(tb, [(CALL_IMPORT, 0), (CALL_RAISE, FROM_E)]) else "False"))
R.append(("torch_raise_arg", str(args(tb, CALL_RAISE)[0] if args(tb, CALL_RAISE) else 0)))
R.append(("torch_import_survives", str(cnt(tb, CALL_IMPORT))))
R.append(("torch_path_n", str(len(p))))
R.append(("torch_path_0", p[0]))
R.append(("torch_path_is_root", "True" if p[0] == "tinygrad" else "False"))
R.append(("torch_path_not_the_parent", "True" if p[0] != "tinygrad/nn" else "False"))
R.append(("torch_path_is_one_level_up", "True" if p[0] == "tinygrad" else "False"))
R.append(("torch_msg_head", MSG_HEAD))
R.append(("torch_msg_tail", MSG_TAIL))
R.append(("torch_msg_lines", str(len(MSG.split("\n")))))
R.append(("torch_msg_lines_expect", str(MSG_LINES)))
R.append(("torch_msg_nl", str(len(MSG_HEAD))))
R.append(("torch_msg_nl_expect", str(MSG_NEWLINE_AT)))
R.append(("torch_msg_has_nl", "True" if "\n" in MSG else "False"))
R.append(("torch_msg_line0", MSG.split("\n")[0]))
R.append(("torch_msg_line1", MSG.split("\n")[1]))
R.append(("torch_msg_order", "True" if MSG.split("\n")[0] == MSG_HEAD else "False"))
R.append(("torch_module", MODULE_NAME))
R.append(("torch-done", "1"))

for k, v in R:
  print(f"{k}={v}")