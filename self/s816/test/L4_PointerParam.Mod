MODULE L4_PointerParam;
  IMPORT Out, HeapManager;
  TYPE Rec = RECORD val: INTEGER END;
       Ptr = POINTER TO Rec;
  VAR p: Ptr;

  PROCEDURE ReadVal(ptr: Ptr): INTEGER;
  BEGIN RETURN ptr.val
  END ReadVal;

  PROCEDURE SetVal(VAR ptr: Ptr; v: INTEGER);
  BEGIN
    NEW(ptr);
    ptr.val := v
  END SetVal;

BEGIN
  SetVal(p, 123);
  Out.Int(p.val, 1); Out.Ln();
  Out.Int(ReadVal(p), 1); Out.Ln()
END L4_PointerParam.
