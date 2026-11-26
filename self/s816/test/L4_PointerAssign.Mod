MODULE L4_PointerAssign;
  IMPORT Out, HeapManager;
  TYPE Rec = RECORD val: INTEGER END;
       Ptr = POINTER TO Rec;
  VAR p, q: Ptr;

BEGIN
  NEW(p);
  p.val := 99;
  q := p;
  Out.Int(q.val, 1); Out.Ln();
  q.val := 55;
  Out.Int(p.val, 1); Out.Ln();
  IF p = q THEN Out.Int(1, 1); Out.Ln() END
END L4_PointerAssign.
