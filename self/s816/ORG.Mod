MODULE ORG; (* 65C816 code generator — self-hosted port of 65Tools/oc/src/ORG.c.

   Backend #2 behind the shared frontend (ORS/ORB/ORP.Mod). Emits a
   relocatable .816 module. Register model: 8 16-bit "registers" at direct
   page $02-$1E (a stack, height RH), static base at DP $00. Instruction
   bytes go through the verified encoder OCG.Mod.

   Exposes the shared-frontend interface (Item = {mode,type,a,b,r,rdo,
   origType}; the target constants; InitSystem; the ~90 codegen entry
   points ORP calls). Where the C ORG_Enter/Return/Open signatures differ
   from what shared ORP passes, the Oberon procedures adopt ORP's
   signatures and derive what the 816 logic needs. *)

  IMPORT SYSTEM, OCG, ORS, ORB, ORGFP, ORGW, Files;

  CONST
    (* --- target parameters (read by the shared frontend) --- *)
    WordSize* = 2;
    SetMax* = 16;          (* SET elements 0..15 *)
    ParLimit* = 52;
    IntSize* = 2; LongSize* = 4; RealSize* = 4;
    SetSize* = 2; NilSize* = 2; StrSize* = 8;
    PtrSize* = 4; IntfcSize* = 8;

    MT = 15;               (* max general registers R0..R14 *)
    maxStrx = 16000;
    maxTD = 160;
    CodeOrg = 0;
    SB_DP = 0;             (* static base at DP $00 *)
    SB_TEMP = 20H;         (* imported module var_base *)
    SB_TEMP_BANK = 22H;
    BANK_DP = 44H;         (* own module data bank byte *)

    (* internal item modes (beyond ORB classes) *)
    Reg = 10; RegI = 11; Cond = 12;

    (* condition codes *)
    MI = 0; PL = 8; EQ = 1; NE = 9; LT = 5; GE = 13;
    LE = 6; GT = 14; AL = 7; NV = 15;

    maxForNest = 8;        (* max nested FOR loops with a non-const limit *)
    maxEnt = 256;          (* max .816 export-table entries *)
    maxMeth = 64;          (* max vtable slots per type *)
    maxVtFix = 512;        (* max vtable-slot loader fixups per module *)
    maxItab = 128;         (* max distinct (record,interface) itables per module *)
    maxItabRef = 256;      (* max PtrToIface conversion sites per module *)
    VtableOff = 16;        (* byte offset of vtable[0] in a TD: size(2) +
                              3 ancestors(12) + nofmeth(2). Each slot is a 2-byte
                              absolute in-bank method address filled by the loader. *)

  TYPE
    Item* = RECORD
      mode*: INTEGER;
      type*: ORB.Type;
      a*, b*, r*: LONGINT;
      rdo*: BOOLEAN;
      origType*: ORB.Type;
      (* backend-private OO state (shared ORP never reads these): the
         receiver designator stashed by MethodItem/InitItem for PrepCall
         to pass as param 0, and the dynamic-dispatch flag *)
      isMeth*: BOOLEAN;
      dynDisp*: BOOLEAN;          (* TRUE: dispatch via vtable slot methSlot *)
      ifaceDisp*: BOOLEAN;        (* TRUE: interface dispatch — receiver + itable
                                     are re-read from the interface designator in
                                     rcv*, and the vtable slot from itable[methSlot] *)
      methSlot*: LONGINT;         (* vtable slot (dynDisp) or itable index (ifaceDisp) *)
      rcvMode*, rcvA*, rcvB*, rcvR*: LONGINT;
      rcvRdo*: BOOLEAN;
      rcvType*: ORB.Type
    END;

  VAR
    varsize: LONGINT;    (* = ORG_varsize; set by SetDataSize *)
    tdx, strx, entry, RH, frame: LONGINT;
    fixorgP, fixorgD, fixorgT: LONGINT;
    check: BOOLEAN;
    version: INTEGER;
    relmap: ARRAY 6 OF INTEGER;
    wa: ORGW.ModArrays;               (* module-image scratch: str/data/tdFixup*/vtFix* *)
    tdFixupC: INTEGER;
    (* deferred type descriptors (classic Oberon-2 single-pass): types are
       recorded at declaration and their descriptors generated at Close,
       placed after the variables + strings so the vtable size is known.
       New/TypeTest emit T.len as a forward fixup patched in GenTDs. *)
    tdList: ARRAY maxTD OF ORB.Type;  (* kept out of wa: array of ptrs (see ORGW.ModArrays) *)
    tdListC: INTEGER;
    tdBase: LONGINT;                              (* var-relative base of TD region *)
    tdRefLoc: ARRAY maxTD OF LONGINT;             (* code sites needing a T.len *)
    tdRefTyp: ARRAY maxTD OF ORB.Type;
    tdRefC: INTEGER;
    vtFixC: INTEGER;
    slotMeth: ARRAY maxMeth OF ORB.Object;        (* method per vtable slot *)
    slotMno: ARRAY maxMeth OF LONGINT;            (* its defining type's mno *)
    itabRec, itabIfc: ARRAY maxItab OF ORB.Type;  (* per-(record,interface) itables *)
    itabOff: ARRAY maxItab OF LONGINT;            (* var-relative offset, set in GenTDs *)
    itabC: INTEGER;
    itabRefLoc: ARRAY maxItabRef OF LONGINT;      (* PtrToIface sites needing an offset *)
    itabRefIdx: ARRAY maxItabRef OF INTEGER;
    itabRefC: INTEGER;
    curModid: ORS.Ident;
    forDepth: LONGINT;                         (* current nested-FOR depth *)
    forPushed: ARRAY maxForNest OF BOOLEAN;    (* did this FOR spill a limit? *)
    (* stashed at Enter for Return (shared ORP's Return(proc,x) lacks
       frame/expo/int; Enter and its Return never nest across another
       Enter, so single module vars suffice) *)
    curFrameSize: LONGINT;
    curExpo, curIntProc: BOOLEAN;

  (* --- helpers --- *)

  PROCEDURE RegAddr(reg: LONGINT): LONGINT;
  BEGIN RETURN reg * 2 + 2
  END RegAddr;

  PROCEDURE Lo16(v: LONGINT): LONGINT;
  BEGIN RETURN v MOD 10000H
  END Lo16;

  PROCEDURE Hi16(v: LONGINT): LONGINT;
  BEGIN RETURN v DIV 10000H MOD 10000H
  END Hi16;

  PROCEDURE Set16(a, i: BOOLEAN);
    VAR na, ni: BOOLEAN; val: LONGINT;
  BEGIN
    IF a THEN na := TRUE ELSE na := OCG.LongA() END;
    IF i THEN ni := TRUE ELSE ni := OCG.LongI() END;
    IF (OCG.LongA() = na) & (OCG.LongI() = ni) THEN (* no change *)
    ELSE
      val := 0;
      IF a THEN val := val + 20H END;
      IF i THEN val := val + 10H END;
      OCG.SetLongA(na); OCG.SetLongI(ni);
      OCG.gen1(OCG.REP * 32 + OCG.mImm, val)
    END
  END Set16;

  PROCEDURE Set8(a, i: BOOLEAN);
    VAR na, ni: BOOLEAN; val: LONGINT;
  BEGIN
    IF a THEN na := FALSE ELSE na := OCG.LongA() END;
    IF i THEN ni := FALSE ELSE ni := OCG.LongI() END;
    IF (OCG.LongA() = na) & (OCG.LongI() = ni) THEN (* no change *)
    ELSE
      val := 0;
      IF a THEN val := val + 20H END;
      IF i THEN val := val + 10H END;
      OCG.SetLongA(na); OCG.SetLongI(ni);
      OCG.gen1(OCG.SEP * 32 + OCG.mImm, val)
    END
  END Set8;

  PROCEDURE incR;
  BEGIN
    IF RH < MT - 1 THEN RH := RH + 1
    ELSE ORS.Mark("register stack overflow")
    END
  END incR;

  (* DP address of the correct module's var_base. mno >= 0 (own): SB_DP,
     no code. mno < 0 (import): emit loads of the module's var_base+bank
     with relocations, return SB_TEMP. *)
  PROCEDURE GetSB(mno: LONGINT): LONGINT;
    VAR res: LONGINT;
  BEGIN
    IF mno >= 0 THEN res := SB_DP
    ELSE
      Set16(TRUE, TRUE);
      OCG.AddRel(OCG.Here());
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, -mno);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, SB_TEMP);
      OCG.AddRel(OCG.Here() + 80000000H);   (* bank reloc flag (bit 31) *)
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, -mno);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, SB_TEMP_BANK);
      res := SB_TEMP
    END;
    RETURN res
  END GetSB;

  PROCEDURE CheckRegs*;
  BEGIN
    Set16(TRUE, TRUE)
    (* Reset at end of every statement: a statement start may be a branch
       target and we must guarantee 16-bit A/index there. *)
  END CheckRegs;

  PROCEDURE SetCC(VAR x: Item; n: LONGINT);
  BEGIN
    x.origType := x.type; x.mode := Cond; x.a := 0; x.b := 0; x.r := n
  END SetCC;

  PROCEDURE Trap(cond, num: LONGINT);
  BEGIN
    IF cond = EQ THEN
      OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 4);
      OCG.gen1(OCG.BRK * 32 + OCG.mImm, num)
    ELSIF cond = NE THEN
      OCG.gen1(OCG.BNE * 32 + OCG.mPCR, OCG.Here() + 4);
      OCG.gen1(OCG.BRK * 32 + OCG.mImm, num)
    ELSIF cond = MI THEN
      OCG.gen1(OCG.BMI * 32 + OCG.mPCR, OCG.Here() + 4);
      OCG.gen1(OCG.BRK * 32 + OCG.mImm, num)
    ELSIF cond = PL THEN
      OCG.gen1(OCG.BPL * 32 + OCG.mPCR, OCG.Here() + 4);
      OCG.gen1(OCG.BRK * 32 + OCG.mImm, num)
    ELSIF cond = LT THEN
      OCG.gen1(OCG.BCC * 32 + OCG.mPCR, OCG.Here() + 4);
      OCG.gen1(OCG.BRK * 32 + OCG.mImm, num)
    ELSIF cond = GE THEN
      OCG.gen1(OCG.BCS * 32 + OCG.mPCR, OCG.Here() + 4);
      OCG.gen1(OCG.BRK * 32 + OCG.mImm, num)
    ELSIF cond = LE THEN
      OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 4 + 4);
      OCG.gen1(OCG.BCC * 32 + OCG.mPCR, OCG.Here() + 4 + 2);
      OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 4);
      OCG.gen1(OCG.BRK * 32 + OCG.mImm, num)
    ELSIF cond = GT THEN
      OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 4 + 2);
      OCG.gen1(OCG.BCS * 32 + OCG.mPCR, OCG.Here() + 4);
      OCG.gen1(OCG.BRK * 32 + OCG.mImm, num)
    ELSIF cond = AL THEN
      OCG.gen1(OCG.BRK * 32 + OCG.mImm, num)
    ELSIF cond = NV THEN (* never trap *)
    ELSE ORS.Mark("Trap not implemented")
    END
  END Trap;

  PROCEDURE negated(cond: LONGINT): LONGINT;
    VAR r: LONGINT;
  BEGIN
    IF cond = EQ THEN r := NE
    ELSIF cond = NE THEN r := EQ
    ELSIF cond = LT THEN r := GE
    ELSIF cond = GE THEN r := LT
    ELSIF cond = LE THEN r := GT
    ELSIF cond = GT THEN r := LE
    ELSIF cond = MI THEN r := PL
    ELSIF cond = PL THEN r := MI
    ELSIF cond = AL THEN r := NV
    ELSIF cond = NV THEN r := AL
    ELSE r := cond
    END;
    RETURN r
  END negated;

  (* Emit conditional branch on cond to a forward fixup chain (target). *)
  PROCEDURE emitBranch(cond: LONGINT; type: ORB.Type; mode, target: LONGINT);
    VAR signed: BOOLEAN;
  BEGIN
    signed := (type.size = 2) & (type.form = ORB.Int);
    IF cond = EQ THEN
      OCG.gen1(OCG.BNE * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
      OCG.gen1(OCG.BRL * 32 + mode, target)
    ELSIF cond = NE THEN
      OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
      OCG.gen1(OCG.BRL * 32 + mode, target)
    ELSIF cond = MI THEN
      OCG.gen1(OCG.BPL * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
      OCG.gen1(OCG.BRL * 32 + mode, target)
    ELSIF cond = PL THEN
      OCG.gen1(OCG.BMI * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
      OCG.gen1(OCG.BRL * 32 + mode, target)
    ELSIF cond = LT THEN
      IF signed THEN
        OCG.gen1(OCG.BVS * 32 + OCG.mPCR, OCG.Here() + 2 + 4);
        OCG.gen1(OCG.BMI * 32 + OCG.mPCR, OCG.Here() + 2 + 6);
        OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 + 7);
        OCG.gen1(OCG.BPL * 32 + OCG.mPCR, OCG.Here() + 2 + 2);
        OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
        OCG.gen1(OCG.BRL * 32 + mode, target)
      ELSE
        OCG.gen1(OCG.BCS * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
        OCG.gen1(OCG.BRL * 32 + mode, target)
      END
    ELSIF cond = GE THEN
      IF signed THEN
        OCG.gen1(OCG.BVS * 32 + OCG.mPCR, OCG.Here() + 2 + 4);
        OCG.gen1(OCG.BPL * 32 + OCG.mPCR, OCG.Here() + 2 + 6);
        OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 + 7);
        OCG.gen1(OCG.BMI * 32 + OCG.mPCR, OCG.Here() + 2 + 2);
        OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
        OCG.gen1(OCG.BRL * 32 + mode, target)
      ELSE
        OCG.gen1(OCG.BCC * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
        OCG.gen1(OCG.BRL * 32 + mode, target)
      END
    ELSIF cond = LE THEN
      IF signed THEN
        OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 2 + 10);
        OCG.gen1(OCG.BVS * 32 + OCG.mPCR, OCG.Here() + 2 + 4);
        OCG.gen1(OCG.BMI * 32 + OCG.mPCR, OCG.Here() + 2 + 6);
        OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 + 7);
        OCG.gen1(OCG.BPL * 32 + OCG.mPCR, OCG.Here() + 2 + 2);
        OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
        OCG.gen1(OCG.BRL * 32 + mode, target)
      ELSE
        OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 2 + 2);
        OCG.gen1(OCG.BCS * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
        OCG.gen1(OCG.BRL * 32 + mode, target)
      END
    ELSIF cond = GT THEN
      IF signed THEN
        OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 2 + 13);
        OCG.gen1(OCG.BVS * 32 + OCG.mPCR, OCG.Here() + 2 + 4);
        OCG.gen1(OCG.BPL * 32 + OCG.mPCR, OCG.Here() + 2 + 6);
        OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 + 7);
        OCG.gen1(OCG.BMI * 32 + OCG.mPCR, OCG.Here() + 2 + 2);
        OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
        OCG.gen1(OCG.BRL * 32 + mode, target)
      ELSE
        OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 2 + 4);
        OCG.gen1(OCG.BCC * 32 + OCG.mPCR, OCG.Here() + 2 + 2);
        OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
        OCG.gen1(OCG.BRL * 32 + mode, target)
      END
    ELSIF cond = AL THEN
      OCG.gen1(OCG.BRL * 32 + mode, target)
    END
  END emitBranch;

  (* fix a BRL fixup at 'at' (offset-lo-byte address) to target. *)
  PROCEDURE fix(at, target: LONGINT);
    VAR offset, ci: LONGINT;
  BEGIN
    offset := target - (at + 1);
    ci := at - CodeOrg;
    IF (offset >= -128) & (offset <= 127) THEN
      OCG.Patch(ci - 1, 80H);        (* BRL -> BRA *)
      OCG.Patch(ci, offset);
      OCG.Patch(ci + 1, 0EAH)        (* NOP high byte *)
    ELSE
      offset := offset - 1;
      OCG.Patch(ci, offset);
      OCG.Patch(ci + 1, offset DIV 100H)
    END
  END fix;

  PROCEDURE FixOne*(at: LONGINT);
  BEGIN fix(at, OCG.Here())
  END FixOne;

  PROCEDURE FixLink*(L: LONGINT);
    VAR L1, ci: LONGINT;
  BEGIN
    (* ~OCG.Faulted() backstops a chain corrupted by a code-buffer overflow
       whose garbage links happen to stay in range (Get already terminates
       out-of-range walks by returning 0). *)
    WHILE (L # 0) & ~OCG.Faulted() DO
      ci := L - CodeOrg;
      L1 := OCG.Get(ci) + OCG.Get(ci + 1) * 100H;
      fix(L, OCG.Here());
      L := L1
    END
  END FixLink;

  PROCEDURE FixLinkWith(L0, dst: LONGINT);
    VAR L1, ci: LONGINT;
  BEGIN
    WHILE L0 # 0 DO
      ci := L0 - CodeOrg;
      L1 := OCG.Get(ci) + OCG.Get(ci + 1) * 100H;
      fix(L0, dst);
      L0 := L1
    END
  END FixLinkWith;

  PROCEDURE merged(L0, L1: LONGINT): LONGINT;
    VAR L2, L3, ci: LONGINT;
  BEGIN
    ci := 0;
    IF L0 # 0 THEN
      L3 := L0;
      REPEAT
        L2 := L3; ci := L2 - CodeOrg;
        L3 := OCG.Get(ci) + OCG.Get(ci + 1) * 100H
      UNTIL L3 = 0;
      OCG.Patch(ci, L1);
      OCG.Patch(ci + 1, L1 DIV 100H);
      L1 := L0
    END;
    RETURN L1
  END merged;

  (* Patch a placeholder 8-bit forward branch (operand byte at 'at'). *)
  PROCEDURE patch(at: LONGINT);
  BEGIN OCG.Patch(at, OCG.Here() - (at + 1))
  END patch;

  (* Emit a forward branch with a placeholder target; return its operand
     byte address for later patch(). *)
  PROCEDURE emitFwdBranch(op: LONGINT): LONGINT;
  BEGIN
    OCG.gen1(op * 32 + OCG.mPCR, OCG.Here() + 2);
    RETURN OCG.Here() - 1
  END emitFwdBranch;

  (* Load two consecutive words at byte offset `off` of the interface value
     designated by (mode,a,b,r) into RegAddr(dst)/dst+1. Var/Par only. *)
  PROCEDURE loadIfacePair(mode, a, b, r, off, dst: LONGINT);
    VAR sb: LONGINT;
  BEGIN
    Set16(TRUE, TRUE);
    IF (mode = ORB.Var) & (r <= 0) THEN
      sb := GetSB(r);
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, a + off);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndY, sb);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(dst));
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, a + off + 2);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndY, sb);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(dst + 1))
    ELSE   (* local Var or by-value Par: stack-frame relative *)
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, a + off + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(dst));
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, a + off + 2 + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(dst + 1))
    END
  END loadIfacePair;

  (* --- load: materialize item x into register(s), leaving x in Reg mode --- *)
  PROCEDURE load(VAR x: Item);
    VAR perAddr, perOp, mno, exno, encoded, sb, falseChain: LONGINT;
  BEGIN
    IF (x.mode # Reg) & (x.type # NIL) & (x.type.form = ORB.Intfc) THEN
      (* fat value {data, itable}: 4 words from the designator *)
      loadIfacePair(x.mode, x.a, x.b, x.r, 0, RH);
      loadIfacePair(x.mode, x.a, x.b, x.r, 4, RH + 2);
      x.mode := Reg; x.r := RH; incR; incR; incR; incR
    ELSIF x.mode # Reg THEN
      IF x.mode = ORB.Const THEN
        IF (x.type.form = ORB.NilTyp) OR (x.type.form = ORB.Pointer) THEN
          Set16(TRUE, TRUE);
          OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(RH));
          OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(RH + 1));
          x.r := RH; incR; incR
        ELSIF x.type.form = ORB.Proc THEN
          IF (x.r > 0) OR ((x.r = 0) & (x.b = 0)) THEN
            ORS.Mark("not exportd")
          ELSIF (x.r = 0) & (x.b = 1) THEN
            Set16(TRUE, TRUE);
            perAddr := OCG.Here();
            perOp := x.a - perAddr - 3;
            OCG.gen1(OCG.PER * 32 + OCG.mImm, Lo16(perOp));
            OCG.Pla;
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
            OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(RH + 1));
            OCG.Phk;
            Set8(TRUE, FALSE);
            OCG.Pla;
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1));
            Set16(TRUE, FALSE);
            x.r := RH; incR; incR
          ELSE
            Set16(TRUE, TRUE);
            mno := -x.r; exno := x.a;
            encoded := mno * 100H + (exno MOD 100H);
            OCG.AddRel(OCG.Here());
            OCG.gen1(OCG.PER * 32 + OCG.mImm, encoded);
            OCG.Pla;
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
            OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(RH + 1));
            OCG.Phk;
            Set8(TRUE, FALSE);
            OCG.Pla;
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1));
            Set16(TRUE, FALSE);
            x.r := RH; incR; incR
          END
        ELSIF x.type.form = ORB.Real THEN
          Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mImm, Lo16(x.a));
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
          OCG.gen1(OCG.LDA * 32 + OCG.mImm, Hi16(x.a));
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1));
          x.r := RH; incR; incR
        ELSIF (x.a <= 0FFFFH) & (x.a >= -10000H) THEN
          IF x.type.size = 1 THEN
            Set8(TRUE, FALSE);
            OCG.gen1(OCG.LDA * 32 + OCG.mImm, x.a MOD 100H);
            Set16(TRUE, FALSE);
            OCG.gen1(OCG.AND * 32 + OCG.mImm, 0FFH);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH))
          ELSE
            Set16(TRUE, TRUE);
            OCG.gen1(OCG.LDA * 32 + OCG.mImm, Lo16(x.a));
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH))
          END;
          x.r := RH; incR
        ELSE
          x.r := RH; incR   (* wide constant: unsupported path, matches C stub *)
        END
      ELSIF x.mode = ORB.Var THEN
        IF x.r > 0 THEN
          IF (x.type.form = ORB.Pointer) OR (x.type.form = ORB.NilTyp)
             OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) THEN
            Set16(TRUE, TRUE);
            OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + frame);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
            OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 2 + frame);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1));
            x.r := RH; incR; incR
          ELSIF x.type.size = 1 THEN
            Set8(TRUE, FALSE);
            OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + frame);
            Set16(TRUE, FALSE);
            OCG.gen1(OCG.AND * 32 + OCG.mImm, 0FFH);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
            x.r := RH; incR
          ELSE
            Set16(TRUE, TRUE);
            OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + frame);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
            x.r := RH; incR
          END
        ELSE
          sb := GetSB(x.r);
          IF (x.type.form = ORB.Pointer) OR (x.type.form = ORB.NilTyp)
             OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) THEN
            Set16(TRUE, TRUE);
            OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndY, sb);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
            OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a + 2);
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndY, sb);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1));
            x.r := RH; incR; incR
          ELSIF x.type.size = 1 THEN
            Set8(TRUE, FALSE);
            OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndY, sb);
            Set16(TRUE, FALSE);
            OCG.gen1(OCG.AND * 32 + OCG.mImm, 0FFH);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
            x.r := RH; incR
          ELSE
            Set16(TRUE, TRUE);
            OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndY, sb);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
            x.r := RH; incR
          END
        END
      ELSIF x.mode = ORB.Par THEN
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + frame);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
        OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 2 + frame);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1));
        IF (x.type.form = ORB.Real) OR (x.type.form = ORB.Pointer) OR (x.type.form = ORB.Proc) THEN
          Set16(TRUE, TRUE);
          IF x.b # 0 THEN
            OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.b + 2);
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(RH));
            OCG.Pha;
            OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.b);
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(RH))
          ELSE
            OCG.gen1(OCG.LDY * 32 + OCG.mImm, 2);
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(RH));
            OCG.Pha;
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, RegAddr(RH))
          END;
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
          OCG.Pla;
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1));
          x.r := RH; incR; incR
        ELSIF x.type.size = 1 THEN
          Set8(TRUE, FALSE);
          IF x.b # 0 THEN
            OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.b);
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(RH))
          ELSE
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, RegAddr(RH))
          END;
          Set16(TRUE, FALSE);
          OCG.gen1(OCG.AND * 32 + OCG.mImm, 0FFH);
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
          x.r := RH; incR
        ELSE
          Set16(TRUE, TRUE);
          IF x.b # 0 THEN
            OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.b);
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(RH))
          ELSE
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, RegAddr(RH))
          END;
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
          x.r := RH; incR
        END
      ELSIF x.mode = RegI THEN
        IF (x.type.form = ORB.Pointer) OR (x.type.form = ORB.NilTyp)
           OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) THEN
          Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a + 2);
          OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(x.r));
          OCG.Pha;
          IF x.a = 0 THEN
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, RegAddr(x.r))
          ELSE
            OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(x.r))
          END;
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r));
          OCG.Pla;
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r + 1))
        ELSIF x.type.size = 1 THEN
          Set8(TRUE, FALSE);
          IF x.a = 0 THEN
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, RegAddr(x.r))
          ELSE
            OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(x.r))
          END;
          Set16(TRUE, FALSE);
          OCG.gen1(OCG.AND * 32 + OCG.mImm, 0FFH);
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r));
          RH := RH - 1
        ELSE
          Set16(TRUE, TRUE);
          IF x.a = 0 THEN
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, RegAddr(x.r))
          ELSE
            OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(x.r))
          END;
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r));
          RH := RH - 1
        END
      ELSIF x.mode = Cond THEN
        emitBranch(negated(x.r), x.origType, OCG.mFix, x.a);
        falseChain := OCG.Here() - 2;   (* BRL offset field = FALSE chain head *)
        FixLink(x.b);                    (* TRUE path *)
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, 1);
        OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
        FixLink(falseChain);             (* FALSE path *)
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
        x.r := RH; incR
      END;
      x.mode := Reg
    END
  END load;

  PROCEDURE loadAdr(VAR x: Item);
    VAR sb: LONGINT;
  BEGIN
    IF x.mode = ORB.Var THEN
      IF x.r > 0 THEN
        Set16(TRUE, TRUE);
        OCG.Tsc;
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mImm, x.a + frame);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
        OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(RH + 1))
      ELSE
        sb := GetSB(x.r);
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, x.a);
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mDP, sb);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
        IF x.r >= 0 THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, BANK_DP)
        ELSE
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, SB_TEMP_BANK)
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1))
      END;
      x.r := RH; incR; incR
    ELSIF x.mode = ORB.Par THEN
      Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 2 + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1));
      IF x.b # 0 THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH));
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mImm, x.b);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH))
      END;
      x.r := RH; incR; incR
    ELSIF x.mode = RegI THEN
      IF x.a # 0 THEN
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mImm, x.a);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r))
      END
    ELSIF x.mode = ORB.Const THEN
      (* a constant aggregate (record/array literal) lives in the data
         section at var-relative offset x.a; its address is SB+varsize+x.a *)
      Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, varsize + x.a);
      OCG.Clc;
      OCG.gen1(OCG.ADC * 32 + OCG.mDP, SB_DP);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, BANK_DP);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1));
      x.r := RH; incR; incR
    ELSE ORS.Mark("address error")
    END;
    x.mode := Reg
  END loadAdr;

  PROCEDURE loadCond(VAR x: Item);
  BEGIN
    IF x.type.form = ORB.Bool THEN
      IF x.mode = ORB.Const THEN
        x.r := 15 - x.a * 8
      ELSE
        load(x);
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
        x.r := NE; RH := RH - 1
      END;
      x.mode := Cond; x.origType := x.type; x.a := 0; x.b := 0
    ELSE ORS.Mark("not Boolean?")
    END
  END loadCond;

  PROCEDURE loadTypTagAdr(T: ORB.Type);
    VAR x: Item;
  BEGIN
    x.mode := ORB.Var; x.a := T.len; x.r := -T.mno; loadAdr(x)
  END loadTypTagAdr;

  PROCEDURE loadStringAdr(VAR x: Item);
  BEGIN
    Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, SB_DP);
    OCG.Clc;
    OCG.gen1(OCG.ADC * 32 + OCG.mImm, varsize + x.a);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
    x.mode := Reg; x.r := RH; incR
  END loadStringAdr;

  (* --- item construction --- *)
  PROCEDURE MakeConstItem*(VAR x: Item; typ: ORB.Type; val: LONGINT);
  BEGIN x.mode := ORB.Const; x.type := typ; x.a := val
  END MakeConstItem;

  PROCEDURE MakeRealItem*(VAR x: Item; val: REAL);
  BEGIN x.mode := ORB.Const; x.type := ORB.realType;
    (* reinterpret the IEEE-32 bit pattern as an integer. VAL target is
       INTEGER (4 bytes = REAL) so this holds whether the compiler's
       LONGINT is 4 (816 self-host) or 8 (LLVM stage-0). *)
    x.a := SYSTEM.VAL(INTEGER, val)
  END MakeRealItem;

  PROCEDURE MakeStringItem*(VAR x: Item; len: LONGINT);
    VAR i: LONGINT;
  BEGIN
    x.mode := ORB.Const; x.type := ORB.strType; x.a := strx; x.b := len;
    IF strx + len < maxStrx THEN
      i := 0;
      WHILE len > 0 DO
        wa.str[strx] := ORD(ORS.str[i]); strx := strx + 1; i := i + 1; len := len - 1
      END
    ELSE ORS.Mark("too many strings")
    END
  END MakeStringItem;

  PROCEDURE MakeDataItem*(VAR x: Item; typ: ORB.Type; offset, size: LONGINT);
  BEGIN x.mode := ORB.Var; x.type := typ; x.a := offset; x.b := 0; x.r := 0;
    x.rdo := TRUE; x.origType := typ
  END MakeDataItem;

  PROCEDURE StrOffset*(): LONGINT;
  BEGIN RETURN strx
  END StrOffset;

  PROCEDURE PutByte*(b: INTEGER);
  BEGIN
    IF strx < maxStrx THEN wa.str[strx] := b MOD 100H; strx := strx + 1
    ELSE ORS.Mark("string space overflow")
    END
  END PutByte;

  (* patch `size` little-endian bytes of `val` at data offset `off` (used by
     the record-literal builder to place a field's constant value at its
     offset within an already-reserved, zero-filled record image) *)
  PROCEDURE PatchStr*(off, val, size: LONGINT);
    VAR i: LONGINT;
  BEGIN i := 0;
    WHILE i < size DO
      IF off + i < maxStrx THEN wa.str[off + i] := val MOD 100H END;
      val := val DIV 100H; i := i + 1
    END
  END PatchStr;

  (* copy `size` bytes within the data section (a nested const record/array
     field value already emitted at srcOff is folded into the parent image) *)
  PROCEDURE CopyStr*(dstOff, srcOff, size: LONGINT);
    VAR i: LONGINT;
  BEGIN i := 0;
    WHILE i < size DO
      IF (dstOff + i < maxStrx) & (srcOff + i < maxStrx) THEN
        wa.str[dstOff + i] := wa.str[srcOff + i]
      END;
      i := i + 1
    END
  END CopyStr;

  (* a constant record/array value living in the data section at offset
     `start`; loadAdr resolves it to SB + varsize + start (see below) *)
  PROCEDURE MakeRecordConst*(VAR x: Item; typ: ORB.Type; start: LONGINT);
  BEGIN
    x.mode := ORB.Const; x.type := typ; x.a := start; x.b := typ.size;
    x.r := 0; x.rdo := TRUE; x.origType := typ;
    x.isMeth := FALSE; x.dynDisp := FALSE; x.ifaceDisp := FALSE
  END MakeRecordConst;

  PROCEDURE MakeItem*(VAR x: Item; y: ORB.Object; curlev: LONGINT);
  BEGIN
    x.isMeth := FALSE; x.dynDisp := FALSE; x.ifaceDisp := FALSE;   (* clear stale OO state on reuse *)
    x.mode := y.class; x.type := y.type; x.a := y.val; x.rdo := y.rdo;
    IF y.class = ORB.Par THEN x.b := 0
    ELSIF (y.class = ORB.Const) & (y.type.form = ORB.String) THEN x.b := y.lev
    ELSIF (y.class = ORB.Const) &
          ((y.type.form = ORB.Array) OR (y.type.form = ORB.Record)) THEN
      IF y.lev < 0 THEN x.mode := ORB.Var; x.r := y.lev; x.rdo := TRUE END;
      x.b := y.type.size
    ELSIF (y.class = ORB.Const) & (y.type.form = ORB.Proc) THEN
      x.r := y.lev; IF y.expo THEN x.b := 1 ELSE x.b := 0 END
    ELSE x.r := y.lev
    END;
    IF (y.lev > 0) & (y.lev # curlev) & (y.class # ORB.Const) THEN
      ORS.Mark("not accessible ")
    END
  END MakeItem;

  PROCEDURE Field*(VAR x: Item; y: ORB.Object);
  BEGIN
    IF x.mode = ORB.Var THEN
      IF x.r >= 0 THEN x.a := x.a + y.val
      ELSE loadAdr(x); x.mode := RegI; x.a := y.val
      END
    ELSIF x.mode = RegI THEN x.a := x.a + y.val
    ELSIF x.mode = ORB.Par THEN x.b := x.b + y.val
    ELSIF x.mode = ORB.Const THEN
      x.a := varsize + x.a + y.val; x.mode := ORB.Var; x.r := 0
    END
  END Field;

  PROCEDURE Index*(VAR x, y: Item);
    VAR s, lim, shifts, ts, idxReg, remaining, sb, i: LONGINT;
      runtime: BOOLEAN;
  BEGIN
    s := x.type.base.size; lim := x.type.len;
    runtime := (y.mode # ORB.Const) OR (lim < 0);
    IF ~runtime THEN
      IF (y.a < 0) OR (y.a >= lim) THEN ORS.Mark("bad index") END;
      IF (x.mode = ORB.Var) & (x.r > 0) & (y.a * s + x.a + frame > 255) THEN
        runtime := TRUE   (* offset too large for LDA nn,S; use runtime path *)
      ELSIF (x.mode = ORB.Var) OR (x.mode = RegI) THEN
        x.a := y.a * s + x.a
      ELSIF x.mode = ORB.Par THEN
        x.b := y.a * s + x.b
      ELSIF x.mode = ORB.Const THEN
        x.a := varsize + y.a * s + x.a; x.mode := ORB.Var; x.r := 0
      END
    END;
    IF runtime THEN
      load(y);
      IF check THEN
        IF lim >= 0 THEN
          Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
          OCG.gen1(OCG.CMP * 32 + OCG.mImm, lim);
          Trap(LT, 1)
        ELSIF (x.mode = ORB.Var) OR (x.mode = ORB.Par) THEN
          Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
          OCG.gen1(OCG.CMP * 32 + OCG.mSR, x.a + 4 + frame);
          Trap(LT, 1)
        ELSE ORS.Mark("error in Index")
        END
      END;
      Set16(TRUE, TRUE);
      IF s > 1 THEN
        shifts := 0; ts := s;
        WHILE (ts > 1) & ~ODD(ts) DO ts := ts DIV 2; shifts := shifts + 1 END;
        IF ts = 1 THEN
          i := 0;
          WHILE i < shifts DO OCG.gen1(OCG.ASL * 32 + OCG.mDP, RegAddr(y.r)); i := i + 1 END
        ELSE
          idxReg := RegAddr(y.r);
          i := 0;
          WHILE i < shifts DO OCG.gen1(OCG.ASL * 32 + OCG.mDP, idxReg); i := i + 1 END;
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, idxReg);
          remaining := ts DIV 2;
          WHILE remaining > 0 DO
            OCG.gen1(OCG.ASL * 32 + OCG.mDP, idxReg);
            IF ODD(remaining) THEN
              OCG.Clc;
              OCG.gen1(OCG.ADC * 32 + OCG.mDP, idxReg)
            END;
            remaining := remaining DIV 2
          END;
          OCG.gen1(OCG.STA * 32 + OCG.mDP, idxReg)
        END
      END;
      IF x.mode = ORB.Var THEN
        IF x.r > 0 THEN
          Set16(TRUE, TRUE);
          OCG.Tsc;
          OCG.Clc;
          OCG.gen1(OCG.ADC * 32 + OCG.mImm, x.a + frame);
          OCG.gen1(OCG.ADC * 32 + OCG.mDP, RegAddr(y.r));
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(y.r))
        ELSE
          sb := GetSB(x.r);
          Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, sb);
          OCG.Clc;
          OCG.gen1(OCG.ADC * 32 + OCG.mImm, x.a);
          OCG.gen1(OCG.ADC * 32 + OCG.mDP, RegAddr(y.r));
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(y.r))
        END;
        OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(RH));
        x.a := 0; x.r := y.r; x.mode := RegI; incR
      ELSIF x.mode = ORB.Par THEN
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + frame);
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mDP, RegAddr(y.r));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(y.r));
        OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 2 + frame);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
        incR;
        x.mode := RegI; x.r := y.r; x.a := x.b
      ELSIF x.mode = ORB.Const THEN
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, SB_DP);
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mImm, varsize + x.a);
        OCG.gen1(OCG.ADC * 32 + OCG.mDP, RegAddr(y.r));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(y.r));
        OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(RH));
        x.a := 0; x.r := y.r; x.mode := RegI; incR
      ELSIF x.mode = RegI THEN
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mDP, RegAddr(y.r));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r));
        RH := RH - 1
      END
    END
  END Index;

  PROCEDURE DeRef*(VAR x: Item);
    VAR sb: LONGINT;
  BEGIN
    Set16(TRUE, TRUE);
    IF x.mode = ORB.Var THEN
      IF x.r > 0 THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + frame);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
        OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 2 + frame);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1))
      ELSE
        sb := GetSB(x.r);
        OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
        OCG.gen1(OCG.LDA * 32 + OCG.mDPIndY, sb);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
        OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a + 2);
        OCG.gen1(OCG.LDA * 32 + OCG.mDPIndY, sb);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1))
      END;
      IF check THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH));
        OCG.gen1(OCG.ORA * 32 + OCG.mDP, RegAddr(RH + 1));
        Trap(NE, 4)
      END;
      x.r := RH; incR; incR
    ELSIF x.mode = ORB.Par THEN
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 2 + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1));
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.b + 2);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(RH));
      OCG.Pha;
      IF x.b = 0 THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, RegAddr(RH))
      ELSE
        OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.b);
        OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(RH))
      END;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
      OCG.Pla;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1));
      IF check THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH));
        OCG.gen1(OCG.ORA * 32 + OCG.mDP, RegAddr(RH + 1));
        Trap(NE, 4)
      END;
      x.r := RH; incR; incR
    ELSIF x.mode = RegI THEN
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a + 2);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(x.r));
      OCG.Pha;
      IF x.a = 0 THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, RegAddr(x.r))
      ELSE
        OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
        OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(x.r))
      END;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r));
      OCG.Pla;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r + 1));
      IF check THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
        OCG.gen1(OCG.ORA * 32 + OCG.mDP, RegAddr(x.r + 1));
        Trap(NE, 4)
      END
    ELSIF x.mode # Reg THEN ORS.Mark("bad mode in DeRef")
    END;
    x.mode := RegI; x.a := 0; x.b := 0
  END DeRef;

  (* --- type descriptors --- *)
  PROCEDURE Q(T: ORB.Type; VAR dcw: LONGINT);
  BEGIN
    IF T.base # NIL THEN
      Q(T.base, dcw);
      wa.data[dcw] := T.len; wa.data[dcw + 1] := 0;
      wa.tdFixupOff[tdFixupC] := tdBase + dcw * 2; wa.tdFixupMno[tdFixupC] := T.mno;
      tdFixupC := tdFixupC + 1;
      dcw := dcw + 2
    END
  END Q;

  PROCEDURE FindPtrFlds(typ: ORB.Type; off: LONGINT; VAR dcw: LONGINT);
    VAR fld: ORB.Object; i, s: LONGINT;
  BEGIN
    IF (typ.form = ORB.Pointer) OR (typ.form = ORB.NilTyp) THEN
      wa.data[dcw] := off; dcw := dcw + 1
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
    IF tdListC < maxTD THEN tdList[tdListC] := T; tdListC := tdListC + 1
    ELSE ORS.Mark("too many record types")
    END
  END BuildTD;

  (* Emit `ADC #<T's descriptor offset>`. Own-module T.len is not known until
     GenTDs, so leave a placeholder + forward fixup; imported types already
     carry their offset in the .smb. *)
  PROCEDURE emitTDLen(T: ORB.Type);
  BEGIN
    IF T.mno <= 0 THEN
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, 0);
      IF tdRefC < maxTD THEN
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
        IF rm # NIL THEN wa.data[vtword + m.val] := rm.val END
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
    tdBase := varsize + strx; dcw := 0; i := 0;
    WHILE i < tdListC DO
      T := tdList[i];
      T.len := tdBase + dcw * 2;
      wa.data[dcw] := T.size; dcw := dcw + 1;
      k := T.nofpar;
      IF k > 3 THEN ORS.Mark("ext level too large")
      ELSE
        Q(T, dcw);
        WHILE k < 3 DO
          wa.data[dcw] := 0FFFFH; wa.data[dcw + 1] := 0FFFFH;
          dcw := dcw + 2; k := k + 1
        END
      END;
      (* method vtable: nofmeth (TOTAL incl. inherited), then that many 2-byte
         slots holding the ABSOLUTE in-bank code address of the most-derived
         impl. All modules load into one bank, so the loader fills every slot:
         an own method (mno=0) as module_base + its code offset; an imported
         inherited one (mno>0) via (mno, exno). Dispatch just reads the slot —
         no per-caller code base, which is what makes an imported object's
         method reachable from any module. *)
      nm := ORB.TotalMeths(T);
      IF nm > maxMeth THEN ORS.Mark("too many methods"); nm := 0 END;
      wa.data[dcw] := nm; dcw := dcw + 1;
      IF nm > 0 THEN
        s := 0; WHILE s < nm DO slotMeth[s] := NIL; slotMno[s] := 0; s := s + 1 END;
        fillVt(T, nm);
        s := 0;
        WHILE s < nm DO
          IF slotMeth[s] = NIL THEN wa.data[dcw + s] := 0   (* abstract: no impl *)
          ELSE
            IF vtFixC >= maxVtFix THEN ORS.Mark("too many vtable fixups")
            ELSE
              wa.vtFixOff[vtFixC] := tdBase + (dcw + s) * 2;
              IF slotMno[s] <= 0 THEN   (* own method: slot = base + offset *)
                wa.data[dcw + s] := slotMeth[s].backend;
                wa.vtFixMno[vtFixC] := 0; wa.vtFixExno[vtFixC] := 0
              ELSE                      (* imported inherited: loader resolves *)
                wa.data[dcw + s] := 0;
                wa.vtFixMno[vtFixC] := slotMno[s];
                wa.vtFixExno[vtFixC] := slotMeth[s].exno
              END;
              vtFixC := vtFixC + 1
            END
          END;
          s := s + 1
        END;
        dcw := dcw + nm
      END;
      FindPtrFlds(T, 0, dcw);
      wa.data[dcw] := 0FFFFH; dcw := dcw + 1;
      i := i + 1
    END;
    (* interface itables: for each (record, interface), one 2-byte entry per
       interface method holding the record's vtable slot for that method
       (indices, so overrides and cross-module callers stay correct). *)
    i := 0;
    WHILE i < itabC DO
      itabOff[i] := tdBase + dcw * 2;
      nm := itabIfc[i].nofmeth;
      s := 0; WHILE s < nm DO wa.data[dcw + s] := 0; s := s + 1 END;
      fillItab(itabIfc[i], itabRec[i], nm, dcw);
      dcw := dcw + nm;
      i := i + 1
    END;
    tdx := dcw;
    IF tdx >= maxTD THEN ORS.Mark("too many record types"); tdx := 0 END;
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

  PROCEDURE TypeTest*(VAR x: Item; T: ORB.Type; varpar, isguard: BOOLEAN);
    VAR offset, sb, nilSkip: LONGINT;
  BEGIN
    IF T = NIL THEN
      IF x.mode >= Reg THEN RH := RH - 1 END;
      SetCC(x, AL)
    ELSIF varpar THEN
      Set16(TRUE, TRUE);
      incR; incR;
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 4 + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 2));
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 6 + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 1));
      offset := 2 + (T.nofpar - 1) * 4;
      OCG.Clc;
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH - 2));
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, offset);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 2));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH - 1));
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 1));
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, RegAddr(RH - 2));
      OCG.Pha;
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, 2);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(RH - 2));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 1));
      OCG.Pla;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 2));
      sb := GetSB(-T.mno);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, sb);
      OCG.Clc;
      emitTDLen(T);
      OCG.gen1(OCG.EOR * 32 + OCG.mDP, RegAddr(RH - 2));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 2));
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.EOR * 32 + OCG.mDP, RegAddr(RH - 1));
      OCG.gen1(OCG.ORA * 32 + OCG.mDP, RegAddr(RH - 2));
      RH := RH - 2;
      IF isguard THEN
        IF check THEN Trap(EQ, 2) END
      ELSE x.origType := ORB.intType; SetCC(x, EQ)
      END
    ELSE
      load(x);
      Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
      OCG.gen1(OCG.ORA * 32 + OCG.mDP, RegAddr(x.r + 1));
      nilSkip := emitFwdBranch(OCG.BEQ);
      incR; incR;
      OCG.Sec;
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
      OCG.gen1(OCG.SBC * 32 + OCG.mImm, 4);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 2));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r + 1));
      OCG.gen1(OCG.SBC * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 1));
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, RegAddr(RH - 2));
      OCG.Pha;
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, 2);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(RH - 2));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 1));
      OCG.Pla;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 2));
      offset := 2 + (T.nofpar - 1) * 4;
      OCG.Clc;
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH - 2));
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, offset);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 2));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH - 1));
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 1));
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, RegAddr(RH - 2));
      OCG.Pha;
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, 2);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(RH - 2));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 1));
      OCG.Pla;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 2));
      sb := GetSB(-T.mno);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, sb);
      OCG.Clc;
      emitTDLen(T);
      OCG.gen1(OCG.EOR * 32 + OCG.mDP, RegAddr(RH - 2));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 2));
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.EOR * 32 + OCG.mDP, RegAddr(RH - 1));
      OCG.gen1(OCG.ORA * 32 + OCG.mDP, RegAddr(RH - 2));
      RH := RH - 2;
      patch(nilSkip);
      IF isguard THEN
        IF check THEN Trap(EQ, 2) END
      ELSE x.origType := ORB.intType; SetCC(x, EQ); RH := RH - 2
      END
    END
  END TypeTest;

  (* --- boolean operators --- *)
  PROCEDURE Not*(VAR x: Item);
    VAR t: LONGINT;
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END;
    x.r := negated(x.r);
    t := x.a; x.a := x.b; x.b := t
  END Not;

  PROCEDURE And1*(VAR x: Item);
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END;
    emitBranch(negated(x.r), x.origType, OCG.mFix, x.a);
    x.a := OCG.Here() - 2;
    FixLink(x.b); x.b := 0
  END And1;

  PROCEDURE And2*(VAR x, y: Item);
  BEGIN
    IF y.mode # Cond THEN loadCond(y) END;
    x.a := merged(y.a, x.a); x.b := y.b; x.r := y.r; x.origType := y.origType
  END And2;

  PROCEDURE Or1*(VAR x: Item);
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END;
    emitBranch(x.r, x.origType, OCG.mFix, x.b);
    x.b := OCG.Here() - 2;
    FixLink(x.a); x.a := 0
  END Or1;

  PROCEDURE Or2*(VAR x, y: Item);
  BEGIN
    IF y.mode # Cond THEN loadCond(y) END;
    x.a := y.a; x.b := merged(y.b, x.b); x.r := y.r; x.origType := y.origType
  END Or2;

  (* --- arithmetic --- *)
  PROCEDURE Neg*(VAR x: Item);
  BEGIN
    IF x.type.form = ORB.Int THEN
      Set16(TRUE, TRUE);
      IF x.mode = ORB.Const THEN x.a := -x.a
      ELSE
        load(x);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
        OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mImm, 1);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r))
      END
    ELSIF x.type.form = ORB.Real THEN
      IF x.mode = ORB.Const THEN x.a := EOR(x.a, 80000000H)
      ELSE
        load(x); Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r + 1));
        OCG.gen1(OCG.EOR * 32 + OCG.mImm, 8000H);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r + 1))
      END
    ELSE (* Set *)
      IF x.mode = ORB.Const THEN x.a := -x.a - 1
      ELSE
        load(x);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
        OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r))
      END
    END
  END Neg;

  PROCEDURE AddOp*(op: LONGINT; VAR x, y: Item);
    VAR destR: LONGINT;
  BEGIN
    IF op = ORS.plus THEN
      IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a + y.a
      ELSIF x.mode = ORB.Const THEN
        load(y);
        IF x.a # 0 THEN
          IF y.type.form = ORB.Int THEN
            Set16(TRUE, TRUE);
            OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
            OCG.Clc;
            OCG.gen1(OCG.ADC * 32 + OCG.mImm, x.a);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(y.r))
          END
        END;
        x.mode := y.mode; x.r := y.r
      ELSIF y.mode = ORB.Const THEN
        load(x);
        IF y.a # 0 THEN
          IF x.type.form = ORB.Int THEN
            Set16(TRUE, TRUE);
            OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
            OCG.Clc;
            OCG.gen1(OCG.ADC * 32 + OCG.mImm, y.a);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r))
          END
        END
      ELSE
        load(x); load(y);
        IF x.type.form = ORB.Int THEN
          destR := RH - 2; Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
          OCG.Clc;
          OCG.gen1(OCG.ADC * 32 + OCG.mDP, RegAddr(y.r));
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(destR))
        END;
        RH := RH - 1; x.r := RH - 1
      END
    ELSE (* minus *)
      IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a - y.a
      ELSIF y.mode = ORB.Const THEN
        load(x);
        IF y.a # 0 THEN
          IF x.type.form = ORB.Int THEN
            Set16(TRUE, TRUE);
            OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
            OCG.Sec;
            OCG.gen1(OCG.SBC * 32 + OCG.mImm, y.a);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r))
          END
        END
      ELSE
        load(x); load(y);
        IF x.type.form = ORB.Int THEN
          destR := RH - 2; Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
          OCG.Sec;
          OCG.gen1(OCG.SBC * 32 + OCG.mDP, RegAddr(y.r));
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(destR))
        END;
        RH := RH - 1; x.r := RH - 1
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
    Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
    OCG.gen1(OCG.LDX * 32 + OCG.mDP, RegAddr(xr));
    OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 2 + 11);
    OCG.gen1(OCG.LSR * 32 + OCG.mDP, RegAddr(xr));
    OCG.gen1(OCG.BCC * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
    OCG.Clc;
    OCG.gen1(OCG.ADC * 32 + OCG.mDP, RegAddr(yr));
    OCG.gen1(OCG.ASL * 32 + OCG.mDP, RegAddr(yr));
    OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 - 15)
  END mulLoop;

  PROCEDURE MulOp*(VAR x, y: Item);
    VAR e, loopTop: LONGINT;
  BEGIN
    IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a * y.a
    ELSIF (y.mode = ORB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN
      load(x); Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDX * 32 + OCG.mImm, e);
      loopTop := OCG.Here();
      OCG.gen1(OCG.ASL * 32 + OCG.mDP, RegAddr(x.r));
      OCG.Dex;
      OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop)
    ELSIF y.mode = ORB.Const THEN
      load(x); load(y); mulLoop(x.r, y.r);
      RH := RH - 1; x.r := RH - 1;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r))
    ELSIF (x.mode = ORB.Const) & (x.a >= 2) & (log2(x.a, e) = 1) THEN
      load(y); Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDX * 32 + OCG.mImm, e);
      loopTop := OCG.Here();
      OCG.gen1(OCG.ASL * 32 + OCG.mDP, RegAddr(y.r));
      OCG.Dex;
      OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
      x.mode := Reg; x.r := y.r
    ELSE
      load(x); load(y); mulLoop(x.r, y.r);
      RH := RH - 1; x.r := RH - 1;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r))
    END
  END MulOp;

  PROCEDURE genDivLoop(dividendReg, divisorReg, quotientReg: LONGINT);
    VAR loopTop: LONGINT;
  BEGIN
    Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(quotientReg));
    loopTop := OCG.Here();
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(dividendReg));
    OCG.gen1(OCG.CMP * 32 + OCG.mDP, RegAddr(divisorReg));
    OCG.gen1(OCG.BCC * 32 + OCG.mPCR, OCG.Here() + 2 + 11);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(dividendReg));
    OCG.Sec;
    OCG.gen1(OCG.SBC * 32 + OCG.mDP, RegAddr(divisorReg));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(dividendReg));
    OCG.gen1(OCG.INC * 32 + OCG.mDP, RegAddr(quotientReg));
    OCG.gen1(OCG.BRA * 32 + OCG.mPCR, loopTop)
  END genDivLoop;

  PROCEDURE DivOp*(op: LONGINT; VAR x, y: Item);
    VAR e, i, divisorReg, quotientReg: LONGINT;
  BEGIN
    IF op = ORS.div THEN
      IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
        IF y.a > 0 THEN x.a := x.a DIV y.a ELSE ORS.Mark("bad divisor") END
      ELSIF (y.mode = ORB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN
        load(x); i := 0;
        WHILE i < e DO
          OCG.gen1(OCG.CMP * 32 + OCG.mImm, 8000H);
          OCG.gen1(OCG.ROR * 32 + OCG.mImpl, 0);
          i := i + 1
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r))
      ELSIF y.mode = ORB.Const THEN
        IF y.a > 0 THEN
          load(x); Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mImm, y.a);
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
          divisorReg := RH; incR; quotientReg := RH; incR;
          genDivLoop(x.r, divisorReg, quotientReg);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(quotientReg));
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r));
          RH := RH - 2
        ELSE ORS.Mark("bad divisor")
        END
      ELSE
        load(y);
        IF check THEN Trap(LE, 6) END;
        load(x);
        quotientReg := RH; incR;
        genDivLoop(x.r, y.r, quotientReg);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(quotientReg));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(y.r));
        x.r := y.r; RH := y.r + 1
      END
    ELSE (* mod *)
      IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
        IF y.a > 0 THEN x.a := x.a MOD y.a ELSE ORS.Mark("bad modulus") END
      ELSIF (y.mode = ORB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN
        load(x); Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
        OCG.gen1(OCG.AND * 32 + OCG.mImm, y.a - 1);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r))
      ELSIF y.mode = ORB.Const THEN
        IF y.a > 0 THEN
          load(x); Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mImm, y.a);
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
          divisorReg := RH; incR; quotientReg := RH; incR;
          genDivLoop(x.r, divisorReg, quotientReg);
          RH := RH - 2
        ELSE ORS.Mark("bad modulus")
        END
      ELSE
        load(y);
        IF check THEN Trap(LE, 6) END;
        load(x);
        quotientReg := RH; incR;
        genDivLoop(x.r, y.r, quotientReg);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(y.r));
        x.r := y.r; RH := y.r + 1
      END
    END
  END DivOp;


  PROCEDURE RealOp*(op: INTEGER; VAR x, y: Item);
  BEGIN
    load(x); load(y); Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_A_LO);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r + 1));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_A_HI);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_B_LO);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r + 1));
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
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGFP.FP_A_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r));
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGFP.FP_A_HI);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r + 1));
    RH := RH - 2; x.r := RH - 2
  END RealOp;

  (* --- sets --- *)
  PROCEDURE Singleton*(VAR x: Item);
    VAR skip, loopTop: LONGINT;
  BEGIN
    IF x.mode = ORB.Const THEN x.a := ASL(1, x.a)
    ELSE
      load(x); Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, 1);
      OCG.gen1(OCG.LDX * 32 + OCG.mDP, RegAddr(x.r));
      skip := OCG.Here() + 2 + 4;
      OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, skip);
      loopTop := OCG.Here();
      OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);
      OCG.Dex;
      OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r))
    END
  END Singleton;

  PROCEDURE Set*(VAR x, y: Item);
    VAR skip, loopTop, mask: LONGINT;
  BEGIN
    IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
      IF x.a <= y.a THEN x.a := ASL(2, y.a) - ASL(1, x.a) ELSE x.a := 0 END
    ELSE
      IF (x.mode = ORB.Const) & (x.a <= 15) THEN
        load(x); Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, Lo16(ASL(0FFFFH, x.a)));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r))
      ELSE
        load(x); Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0FFFFH);
        OCG.gen1(OCG.LDX * 32 + OCG.mDP, RegAddr(x.r));
        skip := OCG.Here() + 2 + 4;
        OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, skip);
        loopTop := OCG.Here();
        OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);
        OCG.Dex;
        OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r))
      END;
      IF (y.mode = ORB.Const) & (y.a < 15) THEN
        mask := Lo16(EOR(ASL(0FFFEH, y.a), 0FFFFH));
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, mask);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
        y.mode := Reg; y.r := RH; incR
      ELSE
        load(y); Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0FFFEH);
        OCG.gen1(OCG.LDX * 32 + OCG.mDP, RegAddr(y.r));
        skip := OCG.Here() + 2 + 4;
        OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, skip);
        loopTop := OCG.Here();
        OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);
        OCG.Dex;
        OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
        OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(y.r))
      END;
      IF x.mode = ORB.Const THEN x.mode := Reg END;
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
      OCG.gen1(OCG.AND * 32 + OCG.mDP, RegAddr(y.r));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r));
      RH := RH - 1; x.r := RH - 1
    END
  END Set;

  PROCEDURE In*(VAR x, y: Item);
    VAR skip, loopTop: LONGINT;
  BEGIN
    load(y); Set16(TRUE, TRUE);
    IF x.mode = ORB.Const THEN
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
      OCG.gen1(OCG.AND * 32 + OCG.mImm, Lo16(ASL(1, x.a)));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(y.r));
      RH := RH - 1
    ELSE
      load(x);
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, 1);
      OCG.gen1(OCG.LDX * 32 + OCG.mDP, RegAddr(x.r));
      skip := OCG.Here() + 2 + 4;
      OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, skip);
      loopTop := OCG.Here();
      OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);
      OCG.Dex;
      OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
      OCG.gen1(OCG.AND * 32 + OCG.mDP, RegAddr(y.r));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(y.r));
      RH := RH - 2
    END;
    SetCC(x, NE)
  END In;

  PROCEDURE SetOp*(op: LONGINT; VAR x, y: Item);
  BEGIN
    IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
      IF op = ORS.plus THEN x.a := ORA(x.a, y.a)
      ELSIF op = ORS.minus THEN x.a := AND(x.a, EOR(y.a, 0FFFFH))
      ELSIF op = ORS.times THEN x.a := AND(x.a, y.a)
      ELSIF op = ORS.rdiv THEN x.a := EOR(x.a, y.a)
      END
    ELSIF y.mode = ORB.Const THEN
      load(x);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
      IF op = ORS.plus THEN OCG.gen1(OCG.ORA * 32 + OCG.mImm, y.a)
      ELSIF op = ORS.minus THEN OCG.gen1(OCG.AND * 32 + OCG.mImm, Lo16(EOR(y.a, 0FFFFH)))
      ELSIF op = ORS.times THEN OCG.gen1(OCG.AND * 32 + OCG.mImm, y.a)
      ELSIF op = ORS.rdiv THEN OCG.gen1(OCG.EOR * 32 + OCG.mImm, y.a)
      END;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r))
    ELSE
      load(x); load(y);
      IF op = ORS.plus THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
        OCG.gen1(OCG.ORA * 32 + OCG.mDP, RegAddr(y.r));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 2))
      ELSIF op = ORS.minus THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
        OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
        OCG.gen1(OCG.AND * 32 + OCG.mDP, RegAddr(x.r));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 2))
      ELSIF op = ORS.times THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
        OCG.gen1(OCG.AND * 32 + OCG.mDP, RegAddr(y.r));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 2))
      ELSIF op = ORS.rdiv THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
        OCG.gen1(OCG.EOR * 32 + OCG.mDP, RegAddr(y.r));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 2))
      END;
      RH := RH - 1; x.r := RH - 1
    END
  END SetOp;

  (* --- relations --- *)
  PROCEDURE IntRelation*(op: INTEGER; VAR x, y: Item);
    VAR isPointer, use8, useSigned, signedCmp: BOOLEAN;
  BEGIN
    isPointer := (x.type.form = ORB.Pointer) OR (x.type.form = ORB.NilTyp) OR (x.type.form = ORB.Proc);
    use8 := ~isPointer & ((x.type.form = ORB.Char) OR (x.type.form = ORB.Byte) OR (x.type.form = ORB.Bool));
    useSigned := ~isPointer & ~use8 & (x.type.form = ORB.Int);
    IF isPointer THEN
      Set16(TRUE, TRUE);
      IF (y.mode = ORB.Const) & (y.a = 0) THEN
        load(x);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
        OCG.gen1(OCG.ORA * 32 + OCG.mDP, RegAddr(x.r + 1));
        RH := RH - 2
      ELSE
        load(x); load(y);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
        OCG.gen1(OCG.CMP * 32 + OCG.mDP, RegAddr(y.r));
        OCG.gen1(OCG.BNE * 32 + OCG.mPCR, OCG.Here() + 2 + 4);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r + 1));
        OCG.gen1(OCG.CMP * 32 + OCG.mDP, RegAddr(y.r + 1));
        RH := RH - 4
      END
    ELSE
      IF use8 THEN Set8(TRUE, FALSE) END;
      signedCmp := useSigned & ((op = ORS.lss) OR (op = ORS.geq) OR (op = ORS.leq) OR (op = ORS.gtr));
      IF (y.mode = ORB.Const) & (y.type.form # ORB.Proc) THEN
        load(x);
        IF (y.a # 0) OR ((op # ORS.eql) & (op # ORS.neq)) THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
          IF signedCmp THEN
            OCG.Sec;
            OCG.gen1(OCG.SBC * 32 + OCG.mImm, y.a)
          ELSE
            OCG.gen1(OCG.CMP * 32 + OCG.mImm, y.a)
          END
        END;
        RH := RH - 1
      ELSE
        IF (x.mode = Cond) OR (y.mode = Cond) THEN ORS.Mark("not implemented") END;
        load(x); load(y);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
        IF signedCmp THEN
          OCG.Sec;
          OCG.gen1(OCG.SBC * 32 + OCG.mDP, RegAddr(y.r))
        ELSE
          OCG.gen1(OCG.CMP * 32 + OCG.mDP, RegAddr(y.r))
        END;
        RH := RH - 2
      END;
      IF use8 THEN Set16(TRUE, TRUE) END
    END;
    SetCC(x, relmap[op - ORS.eql])
  END IntRelation;

  PROCEDURE RealRelation*(op: INTEGER; VAR x, y: Item);
  BEGIN
    load(x); Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_A_LO);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r + 1));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_A_HI);
    IF (y.mode = ORB.Const) & (y.a = 0) THEN
      OCG.gen1(OCG.STZ * 32 + OCG.mDP, ORGFP.FP_B_LO);
      OCG.gen1(OCG.STZ * 32 + OCG.mDP, ORGFP.FP_B_HI);
      RH := RH - 2
    ELSE
      load(y);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_B_LO);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r + 1));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_B_HI);
      RH := RH - 4
    END;
    ORGFP.AddFixup(ORGFP.FP_CMP); OCG.gen1(OCG.JSR * 32 + OCG.mAbs, 0);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGFP.FP_A_LO);
    SetCC(x, relmap[op - ORS.eql]);
    x.origType := ORB.intType
  END RealRelation;

  PROCEDURE StringRelation*(op: INTEGER; VAR x, y: Item);
  BEGIN
    IF x.type.form = ORB.String THEN loadStringAdr(x) ELSE loadAdr(x) END;
    IF y.type.form = ORB.String THEN loadStringAdr(y) ELSE loadAdr(y) END;
    RH := RH - 2;
    SetCC(x, relmap[op - ORS.eql])
  END StringRelation;

  (* --- assignment --- *)
  PROCEDURE StrToChar*(VAR x: Item);
  BEGIN x.type := ORB.charType; x.a := wa.str[x.a]
  END StrToChar;

  PROCEDURE Store*(VAR x, y: Item);
    VAR sb: LONGINT;
  BEGIN
    load(y);
    IF x.mode = ORB.Var THEN
      IF x.r > 0 THEN
        IF (x.type.form = ORB.Pointer) OR (x.type.form = ORB.NilTyp)
           OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) THEN
          Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, x.a + frame);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r + 1));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, x.a + 2 + frame);
          RH := RH - 1
        ELSIF (x.type.size = 1) & (y.type.size >= 1) THEN
          Set8(TRUE, FALSE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, x.a + frame);
          Set16(TRUE, FALSE)
        ELSE
          Set16(TRUE, FALSE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, x.a + frame);
          Set16(TRUE, FALSE)
        END
      ELSE
        sb := GetSB(x.r);
        IF (x.type.form = ORB.Pointer) OR (x.type.form = ORB.NilTyp)
           OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) THEN
          Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
          OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
          OCG.gen1(OCG.STA * 32 + OCG.mDPIndY, sb);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r + 1));
          OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a + 2);
          OCG.gen1(OCG.STA * 32 + OCG.mDPIndY, sb);
          RH := RH - 1
        ELSIF (x.type.size = 1) & (y.type.size >= 1) THEN
          Set8(TRUE, FALSE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
          OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
          OCG.gen1(OCG.STA * 32 + OCG.mDPIndY, sb);
          Set16(TRUE, FALSE)
        ELSE
          Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
          OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
          OCG.gen1(OCG.STA * 32 + OCG.mDPIndY, sb)
        END
      END
    ELSIF x.mode = ORB.Par THEN
      Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 2 + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1));
      IF (x.type.form = ORB.Pointer) OR (x.type.form = ORB.NilTyp)
         OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
        OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.b);
        OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, RegAddr(RH));
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r + 1));
        OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.b + 2);
        OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, RegAddr(RH));
        RH := RH - 1
      ELSIF x.type.size = 1 THEN
        Set8(TRUE, FALSE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
        IF x.b # 0 THEN
          OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.b);
          OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, RegAddr(RH))
        ELSE OCG.gen1(OCG.STA * 32 + OCG.mDPIndL, RegAddr(RH))
        END;
        Set16(TRUE, FALSE)
      ELSE
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
        IF x.b # 0 THEN
          OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.b);
          OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, RegAddr(RH))
        ELSE OCG.gen1(OCG.STA * 32 + OCG.mDPIndL, RegAddr(RH))
        END
      END
    ELSIF x.mode = RegI THEN
      IF (x.type.form = ORB.Pointer) OR (x.type.form = ORB.NilTyp)
         OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) THEN
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
        IF x.a = 0 THEN OCG.gen1(OCG.STA * 32 + OCG.mDPIndL, RegAddr(x.r))
        ELSE
          OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
          OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, RegAddr(x.r))
        END;
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r + 1));
        OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a + 2);
        OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, RegAddr(x.r));
        RH := RH - 1
      ELSIF x.type.size = 1 THEN
        Set8(TRUE, FALSE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
        IF x.a = 0 THEN OCG.gen1(OCG.STA * 32 + OCG.mDPIndL, RegAddr(x.r))
        ELSE
          OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
          OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, RegAddr(x.r))
        END;
        Set16(TRUE, FALSE)
      ELSE
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
        IF x.a = 0 THEN OCG.gen1(OCG.STA * 32 + OCG.mDPIndL, RegAddr(x.r))
        ELSE
          OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
          OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, RegAddr(x.r))
        END
      END;
      RH := RH - 2
    ELSE ORS.Mark("bad mode in Store")
    END;
    RH := RH - 1
  END Store;

  PROCEDURE StoreStruct*(VAR x, y: Item);
    VAR s, wordCount, dstReg, srcReg, loopTop, elemSz, k, i, t: LONGINT;
        valid, openSrc: BOOLEAN;
  BEGIN
    IF y.type.size # 0 THEN
      openSrc := FALSE; k := 0;
      loadAdr(x); loadAdr(y);
      dstReg := RegAddr(x.r); srcReg := RegAddr(y.r);
      valid := TRUE; s := 0;
      IF (x.type.form = ORB.Array) & (x.type.len > 0) THEN
        IF y.type.len >= 0 THEN
          IF x.type.size = y.type.size THEN s := y.type.size
          ELSE ORS.Mark("different length/size, not implemented"); valid := FALSE
          END
        ELSE
          (* Open-array source: the byte count is LEN(y) * elemSize, only
             known at runtime. elemSize must be a power of two so the
             element->byte scale is a shift (covers CHAR/BYTE/INTEGER/ptr/
             REAL and arrays of them). *)
          elemSz := x.type.base.size; t := elemSz;
          WHILE (t > 1) & (t MOD 2 = 0) DO t := t DIV 2; k := k + 1 END;
          IF t # 1 THEN
            ORS.Mark("open array of non-power-of-2 element not implemented");
            valid := FALSE
          ELSE openSrc := TRUE
          END
        END
      ELSIF x.type.form = ORB.Record THEN s := x.type.size
      ELSE ORS.Mark("inadmissible assignment"); valid := FALSE
      END;
      IF valid & ~openSrc THEN
        wordCount := (s + 1) DIV 2; Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDY * 32 + OCG.mImm, 0);
        OCG.gen1(OCG.LDX * 32 + OCG.mImm, wordCount);
        loopTop := OCG.Here();
        OCG.gen1(OCG.LDA * 32 + OCG.mDPIndY, srcReg);
        OCG.gen1(OCG.STA * 32 + OCG.mDPIndY, dstReg);
        OCG.Iny;
        OCG.Iny;
        OCG.Dex;
        OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop)
      ELSIF openSrc THEN
        (* wordCount := (LEN(y) * elemSize + 1) DIV 2, computed in A->X.
           X (the word counter) and Y (the byte index) are 16-bit. LEN(y) is
           at the param's length slot, y.a + 4 + frame (same as Len). *)
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mSR, y.a + 4 + frame);   (* A := element count *)
        i := 0;
        WHILE i < k DO OCG.gen1(OCG.ASL * 32 + OCG.mImpl, 0); i := i + 1 END; (* *elemSize *)
        OCG.gen1(OCG.INC * 32 + OCG.mImpl, 0);               (* +1 ... *)
        OCG.gen1(OCG.LSR * 32 + OCG.mImpl, 0);               (* ... DIV 2 = wordCount *)
        OCG.Tax;               (* X := wordCount (sets Z) *)
        OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 14);  (* empty -> skip loop *)
        OCG.gen1(OCG.LDY * 32 + OCG.mImm, 0);
        loopTop := OCG.Here();
        OCG.gen1(OCG.LDA * 32 + OCG.mDPIndY, srcReg);
        OCG.gen1(OCG.STA * 32 + OCG.mDPIndY, dstReg);
        OCG.Iny;
        OCG.Iny;
        OCG.Dex;
        OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop)
      END
    END;
    RH := 0
  END StoreStruct;

  PROCEDURE CopyString*(VAR x, y: Item);
    VAR len, loopStart: LONGINT;
  BEGIN
    loadAdr(x); len := x.type.len;
    IF len >= 0 THEN
      IF len < y.b THEN ORS.Mark("string too long") END
    ELSIF check THEN Trap(LT, 3)
    END;
    loadStringAdr(y);
    Set8(TRUE, FALSE); Set16(FALSE, TRUE);
    OCG.gen1(OCG.LDY * 32 + OCG.mImm, 0);
    loopStart := OCG.Here();
    OCG.gen1(OCG.LDA * 32 + OCG.mDPIndY, RegAddr(y.r));
    OCG.gen1(OCG.STA * 32 + OCG.mDPIndY, RegAddr(x.r));
    OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
    OCG.Iny;
    OCG.gen1(OCG.BRA * 32 + OCG.mPCR, loopStart);
    RH := RH - 3
  END CopyString;

  (* --- parameters --- *)
  PROCEDURE OpenArrayParam*(VAR x: Item);
  BEGIN
    loadAdr(x);
    IF x.type.len >= 0 THEN
      Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, x.type.len);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r + 2))
    ELSE
      Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 2 + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r + 2))
    END;
    incR
  END OpenArrayParam;

  PROCEDURE VarParam*(VAR x: Item; ftype: ORB.Type);
    VAR xmd, sb: LONGINT;
  BEGIN
    xmd := x.mode;
    IF (x.mode = ORB.Var) & (x.r > 0) THEN
      Set16(TRUE, TRUE);
      OCG.Tsc;
      OCG.Clc;
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, x.a + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
      x.r := RH; x.mode := Reg; incR;
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
      incR
    ELSIF (x.mode = ORB.Var) & (x.r <= 0) THEN
      sb := GetSB(x.r);
      Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, sb);
      IF x.a # 0 THEN
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mImm, x.a)
      END;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1));
      x.r := RH; x.mode := Reg; incR; incR
    ELSE loadAdr(x)
    END;
    IF (ftype.form = ORB.Array) & (ftype.len < 0) THEN
      IF x.type.len >= 0 THEN
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, x.type.len);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r + 2))
      ELSE
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 4 + frame);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r + 2))
      END;
      incR
    ELSIF ftype.form = ORB.Record THEN
      Set16(TRUE, TRUE);
      IF xmd = ORB.Par THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 4 + frame);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r + 2));
        OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 6 + frame);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r + 3))
      ELSE
        sb := GetSB(-x.type.mno);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, sb);
        OCG.Clc;
        emitTDLen(x.type);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r + 2));
        OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(x.r + 3))
      END;
      incR; incR
    END
  END VarParam;

  PROCEDURE ValueParam*(VAR x: Item; ftype: ORB.Type);
  BEGIN load(x)
  END ValueParam;

  PROCEDURE StringParam*(VAR x: Item);
  BEGIN
    Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, SB_DP);
    OCG.Clc;
    OCG.gen1(OCG.ADC * 32 + OCG.mImm, varsize + x.a);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(RH + 1));
    x.mode := Reg; x.r := RH; incR; incR;
    Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, x.b);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
    incR
  END StringParam;

  (* --- FOR --- *)
  PROCEDURE For0*(VAR x, y: Item);
  BEGIN load(y)
  END For0;

  PROCEDURE For1*(VAR x, y, z, w: Item; VAR L: LONGINT);
    VAR useSigned: BOOLEAN;
  BEGIN
    useSigned := (y.type.form = ORB.Int) & (y.type.size = 2);
    IF z.mode = ORB.Const THEN
      load(y);
      IF z.type.size = 1 THEN Set8(TRUE, FALSE) ELSE Set16(TRUE, TRUE) END;
      IF useSigned THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
        OCG.Sec;
        OCG.gen1(OCG.SBC * 32 + OCG.mImm, z.a)
      ELSE OCG.gen1(OCG.CMP * 32 + OCG.mImm, z.a)
      END
    ELSE
      load(y); load(z);
      IF (y.type.size = 1) & (z.type.size = 1) THEN Set8(TRUE, FALSE)
      ELSE Set16(TRUE, TRUE) END;
      IF useSigned THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
        OCG.Sec;
        OCG.gen1(OCG.SBC * 32 + OCG.mDP, RegAddr(z.r))
      ELSE
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
        OCG.gen1(OCG.CMP * 32 + OCG.mDP, RegAddr(z.r))
      END;
      RH := RH - 1
    END;
    Set16(TRUE, FALSE);
    IF w.a > 0 THEN emitBranch(GT, y.type, OCG.mFix, 0)
    ELSIF w.a < 0 THEN emitBranch(LT, y.type, OCG.mFix, 0)
    ELSE ORS.Mark("zero increment"); emitBranch(MI, y.type, OCG.mFix, 0)
    END;
    L := OCG.Here() - 2;
    Store(x, y)
  END For1;

  PROCEDURE For2*(VAR x, y, w: Item);
  BEGIN
    load(x);
    IF w.mode = ORB.Const THEN
      IF w.a > 0 THEN
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mImm, w.a)
      ELSE
        OCG.Sec;
        OCG.gen1(OCG.SBC * 32 + OCG.mImm, -w.a)
      END
    ELSE
      load(w);
      OCG.Clc;
      OCG.gen1(OCG.ADC * 32 + OCG.mDP, RegAddr(w.r));
      RH := RH - 1
    END;
    IF x.mode = ORB.Var THEN
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
      OCG.gen1(OCG.STA * 32 + OCG.mDPIndY, SB_DP)
    ELSE OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r))
    END;
    RH := RH - 1
  END For2;

  (* --- CASE --- *)
  PROCEDURE CaseLabel*(VAR x: Item; val: LONGINT; VAR chain: LONGINT);
  BEGIN
    load(x); Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
    OCG.gen1(OCG.CMP * 32 + OCG.mImm, val);
    RH := RH - 1;
    OCG.gen1(OCG.BNE * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
    OCG.gen1(OCG.BRL * 32 + OCG.mFix, chain);
    chain := OCG.Here() - 2
  END CaseLabel;

  PROCEDURE CaseRange*(VAR x: Item; lo, hi: LONGINT; VAR chain: LONGINT);
  BEGIN
    load(x); Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
    RH := RH - 1;
    OCG.Sec;
    OCG.gen1(OCG.SBC * 32 + OCG.mImm, lo);
    OCG.gen1(OCG.CMP * 32 + OCG.mImm, hi - lo + 1);
    OCG.gen1(OCG.BCS * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
    OCG.gen1(OCG.BRL * 32 + OCG.mFix, chain);
    chain := OCG.Here() - 2
  END CaseRange;

  (* --- branches --- *)
  PROCEDURE Here*(): LONGINT;
  BEGIN RETURN OCG.Here()
  END Here;

  PROCEDURE FJump*(VAR L: LONGINT);
  BEGIN
    emitBranch(AL, ORB.intType, OCG.mFix, L);
    L := OCG.Here() - 2
  END FJump;

  PROCEDURE CFJump*(VAR x: Item);
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END;
    emitBranch(negated(x.r), x.origType, OCG.mFix, x.a);
    FixLink(x.b);
    x.a := OCG.Here() - 2
  END CFJump;

  PROCEDURE BJump*(L: LONGINT);
  BEGIN OCG.gen1(OCG.BRA * 32 + OCG.mPCR, L)
  END BJump;

  PROCEDURE CBJump*(VAR x: Item; L: LONGINT);
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END;
    emitBranch(negated(x.r), x.origType, OCG.mPCR, L);
    FixLink(x.b);
    FixLinkWith(x.a, L)
  END CBJump;

  PROCEDURE Fixup*(VAR x: Item);
  BEGIN FixLink(x.a)
  END Fixup;

  (* --- calls & procedure frame --- *)
  PROCEDURE SaveRegs(r: LONGINT);
    VAR ri: LONGINT;
  BEGIN
    ri := 0; Set16(TRUE, TRUE); frame := frame + 2 * r;
    REPEAT
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(ri));
      OCG.Pha;
      ri := ri + 1
    UNTIL ri >= r
  END SaveRegs;

  PROCEDURE RestoreRegs(r: LONGINT);
    VAR ri: LONGINT;
  BEGIN
    ri := r; Set16(TRUE, TRUE);
    REPEAT
      ri := ri - 1;
      OCG.Pla;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(ri))
    UNTIL ri <= 0;
    frame := frame - 2 * r
  END RestoreRegs;

  PROCEDURE PrepCall*(VAR x: Item; VAR r: LONGINT);
    VAR rcv: Item;
  BEGIN
    IF x.ifaceDisp THEN
      (* interface dispatch: save outer context, then load the fat value's data
         word (the object pointer) from the interface designator as param 0.
         Call re-reads the itable from the same designator. *)
      r := RH;
      IF RH > 0 THEN SaveRegs(RH); RH := 0 END;
      loadIfacePair(x.rcvMode, x.rcvA, x.rcvB, x.rcvR, 0, 0);
      RH := 2
    ELSIF x.isMeth & ((x.rcvMode = Reg) OR (x.rcvMode = RegI)) THEN
      (* receiver already in registers [rcvR, rcvR+1] — a DeRef'd pointer
         (dynamic dispatch / SUPER) or a freshly-allocated instance (a
         constructor). Save the outer context below it, keep the receiver,
         and move it to R0/R1 as param 0; scratch/args then sit above it. *)
      r := x.rcvR;
      IF x.rcvR > 0 THEN SaveRegs(x.rcvR) END;
      IF x.rcvR # 0 THEN
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.rcvR));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(0));
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.rcvR + 1));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(1))
      END;
      RH := 2
    ELSE
      IF x.mode > ORB.Par THEN load(x) END;
      r := RH;
      IF RH > 0 THEN SaveRegs(RH); RH := 0 END;
      IF x.isMeth THEN
        (* VAR-record receiver (static): reload it from memory as param 0 —
           addr+bank+tag — via VarParam. ParamList skips param 0. *)
        rcv.mode := x.rcvMode; rcv.a := x.rcvA; rcv.b := x.rcvB; rcv.r := x.rcvR;
        rcv.rdo := x.rcvRdo; rcv.type := x.rcvType; rcv.isMeth := FALSE;
        VarParam(rcv, rcv.type)
      END
    END
  END PrepCall;

  PROCEDURE Call*(VAR x: Item; r: LONGINT);
    VAR mno, exno, encoded, addrReg, bankReg: LONGINT; wide: BOOLEAN;
  BEGIN
    Set16(TRUE, TRUE);
    IF x.ifaceDisp THEN
      (* interface dispatch: receiver (data) already in R0/R1. Re-read the
         itable from the interface designator, index it by the interface method
         index (methSlot) to get the record's vtable slot, then dispatch through
         the object's vtable exactly like dynamic dispatch (runtime slot). *)
      addrReg := RegAddr(RH);
      loadIfacePair(x.rcvMode, x.rcvA, x.rcvB, x.rcvR, 4, RH + 6);  (* itable ptr *)
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH + 6));
      OCG.Clc;
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, x.methSlot * 2);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 8));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH + 7));
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 9));
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, RegAddr(RH + 8));   (* slot index *)
      OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);                    (* *2 *)
      OCG.Clc;
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, VtableOff);            (* vtable byte offset *)
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 8));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(0));            (* tag ptr = data - 4 *)
      OCG.Sec;
      OCG.gen1(OCG.SBC * 32 + OCG.mImm, 4);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 2));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(1));
      OCG.gen1(OCG.SBC * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 3));
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, RegAddr(RH + 2));   (* TD addr lo *)
      OCG.Clc;
      OCG.gen1(OCG.ADC * 32 + OCG.mDP, RegAddr(RH + 8));       (* + vtable byte offset *)
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 4));
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, 2);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(RH + 2));  (* TD bank *)
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 5));
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, RegAddr(RH + 4));   (* method address *)
      OCG.gen1(OCG.STA * 32 + OCG.mDP, addrReg);
      OCG.Phk;
      OCG.gen1(OCG.PER * 32 + OCG.mImm, 09H);
      Set8(TRUE, FALSE);
      OCG.Phk;
      Set16(TRUE, FALSE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, addrReg);
      OCG.gen1(OCG.DEC * 32 + OCG.mAcc, 0);
      OCG.Pha;
      OCG.Rtl
    ELSIF x.dynDisp THEN
      (* dynamic dispatch: receiver (object pointer) is param 0 in R0/R1.
         tag := [obj-4]; addr := [tag + VtableOff + slot*2] — the loader has
         already filled that slot with the method's absolute in-bank address,
         so no code base is added. All modules share one bank, so the call
         bank is the current program bank (PHK). Scratch above RH. *)
      addrReg := RegAddr(RH);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(0));
      OCG.Sec;
      OCG.gen1(OCG.SBC * 32 + OCG.mImm, 4);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 2));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(1));
      OCG.gen1(OCG.SBC * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 3));
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, RegAddr(RH + 2));   (* TD addr lo *)
      OCG.Clc;
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, VtableOff + x.methSlot * 2);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 4));
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, 2);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(RH + 2));  (* TD bank *)
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, 0);                    (* carry from lo add *)
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 5));
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, RegAddr(RH + 4));   (* method address *)
      OCG.gen1(OCG.STA * 32 + OCG.mDP, addrReg);
      OCG.Phk;
      OCG.gen1(OCG.PER * 32 + OCG.mImm, 09H);
      Set8(TRUE, FALSE);
      OCG.Phk;
      Set16(TRUE, FALSE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, addrReg);
      OCG.gen1(OCG.DEC * 32 + OCG.mAcc, 0);
      OCG.Pha;
      OCG.Rtl
    ELSIF x.mode = ORB.Const THEN
      IF x.r < 0 THEN
        mno := -x.r; exno := x.a;
        encoded := mno * 10000H + (exno MOD 10000H);
        OCG.gen1(OCG.JSL * 32 + OCG.mAbsL, encoded)
      ELSIF x.b = 1 THEN
        OCG.gen1(OCG.JSL * 32 + OCG.mAbsL, x.a)
      ELSE
        OCG.gen1(OCG.JSR * 32 + OCG.mAbs, x.a)
      END
    ELSE
      IF x.mode <= ORB.Par THEN
        load(x);
        addrReg := RegAddr(RH - 2); bankReg := RegAddr(RH - 1);
        IF check THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, addrReg);
          OCG.gen1(OCG.ORA * 32 + OCG.mDP, bankReg);
          Trap(NE, 5)
        END;
        OCG.Phk;
        OCG.gen1(OCG.PER * 32 + OCG.mImm, 0BH);
        Set8(TRUE, FALSE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, bankReg);
        OCG.Pha;
        Set16(TRUE, FALSE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, addrReg);
        OCG.gen1(OCG.DEC * 32 + OCG.mAcc, 0);
        OCG.Pha;
        OCG.Rtl;
        RH := RH - 2
      ELSE
        OCG.Pla;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(1));
        OCG.Pla;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(0));
        addrReg := RegAddr(0); bankReg := RegAddr(1);
        r := r - 2; frame := frame - 4;
        IF check THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, addrReg);
          OCG.gen1(OCG.ORA * 32 + OCG.mDP, bankReg);
          Trap(NE, 5)
        END;
        OCG.Phk;
        OCG.gen1(OCG.PER * 32 + OCG.mImm, 0BH);
        Set8(TRUE, FALSE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, bankReg);
        OCG.Pha;
        Set16(TRUE, FALSE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, addrReg);
        OCG.gen1(OCG.DEC * 32 + OCG.mAcc, 0);
        OCG.Pha;
        OCG.Rtl
      END
    END;
    IF x.type.base.form = ORB.NoTyp THEN
      IF r > 0 THEN RestoreRegs(r) END;
      RH := r
    ELSE
      wide := (x.type.base.form = ORB.Pointer) OR (x.type.base.form = ORB.Real)
              OR (x.type.base.form = ORB.Proc);
      IF r > 0 THEN
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(0));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(r));
        IF wide THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(1));
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(r + 1))
        END;
        RestoreRegs(r)
      END;
      x.mode := Reg; x.r := r;
      IF wide THEN RH := r + 2 ELSE RH := r + 1 END
    END
  END Call;

  (* --- procedure entry / exit --- *)
  (* Shared-frontend signature: (proc, params, parblksize, locblksize,
     intProc). frame_size = parblksize + locblksize; expo = proc.expo. *)
  PROCEDURE Enter*(proc, params: ORB.Object; parblksize, locblksize: LONGINT; intProc: BOOLEAN);
    VAR r, frameSize: LONGINT; param: ORB.Object;
      paramItem, regItem: Item;
  BEGIN
    frameSize := parblksize + locblksize;
    (* Methods always use the far (RTL) convention: dynamic dispatch reaches
       them via a long call and the vtable demands ONE uniform convention
       across every override, so a method can never be a near (RTS) proc.
       The far path also saves/resets SB, which is what makes an imported
       method run with its own module's static base. *)
    curFrameSize := frameSize; curExpo := proc.expo OR (proc.class = ORB.Meth);
    curIntProc := intProc;
    forDepth := 0;
    (* a method keeps its vtable slot in .val, so record its compiled entry
       address in .backend for BuildTD/Close to wire into the vtable *)
    IF proc.class = ORB.Meth THEN proc.backend := OCG.Here() END;
    IF ~intProc THEN
      IF frameSize >= 4000H THEN ORS.Mark("too many locals") END;
      Set16(TRUE, TRUE);
      IF curExpo THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, SB_DP);
        OCG.Pha;
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, BANK_DP);
        OCG.Pha;
        OCG.AddRel(OCG.Here());
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, SB_DP);
        OCG.AddRel(OCG.Here() + 80000000H);
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, BANK_DP)
      END;
      IF frameSize > 0 THEN
        OCG.Tsc;
        OCG.Sec;
        OCG.gen1(OCG.SBC * 32 + OCG.mImm, frameSize);
        OCG.Tcs
      END;
      r := 0; param := params; Set16(TRUE, TRUE);
      WHILE (param # NIL) & ((param.class = ORB.Var) OR (param.class = ORB.Par)) DO
        IF (param.class = ORB.Par) & (param.type.form = ORB.Array) & (param.type.len < 0) THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r + 1));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 2);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r + 2));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 4)
        ELSIF (param.class = ORB.Par) & (param.type.form = ORB.Record) THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r + 1));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 2);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r + 2));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 4);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r + 3));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 6)
        ELSIF param.class = ORB.Par THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r + 1));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 2)
        ELSIF (param.type.form = ORB.Real) OR (param.type.form = ORB.Proc) THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r + 1));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 2)
        ELSIF param.type.form = ORB.Intfc THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r + 1));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 2);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r + 2));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 4);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r + 3));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 6)
        ELSE
          MakeItem(paramItem, param, param.lev);
          regItem.mode := Reg; regItem.type := param.type;
          regItem.r := r; regItem.rdo := TRUE;
          Store(paramItem, regItem)
        END;
        IF (param.class = ORB.Par) & (param.type.form = ORB.Array) & (param.type.len < 0) THEN
          r := r + 3
        ELSIF (param.class = ORB.Par) & (param.type.form = ORB.Record) THEN
          r := r + 4
        ELSIF param.class = ORB.Par THEN r := r + 2
        ELSIF param.type.form = ORB.Intfc THEN r := r + 4
        ELSIF param.type.size <= 2 THEN r := r + 1
        ELSE r := r + 2
        END;
        param := param.next
      END;
      RH := 0
    ELSE
      IF frameSize > 0 THEN
        OCG.Sec;
        OCG.gen1(OCG.SBC * 32 + OCG.mImm, frameSize);
        OCG.Tcs
      END
    END
  END Enter;

  (* Shared-frontend signature: (proc, x). form/size/expo/int from proc
     and the Enter stash. *)
  PROCEDURE Return*(proc: ORB.Object; VAR x: Item);
    VAR form, size: LONGINT;
  BEGIN
    form := proc.type.base.form; size := curFrameSize;
    IF form # ORB.NoTyp THEN load(x) END;
    IF ~curIntProc THEN
      Set16(TRUE, TRUE);
      IF size > 0 THEN
        OCG.Tsc;
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mImm, size);
        OCG.Tcs
      END;
      IF curExpo THEN
        OCG.Pla;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, BANK_DP);
        OCG.Pla;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, SB_DP);
        OCG.Rtl
      ELSE OCG.Rts
      END
    ELSE
      IF size > 0 THEN
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mImm, size);
        OCG.Tcs
      END;
      OCG.Rti
    END;
    RH := 0
  END Return;

  (* --- inline standard procedures --- *)
  PROCEDURE Increment*(upordown: LONGINT; VAR x, y: Item);
    VAR zr: LONGINT; isByte, isInc, useIncDec: BOOLEAN;
  BEGIN
    isByte := x.type = ORB.byteType; isInc := upordown = 0;
    IF y.type.form = ORB.NoTyp THEN y.mode := ORB.Const; y.a := 1 END;
    useIncDec := (y.mode = ORB.Const) & (y.a = 1);
    IF (x.mode = ORB.Var) & (x.r > 0) THEN
      zr := RH;
      IF isByte THEN Set8(TRUE, FALSE) ELSE Set16(TRUE, TRUE) END;
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(zr));
      incR;
      IF y.mode = ORB.Const THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(zr));
        IF useIncDec THEN
          IF isInc THEN OCG.gen1(OCG.INC * 32 + OCG.mAcc, 0) ELSE OCG.gen1(OCG.DEC * 32 + OCG.mAcc, 0) END
        ELSIF isInc THEN
          OCG.Clc; OCG.gen1(OCG.ADC * 32 + OCG.mImm, y.a)
        ELSE
          OCG.Sec; OCG.gen1(OCG.SBC * 32 + OCG.mImm, y.a)
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(zr))
      ELSE
        load(y);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(zr));
        IF isInc THEN
          OCG.Clc; OCG.gen1(OCG.ADC * 32 + OCG.mDP, RegAddr(y.r))
        ELSE
          OCG.Sec; OCG.gen1(OCG.SBC * 32 + OCG.mDP, RegAddr(y.r))
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(zr)); RH := RH - 1
      END;
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(zr));
      OCG.gen1(OCG.STA * 32 + OCG.mSR, x.a + frame);
      IF isByte THEN Set16(TRUE, TRUE) END;
      RH := RH - 1
    ELSE
      loadAdr(x); zr := RH;
      IF isByte THEN Set8(TRUE, FALSE) ELSE Set16(TRUE, TRUE) END;
      OCG.gen1(OCG.LDX * 32 + OCG.mDP, RegAddr(x.r));
      OCG.gen1(OCG.LDA * 32 + OCG.mAbsX, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(zr));
      incR;
      IF y.mode = ORB.Const THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(zr));
        IF useIncDec THEN
          IF isInc THEN OCG.gen1(OCG.INC * 32 + OCG.mAcc, 0) ELSE OCG.gen1(OCG.DEC * 32 + OCG.mAcc, 0) END
        ELSIF isInc THEN
          OCG.Clc; OCG.gen1(OCG.ADC * 32 + OCG.mImm, y.a)
        ELSE
          OCG.Sec; OCG.gen1(OCG.SBC * 32 + OCG.mImm, y.a)
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(zr))
      ELSE
        load(y);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(zr));
        IF isInc THEN
          OCG.Clc; OCG.gen1(OCG.ADC * 32 + OCG.mDP, RegAddr(y.r))
        ELSE
          OCG.Sec; OCG.gen1(OCG.SBC * 32 + OCG.mDP, RegAddr(y.r))
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(zr)); RH := RH - 1
      END;
      OCG.gen1(OCG.LDX * 32 + OCG.mDP, RegAddr(x.r));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(zr));
      OCG.gen1(OCG.STA * 32 + OCG.mAbsX, 0);
      IF isByte THEN Set16(TRUE, TRUE) END;
      RH := RH - 3
    END
  END Increment;

  PROCEDURE Include*(inorex: LONGINT; VAR x, y: Item);
    VAR orig: Item; zr, mask, skip, loopTop: LONGINT;
  BEGIN
    orig := x;
    IF (x.mode = ORB.Var) & (x.r > 0) THEN
      Set16(TRUE, TRUE); zr := RH;
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(zr));
      incR;
      IF y.mode = ORB.Const THEN
        mask := Lo16(ASL(1, y.a));
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(zr));
        IF inorex = 0 THEN OCG.gen1(OCG.ORA * 32 + OCG.mImm, mask)
        ELSE OCG.gen1(OCG.AND * 32 + OCG.mImm, Lo16(EOR(mask, 0FFFFH)))
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(zr))
      ELSE
        load(y);
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, 1);
        OCG.gen1(OCG.LDX * 32 + OCG.mDP, RegAddr(y.r));
        skip := OCG.Here() + 2 + 4;
        OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, skip);
        loopTop := OCG.Here();
        OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);
        OCG.Dex;
        OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
        IF inorex = 0 THEN OCG.gen1(OCG.ORA * 32 + OCG.mDP, RegAddr(zr))
        ELSE
          OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
          OCG.gen1(OCG.AND * 32 + OCG.mDP, RegAddr(zr))
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(zr)); RH := RH - 1
      END;
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(zr));
      OCG.gen1(OCG.STA * 32 + OCG.mSR, orig.a + frame);
      RH := RH - 1
    ELSE
      loadAdr(x); zr := RH; Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDX * 32 + OCG.mDP, RegAddr(x.r));
      OCG.gen1(OCG.LDA * 32 + OCG.mAbsX, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(zr));
      incR;
      IF y.mode = ORB.Const THEN
        mask := Lo16(ASL(1, y.a));
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(zr));
        IF inorex = 0 THEN OCG.gen1(OCG.ORA * 32 + OCG.mImm, mask)
        ELSE OCG.gen1(OCG.AND * 32 + OCG.mImm, Lo16(EOR(mask, 0FFFFH)))
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(zr))
      ELSE
        load(y);
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, 1);
        OCG.gen1(OCG.LDX * 32 + OCG.mDP, RegAddr(y.r));
        skip := OCG.Here() + 2 + 4;
        OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, skip);
        loopTop := OCG.Here();
        OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);
        OCG.Dex;
        OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
        IF inorex = 0 THEN OCG.gen1(OCG.ORA * 32 + OCG.mDP, RegAddr(zr))
        ELSE
          OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
          OCG.gen1(OCG.AND * 32 + OCG.mDP, RegAddr(zr))
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(zr)); RH := RH - 1
      END;
      OCG.gen1(OCG.LDX * 32 + OCG.mDP, RegAddr(x.r));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(zr));
      OCG.gen1(OCG.STA * 32 + OCG.mAbsX, 0);
      RH := RH - 3
    END
  END Include;

  PROCEDURE Assert*(VAR x: Item);
    VAR cond: LONGINT;
  BEGIN
    IF x.mode # Cond THEN loadCond(x) END;
    IF x.a = 0 THEN cond := negated(x.r)
    ELSE FixLink(x.a); x.b := OCG.Here() - 1; cond := 7
    END;
    Trap(cond, 7);
    FixLink(x.b)
  END Assert;

  PROCEDURE New*(VAR x: Item);
    VAR baseType: ORB.Type; y, z: Item; sb: LONGINT;
  BEGIN
    baseType := x.type.base; y := x;
    Set16(TRUE, TRUE);
    sb := GetSB(-baseType.mno);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, sb);
    OCG.Clc;
    emitTDLen(baseType);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(RH + 1));
    incR; incR;
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, baseType.size + 4);
    OCG.gen1(OCG.BRK * 32 + OCG.mImm, 10);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
    OCG.gen1(OCG.STX * 32 + OCG.mDP, RegAddr(RH + 1));
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH - 2));
    OCG.gen1(OCG.STA * 32 + OCG.mDPIndL, RegAddr(RH));
    OCG.gen1(OCG.LDY * 32 + OCG.mImm, 2);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH - 1));
    OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, RegAddr(RH));
    OCG.Clc;
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH));
    OCG.gen1(OCG.ADC * 32 + OCG.mImm, 4);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
    z.r := RH; z.mode := Reg; z.type := y.type;
    incR; incR;
    Store(y, z);
    RH := RH - 2
  END New;

  PROCEDURE Pack*(VAR x, y: Item);
    VAR z: Item;
  BEGIN z := x; load(x); load(y); RH := RH - 1; Store(z, x)
  END Pack;

  PROCEDURE Unpk*(VAR x, y: Item);
    VAR z, e0: Item;
  BEGIN
    z := x; load(x);
    e0.mode := Reg; e0.r := RH; e0.type := ORB.intType;
    Store(y, e0);
    incR;
    Store(z, x)
  END Unpk;

  PROCEDURE IntEn*(VAR x: Item);
  BEGIN
  END IntEn;

  PROCEDURE GetB*(VAR bank, addr, var: Item);
  BEGIN
    load(addr); load(bank);
    addr.type := var.type; addr.mode := RegI; addr.a := 0;
    Store(var, addr)
  END GetB;

  PROCEDURE PutB*(VAR bank, addr, val: Item);
  BEGIN
    load(addr); load(bank);
    addr.type := val.type; addr.mode := RegI; addr.a := 0;
    Store(addr, val)
  END PutB;

  PROCEDURE Get*(VAR addr, var: Item);
  BEGIN ORS.Mark("2-arg GET not supported on 65C816")
  END Get;

  PROCEDURE Put*(VAR addr, val: Item);
  BEGIN ORS.Mark("2-arg PUT not supported on 65C816")
  END Put;

  PROCEDURE Copy*(VAR x, y, z: Item);
    VAR loopTop: LONGINT;
  BEGIN
    load(x); load(y);
    IF z.mode = ORB.Const THEN
      IF z.a > 0 THEN load(z) ELSE ORS.Mark("bad count") END
    ELSE
      load(z);
      IF check THEN Trap(LT, 3) END
    END;
    Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDY * 32 + OCG.mImm, 0);
    loopTop := OCG.Here();
    OCG.gen1(OCG.LDA * 32 + OCG.mDPIndY, RegAddr(x.r));
    OCG.gen1(OCG.STA * 32 + OCG.mDPIndY, RegAddr(y.r));
    OCG.Iny;
    OCG.Iny;
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(z.r));
    OCG.gen1(OCG.DEC * 32 + OCG.mAcc, 0);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(z.r));
    OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
    RH := RH - 3
  END Copy;

  PROCEDURE TRB*(VAR x, y: Item);
  BEGIN
    IF x.mode = ORB.Const THEN
      load(y); Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
      OCG.gen1(OCG.TRB * 32 + OCG.mAbs, x.a);
      RH := RH - 1
    ELSE
      load(x); load(y); Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
      OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
      OCG.gen1(OCG.AND * 32 + OCG.mDPInd, RegAddr(x.r));
      OCG.gen1(OCG.STA * 32 + OCG.mDPInd, RegAddr(x.r));
      RH := RH - 2
    END
  END TRB;

  PROCEDURE TSB*(VAR x, y: Item);
  BEGIN
    IF x.mode = ORB.Const THEN
      load(y); Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
      OCG.gen1(OCG.TSB * 32 + OCG.mAbs, x.a);
      RH := RH - 1
    ELSE
      load(x); load(y); Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
      OCG.gen1(OCG.ORA * 32 + OCG.mDPInd, RegAddr(x.r));
      OCG.gen1(OCG.STA * 32 + OCG.mDPInd, RegAddr(x.r));
      RH := RH - 2
    END
  END TSB;

  PROCEDURE Exec*(VAR addr, bank: Item);
    VAR addrReg, bankReg: LONGINT;
  BEGIN
    load(addr); load(bank);
    addrReg := RegAddr(addr.r); bankReg := RegAddr(bank.r);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, SB_DP);
    OCG.Pha;
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, BANK_DP);
    OCG.Pha;
    OCG.Phk;
    OCG.gen1(OCG.PER * 32 + OCG.mImm, 0BH);
    Set8(TRUE, FALSE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, bankReg);
    OCG.Pha;
    Set16(TRUE, FALSE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, addrReg);
    OCG.gen1(OCG.DEC * 32 + OCG.mAcc, 0);
    OCG.Pha;
    OCG.Rtl;
    OCG.Pla;
    OCG.gen1(OCG.STA * 32 + OCG.mDP, BANK_DP);
    OCG.Pla;
    OCG.gen1(OCG.STA * 32 + OCG.mDP, SB_DP);
    RH := RH - 2
  END Exec;

  (* --- inline functions --- *)
  PROCEDURE Abs*(VAR x: Item);
  BEGIN
    IF x.mode = ORB.Const THEN
      IF x.a < 0 THEN x.a := -x.a END
    ELSE
      load(x);
      IF x.type.form = ORB.Real THEN
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r + 1));
        OCG.gen1(OCG.AND * 32 + OCG.mImm, 7FFFH);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r + 1))
      ELSE
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
        OCG.gen1(OCG.BPL * 32 + OCG.mPCR, OCG.Here() + 2 + 6);
        OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
        OCG.gen1(OCG.INC * 32 + OCG.mAcc, 0);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r))
      END
    END
  END Abs;

  PROCEDURE Odd*(VAR x: Item);
  BEGIN
    load(x); Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 1);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r));
    SetCC(x, NE); RH := RH - 1
  END Odd;

  PROCEDURE Floor*(VAR x: Item);
  BEGIN
    load(x); Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_A_LO);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r + 1));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_A_HI);
    ORGFP.AddFixup(ORGFP.FP_FLOOR); OCG.gen1(OCG.JSR * 32 + OCG.mAbs, 0);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGFP.FP_A_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r));
    RH := RH - 1; x.type := ORB.intType
  END Floor;

  PROCEDURE Float*(VAR x: Item);
  BEGIN
    load(x); Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_A_LO);
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, ORGFP.FP_A_HI);
    ORGFP.AddFixup(ORGFP.FP_FLT); OCG.gen1(OCG.JSR * 32 + OCG.mAbs, 0);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGFP.FP_A_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r));
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGFP.FP_A_HI);
    incR;
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r + 1));
    x.type := ORB.realType
  END Float;

  PROCEDURE Ord*(VAR x: Item);
  BEGIN
    IF (x.mode = ORB.Var) OR (x.mode = ORB.Par) OR (x.mode = RegI) OR (x.mode = Cond) THEN
      load(x)
    END
  END Ord;

  (* CHR(x): INTEGER -> CHAR. Same materialisation as Ord (identical bytes),
     but the result is typed CHAR — the low byte is the character; a store to
     a 1-byte CHAR destination already narrows it. *)
  PROCEDURE Chr*(VAR x: Item);
  BEGIN
    IF (x.mode = ORB.Var) OR (x.mode = ORB.Par) OR (x.mode = RegI) OR (x.mode = Cond) THEN
      load(x)
    END;
    x.type := ORB.charType
  END Chr;

  PROCEDURE Len*(VAR x: Item);
  BEGIN
    IF x.type.len >= 0 THEN
      IF x.mode = RegI THEN RH := RH - 1 END;
      x.mode := ORB.Const; x.a := x.type.len
    ELSE
      Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 4 + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
      x.mode := Reg; x.r := RH; incR
    END
  END Len;

  PROCEDURE Shift*(fct: LONGINT; VAR x, y: Item);
    VAR op, i, L: LONGINT;
  BEGIN
    load(x);
    IF fct = 0 THEN op := OCG.ASL
    ELSIF fct = 1 THEN op := OCG.LSR
    ELSE op := OCG.ROL
    END;
    IF y.mode = ORB.Const THEN
      IF y.a = 1 THEN OCG.gen1(op * 32 + OCG.mDP, RegAddr(x.r))
      ELSE
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
        i := 0;
        WHILE i < y.a DO OCG.gen1(op * 32 + OCG.mImpl, 0); i := i + 1 END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r))
      END
    ELSE
      (* Runtime shift count: the 65C816 has no barrel shifter, so shift the
         value (in its DP register) one place at a time, counting the count
         register down. Value and count both stay in DP; nothing else is
         clobbered. Loop body is 6 bytes (op:2 + DEC:2 + BNE:2), so the
         count=0 guard branches past it to Here()+2(BEQ)+6. *)
      load(y);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));      (* A := count (sets Z) *)
      OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 8);   (* count = 0 -> skip *)
      L := OCG.Here();
      OCG.gen1(op * 32 + OCG.mDP, RegAddr(x.r));           (* value shifted once *)
      OCG.gen1(OCG.DEC * 32 + OCG.mDP, RegAddr(y.r));      (* count-- (sets Z) *)
      OCG.gen1(OCG.BNE * 32 + OCG.mPCR, L);                (* repeat while # 0 *)
      RH := RH - 1                                     (* free the count reg *)
    END
  END Shift;

  PROCEDURE Bitwise*(fct: LONGINT; VAR x, y: Item);
    VAR op: LONGINT;
  BEGIN
    load(x);
    IF fct = 0 THEN op := OCG.AND
    ELSIF fct = 1 THEN op := OCG.EOR
    ELSE op := OCG.ORA
    END;
    IF y.mode = ORB.Const THEN
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, Lo16(y.a));
      OCG.gen1(op * 32 + OCG.mDP, RegAddr(x.r));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r))
    ELSE
      load(y);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
      OCG.gen1(op * 32 + OCG.mDP, RegAddr(x.r));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH - 2));
      RH := RH - 1; x.r := RH - 1
    END
  END Bitwise;

  PROCEDURE UML*(VAR x, y: Item);
  BEGIN load(x); load(y); RH := RH - 1
  END UML;

  PROCEDURE Bit*(VAR x, y: Item);
    VAR loopTop: LONGINT;
  BEGIN
    load(x);
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(RH));
    incR;
    x.mode := RegI; x.a := 0; x.type := ORB.intType;
    load(x);
    Set16(TRUE, TRUE);
    IF y.mode = ORB.Const THEN
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
      OCG.gen1(OCG.AND * 32 + OCG.mImm, ASL(1, y.a));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r));
      RH := RH - 1
    ELSE
      load(y);
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, 1);
      OCG.gen1(OCG.LDX * 32 + OCG.mDP, RegAddr(y.r));
      OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 2 + 4);
      loopTop := OCG.Here();
      OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);
      OCG.Dex;
      OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
      OCG.gen1(OCG.AND * 32 + OCG.mDP, RegAddr(x.r));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r));
      RH := RH - 2
    END;
    SetCC(x, NE)
  END Bit;

  PROCEDURE HH*(VAR x: Item);
  BEGIN x.mode := Reg; x.r := RH; incR
  END HH;

  PROCEDURE Adr*(VAR x: Item);
  BEGIN
    IF (x.mode = ORB.Var) OR (x.mode = ORB.Par) OR (x.mode = RegI) THEN
      loadAdr(x); RH := RH - 1
    ELSIF (x.mode = ORB.Const) & (x.type.form = ORB.Proc) THEN load(x)
    ELSIF (x.mode = ORB.Const) & (x.type.form = ORB.String) THEN loadStringAdr(x)
    ELSIF (x.mode = ORB.Const) &
          ((x.type.form = ORB.Array) OR (x.type.form = ORB.Record)) THEN loadStringAdr(x)
    ELSE ORS.Mark("not addressable")
    END
  END Adr;

  PROCEDURE Bank*(VAR x: Item);
  BEGIN
    IF (x.mode = ORB.Var) OR (x.mode = ORB.Par) OR (x.mode = RegI) THEN
      loadAdr(x); Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r + 1));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r));
      RH := RH - 1
    ELSIF (x.mode = ORB.Const) &
          ((x.type.form = ORB.Array) OR (x.type.form = ORB.Record) OR (x.type.form = ORB.String)) THEN
      Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, BANK_DP);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
      x.mode := Reg; x.r := RH; incR
    ELSE ORS.Mark("not addressable")
    END
  END Bank;

  PROCEDURE Condition*(VAR x: Item);
  BEGIN SetCC(x, x.a)
  END Condition;

  (* --- module management --- *)
  PROCEDURE Open*(modid: ARRAY OF CHAR; v: INTEGER);
    VAR i: INTEGER;
  BEGIN
    curModid := modid;
    OCG.Init; OCG.SetPc(CodeOrg);
    tdx := 0; strx := 0; RH := 0; forDepth := 0;
    fixorgP := 0; fixorgD := 0; fixorgT := 0;
    tdFixupC := 0; tdListC := 0; tdRefC := 0; vtFixC := 0;
    itabC := 0; itabRefC := 0;
    ORGFP.Init;
    check := v # 0; version := v;
    IF v = 0 THEN
      OCG.SetPc(1);
      WHILE OCG.Here() < 8 DO OCG.Patch(OCG.Here(), 0); OCG.SetPc(OCG.Here() + 1) END
    END;
    OCG.SetLongA(TRUE); OCG.SetLongI(TRUE)
  END Open;

  PROCEDURE SetDataSize*(dc: LONGINT);
  BEGIN varsize := dc
  END SetDataSize;

  PROCEDURE Header*;
  BEGIN
    entry := OCG.Here();
    OCG.SetLongA(TRUE); OCG.SetLongI(TRUE);
    OCG.AddRel(OCG.Here());
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, SB_DP);
    OCG.AddRel(OCG.Here() + 80000000H);
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, BANK_DP)
  END Header;


  (* Emit the .816 module — unless a fixed backend buffer overflowed while
     generating code, in which case the code/reloc tables are truncated and
     the module would be silently wrong. Mark instead so the compile fails
     cleanly (this is the clean-abort for an over-large module; the raw
     overflow used to run past the reloc array and segfault). *)
  PROCEDURE Close*(modid: ARRAY OF CHAR; key: LONGINT; nofent: LONGINT);
    VAR wInfo: ORGW.ModInfo;
  BEGIN
    IF OCG.Faulted() THEN
      ORS.Mark("program too large: code or relocation table overflow")
    ELSE
      OCG.Rtl;   (* exit: emulator calls main with JSL, return with RTL *)
      ORGFP.EmitSubroutines; ORGFP.FixupCalls;
      wInfo.key := key; wInfo.nofent := nofent; wInfo.version := version;
      wInfo.varsize := varsize; wInfo.strx := strx; wInfo.tdx := tdx; wInfo.entry := entry;
      wInfo.fixorgP := fixorgP; wInfo.fixorgD := fixorgD; wInfo.fixorgT := fixorgT;
      wInfo.tdListC := tdListC; wInfo.tdFixupC := tdFixupC; wInfo.vtFixC := vtFixC;
      ORGW.WriteModule(modid, wInfo, wa, tdList)
    END
  END Close;

  (* --- SYSTEM pseudo-module registration (816 set) --- *)
  PROCEDURE InitSystem*;
  BEGIN
    ORB.SysFunc("BANK", ORB.intType, 211);
    ORB.SysFunc("H", ORB.intType, 201);
    ORB.SysFunc("COND", ORB.boolType, 191);
    ORB.SysFunc("SIZE", ORB.intType, 181);
    ORB.SysFunc("ADR", ORB.intType, 171);
    ORB.SysFunc("VAL", ORB.intType, 162);
    ORB.SysFunc("BIT", ORB.boolType, 142);
    ORB.SysProc("EXEC", ORB.noType, 152);
    ORB.SysProc("TSB", ORB.noType, 142);
    ORB.SysProc("TRB", ORB.noType, 132);
    ORB.SysProc("COPY", ORB.noType, 123);
    ORB.SysProc("PUT", ORB.noType, 113);
    ORB.SysProc("GET", ORB.noType, 103);
    ORB.SysProc("INTEN", ORB.noType, 91)
  END InitSystem;

  (* --- statement-result / loop-bound hooks --- *)
  PROCEDURE Discard*(VAR x: Item);
  BEGIN  (* free the result register left by a function-call statement *)
    IF x.mode = Reg THEN RH := x.r END
  END Discard;

  PROCEDURE Snapshot*(VAR x: Item);
  BEGIN
    (* The shared frontend evaluates the FOR limit once, before L0. On this
       register machine the limit would be clobbered by the loop body (and
       by any procedure it calls), so spill a non-const limit onto the
       hardware stack. frame += 2 shifts all stack-relative accesses to
       account for it; ForClose pops it at loop exit. Call-safe because the
       push lives on the invocation's own stack. *)
    IF forDepth < maxForNest THEN
      IF x.mode # ORB.Const THEN
        load(x);
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
        OCG.Pha;
        RH := RH - 1; frame := frame + 2;
        x.mode := ORB.Var; x.r := 1; x.a := 1 - frame;
        forPushed[forDepth] := TRUE
      ELSE forPushed[forDepth] := FALSE
      END;
      forDepth := forDepth + 1
    ELSE ORS.Mark("FOR loops nested too deeply")
    END
  END Snapshot;

  PROCEDURE ForClose*;
  BEGIN
    IF forDepth > 0 THEN
      forDepth := forDepth - 1;
      IF forPushed[forDepth] THEN
        Set16(TRUE, TRUE);
        OCG.Pla;   (* discard the spilled limit *)
        frame := frame - 2
      END
    END
  END ForClose;

  (* --- OO / interface entry points: deferred to M4/M5 on this target --- *)
  PROCEDURE MethodItem*(VAR x: Item; m: ORB.Object; direct: BOOLEAN);
  BEGIN
    (* stash the receiver designator (current x) for PrepCall to pass as
       param 0; then turn x into the callable. *)
    x.rcvMode := x.mode; x.rcvA := x.a; x.rcvB := x.b; x.rcvR := x.r;
    x.rcvRdo := x.rdo; x.rcvType := x.type;
    x.isMeth := TRUE; x.type := m.type;
    IF direct THEN
      x.dynDisp := FALSE;
      x.mode := ORB.Const; x.a := m.backend; x.r := 0;
      (* methods always return via RTL (far convention — see Enter), so a
         direct/SUPER call must reach them with JSL even within the module *)
      x.b := 1
    ELSE
      x.dynDisp := TRUE; x.methSlot := m.val; x.mode := ORB.Const
    END
  END MethodItem;

  (* T.Name(args) constructor: allocate a fresh instance of rec (BRK #10 +
     tag header, like New), keep it in registers as the receiver, and set x
     to a direct call to the init body m. The init returns the receiver. *)
  PROCEDURE InitItem*(VAR x: Item; m: ORB.Object; rec: ORB.Type);
    VAR rh0, sb: LONGINT;
  BEGIN
    rh0 := RH;
    Set16(TRUE, TRUE);
    sb := GetSB(-rec.mno);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, sb);
    OCG.Clc;
    emitTDLen(rec);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(RH + 1));
    incR; incR;
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, rec.size + 4);
    OCG.gen1(OCG.BRK * 32 + OCG.mImm, 10);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
    OCG.gen1(OCG.STX * 32 + OCG.mDP, RegAddr(RH + 1));
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH - 2));
    OCG.gen1(OCG.STA * 32 + OCG.mDPIndL, RegAddr(RH));
    OCG.gen1(OCG.LDY * 32 + OCG.mImm, 2);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH - 1));
    OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, RegAddr(RH));
    OCG.Clc;
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH));
    OCG.gen1(OCG.ADC * 32 + OCG.mImm, 4);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
    (* object is now at [rh0+2, rh0+3]; move it over the dead tag registers to
       [rh0, rh0+1] so PrepCall only saves the genuine outer context *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(rh0));
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH + 1));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(rh0 + 1));
    RH := rh0 + 2;
    x.rcvMode := Reg; x.rcvR := rh0; x.rcvType := rec;
    x.isMeth := TRUE; x.dynDisp := FALSE; x.type := m.type;
    x.mode := ORB.Const; x.a := m.backend; x.r := 0;
    x.b := 1  (* init bodies are methods: far/RTL convention, reach via JSL *)
  END InitItem;

  (* Find or create the itable for (rec, ifc); returns its index. Deduped so
     repeated conversions of the same pair share one table. *)
  PROCEDURE RegisterItable(rec, ifc: ORB.Type): INTEGER;
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < itabC) & ~((itabRec[i] = rec) & (itabIfc[i] = ifc)) DO i := i + 1 END;
    IF i = itabC THEN
      IF itabC < maxItab THEN
        itabRec[i] := rec; itabIfc[i] := ifc; itabC := itabC + 1
      ELSE ORS.Mark("too many itables"); i := 0
      END
    END;
    RETURN i
  END RegisterItable;

  (* Emit `ADC #itable_offset` for itable idx, as a forward fixup patched in
     GenTDs (the offset isn't known until descriptors are laid out). *)
  PROCEDURE emitItabOffset(idx: INTEGER);
  BEGIN
    OCG.gen1(OCG.ADC * 32 + OCG.mImm, 0);
    IF itabRefC < maxItabRef THEN
      itabRefLoc[itabRefC] := OCG.Here() - 2; itabRefIdx[itabRefC] := idx;
      itabRefC := itabRefC + 1
    ELSE ORS.Mark("too many itable refs")
    END
  END emitItabOffset;

  (* Designator `i.m` for an interface value i: stash i's designator so PrepCall
     can pass its data word as the receiver and Call can re-read the itable and
     the vtable slot itable[m.val]. The value stays in memory, so this nests. *)
  PROCEDURE IfaceMethodItem*(VAR x: Item; m: ORB.Object);
  BEGIN
    IF (x.mode # ORB.Var) & (x.mode # ORB.Par) THEN
      ORS.Mark("interface receiver must be a variable or parameter")
    END;
    x.rcvMode := x.mode; x.rcvA := x.a; x.rcvB := x.b; x.rcvR := x.r;
    x.rcvType := x.type;
    x.isMeth := TRUE; x.dynDisp := FALSE; x.ifaceDisp := TRUE;
    x.methSlot := m.val; x.type := m.type;
    x.mode := ORB.Const
  END IfaceMethodItem;

  (* pointer (or NIL) -> interface fat value {data, itable} in 4 registers. *)
  PROCEDURE PtrToIface*(VAR x: Item; ift: ORB.Type);
    VAR idx, r0: INTEGER;
  BEGIN
    IF (x.type = NIL) OR (x.type.form # ORB.Pointer) THEN
      Set16(TRUE, TRUE); r0 := RH;
      OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(RH));
      OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(RH + 1));
      OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(RH + 2));
      OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(RH + 3));
      incR; incR; incR; incR
    ELSE
      load(x);                    (* pointer (data) now in R[x.r], R[x.r+1] *)
      idx := RegisterItable(x.type.base, ift);
      Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, SB_DP);
      OCG.Clc;
      emitItabOffset(idx);        (* A := SB + itable_offset *)
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, BANK_DP);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1));
      r0 := x.r; incR; incR
    END;
    x.mode := Reg; x.r := r0; x.type := ift; x.b := 0; x.rdo := FALSE
  END PtrToIface;

  (* interface-var := interface-value: copy all four words. *)
  PROCEDURE StoreIface*(VAR x, y: Item);
    VAR sb, k: LONGINT;
  BEGIN
    load(y);   (* fat value in R[y.r .. y.r+3] *)
    Set16(TRUE, TRUE);
    IF (x.mode = ORB.Var) & (x.r <= 0) THEN
      sb := GetSB(x.r); k := 0;
      WHILE k < 4 DO
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r + k));
        OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a + k * 2);
        OCG.gen1(OCG.STA * 32 + OCG.mDPIndY, sb);
        k := k + 1
      END
    ELSE   (* local Var or Par: stack-frame relative *)
      k := 0;
      WHILE k < 4 DO
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r + k));
        OCG.gen1(OCG.STA * 32 + OCG.mSR, x.a + k * 2 + frame);
        k := k + 1
      END
    END;
    RH := y.r
  END StoreIface;

  (* = / # on interface values: compare the data words (word 0). One side may
     be NIL (a plain zero pointer/nil). Result is a Cond item. *)
  PROCEDURE IfaceRelation*(op: INTEGER; VAR x, y: Item);
  BEGIN
    (* both sides materialize with their data word first (a 4-word fat value or
       a 2-word pointer/NIL), so comparing words 0..1 compares the references *)
    load(x); load(y);
    Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
    OCG.gen1(OCG.EOR * 32 + OCG.mDP, RegAddr(y.r));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r));
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r + 1));
    OCG.gen1(OCG.EOR * 32 + OCG.mDP, RegAddr(y.r + 1));
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, RegAddr(x.r));
    RH := x.r; x.type := ORB.boolType;
    IF op = ORS.eql THEN SetCC(x, EQ) ELSE SetCC(x, NE) END
  END IfaceRelation;

  PROCEDURE Init*;
  BEGIN
    relmap[0] := EQ; relmap[1] := NE; relmap[2] := LT;
    relmap[3] := GE; relmap[4] := LE; relmap[5] := GT;
    OCG.Init
  END Init;

END ORG.
