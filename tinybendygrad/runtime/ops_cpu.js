// ops_cpu.js -- THE INTERPRETED-LANE HALF OF THE CPU DEVICE's SEAM.
//
// THE SEAM IS THE NATIVE LANE's: IT COMPILES C WITH `cc` AND CALLS MACHINE
// CODE THAT IT MMAPPED ITSELF. THE JS LANE HAS NO `mmap` OF AN EXECUTABLE
// REGION AND NO WAY TO CALL A RELOCATED KERNEL, AND THE PORT's
// `runtime/ops_cpu.bend` SAYS SO RATHER THAN PRETENDING.
//
// ⇒ THE JS LANE REFUSES WITH `ENOSYS` AND THE MESSAGE NAMES THE REASON, SO A
// PROGRAM THAT RUNS HERE KNOWS IT DID NOT RUN A KERNEL.
//
// ⇒ THE JS `io_fail` TAKES THE CODE ALONE: ITS EXTRA ARGUMENTS ARE APPENDED
// TO THE `Fail`'s TUPLE, AND THE `Fail` MUST BE `Tuple(code, message)` TO MATCH
// `IO.pass`'s `case Fail{(code, message)}` -- WHICH IS WHAT THE C SIDE'S
// `io_fail(e, code, text)` BUILDS. MEASURED BY CONSTRUCTION: THE JS RUNTIME's
// `io_fail(code, ...rest)` MAKES `Tuple(Tuple(code, text), ...rest)`.
const ENOSYS = 38;

function cpu_compile(src, argv) {
  return io_fail(ENOSYS);
}

function cpu_exec(img, bufs, sizes) {
  return io_fail(ENOSYS);
}

io_eff(CID(Cpu.compile), cpu_compile);
io_eff(CID(Cpu.exec), cpu_exec);
