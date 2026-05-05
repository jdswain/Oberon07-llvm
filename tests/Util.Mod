MODULE Util;

  VAR counter*: INTEGER;

  PROCEDURE Double*(x: INTEGER): INTEGER;
  BEGIN
    RETURN x * 2
  END Double;

  PROCEDURE Bump*();
  BEGIN
    counter := counter + 1
  END Bump;

BEGIN
  counter := 100
END Util.
