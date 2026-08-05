MODULE FilesTests;
  IMPORT Errors, Files, FileDir, TestRunner;

  PROCEDURE TestNewWriteRegister*();
    VAR f: Files.File; r: Files.Rider; i: INTEGER; err: Errors.Error;
  BEGIN
    Files.Delete("oc_files_test.dat", err);
    f := Files.New("oc_files_test.dat");
    IF f = NIL THEN TestRunner.Fail
    ELSE
      Files.Set(r, f, 0);
      FOR i := 0 TO 9 DO Files.WriteByte(r, i + 100) END;
      Files.Register(f);
      IF Files.Length(f) = 10 THEN TestRunner.Pass ELSE TestRunner.Fail END
    END
  END TestNewWriteRegister;

  PROCEDURE TestOldReadBack*();
    VAR f: Files.File; r: Files.Rider; i: INTEGER; b: BYTE; ok: BOOLEAN;
  BEGIN
    f := Files.Old("oc_files_test.dat");
    IF f = NIL THEN TestRunner.Fail
    ELSE
      Files.Set(r, f, 0);
      ok := TRUE;
      FOR i := 0 TO 9 DO
        Files.ReadByte(r, b);
        IF b # i + 100 THEN ok := FALSE END
      END;
      IF ok THEN TestRunner.Pass ELSE TestRunner.Fail END
    END
  END TestOldReadBack;

  PROCEDURE TestEofMarker*();
    VAR f: Files.File; r: Files.Rider; b: BYTE;
  BEGIN
    f := Files.Old("oc_files_test.dat");
    IF f = NIL THEN TestRunner.Fail
    ELSE
      Files.Set(r, f, Files.Length(f));
      Files.ReadByte(r, b);
      IF r.eof THEN TestRunner.Pass ELSE TestRunner.Fail END
    END
  END TestEofMarker;

  PROCEDURE TestWriteIntReadInt*();
    VAR f: Files.File; r: Files.Rider; v: INTEGER; ok: BOOLEAN; err: Errors.Error;
  BEGIN
    Files.Delete("oc_files_test.dat", err);
    f := Files.New("oc_files_test.dat");
    Files.Set(r, f, 0);
    Files.WriteInt(r, 042424242H);
    Files.WriteInt(r, -1);
    Files.Register(f);

    f := Files.Old("oc_files_test.dat");
    Files.Set(r, f, 0);
    Files.ReadInt(r, v);
    ok := v = 042424242H;
    Files.ReadInt(r, v);
    ok := ok & (v = -1);
    IF ok THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestWriteIntReadInt;

  PROCEDURE TestStrings*();
    VAR f: Files.File; r: Files.Rider;
        s: ARRAY 32 OF CHAR; err: Errors.Error;
  BEGIN
    Files.Delete("oc_files_test.dat", err);
    f := Files.New("oc_files_test.dat");
    Files.Set(r, f, 0);
    Files.WriteString(r, "hello, world");
    Files.Register(f);

    f := Files.Old("oc_files_test.dat");
    Files.Set(r, f, 0);
    Files.ReadString(r, s);
    IF s = "hello, world" THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestStrings;

  PROCEDURE TestDelete*();
    VAR f: Files.File; r: Files.Rider; A1, A2: INTEGER; err: Errors.Error;
        fname: FileDir.FileName;
  BEGIN
    Files.Delete("oc_files_test.dat", err);
    f := Files.New("oc_files_test.dat");
    Files.Set(r, f, 0);
    Files.WriteByte(r, 1);
    Files.Register(f);

    fname := "oc_files_test.dat";
    FileDir.Search(fname, A1);
    Files.Delete("oc_files_test.dat", err);
    FileDir.Search(fname, A2);
    IF (A1 # 0) & (err = NIL) & (A2 = 0) THEN TestRunner.Pass
    ELSE TestRunner.Fail END
  END TestDelete;

  PROCEDURE TestDeleteMissing*();
    VAR err: Errors.Error;
  BEGIN
    (* failing path: a real error object arrives, code preserved *)
    Files.Delete("oc_files_no_such_file.dat", err);
    IF (err # NIL) & (err.Code() = 2) & (err.code = 2) THEN
      TestRunner.Pass
    ELSE
      TestRunner.Fail
    END
  END TestDeleteMissing;

  PROCEDURE TestPosAndBase*();
    VAR f: Files.File; r: Files.Rider; err: Errors.Error;
  BEGIN
    Files.Delete("oc_files_test.dat", err);
    f := Files.New("oc_files_test.dat");
    Files.Set(r, f, 0);
    Files.WriteByte(r, 1); Files.WriteByte(r, 2); Files.WriteByte(r, 3);
    IF (Files.Pos(r) = 3) & (Files.Base(r) = f) THEN TestRunner.Pass
    ELSE TestRunner.Fail END;
    Files.Delete("oc_files_test.dat", err)
  END TestPosAndBase;

END FilesTests.
