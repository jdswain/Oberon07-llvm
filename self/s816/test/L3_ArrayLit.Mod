MODULE L3_ArrayLit;
  IMPORT Out;
  TYPE Point = RECORD x, y: INTEGER END;
  VAR nums: ARRAY 4 OF INTEGER; pts: ARRAY 3 OF Point; n, i: INTEGER;
BEGIN
  n := 99;
  nums := ARRAY OF INTEGER {10, 20, n, 40};
  i := 0; WHILE i < 4 DO Out.Int(nums[i], 4); INC(i) END; Out.Ln;
  pts := ARRAY OF Point {Point{x := 1; y := 2}, Point{x := n; y := 4}, Point{x := 5; y := 6}};
  i := 0; WHILE i < 3 DO Out.Int(pts[i].x, 4); Out.Int(pts[i].y, 4); INC(i) END; Out.Ln;
  nums := ARRAY OF INTEGER {7, 8};   (* partial -> zero-fill *)
  i := 0; WHILE i < 4 DO Out.Int(nums[i], 4); INC(i) END; Out.Ln
END L3_ArrayLit.
