MODULE L9_Mid;
  IMPORT Out, L9_Base;

  VAR midVal*: INTEGER;

  PROCEDURE Quadruple*(x: INTEGER): INTEGER;
    VAR t: INTEGER;
  BEGIN
    t := L9_Base.Double(x);
    RETURN L9_Base.Double(t)
  END Quadruple;

BEGIN
  midVal := L9_Base.Double(L9_Base.baseVal);
  Out.Int(2, 1); Out.Ln()
END L9_Mid.
