MODULE L18_B_LongIndex; (* a LONGINT index checked on its 32 bits: here
   10000H, beyond the array, traps 1 *)
  IMPORT Out;
  VAR a: ARRAY 4 OF INTEGER; l: LONGINT;

  PROCEDURE P(VAR b: ARRAY OF INTEGER; i: LONGINT): INTEGER;
  BEGIN RETURN b[i]
  END P;

BEGIN
  a[0] := 10; a[1] := 11; a[2] := 12; a[3] := 13;
  l := 3; Out.Int(a[l], 4); l := 1; a[l + 1] := 22; Out.Int(P(a, l + 1), 4); Out.Ln;
  l := 10000H; Out.Int(a[l], 4); Out.Ln
END L18_B_LongIndex.
