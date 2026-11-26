MODULE L4_PointerLocal;
  IMPORT Out, HeapManager;
  TYPE Rec = RECORD a, b: INTEGER END;
       Ptr = POINTER TO Rec;

  PROCEDURE Work;
    VAR p: Ptr;
  BEGIN
    NEW(p);
    p.a := 10;
    p.b := 20;
    Out.Int(p.a, 1); Out.Ln();
    Out.Int(p.b, 1); Out.Ln();
    Out.Int(p.a + p.b, 1); Out.Ln()
  END Work;

BEGIN
  Work
END L4_PointerLocal.
