MODULE L0_OpenArr;
  (* Open-array-source assignment: `fixed := openParam`. Byte count is the
     source's runtime length * element size; ORG.StoreStruct computes it and
     runs a variable-length copy loop. CHAR (elem 1) and INTEGER (elem 2). *)
  IMPORT Out;
  VAR cdst: ARRAY 8 OF CHAR; idst: ARRAY 4 OF INTEGER;
      csrc: ARRAY 5 OF CHAR; isrc: ARRAY 4 OF INTEGER; i: INTEGER;

  PROCEDURE CopyC(src: ARRAY OF CHAR); BEGIN cdst := src END CopyC;
  PROCEDURE CopyI(src: ARRAY OF INTEGER); BEGIN idst := src END CopyI;
BEGIN
  csrc[0] := "h"; csrc[1] := "i"; csrc[2] := "!"; csrc[3] := "?"; csrc[4] := "z";
  CopyC(csrc);
  i := 0; WHILE i < 5 DO Out.Char(cdst[i]); INC(i) END; Out.Ln;
  isrc[0] := 11; isrc[1] := 22; isrc[2] := 33; isrc[3] := 44;
  CopyI(isrc);
  i := 0; WHILE i < 4 DO Out.Int(idst[i], 4); INC(i) END; Out.Ln
END L0_OpenArr.
