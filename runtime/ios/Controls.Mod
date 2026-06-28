MODULE Controls;
(* Small control toolkit on top of TUI primitives.

   Three building blocks, all reusable across whatever UI the host
   program puts together:

     Cell      a string + optional "highlighted" flag.
     View      a rectangle on the screen with absolute origin and
               size, painted via TUI primitives.
     ListView  a View showing rows pulled from a CellSource, with
               vertical scrolling, a single highlighted selection,
               and a key-handler that emits Open / Back events.

   The controls are intentionally narrow — they don't know about
   any concrete data source (filesystem, buffer registry, command
   palette …). A host module supplies a CellSource and reacts to
   the events ListHandleKey returns. *)

  IMPORT TUI;

  CONST
    (* Width of the text Cell holds. Wider than typical menu entries
       so file paths or buffer labels fit without truncation. *)
    MaxCellText* = 256;

    (* Events emitted by ListHandleKey. None means the key was
       absorbed by selection / scroll; Open / Back are the user's
       intent to act on or step out of the current row. *)
    ListEventNone* = 0;
    ListEventOpen* = 1;       (* Tab / Enter / Right *)
    ListEventBack* = 2;       (* Left *)

    (* Type-ahead buffer: cap on how much prefix the user can type
       to narrow the selection. Longer than typical file or buffer
       names so over-typing is rare. *)
    MaxSearch = 64;

  TYPE
    Cell* = RECORD
      text*:        ARRAY MaxCellText OF CHAR;
      highlighted*: BOOLEAN     (* drawn with bold / extra emphasis *)
    END;

    View* = RECORD
      x*, y*: INTEGER;          (* top-left in absolute screen cells *)
      w*, h*: INTEGER           (* width and height in cells *)
    END;

    CellSource* = PROCEDURE(index: INTEGER; VAR c: Cell): BOOLEAN;
    (* Returns TRUE if `index` is in range and c has been filled. *)

    ListView* = RECORD
      view*:     View;
      src*:      CellSource;
      nCells*:   INTEGER;
      selected*: INTEGER;
      topRow*:   INTEGER;       (* index of the row drawn at view.y *)
      (* Type-ahead state. Each printable key appends to searchBuf
         and jumps to the first cell whose text starts with the
         accumulated prefix (case-insensitive). Any non-printable
         key resets searchLen to 0. *)
      searchBuf: ARRAY MaxSearch OF CHAR;
      searchLen: INTEGER
    END;

  (* ---- View ---- *)

  (* Clear v's rectangle by overwriting each row with spaces.
     ClearLine would scrub the whole terminal row past v.w, so we
     emit explicit spaces instead. *)
  PROCEDURE ViewClear*(v: View);
    VAR row, col: INTEGER;
  BEGIN
    row := 0;
    WHILE row < v.h DO
      TUI.MoveTo(v.x, v.y + row);
      col := 0;
      WHILE col < v.w DO TUI.Write(" "); INC(col) END;
      INC(row)
    END
  END ViewClear;

  (* ---- ListView ---- *)

  PROCEDURE ListInit*(VAR lv: ListView; v: View;
                      src: CellSource; n: INTEGER);
  BEGIN
    lv.view := v;
    lv.src := src;
    lv.nCells := n;
    lv.selected := 0;
    lv.topRow := 0;
    lv.searchLen := 0
  END ListInit;

  (* Reset selection / scroll / type-ahead buffer without disturbing
     view, src, or nCells. Call after the host has reloaded the
     underlying data so a previously-used ListView doesn't carry
     stale state into the new content. *)
  PROCEDURE ListReset*(VAR lv: ListView);
  BEGIN
    lv.selected := 0;
    lv.topRow := 0;
    lv.searchLen := 0
  END ListReset;

  (* Adjust topRow so `selected` falls within [topRow, topRow + h). *)
  PROCEDURE ListEnsureVisible*(VAR lv: ListView);
  BEGIN
    IF lv.selected < lv.topRow THEN
      lv.topRow := lv.selected
    ELSIF lv.selected >= lv.topRow + lv.view.h THEN
      lv.topRow := lv.selected - lv.view.h + 1
    END;
    IF lv.topRow < 0 THEN lv.topRow := 0 END
  END ListEnsureVisible;

  PROCEDURE writePadded(text: ARRAY OF CHAR; width: INTEGER);
    VAR i, n: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(text)) & (i < width) & (text[i] # 0X) DO
      TUI.Write(text[i]); INC(i)
    END;
    n := i;
    WHILE n < width DO TUI.Write(" "); INC(n) END
  END writePadded;

  PROCEDURE ListPaint*(VAR lv: ListView);
    VAR row, idx, attr: INTEGER; c: Cell; ok: BOOLEAN;
  BEGIN
    ListEnsureVisible(lv);
    row := 0;
    WHILE row < lv.view.h DO
      TUI.MoveTo(lv.view.x, lv.view.y + row);
      idx := lv.topRow + row;
      IF (idx >= 0) & (idx < lv.nCells) THEN
        ok := lv.src(idx, c);
        IF ok THEN
          attr := TUI.AttrNormal;
          IF idx = lv.selected THEN attr := attr + TUI.AttrReverse END;
          IF c.highlighted     THEN attr := attr + TUI.AttrBold    END;
          TUI.SetAttr(attr);
          (* Highlighted cells (e.g. directories in the file browser)
             get a distinct foreground; plain cells use the
             terminal's default fg. *)
          IF c.highlighted THEN
            TUI.SetFg(TUI.ColorBlue)
          ELSE
            TUI.SetFg(TUI.ColorDefault)
          END;
          writePadded(c.text, lv.view.w);
          TUI.SetAttr(TUI.AttrNormal);
          TUI.SetFg(TUI.ColorDefault)
        ELSE
          writePadded("", lv.view.w)
        END
      ELSE
        (* Past end of list — blank the row. *)
        writePadded("", lv.view.w)
      END;
      INC(row)
    END
  END ListPaint;

  PROCEDURE toLower(ch: CHAR): CHAR;
    VAR out: CHAR;
  BEGIN
    IF (ch >= "A") & (ch <= "Z") THEN
      out := CHR(ORD(ch) + 32)
    ELSE
      out := ch
    END;
    RETURN out
  END toLower;

  (* True if `text` begins with `prefix` (length `pLen`), case-
     insensitive. text is NUL-terminated; prefix may not be. *)
  PROCEDURE startsWithCI(text: ARRAY OF CHAR;
                         prefix: ARRAY OF CHAR; pLen: INTEGER): BOOLEAN;
    VAR i: INTEGER; ok: BOOLEAN;
  BEGIN
    ok := TRUE; i := 0;
    WHILE ok & (i < pLen) DO
      IF (text[i] = 0X) OR (toLower(text[i]) # toLower(prefix[i])) THEN
        ok := FALSE
      END;
      INC(i)
    END;
    RETURN ok
  END startsWithCI;

  (* First index whose cell text matches the buffer, or -1. *)
  PROCEDURE findPrefix(lv: ListView;
                       prefix: ARRAY OF CHAR; pLen: INTEGER): INTEGER;
    VAR i, found: INTEGER; c: Cell;
  BEGIN
    found := -1; i := 0;
    WHILE (i < lv.nCells) & (found = -1) DO
      IF lv.src(i, c) & startsWithCI(c.text, prefix, pLen) THEN
        found := i
      END;
      INC(i)
    END;
    RETURN found
  END findPrefix;

  (* Process one key against the list.

       Up / Down / PageUp / PageDown / Home / End — mutate
         selected / topRow, emit ListEventNone.
       Tab / Enter / Right — emit ListEventOpen.
       Left — emit ListEventBack.
       Printable ASCII — extend type-ahead buffer; if the prefix
         matches some cell, jump selection there. If appending
         produces no match the new char is dropped so the buffer
         remains a valid prefix.
     Any non-printable key clears the type-ahead buffer so the
     next prefix starts fresh after the user navigates. *)
  PROCEDURE ListHandleKey*(VAR lv: ListView; k: INTEGER;
                           VAR ev: INTEGER);
    VAR idx: INTEGER; ch: CHAR;
  BEGIN
    ev := ListEventNone;
    IF (k >= 32) & (k < 127) THEN
      IF lv.searchLen < MaxSearch - 1 THEN
        ch := CHR(k);
        lv.searchBuf[lv.searchLen] := ch;
        INC(lv.searchLen);
        lv.searchBuf[lv.searchLen] := 0X;
        idx := findPrefix(lv, lv.searchBuf, lv.searchLen);
        IF idx >= 0 THEN
          lv.selected := idx
        ELSE
          (* No cell matches the extended prefix; drop the char so
             the next keystroke can still build on what worked. *)
          DEC(lv.searchLen);
          lv.searchBuf[lv.searchLen] := 0X
        END
      END
    ELSIF (k = TUI.KeyBackspace) OR (k = TUI.KeyCtrlH) THEN
      (* Shrink the type-ahead buffer one char and re-search. With
         an empty buffer backspace is a no-op (the cursor stays
         put). Selection only changes if the shorter prefix still
         matches a different first cell. *)
      IF lv.searchLen > 0 THEN
        DEC(lv.searchLen);
        lv.searchBuf[lv.searchLen] := 0X;
        IF lv.searchLen > 0 THEN
          idx := findPrefix(lv, lv.searchBuf, lv.searchLen);
          IF idx >= 0 THEN lv.selected := idx END
        END
      END
    ELSE
      lv.searchLen := 0;
      IF (k = TUI.KeyArrowUp) OR (k = TUI.KeyCtrlP) THEN
        IF lv.selected > 0 THEN DEC(lv.selected) END
      ELSIF (k = TUI.KeyArrowDown) OR (k = TUI.KeyCtrlN) THEN
        IF lv.selected + 1 < lv.nCells THEN INC(lv.selected) END
      ELSIF k = TUI.KeyPageUp THEN
        lv.selected := lv.selected - lv.view.h;
        IF lv.selected < 0 THEN lv.selected := 0 END
      ELSIF k = TUI.KeyPageDown THEN
        lv.selected := lv.selected + lv.view.h;
        IF lv.selected >= lv.nCells THEN lv.selected := lv.nCells - 1 END;
        IF lv.selected < 0 THEN lv.selected := 0 END
      ELSIF k = TUI.KeyHome THEN
        lv.selected := 0
      ELSIF k = TUI.KeyEnd THEN
        IF lv.nCells > 0 THEN lv.selected := lv.nCells - 1 END
      ELSIF (k = TUI.KeyTab) OR (k = TUI.KeyEnter)
          OR (k = TUI.KeyArrowRight) THEN
        ev := ListEventOpen
      ELSIF k = TUI.KeyArrowLeft THEN
        ev := ListEventBack
      END
    END
  END ListHandleKey;

END Controls.
