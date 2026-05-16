// Files shim — wires the "files" wasm imports to the Go server's
// /api/files endpoints. Uses synchronous XMLHttpRequest because the
// Files API is called from inside synchronous Oberon procedures.
// Real async I/O would need SharedArrayBuffer + Atomics.wait or
// JSPI; sync XHR is deprecated but reliable for a dev tool, and the
// JS thread only blocks on Old (load) and Register/Close (save) —
// never on per-byte reads/writes.

import { readStr, writeI32, writeBytes, readBytes, wasmAlloc } from "./wasm-mem.js";

export interface FilesShimConfig {
  /** Root path under which the server serves the file API.
   *  Typically "/api/files" — the project base is appended onto
   *  each request URL by the C runtime (it stores f->name relative
   *  to the project). */
  apiRoot: string;

  /** URL fragment between apiRoot and the file's name. For the
   *  server's URL convention /api/files/<projectBase>/<path>, this
   *  is the projectBase. May be empty for a flat layout. */
  projectBase: string;
}

export interface FilesShim {
  imports: WebAssembly.ModuleImports;
}

function joinPath(...parts: string[]): string {
  return parts
    .map(p => p.replace(/^\/+|\/+$/g, ""))
    .filter(p => p.length > 0)
    .join("/");
}

export function makeFilesShim(cfg: FilesShimConfig): FilesShim {
  function urlFor(name: string): string {
    const path = joinPath(cfg.apiRoot, cfg.projectBase, name);
    return "/" + path;
  }

  function syncRequest(
    method: string, url: string, body?: BodyInit | null,
  ): { status: number; body: ArrayBuffer; lastModified: number } {
    const xhr = new XMLHttpRequest();
    xhr.open(method, url, false /* sync */);
    xhr.responseType = "arraybuffer";
    try {
      // XHR's send() signature is narrower than fetch's BodyInit;
      // cast the few payload kinds we use through.
      xhr.send((body as Document | XMLHttpRequestBodyInit | null) ?? null);
    } catch (_e) {
      // Network error.
      return { status: 0, body: new ArrayBuffer(0), lastModified: 0 };
    }
    const lm = xhr.getResponseHeader("Last-Modified");
    const lastModified = lm ? Math.floor(new Date(lm).getTime() / 1000) : 0;
    return {
      status: xhr.status,
      body: (xhr.response as ArrayBuffer) ?? new ArrayBuffer(0),
      lastModified,
    };
  }

  const imports: WebAssembly.ModuleImports = {
    // read(name, len, buf_addr_out*, len_out*, date_out*) -> int
    read(namePtr: number, nameLen: number,
         bufAddrOut: number, lenOut: number, dateOut: number): number {
      const name = readStr(namePtr, nameLen);
      const r = syncRequest("GET", urlFor(name));
      if (r.status === 404) return 1;
      if (r.status < 200 || r.status >= 300) return 2;
      const len = r.body.byteLength;
      const ptr = wasmAlloc(len > 0 ? len : 1);
      if (!ptr) return 2;
      if (len > 0) writeBytes(ptr, r.body);
      writeI32(bufAddrOut, ptr);
      writeI32(lenOut, len);
      writeI32(dateOut, r.lastModified);
      return 0;
    },

    // write(name, len, data, data_len) -> int
    write(namePtr: number, nameLen: number,
          dataPtr: number, dataLen: number): number {
      const name = readStr(namePtr, nameLen);
      // Copy into a tight Uint8Array<ArrayBuffer> so the Blob ctor
      // doesn't trip on the SharedArrayBuffer-possible Uint8Array
      // returned by readBytes.
      const src = readBytes(dataPtr, dataLen);
      const dst = new Uint8Array(new ArrayBuffer(src.byteLength));
      dst.set(src);
      const blob = new Blob([dst],
                            { type: "application/octet-stream" });
      const r = syncRequest("PUT", urlFor(name), blob);
      return (r.status >= 200 && r.status < 300) ? 0 : 1;
    },

    // delete(name, len) -> int (0 ok, 2 not found, 1 other)
    "delete"(namePtr: number, nameLen: number): number {
      const name = readStr(namePtr, nameLen);
      const r = syncRequest("DELETE", urlFor(name));
      if (r.status === 404) return 2;
      return (r.status >= 200 && r.status < 300) ? 0 : 1;
    },

    // rename(old, old_len, new, new_len) -> int
    rename(oldPtr: number, oldLen: number,
           newPtr: number, newLen: number): number {
      const oldName = readStr(oldPtr, oldLen);
      const newName = readStr(newPtr, newLen);
      const url = urlFor(oldName) + "?rename=" + encodeURIComponent(newName);
      const r = syncRequest("POST", url);
      if (r.status === 404) return 2;
      return (r.status >= 200 && r.status < 300) ? 0 : 1;
    },

    // exists(name, len) -> int (1 yes, 0 no)
    exists(namePtr: number, nameLen: number): number {
      const name = readStr(namePtr, nameLen);
      const r = syncRequest("HEAD", urlFor(name));
      return (r.status >= 200 && r.status < 300) ? 1 : 0;
    },

    // mkdir(name, len) -> int (0 ok, non-zero error)
    mkdir(namePtr: number, nameLen: number): number {
      const name = readStr(namePtr, nameLen);
      const url = urlFor(name) + "?mkdir=1";
      const r = syncRequest("POST", url);
      return (r.status >= 200 && r.status < 300) ? 0 : 1;
    },
  };

  return { imports };
}
