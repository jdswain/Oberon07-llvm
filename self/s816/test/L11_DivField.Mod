MODULE L11_DivField;
  (* DIV and MOD of a field through a pointer by a variable: the pointer's
     two registers were taken first, the divisor loaded above them, then
     the field loaded into the pointer's first register and its second
     freed as if it were the topmost: the divisor's register was counted
     free, and the quotient written over the divisor (1 DIV 2 gave 1). *)
  IMPORT Out;

  TYPE P = POINTER TO R; R = RECORD rank: INTEGER; b: BYTE END;

  VAR p: P; t: INTEGER;

  PROCEDURE Div(p: P; y: INTEGER): INTEGER;
  BEGIN RETURN p.rank DIV y
  END Div;

  PROCEDURE Mod(p: P; y: INTEGER): INTEGER;
  BEGIN RETURN p.rank MOD y
  END Mod;

  PROCEDURE Odd(p: P; y: INTEGER): BOOLEAN;
  BEGIN RETURN (p # NIL) & ODD(p.rank DIV y)
  END Odd;

BEGIN NEW(p); p.rank := 1; p.b := 9; t := 2;
  Out.Int(Div(p, 2), 0); Out.Ln;
  Out.Int(ORD(Odd(p, 2)), 0); Out.Ln;
  p.rank := 7;
  Out.Int(Div(p, 2), 0); Out.Ln;
  Out.Int(Mod(p, 4), 0); Out.Ln;
  Out.Int(p.b DIV t, 0); Out.Ln;
  Out.Int(p.rank * t + p.b, 0); Out.Ln
END L11_DivField.
