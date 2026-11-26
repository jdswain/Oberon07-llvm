MODULE L17_IfExt;
  (* a record implementing an IMPORTED interface — the base module dispatches
     an implementation it has never seen *)
  IMPORT L17_IfBase, HeapManager;
  TYPE
    Disc* = POINTER TO DiscDesc;
    DiscDesc* = RECORD IMPLEMENTS L17_IfBase.Shape r*: INTEGER END;
  PROCEDURE (d: Disc) Area* (): INTEGER; BEGIN RETURN 3 * d.r * d.r END Area;
  PROCEDURE (d: Disc) Kind* (): INTEGER; BEGIN RETURN 2 END Kind;
  PROCEDURE NewDisc* (r: INTEGER): Disc; VAR d: Disc; BEGIN NEW(d); d.r := r; RETURN d END NewDisc;
END L17_IfExt.
