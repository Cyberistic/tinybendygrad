#!/usr/bin/env python3
"""**THE **CALL **SITES **OF **`List.append`, **COUNTED **IN **THE **COMPILED **FORM** -- **⇒⇒† AND
**AND **THEY **ARE **COUNTED **PER **SITE **AND **PER **CALLING **FUNCTION**, **⇒⇒† AND **SO **A
**SPREAD **OF **22 **MILLION **APPENDS **GETS **AN **OWNER**.

**WHY.** THE PROFILE SAYS **`List.append` **IS **~10% **OF **THE **TURN** (⇒⇒† AND **V8's **OWN
**CPU **PROFILE **OF **THE **COMPILED **FORM**) **AND **IT **DOES **NOT **SAY **WHO **CALLS **IT** ✓
**⇒⇒† AND **AND **THE **COUNT **WITHOUT **THE **OWNER **IS **NOT **A **DIAGNOSIS** ✓.

**THE **COMMAND.** `.venv/bin/python .agents/slop/wgslperf/count-sites.py` -- **AND **IT **PRINTS
**THE **TOP **CALL **SITES **BY **COUNT** ✓.
"""

import collections
import json
import pathlib
import re
import subprocess
import sys

R = pathlib.Path(__file__).resolve().parents[3]
HERE = R / ".agents" / "slop" / "wgslperf"
BEND = R / "bin/bend"

ACC = """globalThis.__S = globalThis.__S || {};
globalThis.__SS = (k) => { globalThis.__S[k] = (globalThis.__S[k] || 0) + 1; };"""


def main():
  tree = (pathlib.Path(sys.argv[sys.argv.index("--tree") + 1]) / "tinybendygrad") if "--tree" in sys.argv else None
  if tree:
    sys.path.insert(0, str(HERE))
    import wgslbase
    driver = wgslbase.driver_for(tree, "sitebundle")
  else:
    driver = HERE / "wgslprof.bend"
  out = HERE / "wgslprof.sites.mjs"
  b = subprocess.run([str(BEND), str(driver), "-o", str(out)], capture_output=True, text=True)
  if b.returncode != 0 or not out.exists():
    raise SystemExit(f"WARN: the driver did not build:\n{b.stderr[:1500]}")
  src = out.read_text()
  # **⇒⇒† AND **EVERY **`List.append(` **CALL **SITE**, **⇒⇒† AND **AND **THE **FUNCTION **IT **IS
  # **IN** ✓
  lines = src.split("\n")
  fun = "?"
  sites = 0
  for i, line in enumerate(lines):
    m = re.match(r"function (\$[A-Za-z0-9_$]+)\(", line)
    if m:
      fun = m.group(1)
    for c in re.finditer(r"\$\$?List_append\(", line):
      sites += 1
      key = f"{fun}#{sites}"
      # **⇒⇒† AND **THE **CALL **IS **WRAPPED **IN **THE **COMMA **OPERATOR** (⇒⇒† AND **AND **THAT
      # **IS **VALID **INSIDE **AN **OBJECT **LITERAL**, **⇒⇒† AND **AND **A **BARE **COMMA **IS
      # **NOT**) ✓
      lines[i] = line[:c.start()] + f'(globalThis.__SS("{key}"), ' + line[c.start():] + ")"
  print(f"THE `List.append` CALL SITES: {sites}")
  m = re.search(r"function (\$chain_wgsl)\(([^)]*)\)\s*\{", "\n".join(lines))
  if not m:
    raise SystemExit("WARN: no chain_wgsl")
  i = "\n".join(lines).find(m.group(0))
  src = "\n".join(lines)[:i] + ACC + "\n".join(lines)[i:]
  out.write_text(src)
  call = HERE / "call-sites.mjs"
  call.write_text('import M from "./wgslprof.sites.mjs";\n'
                  'import fs from "fs";\n'
                  'M["chain_wgsl"]();\n'
                  'fs.writeFileSync(process.env.__WGSL_OUT || "/tmp/wgslsites.json",\n'
                  '  JSON.stringify(globalThis.__S || {}));\n')
  env = dict(subprocess.os.environ)
  env["__WGSL_OUT"] = str(HERE / "site-counts.json")
  r = subprocess.run(["node", str(call)], capture_output=True, text=True, env=env, cwd=str(HERE))
  if r.returncode != 0:
    print(r.stderr[:1200])
    raise SystemExit("WARN: the counting driver did not run")
  C = json.loads((HERE / "site-counts.json").read_text())
  print()
  for k, v in sorted(C.items(), key=lambda kv: -kv[1])[:28]:
    fn, site = k.split("#")
    print(f"  {v:12,}  {fn[:88]:88s} site {site}")


if __name__ == "__main__":
  main()
