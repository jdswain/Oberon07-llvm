MODULE L10_SystemVal;
  IMPORT SYSTEM, Out;
  VAR n, m: INTEGER;
      b: BYTE;
BEGIN
  (* VAL(BYTE, n) - reinterpret integer as byte (smaller or equal) *)
  n := 65;
  b := SYSTEM.VAL(BYTE, n);
  Out.Int(b, 1); Out.Ln();

  (* VAL(INTEGER, n) - identity, same type *)
  n := 1234;
  m := SYSTEM.VAL(INTEGER, n);
  Out.Int(m, 1); Out.Ln();

  (* VAL(CHAR, b) - same size (both 1 byte) *)
  b := 48;
  Out.Char(SYSTEM.VAL(CHAR, b)); Out.Ln()
END L10_SystemVal.
