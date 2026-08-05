MODULE OCG; (* 65C816 instruction encoder.

   Self-hosted port of the C low-level emitter (65Tools/oc/src/cpu.h,
   codegen.c, gen_816.c). Owns the code buffer and program counter, the
   accumulator/index width flags (longa/longi), and the relocation list.
   ORG.Mod (the code generator) drives this via Gen(opcode, mode, v1, v2).

   Byte-for-byte faithful to gen_816.c: mode-driven operand widths, the
   longa/longi immediate distinction, BRA->BRL promotion, large
   stack-relative expansion, and JSR/JSL relocation recording. *)

  CONST
    maxCode* = 48000;
    CodeOrg = 0;             (* code starts at $0000 *)
    maxReloc* = 1024;

    (* addressing modes — same order as the C AddrMode enum *)
    mAbs* = 0; mAcc* = 1; mAbsX* = 2; mAbsY* = 3; mAbsL* = 4;
    mAbsLX* = 5; mAbsInd* = 6; mAbsIndX* = 7; mDP* = 8; mSDPI* = 9;
    mDPX* = 10; mDPY* = 11; mDPInd* = 12; mDPIndL* = 13; mImpl* = 14;
    mPCR* = 15; mPCRL* = 16; mFix* = 17; mAbsIndL* = 18; mBlock* = 19;
    mDPIndX* = 20; mDPIndY* = 21; mDPIndLY* = 22; mImm* = 23;
    mSR* = 24; mSRIY* = 25;

    (* opcodes (only those with encodings). Values are private to this
       module; ORG.Mod refers to them by name. *)
    ADC* = 0; AND* = 1; ASL* = 2; BCC* = 3; BCS* = 4; BEQ* = 5;
    BIT* = 6; BMI* = 7; BNE* = 8; BPL* = 9; BRA* = 10; BRK* = 11;
    BRL* = 12; BVC* = 13; BVS* = 14; CLC* = 15; CLD* = 16; CLI* = 17;
    CLV* = 18; CMP* = 19; COP* = 20; CPX* = 21; CPY* = 22; DEC* = 23;
    DEX* = 24; DEY* = 25; EOR* = 26; INC* = 27; INX* = 28; INY* = 29;
    JMP* = 30; JML* = 31; JSL* = 32; JSR* = 33; LDA* = 34; LDX* = 35;
    LDY* = 36; LSR* = 37; MVN* = 38; MVP* = 39; NOP* = 40; ORA* = 41;
    PEA* = 42; PEI* = 43; PER* = 44; PHA* = 45; PHB* = 46; PHD* = 47;
    PHK* = 48; PHP* = 49; PHX* = 50; PHY* = 51; PLA* = 52; PLB* = 53;
    PLD* = 54; PLP* = 55; PLX* = 56; PLY* = 57; REP* = 58; ROL* = 59;
    ROR* = 60; RTI* = 61; RTL* = 62; RTS* = 63; SBC* = 64; SEC* = 65;
    SED* = 66; SEI* = 67; SEP* = 68; STA* = 69; STP* = 70; STX* = 71;
    STY* = 72; STZ* = 73; TAX* = 74; TAY* = 75; TCD* = 76; TCS* = 77;
    TDC* = 78; TRB* = 79; TSB* = 80; TSC* = 81; TSX* = 82; TXA* = 83;
    TXS* = 84; TXY* = 85; TYA* = 86; TYX* = 87; WAI* = 88; WDM* = 89;
    XBA* = 90; XCE* = 91;

  VAR
    (* State is private (Oberon exports VARs read-only); ORG mutates it
       through the accessors below. The hot path — Gen — touches code/pc
       directly, so per-instruction emission stays a single call. *)
    code: ARRAY maxCode OF BYTE;
    pc: LONGINT;               (* code index = address (CodeOrg = 0) *)
    longa, longi: BOOLEAN;     (* 16-bit accumulator / index registers *)
    dpage, pbreg: LONGINT;
    reloc: ARRAY maxReloc OF LONGINT;
    relocC: INTEGER;

  (* --- byte emission --- *)

  PROCEDURE o(b: LONGINT);
  BEGIN code[pc - CodeOrg] := b MOD 100H; pc := pc + 1
  END o;

  PROCEDURE ob(op, v: LONGINT);      (* op + low byte *)
  BEGIN o(op); o(v)
  END ob;

  PROCEDURE ow(op, v: LONGINT);      (* op + word *)
  BEGIN o(op); o(v); o(v DIV 100H)
  END ow;

  PROCEDURE ol(op, v: LONGINT);      (* op + 24-bit *)
  BEGIN o(op); o(v); o(v DIV 100H); o(v DIV 10000H)
  END ol;

  PROCEDURE om(op, v: LONGINT; b: BOOLEAN);  (* op + byte, +high if b *)
  BEGIN o(op); o(v); IF b THEN o(v DIV 100H) END
  END om;

  PROCEDURE orel(op, v: LONGINT);    (* 8-bit PC-relative branch *)
    VAR r: LONGINT;
  BEGIN o(op); r := v - (pc + 1); o(r)
  END orel;

  PROCEDURE ofix(op, v: LONGINT);    (* forward-branch fixup chain (8-bit) *)
    VAR ch: LONGINT;
  BEGIN
    IF v = 0 THEN ow(op, 0)
    ELSE ch := v - pc; ow(op, ch MOD 100H)
    END
  END ofix;

  PROCEDURE ofixl(op, v: LONGINT);   (* forward BRL fixup chain (16-bit) *)
  BEGIN ow(op, v MOD 10000H)
  END ofixl;

  PROCEDURE omove(op, src, dst: LONGINT);
  BEGIN o(op); o(dst DIV 10000H); o(src DIV 10000H)
  END omove;

  PROCEDURE Byte*(b: LONGINT);
  BEGIN o(b)
  END Byte;

  PROCEDURE Word*(w: LONGINT);
  BEGIN o(w); o(w DIV 100H)
  END Word;

  PROCEDURE Long*(l: LONGINT);
  BEGIN o(l); o(l DIV 100H); o(l DIV 10000H); o(l DIV 1000000H)
  END Long;

  (* --- mode optimisations (codegen_gen) --- *)

  PROCEDURE isDP(addr: LONGINT): BOOLEAN;
  BEGIN RETURN (addr < 100H) OR ((addr - dpage) < 100H)
  END isDP;

  PROCEDURE isLongData(addr: LONGINT): BOOLEAN;
  BEGIN RETURN addr > 0FFFFH
  END isLongData;

  (* branch operand modes (a label): DP / Absolute / PC-relative *)
  PROCEDURE isBr(mode: LONGINT): BOOLEAN;
  BEGIN RETURN (mode = mDP) OR (mode = mAbs) OR (mode = mPCR)
  END isBr;

  (* Large stack-relative CMP: value1 > 255 expands to a DP-temp sequence. *)
  PROCEDURE cmpBigSR(v: LONGINT);
    VAR save: BOOLEAN;
  BEGIN
    ob(85H, 22H);                       (* STA $22 *)
    save := longa;
    IF ~longa THEN o(0C2H); o(20H); longa := TRUE END;   (* REP #$20 *)
    o(0DAH);                            (* PHX *)
    o(3BH);                            (* TSC *)
    o(18H);                            (* CLC *)
    o(69H); o(v + 2); o((v + 2) DIV 100H);   (* ADC #(off+2) *)
    o(0AAH);                            (* TAX *)
    o(0BFH); o(0); o(0); o(0);         (* LDA $000000,X *)
    ob(85H, 24H);                       (* STA $24 *)
    o(0FAH);                            (* PLX *)
    IF ~save THEN o(0E2H); o(20H); longa := FALSE END;   (* SEP #$20 *)
    ob(0A5H, 22H);                      (* LDA $22 *)
    ob(0C5H, 24H)                       (* CMP $24 *)
  END cmpBigSR;

  PROCEDURE ldaBigSR(v: LONGINT);
    VAR save: BOOLEAN;
  BEGIN
    save := longa;
    IF ~longa THEN o(0C2H); o(20H); longa := TRUE END;
    o(0DAH); o(3BH); o(18H);
    o(69H); o(v + 2); o((v + 2) DIV 100H);
    o(0AAH);
    IF ~save THEN o(0E2H); o(20H); longa := FALSE END;
    o(0BFH); o(0); o(0); o(0);
    o(0FAH)
  END ldaBigSR;

  PROCEDURE staBigSR(v: LONGINT);
    VAR save: BOOLEAN;
  BEGIN
    ob(85H, 42H);                       (* STA $42 *)
    save := longa;
    IF ~longa THEN o(0C2H); o(20H); longa := TRUE END;
    o(0DAH); o(3BH); o(18H);
    o(69H); o(v + 2); o((v + 2) DIV 100H);
    o(0AAH);
    IF ~save THEN o(0E2H); o(20H); longa := FALSE END;
    ob(0A5H, 42H);                      (* LDA $42 *)
    o(9FH); o(0); o(0); o(0);          (* STA $000000,X *)
    o(0FAH)
  END staBigSR;

  (* gen_816: emit one instruction. Faithful transcription. *)
  PROCEDURE gen(op, mode, v1, v2: LONGINT);
    VAR r, brl: LONGINT;
  BEGIN
    CASE op OF
      ADC:
        IF mode = mImm THEN om(69H, v1, longa)
        ELSIF mode = mAbs THEN ow(6DH, v1)
        ELSIF mode = mAbsL THEN ol(6FH, v1)
        ELSIF mode = mDP THEN ob(65H, v1)
        ELSIF mode = mDPInd THEN ob(72H, v1)
        ELSIF mode = mDPIndL THEN ob(67H, v1)
        ELSIF mode = mAbsX THEN ow(7DH, v1)
        ELSIF mode = mAbsLX THEN ol(7FH, v1)
        ELSIF mode = mAbsY THEN ow(79H, v1)
        ELSIF mode = mDPX THEN ob(75H, v1)
        ELSIF mode = mDPIndX THEN ob(61H, v1)
        ELSIF mode = mDPIndY THEN ob(71H, v1)
        ELSIF mode = mDPIndLY THEN ob(77H, v1)
        ELSIF mode = mSR THEN ob(63H, v1)
        ELSIF mode = mSRIY THEN ob(73H, v1)
        END
    | AND:
        IF mode = mImm THEN om(29H, v1, longa)
        ELSIF mode = mAbs THEN ow(2DH, v1)
        ELSIF mode = mAbsL THEN ol(2FH, v1)
        ELSIF mode = mDP THEN ob(25H, v1)
        ELSIF mode = mDPInd THEN ob(32H, v1)
        ELSIF mode = mDPIndL THEN ob(27H, v1)
        ELSIF mode = mAbsX THEN ow(3DH, v1)
        ELSIF mode = mAbsLX THEN ol(3FH, v1)
        ELSIF mode = mAbsY THEN ow(39H, v1)
        ELSIF mode = mDPX THEN ob(35H, v1)
        ELSIF mode = mDPIndX THEN ob(21H, v1)
        ELSIF mode = mDPIndY THEN ob(31H, v1)
        ELSIF mode = mDPIndLY THEN ob(37H, v1)
        ELSIF mode = mSR THEN ob(23H, v1)
        ELSIF mode = mSRIY THEN ob(33H, v1)
        END
    | ASL:
        IF (mode = mImpl) OR (mode = mAcc) THEN o(0AH)
        ELSIF mode = mAbs THEN ow(0EH, v1)
        ELSIF mode = mDP THEN ob(06H, v1)
        ELSIF mode = mAbsX THEN ow(1EH, v1)
        ELSIF mode = mDPX THEN ob(16H, v1)
        END
    | BCC:
        IF mode = mFix THEN ofix(90H, v1)
        ELSIF isBr(mode) THEN orel(90H, v1) END
    | BCS:
        IF mode = mFix THEN ofix(0B0H, v1)
        ELSIF isBr(mode) THEN orel(0B0H, v1) END
    | BEQ:
        IF mode = mFix THEN ofix(0F0H, v1)
        ELSIF isBr(mode) THEN orel(0F0H, v1) END
    | BIT:
        IF mode = mImm THEN om(89H, v1, longa)
        ELSIF mode = mAbs THEN ow(2CH, v1)
        ELSIF mode = mDP THEN ob(24H, v1)
        ELSIF mode = mAbsX THEN ow(3CH, v1)
        ELSIF mode = mDPX THEN ob(34H, v1)
        END
    | BMI:
        IF mode = mFix THEN ofix(30H, v1)
        ELSIF isBr(mode) THEN orel(30H, v1) END
    | BNE:
        IF mode = mFix THEN ofix(0D0H, v1)
        ELSIF isBr(mode) THEN orel(0D0H, v1) END
    | BPL:
        IF mode = mFix THEN ofix(10H, v1)
        ELSIF isBr(mode) THEN orel(10H, v1) END
    | BRA:
        IF mode = mFix THEN ofix(80H, v1)
        ELSIF isBr(mode) THEN
          r := v1 - (pc + 1);
          IF (r > 127) OR (r < -128) THEN
            brl := v1 - (pc + 3); ow(82H, brl)
          ELSE orel(80H, v1)
          END
        END
    | BRK:
        IF mode = mImpl THEN ob(00H, 00H)
        ELSIF mode = mImm THEN ob(00H, v1) END
    | BRL:
        IF mode = mFix THEN ofixl(82H, v1)
        ELSIF isBr(mode) THEN r := v1 - (pc + 3); ow(82H, r) END
    | BVC:
        IF isBr(mode) THEN orel(50H, v1) END
    | BVS:
        IF isBr(mode) THEN orel(70H, v1) END
    | CLC: IF mode = mImpl THEN o(18H) END
    | CLD: IF mode = mImpl THEN o(0D8H) END
    | CLI: IF mode = mImpl THEN o(58H) END
    | CLV: IF mode = mImpl THEN o(0B8H) END
    | CMP:
        IF mode = mImm THEN om(0C9H, v1, longa)
        ELSIF mode = mAbs THEN ow(0CDH, v1)
        ELSIF mode = mAbsL THEN ol(0CFH, v1)
        ELSIF mode = mDP THEN ob(0C5H, v1)
        ELSIF mode = mDPInd THEN ob(0D2H, v1)
        ELSIF mode = mDPIndL THEN ob(0C7H, v1)
        ELSIF mode = mAbsX THEN ow(0DDH, v1)
        ELSIF mode = mAbsLX THEN ol(0DFH, v1)
        ELSIF mode = mAbsY THEN ow(0D9H, v1)
        ELSIF mode = mDPX THEN ob(0D5H, v1)
        ELSIF mode = mDPIndX THEN ob(0C1H, v1)
        ELSIF mode = mDPIndY THEN ob(0D1H, v1)
        ELSIF mode = mDPIndLY THEN ob(0D7H, v1)
        ELSIF mode = mSR THEN
          IF v1 > 255 THEN cmpBigSR(v1) ELSE ob(0C3H, v1) END
        ELSIF mode = mSRIY THEN ob(0D3H, v1)
        END
    | COP:
        IF mode = mImm THEN ob(02H, v1) END
    | CPX:
        IF mode = mImm THEN om(0E0H, v1, longi)
        ELSIF mode = mAbs THEN ow(0ECH, v1)
        ELSIF mode = mDP THEN ob(0E4H, v1)
        END
    | CPY:
        IF mode = mImm THEN om(0C0H, v1, longi)
        ELSIF mode = mAbs THEN ow(0CCH, v1)
        ELSIF mode = mDP THEN ob(0C4H, v1)
        END
    | DEC:
        IF (mode = mAcc) OR (mode = mImpl) THEN o(3AH)
        ELSIF mode = mAbs THEN ow(0CEH, v1)
        ELSIF mode = mDP THEN ob(0C6H, v1)
        ELSIF mode = mAbsX THEN ow(0DEH, v1)
        ELSIF mode = mDPX THEN ob(0D6H, v1)
        END
    | DEX: IF mode = mImpl THEN o(0CAH) END
    | DEY: IF mode = mImpl THEN o(88H) END
    | EOR:
        IF mode = mImm THEN om(49H, v1, longa)
        ELSIF mode = mAbs THEN ow(4DH, v1)
        ELSIF mode = mAbsL THEN ol(4FH, v1)
        ELSIF mode = mDP THEN ob(45H, v1)
        ELSIF mode = mDPInd THEN ob(52H, v1)
        ELSIF mode = mDPIndL THEN ob(47H, v1)
        ELSIF mode = mAbsX THEN ow(5DH, v1)
        ELSIF mode = mAbsLX THEN ol(5FH, v1)
        ELSIF mode = mAbsY THEN ow(59H, v1)
        ELSIF mode = mDPX THEN ob(55H, v1)
        ELSIF mode = mDPIndX THEN ob(41H, v1)
        ELSIF mode = mDPIndY THEN ob(51H, v1)
        ELSIF mode = mDPIndLY THEN ob(57H, v1)
        ELSIF mode = mSR THEN ob(43H, v1)
        ELSIF mode = mSRIY THEN ob(53H, v1)
        END
    | INC:
        IF (mode = mAcc) OR (mode = mImpl) THEN o(1AH)
        ELSIF mode = mAbs THEN ow(0EEH, v1)
        ELSIF mode = mDP THEN ob(0E6H, v1)
        ELSIF mode = mAbsX THEN ow(0FEH, v1)
        ELSIF mode = mDPX THEN ob(0F6H, v1)
        END
    | INX: IF mode = mImpl THEN o(0E8H) END
    | INY: IF mode = mImpl THEN o(0C8H) END
    | JMP:
        IF (mode = mDP) OR (mode = mAbs) THEN ow(4CH, v1)
        ELSIF mode = mAbsInd THEN ow(6CH, v1)
        ELSIF mode = mAbsIndX THEN ow(7CH, v1)
        ELSIF mode = mAbsL THEN ol(5CH, v1)
        ELSIF mode = mAbsIndL THEN ow(0DCH, v1)
        END
    | JML:
        IF (mode = mDP) OR (mode = mAbs) OR (mode = mAbsL) THEN ol(5CH, v1)
        ELSIF (mode = mAbsInd) OR (mode = mAbsIndL) THEN ow(0DCH, v1)
        END
    | JSL:
        IF (mode = mDP) OR (mode = mAbs) OR (mode = mAbsL) THEN
          reloc[relocC] := pc; relocC := relocC + 1; ol(22H, v1)
        END
    | JSR:
        IF (mode = mDP) OR (mode = mAbs) THEN
          reloc[relocC] := pc; relocC := relocC + 1; ow(20H, v1)
        ELSIF mode = mAbsIndX THEN ow(0FCH, v1)
        ELSIF mode = mAbsL THEN
          reloc[relocC] := pc; relocC := relocC + 1; ol(22H, v1)
        END
    | LDA:
        IF mode = mImm THEN om(0A9H, v1, longa)
        ELSIF mode = mAbs THEN ow(0ADH, v1)
        ELSIF mode = mAbsL THEN ol(0AFH, v1)
        ELSIF mode = mDP THEN ob(0A5H, v1)
        ELSIF (mode = mAbsInd) OR (mode = mDPInd) THEN ob(0B2H, v1)
        ELSIF mode = mDPIndL THEN ob(0A7H, v1)
        ELSIF mode = mAbsX THEN ow(0BDH, v1)
        ELSIF mode = mAbsLX THEN ol(0BFH, v1)
        ELSIF mode = mAbsY THEN ow(0B9H, v1)
        ELSIF mode = mDPX THEN ob(0B5H, v1)
        ELSIF mode = mDPIndX THEN ob(0A1H, v1)
        ELSIF mode = mDPIndY THEN ob(0B1H, v1)
        ELSIF mode = mDPIndLY THEN ob(0B7H, v1)
        ELSIF mode = mSR THEN
          IF v1 > 255 THEN ldaBigSR(v1) ELSE ob(0A3H, v1) END
        ELSIF mode = mSRIY THEN ob(0B3H, v1)
        END
    | LDX:
        IF mode = mImm THEN om(0A2H, v1, longi)
        ELSIF mode = mAbs THEN ow(0AEH, v1)
        ELSIF mode = mDP THEN ob(0A6H, v1)
        ELSIF mode = mAbsY THEN ow(0BEH, v1)
        ELSIF mode = mDPY THEN ob(0B6H, v1)
        END
    | LDY:
        IF mode = mImm THEN om(0A0H, v1, longi)
        ELSIF mode = mAbs THEN ow(0ACH, v1)
        ELSIF mode = mDP THEN ob(0A4H, v1)
        ELSIF mode = mAbsX THEN ow(0BCH, v1)
        ELSIF mode = mDPX THEN ob(0B4H, v1)
        END
    | LSR:
        IF (mode = mAcc) OR (mode = mImpl) THEN o(4AH)
        ELSIF mode = mAbs THEN ow(4EH, v1)
        ELSIF mode = mDP THEN ob(46H, v1)
        ELSIF mode = mAbsX THEN ow(5EH, v1)
        ELSIF mode = mDPX THEN ob(56H, v1)
        END
    | MVN:
        IF mode = mBlock THEN omove(54H, v2, v1) END
    | MVP:
        IF mode = mBlock THEN omove(44H, v2, v1) END
    | NOP: IF mode = mImpl THEN o(0EAH) END
    | ORA:
        IF mode = mImm THEN om(09H, v1, longa)
        ELSIF mode = mAbs THEN ow(0DH, v1)
        ELSIF mode = mAbsL THEN ol(0FH, v1)
        ELSIF mode = mDP THEN ob(05H, v1)
        ELSIF mode = mDPInd THEN ob(12H, v1)
        ELSIF mode = mDPIndL THEN ob(07H, v1)
        ELSIF mode = mAbsX THEN ow(1DH, v1)
        ELSIF mode = mAbsLX THEN ol(1FH, v1)
        ELSIF mode = mAbsY THEN ow(19H, v1)
        ELSIF mode = mDPX THEN ob(15H, v1)
        ELSIF mode = mDPIndX THEN ob(01H, v1)
        ELSIF mode = mDPIndY THEN ob(11H, v1)
        ELSIF mode = mDPIndLY THEN ob(17H, v1)
        ELSIF mode = mSR THEN ob(03H, v1)
        ELSIF mode = mSRIY THEN ob(13H, v1)
        END
    | PEA:
        IF (mode = mImm) OR (mode = mAbs) THEN ow(0F4H, v1) END
    | PEI:
        IF mode = mDPInd THEN ob(0D4H, v1) END
    | PER:
        IF (mode = mImm) OR (mode = mDP) OR (mode = mAbs) THEN ow(62H, v1) END
    | PHA: IF mode = mImpl THEN o(48H) END
    | PHB: IF mode = mImpl THEN o(8BH) END
    | PHD: IF mode = mImpl THEN o(0BH) END
    | PHK: IF mode = mImpl THEN o(4BH) END
    | PHP: IF mode = mImpl THEN o(08H) END
    | PHX: IF mode = mImpl THEN o(0DAH) END
    | PHY: IF mode = mImpl THEN o(5AH) END
    | PLA: IF mode = mImpl THEN o(68H) END
    | PLB: IF mode = mImpl THEN o(0ABH) END
    | PLD: IF mode = mImpl THEN o(2BH) END
    | PLP: IF mode = mImpl THEN o(28H) END
    | PLX: IF mode = mImpl THEN o(0FAH) END
    | PLY: IF mode = mImpl THEN o(7AH) END
    | REP:
        IF mode = mImm THEN ob(0C2H, v1) END
    | ROL:
        IF (mode = mAcc) OR (mode = mImpl) THEN o(2AH)
        ELSIF mode = mAbs THEN ow(2EH, v1)
        ELSIF mode = mDP THEN ob(26H, v1)
        ELSIF mode = mAbsX THEN ow(3EH, v1)
        ELSIF mode = mDPX THEN ob(36H, v1)
        END
    | ROR:
        IF (mode = mAcc) OR (mode = mImpl) THEN o(6AH)
        ELSIF mode = mAbs THEN ow(6EH, v1)
        ELSIF mode = mDP THEN ob(66H, v1)
        ELSIF mode = mAbsX THEN ow(7EH, v1)
        ELSIF mode = mDPX THEN ob(76H, v1)
        END
    | RTI: IF mode = mImpl THEN o(40H) END
    | RTL: IF mode = mImpl THEN o(6BH) END
    | RTS: IF mode = mImpl THEN o(60H) END
    | SBC:
        IF mode = mImm THEN om(0E9H, v1, longa)
        ELSIF mode = mAbs THEN ow(0EDH, v1)
        ELSIF mode = mAbsL THEN ol(0EFH, v1)
        ELSIF mode = mDP THEN ob(0E5H, v1)
        ELSIF mode = mDPInd THEN ob(0F2H, v1)
        ELSIF mode = mDPIndL THEN ob(0E7H, v1)
        ELSIF mode = mAbsX THEN ow(0FDH, v1)
        ELSIF mode = mAbsLX THEN ol(0FFH, v1)
        ELSIF mode = mAbsY THEN ow(0F9H, v1)
        ELSIF mode = mDPX THEN ob(0F5H, v1)
        ELSIF mode = mDPIndX THEN ob(0E1H, v1)
        ELSIF mode = mDPIndY THEN ob(0F1H, v1)
        ELSIF mode = mDPIndLY THEN ob(0F7H, v1)
        ELSIF mode = mSR THEN ob(0E3H, v1)
        ELSIF mode = mSRIY THEN ob(0F3H, v1)
        END
    | SEC: IF mode = mImpl THEN o(38H) END
    | SED: IF mode = mImpl THEN o(0F8H) END
    | SEI: IF mode = mImpl THEN o(78H) END
    | SEP:
        IF mode = mImm THEN ob(0E2H, v1) END
    | STA:
        IF mode = mAbs THEN ow(8DH, v1)
        ELSIF mode = mAbsL THEN ol(8FH, v1)
        ELSIF mode = mDP THEN ob(85H, v1)
        ELSIF mode = mDPInd THEN ob(92H, v1)
        ELSIF mode = mDPIndL THEN ob(87H, v1)
        ELSIF mode = mAbsX THEN ow(9DH, v1)
        ELSIF mode = mAbsLX THEN ol(9FH, v1)
        ELSIF mode = mAbsY THEN ow(99H, v1)
        ELSIF mode = mDPX THEN ob(95H, v1)
        ELSIF mode = mDPIndX THEN ob(81H, v1)
        ELSIF mode = mDPIndY THEN ob(91H, v1)
        ELSIF mode = mDPIndLY THEN ob(97H, v1)
        ELSIF mode = mSR THEN
          IF v1 > 255 THEN staBigSR(v1) ELSE ob(83H, v1) END
        ELSIF mode = mSRIY THEN ob(93H, v1)
        END
    | STP: IF mode = mImpl THEN o(0DBH) END
    | STX:
        IF mode = mAbs THEN ow(8EH, v1)
        ELSIF mode = mDP THEN ob(86H, v1)
        ELSIF mode = mDPY THEN ow(96H, v1)
        END
    | STY:
        IF mode = mAbs THEN ow(8CH, v1)
        ELSIF mode = mDP THEN ob(84H, v1)
        ELSIF mode = mDPX THEN ob(94H, v1)
        END
    | STZ:
        IF mode = mAbs THEN ow(9CH, v1)
        ELSIF mode = mDP THEN ob(64H, v1)
        ELSIF mode = mAbsX THEN ow(9EH, v1)
        ELSIF mode = mDPX THEN ow(74H, v1)
        END
    | TAX: IF mode = mImpl THEN o(0AAH) END
    | TAY: IF mode = mImpl THEN o(0A8H) END
    | TCD: IF mode = mImpl THEN o(5BH) END
    | TCS: IF mode = mImpl THEN o(1BH) END
    | TDC: IF mode = mImpl THEN o(7BH) END
    | TRB:
        IF mode = mAbs THEN ow(1CH, v1)
        ELSIF mode = mDP THEN ob(14H, v1) END
    | TSB:
        IF mode = mAbs THEN ow(0CH, v1)
        ELSIF mode = mDP THEN ob(04H, v1) END
    | TSC: IF mode = mImpl THEN o(3BH) END
    | TSX: IF mode = mImpl THEN o(0BAH) END
    | TXA: IF mode = mImpl THEN o(8AH) END
    | TXS: IF mode = mImpl THEN o(9AH) END
    | TXY: IF mode = mImpl THEN o(9BH) END
    | TYA: IF mode = mImpl THEN o(98H) END
    | TYX: IF mode = mImpl THEN o(0BBH) END
    | WAI: IF mode = mImpl THEN o(0CBH) END
    | WDM:
        IF mode = mImm THEN ob(42H, v1) END
    | XBA: IF mode = mImpl THEN o(0EBH) END
    | XCE: IF mode = mImpl THEN o(0FBH) END
    END
  END gen;

  (* codegen_gen: apply mode optimisations, then emit. *)
  PROCEDURE Gen*(op, mode, v1, v2: LONGINT);
  BEGIN
    IF mode = mAbs THEN
      IF isDP(v1) THEN mode := mDP END
    ELSIF mode = mAbsY THEN
      IF isDP(v1) THEN mode := mDPY END
    ELSIF mode = mAbsIndX THEN
      IF isDP(v1) THEN mode := mDPIndX END
    ELSIF mode = mAbsInd THEN
      IF isLongData(v1) THEN mode := mAbsIndL END
    END;
    gen(op, mode, v1, v2)
  END Gen;

  (* --- accessors for ORG --- *)
  PROCEDURE Here*(): LONGINT;         BEGIN RETURN pc END Here;
  PROCEDURE SetPc*(p: LONGINT);       BEGIN pc := p END SetPc;
  PROCEDURE Get*(at: LONGINT): INTEGER; BEGIN RETURN code[at] END Get;
  PROCEDURE Patch*(at, b: LONGINT);   BEGIN code[at] := b MOD 100H END Patch;
  PROCEDURE LongA*(): BOOLEAN;        BEGIN RETURN longa END LongA;
  PROCEDURE SetLongA*(b: BOOLEAN);    BEGIN longa := b END SetLongA;
  PROCEDURE LongI*(): BOOLEAN;        BEGIN RETURN longi END LongI;
  PROCEDURE SetLongI*(b: BOOLEAN);    BEGIN longi := b END SetLongI;
  PROCEDURE SetDPage*(d: LONGINT);    BEGIN dpage := d END SetDPage;
  PROCEDURE SetPBReg*(p: LONGINT);    BEGIN pbreg := p END SetPBReg;
  PROCEDURE RelCount*(): INTEGER;     BEGIN RETURN relocC END RelCount;
  PROCEDURE Rel*(i: INTEGER): LONGINT; BEGIN RETURN reloc[i] END Rel;
  PROCEDURE AddRel*(p: LONGINT);
  BEGIN reloc[relocC] := p; relocC := relocC + 1
  END AddRel;

  PROCEDURE Init*;
  BEGIN
    pc := CodeOrg; longa := TRUE; longi := TRUE;
    dpage := 0; pbreg := 0; relocC := 0
  END Init;

BEGIN
  pc := CodeOrg; longa := TRUE; longi := TRUE;
  dpage := 0; pbreg := 0; relocC := 0
END OCG.
