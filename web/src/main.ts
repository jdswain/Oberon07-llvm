// Entry point. Wires the three shims (TUI, Files, Env) to the
// running wasm module and kicks off the program.
//
// The HTML page that loads this file is expected to provide:
//   - a DOM element with id="term" that the TUI grid lives in
//   - a `data-wasm` attribute on that element holding the path
//     of the .wasm to load (defaults to "app.wasm")

import { makeTuiShim   } from "./tui-shim.js";
import { makeFilesShim } from "./files-shim.js";
import { makeEnvShim   } from "./env-shim.js";
import { bindMemory    } from "./wasm-mem.js";

async function main() {
  const term = document.getElementById("term");
  if (!term) throw new Error("expected an element with id='term'");
  const wasmPath = term.getAttribute("data-wasm") ?? "app.wasm";

  const tui   = makeTuiShim(term);
  const env   = makeEnvShim();
  const files = makeFilesShim({
    apiRoot:     "/api/files",
    projectBase: env.projectBase,
  });

  // Minimal WASI stub: oc-built modules call args_get / args_sizes_get
  // / proc_exit during the wasi-libc start-up before main(). The
  // browser supplies an empty argv so Env.ArgCount() returns 0; real
  // env values come from the env shim above.
  const wasi = {
    args_get(): number { return 0; },
    args_sizes_get(argcPtr: number, argvBufSizePtr: number): number {
      const memory = (instance.exports as { memory: WebAssembly.Memory }).memory;
      const view = new DataView(memory.buffer);
      view.setUint32(argcPtr, 0, true);
      view.setUint32(argvBufSizePtr, 0, true);
      return 0;
    },
    proc_exit(code: number): never {
      // wasmtime / wasi-libc invoke this from _start when the
      // program exits. In the browser we just throw to unwind out
      // of the wasm; the page stays alive.
      throw new Error(`wasm exit ${code}`);
    },
    // Round out the surface so wasi-libc start-up doesn't trip on
    // anything we haven't explicitly stubbed. Each is the smallest
    // legal behaviour for our usage.
    fd_write(): number { return 0; },
    fd_close(): number { return 0; },
    fd_seek():  number { return 0; },
    environ_get(): number { return 0; },
    environ_sizes_get(c: number, sz: number): number {
      const memory = (instance.exports as { memory: WebAssembly.Memory }).memory;
      const view = new DataView(memory.buffer);
      view.setUint32(c, 0, true);
      view.setUint32(sz, 0, true);
      return 0;
    },
    clock_time_get(): number { return 0; },
    random_get(buf: number, len: number): number {
      const memory = (instance.exports as { memory: WebAssembly.Memory }).memory;
      const u8 = new Uint8Array(memory.buffer, buf, len);
      crypto.getRandomValues(u8);
      return 0;
    },
  };

  const imports: WebAssembly.Imports = {
    tui:   tui.imports,
    files: files.imports,
    env:   env.imports,
    wasi_snapshot_preview1: wasi,
  };

  const fetched = await fetch(wasmPath);
  if (!fetched.ok) throw new Error(`fetch ${wasmPath}: ${fetched.status}`);
  const { instance } = await WebAssembly.instantiateStreaming(fetched, imports);

  const exports = instance.exports as {
    memory: WebAssembly.Memory;
    _start?: () => void;
  };
  bindMemory(exports.memory, instance.exports);
  if (exports._start) exports._start();
}

main().catch(err => {
  console.error(err);
  const status = document.getElementById("status");
  if (status) status.textContent = String(err);
});
