MODULE L10_SystemSize;
  IMPORT SYSTEM, Out;
  TYPE Rec = RECORD a, b: INTEGER END;
  VAR arr: ARRAY 10 OF INTEGER;
BEGIN
  Out.Int(SYSTEM.SIZE(INTEGER), 1); Out.Ln();
  Out.Int(SYSTEM.SIZE(CHAR), 1); Out.Ln();
  Out.Int(SYSTEM.SIZE(BOOLEAN), 1); Out.Ln();
  Out.Int(SYSTEM.SIZE(Rec), 1); Out.Ln();
  Out.Int(SYSTEM.SIZE(BYTE), 1); Out.Ln()
END L10_SystemSize.
