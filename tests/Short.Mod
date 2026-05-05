MODULE Short;
  (* Short-circuit AND/OR test.
     The classic motivating case: "p # NIL & p.x = 0" must not deref NIL. *)

  TYPE
    Box* = POINTER TO BoxDesc;
    BoxDesc* = RECORD val*: INTEGER END;

  PROCEDURE IsZero*(p: Box): BOOLEAN;
    VAR r: BOOLEAN;
  BEGIN
    (* If p is NIL the second operand is never evaluated, so p.val is safe. *)
    r := (p # NIL) & (p.val = 0);
    RETURN r
  END IsZero;

  PROCEDURE NonNeg*(p: Box): BOOLEAN;
    VAR r: BOOLEAN;
  BEGIN
    (* OR: if p is NIL, short-circuit to TRUE; else check value. *)
    r := (p = NIL) OR (p.val >= 0);
    RETURN r
  END NonNeg;

  PROCEDURE Both*(a, b: BOOLEAN; x, y: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN
    r := 0;
    IF a & (x > 0) THEN r := r + 1 END;
    IF b OR (y > 0) THEN r := r + 10 END;
    RETURN r
  END Both;

END Short.
