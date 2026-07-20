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

  TYPE
    Item* = RECORD
      mode*: INTEGER;
      type*: ORB.Type;
      a*, b*, r*: LONGINT;
      rdo*: BOOLEAN;
      origType*: ORB.Type
    END;

  VAR
    varsize: LONGINT;    (* = ORG_varsize; set by SetDataSize *)
    tdx, strx, entry, RH, frame: LONGINT;
    fixorgP, fixorgD, fixorgT: LONGINT;
    check: BOOLEAN;
    version: INTEGER;
    relmap: ARRAY 6 OF INTEGER;
    data: ARRAY maxTD OF INTEGER;      (* 16-bit TD words *)
    str: ARRAY maxStrx OF INTEGER;     (* string/const data bytes *)
    tdFixupOff, tdFixupMno: ARRAY maxTD OF INTEGER;
    tdFixupC: INTEGER;
    fpFixups: ARRAY FP_OPS, maxFPFixups OF LONGINT;
    fpFixupCount: ARRAY FP_OPS OF INTEGER;
    fpSubAddr: ARRAY FP_OPS OF LONGINT;
    curModid: ORS.Ident;

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
        OCG.Gen(OCG.BEQ, OCG.mPCR, OCG.Here() + 2 + 4 + 4, 0);
        OCG.Gen(OCG.BVS, OCG.mPCR, OCG.Here() + 2 + 4, 0);
        OCG.Gen(OCG.BMI, OCG.mPCR, OCG.Here() + 2 + 6, 0);
        OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 7, 0);
        OCG.Gen(OCG.BPL, OCG.mPCR, OCG.Here() + 2 + 2, 0);
        OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 3, 0);
        OCG.Gen(OCG.BRL, mode, target, 0)
      ELSE
        OCG.Gen(OCG.BEQ, OCG.mPCR, OCG.Here() + 2 + 3 + 3, 0);
        OCG.Gen(OCG.BCC, OCG.mPCR, OCG.Here() + 2 + 3, 0);
        OCG.Gen(OCG.BRL, mode, target, 0)
      END
    ELSIF cond = GT THEN
      IF signed THEN
        OCG.Gen(OCG.BEQ, OCG.mPCR, OCG.Here() + 2 + 4 + 3, 0);
        OCG.Gen(OCG.BVS, OCG.mPCR, OCG.Here() + 2 + 4, 0);
        OCG.Gen(OCG.BPL, OCG.mPCR, OCG.Here() + 2 + 6, 0);
        OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 7, 0);
        OCG.Gen(OCG.BMI, OCG.mPCR, OCG.Here() + 2 + 2, 0);
        OCG.Gen(OCG.BRA, OCG.mPCR, OCG.Here() + 2 + 3, 0);
        OCG.Gen(OCG.BRL, mode, target, 0)
      ELSE
        OCG.Gen(OCG.BEQ, OCG.mPCR, OCG.Here() + 2 + 3, 0);
        OCG.Gen(OCG.BCS, OCG.mPCR, OCG.Here() + 2 + 3 + 3, 0);
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
  BEGIN x.mode := ORB.Const; x.type := typ; x.a := offset; x.b := size
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

END ORG.
