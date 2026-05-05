MODULE SysProvider;
  IMPORT SYSTEM;

  (* Exported procedures whose interfaces use LONGINT. The importer must
     see them as LONGINT (i64), not collapsed to INTEGER. *)
  PROCEDURE GetAdr*(VAR x: INTEGER): LONGINT;
  BEGIN
    RETURN SYSTEM.ADR(x)
  END GetAdr;

  PROCEDURE Read*(a: LONGINT): INTEGER;
    VAR v: INTEGER;
  BEGIN
    SYSTEM.GET(a, v);
    RETURN v
  END Read;

  PROCEDURE Write*(a: LONGINT; v: INTEGER);
  BEGIN
    SYSTEM.PUT(a, v)
  END Write;

END SysProvider.
