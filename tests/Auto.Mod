MODULE Auto;
  IMPORT Out;

  PROCEDURE Greet*();
  BEGIN
    Out.WriteString("Hello from "); Out.WriteString("auto-link!"); Out.Ln();
    Out.WriteString("answer = "); Out.WriteInt(42); Out.Ln()
  END Greet;

BEGIN
  Greet()
END Auto.
