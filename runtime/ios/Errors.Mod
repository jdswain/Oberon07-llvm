MODULE Errors;
(* Core error type (DDR-009). Fallible procedures declare a trailing
   `VAR err: Errors.Error`; the callee assigns it on every path and NIL
   means success:

     f := Files.Old(name);
     Files.Delete(name, err);
     IF err # NIL THEN ... err.code ... err.msg ... END

   The type is an extensible record: a library defines
     PathError* = POINTER TO PathErrorDesc;
     PathErrorDesc* = RECORD (Errors.ErrorDesc) path*: ... END
   and callers that care about specifics narrow with IS / type guards;
   callers that don't treat every error uniformly through the base.
   `code` is interpreted by the module that produced the error — codes
   are not a global namespace.

   Pure Oberon — no C sidecar. Construction goes through the Create
   initialiser (DDR-003/004), so an Error can never exist without its
   fields set. Modules on constrained targets may keep preallocated
   singleton errors and hand out the same one every time. *)

  CONST MsgLength* = 64;

  TYPE
    Error*     = POINTER TO ErrorDesc;
    ErrorDesc* = RECORD
      code*: INTEGER;
      msg*:  ARRAY MsgLength OF CHAR
    END;

  PROCEDURE INIT (e: Error) Create* (code: INTEGER; msg: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    e.code := code;
    i := 0;
    WHILE (i < LEN(msg)) & (i < MsgLength - 1) & (msg[i] # 0X) DO
      e.msg[i] := msg[i];
      INC(i)
    END;
    e.msg[i] := 0X
  END Create;

  PROCEDURE (e: Error) Code* (): INTEGER;
  BEGIN
    RETURN e.code
  END Code;

  (* Copy the message into a caller buffer, truncating as needed. *)
  PROCEDURE (e: Error) Message* (VAR buf: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(buf) - 1) & (i < MsgLength) & (e.msg[i] # 0X) DO
      buf[i] := e.msg[i];
      INC(i)
    END;
    buf[i] := 0X
  END Message;

END Errors.
