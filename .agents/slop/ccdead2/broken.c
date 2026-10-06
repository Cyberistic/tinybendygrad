// sz.c -- the two questions sz.py's os.walk asks: what names are in this
// directory, and is this name a directory.
//
// Both answers come back in the order the host hands them over, because
// os.walk iterates in that order and sz.py's sorted() is stable: sorting here
// would permute the rows of every table with two files of the same length.

#include <dirent.h>
#include <errno.h>
#include <sys/stat.h>

// ONE GUARD PER EFFECT, THE WAY runtime/dtype.c DOES IT, AND FOR A REASON THAT
// IS BIGGER THAN A REGISTRATION. `CID(x)` is not a macro and not C: bend
// substitutes it AT EMIT TIME for an id it allocates ON DEMAND, so a build that
// never reaches an effect never `#define`s its id, and the identifier reaches cc
// undefined. MEASURED, both directions, on two probes in .agents/slop/szlane:
//   probe-isdir.bend reaches Sz.is_dir alone -> `CID_..._SZ_READ_DIR`,
//     `CID_NIL` and `CID_CON` all undeclared, cc rc 1
//   probe-readdir.bend reaches Sz.read_dir alone -> `CID_..._SZ_IS_DIR`
//     undeclared, cc rc 1
// SO THE GUARD IS NOT ONLY AROUND `io_eff`. `sz_read_dir_pack` builds a List and
// names `CID(Nil)`/`CID(Con)`, which are demand-allocated the same way, and
// `sz_read_dir_run` calls that packer -- so the group that implements ONE effect
// is the unit that goes inside its guard, or a guarded-out registration leaves an
// undeclared function behind it.
#ifdef CID(Sz.read_dir)

// read_dir: the names in `path` except "." and "..", which is what os.walk
// leaves out of both `filenames` and `dirnames`. A directory that cannot be
// opened is no names, which is what os.walk answers with one.
static void sz_read_dir_call(IoWork* w) {
  char** names = NULL;
  u32 room = 0;
  w->code = 0;
  w->data = NULL;
  w->word = 0;
  DIR* dir = opendir(w->text);
  if (dir == NULL) {
    w->code = errno;
    return;
  }
  struct dirent* ent;
  while ((ent = readdir(dir)) != NULL) {
    if (ent->d_name[0] == '.' && (ent->d_name[1] == 0
        || (ent->d_name[1] == '.' && ent->d_name[2] == 0))) continue;
    if (w->word == room) {
      room = room ? room * 2 : 16;
      names = realloc(names, room * sizeof(char*));
      if (names == NULL) {
        closedir(dir);
        w->code = ENOMEM;
        return;
      }
    }
    u64 n = strlen(ent->d_name);
    char* copy = io_mem(malloc(n + 1));
    memcpy(copy, ent->d_name, n + 1);
    names[w->word] = copy;
    w->word += 1;
  }
  closedir(dir);
  w->data = (char*)names;
}

static Term sz_read_dir_pack(Env e, IoWork* w) {
  char** names = (char**)w->data;
  Term out = term_pak(CID(Nil), 0);
  for (u32 i = w->word; i > 0; i -= 1) {
    out = io_node(e, CID(Con), io_str(e, names[i - 1], strlen(names[i - 1])), out);
  }
  for (u32 i = 0; i < w->word; i += 1) free(names[i]);
  free(names);
  free(w->text);
  return out;
}

Term sz_read_dir_run(Env e, Term* f, IoWork* w) {
  u64 n = 0;
  char* path = io_cstr(e, f[0], &n);
  w->text = io_mem(malloc(n + 1));
  memcpy(w->text, path, n + 1);
  free(path);
  return io_work(w, sz_read_dir_call, sz_read_dir_pack);
}

static void __attribute__((constructor)) sz_read_dir_use(void) {
  io_eff(CID(Sz.read_dir), sz_read_dir_run, 0);
}

#endif

#ifdef CID(Sz.is_dir)

// is_dir: 1 for a directory, 0 for anything else. An lstat that fails is 0,
// which is what os.path.isdir answers and what os.walk's `entry.is_dir() except
// OSError: False` asks for.
//
// lstat, NOT stat, and the difference is the whole answer. os.walk defaults to
// followlinks=False and never descends a symlink to a directory; stat() FOLLOWS
// one, so it answers 1 for a link the walk must not enter. On a symlink cycle --
// a directory containing a link to itself -- the walk then re-enters its own
// subtree forever, burns the 2^24 fuel of sz.bend's walk, and RETURNS: a D with
// no fuel left is dropped without a word, so the table is silently short of rows
// instead of failing. lstat asks about the name itself, so a link is never a
// directory here, which is os.walk's own rule.
Term sz_is_dir_run(Env e, Term* f, IoWork* w) {
  u64 n = 0;
  char* path = io_cstr(e, f[0], &n);
  struct stat st;
  int yes = n != 0 && lstat(path, &st) == 0 && S_ISDIR(st.st_mode);
  free(path);
  return (Term)yes;
}

static void __attribute__((constructor)) sz_is_dir_use(void) {
  io_eff(CID(Sz.is_dir), sz_is_dir_run, 0);
}

#endif
static void planted(void) { this is not C }
