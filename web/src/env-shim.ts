// Env shim — fills in Cwd / BasePath from the URL the page was
// served from. The Oberon side calls Env.BasePath() to get the
// path prefix that the Files shim will then prepend to every
// request. Cwd is identical for browser deployments (there's no
// other notion of "current directory") but kept distinct to match
// the posix runtime where they differ.

import { writeStr } from "./wasm-mem.js";

export interface EnvShimConfig {
  /** Project base path. Defaults to the first path segment of
   *  window.location, so a page served at /demo/index.html gives
   *  projectBase="demo". Callers can override (useful for tests
   *  and embeddings). */
  projectBase?: string;
}

export interface EnvShim {
  imports: WebAssembly.ModuleImports;
  /** Resolved project base — useful for the Files shim. */
  projectBase: string;
}

function defaultBase(): string {
  // First non-empty segment of window.location.pathname. e.g.
  //   /demo/oed/index.html  ->  "demo"
  //   /                     ->  ""
  if (typeof window === "undefined") return "";
  const segs = window.location.pathname.split("/").filter(s => s.length > 0);
  if (segs.length === 0) return "";
  if (segs[segs.length - 1].includes(".")) segs.pop(); // drop file
  return segs.join("/");
}

export function makeEnvShim(cfg: EnvShimConfig = {}): EnvShim {
  const projectBase = cfg.projectBase ?? defaultBase();
  const imports: WebAssembly.ModuleImports = {
    cwd(ptr: number, len: number): void {
      writeStr(ptr, len, projectBase);
    },
    base_path(ptr: number, len: number): void {
      writeStr(ptr, len, projectBase);
    },
  };
  return { imports, projectBase };
}
