MODULE L19_Stock816; (* for L19_Stock, compiled with -816 (a helper whose
   name ends in 816), run as on a stock 65C816: locals beyond d,S's 255
   bytes, local arrays indexed and passed as VAR parameters, a local
   passed as one *)
  VAR sum*: INTEGER;

  PROCEDURE Fill(VAR a: ARRAY OF INTEGER; k: INTEGER);
    VAR i: INTEGER;
  BEGIN FOR i := 0 TO LEN(a) - 1 DO a[i] := i * k + 1 END
  END Fill;

  PROCEDURE Inc(VAR x: INTEGER);
  BEGIN x := x + 7
  END Inc;

  PROCEDURE Run*;
    VAR big: ARRAY 200 OF INTEGER; small: ARRAY 10 OF INTEGER; i, j, s: INTEGER;
  BEGIN Fill(big, 3); Fill(small, 5); s := 0;
    FOR i := 0 TO 199 DO s := s + big[i] END;
    FOR i := 0 TO 9 DO s := s + small[i] * 2 END;
    j := 5; Inc(j); small[3] := j; Inc(small[3]); s := s + small[3];
    s := s + big[0] + big[199] + small[9];
    sum := s
  END Run;

END L19_Stock816.
