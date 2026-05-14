MODULE Modules;
(* Runtime module loader.

   Bodies are stub-style: empty-or-single-RETURN. Weak linkage means that
   when a host links Modules_rt.c (the strong C implementation) the C
   side wins; callers that don't link Modules_rt.c get harmless no-ops
   that always return NIL.

   The ModDesc record is allocated by Oberon (NewModDesc) so its tag
   matches our compile-time TD layout. The actual dlopen handle lives in
   a side-table inside Modules_rt.c, keyed by ModDesc address — no need
   to expose handle storage to Oberon.
*)

  TYPE
    Module*  = POINTER TO ModDesc;
    Command* = PROCEDURE;

    ModDesc* = RECORD
      name*:   ARRAY 32 OF CHAR;
      refcnt*: INTEGER;
      next*:   Module
    END;

  VAR
    root*: Module;       (* head of loaded-module list *)

  PROCEDURE Load*(name: ARRAY OF CHAR; VAR newmod: Module);
  BEGIN
  END Load;

  PROCEDURE Free*(name: ARRAY OF CHAR);
  BEGIN
  END Free;

  PROCEDURE ThisCommand*(mod: Module; name: ARRAY OF CHAR): Command;
  BEGIN
    RETURN NIL
  END ThisCommand;

  (* Introspection — walks the compiler-emitted <mod>__exports table.
     Every module ships a NULL-terminated array of {name, fn} entries,
     one per exported procedure; ExportCount returns its length, and the
     name/proc accessors index into it. *)

  PROCEDURE ExportCount*(mod: Module): INTEGER;
  BEGIN
    RETURN 0
  END ExportCount;

  PROCEDURE ExportName*(mod: Module; idx: INTEGER; VAR name: ARRAY OF CHAR);
  BEGIN
  END ExportName;

  PROCEDURE ExportProc*(mod: Module; idx: INTEGER): Command;
  BEGIN
    RETURN NIL
  END ExportProc;

  (* Live-object count for ARC leak assertions. Strong override in C
     calls oc_live_objects() from runtime.c. *)
  PROCEDURE LiveObjects*(): INTEGER;
  BEGIN
    RETURN 0
  END LiveObjects;

  (* Allocator helper used by Modules_rt.c — NEW from Oberon ensures the
     fresh ModDesc has the right TD tag and refcount=0 ready for the
     C runtime to take its first reference. *)
  PROCEDURE NewModDesc*(): Module;
    VAR m: Module;
  BEGIN
    NEW(m);
    RETURN m
  END NewModDesc;

END Modules.
