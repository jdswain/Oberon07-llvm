MODULE Files;
(* POSIX-passthrough port of the Project Oberon Files interface.

   The exported types and procedures match NW's Files.Mod so that user
   code targeting Project Oberon ports unchanged. The implementation
   lives in Files_rt.c and treats each Oberon File as a host file under
   the current working directory: Old does fopen("rb+"), New buffers
   in memory until Register renames into place, Read*/Write* are
   bytewise fseek/fread/fwrite. There is no disk image, no B-tree, no
   page cache — that all collapses to the host filesystem. *)

  IMPORT Errors;

  CONST FnLength* = 256;

  TYPE
    File* = POINTER TO FileDesc;

    FileDesc = RECORD
      (* C-private: handle stores a FileBuf pointer cast to LONGINT. *)
      handle:      LONGINT;
      name*:       ARRAY FnLength OF CHAR;
      length:      INTEGER;
      date:        INTEGER;
      registered:  BOOLEAN
    END;

    Rider* = RECORD
      eof*:  BOOLEAN;
      res*:  INTEGER;
      file:  File;
      pos:   INTEGER
    END;

  (* ----- File lifecycle ----- *)

  PROCEDURE Old*(name: ARRAY OF CHAR): File;
  BEGIN RETURN NIL
  END Old;

  PROCEDURE New*(name: ARRAY OF CHAR): File;
  BEGIN RETURN NIL
  END New;

  PROCEDURE Register*(f: File);
  BEGIN
  END Register;

  PROCEDURE Close*(f: File);
  BEGIN
  END Close;

  PROCEDURE Purge*(f: File);
  BEGIN
  END Purge;

  (* Raw C bridges (Files_rt.c). Exported so the empty bodies get weak
     linkage and the C definitions override them; not for user code.
     res: 0 = ok, 2 = not found, otherwise failure. *)
  PROCEDURE DeleteRaw*(name: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN
  END DeleteRaw;

  PROCEDURE RenameRaw*(old, new: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN
  END RenameRaw;

  PROCEDURE MakeDirRaw*(name: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN
  END MakeDirRaw;

  (* Map a raw res code to the DDR-009 error convention. *)
  PROCEDURE resToErr(res: INTEGER; op: ARRAY OF CHAR; VAR err: Errors.Error);
  BEGIN
    IF res = 0 THEN err := NIL
    ELSIF res = 2 THEN err := Errors.Error.Create(res, "not found")
    ELSE err := Errors.Error.Create(res, op)
    END
  END resToErr;

  PROCEDURE Delete*(name: ARRAY OF CHAR; VAR err: Errors.Error);
    VAR res: INTEGER;
  BEGIN
    res := 0;
    DeleteRaw(name, res);
    resToErr(res, "delete failed", err)
  END Delete;

  PROCEDURE Rename*(old, new: ARRAY OF CHAR; VAR err: Errors.Error);
    VAR res: INTEGER;
  BEGIN
    res := 0;
    RenameRaw(old, new, res);
    resToErr(res, "rename failed", err)
  END Rename;

  (* 1 if the named filesystem entry exists (file, dir, link, ...),
     0 otherwise. INTEGER for ABI simplicity. *)
  PROCEDURE Exists*(name: ARRAY OF CHAR): INTEGER;
  BEGIN RETURN 0
  END Exists;

  (* mkdir -p: create `name` and any missing parent directories.
     Already-exists is success. *)
  PROCEDURE MakeDir*(name: ARRAY OF CHAR; VAR err: Errors.Error);
    VAR res: INTEGER;
  BEGIN
    res := 0;
    MakeDirRaw(name, res);
    resToErr(res, "mkdir failed", err)
  END MakeDir;

  (* Streaming directory iteration. On wasm this round-trips through
     /api/files/<path>?list=1; the JS shim parses the response on
     OpenDir and replays it via NextEntry. Returns / VAR convention
     match posix — see Files.Mod there. *)
  PROCEDURE OpenDir*(path: ARRAY OF CHAR): INTEGER;
  BEGIN RETURN -1
  END OpenDir;

  PROCEDURE NextEntry*(cookie: INTEGER;
                       VAR name: ARRAY OF CHAR;
                       VAR isDir: INTEGER): INTEGER;
  BEGIN RETURN 0
  END NextEntry;

  PROCEDURE CloseDir*(cookie: INTEGER);
  BEGIN
  END CloseDir;

  PROCEDURE Length*(f: File): INTEGER;
  BEGIN RETURN 0
  END Length;

  PROCEDURE Date*(f: File): INTEGER;
  BEGIN RETURN 0
  END Date;

  (* ----- Rider positioning ----- *)

  PROCEDURE Set*(VAR r: Rider; f: File; pos: INTEGER);
  BEGIN
  END Set;

  PROCEDURE Pos*(VAR r: Rider): INTEGER;
  BEGIN RETURN 0
  END Pos;

  PROCEDURE Base*(VAR r: Rider): File;
  BEGIN RETURN NIL
  END Base;

  (* ----- Read primitives ----- *)

  PROCEDURE ReadByte*(VAR r: Rider; VAR x: BYTE);
  BEGIN
  END ReadByte;

  PROCEDURE ReadBytes*(VAR r: Rider; VAR x: ARRAY OF BYTE; n: INTEGER);
  BEGIN
  END ReadBytes;

  PROCEDURE Read*(VAR r: Rider; VAR ch: CHAR);
  BEGIN
  END Read;

  PROCEDURE ReadInt*(VAR R: Rider; VAR x: INTEGER);
  BEGIN
  END ReadInt;

  PROCEDURE ReadString*(VAR R: Rider; VAR x: ARRAY OF CHAR);
  BEGIN
  END ReadString;

  PROCEDURE ReadNum*(VAR R: Rider; VAR x: INTEGER);
  BEGIN
  END ReadNum;

  (* ----- Write primitives ----- *)

  PROCEDURE WriteByte*(VAR r: Rider; x: BYTE);
  BEGIN
  END WriteByte;

  PROCEDURE WriteBytes*(VAR r: Rider; x: ARRAY OF BYTE; n: INTEGER);
  BEGIN
  END WriteBytes;

  PROCEDURE Write*(VAR r: Rider; ch: CHAR);
  BEGIN
  END Write;

  PROCEDURE WriteInt*(VAR R: Rider; x: INTEGER);
  BEGIN
  END WriteInt;

  PROCEDURE WriteString*(VAR R: Rider; x: ARRAY OF CHAR);
  BEGIN
  END WriteString;

  PROCEDURE WriteNum*(VAR R: Rider; x: INTEGER);
  BEGIN
  END WriteNum;

  (* Allocator helper used by Files_rt.c — NEW from Oberon ensures the
     fresh FileDesc carries the right TD tag and refcount = 0 ready for
     the C runtime to take its first reference. *)
  PROCEDURE NewFileDesc*(): File;
    VAR f: File;
  BEGIN
    NEW(f); RETURN f
  END NewFileDesc;

END Files.
