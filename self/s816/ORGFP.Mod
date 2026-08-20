MODULE ORGFP; (* 65C816 floating-point subroutine library — companion to ORG.

   Emits the FP runtime routines (add/mul/div/compare/floor/float) that each
   RealOp JSRs into, plus the fixup table that patches those JSRs to the
   routines' final in-bank addresses at Close. Peeled out of ORG so ORG's own
   code fits one 64K bank. Depends only on OCG (the 816 instruction encoder),
   never on ORG — no import cycle. The codegen entry points (RealOp,
   RealRelation, Float, Floor) stay in ORG and drive this module through
   AddFixup / EmitSubroutines / FixupCalls. *)
  IMPORT OCG;

  CONST
    CodeOrg = 0;   (* .816 code base offset; RealOp JSR fixups are absolute *)
    (* FP workspace DP addresses *)
    FP_A_LO* = 22H; FP_A_HI* = 24H; FP_B_LO* = 26H; FP_B_HI* = 28H;
    FP_SIGN = 2AH; FP_EXP = 2CH; FP_M1_LO = 2EH; FP_M1_HI = 30H;
    FP_M2_LO = 32H; FP_M2_HI = 34H; FP_PROD0 = 36H; FP_PROD1 = 38H;
    FP_PROD2 = 3AH; FP_TEMP = 3CH; FP_TEMP2 = 3EH; FP_CNT = 40H;
    (* FP operation indices *)
    FP_ADD* = 0; FP_MUL* = 1; FP_DIV* = 2; FP_CMP* = 3;
    FP_FLOOR* = 4; FP_FLT* = 5; FP_OPS = 6;
    maxFPFixups = 64;

  VAR
    fpFixups: ARRAY FP_OPS, maxFPFixups OF LONGINT;
    fpFixupCount: ARRAY FP_OPS OF INTEGER;
    fpSubAddr: ARRAY FP_OPS OF LONGINT;

  (* Local copies of ORG's forward-branch helpers — pure OCG, kept here so
     this module has no dependency back on ORG. *)
  PROCEDURE patch(at: LONGINT);
  BEGIN OCG.Patch(at, OCG.Here() - (at + 1))
  END patch;

  PROCEDURE emitFwdBranch(op: LONGINT): LONGINT;
  BEGIN
    OCG.gen1(op * 32 + OCG.mPCR, OCG.Here() + 2);
    RETURN OCG.Here() - 1
  END emitFwdBranch;

  PROCEDURE Init*;
    VAR i: INTEGER;
  BEGIN FOR i := 0 TO FP_OPS - 1 DO fpFixupCount[i] := 0 END
  END Init;

  PROCEDURE AddFixup*(idx: INTEGER);
  BEGIN
    IF fpFixupCount[idx] < maxFPFixups THEN
      fpFixups[idx, fpFixupCount[idx]] := OCG.Here() + 1;
      fpFixupCount[idx] := fpFixupCount[idx] + 1
    END
  END AddFixup;

  PROCEDURE emitFP_FLOOR;
    VAR p1, p2, p3, loop, i: LONGINT;
  BEGIN
    fpSubAddr[FP_FLOOR] := OCG.Here();

  (* Extract sign *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 8000H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_SIGN);

  (* Extract exponent = (FP_A_HI & 0x7F80) >> 7 *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7F80H);
  (* >>7: seven LSR A instructions *)
    i := 0;
    WHILE i < 7 DO OCG.gen1(OCG.LSR * 32 + OCG.mAcc, 0); i := i + 1 END;
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_EXP);

  (* If exp == 0: subnormal or zero *)
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → has_exp *)
  (* exp==0: positive→0, negative→-1 (unless -0.0→0) *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_SIGN);
    p2 := emitFwdBranch(OCG.BEQ);   (* BEQ → ret_zero *)
  (* negative: check mantissa for -0.0 *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_LO);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7FFFH);
    p3 := emitFwdBranch(OCG.BEQ);   (* BEQ → ret_zero *)
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0FFFFH);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_LO);
    OCG.Rts;
  (* ret_zero: *)
    patch(p2); patch(p3);
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0000H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_LO);
    OCG.Rts;

  (* has_exp: *)
    patch(p1);
  (* unbiased = exp - 127 *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_EXP);
    OCG.Sec;
    OCG.gen1(OCG.SBC * 32 + OCG.mImm, 127);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_EXP);

  (* If unbiased < 0: |val| < 1 → positive:0, negative:-1 *)
    p1 := emitFwdBranch(OCG.BPL);   (* BPL → normal *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_SIGN);
    OCG.gen1(OCG.BNE * 32 + OCG.mPCR, OCG.Here() + 2 + 5);   (* BNE → neg1 *)
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0000H);
    OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 + 3);   (* BRA → store *)
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0FFFFH);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_LO);
    OCG.Rts;
    patch(p1);

  (* If unbiased >= 15: clamp *)
    OCG.gen1(OCG.CMP * 32 + OCG.mImm, 15);
    p1 := emitFwdBranch(OCG.BCC);   (* BCC → no_ovf *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_SIGN);
    OCG.gen1(OCG.BNE * 32 + OCG.mPCR, OCG.Here() + 2 + 5);   (* BNE → neg_ovf *)
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 7FFFH);
    OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 + 3);   (* BRA → st_ovf *)
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 8000H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_LO);
    OCG.Rts;
    patch(p1);

  (* Build 24-bit mantissa with implicit 1 *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 007FH);
    OCG.gen1(OCG.ORA * 32 + OCG.mImm, 0080H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M1_HI);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M1_LO);

  (* Track fractional bits for FLOOR rounding *)
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_TEMP);

  (* shift_count = 23 - unbiased (always > 0 since unbiased < 15) *)
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 23);
    OCG.Sec;
    OCG.gen1(OCG.SBC * 32 + OCG.mDP, FP_EXP);
    p1 := emitFwdBranch(OCG.BEQ);   (* BEQ → done_shift *)
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_CNT);

    loop := OCG.Here();
    OCG.gen1(OCG.LSR * 32 + OCG.mDP, FP_M1_HI);
    OCG.gen1(OCG.ROR * 32 + OCG.mDP, FP_M1_LO);
    OCG.gen1(OCG.BCC * 32 + OCG.mPCR, OCG.Here() + 2 + 2);   (* BCC +2 *)
    OCG.gen1(OCG.INC * 32 + OCG.mDP, FP_TEMP);
    OCG.gen1(OCG.DEC * 32 + OCG.mDP, FP_CNT);
    OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loop);
    patch(p1);   (* done_shift *)

  (* Result in FP_M1_LO. Apply sign. *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_SIGN);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → negative *)
  (* positive: store directly *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_M1_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_LO);
    OCG.Rts;

  (* negative: negate magnitude; if fractional bits, add 1 before negate *)
    patch(p1);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_TEMP);
    OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 2 + 4);   (* BEQ +4 (no fraction) *)
    OCG.gen1(OCG.INC * 32 + OCG.mDP, FP_M1_LO);
    OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2);   (* BRA +0 (→ negate) *)
  (* negate: two's complement *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_M1_LO);
    OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
    OCG.gen1(OCG.INC * 32 + OCG.mAcc, 0);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_LO);
    OCG.Rts;
  END emitFP_FLOOR;

  (* --- FLT: signed 16-bit integer → IEEE 754 single --- *)

  PROCEDURE emitFP_FLT;
    VAR p1, loop: LONGINT;
  BEGIN
    fpSubAddr[FP_FLT] := OCG.Here();

  (* Input in FP_A_LO (16-bit signed integer) *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_LO);

  (* If zero, return +0.0 *)
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → nonzero *)
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_A_HI);
    OCG.Rts;
    patch(p1);

  (* Save sign, take absolute value *)
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_SIGN);
    p1 := emitFwdBranch(OCG.BPL);   (* BPL → positive *)
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 8000H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_SIGN);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_LO);
    OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
    OCG.gen1(OCG.INC * 32 + OCG.mAcc, 0);
    OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 + 2);   (* BRA → store_abs *)
    patch(p1);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_LO);
  (* store_abs: *)
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M1_LO);
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_M1_HI);

  (* Find highest bit: shift left until bit 15 is set, count shifts *)
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_CNT);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_M1_LO);

    loop := OCG.Here();
    OCG.gen1(OCG.CMP * 32 + OCG.mImm, 8000H);
    p1 := emitFwdBranch(OCG.BCS);   (* BCS → found_msb *)
    OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);
    OCG.gen1(OCG.INC * 32 + OCG.mDP, FP_CNT);
    OCG.gen1(OCG.BRA * 32 + OCG.mPCR, loop);
    patch(p1);

  (* A now has the value shifted so bit 15 is the MSB *)
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_TEMP);
  (* mantissa_lo = (TEMP & 0xFF) << 8 *)
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 00FFH);
    OCG.Xba;
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_LO);

  (* mantissa_hi = (TEMP >> 8) & 0x7F *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_TEMP);
    OCG.Xba;
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 007FH);

  (* exponent = 127 + 15 - shift_count *)
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_TEMP);
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 127 + 15);
    OCG.Sec;
    OCG.gen1(OCG.SBC * 32 + OCG.mDP, FP_CNT);
  (* Shift exp left 7: XBA (<<8) then LSR (>>1) = <<7 *)
    OCG.Xba;
    OCG.gen1(OCG.LSR * 32 + OCG.mAcc, 0);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7F80H);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_TEMP);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_SIGN);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_HI);
    OCG.Rts;
  END emitFP_FLT;

  (* --- FADD: IEEE 754 single addition --- *)
  (* FP_A + FP_B → FP_A *)

  PROCEDURE emitFP_ADD;
    VAR p1, p2, p3, loop, i: LONGINT;
  BEGIN
    fpSubAddr[FP_ADD] := OCG.Here();

  (* Unpack A: sign_a, exp_a, mant_a (24-bit with implicit 1) *)
  (* Check for zero first *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_LO);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7FFFH);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → a_nonzero *)
  (* A is zero: return B *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_LO);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_HI);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_HI);
    OCG.Rts;
    patch(p1);

  (* Check B for zero *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_LO);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_B_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7FFFH);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → b_nonzero *)
    OCG.Rts;
    patch(p1);

  (* Extract sign_a *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 8000H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_SIGN);

  (* Extract exp_a *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7F80H);
    i := 0;
    WHILE i < 7 DO OCG.gen1(OCG.LSR * 32 + OCG.mAcc, 0); i := i + 1 END;
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_EXP);

  (* Extract mant_a (24-bit with implicit 1) *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 007FH);
    OCG.gen1(OCG.ORA * 32 + OCG.mImm, 0080H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M1_HI);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M1_LO);

  (* Extract sign_b *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 8000H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_TEMP2);

  (* Extract exp_b *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7F80H);
    i := 0;
    WHILE i < 7 DO OCG.gen1(OCG.LSR * 32 + OCG.mAcc, 0); i := i + 1 END;
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_TEMP);

  (* Extract mant_b *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 007FH);
    OCG.gen1(OCG.ORA * 32 + OCG.mImm, 0080H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M2_HI);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M2_LO);

  (* Compare exponents: ensure exp_a >= exp_b (swap if needed) *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_EXP);
    OCG.gen1(OCG.CMP * 32 + OCG.mDP, FP_TEMP);
    p1 := emitFwdBranch(OCG.BCS);   (* BCS → no_swap *)

  (* Swap A and B (exp, mant, sign) *)
  (* Swap exponents *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_EXP);
    OCG.gen1(OCG.LDX * 32 + OCG.mDP, FP_TEMP);
    OCG.gen1(OCG.STX * 32 + OCG.mDP, FP_EXP);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_TEMP);
  (* Swap mantissas *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_M1_LO);
    OCG.gen1(OCG.LDX * 32 + OCG.mDP, FP_M2_LO);
    OCG.gen1(OCG.STX * 32 + OCG.mDP, FP_M1_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M2_LO);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_M1_HI);
    OCG.gen1(OCG.LDX * 32 + OCG.mDP, FP_M2_HI);
    OCG.gen1(OCG.STX * 32 + OCG.mDP, FP_M1_HI);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M2_HI);
  (* Swap signs *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_SIGN);
    OCG.gen1(OCG.LDX * 32 + OCG.mDP, FP_TEMP2);
    OCG.gen1(OCG.STX * 32 + OCG.mDP, FP_SIGN);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_TEMP2);
    patch(p1);   (* no_swap *)

  (* Align mantissas: shift M2 right by (exp_a - exp_b) *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_EXP);
    OCG.Sec;
    OCG.gen1(OCG.SBC * 32 + OCG.mDP, FP_TEMP);
    p1 := emitFwdBranch(OCG.BEQ);   (* BEQ → aligned (no shift needed) *)
  (* If shift >= 24, M2 becomes zero *)
    OCG.gen1(OCG.CMP * 32 + OCG.mImm, 24);
    p2 := emitFwdBranch(OCG.BCC);   (* BCC → do_shift *)
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_M2_LO);
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_M2_HI);
    p3 := emitFwdBranch(OCG.BRA);   (* BRA → aligned *)
    patch(p2);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_CNT);
    loop := OCG.Here();
    OCG.gen1(OCG.LSR * 32 + OCG.mDP, FP_M2_HI);
    OCG.gen1(OCG.ROR * 32 + OCG.mDP, FP_M2_LO);
    OCG.gen1(OCG.DEC * 32 + OCG.mDP, FP_CNT);
    OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loop);
    patch(p1); patch(p3);   (* aligned *)

  (* Compare signs *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_SIGN);
    OCG.gen1(OCG.EOR * 32 + OCG.mDP, FP_TEMP2);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → diff_signs *)

  (* Same signs: add mantissas *)
    OCG.Clc;
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_M1_LO);
    OCG.gen1(OCG.ADC * 32 + OCG.mDP, FP_M2_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M1_LO);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_M1_HI);
    OCG.gen1(OCG.ADC * 32 + OCG.mDP, FP_M2_HI);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M1_HI);
  (* Check for mantissa overflow (bit 8 of M1_HI = bit 24 of 24-bit mantissa) *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_M1_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 0100H);
    p2 := emitFwdBranch(OCG.BEQ);   (* BEQ → no_overflow *)
  (* Shift right 1, increment exp *)
    OCG.gen1(OCG.LSR * 32 + OCG.mDP, FP_M1_HI);
    OCG.gen1(OCG.ROR * 32 + OCG.mDP, FP_M1_LO);
    OCG.gen1(OCG.INC * 32 + OCG.mDP, FP_EXP);
    patch(p2);
    p2 := emitFwdBranch(OCG.BRA);   (* BRA → pack *)
    patch(p1);   (* diff_signs *)

  (* Different signs: subtract smaller from larger (M1 >= M2 after exponent alignment) *)
    OCG.Sec;
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_M1_LO);
    OCG.gen1(OCG.SBC * 32 + OCG.mDP, FP_M2_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M1_LO);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_M1_HI);
    OCG.gen1(OCG.SBC * 32 + OCG.mDP, FP_M2_HI);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M1_HI);

  (* Check if result is zero *)
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_M1_LO);
    p3 := emitFwdBranch(OCG.BNE);   (* BNE → normalize *)
  (* Result is zero *)
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_A_LO);
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_A_HI);
    OCG.Rts;
    patch(p3);

  (* Normalize: shift left until bit 7 of M1_HI is set (bit 23 of mantissa) *)
    loop := OCG.Here();
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_M1_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 0080H);
    p3 := emitFwdBranch(OCG.BNE);   (* BNE → normalized (done) *)
    OCG.gen1(OCG.ASL * 32 + OCG.mDP, FP_M1_LO);
    OCG.gen1(OCG.ROL * 32 + OCG.mDP, FP_M1_HI);
    OCG.gen1(OCG.DEC * 32 + OCG.mDP, FP_EXP);
    OCG.gen1(OCG.BRA * 32 + OCG.mPCR, loop);
    patch(p3);
    patch(p2);   (* pack *)

  (* Pack result: FP_A_HI = sign | (exp << 7) | (M1_HI & 0x7F) *)
  (* FP_A_LO = M1_LO *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_EXP);
    OCG.Xba;
    OCG.gen1(OCG.LSR * 32 + OCG.mAcc, 0);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7F80H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_M1_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 007FH);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_SIGN);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_M1_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_LO);
    OCG.Rts;
  END emitFP_ADD;

  (* --- FMUL: IEEE 754 single multiplication --- *)
  (* FP_A * FP_B → FP_A *)

  PROCEDURE emitFP_MUL;
    VAR p1, p2, loop, i: LONGINT;
  BEGIN
    fpSubAddr[FP_MUL] := OCG.Here();

  (* Check A for zero *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_LO);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7FFFH);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → a_nz *)
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_A_LO);
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_A_HI);
    OCG.Rts;
    patch(p1);

  (* Check B for zero *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_LO);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_B_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7FFFH);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → b_nz *)
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_A_LO);
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_A_HI);
    OCG.Rts;
    patch(p1);

  (* Result sign = sign_a XOR sign_b *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.EOR * 32 + OCG.mDP, FP_B_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 8000H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_SIGN);

  (* Result exp = exp_a + exp_b - 127 *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7F80H);
    i := 0;
    WHILE i < 7 DO OCG.gen1(OCG.LSR * 32 + OCG.mAcc, 0); i := i + 1 END;
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_EXP);

    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7F80H);
    i := 0;
    WHILE i < 7 DO OCG.gen1(OCG.LSR * 32 + OCG.mAcc, 0); i := i + 1 END;
    OCG.Clc;
    OCG.gen1(OCG.ADC * 32 + OCG.mDP, FP_EXP);
    OCG.Sec;
    OCG.gen1(OCG.SBC * 32 + OCG.mImm, 127);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_EXP);

  (* Extract mantissa A (24-bit) *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 007FH);
    OCG.gen1(OCG.ORA * 32 + OCG.mImm, 0080H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M1_HI);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M1_LO);

  (* Extract mantissa B (24-bit) *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 007FH);
    OCG.gen1(OCG.ORA * 32 + OCG.mImm, 0080H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M2_HI);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M2_LO);

  (* 24x24 multiply: shift-and-add into PROD2:PROD1:PROD0 (48-bit result) *)
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_PROD0);
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_PROD1);
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_PROD2);
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 24);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_CNT);

    loop := OCG.Here();
  (* Check LSB of M2 *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_M2_LO);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 0001H);
    p1 := emitFwdBranch(OCG.BEQ);   (* BEQ → no_add *)
  (* Add M1 to PROD (48-bit add) *)
    OCG.Clc;
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_PROD0);
    OCG.gen1(OCG.ADC * 32 + OCG.mDP, FP_M1_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_PROD0);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_PROD1);
    OCG.gen1(OCG.ADC * 32 + OCG.mDP, FP_M1_HI);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_PROD1);
    OCG.gen1(OCG.BCC * 32 + OCG.mPCR, OCG.Here() + 2 + 2);   (* BCC +2 *)
    OCG.gen1(OCG.INC * 32 + OCG.mDP, FP_PROD2);
    patch(p1);   (* no_add *)

  (* Shift M2 right by 1 *)
    OCG.gen1(OCG.LSR * 32 + OCG.mDP, FP_M2_HI);
    OCG.gen1(OCG.ROR * 32 + OCG.mDP, FP_M2_LO);
  (* Shift PROD right by 1 *)
    OCG.gen1(OCG.LSR * 32 + OCG.mDP, FP_PROD2);
    OCG.gen1(OCG.ROR * 32 + OCG.mDP, FP_PROD1);
    OCG.gen1(OCG.ROR * 32 + OCG.mDP, FP_PROD0);

    OCG.gen1(OCG.DEC * 32 + OCG.mDP, FP_CNT);
    OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loop);

  (* After 24 right-shifts, PROD = (M1 * M2) >> 24. *)
  (* If PROD1 bit 7 set: mantissa at bit 23, need INC EXP *)
  (* If PROD1 bit 7 clear: mantissa at bit 22, shift left 1 *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_PROD1);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 0080H);
    p1 := emitFwdBranch(OCG.BEQ);   (* BEQ → shift_up *)
  (* PROD1 bit 7 set: product overflow, increment exponent *)
    OCG.gen1(OCG.INC * 32 + OCG.mDP, FP_EXP);
    p2 := emitFwdBranch(OCG.BRA);   (* BRA → pack *)
    patch(p1);   (* shift_up: *)
    OCG.gen1(OCG.ASL * 32 + OCG.mDP, FP_PROD0);
    OCG.gen1(OCG.ROL * 32 + OCG.mDP, FP_PROD1);
    patch(p2);   (* pack: *)

  (* Pack: FP_A_HI = sign | (exp << 7) | (PROD1 & 0x7F), FP_A_LO = PROD0 *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_EXP);
    OCG.Xba;
    OCG.gen1(OCG.LSR * 32 + OCG.mAcc, 0);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7F80H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_PROD1);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 007FH);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_SIGN);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_PROD0);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_LO);
    OCG.Rts;
  END emitFP_MUL;

  (* --- FDIV: IEEE 754 single division --- *)
  (* FP_A / FP_B → FP_A *)

  PROCEDURE emitFP_DIV;
    VAR p1, p2, loop, i: LONGINT;
  BEGIN
    fpSubAddr[FP_DIV] := OCG.Here();

  (* Check B for zero → trap *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_LO);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_B_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7FFFH);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → b_nz *)
    OCG.gen1(OCG.BRK * 32 + OCG.mImm, 7);   (* BRK #7 (division by zero trap) *)
    patch(p1);

  (* Check A for zero *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_LO);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7FFFH);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → a_nz *)
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_A_LO);
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_A_HI);
    OCG.Rts;
    patch(p1);

  (* Result sign = sign_a XOR sign_b *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.EOR * 32 + OCG.mDP, FP_B_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 8000H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_SIGN);

  (* Result exp = exp_a - exp_b + 127 *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7F80H);
    i := 0;
    WHILE i < 7 DO OCG.gen1(OCG.LSR * 32 + OCG.mAcc, 0); i := i + 1 END;
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_EXP);

    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7F80H);
    i := 0;
    WHILE i < 7 DO OCG.gen1(OCG.LSR * 32 + OCG.mAcc, 0); i := i + 1 END;
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_TEMP);

    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_EXP);
    OCG.Sec;
    OCG.gen1(OCG.SBC * 32 + OCG.mDP, FP_TEMP);
    OCG.Clc;
    OCG.gen1(OCG.ADC * 32 + OCG.mImm, 127);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_EXP);

  (* Extract mantissa A (dividend) into M1 *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 007FH);
    OCG.gen1(OCG.ORA * 32 + OCG.mImm, 0080H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M1_HI);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M1_LO);

  (* Extract mantissa B (divisor) into M2 *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 007FH);
    OCG.gen1(OCG.ORA * 32 + OCG.mImm, 0080H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M2_HI);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M2_LO);

  (* Restoring division (SANE-style): compare first, ROL quotient, then shift *)
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_PROD0);
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, FP_PROD1);
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 24);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_CNT);

    loop := OCG.Here();
  (* Step 1: Try subtract remainder - divisor *)
    OCG.Sec;
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_M1_LO);
    OCG.gen1(OCG.SBC * 32 + OCG.mDP, FP_M2_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_TEMP);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_M1_HI);
    OCG.gen1(OCG.SBC * 32 + OCG.mDP, FP_M2_HI);
  (* If borrow (C=0): remainder < divisor *)
    p1 := emitFwdBranch(OCG.BCC);   (* BCC → no_sub *)
  (* No borrow (C=1): commit subtraction *)
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M1_HI);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_TEMP);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_M1_LO);
    patch(p1);   (* no_sub: C=0 if skipped, C=1 if subtracted *)

  (* Step 2: Shift carry into quotient (1=subtracted, 0=not) *)
    OCG.gen1(OCG.ROL * 32 + OCG.mDP, FP_PROD0);
    OCG.gen1(OCG.ROL * 32 + OCG.mDP, FP_PROD1);

  (* Step 3: Shift remainder left for next iteration *)
    OCG.gen1(OCG.ASL * 32 + OCG.mDP, FP_M1_LO);
    OCG.gen1(OCG.ROL * 32 + OCG.mDP, FP_M1_HI);

    OCG.gen1(OCG.DEC * 32 + OCG.mDP, FP_CNT);
    OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loop);

  (* Quotient in PROD1:PROD0 (24-bit). Normalize if needed. *)
  (* Check bit 23 (PROD1 bit 7) *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_PROD1);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 0080H);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → pack *)

  (* Normalize: shift left until bit 23 set *)
    loop := OCG.Here();
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_PROD1);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 0080H);
    p2 := emitFwdBranch(OCG.BNE);   (* BNE → pack2 *)
    OCG.gen1(OCG.ASL * 32 + OCG.mDP, FP_PROD0);
    OCG.gen1(OCG.ROL * 32 + OCG.mDP, FP_PROD1);
    OCG.gen1(OCG.DEC * 32 + OCG.mDP, FP_EXP);
    OCG.gen1(OCG.BRA * 32 + OCG.mPCR, loop);
    patch(p1); patch(p2);

  (* Pack result *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_EXP);
    OCG.Xba;
    OCG.gen1(OCG.LSR * 32 + OCG.mAcc, 0);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7F80H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_PROD1);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 007FH);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_SIGN);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_PROD0);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_LO);
    OCG.Rts;
  END emitFP_DIV;

  (* --- FCMP: IEEE 754 single comparison → -1/0/+1 in FP_A_LO --- *)

  PROCEDURE emitFP_CMP;
    VAR p1, p2: LONGINT;
  BEGIN
    fpSubAddr[FP_CMP] := OCG.Here();

  (* Both zero check *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_LO);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7FFFH);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_TEMP);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_LO);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_B_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7FFFH);
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, FP_TEMP);
    p1 := emitFwdBranch(OCG.BNE);   (* BNE → not_both_zero *)
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_LO);
    OCG.Rts;
    patch(p1);

  (* Sign comparison *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 8000H);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_SIGN);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 8000H);
    OCG.gen1(OCG.CMP * 32 + OCG.mDP, FP_SIGN);
    p1 := emitFwdBranch(OCG.BEQ);   (* BEQ → same_sign *)

  (* Different signs *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_SIGN);
    OCG.gen1(OCG.BNE * 32 + OCG.mPCR, OCG.Here() + 2 + 5);   (* BNE → a is neg *)
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 1);
    OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0FFFFH);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_LO);
    OCG.Rts;
    patch(p1);

  (* Same sign: compare hi magnitude *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7FFFH);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_TEMP);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_B_HI);
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 7FFFH);
    OCG.gen1(OCG.CMP * 32 + OCG.mDP, FP_TEMP);
    p1 := emitFwdBranch(OCG.BEQ);   (* BEQ → hi_equal *)

  (* Hi words differ: B < A means A > B (for positive) *)
    p2 := emitFwdBranch(OCG.BCC);   (* BCC → B < A (carry clear) *)
  (* B > A *)
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0FFFFH);
    OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
    patch(p2);
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 1);
  (* If negative, reverse *)
    OCG.gen1(OCG.BIT * 32 + OCG.mDP, FP_SIGN);
    p2 := emitFwdBranch(OCG.BPL);   (* BPL → store (positive, no reverse) *)
  (* Negate result *)
    OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
    OCG.gen1(OCG.INC * 32 + OCG.mAcc, 0);
    patch(p2);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_LO);
    OCG.Rts;
    patch(p1);   (* hi_equal *)

  (* Compare lo words *)
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, FP_A_LO);
    OCG.gen1(OCG.CMP * 32 + OCG.mDP, FP_B_LO);
    p1 := emitFwdBranch(OCG.BEQ);   (* BEQ → equal *)
    p2 := emitFwdBranch(OCG.BCC);   (* BCC → A < B *)
  (* A > B *)
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 1);
    OCG.gen1(OCG.BRA * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
    patch(p2);
  (* A < B *)
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0FFFFH);
  (* If negative, reverse *)
    OCG.gen1(OCG.BIT * 32 + OCG.mDP, FP_SIGN);
    p2 := emitFwdBranch(OCG.BPL);   (* BPL → store *)
    OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
    OCG.gen1(OCG.INC * 32 + OCG.mAcc, 0);
    patch(p2);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_LO);
    OCG.Rts;
    patch(p1);   (* equal *)
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, FP_A_LO);
    OCG.Rts;
  END emitFP_CMP;


  PROCEDURE EmitSubroutines*;
  BEGIN
    IF fpFixupCount[FP_FLOOR] > 0 THEN emitFP_FLOOR END;
    IF fpFixupCount[FP_FLT] > 0 THEN emitFP_FLT END;
    IF fpFixupCount[FP_ADD] > 0 THEN emitFP_ADD END;
    IF fpFixupCount[FP_MUL] > 0 THEN emitFP_MUL END;
    IF fpFixupCount[FP_DIV] > 0 THEN emitFP_DIV END;
    IF fpFixupCount[FP_CMP] > 0 THEN emitFP_CMP END
  END EmitSubroutines;

  PROCEDURE FixupCalls*;
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
  END FixupCalls;
END ORGFP.
