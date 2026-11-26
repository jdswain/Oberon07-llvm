MODULE L16_SupA;
  (* SUPER through an inherited method, base side: Base declares M. *)
  IMPORT Out;
  TYPE
    Base*     = POINTER TO BaseDesc;
    BaseDesc* = RECORD next*: Base END;

  PROCEDURE (b: Base) M*(VAR x: INTEGER);
  BEGIN Out.String("base M"); Out.Int(x, 2); Out.Ln; INC(x);
    IF b.next # NIL THEN b.next.M(x) END
  END M;
END L16_SupA.
