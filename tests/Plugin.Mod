MODULE Plugin;
  IMPORT Out;

  PROCEDURE Hello*();
  BEGIN
    Out.WriteString("Hello from a dynamically-loaded plugin!"); Out.Ln()
  END Hello;

  PROCEDURE Sum*();
    VAR i, s: INTEGER;
  BEGIN
    s := 0;
    FOR i := 1 TO 10 DO s := s + i END;
    Out.WriteString("Plugin computed sum = "); Out.WriteInt(s); Out.Ln()
  END Sum;

BEGIN
  Out.WriteString("[Plugin loaded]"); Out.Ln()
END Plugin.
