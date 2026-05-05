MODULE Sum;
  VAR result: INTEGER;

  PROCEDURE Add*(x, y: INTEGER): INTEGER;
  BEGIN
    RETURN x + y
  END Add;

BEGIN
  result := Add(2, 3)
END Sum.
