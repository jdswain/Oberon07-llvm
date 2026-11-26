MODULE L18_CallCmp; (* = 0 and # 0 of a procedure's or method's result: A loaded,
   not the flags of the call's cleanup *)
  IMPORT Out, HeapManager;
  TYPE P = POINTER TO R; R = RECORD a: INTEGER END;
  VAR p: P; d: ARRAY 4 OF BYTE;
  PROCEDURE (q: P) M(t: INTEGER; VAR x: ARRAY OF BYTE; n: INTEGER): INTEGER;
  BEGIN x[0] := 5; RETURN t
  END M;
  PROCEDURE F(t: INTEGER): INTEGER; BEGIN RETURN t END F;
  PROCEDURE T(q: P; t: INTEGER): INTEGER;
    VAR k: INTEGER; x: ARRAY 4 OF BYTE;
  BEGIN k := -1;
    IF q.M(t, x, 4) = 0 THEN k := 1 END
  RETURN k
  END T;
BEGIN NEW(p);
  IF p.M(0, d, 4) = 0 THEN Out.String("m0 ok ") ELSE Out.String("m0 BAD ") END;
  IF p.M(3, d, 4) = 0 THEN Out.String("m3 BAD ") ELSE Out.String("m3 ok ") END;
  IF F(0) = 0 THEN Out.String("f0 ok ") ELSE Out.String("f0 BAD ") END;
  IF p.M(0, d, 4) = 0 THEN Out.String("again ok ") ELSE Out.String("again BAD ") END;
  Out.Int(T(p, 0), 3); Out.Int(T(p, 2), 3); Out.Ln
END L18_CallCmp.
