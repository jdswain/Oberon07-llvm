MODULE ParamLen;
(* Minimal reproducer for an oc startup bug seen 2026-05-17.

   Adding a procedure with signature

     PROCEDURE p(b: Buffer; n: INTEGER;
                 VAR a, b, c: INTEGER): BOOLEAN;

   to Oed.Mod made the resulting binary exit silently at startup
   (no output, exit 0) — even though the procedure is never called.
   Bisecting parameter NAMES localised the trigger to the total
   length of the three VAR names exceeding 17 characters:

     VAR aaaaaaa, bbbbb, ccccc : 7+5+5 = 17 → binary runs
     VAR aaaaaaaa, bbbbb, ccccc: 8+5+5 = 18 → binary exits at startup
     VAR aaaaaa, bbbbb, ccccc  : 6+5+5 = 16 → binary runs
     VAR aaaaaa, bbbbbb, cccccc: 6+6+6 = 18 → binary exits at startup
     VAR textEnd, urlStart, urlEnd: 7+8+6 = 21 → binary exits at startup

   Resolved 2026-05-17. Root cause was not the parameter names but
   the source-text buffer size in src/Texts.c: MAX_TEXT_LEN was
   64 KB and Oed.Mod had grown past that, so fread silently
   truncated the source. The scanner hit EOF mid-module-body and
   the parser quietly emitted stubs for everything past the
   truncation point — including Oed.Run's WHILE loop. The "1-char
   rename anywhere flips startup" surface was the rename shifting
   downstream bytes across the truncation boundary.

   The fix sizes the source-text buffer to fstat() of the input
   (capped at MAX_TEXT_LEN_HARD = 16 MB) so realistic modules never
   truncate. ParamLen.Mod stays as a regression marker; it builds
   and runs cleanly. *)

  IMPORT Out;

  TYPE
    Buffer = POINTER TO BufferDesc;
    BufferDesc = RECORD x: INTEGER END;

  PROCEDURE breakOn18(b: Buffer; openPos: INTEGER;
                      VAR aaaaaaaa, bbbbb, ccccc: INTEGER): BOOLEAN;
  BEGIN
    RETURN FALSE
  END breakOn18;

  PROCEDURE worksAt17(b: Buffer; openPos: INTEGER;
                     VAR aaaaaaa, bbbbb, ccccc: INTEGER): BOOLEAN;
  BEGIN
    RETURN FALSE
  END worksAt17;

BEGIN
  Out.WriteString("ParamLen body ran"); Out.Ln()
END ParamLen.
