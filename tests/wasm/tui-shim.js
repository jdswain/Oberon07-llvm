// tui-shim.js — reference JS host for the wasm TUI runtime.
//
// The wasm side (runtime/wasm/TUI_rt.c) declares its TUI operations
// as imports under the module name "tui". This shim implements that
// contract against a textarea-style DOM element. Pair it with an
// xterm.js (or hand-rolled) widget for a real terminal experience —
// the function bodies below are kept deliberately minimal so the
// surface stays obvious.
//
// Usage:
//   import { makeTuiShim, instantiateWithTui } from "./tui-shim.js";
//   const shim = makeTuiShim(document.getElementById("term"));
//   const { instance } = await instantiateWithTui(fetch("app.wasm"), shim);
//
// The shim closes over a `mem` reference that gets bound after
// instantiation so string args (write_str) can be decoded out of the
// wasm linear memory.

export function makeTuiShim(host) {
    // ---- output state ----------------------------------------------
    const cells = [];          // [row][col] = { ch, attr }
    let cursorRow = 0, cursorCol = 0;
    let curAttr   = 0;
    let cursorVisible = true;
    let pendingOutput = "";    // batched between flushes
    let memView   = null;      // bound after instantiation

    // ---- input state -----------------------------------------------
    const keyQueue = [];

    // host element is expected to be a <pre> or similar. We keep it
    // simple here — overwrite the textContent each flush. A real
    // implementation drives xterm.js or a canvas.
    function geometry() {
        // crude character-cell sizing: assume monospace, infer from
        // the host's clientWidth / clientHeight. Falls back to 80x24.
        const ch = host.dataset.charW ? +host.dataset.charW : 8;
        const cl = host.dataset.charH ? +host.dataset.charH : 16;
        const cols = ch ? Math.max(1, Math.floor(host.clientWidth  / ch)) : 80;
        const rows = cl ? Math.max(1, Math.floor(host.clientHeight / cl)) : 24;
        return { rows, cols };
    }

    function ensureRow(r) {
        while (cells.length <= r) cells.push([]);
        return cells[r];
    }
    function ensureCell(r, c) {
        const row = ensureRow(r);
        while (row.length <= c) row.push({ ch: " ", attr: 0 });
        return row[c];
    }

    function render() {
        // Crude: rebuild full text every flush. For a real shim, use a
        // diff or xterm.js writeBuffered.
        let out = "";
        for (let r = 0; r < cells.length; r++) {
            const row = cells[r] || [];
            for (let c = 0; c < row.length; c++) out += row[c].ch;
            out += "\n";
        }
        host.textContent = out;
    }

    // input wiring — keydown handler on the host element. The
    // mapping matches the Oberon-side key constants in TUI.Mod.
    host.tabIndex = 0;
    host.addEventListener("keydown", (e) => {
        let code = 0;
        switch (e.key) {
            case "ArrowUp":    code = 256; break;
            case "ArrowDown":  code = 257; break;
            case "ArrowLeft":  code = 258; break;
            case "ArrowRight": code = 259; break;
            case "Home":       code = 260; break;
            case "End":        code = 261; break;
            case "PageUp":     code = 262; break;
            case "PageDown":   code = 263; break;
            case "Delete":     code = 264; break;
            case "Enter":      code = 13;  break;
            case "Tab":        code = 9;   break;
            case "Escape":     code = 27;  break;
            case "Backspace":  code = 127; break;
            default:
                if (e.ctrlKey && e.key.length === 1) {
                    code = e.key.toUpperCase().charCodeAt(0) & 0x1f;
                } else if (e.altKey && e.key.length === 1) {
                    // Meta-X codes: TUI.Mod assigns 290..299 for the
                    // bound ones. Map a few here; the wasm program
                    // can ignore unknowns.
                    const map = { "<":290, ">":291, "f":292, "b":293,
                                  "a":294, "e":295, "w":296, "y":297,
                                  "n":298, "p":299 };
                    code = map[e.key] || 0;
                } else if (e.key.length === 1) {
                    code = e.key.charCodeAt(0);
                }
        }
        if (code) { keyQueue.push(code); e.preventDefault(); }
    });

    // ---- the imports object ---------------------------------------
    const imports = {
        init() {
            cells.length = 0;
            cursorRow = cursorCol = 0;
            curAttr = 0;
            host.focus();
        },
        shutdown() {
            // Nothing to release. A real shim might unsubscribe
            // keydown / resize observers.
        },
        rows() { return geometry().rows; },
        cols() { return geometry().cols; },
        clear() {
            cells.length = 0;
            cursorRow = cursorCol = 0;
            render();
        },
        clear_line() {
            cells[cursorRow] = [];
            render();
        },
        move_to(col, row) {
            cursorCol = col; cursorRow = row;
        },
        show_cursor() { cursorVisible = true;  render(); },
        hide_cursor() { cursorVisible = false; render(); },
        set_attr(attr) { curAttr = attr; },
        write_char(ch) {
            const cell = ensureCell(cursorRow, cursorCol);
            cell.ch = String.fromCharCode(ch);
            cell.attr = curAttr;
            cursorCol++;
        },
        write_str(ptr, len) {
            if (!memView) return;
            const bytes = new Uint8Array(memView.buffer, ptr, len);
            const s = new TextDecoder().decode(bytes);
            for (const ch of s) {
                const cell = ensureCell(cursorRow, cursorCol);
                cell.ch = ch; cell.attr = curAttr;
                cursorCol++;
            }
        },
        flush() { render(); },
        read_key() {
            return keyQueue.length ? keyQueue.shift() : 0;
        },
    };

    // bindMemory is called by instantiateWithTui after the wasm
    // module is up — write_str needs a live view onto wasm memory.
    function bindMemory(memory) { memView = new Uint8Array(memory.buffer); }

    return { imports, bindMemory };
}

// Convenience wrapper: fetch + instantiate + bind. Source can be a
// Response (from fetch) or a Promise<Response>; falls through to
// WebAssembly.instantiateStreaming.
export async function instantiateWithTui(source, shim, extraImports = {}) {
    const importObject = { tui: shim.imports, ...extraImports };
    const result = await WebAssembly.instantiateStreaming(source, importObject);
    shim.bindMemory(result.instance.exports.memory);
    return result;
}
