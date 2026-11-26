MODULE L9_CrossTypeTest;
  IMPORT Out, L9_TypeBase, HeapManager;
  TYPE
    Ext2 = RECORD (L9_TypeBase.Base) z: INTEGER END;
    PExt2 = POINTER TO Ext2;
  VAR pb: L9_TypeBase.PBase;
      p1: L9_TypeBase.PExt1;
      p2: PExt2;
      b: BOOLEAN;

  PROCEDURE TestVar(VAR r: L9_TypeBase.Base);
  BEGIN
    IF r IS L9_TypeBase.Ext1 THEN Out.Int(1, 0)
    ELSIF r IS Ext2 THEN Out.Int(2, 0)
    ELSE Out.Int(0, 0)
    END;
    Out.Ln
  END TestVar;

BEGIN
  (* Test pointer IS across modules *)
  NEW(p1); p1.x := 10; p1.y := 20;
  pb := p1;
  b := pb IS L9_TypeBase.PExt1;
  IF b THEN Out.Int(1, 0) ELSE Out.Int(0, 0) END;
  Out.Ln;

  (* Test VAR param type test across modules *)
  TestVar(p1^);

  (* Test type guard across modules *)
  Out.Int(pb(L9_TypeBase.PExt1).y, 0); Out.Ln
END L9_CrossTypeTest.
