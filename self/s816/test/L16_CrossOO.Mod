MODULE L16_CrossOO;
  IMPORT Out, L16_OOBase, L16_OOExt;
  VAR d: L16_OOExt.Dog;
BEGIN
  d := L16_OOExt.NewDog(4, 9);
  Out.Int(L16_OOBase.Describe(d), 1); Out.Ln();  (* override 200 + inherited 4 = 204 *)
  Out.Int(d.Bites(), 1); Out.Ln();               (* 9  own slot *)
  Out.Int(d.Sound(), 1); Out.Ln();               (* 200 override *)
  Out.Int(d.Legs(), 1); Out.Ln()                 (* 4  inherited *)
END L16_CrossOO.
