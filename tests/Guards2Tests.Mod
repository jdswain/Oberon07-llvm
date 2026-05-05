MODULE Guards2Tests;
  IMPORT Guards2, TestRunner;

  PROCEDURE TestClassifyDog*();
    VAR a: Guards2.Animal;
  BEGIN
    a := Guards2.NewDog(11);
    IF Guards2.Classify(a) = 1011 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestClassifyDog;

  PROCEDURE TestClassifyCat*();
    VAR a: Guards2.Animal;
  BEGIN
    a := Guards2.NewCat(9);
    IF Guards2.Classify(a) = 2009 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestClassifyCat;

  PROCEDURE TestClassifyBird*();
    VAR a: Guards2.Animal;
  BEGIN
    a := Guards2.NewBird(42);
    IF Guards2.Classify(a) = 3042 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestClassifyBird;

  PROCEDURE TestFurCountMammal*();
    VAR d, c: Guards2.Animal;
  BEGIN
    d := Guards2.NewDog(11);
    c := Guards2.NewCat(9);
    IF (Guards2.FurCount(d) = 1) & (Guards2.FurCount(c) = 2)
    THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestFurCountMammal;

  PROCEDURE TestFurCountBird*();
    VAR a: Guards2.Animal;
  BEGIN
    (* Bird does not extend Mammal — type-CASE should miss and leave r=0. *)
    a := Guards2.NewBird(42);
    IF Guards2.FurCount(a) = 0 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestFurCountBird;

  PROCEDURE TestBreed*();
    VAR a: Guards2.Animal;
  BEGIN
    a := Guards2.NewDog(11);
    IF Guards2.Breed(a) = 11 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestBreed;

END Guards2Tests.
