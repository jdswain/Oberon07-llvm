MODULE ORPS FRIENDS ORP; (* Oberon parser, its expressions and statements:
   selectors, factors, terms, expressions, the standard procedures and
   functions, statement sequences. The first of the parser's two modules
   (ORPS, ORP), a 65C816 module's code being a bank; ORP, its friend,
   assigns to the parser's state here (sym, level, ...). *)

  IMPORT ORS, ORB, ORG;

  CONST VERSION* = 4;   (* .816 v2: deferred type-descriptor layout (after vars+strings);
                          v3: method table slots of address and bank;
                          v4: the variables reached in their bank ([SB],Y): the data in any bank *)
    WordSize* = ORG.WordSize;   (* target word size, from the backend *)

  TYPE
    ExprProc = PROCEDURE (VAR x: ORG.Item);

  VAR
    sym*: INTEGER;   (*last symbol read*)
    level*: INTEGER;
    expression*: ExprProc;   (*to avoid forward references*)
    dummy*: ORB.Object;
    CurRcv*: ORB.Object;
    CurRcvRec*: ORB.Type;
    CurIsInit*, SuperInitCalled*: BOOLEAN;

  PROCEDURE Check*(s: INTEGER; msg: ARRAY OF CHAR);
  BEGIN
    IF sym = s THEN ORS.Get(sym) ELSE ORS.Mark(msg) END
  END Check;

  PROCEDURE qualident*(VAR obj: ORB.Object);
  BEGIN obj := ORB.thisObj(); ORS.Get(sym);
    IF obj = NIL THEN ORS.Mark("undef"); obj := dummy END;
    IF (sym = ORS.period) & (obj.class = ORB.Mod) THEN
      ORS.Get(sym);
      IF sym = ORS.ident THEN
        obj := ORB.thisimport(obj); ORS.Get(sym);
        IF obj = NIL THEN ORS.Mark("undef"); obj := dummy END
      ELSE ORS.Mark("identifier expected"); obj := dummy
      END
    END
  END qualident;

  PROCEDURE CheckBool(VAR x: ORG.Item);
  BEGIN
    IF x.type.form # ORB.Bool THEN ORS.Mark("not Boolean"); x.type := ORB.boolType END
  END CheckBool;

  PROCEDURE CheckInt(VAR x: ORG.Item);
  BEGIN
    IF x.type.form # ORB.Int THEN ORS.Mark("not Integer"); x.type := ORB.intType END
  END CheckInt;

  PROCEDURE CheckReal(VAR x: ORG.Item);
  BEGIN
    IF x.type.form # ORB.Real THEN ORS.Mark("not Real"); x.type := ORB.realType END
  END CheckReal;

  PROCEDURE CheckSet(VAR x: ORG.Item);
  BEGIN
    IF x.type.form # ORB.Set THEN ORS.Mark("not Set"); x.type := ORB.setType END
  END CheckSet;

  PROCEDURE CheckSetVal(VAR x: ORG.Item);
  BEGIN
    IF x.type.form # ORB.Int THEN ORS.Mark("not Int"); x.type := ORB.setType
    ELSIF x.mode = ORB.Const THEN
      IF (x.a < 0) OR (x.a >= ORG.SetMax) THEN ORS.Mark("invalid set") END
    END
  END CheckSetVal;

  PROCEDURE CheckConst(VAR x: ORG.Item);
  BEGIN
    IF x.mode # ORB.Const THEN ORS.Mark("not a constant"); x.mode := ORB.Const END
  END CheckConst;

  PROCEDURE CheckReadOnly(VAR x: ORG.Item);
  BEGIN
    IF x.rdo THEN ORS.Mark("read-only") END
  END CheckReadOnly;

  PROCEDURE CheckExport*(VAR expo: BOOLEAN);
  BEGIN
    IF sym = ORS.times THEN
      expo := TRUE; ORS.Get(sym);
      IF level # 0 THEN ORS.Mark("remove asterisk") END
    ELSE expo := FALSE
    END
  END CheckExport;

  PROCEDURE IsExtension(t0, t1: ORB.Type): BOOLEAN;
  BEGIN
    RETURN (t0 = t1) OR ((t1 # NIL) & IsExtension(t0, t1.base))
  END IsExtension;

  (* expressions *)

  PROCEDURE TypeTest(VAR x: ORG.Item; T: ORB.Type; guard: BOOLEAN);
    VAR xt: ORB.Type;
  BEGIN xt := x.type;
    IF (xt.form = ORB.Intfc) & (T.form = ORB.Pointer) &
       (T.base # NIL) & (T.base.form = ORB.Record) THEN
      (* narrowing an interface reference (DDR-008 §5.4): ordinary tag test,
         as of a pointer: against the record's descriptor *)
      ORG.TypeTest(x, T.base, FALSE, guard);
      IF guard THEN x.type := T ELSE x.type := ORB.boolType END
    ELSIF (T.form = xt.form) &
       ((T.form = ORB.Pointer) OR ((T.form = ORB.Record) & (x.mode = ORB.Par))) THEN
      WHILE (xt # T) & (xt # NIL) DO xt := xt.base END;
      IF xt # T THEN
        xt := x.type;
        IF xt.form = ORB.Pointer THEN
          IF IsExtension(xt.base, T.base) THEN
            ORG.TypeTest(x, T.base, FALSE, guard); x.type := T
          ELSE ORS.Mark("not an extension")
          END
        ELSIF (xt.form = ORB.Record) & (x.mode = ORB.Par) THEN
          IF IsExtension(xt, T) THEN
            ORG.TypeTest(x, T, TRUE, guard); x.type := T
          ELSE ORS.Mark("not an extension")
          END
        ELSE ORS.Mark("incompatible types")
        END
      ELSIF ~guard THEN ORG.TypeTest(x, NIL, FALSE, FALSE)
      END
    ELSE ORS.Mark("type mismatch")
    END;
    IF ~guard THEN x.type := ORB.boolType END
  END TypeTest;

  PROCEDURE EqualSignatures*(t0, t1: ORB.Type): BOOLEAN;
    VAR p0, p1: ORB.Object; com: BOOLEAN;
  BEGIN com := TRUE;
    IF (t0.base = t1.base) & (t0.nofpar = t1.nofpar) & (t0.mthd = t1.mthd) THEN
      p0 := t0.dsc; p1 := t1.dsc;
      WHILE p0 # NIL DO
        IF (p0.class = p1.class) & (p0.rdo = p1.rdo) &
           ((p0.type = p1.type) OR
            ((p0.type.form = ORB.Array) & (p1.type.form = ORB.Array) &
             (p0.type.len = p1.type.len) & (p0.type.base = p1.type.base)) OR
            ((p0.type.form = ORB.Proc) & (p1.type.form = ORB.Proc) &
             EqualSignatures(p0.type, p1.type))) THEN
          p0 := p0.next; p1 := p1.next
        ELSE p0 := NIL; com := FALSE
        END
      END
    ELSE com := FALSE
    END;
    RETURN com
  END EqualSignatures;

  (* Override check (DDR-002): identical signatures, receiver excluded —
     the receiver types necessarily differ; only its mode must agree. *)
  PROCEDURE MethodSigMatch*(t0, t1: ORB.Type): BOOLEAN;
    VAR p0, p1: ORB.Object; n: INTEGER; res: BOOLEAN;
  BEGIN res := TRUE;
    IF (t0.base # t1.base) OR (t0.nofpar # t1.nofpar) THEN res := FALSE
    ELSE
      p0 := t0.dsc; p1 := t1.dsc;
      IF (p0 = NIL) OR (p1 = NIL) OR (p0.class # p1.class) THEN res := FALSE
      ELSE
        p0 := p0.next; p1 := p1.next; n := t0.nofpar - 1;
        WHILE (n > 0) & res DO
          IF (p0 # NIL) & (p1 # NIL) &
             (p0.class = p1.class) & (p0.rdo = p1.rdo) &
             ((p0.type = p1.type) OR
              ((p0.type.form = ORB.Array) & (p1.type.form = ORB.Array) &
               (p0.type.len = p1.type.len) & (p0.type.base = p1.type.base)) OR
              ((p0.type.form = ORB.Proc) & (p1.type.form = ORB.Proc) &
               EqualSignatures(p0.type, p1.type))) THEN
            p0 := p0.next; p1 := p1.next; DEC(n)
          ELSE res := FALSE
          END
        END
      END
    END;
    RETURN res
  END MethodSigMatch;

  PROCEDURE CompTypes*(t0, t1: ORB.Type; varpar: BOOLEAN): BOOLEAN;
  BEGIN
    RETURN (t0 = t1) OR
      ((t0.form = ORB.Array) & (t1.form = ORB.Array) &
       (t0.base = t1.base) & (t0.len = t1.len)) OR
      ((t0.form = ORB.Record) & (t1.form = ORB.Record) & IsExtension(t0, t1)) OR
      (~varpar &
       (((t0.form = ORB.Pointer) & (t1.form = ORB.Pointer) &
         IsExtension(t0.base, t1.base)) OR
        ((t0.form = ORB.Proc) & (t1.form = ORB.Proc) &
         EqualSignatures(t0, t1)) OR
        (* upcast to an interface: statically safe when conformance is
           declared on the record or an ancestor (DDR-008 §5.4) *)
        ((t0.form = ORB.Intfc) & (t1.form = ORB.Pointer) &
         (t1.base # NIL) & (t1.base.form = ORB.Record) &
         ORB.Conforms(t1.base, t0)) OR
        (((t0.form = ORB.Pointer) OR (t0.form = ORB.Proc) OR
          (t0.form = ORB.Intfc)) & (t1.form = ORB.NilTyp))))
  END CompTypes;

  PROCEDURE Parameter(par: ORB.Object);
    VAR x: ORG.Item; varpar: BOOLEAN;
  BEGIN
    expression(x);
    IF par # NIL THEN
      varpar := par.class = ORB.Par;
      IF CompTypes(par.type, x.type, varpar) THEN
        IF ~varpar THEN
          IF (par.type.form = ORB.Intfc) & (x.type.form # ORB.Intfc) THEN
            ORG.PtrToIface(x, par.type)   (* pointer or NIL actual *)
          END;
          ORG.ValueParam(x, par.type)
        ELSE
          IF ~par.rdo THEN CheckReadOnly(x) END;
          ORG.VarParam(x, par.type)
        END
      ELSIF (x.type.form = ORB.Array) & (par.type.form = ORB.Array) &
            (x.type.base = par.type.base) & (par.type.len < 0) THEN
        IF ~par.rdo THEN CheckReadOnly(x) END;
        ORG.OpenArrayParam(x)
      ELSIF (x.type.form = ORB.String) & (par.type.form = ORB.Array) &
            (par.type.base.form = ORB.Char) & (par.type.len < 0) THEN
        ORG.StringParam(x)
      ELSIF ~varpar & (par.type.form = ORB.Int) & (x.type.form = ORB.Int) THEN
        ORG.ValueParam(x, par.type)  (* BYTE *)
      ELSIF (x.type.form = ORB.String) & (x.b = 2) &
            (par.class = ORB.Var) & (par.type.form = ORB.Char) THEN
        ORG.StrToChar(x); ORG.ValueParam(x, par.type)
      ELSIF (par.type.form = ORB.Array) & (par.type.base = ORB.byteType) &
            (par.type.len >= 0) & (par.type.size = x.type.size) THEN
        ORG.VarParam(x, par.type)
      ELSE ORS.Mark("incompatible parameters")
      END
    END
  END Parameter;

  PROCEDURE ParamList(VAR x: ORG.Item);
    VAR n, nexplicit: INTEGER; par: ORB.Object;
  BEGIN n := 0;
    par := x.type.dsc; nexplicit := x.type.nofpar;
    (* type-bound call: the receiver is param 0 but never written at the
       call site — ORG.PrepCall already pushed it from the designator *)
    IF x.type.mthd & (par # NIL) THEN par := par.next; DEC(nexplicit) END;
    IF sym # ORS.rparen THEN
      Parameter(par); n := 1;
      WHILE sym <= ORS.comma DO
        Check(ORS.comma, "comma?");
        IF par # NIL THEN par := par.next END;
        INC(n);
        Parameter(par)
      END;
      Check(ORS.rparen, ") missing")
    ELSE ORS.Get(sym)
    END;
    IF n < nexplicit THEN ORS.Mark("too few params")
    ELSIF n > nexplicit THEN ORS.Mark("too many params")
    END
  END ParamList;

  (* T.Name(args) — named constructor call (DDR-004/005). Allocates a
     fresh instance of the qualifier's record type, calls the init body
     statically, and yields the instance typed as the QUALIFIER (D7.6).
     On entry x is the type designator; ORS.id holds the member name. *)
  PROCEDURE ConstructorCall(VAR x: ORG.Item);
    VAR ptrtyp: ORB.Type;
      ini: ORB.Object;
      rx: LONGINT;
  BEGIN
    ptrtyp := x.type;
    IF (ptrtyp = NIL) OR (ptrtyp.form # ORB.Pointer) OR
       (ptrtyp.base = NIL) OR (ptrtyp.base.form # ORB.Record) THEN
      ORS.Mark("only pointer-to-record types can be qualified");
      ORS.Get(sym)
    ELSE
      ini := ORB.thisinit(ptrtyp.base);
      IF ini = NIL THEN
        IF ORB.thismethod(ptrtyp.base) # NIL THEN
          ORS.Mark("methods cannot be type-qualified")
        ELSE ORS.Mark("no such initialiser")
        END;
        ORS.Get(sym)
      ELSE
        ORS.Get(sym);
        ORG.InitItem(x, ini, ptrtyp.base);
        IF sym = ORS.lparen THEN
          ORS.Get(sym);
          ORG.PrepCall(x, rx);
          ParamList(x);
          ORG.Call(x, rx)
        ELSE
          ORS.Mark("no (");
          ORG.PrepCall(x, rx);
          ORG.Call(x, rx)
        END;
        x.type := ptrtyp; x.rdo := FALSE
      END
    END
  END ConstructorCall;

  (* SUPER.Name — force static binding in the receiver type's IMMEDIATE
     base (DDR-006). Inside an initialiser body the base's initialisers
     are searched first; base methods are reachable from both kinds. *)
  PROCEDURE SuperCall(VAR x: ORG.Item): ORB.Object;
    VAR m: ORB.Object; base: ORB.Type;
  BEGIN
    m := NIL;
    ORG.MakeConstItem(x, ORB.intType, 0);   (* sane item for recovery *)
    ORS.Get(sym);
    Check(ORS.period, "no .");
    IF sym # ORS.ident THEN ORS.Mark("ident?")
    ELSIF (CurRcv = NIL) OR (CurRcvRec = NIL) THEN
      ORS.Mark("SUPER only inside a type-bound procedure"); ORS.Get(sym)
    ELSE
      base := CurRcvRec.base;
      IF base = NIL THEN
        ORS.Mark("receiver type has no base type"); ORS.Get(sym)
      ELSE
        IF CurIsInit THEN m := ORB.thisinit(base) END;
        IF m = NIL THEN m := ORB.thismethod(base) END;
        ORS.Get(sym);
        IF m = NIL THEN ORS.Mark("undef in base type")
        ELSE
          IF m.initf THEN SuperInitCalled := TRUE END;
          (* receiver argument: the record's address *)
          ORG.MakeItem(x, CurRcv, level);
          IF CurRcv.type.form = ORB.Pointer THEN
            ORG.DeRef(x); x.type := CurRcv.type.base
          END;
          ORG.MethodItem(x, m, TRUE);   (* SUPER is a binding construct *)
          x.type := m.type; x.rdo := FALSE
        END
      END
    END;
    RETURN m
  END SuperCall;

  PROCEDURE selector(VAR x: ORG.Item);
    VAR y: ORG.Item; obj: ORB.Object;
      wasPtr, done: BOOLEAN;
  BEGIN
    WHILE (sym = ORS.lbrak) OR (sym = ORS.period) OR (sym = ORS.arrow) OR
          ((sym = ORS.lparen) &
           ((x.type.form = ORB.Record) OR (x.type.form = ORB.Pointer) OR
            (x.type.form = ORB.Intfc))) DO
      IF sym = ORS.lbrak THEN
        REPEAT
          ORS.Get(sym); expression(y);
          IF x.type.form = ORB.Array THEN
            CheckInt(y); ORG.Index(x, y); x.type := x.type.base
          ELSE ORS.Mark("not an array")
          END
        UNTIL sym # ORS.comma;
        Check(ORS.rbrak, "no ]")
      ELSIF sym = ORS.period THEN
        ORS.Get(sym);
        IF sym = ORS.ident THEN
          done := FALSE;
          wasPtr := FALSE;
          IF x.mode = ORB.Typ THEN
            (* type-qualified member: constructor call (DDR-004/005) *)
            ConstructorCall(x); done := TRUE
          END;
          IF ~done & (x.type.form = ORB.Intfc) THEN
            (* interface dispatch (DDR-008 §5.4) *)
            obj := x.type.meth;
            WHILE (obj # NIL) & (obj.name # ORS.id) DO obj := obj.next END;
            ORS.Get(sym);
            IF obj # NIL THEN
              ORG.IfaceMethodItem(x, obj);
              x.type := obj.type; x.rdo := FALSE
            ELSE ORS.Mark("undef")
            END;
            done := TRUE
          END;
          IF ~done THEN
            IF x.type.form = ORB.Pointer THEN
              ORG.DeRef(x); x.type := x.type.base; wasPtr := TRUE;
              x.rdo := FALSE   (* the record pointed to, not the pointer variable *)
            END;
            IF x.type.form = ORB.Record THEN
              obj := ORB.thisfield(x.type);
              IF obj = NIL THEN obj := ORB.thismethod(x.type) END;
              ORS.Get(sym);
              IF obj # NIL THEN
                IF obj.class = ORB.Meth THEN
                  (* type-bound call (DDR-001): pointer receivers need a
                     pointer designator; VAR-record receivers accept both;
                     dispatch is dynamic through a pointer designator *)
                  IF (obj.type.dsc # NIL) & (obj.type.dsc.class = ORB.Var) & ~wasPtr THEN
                    ORS.Mark("method requires a pointer receiver")
                  END;
                  IF (obj.type.dsc # NIL) & (obj.type.dsc.class = ORB.Par) & ~wasPtr & x.rdo THEN
                    ORS.Mark("read-only receiver")
                  END;
                  ORG.MethodItem(x, obj, ~wasPtr);
                  x.type := obj.type; x.rdo := FALSE
                ELSE
                  ORG.Field(x, obj); x.type := obj.type
                END
              ELSE ORS.Mark("undef")
              END
            ELSE ORS.Mark("not a record")
            END
          END
        ELSE ORS.Mark("ident?")
        END
      ELSIF sym = ORS.arrow THEN
        ORS.Get(sym);
        IF x.type.form = ORB.Pointer THEN
          ORG.DeRef(x); x.type := x.type.base;
          x.rdo := FALSE   (* the record pointed to, not the pointer variable *)
        ELSE ORS.Mark("not a pointer")
        END
      ELSIF (sym = ORS.lparen) &
            ((x.type.form = ORB.Record) OR (x.type.form = ORB.Pointer) OR
             (x.type.form = ORB.Intfc)) THEN
        ORS.Get(sym);
        IF sym = ORS.ident THEN
          qualident(obj);
          IF obj.class = ORB.Typ THEN TypeTest(x, obj.type, TRUE)
          ELSE ORS.Mark("guard type expected")
          END
        ELSE ORS.Mark("not an identifier")
        END;
        Check(ORS.rparen, " ) missing")
      END
    END
  END selector;

  PROCEDURE StandFunc(VAR x: ORG.Item; fct: LONGINT; restyp: ORB.Type);
    VAR y: ORG.Item; n, npar: LONGINT;
  BEGIN
    Check(ORS.lparen, "no (");
    npar := fct MOD 10; fct := fct DIV 10;
    expression(x); n := 1;
    WHILE sym = ORS.comma DO
      ORS.Get(sym); expression(y); INC(n)
    END;
    Check(ORS.rparen, "no )");
    IF n = npar THEN
      IF fct = 0 THEN  (* ABS *)
        IF (x.type.form = ORB.Int) OR (x.type.form = ORB.Real) THEN
          ORG.Abs(x); restyp := x.type
        ELSE ORS.Mark("bad type")
        END
      ELSIF fct = 1 THEN CheckInt(x); ORG.Odd(x)       (* ODD *)
      ELSIF fct = 2 THEN CheckReal(x); ORG.Floor(x)    (* FLOOR *)
      ELSIF fct = 3 THEN CheckInt(x); ORG.Float(x)     (* FLT *)
      ELSIF fct = 4 THEN  (* ORD *)
        IF x.type.form <= ORB.Proc THEN ORG.Ord(x)
        ELSIF (x.type.form = ORB.String) & (x.b = 2) THEN ORG.StrToChar(x)
        ELSE ORS.Mark("bad type")
        END
      ELSIF fct = 5 THEN CheckInt(x); ORG.Chr(x)       (* CHR *)
      ELSIF fct = 6 THEN  (* LEN *)
        IF x.type.form = ORB.Array THEN ORG.Len(x)
        ELSE ORS.Mark("not an array")
        END
      ELSIF (fct >= 7) & (fct <= 9) THEN  (* AND, EOR, ORA *)
        CheckInt(y);
        IF (x.type.form = ORB.Int) OR (x.type.form = ORB.Set) THEN
          ORG.Bitwise(fct - 7, x, y); restyp := x.type
        ELSE ORS.Mark("bad type")
        END
      ELSIF (fct >= 10) & (fct <= 12) THEN  (* ASL, LSR, ROL *)
        CheckInt(y);
        IF (x.type.form = ORB.Int) OR (x.type.form = ORB.Set) THEN
          ORG.Shift(fct - 10, x, y); restyp := x.type
        ELSE ORS.Mark("bad type")
        END
      ELSIF fct = 13 THEN ORG.UML(x, y)                (* UML *)
      ELSIF fct = 14 THEN  (* BIT *)
        CheckInt(x); CheckInt(y); ORG.Bit(x, y)
      ELSIF fct = 16 THEN  (* VAL *)
        IF (x.mode = ORB.Typ) & (x.type.size <= y.type.size) THEN
          restyp := x.type; x := y
        ELSE ORS.Mark("casting not allowed")
        END
      ELSIF fct = 17 THEN ORG.Adr(x)                   (* ADR *)
      ELSIF fct = 18 THEN  (* SIZE *)
        IF x.mode = ORB.Typ THEN
          ORG.MakeConstItem(x, ORB.intType, x.type.size)
        ELSE ORS.Mark("must be a type")
        END
      (* 65C816-only SYSTEM functions; unregistered (hence unreachable)
         on the LLVM target, where the ORG stubs are inert. *)
      ELSIF fct = 19 THEN ORG.Condition(x)             (* SYSTEM.COND *)
      ELSIF fct = 20 THEN ORG.HH(x)                    (* SYSTEM.H *)
      ELSIF fct = 21 THEN ORG.Bank(x)                  (* SYSTEM.BANK *)
      END;
      x.type := restyp
    ELSE ORS.Mark("wrong nof params")
    END
  END StandFunc;

  PROCEDURE element(VAR x: ORG.Item);
    VAR y: ORG.Item;
  BEGIN
    expression(x); CheckSetVal(x);
    IF sym = ORS.upto THEN
      ORS.Get(sym); expression(y); CheckSetVal(y); ORG.Set(x, y)
    ELSE ORG.Singleton(x)
    END;
    x.type := ORB.setType
  END element;

  PROCEDURE set(VAR x: ORG.Item);
    VAR y: ORG.Item;
  BEGIN
    IF sym >= ORS.if THEN
      IF sym # ORS.rbrace THEN ORS.Mark(" } missing") END;
      ORG.MakeConstItem(x, ORB.setType, 0)  (* empty set *)
    ELSE
      element(x);
      WHILE (sym < ORS.rparen) OR (sym > ORS.rbrace) DO
        IF sym = ORS.comma THEN ORS.Get(sym)
        ELSIF sym # ORS.rbrace THEN ORS.Mark("missing comma")
        END;
        element(y);
        ORG.SetOp(ORS.plus, x, y)
      END
    END
  END set;

  (* field named `name` anywhere along rec's base chain (fld.val is its byte
     offset within the whole record, inherited or own) *)
  PROCEDURE FindField(rec: ORB.Type; name: ORS.Ident): ORB.Object;
    VAR fld, res: ORB.Object;
  BEGIN res := NIL;
    WHILE (rec # NIL) & (res = NIL) DO
      fld := rec.dsc;
      WHILE (fld # NIL) & (fld.name # name) DO fld := fld.next END;
      IF fld # NIL THEN res := fld END;
      rec := rec.base
    END;
    RETURN res
  END FindField;

  (* Record literal (DDR-019): TypeName{ field := const ; … }. Emits the
     field values into the data section as a zero-filled record image (fields
     placed by offset, any order), yielding a constant record value. Field
     values must be constants (a nested record literal is folded in by copying
     its image); runtime-valued fields are a separate future extension. *)
  PROCEDURE RecordLiteral(VAR x: ORG.Item; rec: ORB.Type);
    VAR fld: ORB.Object; v: ORG.Item; start, i: LONGINT; fname: ORS.Ident;
  BEGIN
    start := ORG.StrOffset();
    i := 0; WHILE i < rec.size DO ORG.PutByte(0); i := i + 1 END;
    ORS.Get(sym);   (* consume { *)
    WHILE sym = ORS.ident DO
      ORS.CopyId(fname); ORS.Get(sym);
      fld := FindField(rec, fname);
      IF fld = NIL THEN ORS.Mark("unknown field") END;
      IF sym = ORS.becomes THEN ORS.Get(sym) ELSE ORS.Mark(":= expected") END;
      expression(v);
      IF fld # NIL THEN
        IF v.mode # ORB.Const THEN
          ORS.Mark("record literal field must be constant")
        ELSIF ~CompTypes(fld.type, v.type, FALSE) THEN
          ORS.Mark("field type mismatch")
        ELSIF (v.type.form = ORB.Record) OR (v.type.form = ORB.Array) THEN
          ORG.CopyStr(start + fld.val, v.a, fld.type.size)   (* nested aggregate *)
        ELSE
          ORG.PatchStr(start + fld.val, v.a, fld.type.size)  (* scalar constant *)
        END
      END;
      IF sym = ORS.semicolon THEN ORS.Get(sym)
      ELSIF sym # ORS.rbrace THEN ORS.Mark("; or } expected") END
    END;
    Check(ORS.rbrace, "} expected");
    ORG.MakeRecordConst(x, rec, start)
  END RecordLiteral;

  (* Target-directed record literal (DDR-019 runtime form): fill an existing
     Var/Par record `target` in place. Reuses StoreStruct-from-a-zero-image to
     zero it (strict zero-fill), then Field + Store per named field (any order,
     runtime values allowed, nested literals recurse). No temporary and no held
     register: each Field/Store re-derives a Var address, so the register
     discipline is inherited from Store. RegI targets (arr[i], p^) are not yet
     handled — they need an ORG-internal held-address fill. *)
  PROCEDURE RecordLitInto(target: ORG.Item; rec: ORB.Type);
    VAR fld, vobj: ORB.Object; fi, v, zi: ORG.Item; start, i: LONGINT;
      fname: ORS.Ident;
  BEGIN
    IF (target.mode # ORB.Var) & (target.mode # ORB.Par) THEN
      ORS.Mark("record literal target must be a variable or field")
    END;
    start := ORG.StrOffset();                       (* zeroed image of rec *)
    i := 0; WHILE i < rec.size DO ORG.PutByte(0); i := i + 1 END;
    ORG.MakeRecordConst(zi, rec, start);
    fi := target; ORG.StoreStruct(fi, zi);          (* zero the target *)
    ORS.Get(sym);                                   (* consume { *)
    WHILE sym = ORS.ident DO
      ORS.CopyId(fname); ORS.Get(sym);
      fld := FindField(rec, fname);
      IF fld = NIL THEN ORS.Mark("unknown field") END;
      IF sym = ORS.becomes THEN ORS.Get(sym) ELSE ORS.Mark(":= expected") END;
      vobj := NIL;
      IF sym = ORS.ident THEN vobj := ORB.thisObj() END;
      IF (fld # NIL) & (vobj # NIL) & (vobj.class = ORB.Typ)
         & (vobj.type.form = ORB.Record) THEN
        fi := target; ORG.Field(fi, fld); fi.type := fld.type;   (* nested literal *)
        qualident(vobj);
        IF sym = ORS.lbrace THEN RecordLitInto(fi, vobj.type)
        ELSE ORS.Mark("{ expected") END
      ELSE
        expression(v);
        IF fld # NIL THEN
          fi := target; ORG.Field(fi, fld); fi.type := fld.type;
          IF ~CompTypes(fld.type, v.type, FALSE) THEN ORS.Mark("field type mismatch")
          ELSIF fld.type.form = ORB.Intfc THEN
            IF v.type.form # ORB.Intfc THEN ORG.PtrToIface(v, fld.type) END;
            ORG.StoreIface(fi, v)
          ELSIF (fld.type.form <= ORB.Pointer) OR (fld.type.form = ORB.Proc) THEN
            ORG.Store(fi, v)
          ELSE ORG.StoreStruct(fi, v)
          END
        END
      END;
      IF sym = ORS.semicolon THEN ORS.Get(sym)
      ELSIF sym # ORS.rbrace THEN ORS.Mark("; or } expected") END
    END;
    Check(ORS.rbrace, "} expected")
  END RecordLitInto;

  (* Target-directed array literal (DDR-020 runtime form): fill a Var/Par array
     `target` in place from `ARRAY OF elemType { e0, e1, … }`. Zeroes the array
     (strict zero-fill), then for each element stores into target[k] — a
     CONSTANT-index target, hence Var mode, so it needs no held-address
     machinery (DDR-019 §9). Elements name their type (DDR-020 §4, Option A):
     a record element is `T{…}`, a nested array `ARRAY OF T {…}`, else an
     expression of the element type. RegI array targets deferred like §DDR-019. *)
  PROCEDURE ArrayLitInto(target: ORG.Item);
    VAR el, idx, et, zi: ORG.Item; arrType, elemType: ORB.Type;
      tobj, vobj: ORB.Object; k, start, i: LONGINT;
  BEGIN
    arrType := target.type;
    IF (target.mode # ORB.Var) & (target.mode # ORB.Par) THEN
      ORS.Mark("array literal target must be a variable or field")
    END;
    ORS.Get(sym); Check(ORS.of, "OF expected");   (* ARRAY OF elemType *)
    qualident(tobj);
    IF arrType.form # ORB.Array THEN ORS.Mark("array literal for a non-array"); elemType := ORB.intType
    ELSE
      elemType := arrType.base;
      IF (tobj.class # ORB.Typ) OR ~CompTypes(elemType, tobj.type, FALSE) THEN
        ORS.Mark("element type mismatch")
      END
    END;
    start := ORG.StrOffset();                      (* zero the whole array *)
    i := 0; WHILE i < arrType.size DO ORG.PutByte(0); i := i + 1 END;
    ORG.MakeRecordConst(zi, arrType, start);
    et := target; ORG.StoreStruct(et, zi);
    Check(ORS.lbrace, "{ expected");
    k := 0;
    WHILE (sym # ORS.rbrace) & (sym # ORS.eot) DO
      IF k >= arrType.len THEN ORS.Mark("too many array elements") END;
      et := target; ORG.MakeConstItem(idx, ORB.intType, k);
      ORG.Index(et, idx); et.type := elemType;     (* et := target[k], constant index -> Var *)
      vobj := NIL; IF sym = ORS.ident THEN vobj := ORB.thisObj() END;
      IF (vobj # NIL) & (vobj.class = ORB.Typ) & (vobj.type.form = ORB.Record)
         & (elemType.form = ORB.Record) THEN
        qualident(vobj);
        IF sym = ORS.lbrace THEN RecordLitInto(et, vobj.type) ELSE ORS.Mark("{ expected") END
      ELSIF (sym = ORS.array) & (elemType.form = ORB.Array) THEN
        ArrayLitInto(et)
      ELSE
        expression(el);
        IF ~CompTypes(elemType, el.type, FALSE) THEN ORS.Mark("element type mismatch")
        ELSIF elemType.form = ORB.Intfc THEN
          IF el.type.form # ORB.Intfc THEN ORG.PtrToIface(el, elemType) END;
          ORG.StoreIface(et, el)
        ELSIF (elemType.form <= ORB.Pointer) OR (elemType.form = ORB.Proc) THEN
          ORG.Store(et, el)
        ELSE ORG.StoreStruct(et, el)
        END
      END;
      INC(k);
      IF sym = ORS.comma THEN ORS.Get(sym)
      ELSIF sym # ORS.rbrace THEN ORS.Mark(", or } expected") END
    END;
    Check(ORS.rbrace, "} expected")
  END ArrayLitInto;

  PROCEDURE factor(VAR x: ORG.Item);
    VAR obj: ORB.Object; rx: LONGINT; m: ORB.Object;
  BEGIN
    (* sync (super sits above the token range; test it explicitly) *)
    IF ((sym < ORS.char) OR (sym > ORS.ident)) & (sym # ORS.super) THEN
      ORS.Mark("expression expected");
      REPEAT ORS.Get(sym)
      UNTIL ((sym >= ORS.char) & (sym <= ORS.for)) OR (sym >= ORS.then)
    END;
    IF sym = ORS.super THEN
      (* SUPER.M(...) as a function call (DDR-006) *)
      m := SuperCall(x);
      IF sym = ORS.lparen THEN
        ORS.Get(sym);
        IF (x.type.form = ORB.Proc) & (x.type.base.form # ORB.NoTyp) THEN
          ORG.PrepCall(x, rx); ParamList(x); ORG.Call(x, rx);
          x.type := x.type.base
        ELSE ORS.Mark("not a function"); ParamList(x)
        END
      ELSE ORS.Mark("no (")
      END
    ELSIF sym = ORS.ident THEN
      qualident(obj);
      IF (obj.class = ORB.Typ) & (obj.type.form = ORB.Record) & (sym = ORS.lbrace) THEN
        RecordLiteral(x, obj.type)                (* DDR-019 record literal *)
      ELSIF obj.class = ORB.SFunc THEN
        StandFunc(x, obj.val, obj.type)
      ELSE
        ORG.MakeItem(x, obj, level);
        selector(x);
        IF sym = ORS.lparen THEN
          ORS.Get(sym);
          IF (x.type.form = ORB.Proc) & (x.type.base.form # ORB.NoTyp) THEN
            ORG.PrepCall(x, rx); ParamList(x); ORG.Call(x, rx);
            x.type := x.type.base
          ELSE ORS.Mark("not a function"); ParamList(x)
          END
        END
      END
    ELSIF sym = ORS.int THEN
      ORG.MakeConstItem(x, ORB.intType, ORS.ival); ORS.Get(sym)
    ELSIF sym = ORS.real THEN
      ORG.MakeRealItem(x, ORS.rval); ORS.Get(sym)
    ELSIF sym = ORS.char THEN
      ORG.MakeConstItem(x, ORB.charType, ORS.ival); ORS.Get(sym)
    ELSIF sym = ORS.nil THEN
      ORS.Get(sym); ORG.MakeConstItem(x, ORB.nilType, 0)
    ELSIF sym = ORS.string THEN
      ORG.MakeStringItem(x, ORS.slen); ORS.Get(sym)
    ELSIF sym = ORS.lparen THEN
      ORS.Get(sym); expression(x); Check(ORS.rparen, "no )")
    ELSIF sym = ORS.lbrace THEN
      ORS.Get(sym); set(x); Check(ORS.rbrace, "no }")
    ELSIF sym = ORS.not THEN
      ORS.Get(sym); factor(x); CheckBool(x); ORG.Not(x)
    ELSIF sym = ORS.false THEN
      ORS.Get(sym); ORG.MakeConstItem(x, ORB.boolType, 0)
    ELSIF sym = ORS.true THEN
      ORS.Get(sym); ORG.MakeConstItem(x, ORB.boolType, 1)
    ELSE
      ORS.Mark("not a factor");
      ORG.MakeConstItem(x, ORB.intType, 0)
    END
  END factor;

  PROCEDURE term(VAR x: ORG.Item);
    VAR y: ORG.Item; op, f: INTEGER;
  BEGIN
    factor(x); f := x.type.form;
    WHILE (sym >= ORS.times) & (sym <= ORS.and) DO
      op := sym; ORS.Get(sym);
      IF op = ORS.times THEN
        IF f = ORB.Int THEN factor(y); CheckInt(y); ORG.MulOp(x, y)
        ELSIF f = ORB.Real THEN factor(y); CheckReal(y); ORG.RealOp(op, x, y)
        ELSIF f = ORB.Set THEN factor(y); CheckSet(y); ORG.SetOp(op, x, y)
        ELSE ORS.Mark("bad type")
        END
      ELSIF (op = ORS.div) OR (op = ORS.mod) THEN
        CheckInt(x); factor(y); CheckInt(y); ORG.DivOp(op, x, y)
      ELSIF op = ORS.rdiv THEN
        IF f = ORB.Real THEN factor(y); CheckReal(y); ORG.RealOp(op, x, y)
        ELSIF f = ORB.Set THEN factor(y); CheckSet(y); ORG.SetOp(op, x, y)
        ELSE ORS.Mark("bad type")
        END
      ELSE  (* op = and *)
        CheckBool(x); ORG.And1(x); factor(y); CheckBool(y); ORG.And2(x, y)
      END
    END
  END term;

  PROCEDURE SimpleExpression(VAR x: ORG.Item);
    VAR y: ORG.Item; op: INTEGER;
  BEGIN
    IF sym = ORS.minus THEN
      ORS.Get(sym); term(x);
      IF (x.type.form = ORB.Int) OR (x.type.form = ORB.Real) OR
         (x.type.form = ORB.Set) THEN
        ORG.Neg(x)
      ELSE CheckInt(x)
      END
    ELSIF sym = ORS.plus THEN
      ORS.Get(sym); term(x)
    ELSE term(x)
    END;
    WHILE (sym >= ORS.plus) & (sym <= ORS.or) DO
      op := sym; ORS.Get(sym);
      IF op = ORS.or THEN
        ORG.Or1(x); CheckBool(x); term(y); CheckBool(y); ORG.Or2(x, y)
      ELSIF x.type.form = ORB.Int THEN
        term(y); CheckInt(y); ORG.AddOp(op, x, y)
      ELSIF x.type.form = ORB.Real THEN
        term(y); CheckReal(y); ORG.RealOp(op, x, y)
      ELSE
        CheckSet(x); term(y); CheckSet(y); ORG.SetOp(op, x, y)
      END
    END
  END SimpleExpression;

  PROCEDURE expression0*(VAR x: ORG.Item);
    VAR y: ORG.Item; obj: ORB.Object;
      rel, xf, yf: INTEGER;
  BEGIN
    SimpleExpression(x);
    IF (sym >= ORS.eql) & (sym <= ORS.gtr) THEN
      rel := sym; ORG.Rel1(x); ORS.Get(sym);
      SimpleExpression(y);
      xf := x.type.form; yf := y.type.form;
      IF x.type = y.type THEN
        IF (xf = ORB.Char) OR (xf = ORB.Int) THEN
          ORG.IntRelation(rel, x, y)
        ELSIF xf = ORB.Real THEN
          ORG.RealRelation(rel, x, y)
        ELSIF (xf = ORB.Set) OR (xf = ORB.Pointer) OR (xf = ORB.Proc) OR
              (xf = ORB.NilTyp) OR (xf = ORB.Bool) THEN
          IF rel <= ORS.neq THEN ORG.IntRelation(rel, x, y)
          ELSE ORS.Mark("only = or #")
          END
        ELSIF xf = ORB.Intfc THEN
          IF rel <= ORS.neq THEN ORG.IfaceRelation(rel, x, y)
          ELSE ORS.Mark("only = or #")
          END
        ELSIF ((xf = ORB.Array) & (x.type.base.form = ORB.Char)) OR
              (xf = ORB.String) THEN
          ORG.StringRelation(rel, x, y)
        ELSE ORS.Mark("illegal comparison")
        END
      ELSIF ((xf = ORB.Intfc) & (yf = ORB.NilTyp)) OR
            ((yf = ORB.Intfc) & (xf = ORB.NilTyp)) THEN
        IF rel <= ORS.neq THEN ORG.IfaceRelation(rel, x, y)
        ELSE ORS.Mark("only = or #")
        END
      ELSIF ((xf = ORB.Pointer) OR ((xf = ORB.Proc) & (yf = ORB.NilTyp))) OR
            ((yf = ORB.Pointer) OR ((yf = ORB.Proc) & (xf = ORB.NilTyp))) THEN
        IF rel <= ORS.neq THEN ORG.IntRelation(rel, x, y)
        ELSE ORS.Mark("only = or #")
        END
      ELSIF ((xf = ORB.Pointer) & (yf = ORB.Pointer) &
             (IsExtension(x.type.base, y.type.base) OR
              IsExtension(y.type.base, x.type.base))) OR
            ((xf = ORB.Proc) & (yf = ORB.Proc) &
             EqualSignatures(x.type, y.type)) THEN
        IF rel <= ORS.neq THEN ORG.IntRelation(rel, x, y)
        ELSE ORS.Mark("only = or #")
        END
      ELSIF ((xf = ORB.Array) & (x.type.base.form = ORB.Char) &
             ((yf = ORB.String) OR
              ((yf = ORB.Array) & (y.type.base.form = ORB.Char)))) OR
            ((yf = ORB.Array) & (y.type.base.form = ORB.Char) &
             (xf = ORB.String)) THEN
        ORG.StringRelation(rel, x, y)
      ELSIF (xf = ORB.Char) & (yf = ORB.String) & (y.b = 2) THEN
        ORG.StrToChar(y); ORG.IntRelation(rel, x, y)
      ELSIF (yf = ORB.Char) & (xf = ORB.String) & (x.b = 2) THEN
        ORG.StrToChar(x); ORG.IntRelation(rel, x, y)
      ELSIF (xf = ORB.Int) & (yf = ORB.Int) THEN
        ORG.IntRelation(rel, x, y)  (* BYTE *)
      ELSE ORS.Mark("illegal comparison")
      END;
      x.type := ORB.boolType
    ELSIF sym = ORS.in THEN
      ORS.Get(sym);
      CheckInt(x); SimpleExpression(y); CheckSet(y);
      ORG.In(x, y);
      x.type := ORB.boolType
    ELSIF sym = ORS.is THEN
      ORS.Get(sym); qualident(obj);
      TypeTest(x, obj.type, FALSE);
      x.type := ORB.boolType
    END
  END expression0;

  (* statements *)

  PROCEDURE StandProc(pno: LONGINT);
    VAR nap, npar: LONGINT;
      x, y, z: ORG.Item;
  BEGIN
    Check(ORS.lparen, "no (");
    npar := pno MOD 10; pno := pno DIV 10;
    expression(x); nap := 1;
    IF (pno = 10) OR (pno = 11) THEN ORG.SpillBank(x) END;   (* GET, PUT: the bank, before the rest takes registers *)
    IF sym = ORS.comma THEN
      ORS.Get(sym); expression(y); nap := 2;
      z.type := ORB.noType;
      WHILE sym = ORS.comma DO
        ORS.Get(sym); expression(z); INC(nap)
      END
    ELSE y.type := ORB.noType
    END;
    Check(ORS.rparen, "no )");
    IF (npar = nap) OR (pno = 0) OR (pno = 1) THEN
      IF (pno = 0) OR (pno = 1) THEN  (* INC, DEC *)
        CheckInt(x); CheckReadOnly(x);
        IF y.type # ORB.noType THEN CheckInt(y)
        ELSE ORG.MakeConstItem(y, x.type, 1)
        END;
        ORG.Increment(pno, x, y)
      ELSIF (pno = 2) OR (pno = 3) THEN  (* INCL, EXCL *)
        CheckSet(x); CheckReadOnly(x); CheckInt(y);
        ORG.Include(pno - 2, x, y)
      ELSIF pno = 4 THEN  (* ASSERT *)
        CheckBool(x); ORG.Assert(x)
      ELSIF pno = 5 THEN  (* NEW *)
        CheckReadOnly(x);
        IF (x.type.form = ORB.Pointer) & (x.type.base.form = ORB.Record) THEN
          IF ORB.HasInits(x.type.base) THEN
            (* DDR-003: allocation must go through a constructor *)
            ORS.Mark("type has initialisers; construct with T.Name(...)")
          ELSE ORG.New(x)
          END
        ELSE ORS.Mark("not a pointer to record")
        END
      ELSIF pno = 6 THEN  (* PACK *)
        CheckReal(x); CheckInt(y); CheckReadOnly(x); ORG.Pack(x, y)
      ELSIF pno = 7 THEN  (* UNPK *)
        CheckReal(x); CheckInt(y); CheckReadOnly(x); ORG.Unpk(x, y)
      ELSIF pno = 10 THEN  (* GET: (addr,var) or 65C816 (bank,addr,var) *)
        CheckInt(x);
        IF nap = 3 THEN ORG.GetB(x, y, z) ELSE ORG.Get(x, y) END
      ELSIF pno = 11 THEN  (* PUT: (addr,val) or 65C816 (bank,addr,val) *)
        CheckInt(x);
        IF nap = 3 THEN ORG.PutB(x, y, z) ELSE ORG.Put(x, y) END
      ELSIF pno = 12 THEN  (* COPY *)
        CheckInt(x); CheckInt(y); CheckInt(z); ORG.Copy(x, y, z)
      (* 65C816-only SYSTEM procedures; unregistered on LLVM. *)
      ELSIF pno = 9 THEN   (* INTEN *) ORG.IntEn(x)
      ELSIF pno = 13 THEN  (* TRB *) CheckInt(x); ORG.TRB(x, y)
      ELSIF pno = 14 THEN  (* TSB *) CheckInt(x); ORG.TSB(x, y)
      ELSIF pno = 15 THEN  (* EXEC *) ORG.Exec(x, y)
      END
    ELSE ORS.Mark("wrong nof parameters")
    END
  END StandProc;

  PROCEDURE StatSequence*;
    VAR obj, sm: ORB.Object;
      orgtype: ORB.Type;
      x, y, z, w: ORG.Item;
      L0, L1, rx: LONGINT;
      callable: BOOLEAN;

    PROCEDURE TypeCase(obj: ORB.Object; VAR x: ORG.Item);
      VAR typobj: ORB.Object;
    BEGIN
      IF sym = ORS.ident THEN
        qualident(typobj);
        ORG.MakeItem(x, obj, level);
        IF typobj.class # ORB.Typ THEN ORS.Mark("not a type") END;
        TypeTest(x, typobj.type, FALSE);
        obj.type := typobj.type;
        ORG.CFJump(x);
        Check(ORS.colon, ": expected");
        StatSequence
      ELSE
        ORG.CFJump(x);
        ORS.Mark("type id expected")
      END
    END TypeCase;

    PROCEDURE SkipCase;
    BEGIN
      WHILE sym # ORS.colon DO ORS.Get(sym) END;
      ORS.Get(sym);
      StatSequence
    END SkipCase;

    PROCEDURE parseCaseLabel(): LONGINT;
      VAR obj: ORB.Object; val: LONGINT;
    BEGIN val := 0;
      IF sym = ORS.int THEN
        val := ORS.ival; ORS.Get(sym)
      ELSIF (sym = ORS.string) & (ORS.slen = 2) THEN
        val := ORD(ORS.str[0]); ORS.Get(sym)
      ELSIF sym = ORS.ident THEN
        qualident(obj);
        IF obj.class = ORB.Const THEN val := obj.val
        ELSE ORS.Mark("not a constant")
        END
      ELSE ORS.Mark("case label expected")
      END;
      RETURN val
    END parseCaseLabel;

    PROCEDURE CaseLabelRange(caseObj: ORB.Object; VAR hitChain: LONGINT);
      VAR cx: ORG.Item; lo, hi: LONGINT;
    BEGIN
      lo := parseCaseLabel();
      IF sym = ORS.upto THEN
        ORS.Get(sym);
        hi := parseCaseLabel();
        ORG.MakeItem(cx, caseObj, level);
        ORG.CaseRange(cx, lo, hi, hitChain)
      ELSE
        ORG.MakeItem(cx, caseObj, level);
        ORG.CaseLabel(cx, lo, hitChain)
      END
    END CaseLabelRange;

    PROCEDURE CaseLabelList(caseObj: ORB.Object; VAR hitChain: LONGINT);
    BEGIN
      CaseLabelRange(caseObj, hitChain);
      WHILE sym = ORS.comma DO
        ORS.Get(sym);
        CaseLabelRange(caseObj, hitChain)
      END
    END CaseLabelList;

    PROCEDURE NumericCaseArm(caseObj: ORB.Object; VAR endChain: LONGINT);
      VAR hitChain, missLink: LONGINT;
    BEGIN
      hitChain := 0; missLink := 0;
      CaseLabelList(caseObj, hitChain);
      ORG.FJump(missLink);      (* skip body if no label matched *)
      ORG.FixLink(hitChain);    (* matched labels land here *)
      Check(ORS.colon, ": expected");
      StatSequence;
      ORG.FJump(endChain);      (* jump to end of CASE *)
      ORG.FixOne(missLink)      (* no-match continues to next arm *)
    END NumericCaseArm;

  BEGIN (* StatSequence *)
    REPEAT
      obj := NIL;
      IF ~((sym >= ORS.ident) & (sym <= ORS.for)) & (sym < ORS.semicolon) &
         (sym # ORS.super) THEN
        ORS.Mark("statement expected");
        REPEAT ORS.Get(sym) UNTIL sym >= ORS.ident
      END;
      IF sym = ORS.ident THEN
        qualident(obj);
        ORG.MakeItem(x, obj, level);
        IF x.mode = ORB.SProc THEN
          StandProc(obj.val)
        ELSE
          selector(x);
          IF sym = ORS.becomes THEN  (* assignment *)
            ORS.Get(sym); CheckReadOnly(x);
            IF sym = ORS.array THEN
              ArrayLitInto(x)   (* DDR-020 array-literal RHS, filled in place *)
            ELSE
            obj := NIL;
            IF sym = ORS.ident THEN obj := ORB.thisObj() END;
            IF (obj # NIL) & (obj.class = ORB.Typ) & (obj.type.form = ORB.Record) THEN
              qualident(obj);   (* DDR-019 record-literal RHS, filled in place *)
              IF sym = ORS.lbrace THEN RecordLitInto(x, obj.type)
              ELSE ORS.Mark("{ expected") END
            ELSE
            expression(y);
            IF CompTypes(x.type, y.type, FALSE) THEN
              IF x.type.form = ORB.Intfc THEN
                IF y.type.form # ORB.Intfc THEN
                  ORG.PtrToIface(y, x.type)   (* pointer or NIL *)
                END;
                ORG.StoreIface(x, y)
              ELSIF (x.type.form <= ORB.Pointer) OR (x.type.form = ORB.Proc) THEN
                ORG.Store(x, y)
              ELSE ORG.StoreStruct(x, y)
              END
            ELSIF (x.type.form = ORB.Array) & (y.type.form = ORB.Array) &
                  (x.type.base = y.type.base) & (y.type.len < 0) THEN
              ORG.StoreStruct(x, y)
            ELSIF (x.type.form = ORB.Array) & (x.type.base.form = ORB.Char) &
                  (y.type.form = ORB.String) THEN
              ORG.CopyString(x, y)
            ELSIF (x.type.form = ORB.Int) & (y.type.form = ORB.Int) THEN
              ORG.Store(x, y)  (* BYTE *)
            ELSIF (x.type.form = ORB.Char) & (y.type.form = ORB.String) &
                  (y.b = 2) THEN
              ORG.StrToChar(y); ORG.Store(x, y)
            ELSE ORS.Mark("illegal assignment")
            END
            END   (* record-literal RHS vs normal expression *)
            END   (* array-literal RHS vs the rest *)
          ELSIF sym = ORS.eql THEN
            ORS.Mark("should be :="); ORS.Get(sym); expression(y)
          ELSIF sym = ORS.lparen THEN  (* procedure call *)
            ORS.Get(sym);
            IF (x.type.form = ORB.Proc) & (x.type.base.form = ORB.NoTyp) THEN
              ORG.PrepCall(x, rx); ParamList(x); ORG.Call(x, rx)
            ELSE ORS.Mark("not a procedure"); ParamList(x)
            END
          ELSIF x.type.form = ORB.Proc THEN  (* call without parameters *)
            IF x.type.mthd THEN
              IF x.type.nofpar > 1 THEN ORS.Mark("missing parameters") END
            ELSIF x.type.nofpar > 0 THEN
              ORS.Mark("missing parameters")
            END;
            IF x.type.base.form = ORB.NoTyp THEN
              ORG.PrepCall(x, rx); ORG.Call(x, rx)
            ELSE ORS.Mark("not a procedure")
            END
          ELSIF x.mode = ORB.Typ THEN ORS.Mark("illegal assignment")
          ELSE ORS.Mark("not a procedure")
          END
        END
      ELSIF sym = ORS.super THEN
        (* SUPER.M(...) / SUPER.Create(...) as a statement (DDR-006).
           A super-initialiser returns the receiver at +1; nothing
           consumes it here, so the statement drops the reference. *)
        sm := SuperCall(x);
        callable := (x.type.form = ORB.Proc) &
          ((x.type.base.form = ORB.NoTyp) OR ((sm # NIL) & sm.initf));
        IF sym = ORS.lparen THEN
          ORS.Get(sym);
          IF callable THEN
            ORG.PrepCall(x, rx); ParamList(x); ORG.Call(x, rx);
            x.type := x.type.base;
            ORG.Discard(x)
          ELSE
            ORS.Mark("not a procedure");
            IF x.type.form = ORB.Proc THEN ParamList(x) END
          END
        ELSIF callable THEN
          IF x.type.mthd THEN
            IF x.type.nofpar > 1 THEN ORS.Mark("missing parameters") END
          ELSIF x.type.nofpar > 0 THEN
            ORS.Mark("missing parameters")
          END;
          ORG.PrepCall(x, rx); ORG.Call(x, rx);
          x.type := x.type.base;
          ORG.Discard(x)
        ELSE ORS.Mark("not a procedure")
        END
      ELSIF sym = ORS.if THEN
        ORS.Get(sym);
        expression(x); CheckBool(x); ORG.CFJump(x);
        Check(ORS.then, "no THEN");
        StatSequence;
        L0 := 0;
        WHILE sym = ORS.elsif DO
          ORS.Get(sym);
          ORG.FJump(L0); ORG.Fixup(x);
          expression(x); CheckBool(x); ORG.CFJump(x);
          Check(ORS.then, "no THEN");
          StatSequence
        END;
        IF sym = ORS.else THEN
          ORS.Get(sym);
          ORG.FJump(L0); ORG.Fixup(x);
          StatSequence
        ELSE ORG.Fixup(x)
        END;
        ORG.FixLink(L0);
        Check(ORS.end, "no END")
      ELSIF sym = ORS.while THEN
        ORS.Get(sym);
        L0 := ORG.Here();
        expression(x); CheckBool(x); ORG.CFJump(x);
        Check(ORS.do, "no DO");
        StatSequence;
        ORG.BJump(L0);
        WHILE sym = ORS.elsif DO
          ORS.Get(sym);
          ORG.Fixup(x);
          expression(x); CheckBool(x); ORG.CFJump(x);
          Check(ORS.do, "no DO");
          StatSequence;
          ORG.BJump(L0)
        END;
        ORG.Fixup(x);
        Check(ORS.end, "no END")
      ELSIF sym = ORS.repeat THEN
        ORS.Get(sym);
        L0 := ORG.Here();
        StatSequence;
        IF sym = ORS.until THEN
          ORS.Get(sym);
          expression(x); CheckBool(x); ORG.CBJump(x, L0)
        ELSE ORS.Mark("missing UNTIL")
        END
      ELSIF sym = ORS.for THEN
        ORS.Get(sym);
        IF sym = ORS.ident THEN
          qualident(obj);
          ORG.MakeItem(x, obj, level);
          CheckInt(x); CheckReadOnly(x);
          IF sym = ORS.becomes THEN
            ORS.Get(sym);
            expression(y); CheckInt(y); ORG.For0(x, y);
            Check(ORS.to, "no TO");
            expression(z); CheckInt(z);
            (* both bounds evaluate once at loop entry (Oberon-07) *)
            ORG.Snapshot(z);
            obj.rdo := TRUE;
            IF sym = ORS.by THEN
              ORS.Get(sym);
              expression(w); CheckConst(w); CheckInt(w)
            ELSE ORG.MakeConstItem(w, ORB.intType, 1)
            END;
            Check(ORS.do, "no DO");
            L0 := ORG.Here();
            ORG.For1(x, z, w, L1);
            StatSequence;
            Check(ORS.end, "no END");
            ORG.For2(x, y, w);
            ORG.BJump(L0);
            ORG.FixLink(L1);
            ORG.ForClose;   (* release any limit the backend spilled at Snapshot *)
            obj.rdo := FALSE
          ELSE ORS.Mark(":= expected")
          END
        ELSE ORS.Mark("identifier expected")
        END
      ELSIF sym = ORS.case THEN
        ORS.Get(sym);
        IF sym = ORS.ident THEN
          qualident(obj);
          orgtype := obj.type;
          IF (orgtype.form = ORB.Pointer) OR
             ((orgtype.form = ORB.Record) & (obj.class = ORB.Par)) THEN
            Check(ORS.of, "OF expected");
            TypeCase(obj, x);
            L0 := 0;
            WHILE sym = ORS.bar DO
              ORS.Get(sym);
              ORG.FJump(L0); ORG.Fixup(x);
              obj.type := orgtype;
              TypeCase(obj, x)
            END;
            ORG.Fixup(x);
            ORG.FixLink(L0);
            obj.type := orgtype
          ELSIF (orgtype.form = ORB.Int) OR (orgtype.form = ORB.Char) THEN
            Check(ORS.of, "OF expected");
            L0 := 0;
            NumericCaseArm(obj, L0);
            WHILE sym = ORS.bar DO
              ORS.Get(sym);
              NumericCaseArm(obj, L0)
            END;
            IF sym = ORS.else THEN
              ORS.Get(sym);
              StatSequence
            END;
            ORG.FixLink(L0)
          ELSE
            ORS.Mark("invalid case type");
            Check(ORS.of, "OF expected");
            SkipCase;
            WHILE sym = ORS.bar DO SkipCase END
          END
        ELSE ORS.Mark("ident expected")
        END;
        Check(ORS.end, "no END")
      END;
      ORG.CheckRegs;
      IF sym = ORS.semicolon THEN ORS.Get(sym)
      ELSIF sym < ORS.semicolon THEN
        ORS.Mark("missing semicolon?"); ORS.Get(sym)
      END
    UNTIL (sym > ORS.semicolon) & (sym # ORS.super)   (* SUPER's token is past them, and starts a statement *)
  END StatSequence;
END ORPS.
