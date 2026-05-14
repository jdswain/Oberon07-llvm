MODULE TUI;
(* Terminal user interface for oed.

   The procedure bodies are empty stubs; the strong implementations live
   in TUI_rt.c and override at link time. Init switches the controlling
   terminal to raw mode and registers an atexit hook so the cooked
   settings are restored even if the program exits abnormally.

   ASCII keys (bytes 0..127) come back from ReadKey as themselves.
   Recognised escape sequences for arrows, navigation and editing keys
   are condensed into the synthetic codes 256..264 so a CASE statement
   can dispatch on them uniformly.

   Output is buffered. Call Flush before ReadKey or any external sleep
   so partial frames do not stay invisible. ReadKey itself flushes. *)

  CONST
    (* Direct ASCII codes returned by ReadKey. *)
    KeyCtrlSpace* =   0;        (* terminal-dependent; works on macOS Terminal *)
    KeyTab*       =   9;
    KeyEnter*     =  13;
    KeyEscape*    =  27;
    KeyBackspace* = 127;

    (* Ctrl + letter — bytes 1..26. Provided as named constants so call
       sites read intent rather than magic numbers. *)
    KeyCtrlA*  =  1; KeyCtrlB*  =  2; KeyCtrlC*  =  3; KeyCtrlD*  =  4;
    KeyCtrlE*  =  5; KeyCtrlF*  =  6; KeyCtrlG*  =  7; KeyCtrlH*  =  8;
    KeyCtrlI*  =  9; KeyCtrlJ*  = 10; KeyCtrlK*  = 11; KeyCtrlL*  = 12;
    KeyCtrlM*  = 13; KeyCtrlN*  = 14; KeyCtrlO*  = 15; KeyCtrlP*  = 16;
    KeyCtrlQ*  = 17; KeyCtrlR*  = 18; KeyCtrlS*  = 19; KeyCtrlT*  = 20;
    KeyCtrlU*  = 21; KeyCtrlV*  = 22; KeyCtrlW*  = 23; KeyCtrlX*  = 24;
    KeyCtrlY*  = 25; KeyCtrlZ*  = 26;

    (* Synthetic codes for keys that arrive as multi-byte CSI sequences.
       Values >= 256 keep them outside the byte range. *)
    KeyArrowUp*    = 256;
    KeyArrowDown*  = 257;
    KeyArrowLeft*  = 258;
    KeyArrowRight* = 259;
    KeyHome*       = 260;
    KeyEnd*        = 261;
    KeyPageUp*     = 262;
    KeyPageDown*   = 263;
    KeyDelete*     = 264;

    (* Meta keys: ESC followed by an ASCII char. Only the few we
       currently bind are decoded; other Meta-X arrive as plain Esc. *)
    KeyMetaLT*     = 290;       (* M-<  : jump to start of buffer *)
    KeyMetaGT*     = 291;       (* M->  : jump to end of buffer *)
    KeyMetaF*      = 292;       (* M-f  : forward word *)
    KeyMetaB*      = 293;       (* M-b  : backward word *)
    KeyMetaA*      = 294;       (* M-a  : backward sentence *)
    KeyMetaE*      = 295;       (* M-e  : forward sentence *)
    KeyMetaW*      = 296;       (* M-w  : copy region *)
    KeyMetaY*      = 297;       (* M-y  : yank-pop / kill-ring rotation *)
    KeyMetaN*      = 298;       (* M-n  : next record (form view) *)
    KeyMetaP*      = 299;       (* M-p  : previous record (form view) *)

    (* Display attributes. Bit-OR together for SetAttr. *)
    AttrNormal*  = 0;
    AttrReverse* = 1;
    AttrBold*    = 2;

  VAR
    (* Terminal dimensions in cells. Updated by Init and Resize. *)
    Rows*: INTEGER;
    Cols*: INTEGER;

  PROCEDURE Init*;
  BEGIN
  END Init;

  PROCEDURE Shutdown*;
  BEGIN
  END Shutdown;

  PROCEDURE Resize*;
  BEGIN
  END Resize;

  PROCEDURE Clear*;
  BEGIN
  END Clear;

  PROCEDURE ClearLine*;
  BEGIN
  END ClearLine;

  PROCEDURE MoveTo*(col, row: INTEGER);
  BEGIN
  END MoveTo;

  PROCEDURE ShowCursor*;
  BEGIN
  END ShowCursor;

  PROCEDURE HideCursor*;
  BEGIN
  END HideCursor;

  PROCEDURE SetAttr*(attr: INTEGER);
  BEGIN
  END SetAttr;

  PROCEDURE Write*(ch: CHAR);
  BEGIN
  END Write;

  PROCEDURE WriteStr*(s: ARRAY OF CHAR);
  BEGIN
  END WriteStr;

  PROCEDURE WriteInt*(n: INTEGER);
  BEGIN
  END WriteInt;

  PROCEDURE Flush*;
  BEGIN
  END Flush;

  PROCEDURE ReadKey*(): INTEGER;
  BEGIN RETURN 0
  END ReadKey;

END TUI.
