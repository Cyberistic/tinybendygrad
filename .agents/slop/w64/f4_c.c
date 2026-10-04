typedef unsigned long long u64;
u64 f4add(u64 a, u64 b) {
  double x, y, z; u64 r;
  __builtin_memcpy(&x, &a, 8);
  __builtin_memcpy(&y, &b, 8);
  z = x + y;
  __builtin_memcpy(&r, &z, 8);
  return r;
}
