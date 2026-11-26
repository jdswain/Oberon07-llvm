MODULE L3_RecordLitRun;
  IMPORT Out;
  TYPE Point = RECORD x, y: INTEGER END; Line = RECORD a, b: Point END;
  VAR p: Point; l: Line; n, k: INTEGER;

  PROCEDURE Fill(VAR q: Point; v: INTEGER);   (* Par target *)
  BEGIN q := Point{x := v; y := v + 1} END Fill;

BEGIN
  n := 42; k := 7;
  p := Point{x := n; y := k};                                       (* runtime *)
  Out.Int(p.x,4); Out.Int(p.y,4); Out.Ln;                           (* 42 7 *)
  p := Point{y := n * 2};                                           (* partial, runtime *)
  Out.Int(p.x,4); Out.Int(p.y,4); Out.Ln;                           (* 0 84 *)
  l := Line{a := Point{x := n; y := 1}; b := Point{x := 2; y := k}};(* nested + runtime *)
  Out.Int(l.a.x,4);Out.Int(l.a.y,4);Out.Int(l.b.x,4);Out.Int(l.b.y,4);Out.Ln;  (* 42 1 2 7 *)
  p := Point{x := 5; y := 6}; p := Point{x := 9};                   (* reassign zero-fill *)
  Out.Int(p.x,4); Out.Int(p.y,4); Out.Ln;                           (* 9 0 *)
  Fill(p, 20);                                                       (* Par target *)
  Out.Int(p.x,4); Out.Int(p.y,4); Out.Ln                            (* 20 21 *)
END L3_RecordLitRun.
