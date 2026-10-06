import re, os, subprocess
ROOT = os.getcwd()
text = open('.agents/TOOLS.md').read()
tracked = set(subprocess.run(['git','ls-files'],capture_output=True,text=True).stdout.split())

def norm(t):
    t = t.strip().strip('`').strip('.,;:)("\'')
    if t.startswith('./'): t = t[2:]
    return t

def absent(t):
    if t.startswith(('http','git@','//')) or 'github.com' in t: return False
    if t in tracked: return False
    if os.path.exists(t): return False
    if any(f.startswith(t.rstrip('/') + '/') for f in tracked): return False
    return True

toks = set()
for w in text.split():
    t = norm(w)
    if '/' in t:
        toks.add(t)
abs_ = sorted(t for t in toks if absent(t))
print('R4 whitespace-slash tokens:', len(toks))
print('R4 absent:', len(abs_))
print('R4 absent under .agents/slop/:', sum(1 for t in abs_ if t.startswith('.agents/slop/')))
print('R4 present:', len(toks) - len(abs_))
for t in abs_[:10]: print('   e.g.', t)

EXTS = (".py", ".sh", ".bend", ".md", ".tsv", ".rows", ".out", ".err", ".txt",
        ".tex", ".js", ".json", ".lock", ".c", ".odin", ".mjs", ".toml", ".yaml", ".yml", ".cfg", ".ini")
def norm5(t):
    t = t.strip().strip('`').strip('*_[]').strip('.,;:)("\'')
    if t.startswith('./'): t = t[2:]
    return t
toks5 = set()
for w in text.split():
    t = norm5(w)
    if '/' in t and t.endswith(EXTS):
        toks5.add(t)
abs5 = sorted(t for t in toks5 if absent(t))
print('R5 ws tokens ending in known ext:', len(toks5))
print('R5 absent:', len(abs5), ' present:', len(toks5)-len(abs5))
print('R5 absent under .agents/slop/:', sum(1 for t in abs5 if t.startswith('.agents/slop/')))
