# BASELINE -- sz.c BEFORE THE GUARDS (Bend 2.0.34, cc = Apple clang version 21.0.0 (clang-2100.1.1.101))

PROBE                      bend -o    emit     cc -fsyn  FIRST cc ERROR
probe-none.bend            rc=0       2885     rc=0      (sz.c not pasted; 0 registrations)
probe-isdir.bend           rc=0       3090     rc=1      undeclared identifier 'CID_NIL' @2981
probe-readdir.bend         rc=0       3146     rc=1      undeclared identifier 'CID_..._SZ_IS_DIR' @3082
sz.bend (all)              rc=0       119075   rc=0      (both ids allocated; both registrations live)

## probe-isdir.bend: 3 undeclared identifiers, all in read_dir's half
$ cc -fsyntax-only emit-isdir.c
  emit-isdir.c:2981:23: error: use of undeclared identifier 'CID_NIL'
  emit-isdir.c:2983:22: error: use of undeclared identifier 'CID_CON'
  emit-isdir.c:3001:10: error: use of undeclared identifier 'CID__________TINYBENDYGRAD_SZ_SZ_READ_DIR'; did you mean 'WL_FID__________TINYBENDYGRAD_SZ_SZ_IS_DIR'?

## probe-readdir.bend: 1 undeclared identifier, is_dir's registration
$ cc -fsyntax-only emit-readdir.c
  emit-readdir.c:3082:10: error: use of undeclared identifier 'CID__________TINYBENDYGRAD_SZ_SZ_IS_DIR'; did you mean 'WL_FID__________TINYBENDYGRAD_SZ_SZ_READ_DIR'?
