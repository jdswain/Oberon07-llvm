MODULE L11_ChainedCalls;
  IMPORT Out;

  PROCEDURE Double(x: INTEGER): INTEGER;
  BEGIN RETURN x * 2
  END Double;

  PROCEDURE Inc(x: INTEGER): INTEGER;
  BEGIN RETURN x + 1
  END Inc;

  PROCEDURE Square(x: INTEGER): INTEGER;
  BEGIN RETURN x * x
  END Square;

BEGIN
  (* Double(Inc(Square(3))) = Double(Inc(9)) = Double(10) = 20 *)
  Out.Int(Double(Inc(Square(3))), 1); Out.Ln;
  (* Double(3) + Inc(Square(2)) = 6 + Inc(4) = 6 + 5 = 11 *)
  Out.Int(Double(3) + Inc(Square(2)), 1); Out.Ln;
  (* Inc(Inc(Inc(0))) = 3 *)
  Out.Int(Inc(Inc(Inc(0))), 1); Out.Ln
END L11_ChainedCalls.
