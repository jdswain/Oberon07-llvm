MODULE L16_SupB;
  (* SUPER through an inherited method, middle: Mid extends Base and
     declares no methods of its own, as View does Responder's. *)
  IMPORT L16_SupA;
  TYPE
    Mid*     = POINTER TO MidDesc;
    MidDesc* = RECORD (L16_SupA.BaseDesc) tag*: INTEGER END;
END L16_SupB.
