// THE FIXTURE, ONCE, FOR BOTH SIDES.
//
// `.agents/slop/clangshim/oracle.py` hands CPython the bytes in `SRC` and this
// header hands the C helper the SAME bytes in `CL_FIXTURE_SRC`.  `fixture-check.py`
// asserts the two are byte-identical, so "the two sides parsed the same file" is
// a checked row and not a claim -- the whole comparison is otherwise about which
// BUILD answered, not which source was read.
//
// `CL_DECLS` below is the C translation of those bytes, and it is what `cdecl_off`
// and the `c=` spelling column are measured from.  It is a SECOND copy on purpose:
// a plant that edits one and not the other is exactly the failure CL-8 warns about
// (the first disarm here MOVED `SIZE struct Pair` 16 -> 24 because it was a second
// plant wearing a disguise).  `fixture-check.py` compiles CL_FIXTURE_SRC for real
// and diffs its sizeof/offsetof against CL_DECLS, so a half-plant fails loudly
// instead of printing a self-contradicting row.
#ifndef CL_FIXTURE_H
#define CL_FIXTURE_H

struct Pair {
  int a;
  char b;
  double c;
};
int top;

static const char CL_FIXTURE_SRC[] =
  "struct Pair {\n"
  "  int a;\n"
  "  char b;\n"
  "  double c;\n"
  "};\n"
  "int top;\n";

static const char CL_FIXTURE_NAME[] = "fixture.c";

// The C spelling of each field, and of the record.  Indexed by the SAME selector
// the Bend laws pass: 0=a, 1=b, 2=c, 3=the record itself.
#define CL_FIELD_NAMES  { "a", "b", "c", "Pair" }
#define CL_FIELD_SPELL  { "int", "char", "double", "struct Pair" }

#endif