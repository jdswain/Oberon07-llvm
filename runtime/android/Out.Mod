MODULE Out;
  (* Defined in C runtime; this module exists only to give Oberon importers
     access to a typed signature. *)
  PROCEDURE Write*(ch: CHAR);
  BEGIN
  END Write;

  PROCEDURE WriteString*(VAR s: ARRAY OF CHAR);
  BEGIN
  END WriteString;

  PROCEDURE WriteInt*(n: INTEGER);
  BEGIN
  END WriteInt;

  PROCEDURE Ln*();
  BEGIN
  END Ln;
END Out.
