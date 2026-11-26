MODULE L0_VShift;
  (* Variable (runtime) shift counts — ASL/LSR by a non-constant amount.
     The 65C816 has no barrel shifter, so ORG.Shift emits a count-down loop. *)
  IMPORT Out;
  VAR n, k: INTEGER;
BEGIN
  n := 1; k := 5;    Out.Int(ASL(n, k), 6); Out.Ln;     (* 32 *)
  n := 1; k := 0;    Out.Int(ASL(n, k), 6); Out.Ln;     (* 1  — count 0, value unchanged *)
  n := 1; k := 10;   Out.Int(ASL(n, k), 6); Out.Ln;     (* 1024 *)
  n := 1024; k := 4; Out.Int(LSR(n, k), 6); Out.Ln;     (* 64 *)
  n := 96; k := 5;   Out.Int(LSR(n, k), 6); Out.Ln;     (* 3 *)
  k := 3;            Out.Int(ASL(1, k) + ASL(1, k+1), 6); Out.Ln  (* 24 — two shifts in one expr *)
END L0_VShift.
