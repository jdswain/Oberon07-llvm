MODULE L11_IntOverflow;
  IMPORT Out;
  VAR x, y: INTEGER;
BEGIN
  (* MAX(INTEGER) = 32767 *)
  x := 7FFFH;
  Out.Int(x, 1); Out.Ln;
  (* MAX + 1 wraps to MIN *)
  x := x + 1;
  Out.Int(x, 1); Out.Ln;
  (* MIN - 1 wraps to MAX *)
  x := x - 1;
  Out.Int(x, 1); Out.Ln;
  (* Multiplication overflow with variables *)
  x := 200; y := 200;
  Out.Int(x * y, 1); Out.Ln
END L11_IntOverflow.
