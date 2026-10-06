// sh(path, ...args) -- run a command, resolve with its stdout, reject with its
// stderr. One function because the lane needs it three times and a second copy
// would be a second thing to get the exit status wrong.
//
// THE EXIT STATUS IS NOT THE VERDICT. `bend --check-only` exits 1 on a CLEAN file
// (dtype.bend's 14 permanently unfilled laws) and a .bend that does not compile
// PRINTS `SOME PROOFS FAIL` and exits 0, so a caller that reads either is wrong
// in one direction or the other. This rejects only on a non-zero exit, and the
// caller reads the FIRST LINE of stdout for the verdict.
import { spawn } from "node:child_process";

export function sh(cmd, ...args) {
  return new Promise((res, rej) => {
    const p = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"] });
    let out = "", err = "";
    p.stdout.on("data", (d) => { out += d; });
    p.stderr.on("data", (d) => { err += d; });
    p.on("error", rej);
    p.on("close", (code) => code === 0 ? res(out) : rej(new Error(`${cmd} exited ${code}\n${err || out}`)));
  });
}
