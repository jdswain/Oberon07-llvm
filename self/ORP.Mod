MODULE ORP; (* NW 25.6.2014 / AP 4.3.2020 / 8.3.2019 in Oberon-07.
   Self-hosted port of src/ORP.c: the parser. Grammar and checks carry
   every extension the C compiler gained:
     - LONGINT / WEAK pointers / promoted structured value params;
     - type-bound procedures with OVERRIDE (DDR-001/002);
     - INIT constructors and type-qualified construction (DDR-003/004/005);
     - SUPER calls with the derived-initialiser chaining rule (DDR-006);
     - interfaces: INTERFACE types, inclusion, IMPLEMENTS + whole-module
       conformance checking, fat-pointer conversions (DDR-008);
     - numeric and type CASE, structured constants (65C816 heritage).
   The driver (argument parsing, auto-compile, linking) stays in C —
   self/main.c — and calls Compile.

   The parser is two modules, a 65C816 module's code being a bank: ORPS
   (expressions and statements) and ORP (types, declarations, procedures,
   the module), ORPS's friend. *)

  IMPORT ORH, ORS, ORB, ORG, ORPS;

  TYPE
    PtrBase = POINTER TO PtrBaseDesc;
    PtrBaseDesc = RECORD
      name: ORS.Ident;
      type: ORB.Type;
      next: PtrBase
    END;

    TypeProc = PROCEDURE (VAR type: ORB.Type);
    FormalTypeProc = PROCEDURE (VAR typ: ORB.Type; dim: INTEGER);

  VAR
    dc: LONGINT;   (*data counter*)
    exno: INTEGER;
    newSF: BOOLEAN;
    Type: TypeProc;
    FormalType: FormalTypeProc;
    modid: ORS.Ident;
    pbsList: PtrBase;   (*list of names of pointer base types*)


  (* types and declarations *)

  PROCEDURE IdentList(class: INTEGER; VAR first: ORB.Object);
    VAR obj: ORB.Object;
  BEGIN
    IF ORPS.sym = ORS.ident THEN
      ORB.NewObj(first, ORS.id, class); ORS.Get(ORPS.sym);
      ORPS.CheckExport(first.expo);
      WHILE ORPS.sym = ORS.comma DO
        ORS.Get(ORPS.sym);
        IF ORPS.sym = ORS.ident THEN
          ORB.NewObj(obj, ORS.id, class); ORS.Get(ORPS.sym);
          ORPS.CheckExport(obj.expo)
        ELSE ORS.Mark("ident?")
        END
      END;
      IF ORPS.sym = ORS.colon THEN ORS.Get(ORPS.sym) ELSE ORS.Mark(":?") END
    ELSE first := NIL
    END
  END IdentList;

  PROCEDURE ArrayType(VAR type: ORB.Type);
    VAR x: ORG.Item; typ: ORB.Type; len: LONGINT;
  BEGIN
    NEW(typ); typ.form := ORB.NoTyp;
    ORPS.expression(x);
    IF (x.mode = ORB.Const) & (x.type.form = ORB.Int) & (x.a >= 0) THEN
      len := x.a
    ELSE len := 1; ORS.Mark("not a valid length")
    END;
    IF ORPS.sym = ORS.of THEN
      ORS.Get(ORPS.sym);
      Type(typ.base);
      IF (typ.base.form = ORB.Array) & (typ.base.len < 0) THEN
        ORS.Mark("dyn array not allowed")
      END
    ELSIF ORPS.sym = ORS.comma THEN
      ORS.Get(ORPS.sym);
      ArrayType(typ.base)
    ELSE
      ORS.Mark("missing OF"); typ.base := ORB.intType
    END;
    typ.size := len * typ.base.size;
    typ.form := ORB.Array;
    typ.len := len;
    type := typ
  END ArrayType;

  PROCEDURE RecordType(VAR type: ORB.Type);
    VAR obj, obj0, new, bot, base: ORB.Object;
      typ, tp: ORB.Type;
      im: ORB.Impl;
      offset, off, n: LONGINT;
  BEGIN
    NEW(typ); typ.form := ORB.NoTyp; typ.base := NIL;
    typ.mno := -ORPS.level; typ.nofpar := 0;
    offset := 0; bot := NIL;
    IF ORPS.sym = ORS.lparen THEN
      ORS.Get(ORPS.sym);  (*record extension*)
      IF ORPS.level # 0 THEN ORS.Mark("extension of local types not implemented") END;
      IF ORPS.sym = ORS.ident THEN
        ORPS.qualident(base);
        IF base.class = ORB.Typ THEN
          IF base.type.form = ORB.Record THEN typ.base := base.type
          ELSE typ.base := ORB.intType; ORS.Mark("invalid extension")
          END;
          typ.nofpar := typ.base.nofpar + 1;
          bot := typ.base.dsc;
          offset := typ.base.size
        ELSE ORS.Mark("type expected")
        END
      ELSE ORS.Mark("ident expected")
      END;
      ORPS.Check(ORS.rparen, "no )")
    END;
    IF ORPS.sym = ORS.implements THEN
      (* declared conformance (DDR-008 §5.1): one base record, many
         interfaces — checked once per module after all methods *)
      IF ORPS.level # 0 THEN ORS.Mark("IMPLEMENTS only at module level") END;
      REPEAT
        ORS.Get(ORPS.sym);
        IF ORPS.sym = ORS.ident THEN
          ORPS.qualident(base);
          IF (base.class = ORB.Typ) & (base.type # NIL) &
             (base.type.form = ORB.Intfc) THEN
            NEW(im); im.intfc := base.type;
            im.next := typ.impl; typ.impl := im
          ELSE ORS.Mark("interface expected")
          END
        ELSE ORS.Mark("ident expected")
        END
      UNTIL ORPS.sym # ORS.comma
    END;
    WHILE ORPS.sym = ORS.ident DO  (*fields*)
      n := 0; obj := bot;
      WHILE ORPS.sym = ORS.ident DO
        obj0 := obj;
        WHILE (obj0 # NIL) & (obj0.name # ORS.id) DO obj0 := obj0.next END;
        IF obj0 # NIL THEN ORS.Mark("mult def") END;
        NEW(new); ORS.CopyId(new.name); new.class := ORB.Fld;
        new.next := obj; obj := new; INC(n);
        ORS.Get(ORPS.sym);
        ORPS.CheckExport(new.expo);
        IF (ORPS.sym # ORS.comma) & (ORPS.sym # ORS.colon) THEN ORS.Mark("comma expected")
        ELSIF ORPS.sym = ORS.comma THEN ORS.Get(ORPS.sym)
        END
      END;
      ORPS.Check(ORS.colon, "colon expected");
      Type(tp);
      IF (tp.form = ORB.Array) & (tp.len < 0) THEN ORS.Mark("dyn array not allowed") END;
      IF tp.size > 1 THEN offset := (offset + 1) DIV 2 * 2 END;
      offset := offset + n * tp.size;
      off := offset; obj0 := obj;
      WHILE obj0 # bot DO
        obj0.type := tp; obj0.lev := 0;
        off := off - tp.size; obj0.val := off;
        obj0 := obj0.next
      END;
      bot := obj;
      IF ORPS.sym = ORS.semicolon THEN ORS.Get(ORPS.sym)
      ELSIF ORPS.sym # ORS.end THEN ORS.Mark(" ; or END")
      END
    END;
    typ.form := ORB.Record;
    typ.dsc := bot;
    typ.size := offset;
    type := typ
  END RecordType;

  PROCEDURE FPSection(VAR adr: LONGINT; VAR nofpar: INTEGER);
    VAR obj, first: ORB.Object;
      tp: ORB.Type;
      parsize: LONGINT;
      cl: INTEGER;
      rdo: BOOLEAN;
  BEGIN
    IF ORPS.sym = ORS.var THEN ORS.Get(ORPS.sym); cl := ORB.Par
    ELSE cl := ORB.Var
    END;
    IdentList(cl, first);
    FormalType(tp, 0);
    rdo := FALSE;
    IF (cl = ORB.Var) & (tp.form >= ORB.Array) & (tp.form # ORB.Intfc) THEN
      cl := ORB.Par; rdo := TRUE
      (* array/record value params promoted, read-only; interface values
         stay by-value (two-word fat pointer) *)
    END;
    IF (tp.form = ORB.Array) & (tp.len < 0) THEN
      parsize := ORG.PtrSize + ORPS.WordSize   (* open array: pointer + length word *)
    ELSIF (cl = ORB.Par) & (tp.form = ORB.Record) THEN
      parsize := 2 * ORG.PtrSize          (* VAR record: data pointer + type-tag pointer *)
    ELSIF cl = ORB.Par THEN
      parsize := ORG.PtrSize              (* VAR / promoted value param: a pointer *)
    ELSE parsize := tp.size
    END;
    WHILE first # NIL DO
      INC(nofpar);
      first.class := cl; first.type := tp; first.rdo := rdo;
      first.lev := ORPS.level;
      first.val := adr + 1;
      adr := adr + parsize;
      first := first.next
    END;
    IF adr >= ORG.ParLimit THEN ORS.Mark("too many parameters") END
  END FPSection;

  PROCEDURE ProcedureType(ptype: ORB.Type; VAR parblksize: LONGINT);
    VAR obj: ORB.Object;
      size: LONGINT;
      nofpar: INTEGER;
  BEGIN
    ptype.base := ORB.noType;
    size := parblksize; nofpar := 0;
    ptype.dsc := NIL;
    IF ORPS.sym = ORS.lparen THEN
      ORS.Get(ORPS.sym);
      IF ORPS.sym = ORS.rparen THEN ORS.Get(ORPS.sym)
      ELSE
        FPSection(size, nofpar);
        WHILE ORPS.sym = ORS.semicolon DO
          ORS.Get(ORPS.sym);
          FPSection(size, nofpar)
        END;
        ORPS.Check(ORS.rparen, "no )")
      END;
      IF ORPS.sym = ORS.colon THEN  (*function*)
        ORS.Get(ORPS.sym);
        IF ORPS.sym = ORS.ident THEN
          ORPS.qualident(obj);
          ptype.base := obj.type;
          IF ~((obj.class = ORB.Typ) &
               (((obj.type.form >= ORB.Byte) & (obj.type.form <= ORB.Pointer)) OR
                (obj.type.form = ORB.Proc) OR
                (obj.type.form = ORB.Intfc))) THEN
            ORS.Mark("illegal function type")
          END
        ELSE ORS.Mark("type identifier expected")
        END
      END
    END;
    ptype.nofpar := nofpar;
    parblksize := size
  END ProcedureType;

  PROCEDURE FormalType0(VAR typ: ORB.Type; dim: INTEGER);
    VAR obj: ORB.Object; dmy: LONGINT;
  BEGIN
    IF ORPS.sym = ORS.ident THEN
      ORPS.qualident(obj);
      IF obj.class = ORB.Typ THEN typ := obj.type
      ELSE ORS.Mark("not a type"); typ := ORB.intType
      END
    ELSIF ORPS.sym = ORS.array THEN
      ORS.Get(ORPS.sym);
      ORPS.Check(ORS.of, "OF ?");
      IF dim >= 1 THEN ORS.Mark("multi-dimensional open arrays not implemented") END;
      NEW(typ);
      typ.form := ORB.Array; typ.len := -1;
      typ.size := ORG.PtrSize + ORPS.WordSize;   (* open-array descriptor: pointer + length word *)
      FormalType(typ.base, dim + 1)
    ELSIF ORPS.sym = ORS.procedure THEN
      ORS.Get(ORPS.sym);
      ORB.OpenScope;
      NEW(typ); typ.form := ORB.Proc; typ.size := 4;
      dmy := 0;
      ProcedureType(typ, dmy);
      typ.dsc := ORB.topScope.next;
      ORB.CloseScope
    ELSE
      ORS.Mark("identifier expected"); typ := ORB.noType
    END
  END FormalType0;

  PROCEDURE CheckRecLevel(lev: INTEGER);
  BEGIN
    IF lev # 0 THEN ORS.Mark("ptr base must be global") END
  END CheckRecLevel;

  (* INTERFACE ... END (DDR-008 §3/§4): method signatures only. A bare
     interface name in member position INCLUDES that interface —
     flattening union, identical signatures collapse, same name with a
     different signature is an ambiguity error. Member val is the itable
     index in the flattened set. *)
  PROCEDURE InterfaceType(VAR type: ORB.Type);
    VAR typ, ptype: ORB.Type;
      tail, iobj, m, ex, nm, rp: ORB.Object;
      inc: ORB.Impl;
      slot: INTEGER;
      dmy: LONGINT;
      mname: ORS.Ident;
  BEGIN
    NEW(typ); typ.form := ORB.Intfc;
    typ.size := 16;   (* fat pointer {data, itable} *)
    typ.mno := -ORPS.level;
    tail := NIL; slot := 0;
    WHILE (ORPS.sym = ORS.ident) OR (ORPS.sym = ORS.procedure) DO
      IF ORPS.sym = ORS.ident THEN
        (* inclusion by naming *)
        ORPS.qualident(iobj);
        IF (iobj.class = ORB.Typ) & (iobj.type # NIL) &
           (iobj.type.form = ORB.Intfc) THEN
          (* remember the inclusion: conformance looks through it *)
          NEW(inc); inc.intfc := iobj.type;
          inc.next := typ.impl; typ.impl := inc;
          m := iobj.type.meth;
          WHILE m # NIL DO
            ex := typ.meth;
            WHILE (ex # NIL) & (ex.name # m.name) DO ex := ex.next END;
            IF ex # NIL THEN
              (* diamond collapse: identical signatures merge *)
              IF ~ORPS.EqualSignatures(ex.type, m.type) THEN
                ORS.Mark("conflicting signatures in included interfaces")
              END
            ELSE
              NEW(nm);
              nm.class := ORB.Meth; nm.expo := TRUE;
              nm.name := m.name; nm.type := m.type;
              nm.lev := m.lev; nm.initf := m.initf;
              nm.next := NIL; nm.val := slot; INC(slot);
              IF tail = NIL THEN typ.meth := nm ELSE tail.next := nm END;
              tail := nm
            END;
            m := m.next
          END
        ELSE ORS.Mark("interface expected")
        END
      ELSE
        (* PROCEDURE Name [FormalParameters] — a required signature *)
        ORS.Get(ORPS.sym);
        IF ORPS.sym = ORS.ident THEN
          ORS.CopyId(mname);
          ORS.Get(ORPS.sym);
          NEW(ptype);
          ptype.form := ORB.Proc; ptype.size := 4; ptype.mthd := TRUE;
          ORB.OpenScope;
          (* synthetic receiver: the conforming type is unknown here *)
          ORB.NewObj(rp, "@", ORB.Var);
          rp.type := ORB.nilType; rp.lev := ORPS.level;
          dmy := 0;
          ProcedureType(ptype, dmy);
          INC(ptype.nofpar);
          ptype.dsc := ORB.topScope.next;
          ORB.CloseScope;
          nm := typ.meth;
          WHILE (nm # NIL) & (nm.name # mname) DO nm := nm.next END;
          IF nm # NIL THEN ORS.Mark("mult def")
          ELSE
            NEW(nm); nm.name := mname;
            nm.class := ORB.Meth; nm.expo := TRUE;
            nm.type := ptype;
            nm.val := slot; INC(slot);
            nm.next := NIL;
            IF tail = NIL THEN typ.meth := nm ELSE tail.next := nm END;
            tail := nm
          END
        ELSE ORS.Mark("method name expected")
        END
      END;
      IF ORPS.sym = ORS.semicolon THEN ORS.Get(ORPS.sym)
      ELSIF ORPS.sym # ORS.end THEN ORS.Mark("; or END")
      END
    END;
    typ.nofmeth := slot;
    type := typ
  END InterfaceType;

  PROCEDURE Type0(VAR type: ORB.Type);
    VAR dmy: LONGINT;
      obj: ORB.Object;
      ptbase: PtrBase;
      isWeak: BOOLEAN;
  BEGIN
    isWeak := FALSE;
    type := ORB.intType;  (*sync*)
    IF (ORPS.sym # ORS.ident) & (ORPS.sym < ORS.array) & (ORPS.sym # ORS.weak) THEN
      ORS.Mark("not a type");
      REPEAT ORS.Get(ORPS.sym)
      UNTIL (ORPS.sym = ORS.ident) OR (ORPS.sym >= ORS.array) OR (ORPS.sym = ORS.weak)
    END;
    (* optional WEAK prefix: applies only to a following POINTER type *)
    IF ORPS.sym = ORS.weak THEN
      ORS.Get(ORPS.sym); isWeak := TRUE;
      IF ORPS.sym # ORS.pointer THEN ORS.Mark("POINTER expected after WEAK") END
    END;
    IF ORPS.sym = ORS.ident THEN
      ORPS.qualident(obj);
      IF obj.class = ORB.Typ THEN
        IF (obj.type # NIL) & (obj.type.form # ORB.NoTyp) THEN
          type := obj.type
        END
      ELSE ORS.Mark("not a type or undefined")
      END
    ELSIF ORPS.sym = ORS.array THEN
      ORS.Get(ORPS.sym); ArrayType(type)
    ELSIF ORPS.sym = ORS.record THEN
      ORS.Get(ORPS.sym); RecordType(type); ORPS.Check(ORS.end, "no END")
    ELSIF ORPS.sym = ORS.interface THEN
      ORS.Get(ORPS.sym); InterfaceType(type); ORPS.Check(ORS.end, "no END")
    ELSIF ORPS.sym = ORS.pointer THEN
      ORS.Get(ORPS.sym); ORPS.Check(ORS.to, "no TO");
      NEW(type);
      type.form := ORB.Pointer; type.size := 4;
      type.base := ORB.intType; type.weak := isWeak;
      IF ORPS.sym = ORS.ident THEN
        obj := ORB.thisObj();
        IF obj # NIL THEN
          IF (obj.class = ORB.Typ) &
             ((obj.type.form = ORB.Record) OR (obj.type.form = ORB.NoTyp)) THEN
            CheckRecLevel(obj.lev);
            type.base := obj.type
          ELSIF obj.class = ORB.Mod THEN
            ORS.Mark("external base type not implemented")
          ELSE ORS.Mark("no valid base type")
          END
        ELSE
          CheckRecLevel(ORPS.level);
          (*enter into list of forward references to be fixed in Declarations*)
          NEW(ptbase);
          ORS.CopyId(ptbase.name);
          ptbase.type := type;
          ptbase.next := pbsList; pbsList := ptbase
        END;
        ORS.Get(ORPS.sym)
      ELSE
        Type(type.base);
        IF (type.base.form # ORB.Record) OR (type.base.typobj = NIL) THEN
          ORS.Mark("must point to named record")
        END;
        CheckRecLevel(ORPS.level)
      END
    ELSIF ORPS.sym = ORS.procedure THEN
      ORS.Get(ORPS.sym);
      ORB.OpenScope;
      NEW(type);
      type.form := ORB.Proc; type.size := 4;
      dmy := 0;
      ProcedureType(type, dmy);
      type.dsc := ORB.topScope.next;
      ORB.CloseScope
    ELSE ORS.Mark("illegal type")
    END
  END Type0;

  PROCEDURE Declarations(VAR varsize: LONGINT; parblksize: LONGINT);
    VAR obj, first, tobj: ORB.Object;
      x: ORG.Item;
      tp, arrtyp: ORB.Type;
      ptbase: PtrBase;
      expo: BOOLEAN;
      id: ORS.Ident;
      reorderOfs, cstart, ccount, cval: LONGINT;
      p: ORB.Object;
  BEGIN
    (*sync*)
    pbsList := NIL;
    IF (ORPS.sym < ORS.const) & (ORPS.sym # ORS.end) & (ORPS.sym # ORS.return) THEN
      ORS.Mark("declaration?");
      REPEAT ORS.Get(ORPS.sym)
      UNTIL (ORPS.sym >= ORS.const) OR (ORPS.sym = ORS.end) OR (ORPS.sym = ORS.return)
    END;
    IF ORPS.sym = ORS.const THEN
      ORS.Get(ORPS.sym);
      WHILE ORPS.sym = ORS.ident DO
        ORS.CopyId(id);
        ORS.Get(ORPS.sym);
        ORPS.CheckExport(expo);
        IF ORPS.sym = ORS.eql THEN ORS.Get(ORPS.sym) ELSE ORS.Mark("= ?") END;
        IF ORPS.sym = ORS.array THEN
          (* structured array constant: ARRAY OF <basetype> { c, c, ... }.
             The elements are emitted into the module data (string) section;
             the Const object carries that offset and an Array type, so it is
             read-only indexed like any other array. Element type must be
             1 or 2 bytes (BYTE/CHAR/INTEGER). *)
          ORS.Get(ORPS.sym); ORPS.Check(ORS.of, "OF?");
          ORPS.qualident(tobj);
          IF tobj.class = ORB.Typ THEN tp := tobj.type
          ELSE ORS.Mark("not a type"); tp := ORB.intType END;
          cstart := ORG.StrOffset(); ccount := 0;
          IF ORPS.sym = ORS.lbrace THEN
            ORS.Get(ORPS.sym);
            WHILE (ORPS.sym # ORS.rbrace) & (ORPS.sym # ORS.eot) DO
              ORPS.expression(x);
              IF x.mode = ORB.Const THEN cval := x.a
              ELSE ORS.Mark("not a constant"); cval := 0 END;
              IF tp.size = 1 THEN ORG.PutByte(cval)
              ELSIF tp.size = 2 THEN
                ORG.PutByte(cval); ORG.PutByte(cval DIV 100H)
              ELSE ORS.Mark("element type must be 1 or 2 bytes") END;
              INC(ccount);
              IF ORPS.sym = ORS.comma THEN ORS.Get(ORPS.sym)
              ELSIF ORPS.sym # ORS.rbrace THEN ORS.Mark(", or } expected") END
            END;
            ORPS.Check(ORS.rbrace, "} expected")
          ELSE ORS.Mark("{ expected") END;
          NEW(arrtyp); arrtyp.form := ORB.Array; arrtyp.base := tp;
          arrtyp.len := ccount; arrtyp.size := ccount * tp.size;
          ORB.NewObj(obj, id, ORB.Const);
          obj.expo := expo; obj.val := cstart;
          obj.lev := ccount * tp.size; obj.type := arrtyp;
          IF expo THEN obj.exno := exno; INC(exno) END
        ELSE
          ORPS.expression(x);
          IF (x.type.form = ORB.String) & (x.b = 2) THEN ORG.StrToChar(x) END;
          ORB.NewObj(obj, id, ORB.Const);
          obj.expo := expo;
          IF x.mode = ORB.Const THEN
            obj.val := x.a; obj.lev := x.b; obj.type := x.type
          ELSE
            ORS.Mark("expression not constant"); obj.type := ORB.intType
          END
        END;
        ORPS.Check(ORS.semicolon, "; missing")
      END
    END;
    IF ORPS.sym = ORS.type THEN
      ORS.Get(ORPS.sym);
      WHILE ORPS.sym = ORS.ident DO
        ORS.CopyId(id);
        ORS.Get(ORPS.sym);
        ORPS.CheckExport(expo);
        IF ORPS.sym = ORS.eql THEN ORS.Get(ORPS.sym) ELSE ORS.Mark("=?") END;
        Type(tp);
        ORB.NewObj(obj, id, ORB.Typ);
        obj.type := tp; obj.expo := expo; obj.lev := ORPS.level;
        IF tp.typobj = NIL THEN tp.typobj := obj END;
        IF expo & (obj.type.form = ORB.Record) THEN
          obj.exno := exno; INC(exno)
        ELSE obj.exno := 0
        END;
        IF tp.form = ORB.Record THEN
          ptbase := pbsList;  (*check whether this is base of a pointer type*)
          WHILE ptbase # NIL DO
            IF obj.name = ptbase.name THEN ptbase.type.base := obj.type END;
            ptbase := ptbase.next
          END;
          IF ORPS.level = 0 THEN ORG.BuildTD(tp, dc) END
        END;
        ORPS.Check(ORS.semicolon, "; missing")
      END
    END;
    IF ORPS.sym = ORS.var THEN
      ORS.Get(ORPS.sym);
      WHILE ORPS.sym = ORS.ident DO
        IdentList(ORB.Var, first);
        Type(tp);
        obj := first;
        WHILE obj # NIL DO
          obj.type := tp; obj.lev := ORPS.level;
          IF ORPS.level > 0 THEN obj.val := 1 + parblksize + varsize
          ELSE obj.val := varsize
          END;
          varsize := varsize + obj.type.size;
          IF obj.expo THEN obj.exno := exno; INC(exno) END;
          obj := obj.next
        END;
        ORPS.Check(ORS.semicolon, "; missing")
      END
    END;
    (* 65C816 heritage: keep scalar locals within 8-bit stack offsets.
       Harmless for the LLVM backend (locals are allocas by name). *)
    IF (ORPS.level > 0) & (varsize > 0) THEN
      reorderOfs := 0;
      p := ORB.topScope.next;
      WHILE p # NIL DO
        IF (p.class = ORB.Var) & (p.lev = ORPS.level) & (p.val > parblksize) &
           (p.type.size <= 8) THEN
          p.val := 1 + parblksize + reorderOfs;
          reorderOfs := reorderOfs + p.type.size
        END;
        p := p.next
      END;
      p := ORB.topScope.next;
      WHILE p # NIL DO
        IF (p.class = ORB.Var) & (p.lev = ORPS.level) & (p.val > parblksize) &
           (p.type.size > 8) THEN
          p.val := 1 + parblksize + reorderOfs;
          reorderOfs := reorderOfs + p.type.size
        END;
        p := p.next
      END
    END;
    ptbase := pbsList;
    WHILE ptbase # NIL DO
      IF ptbase.type.base.form = ORB.Int THEN
        ORS.Mark("undefined pointer base of")
      END;
      ptbase := ptbase.next
    END;
    IF (ORPS.sym >= ORS.const) & (ORPS.sym <= ORS.var) THEN
      ORS.Mark("declaration in bad order")
    END
  END Declarations;

  PROCEDURE MakeMangled(VAR dst: ARRAY OF CHAR; a, b, c: ARRAY OF CHAR);
    VAR i, j: INTEGER;

    PROCEDURE app(VAR dst: ARRAY OF CHAR; VAR j: INTEGER; s: ARRAY OF CHAR);
      VAR i: INTEGER;
    BEGIN i := 0;
      WHILE (i < LEN(s)) & (j < LEN(dst) - 1) & (s[i] # 0X) DO
        dst[j] := s[i]; INC(i); INC(j)
      END;
      dst[j] := 0X
    END app;

  BEGIN
    j := 0; dst[0] := 0X;
    app(dst, j, a); app(dst, j, "__");
    app(dst, j, b); app(dst, j, "__");
    app(dst, j, c)
  END MakeMangled;

  (* Attach a parsed type-bound procedure to its record (DDR-001) and
     enforce the override rules (DDR-002). Slot indices are fixed once
     assigned: an extension taking a new slot freezes its ancestors'
     layouts (mfixed). *)
  PROCEDURE BindMethod(proc: ORB.Object; type, rec: ORB.Type;
                       rtypname: ARRAY OF CHAR; isOverride: BOOLEAN);
    VAR m, bm: ORB.Object;
      bt: ORB.Type;
  BEGIN
    m := rec.dsc;
    WHILE m # NIL DO
      IF m.name = proc.name THEN ORS.Mark("method name clashes with a field") END;
      m := m.next
    END;
    m := rec.meth;
    WHILE m # NIL DO
      IF m.name = proc.name THEN ORS.Mark("mult def") END;
      m := m.next
    END;
    (* nearest visible inherited method of the same name *)
    bm := NIL; bt := rec.base;
    WHILE (bt # NIL) & (bm = NIL) DO
      m := bt.meth;
      WHILE (m # NIL) & (bm = NIL) DO
        IF (m.name = proc.name) & (m.expo OR (bt.mno <= 0)) THEN bm := m END;
        m := m.next
      END;
      bt := bt.base
    END;
    IF bm # NIL THEN
      IF ~isOverride THEN ORS.Mark("hides an inherited method; add OVERRIDE") END;
      IF ~ORPS.MethodSigMatch(type, bm.type) THEN
        ORS.Mark("override signature differs from base method")
      END;
      proc.val := bm.val               (* reuse the base slot *)
    ELSE
      IF isOverride THEN ORS.Mark("no inherited method to override") END;
      IF rec.mfixed THEN
        ORS.Mark("declare base-type methods before extension methods")
      END;
      proc.val := ORB.TotalMeths(rec);  (* next free slot *)
      rec.nofmeth := proc.val + 1;
      bt := rec.base;
      WHILE bt # NIL DO bt.mfixed := TRUE; bt := bt.base END
    END;
    MakeMangled(proc.mname, modid, rtypname, proc.name);
    (* append — declaration order keeps vtable build deterministic *)
    proc.next := NIL;
    IF rec.meth = NIL THEN rec.meth := proc
    ELSE
      m := rec.meth;
      WHILE m.next # NIL DO m := m.next END;
      m.next := proc
    END
  END BindMethod;

  (* Attach an initialiser (DDR-003/004): statically bound named
     constructor — no vtable slot, no override relation. *)
  PROCEDURE BindInit(proc: ORB.Object; rec: ORB.Type; rtypname: ARRAY OF CHAR);
    VAR m: ORB.Object;
  BEGIN
    m := rec.dsc;
    WHILE m # NIL DO
      IF m.name = proc.name THEN ORS.Mark("initialiser name clashes with a field") END;
      m := m.next
    END;
    m := rec.meth;
    WHILE m # NIL DO
      IF m.name = proc.name THEN ORS.Mark("mult def") END;
      m := m.next
    END;
    proc.initf := TRUE;
    proc.val := -1;   (* statically bound: no vtable slot *)
    MakeMangled(proc.mname, modid, rtypname, proc.name);
    proc.next := NIL;
    IF rec.meth = NIL THEN rec.meth := proc
    ELSE
      m := rec.meth;
      WHILE m.next # NIL DO m := m.next END;
      m.next := proc
    END
  END BindInit;

  PROCEDURE ProcedureDecl;
    VAR proc, rp, tobj: ORB.Object;
      type: ORB.Type;
      procid: ORS.Ident;
      x: ORG.Item;
      locblksize, parblksize, L: LONGINT;
      intProc: BOOLEAN;
      (* type-bound procedure state (DDR-001..004/006/007) *)
      hasRcv, isOverride, isInit: BOOLEAN;
      rcvcl: INTEGER;
      rcvname, rtypname: ORS.Ident;
      rcvtyp, rec: ORB.Type;
      (* SUPER context of the enclosing body, restored on exit *)
      savedRcv: ORB.Object;
      savedRec: ORB.Type;
      savedIsInit, savedSuperInit: BOOLEAN;
  BEGIN (* ProcedureDecl *)
    intProc := FALSE;
    hasRcv := FALSE; isOverride := FALSE; isInit := FALSE;
    rcvcl := 0; rcvtyp := NIL; rec := NIL;
    rcvname[0] := 0X; rtypname[0] := 0X;
    ORS.Get(ORPS.sym);
    IF ORPS.sym = ORS.init THEN
      (* initialiser (DDR-003/004): allocates at the call site *)
      isInit := TRUE; ORS.Get(ORPS.sym)
    END;
    IF ORPS.sym = ORS.times THEN
      ORS.Get(ORPS.sym); intProc := TRUE
    END;
    IF ORPS.sym = ORS.lparen THEN
      (* receiver section: PROCEDURE (r: T) M ... (DDR-001/007) *)
      hasRcv := TRUE;
      ORS.Get(ORPS.sym);
      IF ORPS.sym = ORS.var THEN ORS.Get(ORPS.sym); rcvcl := ORB.Par
      ELSE rcvcl := ORB.Var
      END;
      IF ORPS.sym = ORS.ident THEN
        ORS.CopyId(rcvname); ORS.Get(ORPS.sym)
      ELSE ORS.Mark("receiver name expected")
      END;
      ORPS.Check(ORS.colon, "no :");
      IF ORPS.sym = ORS.ident THEN
        ORPS.qualident(tobj);
        IF tobj.class = ORB.Typ THEN
          rcvtyp := tobj.type;
          rtypname := tobj.name
        ELSE ORS.Mark("receiver type expected")
        END
      ELSE ORS.Mark("receiver type expected")
      END;
      ORPS.Check(ORS.rparen, "no )");
      IF rcvtyp # NIL THEN
        IF rcvcl = ORB.Var THEN
          (* value receiver: pointer to record (dynamic dispatch) *)
          IF (rcvtyp.form = ORB.Pointer) & (rcvtyp.base # NIL) &
             (rcvtyp.base.form = ORB.Record) THEN
            rec := rcvtyp.base
          ELSE ORS.Mark("receiver must be POINTER TO record (or VAR with a record type)")
          END
        ELSE
          (* VAR receiver: record (static dispatch) *)
          IF rcvtyp.form = ORB.Record THEN rec := rcvtyp
          ELSE ORS.Mark("VAR receiver must have record type")
          END
        END
      END;
      IF rec # NIL THEN
        IF rec.mno > 0 THEN
          ORS.Mark("cannot bind method to imported type"); rec := NIL
        ELSIF rec.typobj = NIL THEN
          ORS.Mark("receiver's record type must be named"); rec := NIL
        END
      END;
      IF ORPS.level # 0 THEN
        ORS.Mark("methods must be declared at module level"); rec := NIL
      END
    END;
    IF isInit THEN
      IF ~hasRcv THEN ORS.Mark("INIT requires a receiver")
      ELSIF rcvcl # ORB.Var THEN
        ORS.Mark("initialiser receiver must be a pointer, not VAR"); rec := NIL
      END
    END;
    IF ORPS.sym = ORS.ident THEN
      ORS.CopyId(procid);
      ORS.Get(ORPS.sym);
      IF hasRcv THEN
        (* type-bound: named in the record's method list only *)
        NEW(proc); proc.name := procid; proc.class := ORB.Meth
      ELSE
        ORB.NewObj(proc, procid, ORB.Const)
      END;
      IF intProc THEN parblksize := 12 ELSE parblksize := 0 END;
      NEW(type);
      type.form := ORB.Proc; type.size := 4;
      proc.type := type; proc.val := -1; proc.lev := ORPS.level;
      ORPS.CheckExport(proc.expo);
      (* exported methods also get an export-entry number so importers can
         reference them by mno:exno (816 cross-module dispatch) *)
      IF proc.expo THEN proc.exno := exno; INC(exno) END;
      ORB.OpenScope;
      INC(ORPS.level);
      type.base := ORB.noType;
      (* SUPER context: this body's receiver — cleared for plain
         procedures, including ones nested inside a method *)
      savedRcv := ORPS.CurRcv; savedRec := ORPS.CurRcvRec;
      savedIsInit := ORPS.CurIsInit; savedSuperInit := ORPS.SuperInitCalled;
      ORPS.CurRcv := NIL; ORPS.CurRcvRec := NIL;
      ORPS.CurIsInit := FALSE; ORPS.SuperInitCalled := FALSE;
      IF hasRcv THEN
        (* the receiver is the hidden first parameter *)
        type.mthd := TRUE;
        ORB.NewObj(rp, rcvname, rcvcl);
        rp.type := rcvtyp; rp.lev := ORPS.level; rp.rdo := FALSE; rp.val := 1;
        IF rcvcl = ORB.Par THEN parblksize := parblksize + 2 * ORG.PtrSize
        ELSE parblksize := parblksize + ORG.PtrSize
        END;
        IF rec # NIL THEN
          ORPS.CurRcv := rp; ORPS.CurRcvRec := rec; ORPS.CurIsInit := isInit
        END
      END;
      ProcedureType(type, parblksize);
      IF hasRcv THEN INC(type.nofpar) END;   (* count the receiver *)
      IF isInit THEN
        (* the constructed instance is the call's value, typed as the
           receiver type (D7.6) — the heading may not name a result *)
        IF type.base.form # ORB.NoTyp THEN
          ORS.Mark("initialiser has no result type")
        END;
        IF rec # NIL THEN type.base := rcvtyp END
      END;
      IF ORPS.sym = ORS.override THEN
        ORS.Get(ORPS.sym);
        IF ~hasRcv THEN ORS.Mark("OVERRIDE requires a receiver") END;
        IF isInit THEN ORS.Mark("INIT and OVERRIDE are mutually exclusive") END;
        isOverride := TRUE
      END;
      ORPS.Check(ORS.semicolon, "no ;");
      (* params fully in scope; register the method before the body *)
      type.dsc := ORB.topScope.next;
      IF rec # NIL THEN
        IF isInit THEN BindInit(proc, rec, rtypname)
        ELSE BindMethod(proc, type, rec, rtypname, isOverride)
        END
      END;
      locblksize := 0;
      Declarations(locblksize, parblksize);
      IF proc.class # ORB.Meth THEN
        proc.val := ORG.Here()   (* methods keep their vtable slot in val *)
      END;
      proc.type.dsc := ORB.topScope.next;
      IF ORPS.sym = ORS.procedure THEN
        L := 0;
        ORG.FJump(L);
        REPEAT
          ProcedureDecl;
          ORPS.Check(ORS.semicolon, "no ;")
        UNTIL ORPS.sym # ORS.procedure;
        ORG.FixOne(L);
        IF proc.class # ORB.Meth THEN proc.val := ORG.Here() END;
        proc.type.dsc := ORB.topScope.next
      END;
      type.size := locblksize;
      ORG.Enter(proc, ORB.topScope.next, parblksize, locblksize, intProc);
      IF ORPS.sym = ORS.begin THEN
        ORS.Get(ORPS.sym);
        ORPS.StatSequence
      END;
      IF isInit THEN
        (* the constructed instance is returned implicitly *)
        IF ORPS.sym = ORS.return THEN
          ORS.Mark("initialiser has no RETURN");
          ORS.Get(ORPS.sym);
          ORPS.expression(x)   (* recover past the expression *)
        END;
        IF (type.base.form # ORB.NoTyp) & (type.dsc # NIL) THEN
          ORG.MakeItem(x, type.dsc, ORPS.level)   (* the receiver *)
        ELSE ORG.MakeConstItem(x, ORB.noType, 0)
        END
      ELSIF ORPS.sym = ORS.return THEN
        ORS.Get(ORPS.sym);
        IF type.base.form # ORB.NoTyp THEN
          ORPS.expression(x);
          (* mixed integer widths permitted, consistent with assignment *)
          IF ~ORPS.CompTypes(type.base, x.type, FALSE) &
             ~((type.base.form = ORB.Int) & (x.type.form = ORB.Int)) THEN
            ORS.Mark("wrong result type")
          ELSIF (type.base.form = ORB.Intfc) & (x.type.form # ORB.Intfc) THEN
            ORG.PtrToIface(x, type.base)
          END
        ELSE x.type := ORB.noType
        END
      ELSIF type.base.form # ORB.NoTyp THEN
        ORS.Mark("function without result");
        type.base := ORB.noType
      END;
      ORG.Return(proc, x);
      ORB.CloseScope;
      DEC(ORPS.level);
      ORPS.Check(ORS.end, "no END");
      IF ORPS.sym = ORS.ident THEN
        IF ORS.id # procid THEN ORS.Mark("no match") END;
        ORS.Get(ORPS.sym)
      ELSE ORS.Mark("no proc id")
      END;
      (* DDR-003: a derived initialiser must chain to a base initialiser
         whenever one is visible *)
      IF isInit & (rec # NIL) & (rec.base # NIL) &
         ORB.HasVisibleInits(rec.base) & ~ORPS.SuperInitCalled THEN
        ORS.Mark("initialiser must call a base initialiser via SUPER")
      END;
      ORPS.CurRcv := savedRcv; ORPS.CurRcvRec := savedRec;
      ORPS.CurIsInit := savedIsInit; ORPS.SuperInitCalled := savedSuperInit
    ELSE ORS.Mark("proc id expected")
    END
  END ProcedureDecl;

  (* Conformance signature check (DDR-008 §5.2): record method vs
     interface member — receivers excluded. *)
  PROCEDURE IfaceSigMatch(mt, it: ORB.Type): BOOLEAN;
    VAR p0, p1: ORB.Object; n: INTEGER; res: BOOLEAN;
  BEGIN res := TRUE;
    IF (mt.base # it.base) OR (mt.nofpar # it.nofpar) THEN res := FALSE
    ELSE
      p0 := mt.dsc; p1 := it.dsc;
      IF (p0 = NIL) OR (p1 = NIL) THEN res := FALSE
      ELSE
        p0 := p0.next; p1 := p1.next; n := mt.nofpar - 1;
        WHILE (n > 0) & res DO
          IF (p0 # NIL) & (p1 # NIL) &
             (p0.class = p1.class) & (p0.rdo = p1.rdo) &
             ((p0.type = p1.type) OR
              ((p0.type.form = ORB.Array) & (p1.type.form = ORB.Array) &
               (p0.type.len = p1.type.len) & (p0.type.base = p1.type.base)) OR
              ((p0.type.form = ORB.Proc) & (p1.type.form = ORB.Proc) &
               ORPS.EqualSignatures(p0.type, p1.type))) THEN
            p0 := p0.next; p1 := p1.next; DEC(n)
          ELSE res := FALSE
          END
        END
      END
    END;
    RETURN res
  END IfaceSigMatch;

  (* DDR-008 §5.2: for every member of each declared interface's
     flattened set, the record must have a matching type-bound
     procedure. Run once per module, after all methods are declared. *)
  PROCEDURE CheckConformance;
    VAR obj, m, rm: ORB.Object;
      im: ORB.Impl;
  BEGIN
    obj := ORB.topScope.next;
    WHILE obj # NIL DO
      IF (obj.class = ORB.Typ) & (obj.type # NIL) &
         (obj.type.form = ORB.Record) & (obj.type.mno <= 0) THEN
        im := obj.type.impl;
        WHILE im # NIL DO
          m := im.intfc.meth;
          WHILE m # NIL DO
            rm := ORB.FindMeth(obj.type, m.name);
            IF rm = NIL THEN
              ORH.WriteString("  "); ORH.WriteString(obj.name);
              ORH.WriteString(" does not implement ");
              IF im.intfc.typobj # NIL THEN
                ORH.WriteString(im.intfc.typobj.name); ORH.WriteString(".")
              END;
              ORH.WriteString(m.name); ORH.Ln();
              ORS.Mark("interface not implemented")
            ELSIF ~IfaceSigMatch(rm.type, m.type) THEN
              ORH.WriteString("  "); ORH.WriteString(obj.name);
              ORH.WriteString("."); ORH.WriteString(m.name);
              ORH.WriteString(": signature differs from interface"); ORH.Ln();
              ORS.Mark("interface signature mismatch")
            END;
            m := m.next
          END;
          im := im.next
        END
      END;
      obj := obj.next
    END
  END CheckConformance;

  PROCEDURE Import;
    VAR impid, impid1: ORS.Ident;
  BEGIN
    IF ORPS.sym = ORS.ident THEN
      ORS.CopyId(impid);
      ORS.Get(ORPS.sym);
      IF ORPS.sym = ORS.becomes THEN
        ORS.Get(ORPS.sym);
        IF ORPS.sym = ORS.ident THEN
          ORS.CopyId(impid1); ORS.Get(ORPS.sym)
        ELSE ORS.Mark("id expected"); impid1 := impid
        END
      ELSE impid1 := impid
      END;
      ORB.Import(impid, impid1)
    ELSE ORS.Mark("id expected")
    END
  END Import;

  PROCEDURE Module;
    VAR key: LONGINT; large: BOOLEAN;
  BEGIN
    key := 0; large := FALSE;
    ORH.WriteString("  compiling ");
    ORS.Get(ORPS.sym);
    IF ORPS.sym = ORS.module THEN
      ORS.Get(ORPS.sym);
      dc := 0;
      ORB.OpenScope;
      IF ORPS.sym = ORS.ident THEN
        ORS.CopyId(modid);
        ORS.Get(ORPS.sym);
        ORH.WriteString(modid)
      ELSE ORS.Mark("identifier expected")
      END;
      ORB.SetModule(modid);
      IF ORPS.sym = ORS.large THEN large := TRUE; ORS.Get(ORPS.sym) END;  (* MODULE m LARGE; *)
      (* MODULE m FRIENDS a, b; the modules that may assign to m's
         variables. FRIENDS is not a reserved word *)
      IF (ORPS.sym = ORS.ident) & (ORS.id = "FRIENDS") THEN
        REPEAT ORS.Get(ORPS.sym);
          IF ORPS.sym = ORS.ident THEN ORB.AddFriend(ORS.id); ORS.Get(ORPS.sym)
          ELSE ORS.Mark("identifier expected")
          END
        UNTIL ORPS.sym # ORS.comma
      END;
      ORPS.Check(ORS.semicolon, "no ;");
      ORPS.level := 0; exno := 1;
      IF ORPS.sym = ORS.import THEN
        ORS.Get(ORPS.sym);
        Import;
        WHILE ORPS.sym = ORS.comma DO
          ORS.Get(ORPS.sym);
          Import
        END;
        ORPS.Check(ORS.semicolon, "; missing")
      END;
      ORG.Open(modid, ORPS.VERSION, large);
      Declarations(dc, 0);
      ORG.SetDataSize(dc);
      WHILE ORPS.sym = ORS.procedure DO
        ProcedureDecl;
        ORPS.Check(ORS.semicolon, "no ;")
      END;
      CheckConformance;   (* DDR-008: all methods are declared by now *)
      ORG.Header;
      IF ORPS.sym = ORS.begin THEN
        ORS.Get(ORPS.sym);
        ORPS.StatSequence
      END;
      ORPS.Check(ORS.end, "no END");
      IF ORPS.sym = ORS.ident THEN
        IF ORS.id # modid THEN ORS.Mark("no match") END;
        ORS.Get(ORPS.sym)
      ELSE ORS.Mark("identifier missing")
      END;
      IF ORPS.sym # ORS.period THEN ORS.Mark("period missing")
      ELSE
        ORS.Get(ORPS.sym);
        IF ORPS.sym # ORS.eot THEN ORS.Mark("garbage after module") END
      END;
      IF ORS.errcnt = 0 THEN
        ORB.SetVarSize(dc);
        ORG.FinalizeTDs;   (* assign deferred record T.len before the .smb is written *)
        ORB.Export(modid, newSF, key);
        IF newSF THEN ORH.WriteString(" new symbol file") END
      END;
      IF ORS.errcnt = 0 THEN
        ORG.Close(modid, key, exno);
        ORH.WriteString("  key "); ORH.WriteInt(key)
      ELSE
        ORH.Ln();
        ORH.WriteString("compilation FAILED")
      END;
      ORH.Ln();
      ORB.CloseScope;
      pbsList := NIL
    ELSE ORS.Mark("must start with MODULE")
    END
  END Module;

  PROCEDURE Compile*(filename: ARRAY OF CHAR; forceNewSF: BOOLEAN);
  BEGIN
    ORB.Init; ORG.Init;   (* afresh: a compiler that stays loaded compiles again (OS16's oc) *)
    ORB.SetSourceDirectory(filename);
    newSF := forceNewSF;
    ORH.WriteString("Compiling ");
    ORH.WriteString(filename); ORH.Ln();
    IF ORS.Open(filename) THEN
      Module
    ELSE
      ORH.WriteString("Error: cannot open ");
      ORH.WriteString(filename); ORH.Ln();
      ORS.CountError
    END
  END Compile;

  PROCEDURE ErrCnt*(): INTEGER;
  BEGIN RETURN ORS.errcnt
  END ErrCnt;

BEGIN
  ORB.Initialize(ORG.IntSize, ORG.LongSize, ORG.RealSize,
                 ORG.SetSize, ORG.NilSize, ORG.StrSize,
                 ORG.PtrSize, ORG.IntfcSize);
  ORG.InitSystem;   (* backend registers its own SYSTEM pseudo-module *)
  ORB.Init;
  ORG.Init;
  NEW(ORPS.dummy); ORPS.dummy.class := ORB.Var; ORPS.dummy.type := ORB.intType;
  ORPS.expression := ORPS.expression0;
  Type := Type0;
  FormalType := FormalType0;
  ORPS.CurRcv := NIL; ORPS.CurRcvRec := NIL;
  ORPS.CurIsInit := FALSE; ORPS.SuperInitCalled := FALSE
END ORP.
