MODULE L18_HeapStr; (* Strings in records on the heap, which on OS16 is
   outside bank 0: copied into, compared with an open array, indexed,
   passed on as an open array (as the assembler's symbol table does) *)
  IMPORT Out;
  TYPE Ident = ARRAY 16 OF CHAR;
    Obj = POINTER TO ObjDesc; ObjDesc = RECORD name: Ident; n: INTEGER; next: Obj END;
  VAR list, o: Obj; s: Ident;

  PROCEDURE Copy(src: ARRAY OF CHAR; VAR dst: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0; WHILE (i < LEN(dst) - 1) & (src[i] # 0X) DO dst[i] := src[i]; INC(i) END; dst[i] := 0X
  END Copy;

  PROCEDURE Len(a: ARRAY OF CHAR): INTEGER;
    VAR i: INTEGER;
  BEGIN i := 0; WHILE a[i] # 0X DO INC(i) END; RETURN i
  END Len;

  PROCEDURE New(name: ARRAY OF CHAR; n: INTEGER);
    VAR o: Obj;
  BEGIN NEW(o); Copy(name, o.name); o.n := n; o.next := list; list := o
  END New;

  PROCEDURE This(name: ARRAY OF CHAR): Obj;
    VAR o: Obj;
  BEGIN o := list; WHILE (o # NIL) & (o.name # name) DO o := o.next END; RETURN o
  END This;

BEGIN
  list := NIL; New("count", 3); New("val", 7); New("dst", 9);
  o := This("val"); IF o # NIL THEN Out.Int(o.n, 0) ELSE Out.String("no val") END; Out.Ln;
  o := This("count"); IF o # NIL THEN Out.Int(o.n, 0) ELSE Out.String("no count") END; Out.Ln;
  s := "dst"; o := This(s); IF o # NIL THEN Out.Int(o.n, 0) ELSE Out.String("no dst") END; Out.Ln;
  o := list; WHILE o # NIL DO Out.String(o.name); Out.Char(" "); Out.Int(Len(o.name), 0); Out.Char(" "); Out.Char(o.name[0]); Out.Ln; o := o.next END;
  IF list.name = "dst" THEN Out.String("eq") ELSE Out.String("ne") END; Out.Ln;
  IF list.name < "e" THEN Out.String("lt") ELSE Out.String("ge") END; Out.Ln
END L18_HeapStr.
