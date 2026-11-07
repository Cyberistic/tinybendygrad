"""THE TABLE ENTRIES WHOSE BODY IMPLEMENTS A DIFFERENT RULE THAN THE CITATION NAMES.

    .venv/bin/python .agents/slop/sym92/citeshift.py --mismatch

**THE QUESTION.** THE RE-VENDOR TO `f5ac54685074` MOVED AND DELETED UPSTREAM RULES. THE PORT's
TABLE ENTRIES CITE LINES, AND THE CENSUS MATCHES ON THE CITATION AND THE OPS -- SO A CITATION
THAT NAMES A DIFFERENT RULE NOW IS INVISIBLE TO IT.

**THE MEASUREMENT.** FOR EVERY TABLE ENTRY, THE RULE ITS BODY IMPLEMS (THE RULE THE BODY's OWN
COMMENT CITES, LOOKED UP IN THE OLD PIN) IS COMPARED WITH THE RULE AT THE CITED LINE IN THE NEW
PIN. **IF UPSTREAM's TEXT AT THE TWO LINES IS THE SAME, THE RULE ONLY MOVED AND THE ENTRY IS
FINE. IF THE TEXTS DIFFER, THE ENTRY DISPATCHES A BODY FOR A DIFFERENT RULE.**

THE OLD PIN IS `5c2bf39d6` AND THE NEW ONE IS `f5ac54685074`.
"""
import re
import subprocess
import sys

OLD = "5c2bf39d6"
NEW = "f5ac54685074"
PORT = "tinybendygrad/uop/symbolic.bend"


def lines_of(rev):
  out = subprocess.run(["git", "show", f"{rev}:tinygrad/uop/symbolic.py"],
                       capture_output=True, text=True)
  return out.stdout.splitlines() if out.returncode == 0 else []


def norm(t):
  t = re.sub(r"#.*", "", t)
  t = re.sub(r"\s+", " ", t)
  return t.strip().rstrip(",")


def rules_by_line(ls):
  out = {}
  for i, ln in enumerate(ls, start=1):
    t = ln.strip()
    if t.startswith("(") and "lambda" in t and t.endswith(","):
      out[i] = norm(t)
  return out


def main():
  old_by = rules_by_line(lines_of(OLD))
  new_by = rules_by_line(lines_of(NEW))
  src = open(PORT).read()
  disp = {}
  for m in re.finditer(r"case (\d+): sym_(\d+)\(x, u\)", src, re.M):
    disp[int(m.group(1))] = "sym_" + m.group(2)
  # the TABLE: tag -> cited line, AND IT IS THE CENSUS's OWN PARSER AND NOT A SECOND ONE
  import importlib.util
  spec = importlib.util.spec_from_file_location("c", "gates/symrules-census.py")
  census = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(census)
  tbl = {}
  for tname, entries in census.port_tables().items():
    for e in entries:
      if e["cited"] is not None:
        tbl[e["tag"]] = e["cited"]

  def body_cites(name):
    """THE CITATION THE BODY's OWN COMMENT NAMES.

    **THE WINDOW IS THE COMMENT BLOCK AND NOT THE LAST LINE ABOVE**, BECAUSE A RULE's COMMENT
    SPANS SEVERAL LINES AND THE CITATION IS USUALLY THE FIRST OF THEM: `sym_174`'s def is EIGHT
    LINES BELOW ITS `# symbolic.py:174` COMMENT. MEASURED 2026-11-06: A ONE-LINE WINDOW MISSED
    `sym_174` AND THE COUNT WAS 16 INSTEAD OF 17.
    """
    m = re.search(r"^def %s\b" % re.escape(name), src, re.M)
    if not m:
      return None
    # THE COMMENT BLOCK ABOVE THE DEF: THE RUN OF `#` LINES AND BLANK LINES BEFORE IT
    window = src[:m.start()]
    lines = window.splitlines()
    block = []
    for ln in reversed(lines):
      if ln.startswith("#") or ln.strip() == "":
        block.append(ln)
        continue
      break
    cs = re.findall(r"symbolic\.py:(\d+)", "\n".join(reversed(block)))
    if cs:
      return int(cs[0])
    cs = re.findall(r"symbolic\.py:(\d+)", window)
    return int(cs[-1]) if cs else None

  print("THE TABLE ENTRIES WHOSE BODY IS NOT THE CITED RULE")
  n = 0
  for tag in sorted(tbl):
    body = disp.get(tag)
    cited = tbl[tag]
    if body is None:
      continue
    bc = body_cites(body)
    if bc is None:
      continue
    want = old_by.get(bc)
    if want is None:
      continue
    at_new = new_by.get(cited)
    if at_new == want:
      continue  # THE RULE ONLY MOVED
    n += 1
    print("  tag %-3d cites %-4d  body %-9s implements the old %-4d" % (tag, cited, body, bc))
    print("      cited  : %s" % (at_new[:96] if at_new else "NO RULE AT THAT LINE"))
    print("      body   : %s" % want[:96])
  print("  %d of %d entries dispatch a body for a DIFFERENT rule" % (n, len(tbl)))
  return 0


if __name__ == "__main__":
  sys.exit(main())
