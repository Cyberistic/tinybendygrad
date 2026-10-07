// LEAF CAUSE, measured with NO bend runtime in the process: does a census row
// that reported FAILED die on a NULL dereference under the zero-argument
// policy? The census hands every pointer parameter 0 and every by-value struct
// a zeroed block; libclang dereferences the handle, so SIGSEGV is expected.
#include <stdio.h>
#include <string.h>
typedef union { unsigned char _b[24]; unsigned long long _a; } CXType;
typedef union { unsigned char _b[32]; unsigned long long _a; } CXCursor;
extern unsigned clang_getAddressSpace(CXType);
extern unsigned clang_getUnqualifiedType(CXType);
extern unsigned clang_getCursorTLSKind(CXCursor);
extern void* clang_createIndexWithOptions(void*);
extern unsigned clang_getCursorPrintingPolicy(CXCursor);
int main(int argc, char** argv) {
  CXType t; memset(&t, 0, sizeof t);
  CXCursor c; memset(&c, 0, sizeof c);
  const char* which = argc > 1 ? argv[1] : "getAddressSpace";
  printf("calling %s with a ZEROED struct / NULL pointer\n", which); fflush(stdout);
  if (!strcmp(which, "getAddressSpace"))        printf("-> %u\n", clang_getAddressSpace(t));
  if (!strcmp(which, "getUnqualifiedType"))     printf("-> %u\n", clang_getUnqualifiedType(t));
  if (!strcmp(which, "getCursorTLSKind"))      printf("-> %u\n", clang_getCursorTLSKind(c));
  if (!strcmp(which, "createIndexWithOptions")) printf("-> %p\n", clang_createIndexWithOptions(0));
  if (!strcmp(which, "getCursorPrintingPolicy"))printf("-> %p\n", clang_getCursorPrintingPolicy(c));
  printf("returned -- no crash\n");
  return 0;
}
