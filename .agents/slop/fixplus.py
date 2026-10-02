import re, subprocess, sys
P = 'tinybendygrad/codegen/late.bend'
for it in range(300):
  r = subprocess.run(['./bin/bend', P, '--check-only'], capture_output=True, text=True)
  out = r.stdout + r.stderr
  if 'ALL PROOFS CHECK' in out:
    print("CLEAN after", it, "fixes"); sys.exit(0)
  m = re.search(r'- observed : (\w+) \(consumed more than once\)', out)
  d = re.search(r'Location: (\S+)', out)
  if not (m and d):
    print(out[:4000]); sys.exit(1)
  name, arg = d.group(1), m.group(1)
  L = open(P).read().split('\n')
  hdr = None
  for i, l in enumerate(L):
    if re.match(r'def %s[\.(]' % re.escape(name), l):
      hdr = i
  if hdr is None:
    print('no header for', name); sys.exit(1)
  j, sig = hdr, L[hdr]
  while '->' not in sig:
    j += 1; sig += ' ' + L[j].strip()
  new = re.sub(r'(?<![\w+])%s: ' % re.escape(arg), '+%s: ' % arg, sig, count=1)
  if new != sig:
    L[hdr] = new
    for k in range(hdr+1, j+1):
      L[k] = ''
    print(it, 'PARAM +', arg, 'in', name)
  else:
    # a pattern binder in the body
    done = False
    for k in range(hdr, min(hdr+8, len(L))):
      nl = re.sub(r'(?<![\w+])%s(?= <>)' % re.escape(arg), '+%s' % arg, L[k], count=1)
      if nl != L[k]:
        L[k] = nl; done = True
        print(it, 'BINDER +', arg, 'in', name); break
    if not done:
      print('cannot fix', arg, 'in', name); print('\n'.join(L[hdr:hdr+8])); sys.exit(1)
  open(P, 'w').write('\n'.join(L))
print('gave up')
