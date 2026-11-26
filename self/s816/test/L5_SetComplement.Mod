MODULE L5_SetComplement;
  IMPORT Out;
  VAR s, r: SET;
BEGIN
  (* Complement of empty set = full set *)
  s := {};
  r := -s;
  Out.Hex(ORD(r)); Out.Ln();

  (* Complement of full set = empty *)
  s := {0..15};
  r := -s;
  Out.Hex(ORD(r)); Out.Ln();

  (* Complement of low nibble = high nibble *)
  s := {0..3};
  r := -s;
  Out.Hex(ORD(r)); Out.Ln()
END L5_SetComplement.
