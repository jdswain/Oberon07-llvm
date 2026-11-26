MODULE L16_SuperInh;
  (* SUPER.M in a type whose base (L16_SupB.Mid) only inherits M, from
     another module again (L16_SupA.Base): the base's M is called. *)
  IMPORT L16_SupA, L16_SupB, Out;
  TYPE
    Leaf = POINTER TO LeafDesc;
    LeafDesc = RECORD (L16_SupB.MidDesc) name: CHAR END;
  VAR a, b: Leaf; x: INTEGER;

  PROCEDURE (l: Leaf) M*(VAR x: INTEGER) OVERRIDE;
  BEGIN Out.String("leaf "); Out.Char(l.name); Out.Int(x, 2); Out.Ln; INC(x);
    SUPER.M(x)
  END M;

BEGIN
  NEW(a); NEW(b); a.name := "a"; b.name := "b"; a.next := b; b.next := NIL;
  x := 1; a.M(x); Out.Int(x, 0); Out.Ln
END L16_SuperInh.
