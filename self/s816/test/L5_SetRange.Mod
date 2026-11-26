MODULE L5_SetRange;
  IMPORT Out;
  VAR s: SET; a, b: INTEGER;
BEGIN
  (* Constant range {2..7} = bits 2-7 = 0xFC *)
  s := {2..7};
  Out.Hex(ORD(s)); Out.Ln();

  (* Full range {0..15} = 0xFFFF *)
  s := {0..15};
  Out.Hex(ORD(s)); Out.Ln();

  (* Single element range {5..5} = {5} = 0x20 *)
  s := {5..5};
  Out.Hex(ORD(s)); Out.Ln();

  (* Variable range *)
  a := 4; b := 11;
  s := {a..b};
  Out.Hex(ORD(s)); Out.Ln();

  (* Variable range {0..7} = 0xFF *)
  a := 0; b := 7;
  s := {a..b};
  Out.Hex(ORD(s)); Out.Ln()
END L5_SetRange.
