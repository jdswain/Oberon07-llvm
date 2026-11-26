MODULE L18_LongBitwise; (* AND, ORA and EOR of LONGINTs: both words, and the
   registers given back, also in the arms of a CASE (the assembler's
   Binary lost a register in each, until SB was overwritten) *)
  IMPORT Out;
  VAR a, b, c: LONGINT; i, k, guard: INTEGER;

  PROCEDURE Hex(v: LONGINT);
    VAR hi, lo: INTEGER;
  BEGIN hi := v DIV 10000H MOD 10000H; lo := v MOD 10000H; Out.Hex(hi); Out.Hex(lo); Out.Char(" ")
  END Hex;

  PROCEDURE Op(code: INTEGER; a, b: LONGINT): LONGINT;
    VAR c: LONGINT;
  BEGIN
    c := 0;
    CASE code OF
      0: c := AND(a, b)
    | 1: c := ORA(a, b)
    | 2: c := EOR(a, b)
    | 3: c := AND(a, 0FFFF0000H)
    | 4: c := ORA(a, 12345H)
    END
  RETURN c
  END Op;

BEGIN
  guard := 1234;
  a := 12345678H; b := 0F0F0FF00H; i := -2;
  Hex(AND(a, b)); Hex(ORA(a, b)); Hex(EOR(a, b)); Out.Ln;
  c := AND(a, i); Hex(c); c := ORA(b, i); Hex(c); c := EOR(a, 0FFFFFFFFH); Hex(c); Out.Ln;
  FOR k := 0 TO 4 DO Hex(Op(k, a, b)) END; Out.Ln;
  Out.Int(guard, 0); Out.Ln
END L18_LongBitwise.
