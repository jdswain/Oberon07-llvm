MODULE L18_A_RecLitHang; (* a record literal of a type of a module not
   available: reported, and the compiler stops *)
  IMPORT L18_A_NoSuchModule;
  CONST A = L18_A_NoSuchModule.Point{x := 1; z := 2}; C = L18_A_NoSuchModule.Point{x := 1; y := 2;};
END L18_A_RecLitHang.
