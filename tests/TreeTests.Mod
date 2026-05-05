MODULE TreeTests;
  IMPORT Tree, Modules, TestRunner;

  PROCEDURE build(): Tree.Node;
    VAR root: Tree.Node;
  BEGIN
    (*       10
            /  \
           3    7
                 \
                  20
       sum = 40 *)
    root := Tree.Make(10);
    root.left := Tree.Make(3);
    root.right := Tree.Make(7);
    root.right.right := Tree.Make(20);
    RETURN root
  END build;

  PROCEDURE TestSum*();
    VAR root: Tree.Node;
  BEGIN
    root := build();
    IF Tree.Sum(root) = 40 THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestSum;

  PROCEDURE TestNoLeak*();
    VAR root: Tree.Node; base: INTEGER;
  BEGIN
    base := Modules.LiveObjects();
    root := build();
    root := NIL;
    IF Modules.LiveObjects() = base THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestNoLeak;

END TreeTests.
