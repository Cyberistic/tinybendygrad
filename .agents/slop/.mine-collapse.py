import importlib.util, pathlib, sys, collections
HERE = pathlib.Path('.agents/slop')
spec = importlib.util.spec_from_file_location('rebase-gate', HERE/'rebase-gate.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
port = pathlib.Path('.agents/slop/.mine-port.txt').read_text()
def raw_names(text, marker=' = ['):
    out=[]
    for ln,line in enumerate(text.splitlines(),1):
        i=line.find(marker)
        if i<0 or not line.rstrip().endswith(']'): continue
        out.append((ln, line[:i].strip()))
    return out
rn = raw_names(port)
print('physical rows (rows_strict shape):', len(rn))
sh = m.rows(port)
print('names the SHIPPED reader finds on the PORT lane:', len(sh))
print('=> rows the shipped reader CANNOT address:', len(rn)-len(sh))
print()
lost = collections.Counter()
for ln, n in rn:
    if '=' in n:
        lost[n.split('=',1)[0].strip()] += 1
print('PORT-lane names rows() RENAMES (splitting at first =):')
for k,v in sorted(lost.items()):
    print('   %r: %d physical rows collapse onto 1 key -> %d measurements LOST' % (k, v, v-1))

print()
print("which measurement SURVIVES under the shipped reader (dict keeps the LAST):")
for k in ('kern CUDA  lb', 'kern HIP   lb'):
    print('  %r -> %r' % (k, sh[k][:70]))
