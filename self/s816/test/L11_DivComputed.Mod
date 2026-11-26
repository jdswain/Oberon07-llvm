MODULE L11_DivComputed;
  (* DIV and MOD of a dividend computed already (in a register) by a
     variable: the divisor was loaded above it, and DivOp left the
     dividend's register counted after the result went into the
     divisor's; a RETURN then loaded its value a register too high, and
     the caller read the remainder. *)
  IMPORT Out;

  TYPE R = RECORD top, bottom: INTEGER END;

  PROCEDURE Div(a, b, h: INTEGER): INTEGER;
    VAR n: INTEGER;
  BEGIN n := (a - b) DIV h RETURN n
  END Div;

  PROCEDURE Mod(a, b, h: INTEGER): INTEGER;
    VAR n: INTEGER;
  BEGIN n := (a - b) MOD h RETURN n
  END Mod;

  PROCEDURE Rows(h: INTEGER): INTEGER;
    VAR r: R;
  BEGIN r.top := 3; r.bottom := 105
  RETURN (r.bottom - r.top) DIV h
  END Rows;

  PROCEDURE Both(a, h: INTEGER): INTEGER;
    VAR q, m: INTEGER;
  BEGIN q := (a + 1) DIV h; m := (a + 1) MOD h
  RETURN q * 100 + m
  END Both;

BEGIN
  Out.Int(Div(105, 3, 13), 0); Out.Ln;
  Out.Int(Mod(105, 3, 13), 0); Out.Ln;
  Out.Int(Rows(13), 0); Out.Ln;
  Out.Int(Both(101, 13), 0); Out.Ln
END L11_DivComputed.
