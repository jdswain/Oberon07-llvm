MODULE L17_IfGuard;
  (* Type tests and guards on interface values: from a global, a heap
     object's field and a parameter, NIL, and inside larger expressions.
     Box is a base record (extension level 0). NIL IS T is FALSE but
     for v's own type; a guard lets NIL through. *)
  IMPORT Out, L17_IfBase, L17_IfExt;
  TYPE
    Holder = POINTER TO HolderDesc;
    HolderDesc = RECORD n: INTEGER; s: L17_IfBase.Shape END;
  VAR s, t, z: L17_IfBase.Shape; h: Holder; b: L17_IfBase.Box; k: INTEGER;

  PROCEDURE Width (x: L17_IfBase.Shape): INTEGER;
    VAR w: INTEGER;
  BEGIN
    IF x IS L17_IfBase.Box THEN w := x(L17_IfBase.Box).w ELSE w := -1 END;
    RETURN w
  END Width;

  PROCEDURE B (c: BOOLEAN);
  BEGIN IF c THEN Out.String("T") ELSE Out.String("F") END
  END B;

BEGIN
  s := L17_IfBase.NewBox(3, 4); t := L17_IfExt.NewDisc(2); z := NIL;
  B(s IS L17_IfBase.Box); B(t IS L17_IfBase.Box); B(t IS L17_IfExt.Disc);
  B(s IS L17_IfExt.Disc); B(z IS L17_IfBase.Box); Out.Ln;                 (* TFTFT *)
  b := s(L17_IfBase.Box); Out.Int(b.w, 1); Out.Ln;                         (* 3 *)
  Out.Int(s(L17_IfBase.Box).h, 1); Out.Ln;                                 (* 4 *)
  Out.Int(t(L17_IfExt.Disc).r, 1); Out.Ln;                                 (* 2 *)
  NEW(h); h.n := 5; h.s := s;
  Out.Int(h.s(L17_IfBase.Box).w * 10 + h.n, 1); Out.Ln;                    (* 35 *)
  B(h.s IS L17_IfBase.Box); B(h.s IS L17_IfExt.Disc); Out.Ln;              (* TF *)
  Out.Int(Width(s), 1); Out.Char(" "); Out.Int(Width(t), 1); Out.Ln;      (* 3 -1 *)
  k := 100 + s(L17_IfBase.Box).w + t(L17_IfExt.Disc).r * 10; Out.Int(k, 1); Out.Ln;  (* 123 *)
  B((s IS L17_IfBase.Box) & (t IS L17_IfExt.Disc) & ~(t IS L17_IfBase.Box)); Out.Ln  (* T *)
END L17_IfGuard.
