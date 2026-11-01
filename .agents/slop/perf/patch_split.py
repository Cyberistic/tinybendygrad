"""split Prog into St (static) + Gd (grid) + the per-step fields, mechanically.

21 fields are rebuilt per step; 12 of them never change during a work item. Each `Prog{...}` site is
rewritten positionally:

    us    -> st        vs  -> vs     v0   -> (in st)   ms -> ms
    fs    -> (in st)   mk  -> mk     vals -> (in st)   pc -> pc
    n     -> (in st)   pv  -> gd     gx gy gz -> (in gd)  cx cy cz -> (in st)
    bad   -> bad       dead-> dead   un   -> un        vc -> vc     vi -> vi

so the per-step rebuild allocates 11 fields instead of 21. A pattern binds `st`/`gd`; a constructor
passes them straight through, which is why the transform is positional and can be scripted.
"""
import pathlib
import re

P = pathlib.Path("tinybendygrad/runtime/ops_python.bend")
s = P.read_text()

TYPES = '''# ===========================================================================
# THE SPLIT THAT MAKES A STEP CHEAP. `Prog` is rebuilt once or twice per instruction, and it carried
# 21 fields of which TWELVE NEVER CHANGE during a work item -- the program, the pristine arena, the
# buffers, `vals`, the uop count and the grid dimensions. Those move into `St`; the work-item
# counters move into `Gd`. A per-step rebuild then allocates 11 fields instead of 21, and the two
# sub-records are carried by reference. MEASURED (REPORT.md 37.1): the 21-field rebuild is one of the
# two co-equal allocation sources against ~34 allocations per step.
# ===========================================================================
type St is Data:
  St{us: List<&2, Uop>, v0: List<&2, List<&2, Elem>>, fs: List<&2, Buf>, vals: List<&2, U32>,
     n: U32, cx: U32, cy: U32, cz: U32}

type Gd is Data:
  Gd{pv: U32, gx: U32, gy: U32, gz: U32}

def St.us(+t: St) -> List<&2, Uop>:
  match t:
    case St{us, v0, fs, vals, n, cx, cy, cz}: us

def St.v0(+t: St) -> List<&2, List<&2, Elem>>:
  match t:
    case St{us, v0, fs, vals, n, cx, cy, cz}: v0

def St.fs(+t: St) -> List<&2, Buf>:
  match t:
    case St{us, v0, fs, vals, n, cx, cy, cz}: fs

def St.vals(+t: St) -> List<&2, U32>:
  match t:
    case St{us, v0, fs, vals, n, cx, cy, cz}: vals

def St.n(+t: St) -> U32:
  match t:
    case St{us, v0, fs, vals, n, cx, cy, cz}: n

def St.cx(+t: St) -> U32:
  match t:
    case St{us, v0, fs, vals, n, cx, cy, cz}: cx

def St.cy(+t: St) -> U32:
  match t:
    case St{us, v0, fs, vals, n, cx, cy, cz}: cy

def St.cz(+t: St) -> U32:
  match t:
    case St{us, v0, fs, vals, n, cx, cy, cz}: cz

def Gd.pv(+g: Gd) -> U32:
  match g:
    case Gd{pv, gx, gy, gz}: pv

def Gd.gx(+g: Gd) -> U32:
  match g:
    case Gd{pv, gx, gy, gz}: gx

def Gd.gy(+g: Gd) -> U32:
  match g:
    case Gd{pv, gx, gy, gz}: gy

def Gd.gz(+g: Gd) -> U32:
  match g:
    case Gd{pv, gx, gy, gz}: gz

'''

DECL_OLD = '''type Prog is Data:
  Prog{us: List<&2, Uop>, vs: List<&2, List<&2, Elem>>, v0: List<&2, List<&2, Elem>>, ms: List<&2, List<&2, U32>>,
       fs: List<&2, Buf>, mk: List<&2, Bool>, vals: List<&2, U32>, pc: U32, n: U32,
       pv: U32, gx: U32, gy: U32, gz: U32, cx: U32, cy: U32, cz: U32, bad: Bool,
       dead: Bool, un: List<&2, Uop>, vc: List<&2, Elem>, vi: U32}'''
DECL_NEW = TYPES + '''type Prog is Data:
  Prog{st: St, vs: List<&2, List<&2, Elem>>, gd: Gd, ms: List<&2, List<&2, U32>>, mk: List<&2, Bool>,
       pc: U32, bad: Bool, dead: Bool, un: List<&2, Uop>, vc: List<&2, Elem>, vi: U32}'''

assert s.count(DECL_OLD) == 1, "Prog declaration"
s = s.replace(DECL_OLD, DECL_NEW)

# ---- every `Prog{...}` site: 21 fields -> 11, positionally -------------------------------------
def split_fields(body: str) -> list[str]:
  inner = body[len("Prog{"):-1]
  out, depth, cur = [], 0, ""
  for ch in inner:
    if ch in "{[(": depth += 1
    elif ch in "}])": depth -= 1
    if ch == "," and depth == 0:
      out.append(cur.strip()); cur = ""
    else:
      cur += ch
  if cur.strip():
    out.append(cur.strip())
  return out

KEEP = [2, 4, 6, 8, 17, 18, 19, 20, 21]   # 1-based positions that survive
out, i, n, sites = [], 0, len(s), 0
while True:
  j = s.find("Prog{", i)
  if j < 0:
    out.append(s[i:]); break
  k, depth = j + 4, 0
  while k < n:
    if s[k] == "{": depth += 1
    elif s[k] == "}":
      depth -= 1
      if depth == 0: break
    k += 1
  body = s[j:k+1]
  f = split_fields(body)
  if len(f) == 21:
    is_case = s[max(0, j-5):j] == "case "
    st = "_st" if (is_case and "us" not in s[k:k+200]) else "st"
    gd = "_gd" if (is_case and "pv" not in s[k:k+200]) else "gd"
    if is_case:
      # bind the sub-records under the name the body already uses, when it uses one
      tail = s[k+1:k+400]
      st = "st" if re.search(r"\b(us|v0|fs|vals|cx|cy|cz)\b", tail) else "_st"
      gd = "gd" if re.search(r"\bpv\b|\bgx\b|\bgy\b|\bgz\b", tail) else "_gd"
    fields = [st] + [f[p-1] for p in KEEP[1:]]
    fields = fields[:2] + [gd] + fields[2:]
    new = "Prog{" + ", ".join(fields) + "}"
    out.append(s[i:j]); out.append(new); sites += 1
  else:
    out.append(s[i:k+1])
  i = k + 1
s = "".join(out)

P.write_text(s)
print(f"declaration split; {sites} record sites rewritten to 11 fields")
