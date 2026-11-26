MODULE L3_VarRecordTypeTest;
  IMPORT Out;
  TYPE
    Base = RECORD x: INTEGER END;
    Ext1 = RECORD (Base) y: INTEGER END;
    Ext2 = RECORD (Base) z: INTEGER END;
  VAR b: Base; e1: Ext1; e2: Ext2;

  PROCEDURE Test(VAR r: Base);
  BEGIN
    IF r IS Ext1 THEN Out.Int(1, 0)
    ELSIF r IS Ext2 THEN Out.Int(2, 0)
    ELSE Out.Int(0, 0)
    END;
    Out.Ln
  END Test;

  PROCEDURE Guard(VAR r: Base);
  BEGIN
    Out.Int(r(Ext1).y, 0); Out.Ln
  END Guard;

BEGIN
  e1.x := 10; e1.y := 42;
  e2.x := 20; e2.z := 99;
  b.x := 30;
  Test(e1);
  Test(e2);
  Test(b);
  Guard(e1)
END L3_VarRecordTypeTest.
