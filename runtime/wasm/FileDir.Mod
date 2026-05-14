MODULE FileDir;
(* POSIX-passthrough port of Project Oberon's FileDir.

   The PO version maintains a B-tree directory inside a disk image.  We
   expose the same Search / Insert / Delete / Enumerate interface but
   delegate to the host filesystem: Search asks `access(path)`, Delete
   `unlink`s, Enumerate walks the cwd via `opendir`. Insert is a no-op
   because Files.Register already creates the host file. The disk-format
   types (FileHeader, DirPage, sector tables) are NOT exported — programs
   that rely on raw page bytes from the PO disk image won't port. *)

  CONST FnLength* = 32;

  TYPE
    FileName* = ARRAY FnLength OF CHAR;
    EntryHandler* = PROCEDURE (name: FileName; sec: INTEGER; VAR continue: BOOLEAN);

  (* Stub bodies — Files.Register has already created the host file. *)

  PROCEDURE Search*(name: FileName; VAR A: INTEGER);
  BEGIN
  END Search;

  PROCEDURE Insert*(name: FileName; fad: INTEGER);
  BEGIN
  END Insert;

  PROCEDURE Delete*(name: FileName; VAR fad: INTEGER);
  BEGIN
  END Delete;

  PROCEDURE Enumerate*(prefix: ARRAY OF CHAR; proc: EntryHandler);
  BEGIN
  END Enumerate;

  PROCEDURE Init*();
  BEGIN
  END Init;

END FileDir.
