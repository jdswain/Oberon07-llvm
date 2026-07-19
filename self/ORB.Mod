MODULE ORB; (* NW 25.6.2014 / AP 4.3.2020 / 8.3.2019 in Oberon-07.
   Self-hosted port of src/ORB.c: symbol table, imports and exports.
   Deltas from NW's original carried over from the C port:
     - LONGINT (form Int, size 8) alongside INTEGER;
     - type-bound procedures (DDR-001..004): per-record meth lists,
       initialiser flag, mangled symbol names;
     - interfaces (DDR-008): form Intfc, flattened member sets,
       record conformance lists;
     - symbol files carry all of the above (versionkey 4);
     - symbol-file search paths;
     - backend handle fields (codegen-private, opaque here).

   Record layouts here are mirrored by C structs in ORG_rt.c (the LLVM
   backend reads Object/Type/Item graphs directly). Do not reorder
   fields without updating the mirrors. *)

  IMPORT Files, Out, ORS;

  CONST versionkey* = 5; maxTypTab = 64;
    MnLength = 104;  (* mangled Mod__Type__Name *)

    (* class values *)
    Head* = 0; Const* = 1; Var* = 2; Par* = 3; Fld* = 4; Typ* = 5;
    SProc* = 6; SFunc* = 7; Mod* = 8; Meth* = 9;

    (* form values *)
    Byte* = 1; Bool* = 2; Char* = 3; Int* = 4; Real* = 5; Set* = 6;
    Pointer* = 7; NilTyp* = 8; NoTyp* = 9; Proc* = 10; String* = 11;
    Array* = 12; Record* = 13; Intfc* = 14;

  TYPE
    Object* = POINTER TO ObjectDesc;
    Module* = POINTER TO ModDesc;
    Type* = POINTER TO TypeDesc;
    WType* = WEAK POINTER TO TypeDesc;  (* untraced: Item.type fields *)
    Impl* = POINTER TO ImplDesc;

    ObjectDesc* = RECORD
      class*, exno*: INTEGER;
      expo*, rdo*: BOOLEAN;          (* exported / read-only *)
      lev*: INTEGER;
      next*, dsc*: Object;
      type*: Type;
      name*: ORS.Ident;
      val*: LONGINT;                 (* Meth: vtable slot (-1 for inits) *)
      initf*: BOOLEAN;               (* Meth: initialiser (DDR-003) *)
      mname*: ARRAY MnLength OF CHAR;(* Meth: mangled symbol *)
      backend*, backend2*: LONGINT   (* codegen-private handles *)
    END;

    ModDesc* = RECORD (ObjectDesc)
      orgname*: ORS.Ident
    END;

    TypeDesc* = RECORD
      form*, ref*, mno*: INTEGER;    (* ref only for import/export *)
      nofpar*: INTEGER;              (* procs: params; records: ext level *)
      len*: INTEGER;                 (* arrays: len (<0 = open); records: TD adr *)
      dsc*, typobj*: Object;
      base*: Type;                   (* arrays, records, pointers, procs *)
      size*: INTEGER;                (* in bytes *)
      weak*: BOOLEAN;                (* WEAK POINTER TO X *)
      meth*: Object;                 (* records/interfaces: own methods *)
      impl*: Impl;                   (* records: conformances; intfcs: inclusions *)
      nofmeth*: INTEGER;             (* total vtable slots incl. inherited *)
      mfixed*: BOOLEAN;              (* slot layout frozen by an extension *)
      mthd*: BOOLEAN;                (* proc types: param 0 is a receiver *)
      backend*, backend2*: LONGINT   (* codegen-private handles *)
    END;

    ImplDesc* = RECORD
      intfc*: Type;
      next*: Impl
    END;

  VAR topScope*, universe*, systemScope*: Object;
    byteType*, boolType*, charType*: Type;
    intType*, longType*, realType*, setType*: Type;
    nilType*, noType*, strType*: Type;
    varsize*: LONGINT;   (* set by ORP before Export (structured consts) *)

    nofmod: INTEGER;
    Ref: INTEGER;
    ptrSize, intfcSize: INTEGER;   (* target sizes, set by Initialize *)
    typtab: ARRAY maxTypTab OF Type;
    sourceDir: ARRAY 256 OF CHAR;
    searchPaths: ARRAY 8 OF ARRAY 256 OF CHAR;
    numSearchPaths: INTEGER;

  (* ----- helpers ----- *)

  PROCEDURE CopyStr(VAR dst: ARRAY OF CHAR; src: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < LEN(src)) & (i < LEN(dst) - 1) & (src[i] # 0X) DO
      dst[i] := src[i]; INC(i)
    END;
    dst[i] := 0X
  END CopyStr;

  PROCEDURE AppendStr(VAR dst: ARRAY OF CHAR; VAR j: INTEGER; src: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < LEN(src)) & (j < LEN(dst) - 1) & (src[i] # 0X) DO
      dst[j] := src[i]; INC(i); INC(j)
    END;
    dst[j] := 0X
  END AppendStr;

  (* ----- symbol table ----- *)

  PROCEDURE NewObj*(VAR obj: Object; id: ARRAY OF CHAR; class: INTEGER);
    VAR new, x: Object;
  BEGIN x := topScope;
    WHILE (x.next # NIL) & (x.next.name # id) DO x := x.next END;
    IF x.next = NIL THEN
      NEW(new); CopyStr(new.name, id);
      new.class := class; new.next := NIL; new.rdo := FALSE; new.dsc := NIL;
      x.next := new; obj := new
    ELSE obj := x.next; ORS.Mark("mult def")
    END
  END NewObj;

  PROCEDURE thisObj*(): Object;
    VAR s, x: Object;
  BEGIN s := topScope;
    REPEAT x := s.next;
      WHILE (x # NIL) & (x.name # ORS.id) DO x := x.next END;
      s := s.dsc
    UNTIL (x # NIL) OR (s = NIL);
    RETURN x
  END thisObj;

  PROCEDURE thisimport*(mod: Object): Object;
    VAR obj: Object;
  BEGIN
    IF mod.rdo THEN
      IF mod.name[0] # 0X THEN
        obj := mod.dsc;
        WHILE (obj # NIL) & (obj.name # ORS.id) DO obj := obj.next END
      ELSE obj := NIL
      END
    ELSE obj := NIL
    END;
    RETURN obj
  END thisimport;

  PROCEDURE thisfield*(rec: Type): Object;
    VAR fld: Object;
  BEGIN fld := rec.dsc;
    WHILE (fld # NIL) & (fld.name # ORS.id) DO fld := fld.next END;
    RETURN fld
  END thisfield;

  (* Type-bound procedure named ORS.id along the base chain; an override
     shadows what it replaces. Imported types show exported methods only;
     initialisers are never reachable this way (DDR-003). *)
  PROCEDURE thismethod*(rec: Type): Object;
    VAR t: Type; m, res: Object;
  BEGIN t := rec; res := NIL;
    WHILE (t # NIL) & (res = NIL) DO
      m := t.meth;
      WHILE (m # NIL) & (res = NIL) DO
        IF ~m.initf & (m.name = ORS.id) & (m.expo OR (t.mno <= 0)) THEN res := m END;
        m := m.next
      END;
      t := t.base
    END;
    RETURN res
  END thismethod;

  (* Initialiser named ORS.id: the NEAREST level declaring any initialiser
     owns construction (DDR-003 inheritance rule). *)
  PROCEDURE thisinit*(rec: Type): Object;
    VAR t: Type; m, found, res: Object; declares, done: BOOLEAN;
  BEGIN t := rec; res := NIL; done := FALSE;
    WHILE (t # NIL) & ~done DO
      m := t.meth; found := NIL; declares := FALSE;
      WHILE m # NIL DO
        IF m.initf THEN
          declares := TRUE;
          IF (m.name = ORS.id) & (m.expo OR (t.mno <= 0)) THEN found := m END
        END;
        m := m.next
      END;
      IF declares THEN res := found; done := TRUE END;
      t := t.base
    END;
    RETURN res
  END thisinit;

  PROCEDURE HasVisibleInits*(rec: Type): BOOLEAN;
    VAR t: Type; m: Object; declares, visible, done, res: BOOLEAN;
  BEGIN t := rec; res := FALSE; done := FALSE;
    WHILE (t # NIL) & ~done DO
      m := t.meth; declares := FALSE; visible := FALSE;
      WHILE m # NIL DO
        IF m.initf THEN
          declares := TRUE;
          IF m.expo OR (t.mno <= 0) THEN visible := TRUE END
        END;
        m := m.next
      END;
      IF declares THEN res := visible; done := TRUE END;
      t := t.base
    END;
    RETURN res
  END HasVisibleInits;

  PROCEDURE IntfcIncludes(d, i: Type): BOOLEAN;
    VAR im: Impl; res: BOOLEAN;
  BEGIN
    IF d = i THEN res := TRUE
    ELSE res := FALSE; im := d.impl;
      WHILE (im # NIL) & ~res DO
        IF IntfcIncludes(im.intfc, i) THEN res := TRUE END;
        im := im.next
      END
    END;
    RETURN res
  END IntfcIncludes;

  PROCEDURE Conforms*(rec, intfc: Type): BOOLEAN;
    VAR im: Impl; res: BOOLEAN;
  BEGIN res := FALSE;
    WHILE (rec # NIL) & ~res DO
      im := rec.impl;
      WHILE (im # NIL) & ~res DO
        IF IntfcIncludes(im.intfc, intfc) THEN res := TRUE END;
        im := im.next
      END;
      rec := rec.base
    END;
    RETURN res
  END Conforms;

  PROCEDURE FindMeth*(rec: Type; name: ARRAY OF CHAR): Object;
    VAR m, res: Object;
  BEGIN res := NIL;
    WHILE (rec # NIL) & (res = NIL) DO
      m := rec.meth;
      WHILE (m # NIL) & (res = NIL) DO
        IF ~m.initf & (m.name = name) THEN res := m END;
        m := m.next
      END;
      rec := rec.base
    END;
    RETURN res
  END FindMeth;

  PROCEDURE HasInits*(rec: Type): BOOLEAN;
    VAR m: Object; res: BOOLEAN;
  BEGIN res := FALSE;
    WHILE (rec # NIL) & ~res DO
      m := rec.meth;
      WHILE (m # NIL) & ~res DO
        IF m.initf THEN res := TRUE END;
        m := m.next
      END;
      rec := rec.base
    END;
    RETURN res
  END HasInits;

  PROCEDURE TotalMeths*(rec: Type): INTEGER;
    VAR n: INTEGER;
  BEGIN n := 0;
    WHILE rec # NIL DO
      IF rec.nofmeth > n THEN n := rec.nofmeth END;
      rec := rec.base
    END;
    RETURN n
  END TotalMeths;

  PROCEDURE OpenScope*;
    VAR s: Object;
  BEGIN NEW(s); s.class := Head; s.dsc := topScope; s.next := NIL; topScope := s
  END OpenScope;

  PROCEDURE CloseScope*;
  BEGIN topScope := topScope.dsc
  END CloseScope;

  (* ----- paths and symbol files ----- *)

  PROCEDURE SetSourceDirectory*(filename: ARRAY OF CHAR);
    VAR i, n: INTEGER;
  BEGIN
    n := 0;
    WHILE (n < LEN(filename)) & (filename[n] # 0X) DO INC(n) END;
    i := n - 1;
    WHILE (i >= 0) & (filename[i] # "/") & (filename[i] # 5CX) DO DEC(i) END;
    IF i >= 0 THEN
      n := 0;
      WHILE n <= i DO sourceDir[n] := filename[n]; INC(n) END;
      sourceDir[n] := 0X
    ELSE sourceDir[0] := 0X
    END
  END SetSourceDirectory;

  PROCEDURE MakeFileName*(VAR FName: ARRAY OF CHAR; name, ext: ARRAY OF CHAR);
    VAR j: INTEGER;
  BEGIN j := 0; FName[0] := 0X;
    AppendStr(FName, j, sourceDir);
    AppendStr(FName, j, name);
    AppendStr(FName, j, ext)
  END MakeFileName;

  PROCEDURE AddSearchPath*(path: ARRAY OF CHAR);
    VAR j: INTEGER;
  BEGIN
    IF numSearchPaths < 8 THEN
      j := 0;
      AppendStr(searchPaths[numSearchPaths], j, path);
      IF (j > 0) & (searchPaths[numSearchPaths][j-1] # "/") &
         (searchPaths[numSearchPaths][j-1] # 5CX) THEN
        searchPaths[numSearchPaths][j] := "/";
        searchPaths[numSearchPaths][j+1] := 0X
      END;
      INC(numSearchPaths)
    END
  END AddSearchPath;

  PROCEDURE FindSymbolFile(modname: ARRAY OF CHAR): Files.File;
    VAR fname: ARRAY 256 OF CHAR;
      F: Files.File;
      i, j: INTEGER;
  BEGIN
    MakeFileName(fname, modname, ".smb");
    F := Files.Old(fname);
    i := 0;
    WHILE (F = NIL) & (i < numSearchPaths) DO
      j := 0; fname[0] := 0X;
      AppendStr(fname, j, searchPaths[i]);
      AppendStr(fname, j, modname);
      AppendStr(fname, j, ".smb");
      F := Files.Old(fname);
      INC(i)
    END;
    RETURN F
  END FindSymbolFile;

  PROCEDURE ThisModule(name, orgname: ARRAY OF CHAR; decl: BOOLEAN; key: LONGINT): Object;
    VAR mod: Module;
      obj, obj1: Object;
  BEGIN
    obj1 := topScope; obj := obj1.next;
    WHILE (obj # NIL) & (obj(Module).orgname # orgname) DO
      obj1 := obj; obj := obj1.next
    END;
    IF obj = NIL THEN
      (* new module, search for alias *)
      obj := topScope.next;
      WHILE (obj # NIL) & (obj.name # name) DO obj := obj.next END;
      IF obj = NIL THEN
        NEW(mod); mod.class := Mod; mod.rdo := FALSE;
        CopyStr(mod.name, name); CopyStr(mod.orgname, orgname);
        mod.val := key; mod.lev := nofmod; INC(nofmod);
        mod.dsc := NIL; mod.next := NIL;
        IF decl THEN mod.type := noType ELSE mod.type := nilType END;
        obj1.next := mod; obj := mod
      ELSIF decl THEN
        IF obj.type.form = NoTyp THEN ORS.Mark("mult def")
        ELSE ORS.Mark("invalid import order")
        END
      ELSE ORS.Mark("conflict with alias")
      END
    ELSIF decl THEN
      IF obj.type.form = NoTyp THEN ORS.Mark("mult def")
      ELSE ORS.Mark("invalid import order")
      END
    END;
    RETURN obj
  END ThisModule;

  (* ----- .smb primitives ----- *)

  PROCEDURE Read(VAR R: Files.Rider; VAR x: INTEGER);
    VAR b: BYTE;
  BEGIN Files.ReadByte(R, b);
    IF b < 128 THEN x := b ELSE x := b - 256 END
  END Read;

  PROCEDURE Write(VAR R: Files.Rider; x: INTEGER);
  BEGIN Files.WriteByte(R, x MOD 256)
  END Write;

  (* Variable-length signed number, identical to src/Files.c's codec
     (LEB128-signed). Implemented locally because the runtime Files
     ReadNum/WriteNum are INTEGER-typed and const values need LONGINT. *)
  PROCEDURE RNum(VAR R: Files.Rider; VAR x: LONGINT);
    VAR b: BYTE; n, m: LONGINT;
  BEGIN n := 0; m := 1;
    Files.ReadByte(R, b);
    WHILE b >= 128 DO
      n := n + (b - 128) * m; m := m * 128;
      Files.ReadByte(R, b)
    END;
    n := n + b * m; m := m * 128;
    IF b >= 64 THEN n := n - m END;
    x := n
  END RNum;

  PROCEDURE WNum(VAR R: Files.Rider; x: LONGINT);
  BEGIN
    WHILE (x < -64) OR (x >= 64) DO
      Files.WriteByte(R, x MOD 128 + 128); x := x DIV 128
    END;
    Files.WriteByte(R, x MOD 128)
  END WNum;

  (* ----- import ----- *)

  PROCEDURE InType(VAR R: Files.Rider; thismod: Object; VAR T: Type);
    VAR key: INTEGER;
      ref, class, form, np, readonly, k: INTEGER;
      n: LONGINT;
      fld, par, obj, mod, last, lastmeth, mth: Object;
      im, lastimpl: Impl;
      t: Type;
      name, modname: ORS.Ident;
  BEGIN
    Read(R, ref);
    IF ref < 0 THEN T := typtab[-ref]  (*already read*)
    ELSE
      NEW(t); T := t; typtab[ref] := t; t.mno := thismod.lev;
      Read(R, form); t.form := form;
      IF form = Int THEN RNum(R, n); t.size := n END;
      IF form = Pointer THEN
        Read(R, class);
        t.weak := class = 1;
        InType(R, thismod, t.base); t.size := ptrSize
      ELSIF form = Array THEN
        InType(R, thismod, t.base);
        RNum(R, n); t.len := n;
        RNum(R, n); t.size := n
      ELSIF form = Record THEN
        InType(R, thismod, t.base);
        IF t.base.form = NoTyp THEN t.base := NIL; obj := NIL
        ELSE obj := t.base.dsc
        END;
        RNum(R, n); t.len := n;       (* TD adr/exno *)
        RNum(R, n); t.nofpar := n;    (* ext level *)
        RNum(R, n); t.size := n;
        RNum(R, n); t.nofmeth := n;   (* total vtable slots *)
        Read(R, class);
        last := NIL; lastmeth := NIL;
        WHILE class # 0 DO
          IF class = Meth THEN
            NEW(mth); mth.class := Meth;
            Files.ReadString(R, mth.name);
            Read(R, k); mth.expo := k = 1;
            Read(R, k); mth.initf := k = 1;
            RNum(R, mth.val);        (* vtable slot (-1 for inits) *)
            Files.ReadString(R, mth.mname);
            InType(R, thismod, mth.type);
            mth.lev := -thismod.lev;
            IF lastmeth = NIL THEN t.meth := mth ELSE lastmeth.next := mth END;
            lastmeth := mth
          ELSE
            NEW(fld); fld.class := class;
            Files.ReadString(R, fld.name);
            IF last = NIL THEN t.dsc := fld ELSE last.next := fld END;
            last := fld;
            fld.expo := fld.name[0] # 0X;
            InType(R, thismod, fld.type);
            RNum(R, fld.val)
          END;
          Read(R, class)
        END;
        IF last = NIL THEN t.dsc := obj ELSE last.next := obj END;
        (* declared interface conformances *)
        Read(R, class); lastimpl := NIL;
        WHILE class # 0 DO
          NEW(im); InType(R, thismod, im.intfc);
          IF lastimpl = NIL THEN t.impl := im ELSE lastimpl.next := im END;
          lastimpl := im;
          Read(R, class)
        END
      ELSIF form = Intfc THEN
        t.size := intfcSize;   (* fat pointer {data, itable} *)
        Read(R, class); lastmeth := NIL;
        WHILE class # 0 DO
          NEW(mth); mth.class := Meth; mth.expo := TRUE;
          Files.ReadString(R, mth.name);
          RNum(R, mth.val);
          InType(R, thismod, mth.type);
          mth.lev := -thismod.lev;
          IF lastmeth = NIL THEN t.meth := mth ELSE lastmeth.next := mth END;
          lastmeth := mth;
          INC(t.nofmeth);
          Read(R, class)
        END;
        (* directly included interfaces *)
        Read(R, class); lastimpl := NIL;
        WHILE class # 0 DO
          NEW(im); InType(R, thismod, im.intfc);
          IF lastimpl = NIL THEN t.impl := im ELSE lastimpl.next := im END;
          lastimpl := im;
          Read(R, class)
        END
      ELSIF form = Proc THEN
        Read(R, class);               (* method-type flag *)
        t.mthd := class = 1;
        InType(R, thismod, t.base);
        obj := NIL; np := 0;
        Read(R, class);
        WHILE class # 0 DO
          NEW(par); par.class := class;
          Read(R, readonly); par.rdo := readonly = 1;
          InType(R, thismod, par.type);
          par.next := obj; obj := par; INC(np);
          Read(R, class)
        END;
        t.dsc := obj; t.nofpar := np; t.size := ptrSize
      END;
      (* unify basic types with the global type objects so pointer
         equality works across module boundaries *)
      IF form = Byte THEN T := byteType; typtab[ref] := T
      ELSIF form = Bool THEN T := boolType; typtab[ref] := T
      ELSIF form = Char THEN T := charType; typtab[ref] := T
      ELSIF form = Int THEN
        IF t.size >= longType.size THEN T := longType ELSE T := intType END;
        typtab[ref] := T
      ELSIF form = Real THEN T := realType; typtab[ref] := T
      ELSIF form = Set THEN T := setType; typtab[ref] := T
      ELSIF form = NilTyp THEN T := nilType; typtab[ref] := T
      ELSIF form = NoTyp THEN T := noType; typtab[ref] := T
      END;

      Files.ReadString(R, modname);
      IF modname[0] # 0X THEN  (*re-import*)
        Files.ReadInt(R, key);
        Files.ReadString(R, name);
        mod := ThisModule(modname, modname, FALSE, key);
        obj := mod.dsc;
        WHILE (obj # NIL) & (obj.name # name) DO obj := obj.next END;
        IF obj # NIL THEN T := obj.type  (*type object found*)
        ELSE
          NEW(obj); CopyStr(obj.name, name); obj.class := Typ;
          obj.expo := TRUE;
          obj.next := mod.dsc; mod.dsc := obj; obj.type := T;
          T.mno := mod.lev; T.typobj := obj
        END;
        typtab[ref] := T
      END
    END
  END InType;

  PROCEDURE Import*(modid, modid1: ARRAY OF CHAR);
    VAR key: INTEGER;
      class, k: INTEGER;
      obj: Object;
      t: Type;
      thismod: Object;
      modname: ORS.Ident;
      F: Files.File;
      R: Files.Rider;
  BEGIN
    IF modid1 = "SYSTEM" THEN
      thismod := ThisModule(modid, modid1, TRUE, 0); DEC(nofmod);
      thismod.lev := 0; thismod.dsc := systemScope; thismod.rdo := TRUE
    ELSE
      F := FindSymbolFile(modid1);
      IF F # NIL THEN
        Files.Set(R, F, 0);
        Files.ReadInt(R, key); Files.ReadInt(R, key);
        Files.ReadString(R, modname);
        thismod := ThisModule(modid, modid1, TRUE, key);
        thismod.rdo := TRUE;
        Read(R, class);  (*version key*)
        IF class # versionkey THEN ORS.Mark("wrong version") END;
        Read(R, class);
        WHILE class # 0 DO
          NEW(obj); obj.class := class;
          Files.ReadString(R, obj.name);
          InType(R, thismod, obj.type);
          obj.lev := -thismod.lev;
          IF class = Typ THEN
            t := obj.type; t.typobj := obj;
            Read(R, k);
            WHILE k # 0 DO  (*fixup bases of previously declared pointer types*)
              typtab[k].base := t;
              Read(R, k)
            END
          ELSE
            IF class = Const THEN
              IF obj.type.form = Real THEN
                Files.ReadInt(R, k); obj.val := k
              ELSE RNum(R, obj.val)
              END
            ELSIF class = Var THEN
              RNum(R, obj.val); obj.rdo := TRUE
            END
          END;
          obj.expo := TRUE;
          obj.next := thismod.dsc; thismod.dsc := obj;
          Read(R, class)
        END;
        Files.Close(F)
      ELSE ORS.Mark("import not available")
      END
    END
  END Import;

  (* ----- export ----- *)

  PROCEDURE OutType(VAR R: Files.Rider; t: Type);

    PROCEDURE OutPar(VAR R: Files.Rider; par: Object; n: INTEGER);
    BEGIN
      IF n > 0 THEN
        OutPar(R, par.next, n-1);
        Write(R, par.class);
        IF par.rdo THEN Write(R, 1) ELSE Write(R, 0) END;
        OutType(R, par.type)
      END
    END OutPar;

    (* fields: every source-level field with full type; private ones with
       empty names so the importer reconstructs the layout exactly *)
    PROCEDURE OutFields(VAR R: Files.Rider; fld, bot: Object);
      VAR empty: ORS.Ident;
    BEGIN empty[0] := 0X;
      WHILE fld # bot DO
        Write(R, Fld);
        IF fld.expo THEN Files.WriteString(R, fld.name)
        ELSE Files.WriteString(R, empty)
        END;
        OutType(R, fld.type);
        WNum(R, fld.val);
        fld := fld.next
      END
    END OutFields;

    (* own methods, declaration order: every one goes out — exported or
       not — with real name, flags, vtable slot and mangled symbol *)
    PROCEDURE OutMeths(VAR R: Files.Rider; m: Object);
    BEGIN
      WHILE m # NIL DO
        Write(R, Meth);
        Files.WriteString(R, m.name);
        IF m.expo THEN Write(R, 1) ELSE Write(R, 0) END;
        IF m.initf THEN Write(R, 1) ELSE Write(R, 0) END;
        WNum(R, m.val);
        Files.WriteString(R, m.mname);
        OutType(R, m.type);
        m := m.next
      END
    END OutMeths;

    (* interface members: flattened set — name, itable index, signature *)
    PROCEDURE OutIfcMeths(VAR R: Files.Rider; m: Object);
    BEGIN
      WHILE m # NIL DO
        Write(R, Meth);
        Files.WriteString(R, m.name);
        WNum(R, m.val);
        OutType(R, m.type);
        m := m.next
      END
    END OutIfcMeths;

    PROCEDURE OutImpls(VAR R: Files.Rider; im: Impl);
    BEGIN
      WHILE im # NIL DO
        Write(R, 1);
        OutType(R, im.intfc);
        im := im.next
      END
    END OutImpls;

    PROCEDURE OutReExport(VAR R: Files.Rider; t: Type);
      VAR mod: Object;
    BEGIN
      mod := topScope.next;
      WHILE (mod # NIL) & (mod.lev # t.mno) DO mod := mod.next END;
      IF mod # NIL THEN
        Files.WriteString(R, mod(Module).orgname);
        Files.WriteInt(R, mod.val);
        Files.WriteString(R, t.typobj.name)
      ELSE ORS.Mark("re-export not found"); Write(R, 0)
      END
    END OutReExport;

  BEGIN
    IF t.ref > 0 THEN Write(R, -t.ref)  (*type was already output*)
    ELSE
      IF t.typobj # NIL THEN Write(R, Ref); t.ref := Ref; INC(Ref)
      ELSE Write(R, 0)  (*anonymous*)
      END;
      Write(R, t.form);
      IF t.form = Int THEN WNum(R, t.size) END;
      IF t.form = Pointer THEN
        (* v5: the WEAK flag travels — without it an imported weak
           pointer becomes strong and ARC over-releases its targets *)
        IF t.weak THEN Write(R, 1) ELSE Write(R, 0) END;
        OutType(R, t.base)
      ELSIF t.form = Array THEN
        OutType(R, t.base); WNum(R, t.len); WNum(R, t.size)
      ELSIF t.form = Record THEN
        IF t.base # NIL THEN OutType(R, t.base)
        ELSE OutType(R, noType)
        END;
        WNum(R, t.len);
        WNum(R, t.nofpar); WNum(R, t.size);
        WNum(R, TotalMeths(t));
        IF t.base # NIL THEN OutFields(R, t.dsc, t.base.dsc)
        ELSE OutFields(R, t.dsc, NIL)
        END;
        OutMeths(R, t.meth);
        Write(R, 0);
        OutImpls(R, t.impl);
        Write(R, 0)
      ELSIF t.form = Intfc THEN
        OutIfcMeths(R, t.meth);
        Write(R, 0);
        OutImpls(R, t.impl);
        Write(R, 0)
      ELSIF t.form = Proc THEN
        IF t.mthd THEN Write(R, 1) ELSE Write(R, 0) END;
        OutType(R, t.base);
        OutPar(R, t.dsc, t.nofpar);
        Write(R, 0)
      END;
      IF (t.mno > 0) & (t.typobj # NIL) THEN  (*re-export, output name*)
        OutReExport(R, t)
      ELSE Write(R, 0)
      END
    END
  END OutType;

  PROCEDURE Export*(modid: ARRAY OF CHAR; VAR newSF: BOOLEAN; VAR key: LONGINT);
    VAR x, sum, oldkey: INTEGER;
      obj, obj0: Object;
      filename: ARRAY 256 OF CHAR;
      F, F1: Files.File;
      R, R1: Files.Rider;
  BEGIN
    Ref := Record + 1;
    MakeFileName(filename, modid, ".smb");

    (* read old checksum first *)
    F1 := Files.Old(filename);
    IF F1 # NIL THEN
      Files.Set(R1, F1, 4); Files.ReadInt(R1, oldkey); Files.Close(F1)
    ELSE oldkey := 0
    END;

    F := Files.New(filename);
    Files.Set(R, F, 0);
    Files.WriteInt(R, 0);  (*placeholder*)
    Files.WriteInt(R, 0);  (*placeholder for key*)
    Files.WriteString(R, modid);
    Write(R, versionkey);

    obj := topScope.next;
    WHILE obj # NIL DO
      IF obj.expo THEN
        Write(R, obj.class);
        Files.WriteString(R, obj.name);
        OutType(R, obj.type);
        IF obj.class = Typ THEN
          IF obj.type.form = Record THEN
            obj0 := topScope.next;
            (* base of previously declared pointer types? *)
            WHILE obj0 # obj DO
              IF (obj0.type.form = Pointer) & (obj0.type.base = obj.type) &
                 (obj0.type.ref > 0) THEN
                Write(R, obj0.type.ref)
              END;
              obj0 := obj0.next
            END
          END;
          Write(R, 0)
        ELSIF obj.class = Const THEN
          IF obj.type.form = Proc THEN WNum(R, obj.exno)
          ELSIF obj.type.form = Real THEN
            x := obj.val; Files.WriteInt(R, x)
          ELSIF (obj.type.form = Array) OR (obj.type.form = Record) THEN
            WNum(R, varsize + obj.val)
          ELSE WNum(R, obj.val)
          END
        ELSIF obj.class = Var THEN
          WNum(R, obj.val)
        END
      END;
      obj := obj.next
    END;

    REPEAT Write(R, 0) UNTIL Files.Length(F) MOD 4 = 0;

    FOR x := Record+1 TO maxTypTab-1 DO typtab[x] := NIL END;

    (* checksum over the buffered content, then patch and register once *)
    Files.Set(R, F, 0);
    sum := 0; Files.ReadInt(R, x);
    WHILE ~R.eof DO
      sum := sum + x; Files.ReadInt(R, x)
    END;

    IF sum # oldkey THEN
      IF newSF OR (oldkey = 0) THEN
        key := sum; newSF := TRUE;
        Files.Set(R, F, 4); Files.WriteInt(R, sum);
        Files.Register(F); Files.Close(F)
      ELSE ORS.Mark("new symbol file inhibited")
      END
    ELSE
      (* interface fingerprint unchanged — keep the existing key, but
         still patch it in (the fresh file has a placeholder there) *)
      newSF := FALSE; key := sum;
      Files.Set(R, F, 4); Files.WriteInt(R, sum);
      Files.Register(F); Files.Close(F)
    END
  END Export;

  (* ----- initialisation ----- *)

  PROCEDURE Init*;
  BEGIN topScope := universe; nofmod := 1
  END Init;

  (* structured-const offsets in Export are varsize-relative; the parser
     sets it before exporting (imported VARs are read-only) *)
  PROCEDURE SetVarSize*(n: LONGINT);
  BEGIN varsize := n
  END SetVarSize;

  PROCEDURE type(ref, form, size: INTEGER): Type;
    VAR tp: Type;
  BEGIN
    NEW(tp); tp.form := form; tp.size := size; tp.ref := ref; tp.base := NIL;
    typtab[ref] := tp;
    RETURN tp
  END type;

  PROCEDURE enter(name: ARRAY OF CHAR; cl: INTEGER; type: Type; n: INTEGER);
    VAR obj: Object;
  BEGIN
    NEW(obj); CopyStr(obj.name, name);
    obj.class := cl; obj.type := type; obj.val := n; obj.dsc := NIL;
    IF cl = Typ THEN type.typobj := obj END;
    obj.next := systemScope; systemScope := obj
  END enter;

  (* Register a SYSTEM pseudo-module identifier. The backend's InitSystem
     calls these after Initialize; each target supplies its own set with
     target-appropriate result types and arities (DDR back-porting). *)
  PROCEDURE SysFunc*(name: ARRAY OF CHAR; typ: Type; n: INTEGER);
  BEGIN enter(name, SFunc, typ, n)
  END SysFunc;

  PROCEDURE SysProc*(name: ARRAY OF CHAR; typ: Type; n: INTEGER);
  BEGIN enter(name, SProc, typ, n)
  END SysProc;

  (* Basic-type sizes are supplied by the backend (they differ per target:
     e.g. INTEGER is 4 on LLVM, 2 on the 65C816; pointers are 4 on both;
     an interface fat pointer is 16 on LLVM (two 8-byte native pointers)
     but 8 on the 65C816). BYTE/BOOL/CHAR are 1 on every target. *)
  PROCEDURE Initialize*(intSz, longSz, realSz, setSz, nilSz, strSz,
                        ptrSz, intfcSz: INTEGER);
  BEGIN
    ptrSize := ptrSz; intfcSize := intfcSz;
    byteType := type(Byte, Int, 1);
    boolType := type(Bool, Bool, 1);
    charType := type(Char, Char, 1);
    intType := type(Int, Int, intSz);
    (* longType shares form Int but must NOT overwrite typtab[Int] *)
    NEW(longType); longType.form := Int; longType.size := longSz;
    longType.ref := 0; longType.base := NIL;
    realType := type(Real, Real, realSz);
    setType := type(Set, Set, setSz);
    nilType := type(NilTyp, NilTyp, nilSz);
    noType := type(NoTyp, NoTyp, nilSz);
    strType := type(String, String, strSz);

    systemScope := NIL;  (* n = procno*10 + nofpar *)

    (* functions *)
    enter("UML", SFunc, intType, 132);
    enter("ROL", SFunc, intType, 122);
    enter("LSR", SFunc, intType, 112);
    enter("ASL", SFunc, intType, 102);
    enter("ORA", SFunc, intType, 92);
    enter("EOR", SFunc, intType, 82);
    enter("AND", SFunc, intType, 72);
    enter("LEN", SFunc, intType, 61);
    enter("CHR", SFunc, charType, 51);
    enter("ORD", SFunc, intType, 41);
    enter("FLT", SFunc, realType, 31);
    enter("FLOOR", SFunc, intType, 21);
    enter("ODD", SFunc, boolType, 11);
    enter("ABS", SFunc, intType, 1);

    (* procedures *)
    enter("UNPK", SProc, noType, 72);
    enter("PACK", SProc, noType, 62);
    enter("NEW", SProc, noType, 51);
    enter("ASSERT", SProc, noType, 41);
    enter("EXCL", SProc, noType, 32);
    enter("INCL", SProc, noType, 22);
    enter("DEC", SProc, noType, 11);
    enter("INC", SProc, noType, 1);

    (* types *)
    enter("SET", Typ, setType, 0);
    enter("BOOLEAN", Typ, boolType, 0);
    enter("BYTE", Typ, byteType, 0);
    enter("CHAR", Typ, charType, 0);
    enter("LONGREAL", Typ, realType, 0);
    enter("REAL", Typ, realType, 0);
    enter("LONGINT", Typ, longType, 0);
    enter("INTEGER", Typ, intType, 0);

    topScope := NIL; OpenScope();
    topScope.next := systemScope;
    universe := topScope;

    (* The "unsafe" pseudo-module SYSTEM is populated by the backend's
       InitSystem (called next by ORP): its identifiers and their result
       types/arities are target-specific. Leave the scope empty here. *)
    systemScope := NIL
  END Initialize;

BEGIN
  numSearchPaths := 0; sourceDir[0] := 0X; varsize := 0
END ORB.
