MODULE L3_TypeExtension;
  IMPORT Out, HeapManager;
  TYPE
    Base = RECORD x: INTEGER END;
    Derived = RECORD (Base) y: INTEGER END;
  VAR pb: POINTER TO Base; pd: POINTER TO Derived;
BEGIN
  NEW(pd); pd.x := 10; pd.y := 20;
  pb := pd;
  Out.Int(pb.x, 0); Out.Ln;
  Out.Int(pd.y, 0); Out.Ln
END L3_TypeExtension.
