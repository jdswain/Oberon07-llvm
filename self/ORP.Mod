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
   self/main.c — and calls Compile. *)

  IMPORT Files, Out, ORS, ORB, ORG;

  CONST VERSION = 1;
    WordSize = ORG.WordSize;   (* target word size, from the backend *)

  TYPE
    PtrBase = POINTER TO PtrBaseDesc;
    PtrBaseDesc = RECORD
      name: ORS.Ident;
      type: ORB.Type;
      next: PtrBase
    END;

    ExprProc = PROCEDURE (VAR x: ORG.Item);
    TypeProc = PROCEDURE (VAR type: ORB.Type);
    FormalTypeProc = PROCEDURE (VAR typ: ORB.Type; dim: INTEGER);

  VAR sym: INTEGER;   (*last symbol read*)
    dc: LONGINT;      (*data counter*)
    level, exno: INTEGER;
    newSF: BOOLEAN;
    expression: ExprProc;          (*to avoid forward references*)
    Type: TypeProc;
    FormalType: FormalTypeProc;
    modid: ORS.Ident;
    pbsList: PtrBase;   (*list of names of pointer base types*)
    dummy: ORB.Object;
    (* SUPER context of the enclosing type-bound body (DDR-006) *)
    CurRcv: ORB.Object;
    CurRcvRec: ORB.Type;
    CurIsInit, SuperInitCalled: BOOLEAN;

  PROCEDURE Check(s: INTEGER; msg: ARRAY OF CHAR);
  BEGIN
    IF sym = s THEN ORS.Get(sym) ELSE ORS.Mark(msg) END
  END Check;

  PROCEDURE qualident(VAR obj: ORB.Object);
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

  PROCEDURE CheckExport(VAR expo: BOOLEAN);
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
      (* narrowing an interface reference (DDR-008 §5.4): ordinary tag test *)
      ORG.TypeTest(x, T, FALSE, guard);
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

  PROCEDURE EqualSignatures(t0, t1: ORB.Type): BOOLEAN;
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
  PROCEDURE MethodSigMatch(t0, t1: ORB.Type): BOOLEAN;
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

  PROCEDURE CompTypes(t0, t1: ORB.Type; varpar: BOOLEAN): BOOLEAN;
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
              ORG.DeRef(x); x.type := x.type.base; wasPtr := TRUE
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
          ORG.DeRef(x); x.type := x.type.base
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
      ELSIF fct = 5 THEN CheckInt(x); ORG.Ord(x)       (* CHR *)
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
      IF obj.class = ORB.SFunc THEN
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

  PROCEDURE expression0(VAR x: ORG.Item);
    VAR y: ORG.Item; obj: ORB.Object;
      rel, xf, yf: INTEGER;
  BEGIN
    SimpleExpression(x);
    IF (sym >= ORS.eql) & (sym <= ORS.gtr) THEN
      rel := sym; ORS.Get(sym);
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

  PROCEDURE StatSequence;
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
            ORG.For1(x, y, z, w, L1);
            StatSequence;
            Check(ORS.end, "no END");
            ORG.For2(x, y, w);
            ORG.BJump(L0);
            ORG.FixLink(L1);
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
    UNTIL sym > ORS.semicolon
  END StatSequence;

  (* types and declarations *)

  PROCEDURE IdentList(class: INTEGER; VAR first: ORB.Object);
    VAR obj: ORB.Object;
  BEGIN
    IF sym = ORS.ident THEN
      ORB.NewObj(first, ORS.id, class); ORS.Get(sym);
      CheckExport(first.expo);
      WHILE sym = ORS.comma DO
        ORS.Get(sym);
        IF sym = ORS.ident THEN
          ORB.NewObj(obj, ORS.id, class); ORS.Get(sym);
          CheckExport(obj.expo)
        ELSE ORS.Mark("ident?")
        END
      END;
      IF sym = ORS.colon THEN ORS.Get(sym) ELSE ORS.Mark(":?") END
    ELSE first := NIL
    END
  END IdentList;

  PROCEDURE ArrayType(VAR type: ORB.Type);
    VAR x: ORG.Item; typ: ORB.Type; len: LONGINT;
  BEGIN
    NEW(typ); typ.form := ORB.NoTyp;
    expression(x);
    IF (x.mode = ORB.Const) & (x.type.form = ORB.Int) & (x.a >= 0) THEN
      len := x.a
    ELSE len := 1; ORS.Mark("not a valid length")
    END;
    IF sym = ORS.of THEN
      ORS.Get(sym);
      Type(typ.base);
      IF (typ.base.form = ORB.Array) & (typ.base.len < 0) THEN
        ORS.Mark("dyn array not allowed")
      END
    ELSIF sym = ORS.comma THEN
      ORS.Get(sym);
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
    typ.mno := -level; typ.nofpar := 0;
    offset := 0; bot := NIL;
    IF sym = ORS.lparen THEN
      ORS.Get(sym);  (*record extension*)
      IF level # 0 THEN ORS.Mark("extension of local types not implemented") END;
      IF sym = ORS.ident THEN
        qualident(base);
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
      Check(ORS.rparen, "no )")
    END;
    IF sym = ORS.implements THEN
      (* declared conformance (DDR-008 §5.1): one base record, many
         interfaces — checked once per module after all methods *)
      IF level # 0 THEN ORS.Mark("IMPLEMENTS only at module level") END;
      REPEAT
        ORS.Get(sym);
        IF sym = ORS.ident THEN
          qualident(base);
          IF (base.class = ORB.Typ) & (base.type # NIL) &
             (base.type.form = ORB.Intfc) THEN
            NEW(im); im.intfc := base.type;
            im.next := typ.impl; typ.impl := im
          ELSE ORS.Mark("interface expected")
          END
        ELSE ORS.Mark("ident expected")
        END
      UNTIL sym # ORS.comma
    END;
    WHILE sym = ORS.ident DO  (*fields*)
      n := 0; obj := bot;
      WHILE sym = ORS.ident DO
        obj0 := obj;
        WHILE (obj0 # NIL) & (obj0.name # ORS.id) DO obj0 := obj0.next END;
        IF obj0 # NIL THEN ORS.Mark("mult def") END;
        NEW(new); ORS.CopyId(new.name); new.class := ORB.Fld;
        new.next := obj; obj := new; INC(n);
        ORS.Get(sym);
        CheckExport(new.expo);
        IF (sym # ORS.comma) & (sym # ORS.colon) THEN ORS.Mark("comma expected")
        ELSIF sym = ORS.comma THEN ORS.Get(sym)
        END
      END;
      Check(ORS.colon, "colon expected");
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
      IF sym = ORS.semicolon THEN ORS.Get(sym)
      ELSIF sym # ORS.end THEN ORS.Mark(" ; or END")
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
    IF sym = ORS.var THEN ORS.Get(sym); cl := ORB.Par
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
      parsize := 2 * WordSize   (* open array: pointer + length *)
    ELSIF (cl = ORB.Par) & (tp.form = ORB.Record) THEN
      parsize := 2 * WordSize   (* VAR record: pointer + type tag *)
    ELSIF cl = ORB.Par THEN
      parsize := WordSize
    ELSE parsize := tp.size
    END;
    WHILE first # NIL DO
      INC(nofpar);
      first.class := cl; first.type := tp; first.rdo := rdo;
      first.lev := level;
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
    IF sym = ORS.lparen THEN
      ORS.Get(sym);
      IF sym = ORS.rparen THEN ORS.Get(sym)
      ELSE
        FPSection(size, nofpar);
        WHILE sym = ORS.semicolon DO
          ORS.Get(sym);
          FPSection(size, nofpar)
        END;
        Check(ORS.rparen, "no )")
      END;
      IF sym = ORS.colon THEN  (*function*)
        ORS.Get(sym);
        IF sym = ORS.ident THEN
          qualident(obj);
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
    IF sym = ORS.ident THEN
      qualident(obj);
      IF obj.class = ORB.Typ THEN typ := obj.type
      ELSE ORS.Mark("not a type"); typ := ORB.intType
      END
    ELSIF sym = ORS.array THEN
      ORS.Get(sym);
      Check(ORS.of, "OF ?");
      IF dim >= 1 THEN ORS.Mark("multi-dimensional open arrays not implemented") END;
      NEW(typ);
      typ.form := ORB.Array; typ.len := -1;
      typ.size := 2 * WordSize;
      FormalType(typ.base, dim + 1)
    ELSIF sym = ORS.procedure THEN
      ORS.Get(sym);
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
    typ.mno := -level;
    tail := NIL; slot := 0;
    WHILE (sym = ORS.ident) OR (sym = ORS.procedure) DO
      IF sym = ORS.ident THEN
        (* inclusion by naming *)
        qualident(iobj);
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
              IF ~EqualSignatures(ex.type, m.type) THEN
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
        ORS.Get(sym);
        IF sym = ORS.ident THEN
          ORS.CopyId(mname);
          ORS.Get(sym);
          NEW(ptype);
          ptype.form := ORB.Proc; ptype.size := 4; ptype.mthd := TRUE;
          ORB.OpenScope;
          (* synthetic receiver: the conforming type is unknown here *)
          ORB.NewObj(rp, "@", ORB.Var);
          rp.type := ORB.nilType; rp.lev := level;
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
      IF sym = ORS.semicolon THEN ORS.Get(sym)
      ELSIF sym # ORS.end THEN ORS.Mark("; or END")
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
    IF (sym # ORS.ident) & (sym < ORS.array) & (sym # ORS.weak) THEN
      ORS.Mark("not a type");
      REPEAT ORS.Get(sym)
      UNTIL (sym = ORS.ident) OR (sym >= ORS.array) OR (sym = ORS.weak)
    END;
    (* optional WEAK prefix: applies only to a following POINTER type *)
    IF sym = ORS.weak THEN
      ORS.Get(sym); isWeak := TRUE;
      IF sym # ORS.pointer THEN ORS.Mark("POINTER expected after WEAK") END
    END;
    IF sym = ORS.ident THEN
      qualident(obj);
      IF obj.class = ORB.Typ THEN
        IF (obj.type # NIL) & (obj.type.form # ORB.NoTyp) THEN
          type := obj.type
        END
      ELSE ORS.Mark("not a type or undefined")
      END
    ELSIF sym = ORS.array THEN
      ORS.Get(sym); ArrayType(type)
    ELSIF sym = ORS.record THEN
      ORS.Get(sym); RecordType(type); Check(ORS.end, "no END")
    ELSIF sym = ORS.interface THEN
      ORS.Get(sym); InterfaceType(type); Check(ORS.end, "no END")
    ELSIF sym = ORS.pointer THEN
      ORS.Get(sym); Check(ORS.to, "no TO");
      NEW(type);
      type.form := ORB.Pointer; type.size := 4;
      type.base := ORB.intType; type.weak := isWeak;
      IF sym = ORS.ident THEN
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
          CheckRecLevel(level);
          (*enter into list of forward references to be fixed in Declarations*)
          NEW(ptbase);
          ORS.CopyId(ptbase.name);
          ptbase.type := type;
          ptbase.next := pbsList; pbsList := ptbase
        END;
        ORS.Get(sym)
      ELSE
        Type(type.base);
        IF (type.base.form # ORB.Record) OR (type.base.typobj = NIL) THEN
          ORS.Mark("must point to named record")
        END;
        CheckRecLevel(level)
      END
    ELSIF sym = ORS.procedure THEN
      ORS.Get(sym);
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
    VAR obj, first: ORB.Object;
      x: ORG.Item;
      tp: ORB.Type;
      ptbase: PtrBase;
      expo: BOOLEAN;
      id: ORS.Ident;
      reorderOfs: LONGINT;
      p: ORB.Object;
  BEGIN
    (*sync*)
    pbsList := NIL;
    IF (sym < ORS.const) & (sym # ORS.end) & (sym # ORS.return) THEN
      ORS.Mark("declaration?");
      REPEAT ORS.Get(sym)
      UNTIL (sym >= ORS.const) OR (sym = ORS.end) OR (sym = ORS.return)
    END;
    IF sym = ORS.const THEN
      ORS.Get(sym);
      WHILE sym = ORS.ident DO
        ORS.CopyId(id);
        ORS.Get(sym);
        CheckExport(expo);
        IF sym = ORS.eql THEN ORS.Get(sym) ELSE ORS.Mark("= ?") END;
        expression(x);
        IF (x.type.form = ORB.String) & (x.b = 2) THEN ORG.StrToChar(x) END;
        ORB.NewObj(obj, id, ORB.Const);
        obj.expo := expo;
        IF x.mode = ORB.Const THEN
          obj.val := x.a; obj.lev := x.b; obj.type := x.type
        ELSE
          ORS.Mark("expression not constant"); obj.type := ORB.intType
        END;
        Check(ORS.semicolon, "; missing")
      END
    END;
    IF sym = ORS.type THEN
      ORS.Get(sym);
      WHILE sym = ORS.ident DO
        ORS.CopyId(id);
        ORS.Get(sym);
        CheckExport(expo);
        IF sym = ORS.eql THEN ORS.Get(sym) ELSE ORS.Mark("=?") END;
        Type(tp);
        ORB.NewObj(obj, id, ORB.Typ);
        obj.type := tp; obj.expo := expo; obj.lev := level;
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
          IF level = 0 THEN ORG.BuildTD(tp, dc) END
        END;
        Check(ORS.semicolon, "; missing")
      END
    END;
    IF sym = ORS.var THEN
      ORS.Get(sym);
      WHILE sym = ORS.ident DO
        IdentList(ORB.Var, first);
        Type(tp);
        obj := first;
        WHILE obj # NIL DO
          obj.type := tp; obj.lev := level;
          IF level > 0 THEN obj.val := 1 + parblksize + varsize
          ELSE obj.val := varsize
          END;
          varsize := varsize + obj.type.size;
          IF obj.expo THEN obj.exno := exno; INC(exno) END;
          obj := obj.next
        END;
        Check(ORS.semicolon, "; missing")
      END
    END;
    (* 65C816 heritage: keep scalar locals within 8-bit stack offsets.
       Harmless for the LLVM backend (locals are allocas by name). *)
    IF (level > 0) & (varsize > 0) THEN
      reorderOfs := 0;
      p := ORB.topScope.next;
      WHILE p # NIL DO
        IF (p.class = ORB.Var) & (p.lev = level) & (p.val > parblksize) &
           (p.type.size <= 8) THEN
          p.val := 1 + parblksize + reorderOfs;
          reorderOfs := reorderOfs + p.type.size
        END;
        p := p.next
      END;
      p := ORB.topScope.next;
      WHILE p # NIL DO
        IF (p.class = ORB.Var) & (p.lev = level) & (p.val > parblksize) &
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
    IF (sym >= ORS.const) & (sym <= ORS.var) THEN
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
      IF ~MethodSigMatch(type, bm.type) THEN
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
    ORS.Get(sym);
    IF sym = ORS.init THEN
      (* initialiser (DDR-003/004): allocates at the call site *)
      isInit := TRUE; ORS.Get(sym)
    END;
    IF sym = ORS.times THEN
      ORS.Get(sym); intProc := TRUE
    END;
    IF sym = ORS.lparen THEN
      (* receiver section: PROCEDURE (r: T) M ... (DDR-001/007) *)
      hasRcv := TRUE;
      ORS.Get(sym);
      IF sym = ORS.var THEN ORS.Get(sym); rcvcl := ORB.Par
      ELSE rcvcl := ORB.Var
      END;
      IF sym = ORS.ident THEN
        ORS.CopyId(rcvname); ORS.Get(sym)
      ELSE ORS.Mark("receiver name expected")
      END;
      Check(ORS.colon, "no :");
      IF sym = ORS.ident THEN
        qualident(tobj);
        IF tobj.class = ORB.Typ THEN
          rcvtyp := tobj.type;
          rtypname := tobj.name
        ELSE ORS.Mark("receiver type expected")
        END
      ELSE ORS.Mark("receiver type expected")
      END;
      Check(ORS.rparen, "no )");
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
      IF level # 0 THEN
        ORS.Mark("methods must be declared at module level"); rec := NIL
      END
    END;
    IF isInit THEN
      IF ~hasRcv THEN ORS.Mark("INIT requires a receiver")
      ELSIF rcvcl # ORB.Var THEN
        ORS.Mark("initialiser receiver must be a pointer, not VAR"); rec := NIL
      END
    END;
    IF sym = ORS.ident THEN
      ORS.CopyId(procid);
      ORS.Get(sym);
      IF hasRcv THEN
        (* type-bound: named in the record's method list only *)
        NEW(proc); proc.name := procid; proc.class := ORB.Meth
      ELSE
        ORB.NewObj(proc, procid, ORB.Const)
      END;
      IF intProc THEN parblksize := 12 ELSE parblksize := 0 END;
      NEW(type);
      type.form := ORB.Proc; type.size := 4;
      proc.type := type; proc.val := -1; proc.lev := level;
      CheckExport(proc.expo);
      IF proc.expo & ~hasRcv THEN proc.exno := exno; INC(exno) END;
      ORB.OpenScope;
      INC(level);
      type.base := ORB.noType;
      (* SUPER context: this body's receiver — cleared for plain
         procedures, including ones nested inside a method *)
      savedRcv := CurRcv; savedRec := CurRcvRec;
      savedIsInit := CurIsInit; savedSuperInit := SuperInitCalled;
      CurRcv := NIL; CurRcvRec := NIL;
      CurIsInit := FALSE; SuperInitCalled := FALSE;
      IF hasRcv THEN
        (* the receiver is the hidden first parameter *)
        type.mthd := TRUE;
        ORB.NewObj(rp, rcvname, rcvcl);
        rp.type := rcvtyp; rp.lev := level; rp.rdo := FALSE; rp.val := 1;
        IF rcvcl = ORB.Par THEN parblksize := parblksize + 2 * WordSize
        ELSE parblksize := parblksize + WordSize
        END;
        IF rec # NIL THEN
          CurRcv := rp; CurRcvRec := rec; CurIsInit := isInit
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
      IF sym = ORS.override THEN
        ORS.Get(sym);
        IF ~hasRcv THEN ORS.Mark("OVERRIDE requires a receiver") END;
        IF isInit THEN ORS.Mark("INIT and OVERRIDE are mutually exclusive") END;
        isOverride := TRUE
      END;
      Check(ORS.semicolon, "no ;");
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
      IF sym = ORS.procedure THEN
        L := 0;
        ORG.FJump(L);
        REPEAT
          ProcedureDecl;
          Check(ORS.semicolon, "no ;")
        UNTIL sym # ORS.procedure;
        ORG.FixOne(L);
        IF proc.class # ORB.Meth THEN proc.val := ORG.Here() END;
        proc.type.dsc := ORB.topScope.next
      END;
      type.size := locblksize;
      ORG.Enter(proc, ORB.topScope.next, parblksize, locblksize, intProc);
      IF sym = ORS.begin THEN
        ORS.Get(sym);
        StatSequence
      END;
      IF isInit THEN
        (* the constructed instance is returned implicitly *)
        IF sym = ORS.return THEN
          ORS.Mark("initialiser has no RETURN");
          ORS.Get(sym);
          expression(x)   (* recover past the expression *)
        END;
        IF (type.base.form # ORB.NoTyp) & (type.dsc # NIL) THEN
          ORG.MakeItem(x, type.dsc, level)   (* the receiver *)
        ELSE ORG.MakeConstItem(x, ORB.noType, 0)
        END
      ELSIF sym = ORS.return THEN
        ORS.Get(sym);
        IF type.base.form # ORB.NoTyp THEN
          expression(x);
          (* mixed integer widths permitted, consistent with assignment *)
          IF ~CompTypes(type.base, x.type, FALSE) &
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
      DEC(level);
      Check(ORS.end, "no END");
      IF sym = ORS.ident THEN
        IF ORS.id # procid THEN ORS.Mark("no match") END;
        ORS.Get(sym)
      ELSE ORS.Mark("no proc id")
      END;
      (* DDR-003: a derived initialiser must chain to a base initialiser
         whenever one is visible *)
      IF isInit & (rec # NIL) & (rec.base # NIL) &
         ORB.HasVisibleInits(rec.base) & ~SuperInitCalled THEN
        ORS.Mark("initialiser must call a base initialiser via SUPER")
      END;
      CurRcv := savedRcv; CurRcvRec := savedRec;
      CurIsInit := savedIsInit; SuperInitCalled := savedSuperInit
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
               EqualSignatures(p0.type, p1.type))) THEN
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
              Out.WriteString("  "); Out.WriteString(obj.name);
              Out.WriteString(" does not implement ");
              IF im.intfc.typobj # NIL THEN
                Out.WriteString(im.intfc.typobj.name); Out.WriteString(".")
              END;
              Out.WriteString(m.name); Out.Ln();
              ORS.Mark("interface not implemented")
            ELSIF ~IfaceSigMatch(rm.type, m.type) THEN
              Out.WriteString("  "); Out.WriteString(obj.name);
              Out.WriteString("."); Out.WriteString(m.name);
              Out.WriteString(": signature differs from interface"); Out.Ln();
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
    IF sym = ORS.ident THEN
      ORS.CopyId(impid);
      ORS.Get(sym);
      IF sym = ORS.becomes THEN
        ORS.Get(sym);
        IF sym = ORS.ident THEN
          ORS.CopyId(impid1); ORS.Get(sym)
        ELSE ORS.Mark("id expected"); impid1 := impid
        END
      ELSE impid1 := impid
      END;
      ORB.Import(impid, impid1)
    ELSE ORS.Mark("id expected")
    END
  END Import;

  PROCEDURE Module;
    VAR key: LONGINT;
  BEGIN
    key := 0;
    Out.WriteString("  compiling ");
    ORS.Get(sym);
    IF sym = ORS.module THEN
      ORS.Get(sym);
      dc := 0;
      ORB.OpenScope;
      IF sym = ORS.ident THEN
        ORS.CopyId(modid);
        ORS.Get(sym);
        Out.WriteString(modid)
      ELSE ORS.Mark("identifier expected")
      END;
      Check(ORS.semicolon, "no ;");
      level := 0; exno := 1;
      IF sym = ORS.import THEN
        ORS.Get(sym);
        Import;
        WHILE sym = ORS.comma DO
          ORS.Get(sym);
          Import
        END;
        Check(ORS.semicolon, "; missing")
      END;
      ORG.Open(modid, VERSION);
      Declarations(dc, 0);
      ORG.SetDataSize(dc);
      WHILE sym = ORS.procedure DO
        ProcedureDecl;
        Check(ORS.semicolon, "no ;")
      END;
      CheckConformance;   (* DDR-008: all methods are declared by now *)
      ORG.Header;
      IF sym = ORS.begin THEN
        ORS.Get(sym);
        StatSequence
      END;
      Check(ORS.end, "no END");
      IF sym = ORS.ident THEN
        IF ORS.id # modid THEN ORS.Mark("no match") END;
        ORS.Get(sym)
      ELSE ORS.Mark("identifier missing")
      END;
      IF sym # ORS.period THEN ORS.Mark("period missing")
      ELSE
        ORS.Get(sym);
        IF sym # ORS.eot THEN ORS.Mark("garbage after module") END
      END;
      IF ORS.errcnt = 0 THEN
        ORB.SetVarSize(dc);
        ORB.Export(modid, newSF, key);
        IF newSF THEN Out.WriteString(" new symbol file") END
      END;
      IF ORS.errcnt = 0 THEN
        ORG.Close(modid, key, exno);
        Out.WriteString("  key "); Out.WriteInt(key)
      ELSE
        Out.Ln();
        Out.WriteString("compilation FAILED")
      END;
      Out.Ln();
      ORB.CloseScope;
      pbsList := NIL
    ELSE ORS.Mark("must start with MODULE")
    END
  END Module;

  PROCEDURE Compile*(filename: ARRAY OF CHAR; forceNewSF: BOOLEAN);
  BEGIN
    ORB.SetSourceDirectory(filename);
    newSF := forceNewSF;
    Out.WriteString("Compiling ");
    Out.WriteString(filename); Out.Ln();
    IF ORS.Open(filename) THEN
      Module
    ELSE
      Out.WriteString("Error: cannot open ");
      Out.WriteString(filename); Out.Ln();
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
  NEW(dummy); dummy.class := ORB.Var; dummy.type := ORB.intType;
  expression := expression0;
  Type := Type0;
  FormalType := FormalType0;
  CurRcv := NIL; CurRcvRec := NIL;
  CurIsInit := FALSE; SuperInitCalled := FALSE
END ORP.
