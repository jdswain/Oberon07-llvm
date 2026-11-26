MODULE L18_D_Copy0; (* SYSTEM.COPY of a variable count: 0 copies nothing
   (it was 65536 words, over all of bank 0); a negative count traps 3 *)
  IMPORT SYSTEM, Out;
  CONST A = 100H;  (* in bank 0: each word copied onto itself *)
  VAR n, k: INTEGER;
BEGIN
  FOR k := 1 TO 3 DO n := 0; SYSTEM.COPY(A, A, n) END;
  Out.String("0 ok"); Out.Ln;
  n := 1; SYSTEM.COPY(A, A, n); Out.String("1 ok"); Out.Ln;
  n := -1; SYSTEM.COPY(A, A, n);
  Out.String("not reached"); Out.Ln
END L18_D_Copy0.
