MODULE L18_A_PtrCmpOk; (* pointers of related types, and NIL, compared *)
  IMPORT Out;
  TYPE Shape = POINTER TO ShapeDesc; ShapeDesc = RECORD x: INTEGER END;
    Circle = POINTER TO CircleDesc; CircleDesc = RECORD (ShapeDesc) r: INTEGER END;
    Handler = PROCEDURE (i: INTEGER);
  VAR s: Shape; c: Circle; h: Handler;
  PROCEDURE H(i: INTEGER); END H;
BEGIN
  NEW(c); s := c;
  Out.Bool(s = c); Out.Bool(c # s); Out.Bool(s = NIL); Out.Bool(NIL # c);
  h := NIL; Out.Bool(h = NIL); h := H; Out.Bool(h # NIL); Out.Ln
END L18_A_PtrCmpOk.
