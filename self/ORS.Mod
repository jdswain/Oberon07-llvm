MODULE ORS; (* NW 19.9.93 / 15.3.2017  Scanner in Oberon-07.
   Self-hosted port of src/ORS.c (which was itself ported from this
   module's ancestor). Deltas from NW's original:
     - source text comes from the runtime Files module, not Oberon Texts;
     - error output goes to Out with the C port's "pos [line:col]" shape;
     - the OO-extension keywords WEAK, INIT, OVERRIDE, SUPER, INTERFACE,
       IMPLEMENTS (DDR-007/008) — token values match include/ORS.h. *)

  IMPORT SYSTEM, Files, Out;

  CONST IdLen* = 32;
    NKW = 40;  (*nof keywords*)
    maxExp = 38; stringBufSize = 256;

    (*lexical symbols*)
    null = 0; times* = 1; rdiv* = 2; div* = 3; mod* = 4;
    and* = 5; plus* = 6; minus* = 7; or* = 8; eql* = 9;
    neq* = 10; lss* = 11; geq* = 12; leq* = 13; gtr* = 14;
    (* NB: geq/leq/gtr differ from NW's original numbering — the C port
       swapped them and the backend's icmp mapping follows the C values *)
    in* = 15; is* = 16; arrow* = 17; period* = 18;
    char* = 20; int* = 21; real* = 22; false* = 23; true* = 24;
    nil* = 25; string* = 26; not* = 27; lparen* = 28; lbrak* = 29;
    lbrace* = 30; ident* = 31;
    if* = 32; while* = 34; repeat* = 35; case* = 36; for* = 37;
    comma* = 40; colon* = 41; becomes* = 42; upto* = 43; rparen* = 44;
    rbrak* = 45; rbrace* = 46; then* = 47; of* = 48; do* = 49;
    to* = 50; by* = 51; semicolon* = 52; end* = 53; bar* = 54;
    else* = 55; elsif* = 56; until* = 57; return* = 58;
    array* = 60; record* = 61; pointer* = 62; const* = 63; type* = 64;
    var* = 65; procedure* = 66; begin* = 67; import* = 68; module* = 69;
    eot* = 70;
    (* appended after eot, same strategy as the C port: tested by
       equality only, never by range *)
    weak* = 71; init* = 72; override* = 73; super* = 74;
    interface* = 75; implements* = 76;

  TYPE Ident* = ARRAY IdLen OF CHAR;
    KwName = ARRAY 12 OF CHAR;

  VAR ival*, slen*: LONGINT;  (*results of Get*)
    rval*: REAL;
    id*: Ident;  (*for identifiers*)
    str*: ARRAY stringBufSize OF CHAR;
    errcnt*: INTEGER;

    ch: CHAR;             (*last character read*)
    srcF: Files.File;
    srcR: Files.Rider;
    srcEof: BOOLEAN;
    srcPos: LONGINT;      (*chars consumed; points one past ch*)
    line, col: INTEGER;
    errpos: LONGINT;
    k: INTEGER;
    keyTab: ARRAY NKW OF
        RECORD sym: INTEGER; id: KwName END;

  PROCEDURE CopyId*(VAR ident: Ident);
  BEGIN ident := id
  END CopyId;

  (* count an error reported outside the scanner (imported VARs are
     read-only, so callers cannot INC(errcnt) directly) *)
  PROCEDURE CountError*;
  BEGIN INC(errcnt)
  END CountError;

  PROCEDURE Pos*(): LONGINT;
  BEGIN RETURN srcPos
  END Pos;

  PROCEDURE Mark*(msg: ARRAY OF CHAR);
    VAR p: LONGINT;
  BEGIN p := srcPos - 1;
    IF (p > errpos) & (errcnt < 25) THEN
      Out.WriteString("  pos "); Out.WriteInt(p);
      Out.WriteString(" ["); Out.WriteInt(line);
      Out.WriteString(":"); Out.WriteInt(col);
      Out.WriteString("]  "); Out.WriteString(msg); Out.Ln();
      INC(errcnt)
    END;
    errpos := p + 4
  END Mark;

  PROCEDURE Read;
    VAR b: BYTE;
  BEGIN
    IF srcEof THEN ch := 0X
    ELSE
      Files.ReadByte(srcR, b);
      IF srcR.eof THEN srcEof := TRUE; ch := 0X
      ELSE ch := CHR(b); INC(srcPos);
        IF ch = 0AX THEN INC(line); col := 0 ELSE INC(col) END
      END
    END
  END Read;

  PROCEDURE KwEqual(VAR a: Ident; VAR b: KwName): BOOLEAN;
    VAR i: INTEGER; r: BOOLEAN;
  BEGIN i := 0;
    WHILE (i < 12) & (a[i] = b[i]) & (a[i] # 0X) DO INC(i) END;
    IF i >= 12 THEN r := FALSE ELSE r := (a[i] = 0X) & (b[i] = 0X) END;
    RETURN r
  END KwEqual;

  PROCEDURE Identifier(VAR sym: INTEGER);
    VAR i, j: INTEGER;
  BEGIN i := 0;
    REPEAT
      IF i < IdLen-1 THEN id[i] := ch; INC(i) END;
      Read
    UNTIL (ch < "0") OR (ch > "9") & (ch < "A") OR (ch > "Z") & (ch < "a") OR (ch > "z");
    id[i] := 0X;
    sym := ident; j := 0;
    WHILE j < k DO
      IF KwEqual(id, keyTab[j].id) THEN sym := keyTab[j].sym; j := k
      ELSE INC(j)
      END
    END
  END Identifier;

  PROCEDURE String;
    VAR i: INTEGER;
  BEGIN i := 0; Read;
    WHILE ~srcEof & (ch # 22X) & (ch # 0DX) & (ch # 0AX) DO
      IF i < stringBufSize-1 THEN str[i] := ch; INC(i)
      ELSE Mark("string too long")
      END;
      Read
    END;
    str[i] := 0X; INC(i); slen := i;
    IF ch = 22X THEN Read ELSE Mark("string not terminated") END
  END String;

  PROCEDURE HexString;
    VAR i, m, n: INTEGER;
  BEGIN i := 0; Read;
    WHILE ~srcEof & (ch # "$") DO
      WHILE ~srcEof & (ch <= " ") DO Read END;  (*skip*)
      IF ("0" <= ch) & (ch <= "9") THEN m := ORD(ch) - 30H
      ELSIF ("A" <= ch) & (ch <= "F") THEN m := ORD(ch) - 37H
      ELSE m := 0; Mark("hexdig expected")
      END;
      Read;
      IF ("0" <= ch) & (ch <= "9") THEN n := ORD(ch) - 30H
      ELSIF ("A" <= ch) & (ch <= "F") THEN n := ORD(ch) - 37H
      ELSE n := 0; Mark("hexdig expected")
      END;
      IF i < stringBufSize THEN str[i] := CHR(m*10H + n); INC(i)
      ELSE Mark("string too long")
      END;
      Read
    END;
    Read; slen := i  (*no 0X appended!*)
  END HexString;

  PROCEDURE Ten(e: LONGINT): REAL;
    VAR x, t: REAL;
  BEGIN x := 1.0; t := 10.0;
    WHILE e > 0 DO
      IF ODD(e) THEN x := t * x END;
      t := t * t; e := e DIV 2
    END;
    RETURN x
  END Ten;

  PROCEDURE Number(VAR sym: INTEGER);
    CONST max = 2147483647 (*2^31 - 1*);
    VAR i, k, e, n, s, h: LONGINT; x: REAL;
      d: ARRAY 16 OF INTEGER;
      negE: BOOLEAN;
  BEGIN ival := 0; i := 0; n := 0; k := 0;
    REPEAT
      IF n < 16 THEN d[n] := ORD(ch)-30H; INC(n) ELSE Mark("too many digits"); n := 0 END;
      Read
    UNTIL (ch < "0") OR (ch > "9") & (ch < "A") OR (ch > "F");
    IF (ch = "H") OR (ch = "R") OR (ch = "X") THEN  (*hex*)
      REPEAT h := d[i];
        IF h >= 10 THEN h := h-7 END;
        k := k*10H + h; INC(i) (*no overflow check*)
      UNTIL i = n;
      IF ch = "X" THEN sym := char;
        IF k < 100H THEN ival := k ELSE Mark("illegal value"); ival := 0 END
      ELSIF ch = "R" THEN sym := real; rval := SYSTEM.VAL(REAL, k)
      ELSE sym := int; ival := k
      END;
      Read
    ELSIF ch = "." THEN
      Read;
      IF ch = "." THEN (*double dot*) ch := 7FX;  (*decimal integer*)
        REPEAT
          IF d[i] < 10 THEN
            IF k <= (max-d[i]) DIV 10 THEN k := k *10 + d[i] ELSE Mark("too large"); k := 0 END
          ELSE Mark("bad integer")
          END;
          INC(i)
        UNTIL i = n;
        sym := int; ival := k
      ELSE (*real number*) x := 0.0; e := 0;
        REPEAT  (*integer part*) x := x * 10.0 + FLT(d[i]); INC(i) UNTIL i = n;
        WHILE (ch >= "0") & (ch <= "9") DO  (*fraction*)
          x := x * 10.0 + FLT(ORD(ch) - 30H); DEC(e); Read
        END;
        IF (ch = "E") OR (ch = "D") THEN  (*scale factor*)
          Read; s := 0;
          IF ch = "-" THEN negE := TRUE; Read
          ELSE negE := FALSE;
            IF ch = "+" THEN Read END
          END;
          IF (ch >= "0") & (ch <= "9") THEN
            REPEAT s := s*10 + ORD(ch)-30H; Read
            UNTIL (ch < "0") OR (ch > "9");
            IF negE THEN e := e-s ELSE e := e+s END
          ELSE Mark("digit?")
          END
        END;
        IF e < 0 THEN
          IF e >= -maxExp THEN x := x / Ten(-e) ELSE x := 0.0 END
        ELSIF e > 0 THEN
          IF e <= maxExp THEN x := Ten(e) * x ELSE x := 0.0; Mark("too large") END
        END;
        sym := real; rval := x
      END
    ELSE  (*decimal integer*)
      REPEAT
        IF d[i] < 10 THEN
          IF k <= (max-d[i]) DIV 10 THEN k := k*10 + d[i] ELSE Mark("too large"); k := 0 END
        ELSE Mark("bad integer")
        END;
        INC(i)
      UNTIL i = n;
      sym := int; ival := k
    END
  END Number;

  PROCEDURE comment;
  BEGIN Read;
    REPEAT
      WHILE ~srcEof & (ch # "*") DO
        IF ch = "(" THEN Read;
          IF ch = "*" THEN comment END
        ELSE Read
        END
      END;
      WHILE ch = "*" DO Read END
    UNTIL (ch = ")") OR srcEof;
    IF ~srcEof THEN Read ELSE Mark("unterminated comment") END
  END comment;

  PROCEDURE Get*(VAR sym: INTEGER);
  BEGIN
    REPEAT
      WHILE ~srcEof & (ch <= " ") DO Read END;
      IF srcEof THEN sym := eot
      ELSIF ch < "A" THEN
        IF ch < "0" THEN
          IF ch = 22X THEN String; sym := string
          ELSIF ch = "#" THEN Read; sym := neq
          ELSIF ch = "$" THEN HexString; sym := string
          ELSIF ch = "&" THEN Read; sym := and
          ELSIF ch = "(" THEN Read;
            IF ch = "*" THEN sym := null; comment ELSE sym := lparen END
          ELSIF ch = ")" THEN Read; sym := rparen
          ELSIF ch = "*" THEN Read; sym := times
          ELSIF ch = "+" THEN Read; sym := plus
          ELSIF ch = "," THEN Read; sym := comma
          ELSIF ch = "-" THEN Read; sym := minus
          ELSIF ch = "." THEN Read;
            IF ch = "." THEN Read; sym := upto ELSE sym := period END
          ELSIF ch = "/" THEN Read; sym := rdiv
          ELSE Read; (* ! % ' *) sym := null
          END
        ELSIF ch < ":" THEN Number(sym)
        ELSIF ch = ":" THEN Read;
          IF ch = "=" THEN Read; sym := becomes ELSE sym := colon END
        ELSIF ch = ";" THEN Read; sym := semicolon
        ELSIF ch = "<" THEN Read;
          IF ch = "=" THEN Read; sym := leq ELSE sym := lss END
        ELSIF ch = "=" THEN Read; sym := eql
        ELSIF ch = ">" THEN Read;
          IF ch = "=" THEN Read; sym := geq ELSE sym := gtr END
        ELSE (* ? @ *) Read; sym := null
        END
      ELSIF ch < "[" THEN Identifier(sym)
      ELSIF ch < "a" THEN
        IF ch = "[" THEN sym := lbrak
        ELSIF ch = "]" THEN sym := rbrak
        ELSIF ch = "^" THEN sym := arrow
        ELSE (* _ ` *) sym := null
        END;
        Read
      ELSIF ch < "{" THEN Identifier(sym) ELSE
        IF ch = "{" THEN sym := lbrace
        ELSIF ch = "}" THEN sym := rbrace
        ELSIF ch = "|" THEN sym := bar
        ELSIF ch = "~" THEN sym := not
        ELSIF ch = 7FX THEN sym := upto
        ELSE sym := null
        END;
        Read
      END
    UNTIL sym # null
  END Get;

  (* Open the source file and prime the scanner. FALSE if unreadable. *)
  PROCEDURE Open*(name: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    srcF := Files.Old(name);
    srcEof := srcF = NIL;
    errpos := 0; errcnt := 0; srcPos := 0; line := 1; col := 0;
    IF srcF # NIL THEN
      Files.Set(srcR, srcF, 0);
      Read
    ELSE ch := 0X
    END;
    RETURN srcF # NIL
  END Open;

  PROCEDURE EnterKW(sym: INTEGER; name: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    keyTab[k].sym := sym; i := 0;
    WHILE (i < LEN(name)) & (i < 11) & (name[i] # 0X) DO
      keyTab[k].id[i] := name[i]; INC(i)
    END;
    keyTab[k].id[i] := 0X;
    INC(k)
  END EnterKW;

BEGIN k := 0;
  EnterKW(if, "IF");
  EnterKW(do, "DO");
  EnterKW(of, "OF");
  EnterKW(or, "OR");
  EnterKW(to, "TO");
  EnterKW(in, "IN");
  EnterKW(is, "IS");
  EnterKW(by, "BY");
  EnterKW(end, "END");
  EnterKW(nil, "NIL");
  EnterKW(var, "VAR");
  EnterKW(div, "DIV");
  EnterKW(mod, "MOD");
  EnterKW(for, "FOR");
  EnterKW(else, "ELSE");
  EnterKW(then, "THEN");
  EnterKW(true, "TRUE");
  EnterKW(type, "TYPE");
  EnterKW(case, "CASE");
  EnterKW(init, "INIT");
  EnterKW(weak, "WEAK");
  EnterKW(elsif, "ELSIF");
  EnterKW(false, "FALSE");
  EnterKW(array, "ARRAY");
  EnterKW(begin, "BEGIN");
  EnterKW(const, "CONST");
  EnterKW(until, "UNTIL");
  EnterKW(while, "WHILE");
  EnterKW(super, "SUPER");
  EnterKW(record, "RECORD");
  EnterKW(repeat, "REPEAT");
  EnterKW(return, "RETURN");
  EnterKW(import, "IMPORT");
  EnterKW(module, "MODULE");
  EnterKW(pointer, "POINTER");
  EnterKW(procedure, "PROCEDURE");
  EnterKW(override, "OVERRIDE");
  EnterKW(interface, "INTERFACE");
  EnterKW(implements, "IMPLEMENTS")
END ORS.
