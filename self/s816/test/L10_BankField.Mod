MODULE L10_BankField;
  (* SYSTEM.GET and PUT whose bank is a field through a pointer: the bank
     was loaded after the address, left in the pointer's register below
     it, and the pair was the address and whatever was above. Now the bank
     is spilled first and pulled in after the address (ORG.SpillBank,
     BankPair). A heap block written and read through its own bank. *)
  IMPORT SYSTEM, Out;

  TYPE
    B = POINTER TO BD; BD = RECORD c: ARRAY 64 OF CHAR END;
    R = POINTER TO RD; RD = RECORD bank, adr: INTEGER END;

  VAR b: B; r: R; ch: CHAR; n: INTEGER; arr: ARRAY 4 OF R; w: INTEGER;

  PROCEDURE Where(r: R; VAR c: ARRAY OF CHAR);
  BEGIN r.adr := SYSTEM.ADR(c); r.bank := SYSTEM.BANK(c)
  END Where;

  PROCEDURE Put(r: R; i: INTEGER; ch: CHAR);
  BEGIN SYSTEM.PUT(r.bank, r.adr + i, ch)
  END Put;

  PROCEDURE Get(r: R; i: INTEGER): CHAR;
    VAR ch: CHAR;
  BEGIN SYSTEM.GET(r.bank, r.adr + i, ch)
  RETURN ch
  END Get;

BEGIN NEW(b); NEW(r); Where(r, b.c); arr[2] := r;
  Put(r, 0, "h"); Out.Int(ORD(b.c[0]), 0); Out.Ln;            (* a parameter's field *)
  b.c[1] := "i"; Out.Int(ORD(Get(r, 1)), 0); Out.Ln;
  ch := "k"; SYSTEM.PUT(r.bank, r.adr + 3, ch); Out.Int(ORD(b.c[3]), 0); Out.Ln;   (* a global's *)
  n := 2; SYSTEM.PUT(arr[n].bank, arr[n].adr + 4, ORD("m") + n - 2); Out.Int(ORD(b.c[4]), 0); Out.Ln;   (* computed *)
  SYSTEM.GET(arr[n].bank, arr[n].adr + 1, ch); Out.Char(ch); Out.Ln;
  SYSTEM.PUT(r.bank, r.adr + 6, 1234H); SYSTEM.GET(r.bank, r.adr + 6, w); Out.Int(w, 0); Out.Ln
END L10_BankField.
