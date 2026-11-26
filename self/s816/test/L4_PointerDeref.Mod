MODULE L4_PointerDeref;
  IMPORT Out, HeapManager;
  TYPE Rec = RECORD x, y: INTEGER END;
       Ptr = POINTER TO Rec;
  VAR p: Ptr;

BEGIN
  NEW(p);
  p.x := 42;
  p.y := 7;
  Out.Int(p.x, 1); Out.Ln();
  Out.Int(p.y, 1); Out.Ln();
  Out.Int(p.x + p.y, 1); Out.Ln()
END L4_PointerDeref.
