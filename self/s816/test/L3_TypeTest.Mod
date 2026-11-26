MODULE L3_TypeTest;
  IMPORT Out, HeapManager;
  TYPE
    Base = RECORD x: INTEGER END;
    Ext1 = RECORD (Base) y: INTEGER END;
    Ext2 = RECORD (Base) z: INTEGER END;
    PBase = POINTER TO Base;
    PExt1 = POINTER TO Ext1;
    PExt2 = POINTER TO Ext2;
  VAR pb: PBase; p1: PExt1;
    b: BOOLEAN;
BEGIN
  NEW(p1); p1.x := 1; p1.y := 2;
  pb := p1;
  b := pb IS PExt1;
  IF b THEN Out.Int(1, 0) ELSE Out.Int(0, 0) END;
  Out.Ln;
  b := pb IS PExt2;
  IF b THEN Out.Int(1, 0) ELSE Out.Int(0, 0) END;
  Out.Ln
END L3_TypeTest.
