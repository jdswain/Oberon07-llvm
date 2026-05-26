// TUI shim for the wasm runtime. Implements the "tui" import module
// declared in runtime/wasm/TUI_rt.c against a DOM <div> element
// rendered as a fixed-cell grid. Limited 8-colour palette matching
// the IBM 3270 / 5250 family — close to ANSI but with a tighter
// hue range so monochrome and colour displays look similar.

import { readStr, dispatchKey } from "./wasm-mem.js";

// ---- Attribute bits (must match TUI.Mod AttrReverse/Bold/Italic/Underline)
const ATTR_REVERSE   = 1;
const ATTR_BOLD      = 2;
const ATTR_ITALIC    = 4;
const ATTR_UNDERLINE = 8;

// 3270-style palette. Index matches TUI.ColorBlack..ColorWhite;
// -1 means "default" and triggers a CSS reset.
const PALETTE: ReadonlyArray<string> = [
  "#000000", // 0 Black
  "#0050ff", // 1 Blue
  "#ff3030", // 2 Red
  "#ff66cc", // 3 Pink
  "#00cc66", // 4 Green
  "#00cccc", // 5 Turquoise
  "#ffd000", // 6 Yellow
  "#f0f0f0", // 7 White
];

function colorCss(i: number, deflt: string): string {
  if (i < 0 || i > 7) return deflt;
  return PALETTE[i];
}

interface Cell {
  ch:    string;
  attr:  number;
  fg:    number;     // -1 = default
  bg:    number;
}

const KEY_MAP: Record<string, number> = {
  ArrowUp:   256, ArrowDown:  257, ArrowLeft: 258, ArrowRight: 259,
  Home:      260, End:        261, PageUp:    262, PageDown:   263,
  Delete:    264,
  Enter:      13, Tab:          9, Escape:     27, Backspace: 127,
};

const META_MAP: Record<string, number> = {
  "<": 290, ">": 291, f: 292, b: 293, a: 294,
  e:   295, w:   296, y: 297, n: 298, p: 299,
};

export interface TuiShim {
  imports: WebAssembly.ModuleImports;
}

/** Build a TUI shim bound to a DOM container element. The element
 *  is repurposed as a fixed-cell grid — each row becomes a span per
 *  cell so per-cell color/style can be applied. The container
 *  should be styled with a monospace font and tabindex=0 so it can
 *  take keyboard focus. */
export function makeTuiShim(host: HTMLElement): TuiShim {
  let cells: Cell[][] = [];
  let curCol = 0, curRow = 0;
  let curAttr = 0;
  let curFg = -1;
  let curBg = -1;
  let cursorVisible = true;
  let dirty = false;

  const keyQueue: number[] = [];
  host.tabIndex = 0;
  host.style.outline = "none";

  // Geometry — driven by clientWidth / clientHeight and the cell
  // metrics measured below. Recomputed by js_rows / js_cols at
  // every Init / Resize.
  let cellW = 9;
  let cellH = 18;
  let rows = 24;
  let cols = 80;

  function measureCell(): void {
    // Build a probe that matches the row structure (`<div><span>M</span></div>`)
    // so cellH reflects the actual rendered row height — including any
    // CSS height/line-height locking on `#term div`. Measuring a bare
    // span misses that and can let cellH drift away from div height by
    // a subpixel, which feeds back into recomputeDims.
    const probeDiv = document.createElement("div");
    const probe    = document.createElement("span");
    probe.textContent = "M";
    probeDiv.appendChild(probe);
    probeDiv.style.visibility = "hidden";
    probeDiv.style.position   = "absolute";
    probeDiv.style.left       = "-9999px";
    host.appendChild(probeDiv);
    cellW = probe.offsetWidth     || cellW;
    cellH = probeDiv.offsetHeight || cellH;
    probeDiv.remove();
  }

  function recomputeDims(): void {
    measureCell();
    cols = Math.max(1, Math.floor(host.clientWidth  / cellW));
    rows = Math.max(1, Math.floor(host.clientHeight / cellH));
  }

  // Clamp writes to the current viewport. No scrolling is implemented;
  // anything past the bottom/right would otherwise grow `cells`
  // unboundedly, which feeds back into `rows()` (the DOM gets taller
  // → host.clientHeight grows → recomputed rows grows → caller writes
  // more rows next frame → runaway). The TUI contract gives callers a
  // fixed grid via rows()/cols(); clamping enforces that.
  function ensureCell(r: number, c: number): Cell {
    if (r >= rows) r = rows - 1;
    if (c >= cols) c = cols - 1;
    if (r < 0) r = 0;
    if (c < 0) c = 0;
    while (cells.length <= r) cells.push([]);
    const row = cells[r];
    while (row.length <= c) row.push({ ch: " ", attr: 0, fg: -1, bg: -1 });
    return row[c];
  }

  // Two cells share style iff every visual attribute matches. This
  // is the grouping key for emitting runs as single spans (see
  // renderRun below) — runs of like-styled cells get one span, which
  // lets the browser lay out their characters as continuous
  // monospace text rather than one inline-block per glyph (which
  // accumulates sub-pixel drift on certain chars/fallback fonts).
  function sameStyle(a: Cell, b: Cell): boolean {
    return a.attr === b.attr && a.fg === b.fg && a.bg === b.bg;
  }

  function styleSpan(text: string, c: Cell): HTMLSpanElement {
    const sp = document.createElement("span");
    sp.textContent = text;
    const fg = colorCss(c.fg, "");
    const bg = colorCss(c.bg, "");
    if (fg) sp.style.color           = fg;
    if (bg) sp.style.backgroundColor = bg;
    if (c.attr & ATTR_REVERSE) {
      const fgOut = bg || "var(--tui-bg, #000)";
      const bgOut = fg || "var(--tui-fg, #eee)";
      sp.style.color           = fgOut;
      sp.style.backgroundColor = bgOut;
    }
    if (c.attr & ATTR_BOLD)      sp.style.fontWeight     = "bold";
    if (c.attr & ATTR_ITALIC)    sp.style.fontStyle      = "italic";
    if (c.attr & ATTR_UNDERLINE) sp.style.textDecoration = "underline";
    return sp;
  }

  // Paint one logical row. Walks `cells[r]` building runs of cells
  // that share a style and emitting each run as a single span. The
  // cursor, when in this row, is forced to be its own one-char run
  // with cursor colours overlayed.
  function paintRow(r: number): HTMLDivElement {
    const line = document.createElement("div");
    const row = cells[r] || [];

    // Padding: if the cursor lies past the row's content, fill the
    // gap with default cells so the cursor has somewhere to land.
    const isCursorRow = cursorVisible && r === curRow;
    const need = isCursorRow ? Math.max(row.length, curCol + 1) : row.length;
    const pad: Cell = { ch: " ", attr: 0, fg: -1, bg: -1 };

    let runStart = 0;
    while (runStart < need) {
      const startCell = row[runStart] || pad;
      // Cursor cell is its own one-character run regardless of style.
      if (isCursorRow && runStart === curCol) {
        const sp = styleSpan(startCell.ch || " ", startCell);
        sp.style.backgroundColor = "var(--tui-cursor, #ffd000)";
        sp.style.color           = "var(--tui-bg, #000)";
        line.appendChild(sp);
        runStart++;
        continue;
      }
      let end = runStart + 1;
      while (end < need) {
        const c = row[end] || pad;
        if (isCursorRow && end === curCol) break;
        if (!sameStyle(c, startCell)) break;
        end++;
      }
      let text = "";
      for (let i = runStart; i < end; i++) text += (row[i] || pad).ch;
      line.appendChild(styleSpan(text, startCell));
      runStart = end;
    }
    return line;
  }

  function render(): void {
    const frag = document.createDocumentFragment();
    // Iterate up to `rows`, not cells.length, so the DOM has exactly
    // one div per viewport row — fixes the feedback loop where extra
    // cells made the host taller, which made the next rows() call
    // report more rows.
    for (let r = 0; r < rows; r++) frag.appendChild(paintRow(r));
    host.replaceChildren(frag);
    dirty = false;
  }

  // Window-resize → repaint. We can't push a "viewport changed"
  // signal directly into the wasm program; the cheapest wakeup is
  // to dispatch Ctrl-L (the editor's redraw key, a no-op for state
  // but it forces a Refresh which in turn calls TUI.Resize). Debounce
  // through requestAnimationFrame so a drag-resize doesn't fire
  // hundreds of dispatches per second.
  let resizeQueued = false;
  function scheduleResize(): void {
    if (resizeQueued) return;
    resizeQueued = true;
    requestAnimationFrame(() => {
      resizeQueued = false;
      dispatchKey(12);    // Ctrl-L
    });
  }
  window.addEventListener("resize", scheduleResize);

  host.addEventListener("keydown", (e: KeyboardEvent) => {
    let code = 0;
    if (KEY_MAP[e.key] !== undefined) {
      code = KEY_MAP[e.key];
    } else if (e.ctrlKey && e.key.length === 1) {
      code = e.key.toUpperCase().charCodeAt(0) & 0x1f;
    } else if (e.altKey && META_MAP[e.key] !== undefined) {
      code = META_MAP[e.key];
    } else if (e.key.length === 1) {
      code = e.key.charCodeAt(0);
    }
    if (!code) return;
    e.preventDefault();
    // Event-driven path: dispatch straight into the wasm if it
    // exports oc_dispatch_key (i.e. the program uses TUI.Run /
    // TUI.SetKeyHandler). Otherwise fall back to the polling queue
    // for programs that read with TUI.ReadKey directly.
    if (!dispatchKey(code)) {
      keyQueue.push(code);
    }
  });

  const imports: WebAssembly.ModuleImports = {
    init(): void {
      cells = [];
      curCol = curRow = 0;
      curAttr = 0; curFg = -1; curBg = -1;
      cursorVisible = true;
      recomputeDims();
      render();
      host.focus();
    },
    shutdown(): void {
      // Nothing to release — JS GC handles it. The element keeps
      // whatever was last rendered.
    },
    rows(): number { recomputeDims(); return rows; },
    cols(): number { recomputeDims(); return cols; },
    clear(): void {
      cells = [];
      curCol = curRow = 0;
      dirty = true;
    },
    clear_line(): void {
      if (curRow >= 0 && curRow < rows) cells[curRow] = [];
      dirty = true;
    },
    move_to(col: number, row: number): void {
      curCol = Math.max(0, Math.min(col, cols - 1));
      curRow = Math.max(0, Math.min(row, rows - 1));
      dirty = true;
    },
    show_cursor(): void { cursorVisible = true;  dirty = true; },
    hide_cursor(): void { cursorVisible = false; dirty = true; },
    set_attr(attr: number): void { curAttr = attr; },
    set_fg(c: number): void { curFg = c; },
    set_bg(c: number): void { curBg = c; },
    write_char(ch: number): void {
      const cell = ensureCell(curRow, curCol);
      cell.ch = String.fromCharCode(ch);
      cell.attr = curAttr; cell.fg = curFg; cell.bg = curBg;
      curCol++; dirty = true;
    },
    write_str(ptr: number, len: number): void {
      const s = readStr(ptr, len);
      for (const ch of s) {
        if (ch === "\n") { curRow++; curCol = 0; continue; }
        const cell = ensureCell(curRow, curCol);
        cell.ch = ch;
        cell.attr = curAttr; cell.fg = curFg; cell.bg = curBg;
        curCol++;
      }
      dirty = true;
    },
    flush(): void { if (dirty) render(); },
    read_key(): number {
      return keyQueue.length ? keyQueue.shift()! : 0;
    },
  };

  return { imports };
}
