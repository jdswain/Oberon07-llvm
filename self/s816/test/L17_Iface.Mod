MODULE L17_Iface;
  IMPORT Out, L17_IfBase, L17_IfExt;
  VAR s: L17_IfBase.Shape; sc: L17_IfBase.Scaled;
      b: L17_IfBase.Box; d: L17_IfExt.Disc;
BEGIN
  b := L17_IfBase.NewBox(3, 4);
  s := b;
  Out.Int(s.Area(), 1); Out.Ln();                (* dispatch: 12 *)
  Out.Int(s.Kind(), 1); Out.Ln();                (* 1 *)
  Out.Int(L17_IfBase.AreaOf(b), 1); Out.Ln();    (* param: 12 *)
  s := L17_IfBase.MakeShape(6, 7);
  Out.Int(s.Area(), 1); Out.Ln();                (* result: 42 *)
  sc := b; sc.Scale(2);
  Out.Int(sc.Area(), 1); Out.Ln();               (* inclusion: 48 *)
  d := L17_IfExt.NewDisc(2);
  Out.Int(L17_IfBase.AreaOf(d), 1); Out.Ln();    (* cross-module: 12 *)
  s := d;
  Out.Int(s.Area(), 1); Out.Ln()                 (* 12 *)
END L17_Iface.
