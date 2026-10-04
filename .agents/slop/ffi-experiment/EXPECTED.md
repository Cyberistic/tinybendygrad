# EXPECTATIONS — written down BEFORE running. Any deviation is reported, not rationalised.

## E1 — libc `strlen`, C-local string (proves the LINK, not the marshalling)
Expected `./out` stdout, exactly:
```
SLEN 14
```
`strlen("tinybendygrad")` — count it: t-i-n-y-b-e-n-d-y-g-r-a-d = 14.
Command template: `cc out.c -l<lib> -o out` with `<lib>` = empty (libc is implicit).
If this prints anything else, the Term ABI path is wrong, not the link.

## E2 — libc `getenv`, C-local name, returns through a Term
Set `FOO=barbaz` in the environment. `getenv("FOO")` must be non-NULL.
Expected stdout:
```
ENV BARBAZ
```
Two sub-facts proven: the call works, AND a C string crosses back into Bend as a
Bend string through `term_str`/equivalent. If the returned string is garbage the
link still worked and only the return marshalling is broken — say WHICH.

## E3 — Bend string IN, length OUT (the real marshalling cost)
Expected stdout:
```
MARSHAL 9
```
Fed the Bend string literal `"tinybendygrad"` (14 chars). Expected `14`.
This is the per-function cost measurement: does a Bend string reach C as a
pointer I can hand to `strlen` for free?

## E4 — libclang
`clang_getClangVersion()` lives in `/Library/Developer/CommandLineTools/usr/lib/libclang.dylib`.
Expected stdout begins with the substring `clang version` followed by a digit.
Link line: `cc out.c -L/Library/Developer/CommandLineTools/usr/lib -lclang -o out`.
If the link fails, report WHICH of: `bend -o` / `cc` compile / LINK / RUN.

## E5 — three functions in ONE imported .c
E1+E3 and a 3rd function all in one shim.c, one `import`. Expected: all three
lines present. This proves the "one generated .c + one import" shape is real and
not just a 1-function special case.

## DENOMINATORS I must report
- libclang: exported symbol count measured by running, not inherited.
- one driver backend: entry points counted from the actual header on this machine.