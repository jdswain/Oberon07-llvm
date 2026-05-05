MODULE RecsTests;
  IMPORT Recs, TestRunner;

  PROCEDURE TestOrigin*();
  BEGIN
    IF (Recs.origin.x = 100) & (Recs.origin.y = 200)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestOrigin;

  PROCEDURE TestSet*();
    VAR q: Recs.Point;
  BEGIN
    Recs.Set(q, 7, 13);
    IF (q.x = 7) & (q.y = 13) THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSet;

  PROCEDURE TestSum*();
    VAR q: Recs.Point;
  BEGIN
    Recs.Set(q, 7, 13);
    IF Recs.Sum(q) = 20 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSum;

END RecsTests.
