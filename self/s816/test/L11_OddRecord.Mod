MODULE L11_OddRecord;
  (* A record of odd size (65 bytes) in an array, assigned element to
     element and from a variable: nothing beyond the element written. *)
  IMPORT Out;

  TYPE E = RECORD name: ARRAY 64 OF CHAR; dir: BOOLEAN END;
    P = POINTER TO PDesc; PDesc = RECORD n: INTEGER; e: ARRAY 4 OF E END;

  VAR a: ARRAY 4 OF E; t: E; i: INTEGER; p: P;

  PROCEDURE Show(VAR a: ARRAY OF E);
    VAR i: INTEGER;
  BEGIN FOR i := 0 TO 3 DO Out.String(a[i].name); Out.Char(" ") END; Out.Ln
  END Show;

BEGIN
  a[0].name := "Apple"; a[1].name := "Banana"; a[2].name := "Cherry"; a[3].name := "Damson";
  FOR i := 0 TO 3 DO a[i].dir := FALSE END;
  a[1] := a[0]; Show(a);
  t := a[3]; a[2] := t; Show(a);
  NEW(p); p.e[0].name := "Elder"; p.e[1].name := "Fig"; p.e[2].name := "Grape"; p.e[3].name := "Kiwi";
  t := p.e[0]; p.e[1] := t; p.e[2] := p.e[3]; Show(p.e)
END L11_OddRecord.
