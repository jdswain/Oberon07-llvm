# Web port

Browser host for the wasm runtime. The three subsystems
(TUI / Files / Env) are implemented as JS shims that bind to wasm
imports declared in `runtime/wasm/*_rt.c`. A small Go server at
`server/` proxies `/api/files/*` to a local FileStore directory.

## Layout

- `src/` — TypeScript shims, one per import module:
  - `tui-shim.ts`   — DOM cell-grid rendering, palette, keyboard
  - `files-shim.ts` — sync XHR against `/api/files/*`
  - `env-shim.ts`   — URL-derived project base + cwd
  - `wasm-mem.ts`   — shared memory-access helpers
  - `main.ts`       — instantiates the wasm and wires everything
- `dist/` — `tsc` output, ignored by git
- `index.html` — serves the demo `app.wasm` into `<div id="term">`

## Build

```
cd web && npm install && npx tsc
```

## Run

Compile the Oberon program to wasm and drop it next to `index.html`:

```
cd tests/wasm
oc -target wasm32 -o app.wasm WebDemo.Mod
cp app.wasm ../../web/
```

Start the Go server:

```
cd server && go build && ./server -addr :8080 -store ./store
```

Open `http://localhost:8080/`. The `<div id="term">` becomes the
fixed-cell terminal grid; `Modules.Load` works via the static
manifest, `Files.New/Old/Register` round-trips through
`/api/files/<projectBase>/<path>` to the FileStore, and
`Env.BasePath` is derived from the URL the page was served from.

## URL → project base

The Env shim reads `window.location.pathname`, strips a trailing
filename, and exposes the result as `Env.BasePath`. The Files shim
prepends it to every API call, so a page served at
`/demo/oed/index.html` reads / writes under
`<FileStore>/demo/oed/<path>` on the server.

## Limitations

- File I/O is synchronous XHR. Deprecated by browsers but the only
  way to keep Oberon's synchronous file API intact without
  restructuring around async, SharedArrayBuffer + Atomics.wait, or
  JS Promise Integration.
- `ReadKey` is non-blocking; callers poll. A real blocking
  implementation needs JSPI or a worker + SAB.
- No authentication on the server. Anyone on the network can read
  and write the FileStore. Bind to localhost or front with a proxy
  that enforces auth.
