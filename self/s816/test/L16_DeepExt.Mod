MODULE L16_DeepExt;
  (* Record extension seven levels deep (levels 0-7, a type descriptor's
     eight ancestors): type tests at every level, a guard, and dynamic
     dispatch to the deepest override. *)
  IMPORT Out;
  TYPE
    T0 = POINTER TO R0; R0 = RECORD a: INTEGER END;
    T1 = POINTER TO R1; R1 = RECORD (R0) END;
    T2 = POINTER TO R2; R2 = RECORD (R1) END;
    T3 = POINTER TO R3; R3 = RECORD (R2) END;
    T4 = POINTER TO R4; R4 = RECORD (R3) END;
    T5 = POINTER TO R5; R5 = RECORD (R4) END;
    T6 = POINTER TO R6; R6 = RECORD (R5) END;
    T7 = POINTER TO R7; R7 = RECORD (R6) b: INTEGER END;
  VAR p, q: T0; n: INTEGER; t7: T7; t5: T5;

  PROCEDURE (t: T0) Level*(): INTEGER;
  BEGIN RETURN 0
  END Level;

  PROCEDURE (t: T4) Level*(): INTEGER OVERRIDE;
  BEGIN RETURN 4
  END Level;

  PROCEDURE (t: T7) Level*(): INTEGER OVERRIDE;
  BEGIN RETURN 7
  END Level;

  PROCEDURE Count(x: T0): INTEGER;
    VAR n: INTEGER;
  BEGIN n := 0;
    IF x IS T1 THEN INC(n) END; IF x IS T2 THEN INC(n) END; IF x IS T3 THEN INC(n) END;
    IF x IS T4 THEN INC(n) END; IF x IS T5 THEN INC(n) END; IF x IS T6 THEN INC(n) END;
    IF x IS T7 THEN INC(n) END
  RETURN n
  END Count;

BEGIN
  NEW(t7); t7.a := 1; t7.b := 2; p := t7;
  NEW(t5); t5.a := 3; q := t5;
  Out.Int(Count(p), 0); Out.Int(Count(q), 2); Out.Ln;
  Out.Int(p.Level(), 0); Out.Int(q.Level(), 2); Out.Ln;
  Out.Int(p(T7).b, 0); Out.Ln;
  n := 0; IF q IS T7 THEN n := 1 END; Out.Int(n, 0); Out.Ln
END L16_DeepExt.
