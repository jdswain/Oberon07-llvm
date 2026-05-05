MODULE Math;
  VAR
    a, b, c: INTEGER;
    i: INTEGER;

  PROCEDURE Add*(x, y: INTEGER): INTEGER;
  BEGIN
    RETURN x + y
  END Add;

  PROCEDURE Sum(n: INTEGER): INTEGER;
    VAR k, total: INTEGER;
  BEGIN
    total := 0;
    k := 1;
    WHILE k <= n DO
      total := total + k;
      k := k + 1
    END;
    RETURN total
  END Sum;

BEGIN
  a := 10;
  b := 20;
  c := Add(a, b);
  i := Sum(100)
END Math.
