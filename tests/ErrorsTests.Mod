MODULE ErrorsTests;
  IMPORT Errors, TestRunner;

  TYPE
    (* a library-specific error extending the core type (DDR-009 §4) *)
    PathError*     = POINTER TO PathErrorDesc;
    PathErrorDesc* = RECORD (Errors.ErrorDesc)
      isDir*: BOOLEAN
    END;

  PROCEDURE INIT (p: PathError) Create* (code: INTEGER; msg: ARRAY OF CHAR;
                                         isDir: BOOLEAN);
  BEGIN
    SUPER.Create(code, msg);
    p.isDir := isDir
  END Create;

  PROCEDURE TestCreate*();
    VAR e: Errors.Error;
        buf: ARRAY 16 OF CHAR;
  BEGIN
    e := Errors.Error.Create(7, "boom");
    e.Message(buf);
    IF (e.Code() = 7) & (buf = "boom") THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestCreate;

  PROCEDURE TestTruncation*();
    VAR e: Errors.Error;
        buf: ARRAY 4 OF CHAR;
  BEGIN
    e := Errors.Error.Create(1, "long message");
    e.Message(buf);
    IF buf = "lon" THEN TestRunner.Pass ELSE TestRunner.Fail END
  END TestTruncation;

  PROCEDURE TestExtension*();
    VAR e: Errors.Error;
  BEGIN
    (* produced as a specific error, handled through the base *)
    e := PathError.Create(3, "no such dir", TRUE);
    IF e.Code() = 3 THEN TestRunner.Pass ELSE TestRunner.Fail END;
    (* callers that care narrow with the ordinary machinery *)
    IF (e IS PathError) & e(PathError).isDir THEN
      TestRunner.Pass
    ELSE
      TestRunner.Fail
    END
  END TestExtension;

END ErrorsTests.
