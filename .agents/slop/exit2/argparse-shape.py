import argparse
ap = argparse.ArgumentParser(prog='checks/differ.py')
sub = ap.add_subparsers(dest='cmd', required=True)
for name in ('run', 'repro', 'snap', 'plant'):
    sub.add_parser(name)
ap.parse_args()
print('REACHED THE BODY -- argparse did not refuse')
