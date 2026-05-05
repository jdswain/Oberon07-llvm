MODULE Counter;
  VAR n*: INTEGER;

  PROCEDURE Add*(d: INTEGER);
  BEGIN
    n := n + d
  END Add;

BEGIN
  n := 0
END Counter.
