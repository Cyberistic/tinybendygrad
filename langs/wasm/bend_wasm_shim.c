/* bend_wasm_shim.c -- the C side of the emscripten-shaped wasm contract.
 *
 * Emscripten gives you `_malloc`, `ccall` and `_free` and expects the module
 * to export a C entry point it can reach by name.  This file is that entry
 * point, and it is deliberately the whole of it: three functions, no logic,
 * so nothing here can move an f32.
 *
 *   bend_core_task(in_ptr, out_ptr)
 *
 * reads the flat 42-number payload at in_ptr and writes the eight f32 answers
 * at out_ptr.  The payload is the same field list every other lane speaks --
 * 8 image bits, 2 class indices, 32 weight bits -- as f32 and u32 in one
 * block, because the JS backend takes the same order and the same layout.
 *
 * Build it with emcc, per langs/wasm/WALL.md.  That build cannot succeed yet,
 * because Bend 2.0.34 reserves an 8 GiB corpus that no wasm32 address space
 * holds; WALL.md has the measurement and the one-line upstream fix.
 */

/* The payload, and the answer, in f32 units.  Both are fixed by the core's
 * shape: IN=4, BATCH=2, CLS=3, and 27 weights padded into a 32-slot array. */
#define PAYLOAD_F32 42
#define ANSWER_F32 8

/* The images and the weights arrive as bit patterns, so the core reads them
 * through a reinterpretation; the labels are already class indices.  These
 * offsets are the field order the .bend harness and the SDK both use. */
#define IMAGES 8
#define LABELS 2

/*
 * bend_core_task -- run one step.  Returns 0; the answer is in out_ptr.
 *
 * The three arrays are built in linear memory, passed to core_step, and read
 * back out.  Nothing is allocated here: the caller owns in_ptr and out_ptr,
 * which is what keeps the _malloc/_free pair in the JS side and nowhere else.
 */
int bend_core_step(float* images, unsigned int* labels, float* weights, float* loss);

int bend_core_task(float* in_ptr, float* out_ptr) {
  float*    images  = in_ptr;
  unsigned* labels  = (unsigned*)(in_ptr + IMAGES);
  float*    weights = in_ptr + IMAGES + LABELS;
  float     loss    = 0.0f;

  bend_core_step(images, labels, weights, &loss);
  out_ptr[0] = loss;
  return 0;
}
