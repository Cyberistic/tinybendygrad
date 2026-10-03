"""Row parser shared by the wire-* tools.

Row names contain spaces (`PTX tensor_cores sm_75`). A capture of `^(\\S+) = `
drops every such name and the tool then agrees on the handful of names that
have none. This tree has two emitters and dropping either one is a false
agreement:

  `name = value`   tcptx-oracle.py, and the wire-pair control fixture
  `name=value`     elf_rows.py, sqtt_spec.py, and most ports
"""
import json, os, pathlib, re

SPACED = re.compile(r"^(.*?)\s=\s(.*)$")
TIGHT = re.compile(r"^([^\s=]+)=(.*)$")


def rows(text):
  """`name = value` first, then `name=value`. Comment lines are not rows."""
  out = {}
  for line in text.splitlines():
    if not line or line.lstrip().startswith("#"):
      continue
    m = SPACED.match(line) or TIGHT.match(line)
    if m:
      out[m.group(1)] = m.group(2).strip()
  return out


def stripped_env(extra=None):
  """Drop `PYTHONPATH`. A copy of `os.environ` taken after it was set measures
  the treatment, and an oracle that imports the wrong tinygrad exits 1 printing
  nothing -- which a differ then reads as agreement."""
  env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
  if extra:
    env.update(extra)
  return env


def cache_file(cache_dir, port):
  return pathlib.Path(cache_dir) / (port.replace("/", "_") + ".json")


def read_fresh_cache(cache_dir, port, source):
  """A cache older than the source is not a reading. The tc_ptx cache written
  at 14:33 still holds the six retired `py=` literals after the 14:59 fix; a
  reader that trusts it reports a bug that is gone."""
  f = cache_file(cache_dir, port)
  src = pathlib.Path(source)
  if not f.exists():
    return None, "missing"
  if src.exists() and f.stat().st_mtime < src.stat().st_mtime:
    return None, "stale"
  return json.loads(f.read_text()), "fresh"


def write_cache(cache_dir, port, data):
  cache_dir = pathlib.Path(cache_dir)
  cache_dir.mkdir(exist_ok=True)
  cache_file(cache_dir, port).write_text(json.dumps(data))
