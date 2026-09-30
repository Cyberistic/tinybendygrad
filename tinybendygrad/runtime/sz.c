// sz.c -- the two questions sz.py's os.walk asks: what names are in this
// directory, and is this name a directory.
//
// Both answers come back in the order the host hands them over, because
// os.walk iterates in that order and sz.py's sorted() is stable: sorting here
// would permute the rows of every table with two files of the same length.

#include <dirent.h>
#include <errno.h>
#include <sys/stat.h>

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

// is_dir: 1 for a directory, 0 for anything else. A stat that fails is 0, which
// is what os.path.isdir answers and what os.walk's `entry.is_dir() except
// OSError: False` asks for.
Term sz_is_dir_run(Env e, Term* f, IoWork* w) {
  u64 n = 0;
  char* path = io_cstr(e, f[0], &n);
  struct stat st;
  int yes = n != 0 && stat(path, &st) == 0 && S_ISDIR(st.st_mode);
  free(path);
  return (Term)yes;
}

static void __attribute__((constructor)) sz_is_dir_use(void) {
  io_eff(CID(Sz.is_dir), sz_is_dir_run, 0);
}
