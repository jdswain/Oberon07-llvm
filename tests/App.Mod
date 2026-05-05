MODULE App;

  IMPORT Util;

  PROCEDURE Quad*(x: INTEGER): INTEGER;
  BEGIN
    RETURN Util.Double(Util.Double(x))
  END Quad;

  PROCEDURE BumpTwice*();
  BEGIN
    Util.Bump();
    Util.Bump()
  END BumpTwice;

  PROCEDURE GetCounter*(): INTEGER;
  BEGIN
    RETURN Util.counter
  END GetCounter;

END App.
