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
    data: ARRAY maxTD OF LONGINT;      (* 16-bit TD words (LONGINT so
                                          0FFFFH fits a 16-bit-INTEGER host) *)
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
      tdFixupOff[tdFixupC] := dcw * 2; tdFixupMno[tdFixupC] := T.mno;
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

  PROCEDURE BuildTD*(T: ORB.Type; VAR dc: LONGINT);
    VAR dcw, k: LONGINT;
  BEGIN
    dcw := dc DIV 2;
    T.len := dc;
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
    FindPtrFlds(T, 0, dcw);
    data[dcw] := 0FFFFH; dcw := dcw + 1;
    tdx := dcw; dc := dcw * 2;
    IF tdx >= maxTD THEN ORS.Mark("too many record types"); tdx := 0 END
  END BuildTD;

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
      OCG.Gen(OCG.ADC, OCG.mImm, T.len, 0);
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
      OCG.Gen(OCG.ADC, OCG.mImm, T.len, 0);
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

END ORG.
