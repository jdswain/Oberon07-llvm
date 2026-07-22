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

  IMPORT SYSTEM, OCG, ORS, ORB, Files;

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

    (* FP workspace DP addresses *)
    FP_A_LO = 22H; FP_A_HI = 24H; FP_B_LO = 26H; FP_B_HI = 28H;
    FP_SIGN = 2AH; FP_EXP = 2CH; FP_M1_LO = 2EH; FP_M1_HI = 30H;
    FP_M2_LO = 32H; FP_M2_HI = 34H; FP_PROD0 = 36H; FP_PROD1 = 38H;
    FP_PROD2 = 3AH; FP_TEMP = 3CH; FP_TEMP2 = 3EH; FP_CNT = 40H;
    (* FP operation indices *)
    FP_ADD = 0; FP_MUL = 1; FP_DIV = 2; FP_CMP = 3;
    FP_FLOOR = 4; FP_FLT = 5; FP_OPS = 6;
    maxFPFixups = 64;
    maxForNest = 8;        (* max nested FOR loops with a non-const limit *)
    maxEnt = 256;          (* max .816 export-table entries *)
    maxMeth = 64;          (* max vtable slots per type *)
    maxVtFix = 512;        (* max vtable-slot loader fixups per module *)
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
      methSlot*: LONGINT;
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
    data: ARRAY maxTD OF LONGINT;      (* 16-bit TD words (LONGINT so
                                          0FFFFH fits a 16-bit-INTEGER host) *)
    str: ARRAY maxStrx OF INTEGER;     (* string/const data bytes *)
    tdFixupOff, tdFixupMno: ARRAY maxTD OF INTEGER;
    tdFixupC: INTEGER;
    (* deferred type descriptors (classic Oberon-2 single-pass): types are
       recorded at declaration and their descriptors generated at Close,
       placed after the variables + strings so the vtable size is known.
       New/TypeTest emit T.len as a forward fixup patched in GenTDs. *)
    tdList: ARRAY maxTD OF ORB.Type;
    tdListC: INTEGER;
    tdBase: LONGINT;                              (* var-relative base of TD region *)
    tdRefLoc: ARRAY maxTD OF LONGINT;             (* code sites needing a T.len *)
    tdRefTyp: ARRAY maxTD OF ORB.Type;
    tdRefC: INTEGER;
    entryVal: ARRAY maxEnt OF LONGINT;            (* .816 entry table, by exno *)
    vtFixOff, vtFixMno, vtFixExno: ARRAY maxVtFix OF LONGINT;  (* vtable slot fixups *)
    vtFixC: INTEGER;
    slotMeth: ARRAY maxMeth OF ORB.Object;        (* method per vtable slot *)
    slotMno: ARRAY maxMeth OF LONGINT;            (* its defining type's mno *)
    fpFixups: ARRAY FP_OPS, maxFPFixups OF LONGINT;
    fpFixupCount: ARRAY FP_OPS OF INTEGER;
    fpSubAddr: ARRAY FP_OPS OF LONGINT;
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
      OCG.Gen(OCG.REP, OCG.mImm, val, 0)
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
      OCG.Gen(OCG.SEP, OCG.mImm, val, 0)
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
      OCG.Gen(OCG.LDA, OCG.mImm, -mno, 0);
      OCG.Gen(OCG.STA, OCG.mDP, SB_TEMP, 0);
      OCG.AddRel(OCG.Here() + 80000000H);   (* bank reloc flag (bit 31) *)
      OCG.Gen(OCG.LDA, OCG.mImm, -mno, 0);
      OCG.Gen(OCG.STA, OCG.mDP, SB_TEMP_BANK, 0);
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
      OCG.Gen(OCG.BEQ, OCG.mPCR, OCG.Here() + 4, 0);
      OCG.Gen(OCG.BRK, OCG.mImm, num, 0)
    ELSIF cond = NE THEN
      OCG.Gen(OCG.BNE, OCG.mPCR, OCG.Here() + 4, 0);
      OCG.Gen(OCG.BRK, OCG.mImm, num, 0)
    ELSIF cond = MI THEN
      OCG.Gen(OCG.BMI, OCG.mPCR, OCG.Here() + 4, 0);
      OCG.Gen(OCG.BRK, OCG.mImm, num, 0)
    ELSIF cond = PL THEN
      OCG.Gen(OCG.BPL, OCG.mPCR, OCG.Here() + 4, 0);
      OCG.Gen(OCG.BRK, OCG.mImm, num, 0)
    ELSIF cond = LT THEN
      OCG.Gen(OCG.BCC, OCG.mPCR, OCG.Here() + 4, 0);
      OCG.Gen(OCG.BRK, OCG.mImm, num, 0)
    ELSIF cond = GE THEN
      OCG.Gen(OCG.BCS, OCG.mPCR, OCG.Here() + 4, 0);
      OCG.Gen(OCG.BRK, OCG.mImm, num, 0)
    ELSIF cond = LE THEN
      OCG.Gen(OCG.BEQ, OCG.mPCR, OCG.Here() + 4 + 4, 0);
      OCG.Gen(OCG.BCC, OCG.mPCR, OCG.Here() + 4 + 2, 0);
      OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 4, 0);
      OCG.Gen(OCG.BRK, OCG.mImm, num, 0)
    ELSIF cond = GT THEN
      OCG.Gen(OCG.BEQ, OCG.mPCR, OCG.Here() + 4 + 2, 0);
      OCG.Gen(OCG.BCS, OCG.mPCR, OCG.Here() + 4, 0);
      OCG.Gen(OCG.BRK, OCG.mImm, num, 0)
    ELSIF cond = AL THEN
      OCG.Gen(OCG.BRK, OCG.mImm, num, 0)
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
      OCG.Gen(OCG.BNE, OCG.mPCR, OCG.Here() + 2 + 3, 0);
      OCG.Gen(OCG.BRL, mode, target, 0)
    ELSIF cond = NE THEN
      OCG.Gen(OCG.BEQ, OCG.mPCR, OCG.Here() + 2 + 3, 0);
      OCG.Gen(OCG.BRL, mode, target, 0)
    ELSIF cond = MI THEN
      OCG.Gen(OCG.BPL, OCG.mPCR, OCG.Here() + 2 + 3, 0);
      OCG.Gen(OCG.BRL, mode, target, 0)
    ELSIF cond = PL THEN
      OCG.Gen(OCG.BMI, OCG.mPCR, OCG.Here() + 2 + 3, 0);
      OCG.Gen(OCG.BRL, mode, target, 0)
    ELSIF cond = LT THEN
      IF signed THEN
        OCG.Gen(OCG.BVS, OCG.mPCR, OCG.Here() + 2 + 4, 0);
        OCG.Gen(OCG.BMI, OCG.mPCR, OCG.Here() + 2 + 6, 0);
        OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 7, 0);
        OCG.Gen(OCG.BPL, OCG.mPCR, OCG.Here() + 2 + 2, 0);
        OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 3, 0);
        OCG.Gen(OCG.BRL, mode, target, 0)
      ELSE
        OCG.Gen(OCG.BCS, OCG.mPCR, OCG.Here() + 2 + 3, 0);
        OCG.Gen(OCG.BRL, mode, target, 0)
      END
    ELSIF cond = GE THEN
      IF signed THEN
        OCG.Gen(OCG.BVS, OCG.mPCR, OCG.Here() + 2 + 4, 0);
        OCG.Gen(OCG.BPL, OCG.mPCR, OCG.Here() + 2 + 6, 0);
        OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 7, 0);
        OCG.Gen(OCG.BMI, OCG.mPCR, OCG.Here() + 2 + 2, 0);
        OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 3, 0);
        OCG.Gen(OCG.BRL, mode, target, 0)
      ELSE
        OCG.Gen(OCG.BCC, OCG.mPCR, OCG.Here() + 2 + 3, 0);
        OCG.Gen(OCG.BRL, mode, target, 0)
      END
    ELSIF cond = LE THEN
      IF signed THEN
        OCG.Gen(OCG.BEQ, OCG.mPCR, OCG.Here() + 2 + 10, 0);
        OCG.Gen(OCG.BVS, OCG.mPCR, OCG.Here() + 2 + 4, 0);
        OCG.Gen(OCG.BMI, OCG.mPCR, OCG.Here() + 2 + 6, 0);
        OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 7, 0);
        OCG.Gen(OCG.BPL, OCG.mPCR, OCG.Here() + 2 + 2, 0);
        OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 3, 0);
        OCG.Gen(OCG.BRL, mode, target, 0)
      ELSE
        OCG.Gen(OCG.BEQ, OCG.mPCR, OCG.Here() + 2 + 2, 0);
        OCG.Gen(OCG.BCS, OCG.mPCR, OCG.Here() + 2 + 3, 0);
        OCG.Gen(OCG.BRL, mode, target, 0)
      END
    ELSIF cond = GT THEN
      IF signed THEN
        OCG.Gen(OCG.BEQ, OCG.mPCR, OCG.Here() + 2 + 13, 0);
        OCG.Gen(OCG.BVS, OCG.mPCR, OCG.Here() + 2 + 4, 0);
        OCG.Gen(OCG.BPL, OCG.mPCR, OCG.Here() + 2 + 6, 0);
        OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 7, 0);
        OCG.Gen(OCG.BMI, OCG.mPCR, OCG.Here() + 2 + 2, 0);
        OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 3, 0);
        OCG.Gen(OCG.BRL, mode, target, 0)
      ELSE
        OCG.Gen(OCG.BEQ, OCG.mPCR, OCG.Here() + 2 + 4, 0);
        OCG.Gen(OCG.BCC, OCG.mPCR, OCG.Here() + 2 + 2, 0);
        OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 3, 0);
        OCG.Gen(OCG.BRL, mode, target, 0)
      END
    ELSIF cond = AL THEN
      OCG.Gen(OCG.BRL, mode, target, 0)
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
    WHILE L # 0 DO
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
    OCG.Gen(op, OCG.mPCR, OCG.Here() + 2, 0);
    RETURN OCG.Here() - 1
  END emitFwdBranch;

  (* --- load: materialize item x into register(s), leaving x in Reg mode --- *)
  PROCEDURE load(VAR x: Item);
    VAR perAddr, perOp, mno, exno, encoded, sb, falseChain: LONGINT;
  BEGIN
    IF x.mode # Reg THEN
      IF x.mode = ORB.Const THEN
        IF (x.type.form = ORB.NilTyp) OR (x.type.form = ORB.Pointer) THEN
          Set16(TRUE, TRUE);
          OCG.Gen(OCG.STZ, OCG.mDP, RegAddr(RH), 0);
          OCG.Gen(OCG.STZ, OCG.mDP, RegAddr(RH + 1), 0);
          x.r := RH; incR; incR
        ELSIF x.type.form = ORB.Proc THEN
          IF (x.r > 0) OR ((x.r = 0) & (x.b = 0)) THEN
            ORS.Mark("not exportd")
          ELSIF (x.r = 0) & (x.b = 1) THEN
            Set16(TRUE, TRUE);
            perAddr := OCG.Here();
            perOp := x.a - perAddr - 3;
            OCG.Gen(OCG.PER, OCG.mImm, Lo16(perOp), 0);
            OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
            OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
            OCG.Gen(OCG.STZ, OCG.mDP, RegAddr(RH + 1), 0);
            OCG.Gen(OCG.PHK, OCG.mImpl, 0, 0);
            Set8(TRUE, FALSE);
            OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
            OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 1), 0);
            Set16(TRUE, FALSE);
            x.r := RH; incR; incR
          ELSE
            Set16(TRUE, TRUE);
            mno := -x.r; exno := x.a;
            encoded := mno * 100H + (exno MOD 100H);
            OCG.AddRel(OCG.Here());
            OCG.Gen(OCG.PER, OCG.mImm, encoded, 0);
            OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
            OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
            OCG.Gen(OCG.STZ, OCG.mDP, RegAddr(RH + 1), 0);
            OCG.Gen(OCG.PHK, OCG.mImpl, 0, 0);
            Set8(TRUE, FALSE);
            OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
            OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 1), 0);
            Set16(TRUE, FALSE);
            x.r := RH; incR; incR
          END
        ELSIF x.type.form = ORB.Real THEN
          Set16(TRUE, TRUE);
          OCG.Gen(OCG.LDA, OCG.mImm, Lo16(x.a), 0);
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
          OCG.Gen(OCG.LDA, OCG.mImm, Hi16(x.a), 0);
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 1), 0);
          x.r := RH; incR; incR
        ELSIF (x.a <= 0FFFFH) & (x.a >= -10000H) THEN
          IF x.type.size = 1 THEN
            Set8(TRUE, FALSE);
            OCG.Gen(OCG.LDA, OCG.mImm, x.a MOD 100H, 0);
            Set16(TRUE, FALSE);
            OCG.Gen(OCG.AND, OCG.mImm, 0FFH, 0);
            OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0)
          ELSE
            Set16(TRUE, TRUE);
            OCG.Gen(OCG.LDA, OCG.mImm, Lo16(x.a), 0);
            OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0)
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
            OCG.Gen(OCG.LDA, OCG.mSR, x.a + frame, 0);
            OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
            OCG.Gen(OCG.LDA, OCG.mSR, x.a + 2 + frame, 0);
            OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 1), 0);
            x.r := RH; incR; incR
          ELSIF x.type.size = 1 THEN
            Set8(TRUE, FALSE);
            OCG.Gen(OCG.LDA, OCG.mSR, x.a + frame, 0);
            Set16(TRUE, FALSE);
            OCG.Gen(OCG.AND, OCG.mImm, 0FFH, 0);
            OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
            x.r := RH; incR
          ELSE
            Set16(TRUE, TRUE);
            OCG.Gen(OCG.LDA, OCG.mSR, x.a + frame, 0);
            OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
            x.r := RH; incR
          END
        ELSE
          sb := GetSB(x.r);
          IF (x.type.form = ORB.Pointer) OR (x.type.form = ORB.NilTyp)
             OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) THEN
            Set16(TRUE, TRUE);
            OCG.Gen(OCG.LDY, OCG.mImm, x.a, 0);
            OCG.Gen(OCG.LDA, OCG.mDPIndY, sb, 0);
            OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
            OCG.Gen(OCG.LDY, OCG.mImm, x.a + 2, 0);
            OCG.Gen(OCG.LDA, OCG.mDPIndY, sb, 0);
            OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 1), 0);
            x.r := RH; incR; incR
          ELSIF x.type.size = 1 THEN
            Set8(TRUE, FALSE);
            OCG.Gen(OCG.LDY, OCG.mImm, x.a, 0);
            OCG.Gen(OCG.LDA, OCG.mDPIndY, sb, 0);
            Set16(TRUE, FALSE);
            OCG.Gen(OCG.AND, OCG.mImm, 0FFH, 0);
            OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
            x.r := RH; incR
          ELSE
            Set16(TRUE, TRUE);
            OCG.Gen(OCG.LDY, OCG.mImm, x.a, 0);
            OCG.Gen(OCG.LDA, OCG.mDPIndY, sb, 0);
            OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
            x.r := RH; incR
          END
        END
      ELSIF x.mode = ORB.Par THEN
        Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDA, OCG.mSR, x.a + frame, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
        OCG.Gen(OCG.LDA, OCG.mSR, x.a + 2 + frame, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 1), 0);
        IF (x.type.form = ORB.Real) OR (x.type.form = ORB.Pointer) OR (x.type.form = ORB.Proc) THEN
          Set16(TRUE, TRUE);
          IF x.b # 0 THEN
            OCG.Gen(OCG.LDY, OCG.mImm, x.b + 2, 0);
            OCG.Gen(OCG.LDA, OCG.mDPIndLY, RegAddr(RH), 0);
            OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
            OCG.Gen(OCG.LDY, OCG.mImm, x.b, 0);
            OCG.Gen(OCG.LDA, OCG.mDPIndLY, RegAddr(RH), 0)
          ELSE
            OCG.Gen(OCG.LDY, OCG.mImm, 2, 0);
            OCG.Gen(OCG.LDA, OCG.mDPIndLY, RegAddr(RH), 0);
            OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
            OCG.Gen(OCG.LDA, OCG.mDPIndL, RegAddr(RH), 0)
          END;
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
          OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 1), 0);
          x.r := RH; incR; incR
        ELSIF x.type.size = 1 THEN
          Set8(TRUE, FALSE);
          IF x.b # 0 THEN
            OCG.Gen(OCG.LDY, OCG.mImm, x.b, 0);
            OCG.Gen(OCG.LDA, OCG.mDPIndLY, RegAddr(RH), 0)
          ELSE
            OCG.Gen(OCG.LDA, OCG.mDPIndL, RegAddr(RH), 0)
          END;
          Set16(TRUE, FALSE);
          OCG.Gen(OCG.AND, OCG.mImm, 0FFH, 0);
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
          x.r := RH; incR
        ELSE
          Set16(TRUE, TRUE);
          IF x.b # 0 THEN
            OCG.Gen(OCG.LDY, OCG.mImm, x.b, 0);
            OCG.Gen(OCG.LDA, OCG.mDPIndLY, RegAddr(RH), 0)
          ELSE
            OCG.Gen(OCG.LDA, OCG.mDPIndL, RegAddr(RH), 0)
          END;
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
          x.r := RH; incR
        END
      ELSIF x.mode = RegI THEN
        IF (x.type.form = ORB.Pointer) OR (x.type.form = ORB.NilTyp)
           OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) THEN
          Set16(TRUE, TRUE);
          OCG.Gen(OCG.LDY, OCG.mImm, x.a + 2, 0);
          OCG.Gen(OCG.LDA, OCG.mDPIndLY, RegAddr(x.r), 0);
          OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
          IF x.a = 0 THEN
            OCG.Gen(OCG.LDA, OCG.mDPIndL, RegAddr(x.r), 0)
          ELSE
            OCG.Gen(OCG.LDY, OCG.mImm, x.a, 0);
            OCG.Gen(OCG.LDA, OCG.mDPIndLY, RegAddr(x.r), 0)
          END;
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0);
          OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r + 1), 0)
        ELSIF x.type.size = 1 THEN
          Set8(TRUE, FALSE);
          IF x.a = 0 THEN
            OCG.Gen(OCG.LDA, OCG.mDPIndL, RegAddr(x.r), 0)
          ELSE
            OCG.Gen(OCG.LDY, OCG.mImm, x.a, 0);
            OCG.Gen(OCG.LDA, OCG.mDPIndLY, RegAddr(x.r), 0)
          END;
          Set16(TRUE, FALSE);
          OCG.Gen(OCG.AND, OCG.mImm, 0FFH, 0);
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0);
          RH := RH - 1
        ELSE
          Set16(TRUE, TRUE);
          IF x.a = 0 THEN
            OCG.Gen(OCG.LDA, OCG.mDPIndL, RegAddr(x.r), 0)
          ELSE
            OCG.Gen(OCG.LDY, OCG.mImm, x.a, 0);
            OCG.Gen(OCG.LDA, OCG.mDPIndLY, RegAddr(x.r), 0)
          END;
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0);
          RH := RH - 1
        END
      ELSIF x.mode = Cond THEN
        emitBranch(negated(x.r), x.origType, OCG.mFix, x.a);
        falseChain := OCG.Here() - 2;   (* BRL offset field = FALSE chain head *)
        FixLink(x.b);                    (* TRUE path *)
        OCG.Gen(OCG.LDA, OCG.mImm, 1, 0);
        OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 3, 0);
        FixLink(falseChain);             (* FALSE path *)
        OCG.Gen(OCG.LDA, OCG.mImm, 0, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
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
        OCG.Gen(OCG.TSC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.ADC, OCG.mImm, x.a + frame, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
        OCG.Gen(OCG.STZ, OCG.mDP, RegAddr(RH + 1), 0)
      ELSE
        sb := GetSB(x.r);
        Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDA, OCG.mImm, x.a, 0);
        OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.ADC, OCG.mDP, sb, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
        IF x.r >= 0 THEN
          OCG.Gen(OCG.LDA, OCG.mDP, BANK_DP, 0)
        ELSE
          OCG.Gen(OCG.LDA, OCG.mDP, SB_TEMP_BANK, 0)
        END;
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 1), 0)
      END;
      x.r := RH; incR; incR
    ELSIF x.mode = ORB.Par THEN
      Set16(TRUE, TRUE);
      OCG.Gen(OCG.LDA, OCG.mSR, x.a + frame, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
      OCG.Gen(OCG.LDA, OCG.mSR, x.a + 2 + frame, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 1), 0);
      IF x.b # 0 THEN
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(RH), 0);
        OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.ADC, OCG.mImm, x.b, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0)
      END;
      x.r := RH; incR; incR
    ELSIF x.mode = RegI THEN
      IF x.a # 0 THEN
        Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
        OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.ADC, OCG.mImm, x.a, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0)
      END
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
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
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
    OCG.Gen(OCG.LDA, OCG.mDP, SB_DP, 0);
    OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.ADC, OCG.mImm, varsize + x.a, 0);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
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
        str[strx] := ORD(ORS.str[i]); strx := strx + 1; i := i + 1; len := len - 1
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
    IF strx < maxStrx THEN str[strx] := b MOD 100H; strx := strx + 1
    ELSE ORS.Mark("string space overflow")
    END
  END PutByte;

  PROCEDURE MakeItem*(VAR x: Item; y: ORB.Object; curlev: LONGINT);
  BEGIN
    x.isMeth := FALSE; x.dynDisp := FALSE;   (* clear stale OO state on reuse *)
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
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
          OCG.Gen(OCG.CMP, OCG.mImm, lim, 0);
          Trap(LT, 1)
        ELSIF (x.mode = ORB.Var) OR (x.mode = ORB.Par) THEN
          Set16(TRUE, TRUE);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
          OCG.Gen(OCG.CMP, OCG.mSR, x.a + 4 + frame, 0);
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
          WHILE i < shifts DO OCG.Gen(OCG.ASL, OCG.mDP, RegAddr(y.r), 0); i := i + 1 END
        ELSE
          idxReg := RegAddr(y.r);
          i := 0;
          WHILE i < shifts DO OCG.Gen(OCG.ASL, OCG.mDP, idxReg, 0); i := i + 1 END;
          OCG.Gen(OCG.LDA, OCG.mDP, idxReg, 0);
          remaining := ts DIV 2;
          WHILE remaining > 0 DO
            OCG.Gen(OCG.ASL, OCG.mDP, idxReg, 0);
            IF ODD(remaining) THEN
              OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
              OCG.Gen(OCG.ADC, OCG.mDP, idxReg, 0)
            END;
            remaining := remaining DIV 2
          END;
          OCG.Gen(OCG.STA, OCG.mDP, idxReg, 0)
        END
      END;
      IF x.mode = ORB.Var THEN
        IF x.r > 0 THEN
          Set16(TRUE, TRUE);
          OCG.Gen(OCG.TSC, OCG.mImpl, 0, 0);
          OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
          OCG.Gen(OCG.ADC, OCG.mImm, x.a + frame, 0);
          OCG.Gen(OCG.ADC, OCG.mDP, RegAddr(y.r), 0);
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(y.r), 0)
        ELSE
          sb := GetSB(x.r);
          Set16(TRUE, TRUE);
          OCG.Gen(OCG.LDA, OCG.mDP, sb, 0);
          OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
          OCG.Gen(OCG.ADC, OCG.mImm, x.a, 0);
          OCG.Gen(OCG.ADC, OCG.mDP, RegAddr(y.r), 0);
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(y.r), 0)
        END;
        OCG.Gen(OCG.STZ, OCG.mDP, RegAddr(RH), 0);
        x.a := 0; x.r := y.r; x.mode := RegI; incR
      ELSIF x.mode = ORB.Par THEN
        Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDA, OCG.mSR, x.a + frame, 0);
        OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.ADC, OCG.mDP, RegAddr(y.r), 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(y.r), 0);
        OCG.Gen(OCG.LDA, OCG.mSR, x.a + 2 + frame, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
        incR;
        x.mode := RegI; x.r := y.r; x.a := x.b
      ELSIF x.mode = ORB.Const THEN
        Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDA, OCG.mDP, SB_DP, 0);
        OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.ADC, OCG.mImm, varsize + x.a, 0);
        OCG.Gen(OCG.ADC, OCG.mDP, RegAddr(y.r), 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(y.r), 0);
        OCG.Gen(OCG.STZ, OCG.mDP, RegAddr(RH), 0);
        x.a := 0; x.r := y.r; x.mode := RegI; incR
      ELSIF x.mode = RegI THEN
        Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
        OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.ADC, OCG.mDP, RegAddr(y.r), 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0);
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
        OCG.Gen(OCG.LDA, OCG.mSR, x.a + frame, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
        OCG.Gen(OCG.LDA, OCG.mSR, x.a + 2 + frame, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 1), 0)
      ELSE
        sb := GetSB(x.r);
        OCG.Gen(OCG.LDY, OCG.mImm, x.a, 0);
        OCG.Gen(OCG.LDA, OCG.mDPIndY, sb, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
        OCG.Gen(OCG.LDY, OCG.mImm, x.a + 2, 0);
        OCG.Gen(OCG.LDA, OCG.mDPIndY, sb, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 1), 0)
      END;
      IF check THEN
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(RH), 0);
        OCG.Gen(OCG.ORA, OCG.mDP, RegAddr(RH + 1), 0);
        Trap(NE, 4)
      END;
      x.r := RH; incR; incR
    ELSIF x.mode = ORB.Par THEN
      OCG.Gen(OCG.LDA, OCG.mSR, x.a + frame, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
      OCG.Gen(OCG.LDA, OCG.mSR, x.a + 2 + frame, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 1), 0);
      OCG.Gen(OCG.LDY, OCG.mImm, x.b + 2, 0);
      OCG.Gen(OCG.LDA, OCG.mDPIndLY, RegAddr(RH), 0);
      OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
      IF x.b = 0 THEN
        OCG.Gen(OCG.LDA, OCG.mDPIndL, RegAddr(RH), 0)
      ELSE
        OCG.Gen(OCG.LDY, OCG.mImm, x.b, 0);
        OCG.Gen(OCG.LDA, OCG.mDPIndLY, RegAddr(RH), 0)
      END;
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
      OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 1), 0);
      IF check THEN
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(RH), 0);
        OCG.Gen(OCG.ORA, OCG.mDP, RegAddr(RH + 1), 0);
        Trap(NE, 4)
      END;
      x.r := RH; incR; incR
    ELSIF x.mode = RegI THEN
      OCG.Gen(OCG.LDY, OCG.mImm, x.a + 2, 0);
      OCG.Gen(OCG.LDA, OCG.mDPIndLY, RegAddr(x.r), 0);
      OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
      IF x.a = 0 THEN
        OCG.Gen(OCG.LDA, OCG.mDPIndL, RegAddr(x.r), 0)
      ELSE
        OCG.Gen(OCG.LDY, OCG.mImm, x.a, 0);
        OCG.Gen(OCG.LDA, OCG.mDPIndLY, RegAddr(x.r), 0)
      END;
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0);
      OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r + 1), 0);
      IF check THEN
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
        OCG.Gen(OCG.ORA, OCG.mDP, RegAddr(x.r + 1), 0);
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
      data[dcw] := T.len; data[dcw + 1] := 0;
      tdFixupOff[tdFixupC] := tdBase + dcw * 2; tdFixupMno[tdFixupC] := T.mno;
      tdFixupC := tdFixupC + 1;
      dcw := dcw + 2
    END
  END Q;

  PROCEDURE FindPtrFlds(typ: ORB.Type; off: LONGINT; VAR dcw: LONGINT);
    VAR fld: ORB.Object; i, s: LONGINT;
  BEGIN
    IF (typ.form = ORB.Pointer) OR (typ.form = ORB.NilTyp) THEN
      data[dcw] := off; dcw := dcw + 1
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
      OCG.Gen(OCG.ADC, OCG.mImm, 0, 0);
      IF tdRefC < maxTD THEN
        tdRefLoc[tdRefC] := OCG.Here() - 2; tdRefTyp[tdRefC] := T;
        tdRefC := tdRefC + 1
      ELSE ORS.Mark("too many descriptor refs")
      END
    ELSE OCG.Gen(OCG.ADC, OCG.mImm, T.len, 0)
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

  (* Generate every recorded descriptor into data[], placed at var-relative
     offset tdBase = varsize + strx (after the variables and strings), and
     patch the forward T.len references. Called from Close. *)
  PROCEDURE GenTDs;
    VAR i, dcw, k, s, nm: LONGINT; T: ORB.Type;
  BEGIN
    tdBase := varsize + strx; dcw := 0; i := 0;
    WHILE i < tdListC DO
      T := tdList[i];
      T.len := tdBase + dcw * 2;
      data[dcw] := T.size; dcw := dcw + 1;
      k := T.nofpar;
      IF k > 3 THEN ORS.Mark("ext level too large")
      ELSE
        Q(T, dcw);
        WHILE k < 3 DO
          data[dcw] := 0FFFFH; data[dcw + 1] := 0FFFFH;
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
      data[dcw] := nm; dcw := dcw + 1;
      IF nm > 0 THEN
        s := 0; WHILE s < nm DO slotMeth[s] := NIL; slotMno[s] := 0; s := s + 1 END;
        fillVt(T, nm);
        s := 0;
        WHILE s < nm DO
          IF slotMeth[s] = NIL THEN data[dcw + s] := 0   (* abstract: no impl *)
          ELSE
            IF vtFixC >= maxVtFix THEN ORS.Mark("too many vtable fixups")
            ELSE
              vtFixOff[vtFixC] := tdBase + (dcw + s) * 2;
              IF slotMno[s] <= 0 THEN   (* own method: slot = base + offset *)
                data[dcw + s] := slotMeth[s].backend;
                vtFixMno[vtFixC] := 0; vtFixExno[vtFixC] := 0
              ELSE                      (* imported inherited: loader resolves *)
                data[dcw + s] := 0;
                vtFixMno[vtFixC] := slotMno[s];
                vtFixExno[vtFixC] := slotMeth[s].exno
              END;
              vtFixC := vtFixC + 1
            END
          END;
          s := s + 1
        END;
        dcw := dcw + nm
      END;
      FindPtrFlds(T, 0, dcw);
      data[dcw] := 0FFFFH; dcw := dcw + 1;
      i := i + 1
    END;
    tdx := dcw;
    IF tdx >= maxTD THEN ORS.Mark("too many record types"); tdx := 0 END;
    i := 0;
    WHILE i < tdRefC DO
      OCG.Patch(tdRefLoc[i], tdRefTyp[i].len MOD 100H);
      OCG.Patch(tdRefLoc[i] + 1, tdRefTyp[i].len DIV 100H MOD 100H);
      i := i + 1
    END
  END GenTDs;

  PROCEDURE TypeTest*(VAR x: Item; T: ORB.Type; varpar, isguard: BOOLEAN);
    VAR offset, sb, nilSkip: LONGINT;
  BEGIN
    IF T = NIL THEN
      IF x.mode >= Reg THEN RH := RH - 1 END;
      SetCC(x, AL)
    ELSIF varpar THEN
      Set16(TRUE, TRUE);
      incR; incR;
      OCG.Gen(OCG.LDA, OCG.mSR, x.a + 4 + frame, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 2), 0);
      OCG.Gen(OCG.LDA, OCG.mSR, x.a + 6 + frame, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 1), 0);
      offset := 2 + (T.nofpar - 1) * 4;
      OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(RH - 2), 0);
      OCG.Gen(OCG.ADC, OCG.mImm, offset, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 2), 0);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(RH - 1), 0);
      OCG.Gen(OCG.ADC, OCG.mImm, 0, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 1), 0);
      OCG.Gen(OCG.LDA, OCG.mDPIndL, RegAddr(RH - 2), 0);
      OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.LDY, OCG.mImm, 2, 0);
      OCG.Gen(OCG.LDA, OCG.mDPIndLY, RegAddr(RH - 2), 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 1), 0);
      OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 2), 0);
      sb := GetSB(-T.mno);
      OCG.Gen(OCG.LDA, OCG.mDP, sb, 0);
      OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
      emitTDLen(T);
      OCG.Gen(OCG.EOR, OCG.mDP, RegAddr(RH - 2), 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 2), 0);
      OCG.Gen(OCG.LDA, OCG.mImm, 0, 0);
      OCG.Gen(OCG.EOR, OCG.mDP, RegAddr(RH - 1), 0);
      OCG.Gen(OCG.ORA, OCG.mDP, RegAddr(RH - 2), 0);
      RH := RH - 2;
      IF isguard THEN
        IF check THEN Trap(EQ, 2) END
      ELSE x.origType := ORB.intType; SetCC(x, EQ)
      END
    ELSE
      load(x);
      Set16(TRUE, TRUE);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
      OCG.Gen(OCG.ORA, OCG.mDP, RegAddr(x.r + 1), 0);
      nilSkip := emitFwdBranch(OCG.BEQ);
      incR; incR;
      OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
      OCG.Gen(OCG.SBC, OCG.mImm, 4, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 2), 0);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r + 1), 0);
      OCG.Gen(OCG.SBC, OCG.mImm, 0, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 1), 0);
      OCG.Gen(OCG.LDA, OCG.mDPIndL, RegAddr(RH - 2), 0);
      OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.LDY, OCG.mImm, 2, 0);
      OCG.Gen(OCG.LDA, OCG.mDPIndLY, RegAddr(RH - 2), 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 1), 0);
      OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 2), 0);
      offset := 2 + (T.nofpar - 1) * 4;
      OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(RH - 2), 0);
      OCG.Gen(OCG.ADC, OCG.mImm, offset, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 2), 0);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(RH - 1), 0);
      OCG.Gen(OCG.ADC, OCG.mImm, 0, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 1), 0);
      OCG.Gen(OCG.LDA, OCG.mDPIndL, RegAddr(RH - 2), 0);
      OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.LDY, OCG.mImm, 2, 0);
      OCG.Gen(OCG.LDA, OCG.mDPIndLY, RegAddr(RH - 2), 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 1), 0);
      OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 2), 0);
      sb := GetSB(-T.mno);
      OCG.Gen(OCG.LDA, OCG.mDP, sb, 0);
      OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
      emitTDLen(T);
      OCG.Gen(OCG.EOR, OCG.mDP, RegAddr(RH - 2), 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 2), 0);
      OCG.Gen(OCG.LDA, OCG.mImm, 0, 0);
      OCG.Gen(OCG.EOR, OCG.mDP, RegAddr(RH - 1), 0);
      OCG.Gen(OCG.ORA, OCG.mDP, RegAddr(RH - 2), 0);
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
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
        OCG.Gen(OCG.EOR, OCG.mImm, 0FFFFH, 0);
        OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.ADC, OCG.mImm, 1, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0)
      END
    ELSIF x.type.form = ORB.Real THEN
      IF x.mode = ORB.Const THEN x.a := EOR(x.a, 80000000H)
      ELSE
        load(x); Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r + 1), 0);
        OCG.Gen(OCG.EOR, OCG.mImm, 8000H, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r + 1), 0)
      END
    ELSE (* Set *)
      IF x.mode = ORB.Const THEN x.a := -x.a - 1
      ELSE
        load(x);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
        OCG.Gen(OCG.EOR, OCG.mImm, 0FFFFH, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0)
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
            OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
            OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
            OCG.Gen(OCG.ADC, OCG.mImm, x.a, 0);
            OCG.Gen(OCG.STA, OCG.mDP, RegAddr(y.r), 0)
          END
        END;
        x.mode := y.mode; x.r := y.r
      ELSIF y.mode = ORB.Const THEN
        load(x);
        IF y.a # 0 THEN
          IF x.type.form = ORB.Int THEN
            Set16(TRUE, TRUE);
            OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
            OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
            OCG.Gen(OCG.ADC, OCG.mImm, y.a, 0);
            OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0)
          END
        END
      ELSE
        load(x); load(y);
        IF x.type.form = ORB.Int THEN
          destR := RH - 2; Set16(TRUE, TRUE);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
          OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
          OCG.Gen(OCG.ADC, OCG.mDP, RegAddr(y.r), 0);
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(destR), 0)
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
            OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
            OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
            OCG.Gen(OCG.SBC, OCG.mImm, y.a, 0);
            OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0)
          END
        END
      ELSE
        load(x); load(y);
        IF x.type.form = ORB.Int THEN
          destR := RH - 2; Set16(TRUE, TRUE);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
          OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
          OCG.Gen(OCG.SBC, OCG.mDP, RegAddr(y.r), 0);
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(destR), 0)
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
    OCG.Gen(OCG.LDA, OCG.mImm, 0, 0);
    OCG.Gen(OCG.LDX, OCG.mDP, RegAddr(xr), 0);
    OCG.Gen(OCG.BEQ, OCG.mPCR, OCG.Here() + 2 + 11, 0);
    OCG.Gen(OCG.LSR, OCG.mDP, RegAddr(xr), 0);
    OCG.Gen(OCG.BCC, OCG.mPCR, OCG.Here() + 2 + 3, 0);
    OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.ADC, OCG.mDP, RegAddr(yr), 0);
    OCG.Gen(OCG.ASL, OCG.mDP, RegAddr(yr), 0);
    OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 - 15, 0)
  END mulLoop;

  PROCEDURE MulOp*(VAR x, y: Item);
    VAR e, loopTop: LONGINT;
  BEGIN
    IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a * y.a
    ELSIF (y.mode = ORB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN
      load(x); Set16(TRUE, TRUE);
      OCG.Gen(OCG.LDX, OCG.mImm, e, 0);
      loopTop := OCG.Here();
      OCG.Gen(OCG.ASL, OCG.mDP, RegAddr(x.r), 0);
      OCG.Gen(OCG.DEX, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.BNE, OCG.mPCR, loopTop, 0)
    ELSIF y.mode = ORB.Const THEN
      load(x); load(y); mulLoop(x.r, y.r);
      RH := RH - 1; x.r := RH - 1;
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0)
    ELSIF (x.mode = ORB.Const) & (x.a >= 2) & (log2(x.a, e) = 1) THEN
      load(y); Set16(TRUE, TRUE);
      OCG.Gen(OCG.LDX, OCG.mImm, e, 0);
      loopTop := OCG.Here();
      OCG.Gen(OCG.ASL, OCG.mDP, RegAddr(y.r), 0);
      OCG.Gen(OCG.DEX, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.BNE, OCG.mPCR, loopTop, 0);
      x.mode := Reg; x.r := y.r
    ELSE
      load(x); load(y); mulLoop(x.r, y.r);
      RH := RH - 1; x.r := RH - 1;
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0)
    END
  END MulOp;

  PROCEDURE genDivLoop(dividendReg, divisorReg, quotientReg: LONGINT);
    VAR loopTop: LONGINT;
  BEGIN
    Set16(TRUE, TRUE);
    OCG.Gen(OCG.LDA, OCG.mImm, 0, 0);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(quotientReg), 0);
    loopTop := OCG.Here();
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(dividendReg), 0);
    OCG.Gen(OCG.CMP, OCG.mDP, RegAddr(divisorReg), 0);
    OCG.Gen(OCG.BCC, OCG.mPCR, OCG.Here() + 2 + 11, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(dividendReg), 0);
    OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.SBC, OCG.mDP, RegAddr(divisorReg), 0);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(dividendReg), 0);
    OCG.Gen(OCG.INC, OCG.mDP, RegAddr(quotientReg), 0);
    OCG.Gen(OCG.BRA, OCG.mPCR, loopTop, 0)
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
          OCG.Gen(OCG.CMP, OCG.mImm, 8000H, 0);
          OCG.Gen(OCG.ROR, OCG.mImpl, 0, 0);
          i := i + 1
        END;
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0)
      ELSIF y.mode = ORB.Const THEN
        IF y.a > 0 THEN
          load(x); Set16(TRUE, TRUE);
          OCG.Gen(OCG.LDA, OCG.mImm, y.a, 0);
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
          divisorReg := RH; incR; quotientReg := RH; incR;
          genDivLoop(x.r, divisorReg, quotientReg);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(quotientReg), 0);
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0);
          RH := RH - 2
        ELSE ORS.Mark("bad divisor")
        END
      ELSE
        load(y);
        IF check THEN Trap(LE, 6) END;
        load(x);
        quotientReg := RH; incR;
        genDivLoop(x.r, y.r, quotientReg);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(quotientReg), 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(y.r), 0);
        x.r := y.r; RH := y.r + 1
      END
    ELSE (* mod *)
      IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
        IF y.a > 0 THEN x.a := x.a MOD y.a ELSE ORS.Mark("bad modulus") END
      ELSIF (y.mode = ORB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN
        load(x); Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
        OCG.Gen(OCG.AND, OCG.mImm, y.a - 1, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0)
      ELSIF y.mode = ORB.Const THEN
        IF y.a > 0 THEN
          load(x); Set16(TRUE, TRUE);
          OCG.Gen(OCG.LDA, OCG.mImm, y.a, 0);
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
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
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(y.r), 0);
        x.r := y.r; RH := y.r + 1
      END
    END
  END DivOp;

  PROCEDURE addFPFixup(idx: INTEGER);
  BEGIN
    IF fpFixupCount[idx] < maxFPFixups THEN
      fpFixups[idx, fpFixupCount[idx]] := OCG.Here() + 1;
      fpFixupCount[idx] := fpFixupCount[idx] + 1
    END
  END addFPFixup;

  PROCEDURE RealOp*(op: INTEGER; VAR x, y: Item);
  BEGIN
    load(x); load(y); Set16(TRUE, TRUE);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r + 1), 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_B_LO, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r + 1), 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_B_HI, 0);
    IF op = ORS.plus THEN
      addFPFixup(FP_ADD); OCG.Gen(OCG.JSR, OCG.mAbs, 0, 0)
    ELSIF op = ORS.minus THEN
      OCG.Gen(OCG.LDA, OCG.mDP, FP_B_HI, 0);
      OCG.Gen(OCG.EOR, OCG.mImm, 8000H, 0);
      OCG.Gen(OCG.STA, OCG.mDP, FP_B_HI, 0);
      addFPFixup(FP_ADD); OCG.Gen(OCG.JSR, OCG.mAbs, 0, 0)
    ELSIF op = ORS.times THEN
      addFPFixup(FP_MUL); OCG.Gen(OCG.JSR, OCG.mAbs, 0, 0)
    ELSIF op = ORS.rdiv THEN
      addFPFixup(FP_DIV); OCG.Gen(OCG.JSR, OCG.mAbs, 0, 0)
    END;
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r + 1), 0);
    RH := RH - 2; x.r := RH - 2
  END RealOp;

  (* --- sets --- *)
  PROCEDURE Singleton*(VAR x: Item);
    VAR skip, loopTop: LONGINT;
  BEGIN
    IF x.mode = ORB.Const THEN x.a := ASL(1, x.a)
    ELSE
      load(x); Set16(TRUE, TRUE);
      OCG.Gen(OCG.LDA, OCG.mImm, 1, 0);
      OCG.Gen(OCG.LDX, OCG.mDP, RegAddr(x.r), 0);
      skip := OCG.Here() + 2 + 4;
      OCG.Gen(OCG.BEQ, OCG.mPCR, skip, 0);
      loopTop := OCG.Here();
      OCG.Gen(OCG.ASL, OCG.mAcc, 0, 0);
      OCG.Gen(OCG.DEX, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.BNE, OCG.mPCR, loopTop, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0)
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
        OCG.Gen(OCG.LDA, OCG.mImm, Lo16(ASL(0FFFFH, x.a)), 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0)
      ELSE
        load(x); Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDA, OCG.mImm, 0FFFFH, 0);
        OCG.Gen(OCG.LDX, OCG.mDP, RegAddr(x.r), 0);
        skip := OCG.Here() + 2 + 4;
        OCG.Gen(OCG.BEQ, OCG.mPCR, skip, 0);
        loopTop := OCG.Here();
        OCG.Gen(OCG.ASL, OCG.mAcc, 0, 0);
        OCG.Gen(OCG.DEX, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.BNE, OCG.mPCR, loopTop, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0)
      END;
      IF (y.mode = ORB.Const) & (y.a < 15) THEN
        mask := Lo16(EOR(ASL(0FFFEH, y.a), 0FFFFH));
        Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDA, OCG.mImm, mask, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
        y.mode := Reg; y.r := RH; incR
      ELSE
        load(y); Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDA, OCG.mImm, 0FFFEH, 0);
        OCG.Gen(OCG.LDX, OCG.mDP, RegAddr(y.r), 0);
        skip := OCG.Here() + 2 + 4;
        OCG.Gen(OCG.BEQ, OCG.mPCR, skip, 0);
        loopTop := OCG.Here();
        OCG.Gen(OCG.ASL, OCG.mAcc, 0, 0);
        OCG.Gen(OCG.DEX, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.BNE, OCG.mPCR, loopTop, 0);
        OCG.Gen(OCG.EOR, OCG.mImm, 0FFFFH, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(y.r), 0)
      END;
      IF x.mode = ORB.Const THEN x.mode := Reg END;
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
      OCG.Gen(OCG.AND, OCG.mDP, RegAddr(y.r), 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0);
      RH := RH - 1; x.r := RH - 1
    END
  END Set;

  PROCEDURE In*(VAR x, y: Item);
    VAR skip, loopTop: LONGINT;
  BEGIN
    load(y); Set16(TRUE, TRUE);
    IF x.mode = ORB.Const THEN
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
      OCG.Gen(OCG.AND, OCG.mImm, Lo16(ASL(1, x.a)), 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(y.r), 0);
      RH := RH - 1
    ELSE
      load(x);
      OCG.Gen(OCG.LDA, OCG.mImm, 1, 0);
      OCG.Gen(OCG.LDX, OCG.mDP, RegAddr(x.r), 0);
      skip := OCG.Here() + 2 + 4;
      OCG.Gen(OCG.BEQ, OCG.mPCR, skip, 0);
      loopTop := OCG.Here();
      OCG.Gen(OCG.ASL, OCG.mAcc, 0, 0);
      OCG.Gen(OCG.DEX, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.BNE, OCG.mPCR, loopTop, 0);
      OCG.Gen(OCG.AND, OCG.mDP, RegAddr(y.r), 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(y.r), 0);
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
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
      IF op = ORS.plus THEN OCG.Gen(OCG.ORA, OCG.mImm, y.a, 0)
      ELSIF op = ORS.minus THEN OCG.Gen(OCG.AND, OCG.mImm, Lo16(EOR(y.a, 0FFFFH)), 0)
      ELSIF op = ORS.times THEN OCG.Gen(OCG.AND, OCG.mImm, y.a, 0)
      ELSIF op = ORS.rdiv THEN OCG.Gen(OCG.EOR, OCG.mImm, y.a, 0)
      END;
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0)
    ELSE
      load(x); load(y);
      IF op = ORS.plus THEN
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
        OCG.Gen(OCG.ORA, OCG.mDP, RegAddr(y.r), 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 2), 0)
      ELSIF op = ORS.minus THEN
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
        OCG.Gen(OCG.EOR, OCG.mImm, 0FFFFH, 0);
        OCG.Gen(OCG.AND, OCG.mDP, RegAddr(x.r), 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 2), 0)
      ELSIF op = ORS.times THEN
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
        OCG.Gen(OCG.AND, OCG.mDP, RegAddr(y.r), 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 2), 0)
      ELSIF op = ORS.rdiv THEN
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
        OCG.Gen(OCG.EOR, OCG.mDP, RegAddr(y.r), 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 2), 0)
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
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
        OCG.Gen(OCG.ORA, OCG.mDP, RegAddr(x.r + 1), 0);
        RH := RH - 2
      ELSE
        load(x); load(y);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
        OCG.Gen(OCG.CMP, OCG.mDP, RegAddr(y.r), 0);
        OCG.Gen(OCG.BNE, OCG.mPCR, OCG.Here() + 2 + 4, 0);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r + 1), 0);
        OCG.Gen(OCG.CMP, OCG.mDP, RegAddr(y.r + 1), 0);
        RH := RH - 4
      END
    ELSE
      IF use8 THEN Set8(TRUE, FALSE) END;
      signedCmp := useSigned & ((op = ORS.lss) OR (op = ORS.geq) OR (op = ORS.leq) OR (op = ORS.gtr));
      IF (y.mode = ORB.Const) & (y.type.form # ORB.Proc) THEN
        load(x);
        IF (y.a # 0) OR ((op # ORS.eql) & (op # ORS.neq)) THEN
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
          IF signedCmp THEN
            OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
            OCG.Gen(OCG.SBC, OCG.mImm, y.a, 0)
          ELSE
            OCG.Gen(OCG.CMP, OCG.mImm, y.a, 0)
          END
        END;
        RH := RH - 1
      ELSE
        IF (x.mode = Cond) OR (y.mode = Cond) THEN ORS.Mark("not implemented") END;
        load(x); load(y);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
        IF signedCmp THEN
          OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
          OCG.Gen(OCG.SBC, OCG.mDP, RegAddr(y.r), 0)
        ELSE
          OCG.Gen(OCG.CMP, OCG.mDP, RegAddr(y.r), 0)
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
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r + 1), 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_HI, 0);
    IF (y.mode = ORB.Const) & (y.a = 0) THEN
      OCG.Gen(OCG.STZ, OCG.mDP, FP_B_LO, 0);
      OCG.Gen(OCG.STZ, OCG.mDP, FP_B_HI, 0);
      RH := RH - 2
    ELSE
      load(y);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
      OCG.Gen(OCG.STA, OCG.mDP, FP_B_LO, 0);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r + 1), 0);
      OCG.Gen(OCG.STA, OCG.mDP, FP_B_HI, 0);
      RH := RH - 4
    END;
    addFPFixup(FP_CMP); OCG.Gen(OCG.JSR, OCG.mAbs, 0, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_LO, 0);
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
  BEGIN x.type := ORB.charType; x.a := str[x.a]
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
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
          OCG.Gen(OCG.STA, OCG.mSR, x.a + frame, 0);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r + 1), 0);
          OCG.Gen(OCG.STA, OCG.mSR, x.a + 2 + frame, 0);
          RH := RH - 1
        ELSIF (x.type.size = 1) & (y.type.size >= 1) THEN
          Set8(TRUE, FALSE);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
          OCG.Gen(OCG.STA, OCG.mSR, x.a + frame, 0);
          Set16(TRUE, FALSE)
        ELSE
          Set16(TRUE, FALSE);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
          OCG.Gen(OCG.STA, OCG.mSR, x.a + frame, 0);
          Set16(TRUE, FALSE)
        END
      ELSE
        sb := GetSB(x.r);
        IF (x.type.form = ORB.Pointer) OR (x.type.form = ORB.NilTyp)
           OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) THEN
          Set16(TRUE, TRUE);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
          OCG.Gen(OCG.LDY, OCG.mImm, x.a, 0);
          OCG.Gen(OCG.STA, OCG.mDPIndY, sb, 0);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r + 1), 0);
          OCG.Gen(OCG.LDY, OCG.mImm, x.a + 2, 0);
          OCG.Gen(OCG.STA, OCG.mDPIndY, sb, 0);
          RH := RH - 1
        ELSIF (x.type.size = 1) & (y.type.size >= 1) THEN
          Set8(TRUE, FALSE);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
          OCG.Gen(OCG.LDY, OCG.mImm, x.a, 0);
          OCG.Gen(OCG.STA, OCG.mDPIndY, sb, 0);
          Set16(TRUE, FALSE)
        ELSE
          Set16(TRUE, TRUE);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
          OCG.Gen(OCG.LDY, OCG.mImm, x.a, 0);
          OCG.Gen(OCG.STA, OCG.mDPIndY, sb, 0)
        END
      END
    ELSIF x.mode = ORB.Par THEN
      Set16(TRUE, TRUE);
      OCG.Gen(OCG.LDA, OCG.mSR, x.a + frame, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
      OCG.Gen(OCG.LDA, OCG.mSR, x.a + 2 + frame, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 1), 0);
      IF (x.type.form = ORB.Pointer) OR (x.type.form = ORB.NilTyp)
         OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) THEN
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
        OCG.Gen(OCG.LDY, OCG.mImm, x.b, 0);
        OCG.Gen(OCG.STA, OCG.mDPIndLY, RegAddr(RH), 0);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r + 1), 0);
        OCG.Gen(OCG.LDY, OCG.mImm, x.b + 2, 0);
        OCG.Gen(OCG.STA, OCG.mDPIndLY, RegAddr(RH), 0);
        RH := RH - 1
      ELSIF x.type.size = 1 THEN
        Set8(TRUE, FALSE);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
        IF x.b # 0 THEN
          OCG.Gen(OCG.LDY, OCG.mImm, x.b, 0);
          OCG.Gen(OCG.STA, OCG.mDPIndLY, RegAddr(RH), 0)
        ELSE OCG.Gen(OCG.STA, OCG.mDPIndL, RegAddr(RH), 0)
        END;
        Set16(TRUE, FALSE)
      ELSE
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
        IF x.b # 0 THEN
          OCG.Gen(OCG.LDY, OCG.mImm, x.b, 0);
          OCG.Gen(OCG.STA, OCG.mDPIndLY, RegAddr(RH), 0)
        ELSE OCG.Gen(OCG.STA, OCG.mDPIndL, RegAddr(RH), 0)
        END
      END
    ELSIF x.mode = RegI THEN
      IF (x.type.form = ORB.Pointer) OR (x.type.form = ORB.NilTyp)
         OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) THEN
        Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
        IF x.a = 0 THEN OCG.Gen(OCG.STA, OCG.mDPIndL, RegAddr(x.r), 0)
        ELSE
          OCG.Gen(OCG.LDY, OCG.mImm, x.a, 0);
          OCG.Gen(OCG.STA, OCG.mDPIndLY, RegAddr(x.r), 0)
        END;
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r + 1), 0);
        OCG.Gen(OCG.LDY, OCG.mImm, x.a + 2, 0);
        OCG.Gen(OCG.STA, OCG.mDPIndLY, RegAddr(x.r), 0);
        RH := RH - 1
      ELSIF x.type.size = 1 THEN
        Set8(TRUE, FALSE);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
        IF x.a = 0 THEN OCG.Gen(OCG.STA, OCG.mDPIndL, RegAddr(x.r), 0)
        ELSE
          OCG.Gen(OCG.LDY, OCG.mImm, x.a, 0);
          OCG.Gen(OCG.STA, OCG.mDPIndLY, RegAddr(x.r), 0)
        END;
        Set16(TRUE, FALSE)
      ELSE
        Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
        IF x.a = 0 THEN OCG.Gen(OCG.STA, OCG.mDPIndL, RegAddr(x.r), 0)
        ELSE
          OCG.Gen(OCG.LDY, OCG.mImm, x.a, 0);
          OCG.Gen(OCG.STA, OCG.mDPIndLY, RegAddr(x.r), 0)
        END
      END;
      RH := RH - 2
    ELSE ORS.Mark("bad mode in Store")
    END;
    RH := RH - 1
  END Store;

  PROCEDURE StoreStruct*(VAR x, y: Item);
    VAR s, wordCount, dstReg, srcReg, loopTop: LONGINT; valid: BOOLEAN;
  BEGIN
    IF y.type.size # 0 THEN
      loadAdr(x); loadAdr(y);
      dstReg := RegAddr(x.r); srcReg := RegAddr(y.r);
      valid := TRUE; s := 0;
      IF (x.type.form = ORB.Array) & (x.type.len > 0) THEN
        IF y.type.len >= 0 THEN
          IF x.type.size = y.type.size THEN s := y.type.size
          ELSE ORS.Mark("different length/size, not implemented"); valid := FALSE
          END
        ELSE ORS.Mark("open array assignment not implemented"); valid := FALSE
        END
      ELSIF x.type.form = ORB.Record THEN s := x.type.size
      ELSE ORS.Mark("inadmissible assignment"); valid := FALSE
      END;
      IF valid THEN
        wordCount := (s + 1) DIV 2; Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDY, OCG.mImm, 0, 0);
        OCG.Gen(OCG.LDX, OCG.mImm, wordCount, 0);
        loopTop := OCG.Here();
        OCG.Gen(OCG.LDA, OCG.mDPIndY, srcReg, 0);
        OCG.Gen(OCG.STA, OCG.mDPIndY, dstReg, 0);
        OCG.Gen(OCG.INY, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.INY, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.DEX, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.BNE, OCG.mPCR, loopTop, 0)
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
    OCG.Gen(OCG.LDY, OCG.mImm, 0, 0);
    loopStart := OCG.Here();
    OCG.Gen(OCG.LDA, OCG.mDPIndY, RegAddr(y.r), 0);
    OCG.Gen(OCG.STA, OCG.mDPIndY, RegAddr(x.r), 0);
    OCG.Gen(OCG.BEQ, OCG.mPCR, OCG.Here() + 2 + 3, 0);
    OCG.Gen(OCG.INY, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.BRA, OCG.mPCR, loopStart, 0);
    RH := RH - 3
  END CopyString;

  (* --- parameters --- *)
  PROCEDURE OpenArrayParam*(VAR x: Item);
  BEGIN
    loadAdr(x);
    IF x.type.len >= 0 THEN
      Set16(TRUE, TRUE);
      OCG.Gen(OCG.LDA, OCG.mImm, x.type.len, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r + 2), 0)
    ELSE
      Set16(TRUE, TRUE);
      OCG.Gen(OCG.LDA, OCG.mSR, x.a + 2 + frame, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r + 2), 0)
    END;
    incR
  END OpenArrayParam;

  PROCEDURE VarParam*(VAR x: Item; ftype: ORB.Type);
    VAR xmd, sb: LONGINT;
  BEGIN
    xmd := x.mode;
    IF (x.mode = ORB.Var) & (x.r > 0) THEN
      Set16(TRUE, TRUE);
      OCG.Gen(OCG.TSC, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.ADC, OCG.mImm, x.a + frame, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
      x.r := RH; x.mode := Reg; incR;
      OCG.Gen(OCG.LDA, OCG.mImm, 0, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
      incR
    ELSIF (x.mode = ORB.Var) & (x.r <= 0) THEN
      sb := GetSB(x.r);
      Set16(TRUE, TRUE);
      OCG.Gen(OCG.LDA, OCG.mDP, sb, 0);
      IF x.a # 0 THEN
        OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.ADC, OCG.mImm, x.a, 0)
      END;
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
      OCG.Gen(OCG.LDA, OCG.mImm, 0, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 1), 0);
      x.r := RH; x.mode := Reg; incR; incR
    ELSE loadAdr(x)
    END;
    IF (ftype.form = ORB.Array) & (ftype.len < 0) THEN
      IF x.type.len >= 0 THEN
        Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDA, OCG.mImm, x.type.len, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r + 2), 0)
      ELSE
        Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDA, OCG.mSR, x.a + 4 + frame, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r + 2), 0)
      END;
      incR
    ELSIF ftype.form = ORB.Record THEN
      Set16(TRUE, TRUE);
      IF xmd = ORB.Par THEN
        OCG.Gen(OCG.LDA, OCG.mSR, x.a + 4 + frame, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r + 2), 0);
        OCG.Gen(OCG.LDA, OCG.mSR, x.a + 6 + frame, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r + 3), 0)
      ELSE
        sb := GetSB(-x.type.mno);
        OCG.Gen(OCG.LDA, OCG.mDP, sb, 0);
        OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
        emitTDLen(x.type);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r + 2), 0);
        OCG.Gen(OCG.STZ, OCG.mDP, RegAddr(x.r + 3), 0)
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
    OCG.Gen(OCG.LDA, OCG.mDP, SB_DP, 0);
    OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.ADC, OCG.mImm, varsize + x.a, 0);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
    OCG.Gen(OCG.STZ, OCG.mDP, RegAddr(RH + 1), 0);
    x.mode := Reg; x.r := RH; incR; incR;
    Set16(TRUE, TRUE);
    OCG.Gen(OCG.LDA, OCG.mImm, x.b, 0);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
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
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
        OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.SBC, OCG.mImm, z.a, 0)
      ELSE OCG.Gen(OCG.CMP, OCG.mImm, z.a, 0)
      END
    ELSE
      load(y); load(z);
      IF (y.type.size = 1) & (z.type.size = 1) THEN Set8(TRUE, FALSE)
      ELSE Set16(TRUE, TRUE) END;
      IF useSigned THEN
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
        OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.SBC, OCG.mDP, RegAddr(z.r), 0)
      ELSE
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
        OCG.Gen(OCG.CMP, OCG.mDP, RegAddr(z.r), 0)
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
        OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.ADC, OCG.mImm, w.a, 0)
      ELSE
        OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.SBC, OCG.mImm, -w.a, 0)
      END
    ELSE
      load(w);
      OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.ADC, OCG.mDP, RegAddr(w.r), 0);
      RH := RH - 1
    END;
    IF x.mode = ORB.Var THEN
      OCG.Gen(OCG.LDY, OCG.mImm, x.a, 0);
      OCG.Gen(OCG.STA, OCG.mDPIndY, SB_DP, 0)
    ELSE OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0)
    END;
    RH := RH - 1
  END For2;

  (* --- CASE --- *)
  PROCEDURE CaseLabel*(VAR x: Item; val: LONGINT; VAR chain: LONGINT);
  BEGIN
    load(x); Set16(TRUE, TRUE);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
    OCG.Gen(OCG.CMP, OCG.mImm, val, 0);
    RH := RH - 1;
    OCG.Gen(OCG.BNE, OCG.mPCR, OCG.Here() + 2 + 3, 0);
    OCG.Gen(OCG.BRL, OCG.mFix, chain, 0);
    chain := OCG.Here() - 2
  END CaseLabel;

  PROCEDURE CaseRange*(VAR x: Item; lo, hi: LONGINT; VAR chain: LONGINT);
  BEGIN
    load(x); Set16(TRUE, TRUE);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
    RH := RH - 1;
    OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.SBC, OCG.mImm, lo, 0);
    OCG.Gen(OCG.CMP, OCG.mImm, hi - lo + 1, 0);
    OCG.Gen(OCG.BCS, OCG.mPCR, OCG.Here() + 2 + 3, 0);
    OCG.Gen(OCG.BRL, OCG.mFix, chain, 0);
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
  BEGIN OCG.Gen(OCG.BRA, OCG.mPCR, L, 0)
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
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(ri), 0);
      OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
      ri := ri + 1
    UNTIL ri >= r
  END SaveRegs;

  PROCEDURE RestoreRegs(r: LONGINT);
    VAR ri: LONGINT;
  BEGIN
    ri := r; Set16(TRUE, TRUE);
    REPEAT
      ri := ri - 1;
      OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(ri), 0)
    UNTIL ri <= 0;
    frame := frame - 2 * r
  END RestoreRegs;

  PROCEDURE PrepCall*(VAR x: Item; VAR r: LONGINT);
    VAR rcv: Item;
  BEGIN
    IF x.isMeth & ((x.rcvMode = Reg) OR (x.rcvMode = RegI)) THEN
      (* receiver already in registers [rcvR, rcvR+1] — a DeRef'd pointer
         (dynamic dispatch / SUPER) or a freshly-allocated instance (a
         constructor). Save the outer context below it, keep the receiver,
         and move it to R0/R1 as param 0; scratch/args then sit above it. *)
      r := x.rcvR;
      IF x.rcvR > 0 THEN SaveRegs(x.rcvR) END;
      IF x.rcvR # 0 THEN
        Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.rcvR), 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(0), 0);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.rcvR + 1), 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(1), 0)
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
    IF x.dynDisp THEN
      (* dynamic dispatch: receiver (object pointer) is param 0 in R0/R1.
         tag := [obj-4]; addr := [tag + VtableOff + slot*2] — the loader has
         already filled that slot with the method's absolute in-bank address,
         so no code base is added. All modules share one bank, so the call
         bank is the current program bank (PHK). Scratch above RH. *)
      addrReg := RegAddr(RH);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(0), 0);
      OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.SBC, OCG.mImm, 4, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 2), 0);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(1), 0);
      OCG.Gen(OCG.SBC, OCG.mImm, 0, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 3), 0);
      OCG.Gen(OCG.LDA, OCG.mDPIndL, RegAddr(RH + 2), 0);   (* TD addr lo *)
      OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.ADC, OCG.mImm, VtableOff + x.methSlot * 2, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 4), 0);
      OCG.Gen(OCG.LDY, OCG.mImm, 2, 0);
      OCG.Gen(OCG.LDA, OCG.mDPIndLY, RegAddr(RH + 2), 0);  (* TD bank *)
      OCG.Gen(OCG.ADC, OCG.mImm, 0, 0);                    (* carry from lo add *)
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH + 5), 0);
      OCG.Gen(OCG.LDA, OCG.mDPIndL, RegAddr(RH + 4), 0);   (* method address *)
      OCG.Gen(OCG.STA, OCG.mDP, addrReg, 0);
      OCG.Gen(OCG.PHK, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.PER, OCG.mImm, 09H, 0);
      Set8(TRUE, FALSE);
      OCG.Gen(OCG.PHK, OCG.mImpl, 0, 0);
      Set16(TRUE, FALSE);
      OCG.Gen(OCG.LDA, OCG.mDP, addrReg, 0);
      OCG.Gen(OCG.DEC, OCG.mAcc, 0, 0);
      OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.RTL, OCG.mImpl, 0, 0)
    ELSIF x.mode = ORB.Const THEN
      IF x.r < 0 THEN
        mno := -x.r; exno := x.a;
        encoded := mno * 10000H + (exno MOD 10000H);
        OCG.Gen(OCG.JSL, OCG.mAbsL, encoded, 0)
      ELSIF x.b = 1 THEN
        OCG.Gen(OCG.JSL, OCG.mAbsL, x.a, 0)
      ELSE
        OCG.Gen(OCG.JSR, OCG.mAbs, x.a, 0)
      END
    ELSE
      IF x.mode <= ORB.Par THEN
        load(x);
        addrReg := RegAddr(RH - 2); bankReg := RegAddr(RH - 1);
        IF check THEN
          OCG.Gen(OCG.LDA, OCG.mDP, addrReg, 0);
          OCG.Gen(OCG.ORA, OCG.mDP, bankReg, 0);
          Trap(NE, 5)
        END;
        OCG.Gen(OCG.PHK, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.PER, OCG.mImm, 0BH, 0);
        Set8(TRUE, FALSE);
        OCG.Gen(OCG.LDA, OCG.mDP, bankReg, 0);
        OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
        Set16(TRUE, FALSE);
        OCG.Gen(OCG.LDA, OCG.mDP, addrReg, 0);
        OCG.Gen(OCG.DEC, OCG.mAcc, 0, 0);
        OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.RTL, OCG.mImpl, 0, 0);
        RH := RH - 2
      ELSE
        OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(1), 0);
        OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(0), 0);
        addrReg := RegAddr(0); bankReg := RegAddr(1);
        r := r - 2; frame := frame - 4;
        IF check THEN
          OCG.Gen(OCG.LDA, OCG.mDP, addrReg, 0);
          OCG.Gen(OCG.ORA, OCG.mDP, bankReg, 0);
          Trap(NE, 5)
        END;
        OCG.Gen(OCG.PHK, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.PER, OCG.mImm, 0BH, 0);
        Set8(TRUE, FALSE);
        OCG.Gen(OCG.LDA, OCG.mDP, bankReg, 0);
        OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
        Set16(TRUE, FALSE);
        OCG.Gen(OCG.LDA, OCG.mDP, addrReg, 0);
        OCG.Gen(OCG.DEC, OCG.mAcc, 0, 0);
        OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.RTL, OCG.mImpl, 0, 0)
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
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(0), 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(r), 0);
        IF wide THEN
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(1), 0);
          OCG.Gen(OCG.STA, OCG.mDP, RegAddr(r + 1), 0)
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
        OCG.Gen(OCG.LDA, OCG.mDP, SB_DP, 0);
        OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.LDA, OCG.mDP, BANK_DP, 0);
        OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
        OCG.AddRel(OCG.Here());
        OCG.Gen(OCG.LDA, OCG.mImm, 0, 0);
        OCG.Gen(OCG.STA, OCG.mDP, SB_DP, 0);
        OCG.AddRel(OCG.Here() + 80000000H);
        OCG.Gen(OCG.LDA, OCG.mImm, 0, 0);
        OCG.Gen(OCG.STA, OCG.mDP, BANK_DP, 0)
      END;
      IF frameSize > 0 THEN
        OCG.Gen(OCG.TSC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.SBC, OCG.mImm, frameSize, 0);
        OCG.Gen(OCG.TCS, OCG.mImpl, 0, 0)
      END;
      r := 0; param := params; Set16(TRUE, TRUE);
      WHILE (param # NIL) & ((param.class = ORB.Var) OR (param.class = ORB.Par)) DO
        IF (param.class = ORB.Par) & (param.type.form = ORB.Array) & (param.type.len < 0) THEN
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(r), 0);
          OCG.Gen(OCG.STA, OCG.mSR, param.val, 0);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(r + 1), 0);
          OCG.Gen(OCG.STA, OCG.mSR, param.val + 2, 0);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(r + 2), 0);
          OCG.Gen(OCG.STA, OCG.mSR, param.val + 4, 0)
        ELSIF (param.class = ORB.Par) & (param.type.form = ORB.Record) THEN
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(r), 0);
          OCG.Gen(OCG.STA, OCG.mSR, param.val, 0);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(r + 1), 0);
          OCG.Gen(OCG.STA, OCG.mSR, param.val + 2, 0);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(r + 2), 0);
          OCG.Gen(OCG.STA, OCG.mSR, param.val + 4, 0);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(r + 3), 0);
          OCG.Gen(OCG.STA, OCG.mSR, param.val + 6, 0)
        ELSIF param.class = ORB.Par THEN
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(r), 0);
          OCG.Gen(OCG.STA, OCG.mSR, param.val, 0);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(r + 1), 0);
          OCG.Gen(OCG.STA, OCG.mSR, param.val + 2, 0)
        ELSIF (param.type.form = ORB.Real) OR (param.type.form = ORB.Proc) THEN
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(r), 0);
          OCG.Gen(OCG.STA, OCG.mSR, param.val, 0);
          OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(r + 1), 0);
          OCG.Gen(OCG.STA, OCG.mSR, param.val + 2, 0)
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
        ELSIF param.type.size <= 2 THEN r := r + 1
        ELSE r := r + 2
        END;
        param := param.next
      END;
      RH := 0
    ELSE
      IF frameSize > 0 THEN
        OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.SBC, OCG.mImm, frameSize, 0);
        OCG.Gen(OCG.TCS, OCG.mImpl, 0, 0)
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
        OCG.Gen(OCG.TSC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.ADC, OCG.mImm, size, 0);
        OCG.Gen(OCG.TCS, OCG.mImpl, 0, 0)
      END;
      IF curExpo THEN
        OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.STA, OCG.mDP, BANK_DP, 0);
        OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.STA, OCG.mDP, SB_DP, 0);
        OCG.Gen(OCG.RTL, OCG.mImpl, 0, 0)
      ELSE OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0)
      END
    ELSE
      IF size > 0 THEN
        OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.ADC, OCG.mImm, size, 0);
        OCG.Gen(OCG.TCS, OCG.mImpl, 0, 0)
      END;
      OCG.Gen(OCG.RTI, OCG.mImpl, 0, 0)
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
      OCG.Gen(OCG.LDA, OCG.mSR, x.a + frame, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(zr), 0);
      incR;
      IF y.mode = ORB.Const THEN
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(zr), 0);
        IF useIncDec THEN
          IF isInc THEN OCG.Gen(OCG.INC, OCG.mAcc, 0, 0) ELSE OCG.Gen(OCG.DEC, OCG.mAcc, 0, 0) END
        ELSIF isInc THEN
          OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0); OCG.Gen(OCG.ADC, OCG.mImm, y.a, 0)
        ELSE
          OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0); OCG.Gen(OCG.SBC, OCG.mImm, y.a, 0)
        END;
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(zr), 0)
      ELSE
        load(y);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(zr), 0);
        IF isInc THEN
          OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0); OCG.Gen(OCG.ADC, OCG.mDP, RegAddr(y.r), 0)
        ELSE
          OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0); OCG.Gen(OCG.SBC, OCG.mDP, RegAddr(y.r), 0)
        END;
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(zr), 0); RH := RH - 1
      END;
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(zr), 0);
      OCG.Gen(OCG.STA, OCG.mSR, x.a + frame, 0);
      IF isByte THEN Set16(TRUE, TRUE) END;
      RH := RH - 1
    ELSE
      loadAdr(x); zr := RH;
      IF isByte THEN Set8(TRUE, FALSE) ELSE Set16(TRUE, TRUE) END;
      OCG.Gen(OCG.LDX, OCG.mDP, RegAddr(x.r), 0);
      OCG.Gen(OCG.LDA, OCG.mAbsX, 0, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(zr), 0);
      incR;
      IF y.mode = ORB.Const THEN
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(zr), 0);
        IF useIncDec THEN
          IF isInc THEN OCG.Gen(OCG.INC, OCG.mAcc, 0, 0) ELSE OCG.Gen(OCG.DEC, OCG.mAcc, 0, 0) END
        ELSIF isInc THEN
          OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0); OCG.Gen(OCG.ADC, OCG.mImm, y.a, 0)
        ELSE
          OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0); OCG.Gen(OCG.SBC, OCG.mImm, y.a, 0)
        END;
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(zr), 0)
      ELSE
        load(y);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(zr), 0);
        IF isInc THEN
          OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0); OCG.Gen(OCG.ADC, OCG.mDP, RegAddr(y.r), 0)
        ELSE
          OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0); OCG.Gen(OCG.SBC, OCG.mDP, RegAddr(y.r), 0)
        END;
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(zr), 0); RH := RH - 1
      END;
      OCG.Gen(OCG.LDX, OCG.mDP, RegAddr(x.r), 0);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(zr), 0);
      OCG.Gen(OCG.STA, OCG.mAbsX, 0, 0);
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
      OCG.Gen(OCG.LDA, OCG.mSR, x.a + frame, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(zr), 0);
      incR;
      IF y.mode = ORB.Const THEN
        mask := Lo16(ASL(1, y.a));
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(zr), 0);
        IF inorex = 0 THEN OCG.Gen(OCG.ORA, OCG.mImm, mask, 0)
        ELSE OCG.Gen(OCG.AND, OCG.mImm, Lo16(EOR(mask, 0FFFFH)), 0)
        END;
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(zr), 0)
      ELSE
        load(y);
        OCG.Gen(OCG.LDA, OCG.mImm, 1, 0);
        OCG.Gen(OCG.LDX, OCG.mDP, RegAddr(y.r), 0);
        skip := OCG.Here() + 2 + 4;
        OCG.Gen(OCG.BEQ, OCG.mPCR, skip, 0);
        loopTop := OCG.Here();
        OCG.Gen(OCG.ASL, OCG.mAcc, 0, 0);
        OCG.Gen(OCG.DEX, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.BNE, OCG.mPCR, loopTop, 0);
        IF inorex = 0 THEN OCG.Gen(OCG.ORA, OCG.mDP, RegAddr(zr), 0)
        ELSE
          OCG.Gen(OCG.EOR, OCG.mImm, 0FFFFH, 0);
          OCG.Gen(OCG.AND, OCG.mDP, RegAddr(zr), 0)
        END;
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(zr), 0); RH := RH - 1
      END;
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(zr), 0);
      OCG.Gen(OCG.STA, OCG.mSR, orig.a + frame, 0);
      RH := RH - 1
    ELSE
      loadAdr(x); zr := RH; Set16(TRUE, TRUE);
      OCG.Gen(OCG.LDX, OCG.mDP, RegAddr(x.r), 0);
      OCG.Gen(OCG.LDA, OCG.mAbsX, 0, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(zr), 0);
      incR;
      IF y.mode = ORB.Const THEN
        mask := Lo16(ASL(1, y.a));
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(zr), 0);
        IF inorex = 0 THEN OCG.Gen(OCG.ORA, OCG.mImm, mask, 0)
        ELSE OCG.Gen(OCG.AND, OCG.mImm, Lo16(EOR(mask, 0FFFFH)), 0)
        END;
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(zr), 0)
      ELSE
        load(y);
        OCG.Gen(OCG.LDA, OCG.mImm, 1, 0);
        OCG.Gen(OCG.LDX, OCG.mDP, RegAddr(y.r), 0);
        skip := OCG.Here() + 2 + 4;
        OCG.Gen(OCG.BEQ, OCG.mPCR, skip, 0);
        loopTop := OCG.Here();
        OCG.Gen(OCG.ASL, OCG.mAcc, 0, 0);
        OCG.Gen(OCG.DEX, OCG.mImpl, 0, 0);
        OCG.Gen(OCG.BNE, OCG.mPCR, loopTop, 0);
        IF inorex = 0 THEN OCG.Gen(OCG.ORA, OCG.mDP, RegAddr(zr), 0)
        ELSE
          OCG.Gen(OCG.EOR, OCG.mImm, 0FFFFH, 0);
          OCG.Gen(OCG.AND, OCG.mDP, RegAddr(zr), 0)
        END;
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(zr), 0); RH := RH - 1
      END;
      OCG.Gen(OCG.LDX, OCG.mDP, RegAddr(x.r), 0);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(zr), 0);
      OCG.Gen(OCG.STA, OCG.mAbsX, 0, 0);
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
    OCG.Gen(OCG.LDA, OCG.mDP, sb, 0);
    OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
    emitTDLen(baseType);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
    OCG.Gen(OCG.STZ, OCG.mDP, RegAddr(RH + 1), 0);
    incR; incR;
    OCG.Gen(OCG.LDA, OCG.mImm, baseType.size + 4, 0);
    OCG.Gen(OCG.BRK, OCG.mImm, 10, 0);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
    OCG.Gen(OCG.STX, OCG.mDP, RegAddr(RH + 1), 0);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(RH - 2), 0);
    OCG.Gen(OCG.STA, OCG.mDPIndL, RegAddr(RH), 0);
    OCG.Gen(OCG.LDY, OCG.mImm, 2, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(RH - 1), 0);
    OCG.Gen(OCG.STA, OCG.mDPIndLY, RegAddr(RH), 0);
    OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(RH), 0);
    OCG.Gen(OCG.ADC, OCG.mImm, 4, 0);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
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
    OCG.Gen(OCG.LDY, OCG.mImm, 0, 0);
    loopTop := OCG.Here();
    OCG.Gen(OCG.LDA, OCG.mDPIndY, RegAddr(x.r), 0);
    OCG.Gen(OCG.STA, OCG.mDPIndY, RegAddr(y.r), 0);
    OCG.Gen(OCG.INY, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.INY, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(z.r), 0);
    OCG.Gen(OCG.DEC, OCG.mAcc, 0, 0);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(z.r), 0);
    OCG.Gen(OCG.BNE, OCG.mPCR, loopTop, 0);
    RH := RH - 3
  END Copy;

  PROCEDURE TRB*(VAR x, y: Item);
  BEGIN
    IF x.mode = ORB.Const THEN
      load(y); Set16(TRUE, TRUE);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
      OCG.Gen(OCG.TRB, OCG.mAbs, x.a, 0);
      RH := RH - 1
    ELSE
      load(x); load(y); Set16(TRUE, TRUE);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
      OCG.Gen(OCG.EOR, OCG.mImm, 0FFFFH, 0);
      OCG.Gen(OCG.AND, OCG.mDPInd, RegAddr(x.r), 0);
      OCG.Gen(OCG.STA, OCG.mDPInd, RegAddr(x.r), 0);
      RH := RH - 2
    END
  END TRB;

  PROCEDURE TSB*(VAR x, y: Item);
  BEGIN
    IF x.mode = ORB.Const THEN
      load(y); Set16(TRUE, TRUE);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
      OCG.Gen(OCG.TSB, OCG.mAbs, x.a, 0);
      RH := RH - 1
    ELSE
      load(x); load(y); Set16(TRUE, TRUE);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
      OCG.Gen(OCG.ORA, OCG.mDPInd, RegAddr(x.r), 0);
      OCG.Gen(OCG.STA, OCG.mDPInd, RegAddr(x.r), 0);
      RH := RH - 2
    END
  END TSB;

  PROCEDURE Exec*(VAR addr, bank: Item);
    VAR addrReg, bankReg: LONGINT;
  BEGIN
    load(addr); load(bank);
    addrReg := RegAddr(addr.r); bankReg := RegAddr(bank.r);
    OCG.Gen(OCG.LDA, OCG.mDP, SB_DP, 0);
    OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, BANK_DP, 0);
    OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.PHK, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.PER, OCG.mImm, 0BH, 0);
    Set8(TRUE, FALSE);
    OCG.Gen(OCG.LDA, OCG.mDP, bankReg, 0);
    OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
    Set16(TRUE, FALSE);
    OCG.Gen(OCG.LDA, OCG.mDP, addrReg, 0);
    OCG.Gen(OCG.DEC, OCG.mAcc, 0, 0);
    OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.RTL, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.STA, OCG.mDP, BANK_DP, 0);
    OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.STA, OCG.mDP, SB_DP, 0);
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
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r + 1), 0);
        OCG.Gen(OCG.AND, OCG.mImm, 7FFFH, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r + 1), 0)
      ELSE
        Set16(TRUE, TRUE);
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
        OCG.Gen(OCG.BPL, OCG.mPCR, OCG.Here() + 2 + 6, 0);
        OCG.Gen(OCG.EOR, OCG.mImm, 0FFFFH, 0);
        OCG.Gen(OCG.INC, OCG.mAcc, 0, 0);
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0)
      END
    END
  END Abs;

  PROCEDURE Odd*(VAR x: Item);
  BEGIN
    load(x); Set16(TRUE, TRUE);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
    OCG.Gen(OCG.AND, OCG.mImm, 1, 0);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0);
    SetCC(x, NE); RH := RH - 1
  END Odd;

  PROCEDURE Floor*(VAR x: Item);
  BEGIN
    load(x); Set16(TRUE, TRUE);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r + 1), 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_HI, 0);
    addFPFixup(FP_FLOOR); OCG.Gen(OCG.JSR, OCG.mAbs, 0, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0);
    RH := RH - 1; x.type := ORB.intType
  END Floor;

  PROCEDURE Float*(VAR x: Item);
  BEGIN
    load(x); Set16(TRUE, TRUE);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.STZ, OCG.mDP, FP_A_HI, 0);
    addFPFixup(FP_FLT); OCG.Gen(OCG.JSR, OCG.mAbs, 0, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_HI, 0);
    incR;
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r + 1), 0);
    x.type := ORB.realType
  END Float;

  PROCEDURE Ord*(VAR x: Item);
  BEGIN
    IF (x.mode = ORB.Var) OR (x.mode = ORB.Par) OR (x.mode = RegI) OR (x.mode = Cond) THEN
      load(x)
    END
  END Ord;

  PROCEDURE Len*(VAR x: Item);
  BEGIN
    IF x.type.len >= 0 THEN
      IF x.mode = RegI THEN RH := RH - 1 END;
      x.mode := ORB.Const; x.a := x.type.len
    ELSE
      Set16(TRUE, TRUE);
      OCG.Gen(OCG.LDA, OCG.mSR, x.a + 4 + frame, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
      x.mode := Reg; x.r := RH; incR
    END
  END Len;

  PROCEDURE Shift*(fct: LONGINT; VAR x, y: Item);
    VAR op, i: LONGINT;
  BEGIN
    load(x);
    IF fct = 0 THEN op := OCG.ASL
    ELSIF fct = 1 THEN op := OCG.LSR
    ELSE op := OCG.ROL
    END;
    IF y.mode = ORB.Const THEN
      IF y.a = 1 THEN OCG.Gen(op, OCG.mDP, RegAddr(x.r), 0)
      ELSE
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
        i := 0;
        WHILE i < y.a DO OCG.Gen(op, OCG.mImpl, 0, 0); i := i + 1 END;
        OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0)
      END
    ELSE ORS.Mark("non-const shift not implemented")
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
      OCG.Gen(OCG.LDA, OCG.mImm, Lo16(y.a), 0);
      OCG.Gen(op, OCG.mDP, RegAddr(x.r), 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0)
    ELSE
      load(y);
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(y.r), 0);
      OCG.Gen(op, OCG.mDP, RegAddr(x.r), 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH - 2), 0);
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
    OCG.Gen(OCG.STZ, OCG.mDP, RegAddr(RH), 0);
    incR;
    x.mode := RegI; x.a := 0; x.type := ORB.intType;
    load(x);
    Set16(TRUE, TRUE);
    IF y.mode = ORB.Const THEN
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
      OCG.Gen(OCG.AND, OCG.mImm, ASL(1, y.a), 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0);
      RH := RH - 1
    ELSE
      load(y);
      OCG.Gen(OCG.LDA, OCG.mImm, 1, 0);
      OCG.Gen(OCG.LDX, OCG.mDP, RegAddr(y.r), 0);
      OCG.Gen(OCG.BEQ, OCG.mPCR, OCG.Here() + 2 + 4, 0);
      loopTop := OCG.Here();
      OCG.Gen(OCG.ASL, OCG.mAcc, 0, 0);
      OCG.Gen(OCG.DEX, OCG.mImpl, 0, 0);
      OCG.Gen(OCG.BNE, OCG.mPCR, loopTop, 0);
      OCG.Gen(OCG.AND, OCG.mDP, RegAddr(x.r), 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0);
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
      OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r + 1), 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(x.r), 0);
      RH := RH - 1
    ELSIF (x.mode = ORB.Const) &
          ((x.type.form = ORB.Array) OR (x.type.form = ORB.Record) OR (x.type.form = ORB.String)) THEN
      Set16(TRUE, TRUE);
      OCG.Gen(OCG.LDA, OCG.mDP, BANK_DP, 0);
      OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
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
    FOR i := 0 TO FP_OPS - 1 DO fpFixupCount[i] := 0 END;
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
    OCG.Gen(OCG.LDA, OCG.mImm, 0, 0);
    OCG.Gen(OCG.STA, OCG.mDP, SB_DP, 0);
    OCG.AddRel(OCG.Here() + 80000000H);
    OCG.Gen(OCG.LDA, OCG.mImm, 0, 0);
    OCG.Gen(OCG.STA, OCG.mDP, BANK_DP, 0)
  END Header;

  PROCEDURE NofPtrs(typ: ORB.Type): LONGINT;
    VAR fld: ORB.Object; n: LONGINT;
  BEGIN
    IF (typ.form = ORB.Pointer) OR (typ.form = ORB.NilTyp) THEN n := 1
    ELSIF typ.form = ORB.Record THEN
      fld := typ.dsc; n := 0;
      WHILE fld # NIL DO n := NofPtrs(fld.type) + n; fld := fld.next END
    ELSIF typ.form = ORB.Array THEN n := NofPtrs(typ.base) * typ.len
    ELSE n := 0
    END;
    RETURN n
  END NofPtrs;

  (* --- .816 writer helpers --- *)
  PROCEDURE Write4(VAR R: Files.Rider; v: LONGINT);
  BEGIN
    Files.WriteByte(R, v MOD 100H);
    Files.WriteByte(R, v DIV 100H MOD 100H);
    Files.WriteByte(R, v DIV 10000H MOD 100H);
    Files.WriteByte(R, v DIV 1000000H MOD 100H)
  END Write4;

  PROCEDURE FindPtrs(VAR R: Files.Rider; typ: ORB.Type; adr: LONGINT);
    VAR fld: ORB.Object; i, s: LONGINT;
  BEGIN
    IF (typ.form = ORB.Pointer) OR (typ.form = ORB.NilTyp) THEN
      Write4(R, adr)
    ELSIF typ.form = ORB.Record THEN
      fld := typ.dsc;
      WHILE fld # NIL DO FindPtrs(R, fld.type, fld.val + adr); fld := fld.next END
    ELSIF typ.form = ORB.Array THEN
      s := typ.base.size; i := 0;
      WHILE i < typ.len DO FindPtrs(R, typ.base, i * s + adr); i := i + 1 END
    END
  END FindPtrs;

  PROCEDURE emitFP_FLOOR;
    VAR p1, p2, p3, loop, i: LONGINT;
  BEGIN
    fpSubAddr[FP_FLOOR] := OCG.Here();

  (* Extract sign *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 8000H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_SIGN, 0);

  (* Extract exponent = (FP_A_HI & 0x7F80) >> 7 *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7F80H, 0);
  (* >>7: seven LSR A instructions *)
    i := 0;
    WHILE i < 7 DO OCG.Gen(OCG.LSR, OCG.mAcc, 0, 0); i := i + 1 END;
    OCG.Gen(OCG.STA, OCG.mDP, FP_EXP, 0);

  (* If exp == 0: subnormal or zero *)
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → has_exp *)
  (* exp==0: positive→0, negative→-1 (unless -0.0→0) *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_SIGN, 0);
    p2 := emitFwdBranch(OCG.BEQ);   (* BEQ → ret_zero *)
  (* negative: check mantissa for -0.0 *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7FFFH, 0);
    p3 := emitFwdBranch(OCG.BEQ);   (* BEQ → ret_zero *)
    OCG.Gen(OCG.LDA, OCG.mImm, 0FFFFH, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
  (* ret_zero: *)
    patch(p2); patch(p3);
    OCG.Gen(OCG.LDA, OCG.mImm, 0000H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);

  (* has_exp: *)
    patch(p1);
  (* unbiased = exp - 127 *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_EXP, 0);
    OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.SBC, OCG.mImm, 127, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_EXP, 0);

  (* If unbiased < 0: |val| < 1 → positive:0, negative:-1 *)
    p1 := emitFwdBranch(OCG.BPL);   (* BPL → normal *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_SIGN, 0);
    OCG.Gen(OCG.BNE, OCG.mPCR, OCG.Here() + 2 + 5, 0);   (* BNE → neg1 *)
    OCG.Gen(OCG.LDA, OCG.mImm, 0000H, 0);
    OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 3, 0);   (* BRA → store *)
    OCG.Gen(OCG.LDA, OCG.mImm, 0FFFFH, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
    patch(p1);

  (* If unbiased >= 15: clamp *)
    OCG.Gen(OCG.CMP, OCG.mImm, 15, 0);
    p1 := emitFwdBranch(OCG.BCC);   (* BCC → no_ovf *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_SIGN, 0);
    OCG.Gen(OCG.BNE, OCG.mPCR, OCG.Here() + 2 + 5, 0);   (* BNE → neg_ovf *)
    OCG.Gen(OCG.LDA, OCG.mImm, 7FFFH, 0);
    OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 3, 0);   (* BRA → st_ovf *)
    OCG.Gen(OCG.LDA, OCG.mImm, 8000H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
    patch(p1);

  (* Build 24-bit mantissa with implicit 1 *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 007FH, 0);
    OCG.Gen(OCG.ORA, OCG.mImm, 0080H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M1_HI, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M1_LO, 0);

  (* Track fractional bits for FLOOR rounding *)
    OCG.Gen(OCG.STZ, OCG.mDP, FP_TEMP, 0);

  (* shift_count = 23 - unbiased (always > 0 since unbiased < 15) *)
    OCG.Gen(OCG.LDA, OCG.mImm, 23, 0);
    OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.SBC, OCG.mDP, FP_EXP, 0);
    p1 := emitFwdBranch(OCG.BEQ);   (* BEQ → done_shift *)
    OCG.Gen(OCG.STA, OCG.mDP, FP_CNT, 0);

    loop := OCG.Here();
    OCG.Gen(OCG.LSR, OCG.mDP, FP_M1_HI, 0);
    OCG.Gen(OCG.ROR, OCG.mDP, FP_M1_LO, 0);
    OCG.Gen(OCG.BCC, OCG.mPCR, OCG.Here() + 2 + 2, 0);   (* BCC +2 *)
    OCG.Gen(OCG.INC, OCG.mDP, FP_TEMP, 0);
    OCG.Gen(OCG.DEC, OCG.mDP, FP_CNT, 0);
    OCG.Gen(OCG.BNE, OCG.mPCR, loop, 0);
    patch(p1);   (* done_shift *)

  (* Result in FP_M1_LO. Apply sign. *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_SIGN, 0);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → negative *)
  (* positive: store directly *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_M1_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);

  (* negative: negate magnitude; if fractional bits, add 1 before negate *)
    patch(p1);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_TEMP, 0);
    OCG.Gen(OCG.BEQ, OCG.mPCR, OCG.Here() + 2 + 4, 0);   (* BEQ +4 (no fraction) *)
    OCG.Gen(OCG.INC, OCG.mDP, FP_M1_LO, 0);
    OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2, 0);   (* BRA +0 (→ negate) *)
  (* negate: two's complement *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_M1_LO, 0);
    OCG.Gen(OCG.EOR, OCG.mImm, 0FFFFH, 0);
    OCG.Gen(OCG.INC, OCG.mAcc, 0, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
  END emitFP_FLOOR;

  (* --- FLT: signed 16-bit integer → IEEE 754 single --- *)

  PROCEDURE emitFP_FLT;
    VAR p1, loop: LONGINT;
  BEGIN
    fpSubAddr[FP_FLT] := OCG.Here();

  (* Input in FP_A_LO (16-bit signed integer) *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_LO, 0);

  (* If zero, return +0.0 *)
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → nonzero *)
    OCG.Gen(OCG.STZ, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
    patch(p1);

  (* Save sign, take absolute value *)
    OCG.Gen(OCG.STZ, OCG.mDP, FP_SIGN, 0);
    p1 := emitFwdBranch(OCG.BPL);   (* BPL → positive *)
    OCG.Gen(OCG.LDA, OCG.mImm, 8000H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_SIGN, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.EOR, OCG.mImm, 0FFFFH, 0);
    OCG.Gen(OCG.INC, OCG.mAcc, 0, 0);
    OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 2, 0);   (* BRA → store_abs *)
    patch(p1);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_LO, 0);
  (* store_abs: *)
    OCG.Gen(OCG.STA, OCG.mDP, FP_M1_LO, 0);
    OCG.Gen(OCG.STZ, OCG.mDP, FP_M1_HI, 0);

  (* Find highest bit: shift left until bit 15 is set, count shifts *)
    OCG.Gen(OCG.LDA, OCG.mImm, 0, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_CNT, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_M1_LO, 0);

    loop := OCG.Here();
    OCG.Gen(OCG.CMP, OCG.mImm, 8000H, 0);
    p1 := emitFwdBranch(OCG.BCS);   (* BCS → found_msb *)
    OCG.Gen(OCG.ASL, OCG.mAcc, 0, 0);
    OCG.Gen(OCG.INC, OCG.mDP, FP_CNT, 0);
    OCG.Gen(OCG.BRA, OCG.mPCR, loop, 0);
    patch(p1);

  (* A now has the value shifted so bit 15 is the MSB *)
    OCG.Gen(OCG.STA, OCG.mDP, FP_TEMP, 0);
  (* mantissa_lo = (TEMP & 0xFF) << 8 *)
    OCG.Gen(OCG.AND, OCG.mImm, 00FFH, 0);
    OCG.Gen(OCG.XBA, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);

  (* mantissa_hi = (TEMP >> 8) & 0x7F *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_TEMP, 0);
    OCG.Gen(OCG.XBA, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 007FH, 0);

  (* exponent = 127 + 15 - shift_count *)
    OCG.Gen(OCG.STA, OCG.mDP, FP_TEMP, 0);
    OCG.Gen(OCG.LDA, OCG.mImm, 127 + 15, 0);
    OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.SBC, OCG.mDP, FP_CNT, 0);
  (* Shift exp left 7: XBA (<<8) then LSR (>>1) = <<7 *)
    OCG.Gen(OCG.XBA, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.LSR, OCG.mAcc, 0, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7F80H, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_TEMP, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_SIGN, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
  END emitFP_FLT;

  (* --- FADD: IEEE 754 single addition --- *)
  (* FP_A + FP_B → FP_A *)

  PROCEDURE emitFP_ADD;
    VAR p1, p2, p3, loop, i: LONGINT;
  BEGIN
    fpSubAddr[FP_ADD] := OCG.Here();

  (* Unpack A: sign_a, exp_a, mant_a (24-bit with implicit 1) *)
  (* Check for zero first *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7FFFH, 0);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → a_nonzero *)
  (* A is zero: return B *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_HI, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
    patch(p1);

  (* Check B for zero *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_LO, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_B_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7FFFH, 0);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → b_nonzero *)
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
    patch(p1);

  (* Extract sign_a *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 8000H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_SIGN, 0);

  (* Extract exp_a *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7F80H, 0);
    i := 0;
    WHILE i < 7 DO OCG.Gen(OCG.LSR, OCG.mAcc, 0, 0); i := i + 1 END;
    OCG.Gen(OCG.STA, OCG.mDP, FP_EXP, 0);

  (* Extract mant_a (24-bit with implicit 1) *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 007FH, 0);
    OCG.Gen(OCG.ORA, OCG.mImm, 0080H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M1_HI, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M1_LO, 0);

  (* Extract sign_b *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 8000H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_TEMP2, 0);

  (* Extract exp_b *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7F80H, 0);
    i := 0;
    WHILE i < 7 DO OCG.Gen(OCG.LSR, OCG.mAcc, 0, 0); i := i + 1 END;
    OCG.Gen(OCG.STA, OCG.mDP, FP_TEMP, 0);

  (* Extract mant_b *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 007FH, 0);
    OCG.Gen(OCG.ORA, OCG.mImm, 0080H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M2_HI, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M2_LO, 0);

  (* Compare exponents: ensure exp_a >= exp_b (swap if needed) *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_EXP, 0);
    OCG.Gen(OCG.CMP, OCG.mDP, FP_TEMP, 0);
    p1 := emitFwdBranch(OCG.BCS);   (* BCS → no_swap *)

  (* Swap A and B (exp, mant, sign) *)
  (* Swap exponents *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_EXP, 0);
    OCG.Gen(OCG.LDX, OCG.mDP, FP_TEMP, 0);
    OCG.Gen(OCG.STX, OCG.mDP, FP_EXP, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_TEMP, 0);
  (* Swap mantissas *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_M1_LO, 0);
    OCG.Gen(OCG.LDX, OCG.mDP, FP_M2_LO, 0);
    OCG.Gen(OCG.STX, OCG.mDP, FP_M1_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M2_LO, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_M1_HI, 0);
    OCG.Gen(OCG.LDX, OCG.mDP, FP_M2_HI, 0);
    OCG.Gen(OCG.STX, OCG.mDP, FP_M1_HI, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M2_HI, 0);
  (* Swap signs *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_SIGN, 0);
    OCG.Gen(OCG.LDX, OCG.mDP, FP_TEMP2, 0);
    OCG.Gen(OCG.STX, OCG.mDP, FP_SIGN, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_TEMP2, 0);
    patch(p1);   (* no_swap *)

  (* Align mantissas: shift M2 right by (exp_a - exp_b) *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_EXP, 0);
    OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.SBC, OCG.mDP, FP_TEMP, 0);
    p1 := emitFwdBranch(OCG.BEQ);   (* BEQ → aligned (no shift needed) *)
  (* If shift >= 24, M2 becomes zero *)
    OCG.Gen(OCG.CMP, OCG.mImm, 24, 0);
    p2 := emitFwdBranch(OCG.BCC);   (* BCC → do_shift *)
    OCG.Gen(OCG.STZ, OCG.mDP, FP_M2_LO, 0);
    OCG.Gen(OCG.STZ, OCG.mDP, FP_M2_HI, 0);
    p3 := emitFwdBranch(OCG.BRA);   (* BRA → aligned *)
    patch(p2);
    OCG.Gen(OCG.STA, OCG.mDP, FP_CNT, 0);
    loop := OCG.Here();
    OCG.Gen(OCG.LSR, OCG.mDP, FP_M2_HI, 0);
    OCG.Gen(OCG.ROR, OCG.mDP, FP_M2_LO, 0);
    OCG.Gen(OCG.DEC, OCG.mDP, FP_CNT, 0);
    OCG.Gen(OCG.BNE, OCG.mPCR, loop, 0);
    patch(p1); patch(p3);   (* aligned *)

  (* Compare signs *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_SIGN, 0);
    OCG.Gen(OCG.EOR, OCG.mDP, FP_TEMP2, 0);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → diff_signs *)

  (* Same signs: add mantissas *)
    OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_M1_LO, 0);
    OCG.Gen(OCG.ADC, OCG.mDP, FP_M2_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M1_LO, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_M1_HI, 0);
    OCG.Gen(OCG.ADC, OCG.mDP, FP_M2_HI, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M1_HI, 0);
  (* Check for mantissa overflow (bit 8 of M1_HI = bit 24 of 24-bit mantissa) *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_M1_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 0100H, 0);
    p2 := emitFwdBranch(OCG.BEQ);   (* BEQ → no_overflow *)
  (* Shift right 1, increment exp *)
    OCG.Gen(OCG.LSR, OCG.mDP, FP_M1_HI, 0);
    OCG.Gen(OCG.ROR, OCG.mDP, FP_M1_LO, 0);
    OCG.Gen(OCG.INC, OCG.mDP, FP_EXP, 0);
    patch(p2);
    p2 := emitFwdBranch(OCG.BRA);   (* BRA → pack *)
    patch(p1);   (* diff_signs *)

  (* Different signs: subtract smaller from larger (M1 >= M2 after exponent alignment) *)
    OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_M1_LO, 0);
    OCG.Gen(OCG.SBC, OCG.mDP, FP_M2_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M1_LO, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_M1_HI, 0);
    OCG.Gen(OCG.SBC, OCG.mDP, FP_M2_HI, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M1_HI, 0);

  (* Check if result is zero *)
    OCG.Gen(OCG.ORA, OCG.mDP, FP_M1_LO, 0);
    p3 := emitFwdBranch(OCG.BNE);   (* BNE → normalize *)
  (* Result is zero *)
    OCG.Gen(OCG.STZ, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.STZ, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
    patch(p3);

  (* Normalize: shift left until bit 7 of M1_HI is set (bit 23 of mantissa) *)
    loop := OCG.Here();
    OCG.Gen(OCG.LDA, OCG.mDP, FP_M1_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 0080H, 0);
    p3 := emitFwdBranch(OCG.BNE);   (* BNE → normalized (done) *)
    OCG.Gen(OCG.ASL, OCG.mDP, FP_M1_LO, 0);
    OCG.Gen(OCG.ROL, OCG.mDP, FP_M1_HI, 0);
    OCG.Gen(OCG.DEC, OCG.mDP, FP_EXP, 0);
    OCG.Gen(OCG.BRA, OCG.mPCR, loop, 0);
    patch(p3);
    patch(p2);   (* pack *)

  (* Pack result: FP_A_HI = sign | (exp << 7) | (M1_HI & 0x7F) *)
  (* FP_A_LO = M1_LO *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_EXP, 0);
    OCG.Gen(OCG.XBA, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.LSR, OCG.mAcc, 0, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7F80H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_M1_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 007FH, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_SIGN, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_M1_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
  END emitFP_ADD;

  (* --- FMUL: IEEE 754 single multiplication --- *)
  (* FP_A * FP_B → FP_A *)

  PROCEDURE emitFP_MUL;
    VAR p1, p2, loop, i: LONGINT;
  BEGIN
    fpSubAddr[FP_MUL] := OCG.Here();

  (* Check A for zero *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7FFFH, 0);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → a_nz *)
    OCG.Gen(OCG.STZ, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.STZ, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
    patch(p1);

  (* Check B for zero *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_LO, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_B_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7FFFH, 0);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → b_nz *)
    OCG.Gen(OCG.STZ, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.STZ, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
    patch(p1);

  (* Result sign = sign_a XOR sign_b *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.EOR, OCG.mDP, FP_B_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 8000H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_SIGN, 0);

  (* Result exp = exp_a + exp_b - 127 *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7F80H, 0);
    i := 0;
    WHILE i < 7 DO OCG.Gen(OCG.LSR, OCG.mAcc, 0, 0); i := i + 1 END;
    OCG.Gen(OCG.STA, OCG.mDP, FP_EXP, 0);

    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7F80H, 0);
    i := 0;
    WHILE i < 7 DO OCG.Gen(OCG.LSR, OCG.mAcc, 0, 0); i := i + 1 END;
    OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.ADC, OCG.mDP, FP_EXP, 0);
    OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.SBC, OCG.mImm, 127, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_EXP, 0);

  (* Extract mantissa A (24-bit) *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 007FH, 0);
    OCG.Gen(OCG.ORA, OCG.mImm, 0080H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M1_HI, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M1_LO, 0);

  (* Extract mantissa B (24-bit) *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 007FH, 0);
    OCG.Gen(OCG.ORA, OCG.mImm, 0080H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M2_HI, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M2_LO, 0);

  (* 24x24 multiply: shift-and-add into PROD2:PROD1:PROD0 (48-bit result) *)
    OCG.Gen(OCG.STZ, OCG.mDP, FP_PROD0, 0);
    OCG.Gen(OCG.STZ, OCG.mDP, FP_PROD1, 0);
    OCG.Gen(OCG.STZ, OCG.mDP, FP_PROD2, 0);
    OCG.Gen(OCG.LDA, OCG.mImm, 24, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_CNT, 0);

    loop := OCG.Here();
  (* Check LSB of M2 *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_M2_LO, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 0001H, 0);
    p1 := emitFwdBranch(OCG.BEQ);   (* BEQ → no_add *)
  (* Add M1 to PROD (48-bit add) *)
    OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_PROD0, 0);
    OCG.Gen(OCG.ADC, OCG.mDP, FP_M1_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_PROD0, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_PROD1, 0);
    OCG.Gen(OCG.ADC, OCG.mDP, FP_M1_HI, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_PROD1, 0);
    OCG.Gen(OCG.BCC, OCG.mPCR, OCG.Here() + 2 + 2, 0);   (* BCC +2 *)
    OCG.Gen(OCG.INC, OCG.mDP, FP_PROD2, 0);
    patch(p1);   (* no_add *)

  (* Shift M2 right by 1 *)
    OCG.Gen(OCG.LSR, OCG.mDP, FP_M2_HI, 0);
    OCG.Gen(OCG.ROR, OCG.mDP, FP_M2_LO, 0);
  (* Shift PROD right by 1 *)
    OCG.Gen(OCG.LSR, OCG.mDP, FP_PROD2, 0);
    OCG.Gen(OCG.ROR, OCG.mDP, FP_PROD1, 0);
    OCG.Gen(OCG.ROR, OCG.mDP, FP_PROD0, 0);

    OCG.Gen(OCG.DEC, OCG.mDP, FP_CNT, 0);
    OCG.Gen(OCG.BNE, OCG.mPCR, loop, 0);

  (* After 24 right-shifts, PROD = (M1 * M2) >> 24. *)
  (* If PROD1 bit 7 set: mantissa at bit 23, need INC EXP *)
  (* If PROD1 bit 7 clear: mantissa at bit 22, shift left 1 *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_PROD1, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 0080H, 0);
    p1 := emitFwdBranch(OCG.BEQ);   (* BEQ → shift_up *)
  (* PROD1 bit 7 set: product overflow, increment exponent *)
    OCG.Gen(OCG.INC, OCG.mDP, FP_EXP, 0);
    p2 := emitFwdBranch(OCG.BRA);   (* BRA → pack *)
    patch(p1);   (* shift_up: *)
    OCG.Gen(OCG.ASL, OCG.mDP, FP_PROD0, 0);
    OCG.Gen(OCG.ROL, OCG.mDP, FP_PROD1, 0);
    patch(p2);   (* pack: *)

  (* Pack: FP_A_HI = sign | (exp << 7) | (PROD1 & 0x7F), FP_A_LO = PROD0 *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_EXP, 0);
    OCG.Gen(OCG.XBA, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.LSR, OCG.mAcc, 0, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7F80H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_PROD1, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 007FH, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_SIGN, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_PROD0, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
  END emitFP_MUL;

  (* --- FDIV: IEEE 754 single division --- *)
  (* FP_A / FP_B → FP_A *)

  PROCEDURE emitFP_DIV;
    VAR p1, p2, loop, i: LONGINT;
  BEGIN
    fpSubAddr[FP_DIV] := OCG.Here();

  (* Check B for zero → trap *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_LO, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_B_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7FFFH, 0);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → b_nz *)
    OCG.Gen(OCG.BRK, OCG.mImm, 7, 0);   (* BRK #7 (division by zero trap) *)
    patch(p1);

  (* Check A for zero *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7FFFH, 0);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → a_nz *)
    OCG.Gen(OCG.STZ, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.STZ, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
    patch(p1);

  (* Result sign = sign_a XOR sign_b *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.EOR, OCG.mDP, FP_B_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 8000H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_SIGN, 0);

  (* Result exp = exp_a - exp_b + 127 *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7F80H, 0);
    i := 0;
    WHILE i < 7 DO OCG.Gen(OCG.LSR, OCG.mAcc, 0, 0); i := i + 1 END;
    OCG.Gen(OCG.STA, OCG.mDP, FP_EXP, 0);

    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7F80H, 0);
    i := 0;
    WHILE i < 7 DO OCG.Gen(OCG.LSR, OCG.mAcc, 0, 0); i := i + 1 END;
    OCG.Gen(OCG.STA, OCG.mDP, FP_TEMP, 0);

    OCG.Gen(OCG.LDA, OCG.mDP, FP_EXP, 0);
    OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.SBC, OCG.mDP, FP_TEMP, 0);
    OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.ADC, OCG.mImm, 127, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_EXP, 0);

  (* Extract mantissa A (dividend) into M1 *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 007FH, 0);
    OCG.Gen(OCG.ORA, OCG.mImm, 0080H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M1_HI, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M1_LO, 0);

  (* Extract mantissa B (divisor) into M2 *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 007FH, 0);
    OCG.Gen(OCG.ORA, OCG.mImm, 0080H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M2_HI, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M2_LO, 0);

  (* Restoring division (SANE-style): compare first, ROL quotient, then shift *)
    OCG.Gen(OCG.STZ, OCG.mDP, FP_PROD0, 0);
    OCG.Gen(OCG.STZ, OCG.mDP, FP_PROD1, 0);
    OCG.Gen(OCG.LDA, OCG.mImm, 24, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_CNT, 0);

    loop := OCG.Here();
  (* Step 1: Try subtract remainder - divisor *)
    OCG.Gen(OCG.SEC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_M1_LO, 0);
    OCG.Gen(OCG.SBC, OCG.mDP, FP_M2_LO, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_TEMP, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_M1_HI, 0);
    OCG.Gen(OCG.SBC, OCG.mDP, FP_M2_HI, 0);
  (* If borrow (C=0): remainder < divisor *)
    p1 := emitFwdBranch(OCG.BCC);   (* BCC → no_sub *)
  (* No borrow (C=1): commit subtraction *)
    OCG.Gen(OCG.STA, OCG.mDP, FP_M1_HI, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_TEMP, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_M1_LO, 0);
    patch(p1);   (* no_sub: C=0 if skipped, C=1 if subtracted *)

  (* Step 2: Shift carry into quotient (1=subtracted, 0=not) *)
    OCG.Gen(OCG.ROL, OCG.mDP, FP_PROD0, 0);
    OCG.Gen(OCG.ROL, OCG.mDP, FP_PROD1, 0);

  (* Step 3: Shift remainder left for next iteration *)
    OCG.Gen(OCG.ASL, OCG.mDP, FP_M1_LO, 0);
    OCG.Gen(OCG.ROL, OCG.mDP, FP_M1_HI, 0);

    OCG.Gen(OCG.DEC, OCG.mDP, FP_CNT, 0);
    OCG.Gen(OCG.BNE, OCG.mPCR, loop, 0);

  (* Quotient in PROD1:PROD0 (24-bit). Normalize if needed. *)
  (* Check bit 23 (PROD1 bit 7) *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_PROD1, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 0080H, 0);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → pack *)

  (* Normalize: shift left until bit 23 set *)
    loop := OCG.Here();
    OCG.Gen(OCG.LDA, OCG.mDP, FP_PROD1, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 0080H, 0);
    p2 := emitFwdBranch(OCG.BNE);   (* BNE → pack2 *)
    OCG.Gen(OCG.ASL, OCG.mDP, FP_PROD0, 0);
    OCG.Gen(OCG.ROL, OCG.mDP, FP_PROD1, 0);
    OCG.Gen(OCG.DEC, OCG.mDP, FP_EXP, 0);
    OCG.Gen(OCG.BRA, OCG.mPCR, loop, 0);
    patch(p1); patch(p2);

  (* Pack result *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_EXP, 0);
    OCG.Gen(OCG.XBA, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.LSR, OCG.mAcc, 0, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7F80H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_PROD1, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 007FH, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_SIGN, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_PROD0, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
  END emitFP_DIV;

  (* --- FCMP: IEEE 754 single comparison → -1/0/+1 in FP_A_LO --- *)

  PROCEDURE emitFP_CMP;
    VAR p1, p2: LONGINT;
  BEGIN
    fpSubAddr[FP_CMP] := OCG.Here();

  (* Both zero check *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7FFFH, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_TEMP, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_LO, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_B_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7FFFH, 0);
    OCG.Gen(OCG.ORA, OCG.mDP, FP_TEMP, 0);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → not_both_zero *)
    OCG.Gen(OCG.LDA, OCG.mImm, 0, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
    patch(p1);

  (* Sign comparison *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 8000H, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_SIGN, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 8000H, 0);
    OCG.Gen(OCG.CMP, OCG.mDP, FP_SIGN, 0);
    p1 := emitFwdBranch(OCG.BEQ);   (* BEQ → same_sign *)

  (* Different signs *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_SIGN, 0);
    OCG.Gen(OCG.BNE, OCG.mPCR, OCG.Here() + 2 + 5, 0);   (* BNE → a is neg *)
    OCG.Gen(OCG.LDA, OCG.mImm, 1, 0);
    OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 3, 0);
    OCG.Gen(OCG.LDA, OCG.mImm, 0FFFFH, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
    patch(p1);

  (* Same sign: compare hi magnitude *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7FFFH, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_TEMP, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, FP_B_HI, 0);
    OCG.Gen(OCG.AND, OCG.mImm, 7FFFH, 0);
    OCG.Gen(OCG.CMP, OCG.mDP, FP_TEMP, 0);
    p1 := emitFwdBranch(OCG.BEQ);   (* BEQ → hi_equal *)

  (* Hi words differ: B < A means A > B (for positive) *)
    p2 := emitFwdBranch(OCG.BCC);   (* BCC → B < A (carry clear) *)
  (* B > A *)
    OCG.Gen(OCG.LDA, OCG.mImm, 0FFFFH, 0);
    OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 3, 0);
    patch(p2);
    OCG.Gen(OCG.LDA, OCG.mImm, 1, 0);
  (* If negative, reverse *)
    OCG.Gen(OCG.BIT, OCG.mDP, FP_SIGN, 0);
    p2 := emitFwdBranch(OCG.BPL);   (* BPL → store (positive, no reverse) *)
  (* Negate result *)
    OCG.Gen(OCG.EOR, OCG.mImm, 0FFFFH, 0);
    OCG.Gen(OCG.INC, OCG.mAcc, 0, 0);
    patch(p2);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
    patch(p1);   (* hi_equal *)

  (* Compare lo words *)
    OCG.Gen(OCG.LDA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.CMP, OCG.mDP, FP_B_LO, 0);
    p1 := emitFwdBranch(OCG.BEQ);   (* BEQ → equal *)
    p2 := emitFwdBranch(OCG.BCC);   (* BCC → A < B *)
  (* A > B *)
    OCG.Gen(OCG.LDA, OCG.mImm, 1, 0);
    OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 3, 0);
    patch(p2);
  (* A < B *)
    OCG.Gen(OCG.LDA, OCG.mImm, 0FFFFH, 0);
  (* If negative, reverse *)
    OCG.Gen(OCG.BIT, OCG.mDP, FP_SIGN, 0);
    p2 := emitFwdBranch(OCG.BPL);   (* BPL → store *)
    OCG.Gen(OCG.EOR, OCG.mImm, 0FFFFH, 0);
    OCG.Gen(OCG.INC, OCG.mAcc, 0, 0);
    patch(p2);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
    patch(p1);   (* equal *)
    OCG.Gen(OCG.LDA, OCG.mImm, 0, 0);
    OCG.Gen(OCG.STA, OCG.mDP, FP_A_LO, 0);
    OCG.Gen(OCG.RTS, OCG.mImpl, 0, 0);
  END emitFP_CMP;


  PROCEDURE emitFPSubroutines;
  BEGIN
    IF fpFixupCount[FP_FLOOR] > 0 THEN emitFP_FLOOR END;
    IF fpFixupCount[FP_FLT] > 0 THEN emitFP_FLT END;
    IF fpFixupCount[FP_ADD] > 0 THEN emitFP_ADD END;
    IF fpFixupCount[FP_MUL] > 0 THEN emitFP_MUL END;
    IF fpFixupCount[FP_DIV] > 0 THEN emitFP_DIV END;
    IF fpFixupCount[FP_CMP] > 0 THEN emitFP_CMP END
  END emitFPSubroutines;

  PROCEDURE fixupFPCalls;
    VAR op, i, pos, addr: LONGINT;
  BEGIN
    op := 0;
    WHILE op < FP_OPS DO
      i := 0;
      WHILE i < fpFixupCount[op] DO
        pos := fpFixups[op, i] - CodeOrg;
        addr := fpSubAddr[op];
        OCG.Patch(pos, addr MOD 100H);
        OCG.Patch(pos + 1, addr DIV 100H MOD 100H);
        i := i + 1
      END;
      op := op + 1
    END
  END fixupFPCalls;

  PROCEDURE Close*(modid: ARRAY OF CHAR; key: LONGINT; nofent: LONGINT);
    VAR obj: ORB.Object; i, comsize, nofimps, nofptrs, size: LONGINT;
      name: ARRAY 256 OF CHAR; F: Files.File; R: Files.Rider;
  BEGIN
    (* Exit: emulator calls main with JSL, return with RTL *)
    OCG.Gen(OCG.RTL, OCG.mImpl, 0, 0);
    emitFPSubroutines; fixupFPCalls;
    GenTDs;   (* generate deferred type descriptors + patch T.len fixups *)

    obj := ORB.topScope.next;
    nofimps := 0; comsize := 4; nofptrs := 0;
    WHILE obj # NIL DO
      IF (obj.class = ORB.Mod) & (obj.dsc # ORB.systemScope) THEN
        nofimps := nofimps + 1
      ELSIF (obj.exno # 0) & (obj.class = ORB.Const) &
            (obj.type.form = ORB.Proc) & (obj.type.nofpar = 0) &
            (obj.type.base = ORB.noType) THEN
        i := 0; WHILE obj.name[i] # 0X DO i := i + 1 END;
        i := (i + 4) DIV 4 * 4;
        comsize := comsize + i + 4
      ELSIF obj.class = ORB.Var THEN
        nofptrs := nofptrs + NofPtrs(obj.type)
      END;
      obj := obj.next
    END;

    size := varsize + strx + comsize + (OCG.Here() + nofimps + nofent + nofptrs + 1) * 4;

    i := 0; WHILE modid[i] # 0X DO name[i] := modid[i]; i := i + 1 END;
    name[i] := "."; name[i + 1] := "8"; name[i + 2] := "1"; name[i + 3] := "6";
    name[i + 4] := 0X;
    F := Files.New(name);
    Files.Set(R, F, 0);
    Files.WriteString(R, modid);
    Write4(R, key);
    Files.WriteByte(R, version MOD 100H);
    Write4(R, size);

    obj := ORB.topScope.next;
    WHILE (obj # NIL) & (obj.class = ORB.Mod) DO
      IF obj.dsc # ORB.systemScope THEN
        Files.WriteString(R, obj(ORB.Module).orgname);
        Write4(R, obj.val)
      END;
      obj := obj.next
    END;
    Files.WriteByte(R, 0);

    Write4(R, tdx * 2);
    i := 0;
    WHILE i < tdx DO
      Files.WriteByte(R, data[i] MOD 100H);
      Files.WriteByte(R, data[i] DIV 100H MOD 100H);
      i := i + 1
    END;

    Write4(R, varsize);
    Write4(R, strx);
    i := 0; WHILE i < strx DO Files.WriteByte(R, str[i] MOD 100H); i := i + 1 END;

    Write4(R, OCG.Here() - CodeOrg);
    i := 0;
    WHILE i < OCG.Here() - CodeOrg DO
      Files.WriteByte(R, OCG.Get(i) MOD 100H); i := i + 1
    END;

    obj := ORB.topScope.next;
    WHILE obj # NIL DO
      IF (obj.exno # 0) & (obj.class = ORB.Const) &
         (obj.type.form = ORB.Proc) & (obj.type.nofpar = 0) &
         (obj.type.base = ORB.noType) THEN
        Files.WriteString(R, obj.name);
        Write4(R, obj.val)
      END;
      obj := obj.next
    END;
    Files.WriteByte(R, 0);

    Write4(R, nofent);
    Write4(R, entry);

    (* Build the export table indexed by exno (the loader indexes exports[]
       by exno), merging module-level procs/vars/types with methods — which
       live in each record's meth list, not topScope. A method's entry is its
       CODE address (backend), so importers can reach it by mno:exno. *)
    i := 0; WHILE i < maxEnt DO entryVal[i] := 0; i := i + 1 END;
    obj := ORB.topScope.next;
    WHILE obj # NIL DO
      IF (obj.exno # 0) & (obj.exno < maxEnt) THEN
        IF ((obj.class = ORB.Const) & (obj.type.form = ORB.Proc)) OR
           (obj.class = ORB.Var) THEN
          entryVal[obj.exno] := obj.val
        ELSIF (obj.class = ORB.Const) &
              ((obj.type.form = ORB.Array) OR (obj.type.form = ORB.Record)) THEN
          entryVal[obj.exno] := varsize + obj.val
        ELSIF obj.class = ORB.Typ THEN
          IF obj.type.form = ORB.Record THEN
            entryVal[obj.exno] := obj.type.len MOD 10000H
          ELSIF (obj.type.form = ORB.Pointer) &
                ((obj.type.base.typobj = NIL) OR (obj.type.base.typobj.exno = 0)) THEN
            entryVal[obj.exno] := obj.type.base.len MOD 10000H
          END
        END
      END;
      obj := obj.next
    END;
    i := 0;
    WHILE i < tdListC DO
      obj := tdList[i].meth;
      WHILE obj # NIL DO
        IF (obj.exno # 0) & (obj.exno < maxEnt) THEN entryVal[obj.exno] := obj.backend END;
        obj := obj.next
      END;
      i := i + 1
    END;
    i := 1;
    WHILE i < nofent DO Write4(R, entryVal[i]); i := i + 1 END;

    obj := ORB.topScope.next;
    WHILE obj # NIL DO
      IF obj.class = ORB.Var THEN FindPtrs(R, obj.type, obj.val) END;
      obj := obj.next
    END;

    Write4(R, -1);
    Write4(R, fixorgP);
    Write4(R, fixorgD);
    Write4(R, fixorgT);

    Write4(R, tdFixupC);
    i := 0;
    WHILE i < tdFixupC DO
      Files.WriteByte(R, tdFixupOff[i] MOD 100H);
      Files.WriteByte(R, tdFixupOff[i] DIV 100H MOD 100H);
      Files.WriteByte(R, tdFixupMno[i] MOD 100H);
      Files.WriteByte(R, tdFixupMno[i] DIV 100H MOD 100H);
      i := i + 1
    END;

    (* vtable fixups: an imported inherited method's slot, resolved by the
       loader to (import_base + exports[exno]) - this_module_code_base so the
       codeBase+slot dispatch lands in the base module. offset(4) mno(2) exno(2). *)
    Write4(R, vtFixC);
    i := 0;
    WHILE i < vtFixC DO
      Write4(R, vtFixOff[i]);
      Files.WriteByte(R, vtFixMno[i] MOD 100H);
      Files.WriteByte(R, vtFixMno[i] DIV 100H MOD 100H);
      Files.WriteByte(R, vtFixExno[i] MOD 100H);
      Files.WriteByte(R, vtFixExno[i] DIV 100H MOD 100H);
      i := i + 1
    END;

    Write4(R, OCG.RelCount());
    i := 0;
    WHILE i < OCG.RelCount() DO Write4(R, OCG.Rel(i)); i := i + 1 END;

    Write4(R, entry);
    Files.WriteByte(R, ORD("O"));
    Files.Register(F)
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
        OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(x.r), 0);
        OCG.Gen(OCG.PHA, OCG.mImpl, 0, 0);
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
        OCG.Gen(OCG.PLA, OCG.mImpl, 0, 0);   (* discard the spilled limit *)
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
    OCG.Gen(OCG.LDA, OCG.mDP, sb, 0);
    OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
    emitTDLen(rec);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
    OCG.Gen(OCG.STZ, OCG.mDP, RegAddr(RH + 1), 0);
    incR; incR;
    OCG.Gen(OCG.LDA, OCG.mImm, rec.size + 4, 0);
    OCG.Gen(OCG.BRK, OCG.mImm, 10, 0);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
    OCG.Gen(OCG.STX, OCG.mDP, RegAddr(RH + 1), 0);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(RH - 2), 0);
    OCG.Gen(OCG.STA, OCG.mDPIndL, RegAddr(RH), 0);
    OCG.Gen(OCG.LDY, OCG.mImm, 2, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(RH - 1), 0);
    OCG.Gen(OCG.STA, OCG.mDPIndLY, RegAddr(RH), 0);
    OCG.Gen(OCG.CLC, OCG.mImpl, 0, 0);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(RH), 0);
    OCG.Gen(OCG.ADC, OCG.mImm, 4, 0);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(RH), 0);
    (* object is now at [rh0+2, rh0+3]; move it over the dead tag registers to
       [rh0, rh0+1] so PrepCall only saves the genuine outer context *)
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(RH), 0);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(rh0), 0);
    OCG.Gen(OCG.LDA, OCG.mDP, RegAddr(RH + 1), 0);
    OCG.Gen(OCG.STA, OCG.mDP, RegAddr(rh0 + 1), 0);
    RH := rh0 + 2;
    x.rcvMode := Reg; x.rcvR := rh0; x.rcvType := rec;
    x.isMeth := TRUE; x.dynDisp := FALSE; x.type := m.type;
    x.mode := ORB.Const; x.a := m.backend; x.r := 0;
    x.b := 1  (* init bodies are methods: far/RTL convention, reach via JSL *)
  END InitItem;

  PROCEDURE IfaceMethodItem*(VAR x: Item; m: ORB.Object);
  BEGIN ORS.Mark("interfaces not implemented on 65C816 yet")
  END IfaceMethodItem;

  PROCEDURE PtrToIface*(VAR x: Item; ift: ORB.Type);
  BEGIN ORS.Mark("interfaces not implemented on 65C816 yet")
  END PtrToIface;

  PROCEDURE StoreIface*(VAR x, y: Item);
  BEGIN ORS.Mark("interfaces not implemented on 65C816 yet")
  END StoreIface;

  PROCEDURE IfaceRelation*(op: INTEGER; VAR x, y: Item);
  BEGIN ORS.Mark("interfaces not implemented on 65C816 yet")
  END IfaceRelation;

  PROCEDURE Init*;
  BEGIN
    relmap[0] := EQ; relmap[1] := NE; relmap[2] := LT;
    relmap[3] := GE; relmap[4] := LE; relmap[5] := GT;
    OCG.Init
  END Init;

END ORG.
