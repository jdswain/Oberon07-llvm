// Helper for reading / writing wasm linear memory from JS.
// Bound by main.ts after the wasm module is instantiated; every other
// shim asks this module for a fresh view rather than caching one,
// because the linear memory may grow (and previous views become
// detached) on any wasm side allocation.

let memoryRef: WebAssembly.Memory | null = null;
let wasmExports: WebAssembly.Exports | null = null;

export function bindMemory(memory: WebAssembly.Memory, exports: WebAssembly.Exports) {
  memoryRef = memory;
  wasmExports = exports;
}

function view(): Uint8Array {
  if (!memoryRef) throw new Error("wasm memory not yet bound");
  return new Uint8Array(memoryRef.buffer);
}

function dv(): DataView {
  if (!memoryRef) throw new Error("wasm memory not yet bound");
  return new DataView(memoryRef.buffer);
}

/** Decode an Oberon (ptr, len) string into a JS string. The Oberon
 *  ABI for ARRAY OF CHAR is NUL-terminated within the buffer; stop
 *  at the first 0 if it appears before `len`. */
export function readStr(ptr: number, len: number): string {
  if (len <= 0) return "";
  const u8 = view();
  let end = ptr + len;
  for (let i = ptr; i < end; i++) {
    if (u8[i] === 0) { end = i; break; }
  }
  return new TextDecoder().decode(u8.subarray(ptr, end));
}

/** Write `s` into the buffer at `ptr` (capacity `cap` bytes,
 *  including the NUL terminator). Truncates rather than overflows.
 *  Used by Env.Cwd / Env.BasePath etc. that take VAR ARRAY OF CHAR. */
export function writeStr(ptr: number, cap: number, s: string): void {
  if (cap <= 0) return;
  const bytes = new TextEncoder().encode(s);
  const u8 = view();
  const n = Math.min(bytes.length, cap - 1);
  for (let i = 0; i < n; i++) u8[ptr + i] = bytes[i];
  u8[ptr + n] = 0;
}

/** Raw byte read — used by Files.write to ship file content out. */
export function readBytes(ptr: number, len: number): Uint8Array {
  // Slice into a fresh buffer so callers can hand it to fetch/XHR
  // without worrying about the wasm memory growing under them.
  return view().slice(ptr, ptr + len);
}

/** Copy `bytes` into wasm memory at `ptr`. */
export function writeBytes(ptr: number, bytes: Uint8Array | ArrayBuffer): void {
  const src = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const u8 = view();
  u8.set(src, ptr);
}

/** Write a 32-bit little-endian integer at `ptr`. */
export function writeI32(ptr: number, v: number): void {
  dv().setInt32(ptr, v | 0, true);
}

/** Call back into the wasm-exported allocator. The wasm side exports
 *  `oc_wasm_alloc(n)` returning a fresh ptr (or 0 on failure). */
export function wasmAlloc(n: number): number {
  if (!wasmExports) throw new Error("wasm exports not yet bound");
  const fn = (wasmExports as Record<string, unknown>)["oc_wasm_alloc"];
  if (typeof fn !== "function") throw new Error("oc_wasm_alloc missing");
  return (fn as (n: number) => number)(n);
}

/** Dispatch a key into the wasm — calls the TUI runtime's
 *  oc_dispatch_key export, which invokes whatever handler the
 *  Oberon program registered via TUI.SetKeyHandler. Returns true
 *  if the export was present and called. */
export function dispatchKey(code: number): boolean {
  if (!wasmExports) return false;
  const fn = (wasmExports as Record<string, unknown>)["oc_dispatch_key"];
  if (typeof fn !== "function") return false;
  (fn as (k: number) => void)(code);
  return true;
}
