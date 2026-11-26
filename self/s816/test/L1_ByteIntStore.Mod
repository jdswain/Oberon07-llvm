MODULE L1_ByteIntStore;
  IMPORT Out;

  VAR
    gb: BYTE;
    gi: INTEGER;
    gb2: BYTE;
    gi2: INTEGER;
    arr: ARRAY 4 OF BYTE;

  PROCEDURE TestLocal;
    VAR lb: BYTE; li: INTEGER;
  BEGIN
    (* Local BYTE to local INTEGER *)
    lb := 99;
    li := lb;
    Out.Int(li, 0); Out.Ln();

    (* Local INTEGER to local BYTE *)
    li := 300;
    lb := li MOD 256;
    Out.Int(lb, 0); Out.Ln();

    (* Local BYTE to global INTEGER *)
    lb := 77;
    gi := lb;
    Out.Int(gi, 0); Out.Ln();

    (* Global BYTE to local INTEGER *)
    gb := 88;
    li := gb;
    Out.Int(li, 0); Out.Ln()
  END TestLocal;

  PROCEDURE TestVarParam(VAR b: BYTE; VAR i: INTEGER);
  BEGIN
    (* Read BYTE through VAR param, store to INTEGER through VAR param *)
    i := b;
    Out.Int(i, 0); Out.Ln()
  END TestVarParam;

  PROCEDURE TestByteParam(b: BYTE);
    VAR i: INTEGER;
  BEGIN
    i := b;
    Out.Int(i, 0); Out.Ln()
  END TestByteParam;

BEGIN
  (* Test 1: BYTE global to INTEGER global *)
  gb := 42;
  gi := gb;
  Out.Int(gi, 0); Out.Ln();

  (* Test 2: Ensure high byte is clean (would show > 255 if garbage) *)
  gi2 := 0FFFFH;  (* fill gi2 with all 1s first *)
  gb := 100;
  gi2 := gb;       (* BYTE -> INTEGER store; high byte must be 0 *)
  Out.Int(gi2, 0); Out.Ln();

  (* Test 3: INTEGER global to BYTE global *)
  gi := 300;
  gb := gi MOD 256;
  Out.Int(gb, 0); Out.Ln();

  (* Test 4: BYTE value 255 to INTEGER (must be 255, not -1) *)
  gb := 255;
  gi := gb;
  Out.Int(gi, 0); Out.Ln();

  (* Test 5: BYTE value 0 to INTEGER *)
  gb := 0;
  gi := gb;
  Out.Int(gi, 0); Out.Ln();

  (* Test 6: Local BYTE/INTEGER conversions *)
  TestLocal;

  (* Test 7: BYTE array element to INTEGER *)
  arr[0] := 10;
  arr[1] := 200;
  arr[2] := 0;
  arr[3] := 255;
  gi := arr[0]; Out.Int(gi, 0); Out.Ln();
  gi := arr[1]; Out.Int(gi, 0); Out.Ln();
  gi := arr[2]; Out.Int(gi, 0); Out.Ln();
  gi := arr[3]; Out.Int(gi, 0); Out.Ln();

  (* Test 8: VAR param BYTE to INTEGER *)
  gb := 66;
  TestVarParam(gb, gi);

  (* Test 9: Value param BYTE *)
  TestByteParam(123)
END L1_ByteIntStore.
