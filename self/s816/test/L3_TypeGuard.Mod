MODULE L3_TypeGuard;
  IMPORT Out, HeapManager;
  TYPE
    Base = RECORD x: INTEGER END;
    Derived = RECORD (Base) y: INTEGER END;
    PBase = POINTER TO Base;
    PDerived = POINTER TO Derived;
  VAR pb: PBase; pd: PDerived;
BEGIN
  NEW(pd); pd.x := 42; pd.y := 99;
  pb := pd;
  Out.Int(pb(PDerived).y, 0); Out.Ln
END L3_TypeGuard.
