MODULE ORGE FRIENDS ORG; (* 65C816 code generator, its expressions: type
   descriptors and type tests, arithmetic, sets, relations, parameters,
   FOR and CASE. The second of ORG's three modules (ORGI, ORGE, ORG). *)

  IMPORT OCG, ORS, ORB, ORGFP, ORGI;

  VAR
    tdx*: LONGINT;
    relmap*: ARRAY 6 OF INTEGER;
    tdFixupC*: INTEGER;
    (* deferred type descriptors (classic Oberon-2 single-pass): types are
       recorded at declaration and their descriptors generated at Close,
       placed after the variables + strings so the vtable size is known.
       New/TypeTest emit T.len as a forward fixup patched in GenTDs. *)
    tdList*: ARRAY ORGI.maxTD OF ORB.Type;  (* kept out of wa: array of ptrs (see ORGW.ModArrays) *)
    tdListC*: INTEGER;
    tdBase: LONGINT;                              (* var-relative base of TD region *)
    tdRefLoc: ARRAY ORGI.maxTD OF LONGINT;        (* code sites needing a T.len *)
    tdRefTyp: ARRAY ORGI.maxTD OF ORB.Type;
    tdRefC*: INTEGER;
    vtFixC*: INTEGER;
    slotMeth: ARRAY ORGI.maxMeth OF ORB.Object;   (* method per vtable slot *)
    slotMno: ARRAY ORGI.maxMeth OF LONGINT;       (* its defining type's mno *)
    itabRec*, itabIfc*: ARRAY ORGI.maxItab OF ORB.Type;  (* per-(record,interface) itables *)
    itabOff: ARRAY ORGI.maxItab OF LONGINT;       (* var-relative offset, set in GenTDs *)
    itabC*: INTEGER;
    itabRefLoc*: ARRAY ORGI.maxItabRef OF LONGINT;  (* PtrToIface sites needing an offset *)
    itabRefIdx*: ARRAY ORGI.maxItabRef OF INTEGER;
    itabRefC*: INTEGER;
    forY: ORGI.Item;                           (* For0's start value, in a register, for For1 *)


  (* --- type descriptors --- *)
  (* T's ancestors from level 0 (the base record) to T itself, as Wirth's:
     an object's type tests at any level, its own included, read the entry
     of that level *)
  PROCEDURE Q(T: ORB.Type; VAR dcw: LONGINT);
  BEGIN
    IF T.base # NIL THEN Q(T.base, dcw) END;
    ORGI.wa.data[dcw] := T.len; ORGI.wa.data[dcw + 1] := 0;
    IF tdFixupC >= LEN(ORGI.wa.tdFixupOff) THEN ORS.Mark("too many type descriptor fixups")
    ELSE
      ORGI.wa.tdFixupOff[tdFixupC] := tdBase + dcw * 2; ORGI.wa.tdFixupMno[tdFixupC] := T.mno;
      tdFixupC := tdFixupC + 1
    END;
    dcw := dcw + 2
  END Q;

  PROCEDURE FindPtrFlds(typ: ORB.Type; off: LONGINT; VAR dcw: LONGINT);
    VAR fld: ORB.Object; i, s: LONGINT;
  BEGIN
    IF (typ.form = ORB.Pointer) & typ.weak THEN   (* WEAK: not traced *)
    ELSIF (typ.form = ORB.Pointer) OR (typ.form = ORB.NilTyp)
        OR (typ.form = ORB.Intfc) THEN   (* an interface value's object: its first 4 bytes *)
      ORGI.wa.data[dcw] := off; dcw := dcw + 1
    ELSIF typ.form = ORB.Record THEN
      fld := typ.dsc;
      WHILE fld # NIL DO
        FindPtrFlds(fld.type, fld.val + off, dcw); fld := fld.next
      END
    ELSIF typ.form = ORB.Array THEN
      s := typ.base.size; i := 0;
      WHILE i < typ.len DO
        FindPtrFlds(typ.base, i * s + off, dcw); i := i + 1
      END
    END
  END FindPtrFlds;

  (* BuildTD only RECORDS the type. The descriptor is generated at Close by
     GenTDs, once every method (hence the vtable size) is known — the classic
     Oberon-2 single-pass discipline, matching the LLVM backend here. *)
  PROCEDURE BuildTD*(T: ORB.Type; VAR dc: LONGINT);
  BEGIN
    IF tdListC < ORGI.maxTD THEN tdList[tdListC] := T; tdListC := tdListC + 1
    ELSE ORS.Mark("too many record types")
    END
  END BuildTD;

  (* Emit `ADC #<T's descriptor offset>`. Own-module T.len is not known until
     GenTDs, so leave a placeholder + forward fixup; imported types already
     carry their offset in the .smb. *)
  PROCEDURE emitTDLen*(T: ORB.Type);
  BEGIN
    IF T.mno <= 0 THEN
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, 0);
      IF tdRefC < ORGI.maxTD THEN
        tdRefLoc[tdRefC] := OCG.Here() - 2; tdRefTyp[tdRefC] := T;
        tdRefC := tdRefC + 1
      ELSE ORS.Mark("too many descriptor refs")
      END
    ELSE OCG.gen1(OCG.ADC * 32 + OCG.mImm, T.len)
    END
  END emitTDLen;

  (* Fill T's vtable words (base first, so a derived override wins the slot).
     Slots hold the method's CODE OFFSET (relative to the module code base) —
     a compile-time constant, so no relocation. *)
  (* Record the most-derived method per slot (base first so a derived
     override wins) together with its defining type's mno, so GenTDs can tell
     an own method (fill its code offset) from an imported inherited one
     (leave a loader vtable-fixup). *)
  PROCEDURE fillVt(anc: ORB.Type; nm: LONGINT);
    VAR m: ORB.Object;
  BEGIN
    IF anc.base # NIL THEN fillVt(anc.base, nm) END;
    m := anc.meth;
    WHILE m # NIL DO
      IF (m.val >= 0) & (m.val < nm) THEN
        slotMeth[m.val] := m; slotMno[m.val] := anc.mno
      END;
      m := m.next
    END
  END fillVt;

  (* Fill an itable: entry k (k = interface method's index m.val) holds the
     record's vtable slot for the method of the same name. Slot indices are
     stable across overrides, so this constant table works for every extension
     hidden behind the interface, from any module. *)
  PROCEDURE fillItab(ifc, rec: ORB.Type; nm, vtword: LONGINT);
    VAR m, rm: ORB.Object;
  BEGIN
    m := ifc.meth;
    WHILE m # NIL DO
      IF (m.val >= 0) & (m.val < nm) THEN
        rm := ORB.FindMeth(rec, m.name);
        IF rm # NIL THEN ORGI.wa.data[vtword + m.val] := rm.val END
      END;
      m := m.next
    END
  END fillItab;

  (* Generate every recorded descriptor into wa.data[], placed at var-relative
     offset tdBase = varsize + strx (after the variables and strings), and
     patch the forward T.len references. Called from Close. *)
  PROCEDURE GenTDs;
    VAR i, dcw, k, s, nm: LONGINT; T: ORB.Type;
  BEGIN
    tdBase := ORGI.varsize + ORGI.strx; dcw := 0; i := 0;
    WHILE i < tdListC DO
      T := tdList[i];
      T.len := tdBase + dcw * 2;
      ORGI.wa.data[dcw] := T.size; dcw := dcw + 1;
      k := T.nofpar;
      IF k >= ORGI.ExtLevels THEN ORS.Mark("ext level too large")
      ELSE
        Q(T, dcw); k := k + 1;
        WHILE k < ORGI.ExtLevels DO
          ORGI.wa.data[dcw] := 0FFFFH; ORGI.wa.data[dcw + 1] := 0FFFFH;
          dcw := dcw + 2; k := k + 1
        END
      END;
      (* method vtable: nofmeth (TOTAL incl. inherited), then that many
         4-byte slots holding the code address and bank of the most-derived
         impl, which the loader fills: an own method (mno=0) as module_base
         + its code offset, in this module's bank; an imported inherited one
         (mno>0) via (mno, exno), in that module's bank. Dispatch just reads
         the slot, so an imported object's method is reachable from any
         module in any bank. *)
      nm := ORB.TotalMeths(T);
      IF nm > ORGI.maxMeth THEN ORS.Mark("too many methods"); nm := 0 END;
      ORGI.wa.data[dcw] := nm; dcw := dcw + 1;
      IF nm > 0 THEN
        s := 0; WHILE s < nm DO slotMeth[s] := NIL; slotMno[s] := 0; s := s + 1 END;
        fillVt(T, nm);
        s := 0;
        WHILE s < nm DO
          ORGI.wa.data[dcw + 2 * s + 1] := 0;                    (* the bank, the loader's *)
          IF slotMeth[s] = NIL THEN ORGI.wa.data[dcw + 2 * s] := 0   (* abstract: no impl *)
          ELSE
            IF vtFixC >= ORGI.maxVtFix THEN ORS.Mark("too many vtable fixups")
            ELSE
              ORGI.wa.vtFixOff[vtFixC] := tdBase + (dcw + 2 * s) * 2;
              IF slotMno[s] <= 0 THEN   (* own method: slot = base + offset *)
                ORGI.wa.data[dcw + 2 * s] := slotMeth[s].backend;
                ORGI.wa.vtFixMno[vtFixC] := 0; ORGI.wa.vtFixExno[vtFixC] := 0
              ELSE                      (* imported inherited: loader resolves *)
                ORGI.wa.data[dcw + 2 * s] := 0;
                ORGI.wa.vtFixMno[vtFixC] := slotMno[s];
                ORGI.wa.vtFixExno[vtFixC] := slotMeth[s].exno
              END;
              vtFixC := vtFixC + 1
            END
          END;
          s := s + 1
        END;
        dcw := dcw + 2 * nm
      END;
      FindPtrFlds(T, 0, dcw);
      ORGI.wa.data[dcw] := 0FFFFH; dcw := dcw + 1;
      i := i + 1
    END;
    (* interface itables: for each (record, interface), one 2-byte entry per
       interface method holding the record's vtable slot for that method
       (indices, so overrides and cross-module callers stay correct). *)
    i := 0;
    WHILE i < itabC DO
      itabOff[i] := tdBase + dcw * 2;
      nm := itabIfc[i].nofmeth;
      s := 0; WHILE s < nm DO ORGI.wa.data[dcw + s] := 0; s := s + 1 END;
      fillItab(itabIfc[i], itabRec[i], nm, dcw);
      dcw := dcw + nm;
      i := i + 1
    END;
    tdx := dcw;
    IF tdx >= LEN(ORGI.wa.data) THEN ORS.Mark("type descriptors too large"); tdx := 0 END;
    i := 0;
    WHILE i < tdRefC DO
      OCG.Patch(tdRefLoc[i], tdRefTyp[i].len MOD 100H);
      OCG.Patch(tdRefLoc[i] + 1, tdRefTyp[i].len DIV 100H MOD 100H);
      i := i + 1
    END;
    i := 0;
    WHILE i < itabRefC DO
      OCG.Patch(itabRefLoc[i], itabOff[itabRefIdx[i]] MOD 100H);
      OCG.Patch(itabRefLoc[i] + 1, itabOff[itabRefIdx[i]] DIV 100H MOD 100H);
      i := i + 1
    END
  END GenTDs;

  (* Generate the deferred descriptors and assign every record's T.len. ORP
     calls this after the body (so varsize/strx and all New/TypeTest fixup
     sites are final) but BEFORE ORB.Export, so the .smb carries the real TD
     offsets that importing modules need for cross-module type tests / NEW. *)
  PROCEDURE FinalizeTDs*;
  BEGIN GenTDs
  END FinalizeTDs;

  PROCEDURE TypeTest*(VAR x: ORGI.Item; T: ORB.Type; varpar, isguard: BOOLEAN);
    VAR offset, sb, nilSkip: LONGINT;
  BEGIN
    IF T = NIL THEN
      IF x.mode >= ORGI.Reg THEN ORGI.RH := ORGI.RH - 1 END;
      ORGI.SetCC(x, ORGI.AL)
    ELSIF varpar THEN
      ORGI.Set16(TRUE, TRUE);
      ORGI.incR; ORGI.incR;
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 4 + ORGI.frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2));
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 6 + ORGI.frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 1));
      offset := 2 + T.nofpar * 4;
      OCG.Clc;
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2));
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, offset);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 1));
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 1));
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, ORGI.RegAddr(ORGI.RH - 2));
      OCG.Pha;
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, 2);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, ORGI.RegAddr(ORGI.RH - 2));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 1));
      OCG.Pla;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2));
      sb := ORGI.GetSB(-T.mno);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, sb);
      OCG.Clc;
      emitTDLen(T);
      OCG.gen1(OCG.EOR * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.BankOf(sb));   (* the descriptor's bank *)
      OCG.gen1(OCG.EOR * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 1));
      OCG.gen1(OCG.ORA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2));
      ORGI.RH := ORGI.RH - 2;
      IF isguard THEN
        IF ORGI.check THEN ORGI.Trap(ORGI.EQ, 2) END
      ELSE x.origType := ORB.intType; ORGI.SetCC(x, ORGI.EQ)
      END
    ELSE
      ORGI.load(x);
      IF x.type.form = ORB.Intfc THEN ORGI.RH := x.r + 2 END;   (* the object; the itable dropped *)
      ORGI.Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      OCG.gen1(OCG.ORA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
      nilSkip := ORGI.emitFwdBranch(OCG.BEQ);
      ORGI.incR; ORGI.incR;
      OCG.Sec;
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      OCG.gen1(OCG.SBC * 32 + OCG.mImm, 4);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
      OCG.gen1(OCG.SBC * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 1));
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, ORGI.RegAddr(ORGI.RH - 2));
      OCG.Pha;
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, 2);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, ORGI.RegAddr(ORGI.RH - 2));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 1));
      OCG.Pla;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2));
      offset := 2 + T.nofpar * 4;
      OCG.Clc;
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2));
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, offset);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 1));
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 1));
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, ORGI.RegAddr(ORGI.RH - 2));
      OCG.Pha;
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, 2);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, ORGI.RegAddr(ORGI.RH - 2));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 1));
      OCG.Pla;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2));
      sb := ORGI.GetSB(-T.mno);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, sb);
      OCG.Clc;
      emitTDLen(T);
      OCG.gen1(OCG.EOR * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.BankOf(sb));   (* the descriptor's bank *)
      OCG.gen1(OCG.EOR * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 1));
      OCG.gen1(OCG.ORA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2));
      ORGI.RH := ORGI.RH - 2;
      ORGI.patch(nilSkip);
      IF isguard THEN
        IF ORGI.check THEN ORGI.Trap(ORGI.EQ, 2) END
      ELSE x.origType := ORB.intType; ORGI.SetCC(x, ORGI.EQ); ORGI.RH := ORGI.RH - 2
      END
    END
  END TypeTest;

  (* --- arithmetic --- *)
  PROCEDURE Neg*(VAR x: ORGI.Item);
  BEGIN
    IF ORGI.IsLong(x.type) THEN
      IF x.mode = ORB.Const THEN x.a := -x.a
      ELSE
        ORGI.load(x); ORGI.longNeg(x.r)                              (* two's complement 32-bit *)
      END
    ELSIF x.type.form = ORB.Int THEN
      ORGI.Set16(TRUE, TRUE);
      IF x.mode = ORB.Const THEN x.a := -x.a
      ELSE
        ORGI.load(x);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mImm, 1);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r))
      END
    ELSIF x.type.form = ORB.Real THEN
      IF x.mode = ORB.Const THEN x.a := EOR(x.a, 80000000H)
      ELSE
        ORGI.load(x); ORGI.Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
        OCG.gen1(OCG.EOR * 32 + OCG.mImm, 8000H);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1))
      END
    ELSE (* Set *)
      IF x.mode = ORB.Const THEN x.a := -x.a - 1
      ELSE
        ORGI.load(x);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r))
      END
    END
  END Neg;

  (* 32-bit LONGINT dst := xr (add: Clc) or (sub: Sec) yr, two-word.
     Each word is read before dst is written, so dst may alias xr or yr —
     callers put dst at the lower operand pair to compact the result. *)
  PROCEDURE longAddReg(dst, xr, yr, aluOp: LONGINT; sub: BOOLEAN);
  BEGIN
    ORGI.Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(xr));
    IF sub THEN OCG.Sec ELSE OCG.Clc END;
    OCG.gen1(aluOp * 32 + OCG.mDP, ORGI.RegAddr(yr));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(dst));
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(xr + 1));
    OCG.gen1(aluOp * 32 + OCG.mDP, ORGI.RegAddr(yr + 1));       (* carry propagates *)
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(dst + 1))
  END longAddReg;

  (* 32-bit LONGINT add/subtract of an immediate constant c into two-word dst. *)
  PROCEDURE longAddImm(dst, c, aluOp: LONGINT; sub: BOOLEAN);
  BEGIN
    ORGI.Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(dst));
    IF sub THEN OCG.Sec ELSE OCG.Clc END;
    OCG.gen1(aluOp * 32 + OCG.mImm, ORGI.Lo16(c));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(dst));
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(dst + 1));
    OCG.gen1(aluOp * 32 + OCG.mImm, ORGI.Hi16(c));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(dst + 1))
  END longAddImm;

  PROCEDURE AddOp*(op: LONGINT; VAR x, y: ORGI.Item);
    VAR destR: LONGINT;
  BEGIN
    ORGI.promoteConst(x, y); ORGI.widenToConst(x, y);
    IF op = ORS.plus THEN
      IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a + y.a
      ELSIF x.mode = ORB.Const THEN
        ORGI.load(y);
        IF x.a # 0 THEN
          IF ORGI.IsLong(y.type) THEN longAddImm(y.r, x.a, OCG.ADC, FALSE)
          ELSIF y.type.form = ORB.Int THEN
            ORGI.Set16(TRUE, TRUE);
            OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r));
            OCG.Clc;
            OCG.gen1(OCG.ADC * 32 + OCG.mImm, x.a);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(y.r))
          END
        END;
        x.mode := y.mode; x.r := y.r
      ELSIF y.mode = ORB.Const THEN
        ORGI.load(x);
        IF y.a # 0 THEN
          IF ORGI.IsLong(x.type) THEN longAddImm(x.r, y.a, OCG.ADC, FALSE)
          ELSIF x.type.form = ORB.Int THEN
            ORGI.Set16(TRUE, TRUE);
            OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
            OCG.Clc;
            OCG.gen1(OCG.ADC * 32 + OCG.mImm, y.a);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r))
          END
        END
      ELSIF ORGI.IsLong(x.type) OR ORGI.IsLong(y.type) THEN
        ORGI.loadLongPair(x, y);                         (* widens an INTEGER operand *)
        destR := ORGI.RH - 4;                            (* compact into the lower pair *)
        longAddReg(destR, x.r, y.r, OCG.ADC, FALSE);
        ORGI.RH := ORGI.RH - 2; x.r := ORGI.RH - 2
      ELSE
        ORGI.load(x); ORGI.load(y);
        IF x.type.form = ORB.Int THEN
          destR := ORGI.RH - 2; ORGI.Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
          OCG.Clc;
          OCG.gen1(OCG.ADC * 32 + OCG.mDP, ORGI.RegAddr(y.r));
          OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(destR))
        END;
        ORGI.RH := ORGI.RH - 1; x.r := ORGI.RH - 1
      END
    ELSE (* minus *)
      IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a - y.a
      ELSIF y.mode = ORB.Const THEN
        ORGI.load(x);
        IF y.a # 0 THEN
          IF ORGI.IsLong(x.type) THEN longAddImm(x.r, y.a, OCG.SBC, TRUE)
          ELSIF x.type.form = ORB.Int THEN
            ORGI.Set16(TRUE, TRUE);
            OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
            OCG.Sec;
            OCG.gen1(OCG.SBC * 32 + OCG.mImm, y.a);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r))
          END
        END
      ELSIF ORGI.IsLong(x.type) OR ORGI.IsLong(y.type) THEN
        ORGI.loadLongPair(x, y);                         (* widens an INTEGER operand *)
        destR := ORGI.RH - 4;                            (* compact into the lower pair *)
        longAddReg(destR, x.r, y.r, OCG.SBC, TRUE);
        ORGI.RH := ORGI.RH - 2; x.r := ORGI.RH - 2
      ELSE
        ORGI.load(x); ORGI.load(y);
        IF x.type.form = ORB.Int THEN
          destR := ORGI.RH - 2; ORGI.Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
          OCG.Sec;
          OCG.gen1(OCG.SBC * 32 + OCG.mDP, ORGI.RegAddr(y.r));
          OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(destR))
        END;
        ORGI.RH := ORGI.RH - 1; x.r := ORGI.RH - 1
      END
    END
  END AddOp;

  PROCEDURE log2(m: LONGINT; VAR e: LONGINT): LONGINT;
  BEGIN
    e := 0;
    WHILE m MOD 2 = 0 DO m := m DIV 2; e := e + 1 END;
    RETURN m
  END log2;

  (* general shift-and-add multiply loop; result left in A *)
  PROCEDURE mulLoop(xr, yr: LONGINT);
  BEGIN
    ORGI.Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
    OCG.gen1(OCG.LDX * 32 + OCG.mDP, ORGI.RegAddr(xr));
    OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 2 + 11);
    OCG.gen1(OCG.LSR * 32 + OCG.mDP, ORGI.RegAddr(xr));
    OCG.gen1(OCG.BCC * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
    OCG.Clc;
    OCG.gen1(OCG.ADC * 32 + OCG.mDP, ORGI.RegAddr(yr));
    OCG.gen1(OCG.ASL * 32 + OCG.mDP, ORGI.RegAddr(yr));
    OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 - 15)
  END mulLoop;

  (* 32-bit arithmetic shift right of two-word reg r by e bits, in place
     (signed DIV by 2^e). The sign bit is replicated via CMP #8000H. *)
  PROCEDURE longAsr(r, e: LONGINT);
    VAR i: LONGINT;
  BEGIN
    ORGI.Set16(TRUE, TRUE); i := 0;
    IF e >= 16 THEN   (* a word at once: the high into the low, the sign into the high *)
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r + 1));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(r));
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.BIT * 32 + OCG.mDP, ORGI.RegAddr(r + 1));  (* N := the sign *)
      OCG.gen1(OCG.BPL * 32 + OCG.mPCR, OCG.Here() + 2 + 1);
      OCG.gen1(OCG.DEC * 32 + OCG.mAcc, 0);              (* 0FFFFH *)
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(r + 1));
      i := 16
    ELSIF e >= 8 THEN   (* a byte at once: bytes 1 and 2 the low word, byte 3 the high, its sign extended *)
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r) + 1);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(r));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r) + 3);
      OCG.gen1(OCG.AND * 32 + OCG.mImm, 0FFH);
      OCG.gen1(OCG.CMP * 32 + OCG.mImm, 80H);
      OCG.gen1(OCG.BCC * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
      OCG.gen1(OCG.ORA * 32 + OCG.mImm, 0FF00H);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(r + 1));
      i := 8
    END;
    WHILE i < e DO
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r + 1));
      OCG.gen1(OCG.CMP * 32 + OCG.mImm, 8000H);          (* C := high-word sign *)
      OCG.gen1(OCG.ROR * 32 + OCG.mDP, ORGI.RegAddr(r + 1));  (* high >>1 (arith) *)
      OCG.gen1(OCG.ROR * 32 + OCG.mDP, ORGI.RegAddr(r));      (* low  >>1 *)
      i := i + 1
    END
  END longAsr;

  (* 32-bit shift left of two-word reg r by e bits, in place (MUL by 2^e). *)
  PROCEDURE longAsl(r, e: LONGINT);
    VAR i: LONGINT;
  BEGIN
    ORGI.Set16(TRUE, TRUE); i := 0;
    IF e >= 16 THEN   (* a word at once: the low into the high, 0 into the low *)
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(r + 1));
      OCG.gen1(OCG.STZ * 32 + OCG.mDP, ORGI.RegAddr(r));
      i := 16
    ELSIF e >= 8 THEN   (* a byte at once: bytes 1 and 2 the high word, byte 0 into byte 1 *)
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r) + 1);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(r + 1));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r));
      OCG.Xba;
      OCG.gen1(OCG.AND * 32 + OCG.mImm, 0FF00H);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(r));
      i := 8
    END;
    WHILE i < e DO
      OCG.gen1(OCG.ASL * 32 + OCG.mDP, ORGI.RegAddr(r));      (* low <<1, bit15->C *)
      OCG.gen1(OCG.ROL * 32 + OCG.mDP, ORGI.RegAddr(r + 1));  (* high <<1, C->bit0 *)
      i := i + 1
    END
  END longAsl;

  PROCEDURE MulOp*(VAR x, y: ORGI.Item);
    VAR e, loopTop: LONGINT;
  BEGIN
    ORGI.promoteConst(x, y); ORGI.widenToConst(x, y);
    IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a * y.a
    ELSIF (y.mode = ORB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN
      IF ORGI.IsLong(x.type) THEN ORGI.load(x); longAsl(x.r, e)
      ELSE
        ORGI.load(x); ORGI.Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDX * 32 + OCG.mImm, e);
        loopTop := OCG.Here();
        OCG.gen1(OCG.ASL * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        OCG.Dex;
        OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop)
      END
    ELSIF ORGI.IsLong(x.type) OR ORGI.IsLong(y.type) THEN ORGI.longCall(ORGFP.L_MUL, x, y, FALSE, FALSE)
    ELSIF y.mode = ORB.Const THEN
      ORGI.load(x); ORGI.load(y); mulLoop(x.r, y.r);
      ORGI.RH := ORGI.RH - 1; x.r := ORGI.RH - 1;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r))
    ELSIF (x.mode = ORB.Const) & (x.a >= 2) & (log2(x.a, e) = 1) THEN
      IF ORGI.IsLong(y.type) THEN ORGI.load(y); longAsl(y.r, e); x.mode := ORGI.Reg; x.r := y.r
      ELSE
        ORGI.load(y); ORGI.Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDX * 32 + OCG.mImm, e);
        loopTop := OCG.Here();
        OCG.gen1(OCG.ASL * 32 + OCG.mDP, ORGI.RegAddr(y.r));
        OCG.Dex;
        OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
        x.mode := ORGI.Reg; x.r := y.r
      END
    ELSE
      ORGI.load(x); ORGI.load(y); mulLoop(x.r, y.r);
      ORGI.RH := ORGI.RH - 1; x.r := ORGI.RH - 1;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r))
    END
  END MulOp;

  (* Unsigned 16-bit division. Restoring binary long division (shift-subtract),
     16 iterations — O(1) in the operand values, not O(quotient) as the old
     repeated-subtraction loop was (that made e.g. addr DIV 1 loop 'addr' times,
     which looked like a hang in Files/Modules cluster/sector math).
     Contract unchanged: on exit quotientReg = dividend DIV divisor,
     dividendReg = dividend MOD divisor. Uses X as the bit counter (a fresh
     scratch here, as elsewhere in codegen). *)
  PROCEDURE genDivLoop(dividendReg, divisorReg, quotientReg: LONGINT);
    VAR loopTop: LONGINT;
  BEGIN
    ORGI.Set16(TRUE, TRUE);
    (* quotientReg := dividend (the shifting accumulator; its bits vacate at the
       bottom to hold quotient bits); dividendReg := 0 (remainder accumulator) *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(dividendReg));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(quotientReg));
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, ORGI.RegAddr(dividendReg));
    OCG.gen1(OCG.LDX * 32 + OCG.mImm, 16);
    loopTop := OCG.Here();
    OCG.gen1(OCG.ASL * 32 + OCG.mDP, ORGI.RegAddr(quotientReg));  (* MSB -> C *)
    OCG.gen1(OCG.ROL * 32 + OCG.mDP, ORGI.RegAddr(dividendReg));  (* rem = rem<<1 | bit *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(dividendReg));
    OCG.Sec;
    OCG.gen1(OCG.SBC * 32 + OCG.mDP, ORGI.RegAddr(divisorReg));   (* trial rem - divisor *)
    OCG.gen1(OCG.BCC * 32 + OCG.mPCR, OCG.Here() + 2 + 4);   (* rem<divisor: skip commit *)
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(dividendReg));  (* commit rem -= divisor *)
    OCG.gen1(OCG.INC * 32 + OCG.mDP, ORGI.RegAddr(quotientReg));  (* quotient bit := 1 *)
    OCG.Dex;
    OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop)
  END genDivLoop;

  (* x and y into registers for a division by a variable. A field
     through a pointer (RegI), loaded, frees its pointer's second register
     as if it were the topmost. So the one whose registers are on top is
     loaded first: y if it holds any (computed, or a pointer's), and then
     x without freeing y's; else x, then y above it. (y was loaded first
     always, and a field x through a pointer under it freed y's register:
     p.f DIV n wrote the quotient over the divisor.) *)
  PROCEDURE loadOperands(VAR x, y: ORGI.Item);
    VAR top: LONGINT;
  BEGIN
    IF (y.mode = ORGI.Reg) OR (y.mode = ORGI.RegI) THEN
      ORGI.load(y); top := ORGI.RH; ORGI.load(x); IF ORGI.RH < top THEN ORGI.RH := top END
    ELSE ORGI.load(x); ORGI.load(y)
    END
  END loadOperands;

  PROCEDURE DivOp*(op: LONGINT; VAR x, y: ORGI.Item);
    VAR e, i, divisorReg, quotientReg: LONGINT;
  BEGIN
    ORGI.promoteConst(x, y); ORGI.widenToConst(x, y);
    IF op = ORS.div THEN
      IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
        IF y.a > 0 THEN x.a := x.a DIV y.a ELSE ORS.Mark("bad divisor") END
      ELSIF (y.mode = ORB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN
        IF ORGI.IsLong(x.type) THEN ORGI.load(x); longAsr(x.r, e)
        ELSE
          (* A is not x after load(x) when x is already in a register, a
             procedure's result for one: load it *)
          ORGI.load(x); ORGI.Set16(TRUE, TRUE); i := 0;
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
          WHILE i < e DO
            OCG.gen1(OCG.CMP * 32 + OCG.mImm, 8000H);
            OCG.gen1(OCG.ROR * 32 + OCG.mImpl, 0);
            i := i + 1
          END;
          OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r))
        END
      ELSIF ORGI.IsLong(x.type) OR ORGI.IsLong(y.type) THEN ORGI.longCall(ORGFP.L_DIV, x, y, FALSE, TRUE)
      ELSIF y.mode = ORB.Const THEN
        IF y.a > 0 THEN
          ORGI.load(x); ORGI.Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mImm, y.a);
          OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));
          divisorReg := ORGI.RH; ORGI.incR; quotientReg := ORGI.RH; ORGI.incR;
          genDivLoop(x.r, divisorReg, quotientReg);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(quotientReg));
          OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
          ORGI.RH := ORGI.RH - 2
        ELSE ORS.Mark("bad divisor")
        END
      ELSE
        loadOperands(x, y);
        IF ORGI.check THEN   (* the divisor's flags: it was not the last loaded if it was in a register *)
          ORGI.Set16(TRUE, TRUE); OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r)); ORGI.Trap(ORGI.LE, 6)
        END;
        quotientReg := ORGI.RH; ORGI.incR;
        genDivLoop(x.r, y.r, quotientReg);
        (* the quotient into the lower of x's and y's registers, those above
           it freed: x was loaded first if it was computed already, and was
           the lower then; leaving it counted, the next load went a register
           too high (a RETURN: the result not where the caller looks) *)
        IF y.r < x.r THEN x.r := y.r END;
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(quotientReg));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        ORGI.RH := x.r + 1
      END
    ELSE (* mod *)
      IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
        IF y.a > 0 THEN x.a := x.a MOD y.a ELSE ORS.Mark("bad modulus") END
      ELSIF (y.mode = ORB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN
        IF ORGI.IsLong(x.type) THEN
          (* remainder = value AND (2^e - 1); masking each word with the low/high
             half of the mask zeroes everything above bit e uniformly. *)
          ORGI.load(x); ORGI.Set16(TRUE, TRUE);
          IF ORGI.Lo16(y.a - 1) # 0FFFFH THEN   (* a mask of all ones: the word as it is *)
            OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
            OCG.gen1(OCG.AND * 32 + OCG.mImm, ORGI.Lo16(y.a - 1));
            OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r))
          END;
          IF ORGI.Hi16(y.a - 1) = 0 THEN OCG.gen1(OCG.STZ * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1))
          ELSE
            OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
            OCG.gen1(OCG.AND * 32 + OCG.mImm, ORGI.Hi16(y.a - 1));
            OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1))
          END
        ELSE
          ORGI.load(x); ORGI.Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
          OCG.gen1(OCG.AND * 32 + OCG.mImm, y.a - 1);
          OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r))
        END
      ELSIF ORGI.IsLong(x.type) OR ORGI.IsLong(y.type) THEN ORGI.longCall(ORGFP.L_DIV, x, y, TRUE, TRUE)
      ELSIF y.mode = ORB.Const THEN
        IF y.a > 0 THEN
          ORGI.load(x); ORGI.Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mImm, y.a);
          OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));
          divisorReg := ORGI.RH; ORGI.incR; quotientReg := ORGI.RH; ORGI.incR;
          genDivLoop(x.r, divisorReg, quotientReg);
          ORGI.RH := ORGI.RH - 2
        ELSE ORS.Mark("bad modulus")
        END
      ELSE
        loadOperands(x, y);
        IF ORGI.check THEN   (* the divisor's flags: it was not the last loaded if it was in a register *)
          ORGI.Set16(TRUE, TRUE); OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r)); ORGI.Trap(ORGI.LE, 6)
        END;
        quotientReg := ORGI.RH; ORGI.incR;
        genDivLoop(x.r, y.r, quotientReg);
        (* the remainder, in x's register, into the lower of x's and y's *)
        IF y.r < x.r THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
          OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(y.r));
          x.r := y.r
        END;
        ORGI.RH := x.r + 1
      END
    END
  END DivOp;


  PROCEDURE RealOp*(op: INTEGER; VAR x, y: ORGI.Item);
  BEGIN
    ORGI.load(x); ORGI.load(y); ORGI.Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_A_LO);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_A_HI);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_B_LO);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r + 1));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_B_HI);
    IF op = ORS.plus THEN
      ORGFP.AddFixup(ORGFP.FP_ADD); OCG.gen1(OCG.JSR * 32 + OCG.mAbs, 0)
    ELSIF op = ORS.minus THEN
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGFP.FP_B_HI);
      OCG.gen1(OCG.EOR * 32 + OCG.mImm, 8000H);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_B_HI);
      ORGFP.AddFixup(ORGFP.FP_ADD); OCG.gen1(OCG.JSR * 32 + OCG.mAbs, 0)
    ELSIF op = ORS.times THEN
      ORGFP.AddFixup(ORGFP.FP_MUL); OCG.gen1(OCG.JSR * 32 + OCG.mAbs, 0)
    ELSIF op = ORS.rdiv THEN
      ORGFP.AddFixup(ORGFP.FP_DIV); OCG.gen1(OCG.JSR * 32 + OCG.mAbs, 0)
    END;
    (* the result into the lower pair: x was loaded after y when y was in
       the registers first (x / F(), F's result in R0, x above it) *)
    x.r := ORGI.RH - 4;
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGFP.FP_A_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGFP.FP_A_HI);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
    ORGI.RH := ORGI.RH - 2
  END RealOp;

  (* --- sets --- *)
  PROCEDURE Singleton*(VAR x: ORGI.Item);
    VAR skip, loopTop: LONGINT;
  BEGIN
    IF x.mode = ORB.Const THEN x.a := ASL(1, x.a)
    ELSE
      ORGI.load(x); ORGI.Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, 1);
      OCG.gen1(OCG.LDX * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      skip := OCG.Here() + 2 + 4;
      OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, skip);
      loopTop := OCG.Here();
      OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);
      OCG.Dex;
      OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r))
    END
  END Singleton;

  PROCEDURE Set*(VAR x, y: ORGI.Item);
    VAR skip, loopTop, mask: LONGINT;
  BEGIN
    IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
      IF x.a <= y.a THEN x.a := ASL(2, y.a) - ASL(1, x.a) ELSE x.a := 0 END
    ELSE
      IF (x.mode = ORB.Const) & (x.a <= 15) THEN
        ORGI.load(x); ORGI.Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, ORGI.Lo16(ASL(0FFFFH, x.a)));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r))
      ELSE
        ORGI.load(x); ORGI.Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0FFFFH);
        OCG.gen1(OCG.LDX * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        skip := OCG.Here() + 2 + 4;
        OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, skip);
        loopTop := OCG.Here();
        OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);
        OCG.Dex;
        OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r))
      END;
      IF (y.mode = ORB.Const) & (y.a < 15) THEN
        mask := ORGI.Lo16(EOR(ASL(0FFFEH, y.a), 0FFFFH));
        ORGI.Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, mask);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));
        y.mode := ORGI.Reg; y.r := ORGI.RH; ORGI.incR
      ELSE
        ORGI.load(y); ORGI.Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0FFFEH);
        OCG.gen1(OCG.LDX * 32 + OCG.mDP, ORGI.RegAddr(y.r));
        skip := OCG.Here() + 2 + 4;
        OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, skip);
        loopTop := OCG.Here();
        OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);
        OCG.Dex;
        OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
        OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(y.r))
      END;
      IF x.mode = ORB.Const THEN x.mode := ORGI.Reg END;
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      OCG.gen1(OCG.AND * 32 + OCG.mDP, ORGI.RegAddr(y.r));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      ORGI.RH := ORGI.RH - 1; x.r := ORGI.RH - 1
    END
  END Set;

  PROCEDURE In*(VAR x, y: ORGI.Item);
    VAR skip, loopTop: LONGINT;
  BEGIN
    ORGI.load(y); ORGI.Set16(TRUE, TRUE);
    IF x.mode = ORB.Const THEN
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r));
      OCG.gen1(OCG.AND * 32 + OCG.mImm, ORGI.Lo16(ASL(1, x.a)));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(y.r));
      ORGI.RH := ORGI.RH - 1
    ELSE
      ORGI.load(x);
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, 1);
      OCG.gen1(OCG.LDX * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      skip := OCG.Here() + 2 + 4;
      OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, skip);
      loopTop := OCG.Here();
      OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);
      OCG.Dex;
      OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
      OCG.gen1(OCG.AND * 32 + OCG.mDP, ORGI.RegAddr(y.r));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(y.r));
      ORGI.RH := ORGI.RH - 2
    END;
    ORGI.SetCC(x, ORGI.NE)
  END In;

  PROCEDURE SetOp*(op: LONGINT; VAR x, y: ORGI.Item);
  BEGIN
    IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
      IF op = ORS.plus THEN x.a := ORA(x.a, y.a)
      ELSIF op = ORS.minus THEN x.a := AND(x.a, EOR(y.a, 0FFFFH))
      ELSIF op = ORS.times THEN x.a := AND(x.a, y.a)
      ELSIF op = ORS.rdiv THEN x.a := EOR(x.a, y.a)
      END
    ELSIF y.mode = ORB.Const THEN
      ORGI.load(x);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      IF op = ORS.plus THEN OCG.gen1(OCG.ORA * 32 + OCG.mImm, y.a)
      ELSIF op = ORS.minus THEN OCG.gen1(OCG.AND * 32 + OCG.mImm, ORGI.Lo16(EOR(y.a, 0FFFFH)))
      ELSIF op = ORS.times THEN OCG.gen1(OCG.AND * 32 + OCG.mImm, y.a)
      ELSIF op = ORS.rdiv THEN OCG.gen1(OCG.EOR * 32 + OCG.mImm, y.a)
      END;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r))
    ELSE
      ORGI.load(x); ORGI.load(y);
      IF op = ORS.plus THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        OCG.gen1(OCG.ORA * 32 + OCG.mDP, ORGI.RegAddr(y.r));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2))
      ELSIF op = ORS.minus THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r));
        OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
        OCG.gen1(OCG.AND * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2))
      ELSIF op = ORS.times THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        OCG.gen1(OCG.AND * 32 + OCG.mDP, ORGI.RegAddr(y.r));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2))
      ELSIF op = ORS.rdiv THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        OCG.gen1(OCG.EOR * 32 + OCG.mDP, ORGI.RegAddr(y.r));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 2))
      END;
      ORGI.RH := ORGI.RH - 1; x.r := ORGI.RH - 1
    END
  END SetOp;

  (* --- relations --- *)

  (* Called with the left operand of a relation before the right one is
     compiled. A condition is only flags and pending branches, which the
     code of the right operand would destroy: make it a value. *)
  PROCEDURE Rel1*(VAR x: ORGI.Item);
  BEGIN
    IF x.mode = ORGI.Cond THEN ORGI.load(x) END
  END Rel1;
  PROCEDURE IntRelation*(op: INTEGER; VAR x, y: ORGI.Item);
    VAR isPointer, use8, useSigned, signedCmp: BOOLEAN;
  BEGIN
    ORGI.promoteConst(x, y); ORGI.widenToConst(x, y);
    IF y.mode = ORGI.Cond THEN ORGI.load(y) END;   (* while its flags are still there *)
    isPointer :=(x.type.form = ORB.Pointer) OR (x.type.form = ORB.NilTyp) OR (x.type.form = ORB.Proc);
    use8 := ~isPointer & ((x.type.form = ORB.Char) OR (x.type.form = ORB.Byte) OR (x.type.form = ORB.Bool));
    useSigned := ~isPointer & ~use8 & (x.type.form = ORB.Int);
    IF isPointer THEN
      ORGI.Set16(TRUE, TRUE);
      IF (y.mode = ORB.Const) & (y.a = 0) THEN
        ORGI.load(x);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        OCG.gen1(OCG.ORA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
        ORGI.RH := ORGI.RH - 2
      ELSE
        ORGI.load(x); ORGI.load(y);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        OCG.gen1(OCG.CMP * 32 + OCG.mDP, ORGI.RegAddr(y.r));
        OCG.gen1(OCG.BNE * 32 + OCG.mPCR, OCG.Here() + 2 + 4);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
        OCG.gen1(OCG.CMP * 32 + OCG.mDP, ORGI.RegAddr(y.r + 1));
        ORGI.RH := ORGI.RH - 4
      END
    ELSIF ORGI.IsLong(x.type) OR ORGI.IsLong(y.type) THEN
      (* 32-bit compare: full subtract leaves C = (x>=y) and, after ORing the
         two word-differences, Z = (x=y) — exactly the flags emitBranch tests
         for a size-4 operand, which are those of an unsigned compare.
         LONGINT is signed, so for the ordering relations the sign bit of
         both operands is inverted first: x < y signed is the same as
         (x + 2^31) < (y + 2^31) unsigned. Equality is unaffected. EOR,
         LDA and STA leave the carry of the low subtract alone. *)
      ORGI.Set16(TRUE, TRUE);
      signedCmp := (op = ORS.lss) OR (op = ORS.geq) OR (op = ORS.leq) OR (op = ORS.gtr);
      IF (y.mode = ORB.Const) & (y.type.form # ORB.Proc) THEN
        ORGI.cvt(x, TRUE); ORGI.load(x);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        OCG.Sec;
        OCG.gen1(OCG.SBC * 32 + OCG.mImm, ORGI.Lo16(y.a));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));      (* low diff -> scratch *)
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
        IF signedCmp THEN
          OCG.gen1(OCG.EOR * 32 + OCG.mImm, 8000H);
          OCG.gen1(OCG.SBC * 32 + OCG.mImm, (ORGI.Hi16(y.a) + 8000H) MOD 10000H)
        ELSE
          OCG.gen1(OCG.SBC * 32 + OCG.mImm, ORGI.Hi16(y.a))
        END;
        OCG.gen1(OCG.ORA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));      (* Z := full equality *)
        ORGI.RH := ORGI.RH - 2
      ELSE
        ORGI.loadLongPair(x, y);                                (* widens an INTEGER operand *)
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        OCG.Sec;
        OCG.gen1(OCG.SBC * 32 + OCG.mDP, ORGI.RegAddr(y.r));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));      (* low diff -> scratch *)
        IF signedCmp THEN  (* y's register is a temporary: flip its sign in place *)
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r + 1));
          OCG.gen1(OCG.EOR * 32 + OCG.mImm, 8000H);
          OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(y.r + 1))
        END;
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
        IF signedCmp THEN OCG.gen1(OCG.EOR * 32 + OCG.mImm, 8000H) END;
        OCG.gen1(OCG.SBC * 32 + OCG.mDP, ORGI.RegAddr(y.r + 1));
        OCG.gen1(OCG.ORA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));      (* Z := full equality *)
        ORGI.RH := ORGI.RH - 4
      END
    ELSE
      IF use8 THEN ORGI.Set8(TRUE, FALSE) END;
      signedCmp := useSigned & ((op = ORS.lss) OR (op = ORS.geq) OR (op = ORS.leq) OR (op = ORS.gtr));
      IF (y.mode = ORB.Const) & (y.type.form # ORB.Proc) THEN
        (* x into A, which = 0 and # 0 test by Z alone: the flags load(x)
           leaves are not x's when x was already a register (a procedure's
           result), load then emitting nothing *)
        ORGI.load(x);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        IF (y.a # 0) OR ((op # ORS.eql) & (op # ORS.neq)) THEN
          IF signedCmp THEN
            OCG.Sec;
            OCG.gen1(OCG.SBC * 32 + OCG.mImm, y.a)
          ELSE
            OCG.gen1(OCG.CMP * 32 + OCG.mImm, y.a)
          END
        END;
        ORGI.RH := ORGI.RH - 1
      ELSE
        ORGI.load(x); ORGI.load(y);   (* a condition on the left was loaded by Rel1 *)
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        IF signedCmp THEN
          OCG.Sec;
          OCG.gen1(OCG.SBC * 32 + OCG.mDP, ORGI.RegAddr(y.r))
        ELSE
          OCG.gen1(OCG.CMP * 32 + OCG.mDP, ORGI.RegAddr(y.r))
        END;
        ORGI.RH := ORGI.RH - 2
      END;
      IF use8 THEN ORGI.Set16(TRUE, TRUE) END
    END;
    ORGI.SetCC(x, relmap[op - ORS.eql])
  END IntRelation;

  PROCEDURE RealRelation*(op: INTEGER; VAR x, y: ORGI.Item);
  BEGIN
    ORGI.load(x); ORGI.Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_A_LO);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_A_HI);
    IF (y.mode = ORB.Const) & (y.a = 0) THEN
      OCG.gen1(OCG.STZ * 32 + OCG.mDP, ORGFP.FP_B_LO);
      OCG.gen1(OCG.STZ * 32 + OCG.mDP, ORGFP.FP_B_HI);
      ORGI.RH := ORGI.RH - 2
    ELSE
      ORGI.load(y);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_B_LO);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r + 1));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_B_HI);
      ORGI.RH := ORGI.RH - 4
    END;
    ORGFP.AddFixup(ORGFP.FP_CMP); OCG.gen1(OCG.JSR * 32 + OCG.mAbs, 0);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGFP.FP_A_LO);
    ORGI.SetCC(x, relmap[op - ORS.eql]);
    x.origType := ORB.intType
  END RealRelation;

  (* The far address of a string operand in two registers (address, bank).
     A string constant lives in this module's data, which is in bank 0. *)
  PROCEDURE strAdr(VAR x: ORGI.Item);
  BEGIN
    IF x.type.form = ORB.String THEN
      ORGI.loadStringAdr(x);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.BANK_DP);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH)); ORGI.incR
    ELSE ORGI.loadAdr(x)
    END
  END strAdr;

  (* Compare two 0X-terminated strings character by character. The loop
     ends at the first difference or at the common terminator, leaving
     Z = (x = y) and C = (x >= y) from the 8-bit CMP of that character —
     the flags emitBranch tests for an unsigned operand. REP changes
     neither. *)
  PROCEDURE StringRelation*(op: INTEGER; VAR x, y: ORGI.Item);
    VAR loopTop: LONGINT;
  BEGIN
    strAdr(x); strAdr(y);
    ORGI.Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDY * 32 + OCG.mImm, 0);
    ORGI.Set8(TRUE, FALSE);
    loopTop := OCG.Here();
    OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, ORGI.RegAddr(x.r));
    OCG.gen1(OCG.CMP * 32 + OCG.mDPIndLY, ORGI.RegAddr(y.r));
    OCG.gen1(OCG.BNE * 32 + OCG.mPCR, OCG.Here() + 2 + 7);   (* differ *)
    OCG.gen1(OCG.CMP * 32 + OCG.mImm, 0);
    OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 2 + 3);   (* both ended *)
    OCG.Iny;
    OCG.gen1(OCG.BRA * 32 + OCG.mPCR, loopTop);
    ORGI.Set16(TRUE, FALSE);
    ORGI.RH := ORGI.RH - 4;
    ORGI.SetCC(x, relmap[op - ORS.eql])
  END StringRelation;

  (* --- parameters --- *)
  PROCEDURE OpenArrayParam*(VAR x: ORGI.Item);
  BEGIN
    ORGI.loadAdr(x);
    IF x.type.len >= 0 THEN
      ORGI.Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, x.type.len);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 2))
    ELSE
      ORGI.Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 2 + ORGI.frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 2))
    END;
    ORGI.incR
  END OpenArrayParam;

  PROCEDURE VarParam*(VAR x: ORGI.Item; ftype: ORB.Type);
    VAR xmd, sb: LONGINT;
  BEGIN
    xmd := x.mode;
    IF (x.mode = ORB.Var) & (x.r > 0) THEN
      ORGI.Set16(TRUE, TRUE);
      OCG.Tsc;
      OCG.Clc;
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, x.a + ORGI.frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));
      x.r := ORGI.RH; x.mode := ORGI.Reg; ORGI.incR;
      ORGI.stackBank(ORGI.RH);
      ORGI.incR
    ELSIF (x.mode = ORB.Var) & (x.r <= 0) THEN
      sb := ORGI.GetSB(x.r);
      ORGI.Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, sb);
      IF x.a # 0 THEN
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mImm, x.a)
      END;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.BankOf(sb));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 1));
      x.r := ORGI.RH; x.mode := ORGI.Reg; ORGI.incR; ORGI.incR
    ELSE ORGI.loadAdr(x)
    END;
    IF (ftype.form = ORB.Array) & (ftype.len < 0) THEN
      IF x.type.len >= 0 THEN
        ORGI.Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, x.type.len);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 2))
      ELSE
        ORGI.Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 4 + ORGI.frame);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 2))
      END;
      ORGI.incR
    ELSIF ftype.form = ORB.Record THEN
      ORGI.Set16(TRUE, TRUE);
      IF xmd = ORB.Par THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 4 + ORGI.frame);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 2));
        OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 6 + ORGI.frame);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 3))
      ELSE
        sb := ORGI.GetSB(-x.type.mno);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, sb);
        OCG.Clc;
        emitTDLen(x.type);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 2));
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.BankOf(sb));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 3))
      END;
      ORGI.incR; ORGI.incR
    END
  END VarParam;

  PROCEDURE ValueParam*(VAR x: ORGI.Item; ftype: ORB.Type);
  BEGIN
    IF (ftype # NIL) & (ftype.form = ORB.Int) THEN ORGI.cvt(x, ORGI.IsLong(ftype)) END;
    ORGI.load(x)
  END ValueParam;

  PROCEDURE StringParam*(VAR x: ORGI.Item);
  BEGIN
    ORGI.Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.SB_DP);
    OCG.Clc;
    OCG.gen1(OCG.ADC * 32 + OCG.mImm, ORGI.varsize + x.a);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.BANK_DP);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 1));
    x.mode := ORGI.Reg; x.r := ORGI.RH; ORGI.incR; ORGI.incR;
    ORGI.Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, x.b);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));
    ORGI.incR
  END StringParam;

  (* --- FOR --- *)
  (* the start value, in the control variable's width *)
  PROCEDURE For0*(VAR x, y: ORGI.Item);
  BEGIN
    IF (x.type # NIL) & (x.type.form = ORB.Int) THEN ORGI.cvt(y, ORGI.IsLong(x.type)) END;
    ORGI.load(y); forY := y
  END For0;

  (* The test at the loop's head: out when y, the register For0 loaded,
     has passed the limit z. (Not y as a parameter: a record parameter is
     four words, and fourteen are passed.) A LONGINT: z - y (or y - z,
     stepping down) below zero, as a signed 16-bit result's high word
     tells it *)
  PROCEDURE For1*(VAR x, z, w: ORGI.Item; VAR L: LONGINT);
    VAR useSigned: BOOLEAN; yy, zz: ORGI.Item;
  BEGIN yy := forY; zz := z;
    IF ORGI.IsLong(x.type) THEN
      ORGI.load(yy);
      IF zz.mode # ORB.Const THEN ORGI.load(zz); ORGI.cvt(zz, TRUE) END;
      ORGI.Set16(TRUE, TRUE);
      IF w.a > 0 THEN   (* z - y *)
        IF zz.mode = ORB.Const THEN OCG.gen1(OCG.LDA * 32 + OCG.mImm, ORGI.Lo16(zz.a))
        ELSE OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(zz.r))
        END;
        OCG.Sec; OCG.gen1(OCG.SBC * 32 + OCG.mDP, ORGI.RegAddr(yy.r));
        IF zz.mode = ORB.Const THEN OCG.gen1(OCG.LDA * 32 + OCG.mImm, ORGI.Hi16(zz.a))
        ELSE OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(zz.r + 1))
        END;
        OCG.gen1(OCG.SBC * 32 + OCG.mDP, ORGI.RegAddr(yy.r + 1))
      ELSE   (* y - z *)
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(yy.r)); OCG.Sec;
        IF zz.mode = ORB.Const THEN OCG.gen1(OCG.SBC * 32 + OCG.mImm, ORGI.Lo16(zz.a))
        ELSE OCG.gen1(OCG.SBC * 32 + OCG.mDP, ORGI.RegAddr(zz.r))
        END;
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(yy.r + 1));
        IF zz.mode = ORB.Const THEN OCG.gen1(OCG.SBC * 32 + OCG.mImm, ORGI.Hi16(zz.a))
        ELSE OCG.gen1(OCG.SBC * 32 + OCG.mDP, ORGI.RegAddr(zz.r + 1))
        END
      END;
      IF zz.mode # ORB.Const THEN ORGI.RH := ORGI.RH - 2 END;
      IF w.a = 0 THEN ORS.Mark("zero increment") END;
      ORGI.emitBranch(ORGI.LT, ORB.intType, OCG.mFix, 0);
      L := OCG.Here() - 2;
      ORGI.Store(x, yy)
    ELSE
      useSigned := (yy.type.form = ORB.Int) & (yy.type.size = 2);
      IF zz.mode = ORB.Const THEN
        ORGI.load(yy);
        IF zz.type.size = 1 THEN ORGI.Set8(TRUE, FALSE) ELSE ORGI.Set16(TRUE, TRUE) END;
        IF useSigned THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(yy.r));
          OCG.Sec;
          OCG.gen1(OCG.SBC * 32 + OCG.mImm, zz.a)
        ELSE OCG.gen1(OCG.CMP * 32 + OCG.mImm, zz.a)
        END
      ELSE
        ORGI.load(yy); ORGI.load(zz);
        IF (yy.type.size = 1) & (zz.type.size = 1) THEN ORGI.Set8(TRUE, FALSE)
        ELSE ORGI.Set16(TRUE, TRUE) END;
        IF useSigned THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(yy.r));
          OCG.Sec;
          OCG.gen1(OCG.SBC * 32 + OCG.mDP, ORGI.RegAddr(zz.r))
        ELSE
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(yy.r));
          OCG.gen1(OCG.CMP * 32 + OCG.mDP, ORGI.RegAddr(zz.r))
        END;
        ORGI.RH := ORGI.RH - 1
      END;
      ORGI.Set16(TRUE, FALSE);
      IF w.a > 0 THEN ORGI.emitBranch(ORGI.GT, yy.type, OCG.mFix, 0)
      ELSIF w.a < 0 THEN ORGI.emitBranch(ORGI.LT, yy.type, OCG.mFix, 0)
      ELSE ORS.Mark("zero increment"); ORGI.emitBranch(ORGI.MI, yy.type, OCG.mFix, 0)
      END;
      L := OCG.Here() - 2;
      ORGI.Store(x, yy)
    END
  END For1;

  (* x + w into the register the test reads (load leaves x a register).
     w is a constant (ORP's CheckConst) *)
  PROCEDURE For2*(VAR x, y, w: ORGI.Item);
  BEGIN
    ORGI.load(x);
    IF ORGI.IsLong(x.type) THEN
      ORGI.Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r)); OCG.Clc;
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, ORGI.Lo16(w.a));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, ORGI.Hi16(w.a));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
      ORGI.RH := ORGI.RH - 2
    ELSE
      IF w.mode = ORB.Const THEN
        IF w.a > 0 THEN
          OCG.Clc;
          OCG.gen1(OCG.ADC * 32 + OCG.mImm, w.a)
        ELSE
          OCG.Sec;
          OCG.gen1(OCG.SBC * 32 + OCG.mImm, -w.a)
        END
      ELSE
        ORGI.load(w);
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mDP, ORGI.RegAddr(w.r));
        ORGI.RH := ORGI.RH - 1
      END;
      IF x.mode = ORB.Var THEN
        OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
        OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, ORGI.SB_DP)
      ELSE OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r))
      END;
      ORGI.RH := ORGI.RH - 1
    END
  END For2;

  (* --- CASE --- *)
  (* A LONGINT selector is two registers, both words compared *)
  PROCEDURE CaseLabel*(VAR x: ORGI.Item; val: LONGINT; VAR chain: LONGINT);
  BEGIN
    ORGI.load(x); ORGI.Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
    OCG.gen1(OCG.CMP * 32 + OCG.mImm, ORGI.Lo16(val));
    IF ORGI.IsLong(x.type) THEN
      OCG.gen1(OCG.BNE * 32 + OCG.mPCR, OCG.Here() + 2 + 2 + 3 + 2 + 3);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
      OCG.gen1(OCG.CMP * 32 + OCG.mImm, ORGI.Hi16(val));
      ORGI.RH := ORGI.RH - 2
    ELSE ORGI.RH := ORGI.RH - 1
    END;
    OCG.gen1(OCG.BNE * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
    OCG.gen1(OCG.BRL * 32 + OCG.mFix, chain);
    chain := OCG.Here() - 2
  END CaseLabel;

  (* x - lo, unsigned, below hi - lo + 1 *)
  PROCEDURE CaseRange*(VAR x: ORGI.Item; lo, hi: LONGINT; VAR chain: LONGINT);
    VAR n: LONGINT;
  BEGIN
    ORGI.load(x); ORGI.Set16(TRUE, TRUE);
    IF ORGI.IsLong(x.type) THEN n := hi - lo + 1;
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      OCG.Sec;
      OCG.gen1(OCG.SBC * 32 + OCG.mImm, ORGI.Lo16(lo));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
      OCG.gen1(OCG.SBC * 32 + OCG.mImm, ORGI.Hi16(lo));
      OCG.gen1(OCG.CMP * 32 + OCG.mImm, ORGI.Hi16(n));
      OCG.gen1(OCG.BCC * 32 + OCG.mPCR, OCG.Here() + 2 + 2 + 2 + 3 + 2);   (* in range *)
      OCG.gen1(OCG.BNE * 32 + OCG.mPCR, OCG.Here() + 2 + 2 + 3 + 2 + 3);   (* above it *)
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      OCG.gen1(OCG.CMP * 32 + OCG.mImm, ORGI.Lo16(n));
      ORGI.RH := ORGI.RH - 2
    ELSE
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      ORGI.RH := ORGI.RH - 1;
      OCG.Sec;
      OCG.gen1(OCG.SBC * 32 + OCG.mImm, lo);
      OCG.gen1(OCG.CMP * 32 + OCG.mImm, hi - lo + 1)
    END;
    OCG.gen1(OCG.BCS * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
    OCG.gen1(OCG.BRL * 32 + OCG.mFix, chain);
    chain := OCG.Here() - 2
  END CaseRange;

END ORGE.
