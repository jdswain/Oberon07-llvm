MODULE B;
  IMPORT Counter;
  PROCEDURE Touch*();
  BEGIN
    Counter.Add(1)
  END Touch;
BEGIN
  Counter.Add(1000)
END B.
