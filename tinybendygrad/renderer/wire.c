// wire.c -- THE WIRE SPLIT, AS AN EFFECT. THE COMPILED LANE'S HALF.
//
// WHY THERE IS A .c HALF AT ALL: the port's effects have both halves because the COMPILED lane is C
// (`sz.c` is 100 lines of C for `opendir`), and the effect source is read once, in one namespace
// (`comp.ts`'s `effect_src`). A `.bend` def that imports a `.js` and not a `.c` REFUSES to build in the C
// lane ("a foreign def without a .js import" is the JS lane's message; the C lane's is "no .c import").
//
// AND WHAT IT COSTS HERE: **THE C LANE KEEPS THE PRELUDE'S COST, AND THAT IS DELIBERATE.** A C
// `String.split` IS THE SAME ALGORITHM AS THE PRELUDE'S -- a scan for the separator with a per-token copy --
// so the C half here is the same work the prelude does, and the C LANE'S DECODE IS NOT SLOWER THAN TODAY.
// The win is in the JS lane, WHICH IS THE SHIPPED DAEMON (`bun`), and the JS half is
// `tinybendygrad/renderer/wire.js`.
//
// MEASURED (`PARITY.md` §125/§126): the prelude's split is 5.16 ms of a 5.58 ms daemon turn -- 92.6% --
// and the JS lane's native split is 0.136 ms a turn.
//
// SO THIS FILE IS THE FAITHFUL C ALGORITHM, NOT A REFUSAL: it splits on ' ' and copies each token.

#include <string.h>

#ifdef CID(Wire.split)

// The scan: one token at a time, each copied into the work item's buffer list.
static void wire_split_call(IoWork* w) {
  const char* s = w->text;
  u64 n = strlen(s);
  u64 start = 0;
  u32 count = 0;
  char** parts = NULL;
  u32 room = 0;
  for (u64 i = 0; i <= n; i += 1) {
    if (i == n || s[i] == ' ') {
      if (count == room) {
        room = room ? room * 2 : 64;
        parts = realloc(parts, room * sizeof(char*));
        if (parts == NULL) { w->code = 12; return; }
      }
      u64 len = i - start;
      char* copy = io_mem(malloc(len + 1));
      memcpy(copy, s + start, len);
      copy[len] = '\0';
      parts[count] = copy;
      count += 1;
      start = i + 1;
    }
  }
  w->data = (char*)parts;
  w->word = count;
}

// The pack: the list, newest first, so the caller walks it in wire order.
static Term wire_split_pack(Env e, IoWork* w) {
  char** parts = (char**)w->data;
  Term out = term_pak(CID(Nil), 0);
  for (u32 i = w->word; i > 0; i -= 1) {
    out = io_node(e, CID(Con), io_str(e, parts[i - 1], strlen(parts[i - 1])), out);
  }
  for (u32 i = 0; i < w->word; i += 1) free(parts[i]);
  free(parts);
  free(w->text);
  return out;
}

Term wire_split_run(Env e, Term* f, IoWork* w) {
  u64 n = 0;
  char* path = io_cstr(e, f[0], &n);
  w->text = io_mem(malloc(n + 1));
  memcpy(w->text, path, n + 1);
  free(path);
  return io_work(w, wire_split_call, wire_split_pack);
}

static void __attribute__((constructor)) wire_split_use(void) {
  io_eff(CID(Wire.split), wire_split_run, 0);
}

#endif
