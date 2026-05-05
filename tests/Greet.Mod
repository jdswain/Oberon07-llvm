MODULE Greet;
  IMPORT Out;

  PROCEDURE SayHello*();
  BEGIN
    Out.WriteString("Hello, ");
    Out.WriteString("world!");
    Out.Ln();
    Out.WriteString("answer = ");
    Out.WriteInt(42);
    Out.Ln()
  END SayHello;

END Greet.
