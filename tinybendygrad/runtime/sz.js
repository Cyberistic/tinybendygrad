// sz.js -- the two questions sz.py's os.walk asks, in the interpreted lane.
// The answers come back in readdir order, because os.walk iterates in that
// order and sz.py's sorted() is stable. A directory that cannot be read is no
// names, which is what os.walk does with one.

function sz_read_dir(path) {
  let names;
  try {
    names = require("node:fs").readdirSync(path);
  } catch (e) {
    return { $: CID(Nil) };
  }
  let xs = { $: CID(Nil) };
  for (let i = names.length; i > 0; i -= 1) {
    xs = { $: CID(Con), head: names[i - 1], tail: xs };
  }
  return xs;
}

io_eff(CID(Sz.read_dir), sz_read_dir);

// 1 for a directory, 0 for anything else: os.path.isdir answers False for a
// path it cannot stat, and so does os.walk's `entry.is_dir() except OSError`.
function sz_is_dir(path) {
  try {
    return require("node:fs").lstatSync(path).isDirectory() ? 1 : 0;
  } catch (e) {
    return 0;
  }
}

io_eff(CID(Sz.is_dir), sz_is_dir);
