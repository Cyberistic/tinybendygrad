#ifdef __APPLE__
typedef void (*gotfn)(void);
gotfn _GLOBAL_OFFSET_TABLE_[64] __asm("__GLOBAL_OFFSET_TABLE_") = {0};
#endif
void ext_fn(int i) { (void)i; }
int ext_data = 41;
double dsin(double x) { return __builtin_sin(x); }
