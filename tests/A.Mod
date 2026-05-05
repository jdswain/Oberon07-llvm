MODULE A;
  IMPORT Counter;
  PROCEDURE Touch*();
  BEGIN
    Counter.Add(1)
  END Touch;
BEGIN
  Counter.Add(100)
END A.
