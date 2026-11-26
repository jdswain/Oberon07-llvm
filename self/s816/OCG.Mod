MODULE OCG; (* 65C816 instruction encoder.

   Self-hosted port of the C low-level emitter (65Tools/oc/src/cpu.h,
   codegen.c, gen_816.c). Owns the code buffer and program counter, the
   accumulator/index width flags (longa/longi), and the relocation list.
   ORG.Mod (the code generator) drives this via Gen(opcode, mode, v1, v2).

   Byte-for-byte faithful to gen_816.c: mode-driven operand widths, the
   longa/longi immediate distinction, BRA->BRL promotion, large
   stack-relative expansion, and JSR/JSL relocation recording. *)

  CONST
    (* A module's code loads into one 64K bank (code starts at bank offset 0).
       Cap it just under the bank so the loader's per-module header/tables have
       room — 65024 = 65536 - 512. Modules that overflow this abort cleanly
       ("program too large"); the two that do today, ORG (~117K) and ORP
       (~71K), are too big for one bank and need splitting, not a larger cap.
       maxReloc is sized for a near-full-bank module (reloc count tracks code
       size at roughly code/40; the largest module that fits, ORB, uses 374).

       SMALL model is capped at maxCodeSmall = 65024 (= 65536 - 512, leaving
       the loader's per-module header/tables room in the bank): intra-module
       calls are JSR (16-bit), so the whole module must sit in one bank. A
       LARGE module (MODULE m LARGE) uses JSL for internal calls and may fill
       maxCode. Its forward-branch fixup chain links are stored RELATIVE (see
       ofixl), so they survive a >64K code image; branch DISTANCES stay <32K
       either way (every branch is intra-procedure, well within BRL's +/-32K
       reach). On-target the compiler will hold `code` as bank-sized chunks
       (all access is funnelled through o/Get/Patch); today it runs on the
       host, where a flat 128K array is fine. *)
    maxCodeSmall = 65024;    (* SMALL-model code cap (one bank) *)
    maxCode* = 131072;       (* code-buffer size = LARGE-model cap (2 banks) *)
    CodeOrg = 0;             (* code starts at $0000 *)
    maxReloc* = 4096;
    (* code is held in chunks on the heap: a 65C816 module's variables are
       in bank 0, and an array is indexed within a bank *)
    ChunkSize = 8000H; maxChunks = 4;   (* maxCode DIV ChunkSize *)
    (* the code generator's registers, words of the direct page (ORGI.RegAddr) *)
    RegLo = 2; RegHi = 1FH;
    maxHeld = 8;
    maxSites = 2048;   (* a procedure's branches, PERs and JMPs, for Relax *)

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
    (* the core's extension after WDM (xops; Verilog65C816's docs/65C832.md):
       a multiply or divide is $42 and the opcode of an ADC (MUL), AND
       (UML), CMP (DIV) or EOR (UDV), X: the product's high word or the
       remainder; ASR #n, A's shift with its sign, has no opcode of its own *)
    xMUL* = ADC; xUML* = AND; xDIV* = CMP; xUDV* = EOR; ASR* = 92;

  TYPE
    Chunk = POINTER TO ChunkDesc;
    ChunkDesc = RECORD b: ARRAY ChunkSize OF BYTE END;
    Relocs = POINTER TO RelocsDesc;
    RelocsDesc = RECORD r: ARRAY maxReloc OF LONGINT END;
    (* an instruction the peephole holds back, its A and index widths *)
    HeldInsn = RECORD op, mode, v1, v2: LONGINT; la, li: BOOLEAN END;
    (* Relax's: each site's place and target before the move, what is done
       to it (0 nothing, 1 merged with the BRL after it, 2 made a BRA, 3
       merged away), the targets sorted, and the bytes left out: where, and
       how many up to there *)
    Sites = POINTER TO SitesDesc;
    SitesDesc = RECORD
      at, to, tg, dpos: ARRAY maxSites OF LONGINT;
      dcum: ARRAY maxSites OF INTEGER;
      act: ARRAY maxSites OF BYTE
    END;

  VAR
    (* State is private (Oberon exports VARs read-only); ORG mutates it
       through the accessors below. The hot path — Gen — touches code/pc
       directly, so per-instruction emission stays a single call. *)
    code: ARRAY maxChunks OF Chunk;   (* allocated as they are reached *)
    pc: LONGINT;               (* code index = address (CodeOrg = 0) *)
    codeLimit: LONGINT;        (* active code cap: maxCodeSmall, or ~maxCode in LARGE *)
    longa, longi: BOOLEAN;     (* 16-bit accumulator / index registers *)
    dpage, pbreg: LONGINT;
    reloc: Relocs;
    relocC: INTEGER;
    fault: BOOLEAN;            (* a fixed buffer (code/reloc) overflowed *)
    xops*: BOOLEAN;            (* -x: code for the core with its extension after WDM *)
    stock*: BOOLEAN;           (* -816: code for a stock 65C816, its direct page and stack in bank 0 *)
    (* the peephole (emit): the instructions held back after a store to a
       register, held[0] that store, to pend; A's register (-1: none), and
       whether N and Z are A's; the furthest place a branch was emitted
       to ahead, by its bytes *)
    peep*: BOOLEAN;            (* off: -O0 *)
    held: ARRAY maxHeld OF HeldInsn;
    nheld: INTEGER;
    pend, aReg, fwdMax: LONGINT;
    nzA: BOOLEAN;
    (* each opcode's class, for the peephole: a an ALU result in A (N Z
       A's), l LDA, s a shift or INC/DEC, S STA, z STZ STX STY, t TSB TRB,
       n neither A nor N Z, c a branch on a condition, x N Z another's
       (an index's, a compare's), r REP SEP XBA, B a jump, a call, a return
       or the like; and each mode's: h no memory, d the direct page's, x
       the direct page indexed, s the stack's, - another *)
    cls: ARRAY 96 OF CHAR;
    mcls: ARRAY 28 OF CHAR;
    (* the procedure being compiled: its first place, its sites (Relax) *)
    relax*: BOOLEAN;           (* off: -O0 *)
    st: Sites;
    nsite, ndel: INTEGER;
    sitesFull: BOOLEAN;
    relaxFrom: LONGINT;
    relocFrom: INTEGER;        (* the procedure's first relocation *)
    movedFrom: LONGINT;        (* where the code Relax last closed up began *)

  (* --- byte emission --- *)

  (* Bounds-checked so a module larger than the fixed code buffer sets the
     fault flag instead of writing past `code` (which segfaulted the
     self-compile of the big ORG module). pc stays monotonic so branch
     offsets remain consistent; the fault makes Close refuse to emit. *)
  (* code[at] := b, its chunk allocated (and zeroed) when first reached *)
  PROCEDURE put(at, b: LONGINT);
    VAR k, i: LONGINT;
  BEGIN k := at DIV ChunkSize;
    IF code[k] = NIL THEN NEW(code[k]);
      FOR i := 0 TO ChunkSize - 1 DO code[k].b[i] := 0 END
    END;
    code[k].b[at MOD ChunkSize] := b MOD 100H
  END put;

  PROCEDURE o(b: LONGINT);
  BEGIN
    IF pc - CodeOrg < codeLimit THEN put(pc - CodeOrg, b)
    ELSE fault := TRUE
    END;
    pc := pc + 1
  END o;

  (* Bounds-checked relocation append — the reloc table is fixed-size, and a
     module with more module/import calls than fit was the actual segfault
     (an out-of-bounds LONGINT store in gen). Overflow sets fault. *)
  PROCEDURE addReloc(p: LONGINT);
  BEGIN
    IF relocC < maxReloc THEN reloc.r[relocC] := p; relocC := relocC + 1
    ELSE fault := TRUE
    END
  END addReloc;

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

  (* a branch, PER or JMP at pc, for Relax *)
  PROCEDURE site;
  BEGIN
    IF nsite < maxSites THEN st.at[nsite] := pc; nsite := nsite + 1 ELSE sitesFull := TRUE END
  END site;

  (* a branch or jump to v, a place ahead by its bytes: no peephole there *)
  PROCEDURE ahead(v, len: LONGINT);
  BEGIN IF (v > pc + len) & (v > fwdMax) THEN fwdMax := v END
  END ahead;

  PROCEDURE orel(op, v: LONGINT);    (* 8-bit PC-relative branch *)
    VAR r: LONGINT;
  BEGIN ahead(v, 2); site; o(op); r := v - (pc + 1); o(r)
  END orel;

  PROCEDURE ofix(op, v: LONGINT);    (* forward-branch fixup chain (8-bit) *)
    VAR ch: LONGINT;
  BEGIN site;
    IF v = 0 THEN ow(op, 0)
    ELSE ch := v - pc; ow(op, ch MOD 100H)
    END
  END ofix;

  PROCEDURE ofixl(op, v: LONGINT);   (* forward BRL fixup chain *)
    VAR ch: LONGINT;
  BEGIN
    (* Store the link RELATIVE to this operand (v = previous site's operand
       position, this operand is at pc+1). Intra-procedure, so |ch| < 32K fits
       16 bits even when the absolute positions exceed 64K. v = 0 is the
       empty/end sentinel. *)
    site;
    IF v = 0 THEN ow(op, 0)
    ELSE ch := v - (pc + 1); ow(op, ch MOD 10000H)
    END
  END ofixl;

  PROCEDURE omove(op, src, dst: LONGINT);
  BEGIN o(op); o(dst DIV 10000H); o(src DIV 10000H)
  END omove;

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

  (* A local beyond the reach of d,S (v > 255): X pushed, then X := its
     offset from the direct page, for dp,X. With the banked direct page
     and stack (WDM #$B1) both are in D's bank, the direct page at
     Lo(D) * 100H, so X := S + v - Lo(D) * 100H and LDA $00,X reaches the
     stack's bank, as a local's address does (ORG.stackBank). Not
     $000000,X: that is bank 0, and the kernel's variables are there. On a
     stock 65C816 (-816) both are in bank 0, the direct page at D: X := S
     + v - D. 16-bit A, which is lost. *)
  PROCEDURE bigX(v: LONGINT);
  BEGIN
    o(0DAH);                            (* PHX *)
    o(7BH);                             (* TDC *)
    IF ~stock THEN
      o(29H); o(0FFH); o(0);            (* AND #$00FF *)
      o(0EBH)                           (* XBA: Lo(D) * 100H *)
    END;
    o(49H); o(0FFH); o(0FFH);           (* EOR #$FFFF *)
    o(1AH);                             (* INC A: its negative *)
    o(48H);                             (* PHA *)
    o(3BH);                             (* TSC *)
    o(18H);                             (* CLC *)
    o(63H); o(1);                       (* ADC 1,S *)
    o(18H);                             (* CLC: S above the page carried *)
    o(69H); o(v + 4); o((v + 4) DIV 100H);   (* ADC #(v + 4): S was 4 more *)
    o(0AAH);                            (* TAX *)
    o(68H)                              (* PLA *)
  END bigX;

  (* Large stack-relative CMP: value1 > 255 expands to a DP-temp sequence. *)
  PROCEDURE cmpBigSR(v: LONGINT);
    VAR save: BOOLEAN;
  BEGIN
    ob(85H, 22H);                       (* STA $22 *)
    save := longa;
    IF ~longa THEN o(0C2H); o(20H); longa := TRUE END;   (* REP #$20 *)
    bigX(v);
    o(0B5H); o(0);                      (* LDA $00,X *)
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
    bigX(v);
    IF ~save THEN o(0E2H); o(20H); longa := FALSE END;
    o(0B5H); o(0);                      (* LDA $00,X *)
    o(0FAH)                             (* PLX *)
  END ldaBigSR;

  PROCEDURE staBigSR(v: LONGINT);
    VAR save: BOOLEAN;
  BEGIN
    ob(85H, 0);                         (* STA $00, free: SB is at $42 *)
    save := longa;
    IF ~longa THEN o(0C2H); o(20H); longa := TRUE END;
    bigX(v);
    IF ~save THEN o(0E2H); o(20H); longa := FALSE END;
    ob(0A5H, 0);                        (* LDA $00 *)
    o(95H); o(0);                       (* STA $00,X *)
    o(0FAH)                             (* PLX *)
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
          (* the offset counts from the end of the two-byte BRA. (The C
             original tested v1 - (pc + 1), so a branch of exactly -129
             was emitted as BRA with the offset wrapped to +127.) *)
          r := v1 - (pc + 2);
          IF (r > 127) OR (r < -128) THEN
            ahead(v1, 3); site; brl := v1 - (pc + 3); ow(82H, brl)
          ELSE orel(80H, v1)
          END
        END
    | BRK:
        IF mode = mImpl THEN ob(00H, 00H)
        ELSIF mode = mImm THEN ob(00H, v1) END
    | BRL:
        IF mode = mFix THEN ofixl(82H, v1)
        ELSIF isBr(mode) THEN ahead(v1, 3); site; r := v1 - (pc + 3); ow(82H, r) END
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
        IF (mode = mDP) OR (mode = mAbs) THEN ahead(v1, 3); site; ow(4CH, v1)
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
          addReloc(pc); ol(22H, v1)
        END
    | JSR:
        IF (mode = mDP) OR (mode = mAbs) THEN
          addReloc(pc); ow(20H, v1)
        ELSIF mode = mAbsIndX THEN ow(0FCH, v1)
        ELSIF mode = mAbsL THEN
          addReloc(pc); ol(22H, v1)
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
        IF (mode = mImm) OR (mode = mDP) OR (mode = mAbs) THEN
          (* a PER the loader fills (an import's address) is not relative *)
          IF (relocC = 0) OR (reloc.r[relocC - 1] # pc) THEN site END;
          ow(62H, v1)
        END
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

  (* --- the peephole: a store to a register held back ---

     The code generator's registers are words of the direct page, RegLo
     to RegHi, and a value goes through them: LDA x, STA r, then LDA r
     for what is done with it. A store to a register is held back here,
     with what follows it, until something reads the register or the
     held instructions must be where they are, then emitted as it was:
     the instructions are never reordered, only these left out:

       an LDA r while A is r's value and N and Z are A's: A and the
       flags are as the LDA would leave them;

       the held store, when the register is stored again before
       anything has read it (in between no branch, no label: a label is
       Here's), or when the code generator says the register is free
       (Dead: a statement's end).

     A branch to a place computed ahead, Here() + n (a skip over the
     next instructions), counts their bytes, so up to that place nothing
     is held or left out (fwdMax). *)

  PROCEDURE phys(op, mode, v1, v2: LONGINT; la, li: BOOLEAN);
    VAR sa, si: BOOLEAN;
  BEGIN sa := longa; si := longi; longa := la; longi := li;
    gen(op, mode, v1, v2);
    longa := sa; longi := si
  END phys;

  PROCEDURE isReg(v: LONGINT): BOOLEAN;
  BEGIN RETURN (v >= RegLo) & (v <= RegHi)
  END isReg;

  (* the held instructions from k on emitted, held[0..k-1] left out *)
  PROCEDURE release(k: INTEGER);
  BEGIN
    WHILE k < nheld DO
      phys(held[k].op, held[k].mode, held[k].v1, held[k].v2, held[k].la, held[k].li); k := k + 1
    END;
    nheld := 0; pend := -1
  END release;

  PROCEDURE Flush*;
  BEGIN IF nheld > 0 THEN release(0) END
  END Flush;

  (* the registers at lo and above are free: a held store to one left out *)
  PROCEDURE Dead*(lo: LONGINT);
  BEGIN
    IF (nheld > 0) & (pend >= lo) THEN release(1) END;
    IF aReg >= lo THEN aReg := -1 END
  END Dead;

  (* the instruction may read or write the direct page's p and p + 1 *)
  PROCEDURE touches(mode, v1, p: LONGINT): BOOLEAN;
    VAR c: CHAR;
  BEGIN c := mcls[mode]
    RETURN (c = "d") & (v1 >= p - 2) & (v1 <= p + 1) OR (c = "x")
  END touches;

  (* an instruction that can wait after a held store: no branch, no call,
     the direct page or the stack its only memory (d,S near) *)
  PROCEDURE holdable(op, mode, v1: LONGINT): BOOLEAN;
    VAR c, m: CHAR;
  BEGIN c := cls[op]; m := mcls[mode]
    RETURN (c # "c") & (c # "B") & ((m = "h") OR (m = "d") OR (m = "s") & (v1 <= 255))
  END holdable;

  (* what the instruction does to A and to N and Z, by its class (cls) *)
  PROCEDURE track(op, mode, v1: LONGINT);
    VAR c: CHAR;
  BEGIN c := cls[op];
    IF c = "l" THEN
      IF (mode = mDP) & longa & isReg(v1) THEN aReg := v1 ELSE aReg := -1 END;
      nzA := TRUE
    ELSIF c = "a" THEN aReg := -1; nzA := TRUE
    ELSIF c = "s" THEN
      IF (mode = mAcc) OR (mode = mImpl) THEN aReg := -1; nzA := TRUE
      ELSE
        IF (aReg >= 0) & touches(mode, v1, aReg) THEN aReg := -1 END;
        nzA := FALSE
      END
    ELSIF c = "S" THEN
      IF (mode = mDP) & longa & (v1 = aReg) THEN (* A is still the register's *)
      ELSIF (mode = mDP) & longa & isReg(v1) THEN aReg := v1
      ELSIF (aReg >= 0) & touches(mode, v1, aReg) THEN aReg := -1
      END
    ELSIF (c = "z") OR (c = "t") THEN
      IF (aReg >= 0) & touches(mode, v1, aReg) THEN aReg := -1 END;
      IF c = "t" THEN nzA := FALSE END
    ELSIF c = "x" THEN nzA := FALSE
    ELSIF (c = "n") OR (c = "c") THEN (* neither; a branch not taken: as before *)
    ELSE aReg := -1; nzA := FALSE   (* r: REP, SEP, XBA; B: a jump, a call, ... *)
    END
  END track;

  (* one instruction into the peephole *)
  PROCEDURE emit(op, mode, v1, v2: LONGINT);
  BEGIN
    IF ~peep OR (pc < fwdMax) THEN
      Flush; gen(op, mode, v1, v2); aReg := -1; nzA := FALSE
    ELSIF (op = LDA) & (mode = mDP) & longa & (v1 = aReg) & nzA THEN (* left out *)
    ELSIF (op = STA) & (mode = mDP) & longa & isReg(v1) THEN
      IF (nheld > 0) & (pend = v1) THEN release(1)   (* the held store: stored again, unread *)
      ELSE Flush
      END;
      held[0].op := op; held[0].mode := mode; held[0].v1 := v1; held[0].v2 := v2;
      held[0].la := longa; held[0].li := longi; nheld := 1; pend := v1; aReg := v1
    ELSIF (nheld > 0) & (nheld < maxHeld) & holdable(op, mode, v1) & ~touches(mode, v1, pend) THEN
      held[nheld].op := op; held[nheld].mode := mode; held[nheld].v1 := v1; held[nheld].v2 := v2;
      held[nheld].la := longa; held[nheld].li := longi; nheld := nheld + 1;
      track(op, mode, v1)
    ELSE
      Flush; gen(op, mode, v1, v2); track(op, mode, v1)
    END
  END emit;

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
    emit(op, mode, v1, v2)
  END Gen;

  (* bytes into the code as they are, not instructions: the peephole's
     held instructions first, and after them nothing known of A *)
  PROCEDURE Byte*(b: LONGINT);
  BEGIN Flush; aReg := -1; nzA := FALSE; o(b)
  END Byte;

  PROCEDURE Word*(w: LONGINT);
  BEGIN Flush; aReg := -1; nzA := FALSE; o(w); o(w DIV 100H)
  END Word;

  PROCEDURE Long*(l: LONGINT);
  BEGIN Flush; aReg := -1; nzA := FALSE; o(l); o(l DIV 100H); o(l DIV 10000H); o(l DIV 1000000H)
  END Long;

  (* Narrow 0-arg emitters for implied 1-byte instructions. A full
     Gen(op, mImpl, 0, 0) call compiles to ~23 bytes at the call site (4
     constant args + JSR); one of these is ~3. ORG has 191 implied sites. *)
  PROCEDURE Clc*; BEGIN emit(CLC, mImpl, 0, 0) END Clc;
  PROCEDURE Sec*; BEGIN emit(SEC, mImpl, 0, 0) END Sec;
  PROCEDURE Rts*; BEGIN emit(RTS, mImpl, 0, 0) END Rts;
  PROCEDURE Rtl*; BEGIN emit(RTL, mImpl, 0, 0) END Rtl;
  PROCEDURE Pha*; BEGIN emit(PHA, mImpl, 0, 0) END Pha;
  PROCEDURE Pla*; BEGIN emit(PLA, mImpl, 0, 0) END Pla;
  PROCEDURE Dex*; BEGIN emit(DEX, mImpl, 0, 0) END Dex;
  PROCEDURE Phk*; BEGIN emit(PHK, mImpl, 0, 0) END Phk;
  PROCEDURE Iny*; BEGIN emit(INY, mImpl, 0, 0) END Iny;
  PROCEDURE Xba*; BEGIN emit(XBA, mImpl, 0, 0) END Xba;
  PROCEDURE Tsc*; BEGIN emit(TSC, mImpl, 0, 0) END Tsc;
  PROCEDURE Tcs*; BEGIN emit(TCS, mImpl, 0, 0) END Tcs;
  PROCEDURE Tax*; BEGIN emit(TAX, mImpl, 0, 0) END Tax;
  PROCEDURE Rti*; BEGIN emit(RTI, mImpl, 0, 0) END Rti;
  PROCEDURE Txa*; BEGIN emit(TXA, mImpl, 0, 0) END Txa;

  (* Arity-narrowed entry points so ORG needn't pass unused operands: the
     instruction selector is packed as op*32 + mode (mode < 32), a compile-
     time constant at most sites, so a call materialises ONE constant plus its
     real operand(s) instead of the four Gen takes. gen1 = one operand
     (v2 = 0); gen2 = two. Both route through Gen for mode-opt + the peephole. *)
  PROCEDURE gen1*(sel, v1: LONGINT);
  BEGIN Gen(sel DIV 32, sel MOD 32, v1, 0)
  END gen1;

  PROCEDURE gen2*(sel, v1, v2: LONGINT);
  BEGIN Gen(sel DIV 32, sel MOD 32, v1, v2)
  END gen2;

  (* --- the extension after WDM (xops) --- *)

  (* -x, for a driver in Oberon (main.c sets xops) *)
  PROCEDURE SetXops*(on: BOOLEAN);
  BEGIN xops := on
  END SetXops;

  (* -816, for a driver in Oberon (main.c sets stock): code for a stock
     65C816, without the board's banked direct page and stack (WDM #$B1,
     Verilog65C816's docs/BankedDP.md), so a local's bank is 0; not with -x *)
  PROCEDURE SetStock*(on: BOOLEAN);
  BEGIN stock := on
  END SetStock;

  (* a multiply or divide, sel xMUL, xUML, xDIV or xUDV * 32 and mDP or
     mImm: $42, then that instruction *)
  PROCEDURE X*(sel, v: LONGINT);
  BEGIN Flush; aReg := -1; nzA := FALSE; o(42H); gen(sel DIV 32, sel MOD 32, v, 0)
  END X;

  (* A shifted n bits (0 < n < 16 of a 16-bit A) at once: op ASL, LSR, ASR
     or ROL, ROR (not through C) *)
  PROCEDURE ShiftA*(op, n: LONGINT);
  BEGIN Flush; aReg := -1; nzA := FALSE; o(42H);
    IF op = ASL THEN o(0AH) ELSIF op = LSR THEN o(4AH) ELSIF op = ASR THEN o(8AH)
    ELSIF op = ROL THEN o(2AH) ELSE o(6AH)
    END;
    o(n)
  END ShiftA;

  (* --- accessors for ORG --- *)
  (* a place in the code: perhaps a label, so the peephole's held
     instructions there first, and nothing known of A *)
  PROCEDURE Here*(): LONGINT;
  BEGIN Flush; aReg := -1; nzA := FALSE; RETURN pc
  END Here;
  PROCEDURE SetPc*(p: LONGINT);       BEGIN Flush; aReg := -1; nzA := FALSE; pc := p END SetPc;
  (* Bounds-checked: after a code-buffer overflow the fixup chains embedded
     in `code` are truncated, so a chain walk could read/patch out of range.
     Get returns 0 (a chain terminator, so walks end) and Patch is a no-op;
     both set fault so Close refuses to emit. *)
  PROCEDURE Get*(at: LONGINT): INTEGER;
    VAR r: INTEGER;
  BEGIN Flush;
    IF (at >= 0) & (at < maxCode) THEN
      IF code[at DIV ChunkSize] = NIL THEN r := 0 ELSE r := code[at DIV ChunkSize].b[at MOD ChunkSize] END
    ELSE fault := TRUE; r := 0
    END;
    RETURN r
  END Get;
  PROCEDURE Patch*(at, b: LONGINT);
  BEGIN Flush;
    IF (at >= 0) & (at < maxCode) THEN put(at, b) ELSE fault := TRUE END
  END Patch;
  PROCEDURE LongA*(): BOOLEAN;        BEGIN RETURN longa END LongA;
  PROCEDURE SetLongA*(b: BOOLEAN);    BEGIN longa := b END SetLongA;
  PROCEDURE LongI*(): BOOLEAN;        BEGIN RETURN longi END LongI;
  PROCEDURE SetLongI*(b: BOOLEAN);    BEGIN longi := b END SetLongI;
  PROCEDURE SetDPage*(d: LONGINT);    BEGIN dpage := d END SetDPage;
  PROCEDURE SetPBReg*(p: LONGINT);    BEGIN pbreg := p END SetPBReg;
  (* Select the code cap: SMALL (one bank, JSR internal calls) or LARGE
     (fill the buffer, JSL internal calls). ORG.Open calls this per module. *)
  PROCEDURE SetLarge*(large: BOOLEAN);
  BEGIN IF large THEN codeLimit := maxCode - 512 ELSE codeLimit := maxCodeSmall END
  END SetLarge;
  PROCEDURE RelCount*(): INTEGER;     BEGIN Flush; RETURN relocC END RelCount;
  PROCEDURE Rel*(i: INTEGER): LONGINT; BEGIN RETURN reloc.r[i] END Rel;
  PROCEDURE AddRel*(p: LONGINT);
  BEGIN addReloc(p)
  END AddRel;

  (* TRUE once a fixed buffer (code or reloc) overflowed — the module is too
     large. ORG.Close checks this and refuses to emit a truncated .816. *)
  PROCEDURE Faulted*(): BOOLEAN;
  BEGIN RETURN fault
  END Faulted;

  (* --- relaxation: a procedure's branches made short where they reach ---

     A forward branch is made long, for a chain fixed later: a condition's
     is its inverse over a BRL (Bcc' +3, BRL), which a fix that reaches
     makes BRA and NOP. Every branch, PER and JMP of the procedure is noted
     where it is (site); at its end (Relax) such a pair becomes one Bcc,
     and a lone BRL, or BRA and NOP, a BRA, where they reach and nothing
     branches into the bytes they lose. The code after them closes up;
     every branch and PER of the procedure is encoded again, the
     relocations moved, and NewPos tells the code generator where each of
     its places is now. *)

  PROCEDURE rd(p: LONGINT): LONGINT;
  BEGIN RETURN code[p DIV ChunkSize].b[p MOD ChunkSize]
  END rd;

  (* where the branch, PER or JMP at p goes *)
  PROCEDURE target(p: LONGINT): LONGINT;
    VAR op, d: LONGINT;
  BEGIN op := rd(p);
    IF (op = 82H) OR (op = 62H) THEN   (* within the bank: a PER to a place 32K away wraps *)
      d := p DIV 10000H * 10000H + (p + 3 + rd(p + 1) + rd(p + 2) * 100H) MOD 10000H
    ELSIF op = 4CH THEN d := p DIV 10000H * 10000H + rd(p + 1) + rd(p + 2) * 100H
    ELSE d := rd(p + 1); IF d >= 80H THEN d := d - 100H END; d := p + 2 + d
    END
    RETURN d
  END target;

  (* the place p of the procedure's code had before Relax, now *)
  PROCEDURE NewPos*(p: LONGINT): LONGINT;
    VAR lo, hi, m: INTEGER;
  BEGIN lo := 0; hi := ndel;   (* the first left-out place at or above p: lo *)
    WHILE lo < hi DO m := (lo + hi) DIV 2;
      IF st.dpos[m] < p THEN lo := m + 1 ELSE hi := m END
    END;
    IF lo > 0 THEN p := p - st.dcum[lo - 1] END
    RETURN p
  END NewPos;

  (* the bytes Relax would leave out, from st.act *)
  PROCEDURE deletions;
    VAR i: INTEGER; c: INTEGER;
  BEGIN ndel := 0; c := 0;
    FOR i := 0 TO nsite - 1 DO
      IF st.act[i] = 1 THEN c := c + 3; st.dpos[ndel] := st.at[i] + 2; st.dcum[ndel] := c; ndel := ndel + 1
      ELSIF st.act[i] = 2 THEN c := c + 1; st.dpos[ndel] := st.at[i] + 2; st.dcum[ndel] := c; ndel := ndel + 1
      END
    END
  END deletions;

  (* a target in [a, b): a branch into bytes that would be left out *)
  PROCEDURE into(a, b: LONGINT): BOOLEAN;
    VAR lo, hi, m: INTEGER;
  BEGIN lo := 0; hi := nsite;
    WHILE lo < hi DO m := (lo + hi) DIV 2;
      IF st.tg[m] < a THEN lo := m + 1 ELSE hi := m END
    END
    RETURN (lo < nsite) & (st.tg[lo] < b)
  END into;

  (* a long branch: BRL, or a BRL a fix made BRA and NOP *)
  PROCEDURE longBr(p: LONGINT): BOOLEAN;
  BEGIN RETURN (rd(p) = 82H) OR (rd(p) = 80H) & (rd(p + 2) = 0EAH)
  END longBr;

  PROCEDURE fits(d: LONGINT): BOOLEAN;
  BEGIN RETURN (d >= -128) & (d <= 127)
  END fits;

  (* the procedure's code, from BeginProc's place to pc, relaxed: TRUE if
     it moved, NewPos then telling where its places are *)
  PROCEDURE Relax*(): BOOLEAN;
    VAR i, j, h, po, wo, n: INTEGER; s, t, d, p, w, oldpc, r, b: LONGINT; moved, flag: BOOLEAN;
      ch: Chunk;
  BEGIN Flush; ndel := 0; moved := FALSE; movedFrom := relaxFrom;
    IF relax & ~sitesFull & ~fault & (nsite > 0) THEN
      FOR i := 0 TO nsite - 1 DO st.to[i] := target(st.at[i]); st.tg[i] := st.to[i]; st.act[i] := 0 END;
      (* the targets sorted (Shell's sort), for into *)
      h := 1; WHILE h < nsite DIV 3 DO h := h * 3 + 1 END;
      WHILE h > 0 DO
        FOR i := h TO nsite - 1 DO t := st.tg[i]; j := i;
          WHILE (j >= h) & (st.tg[j - h] > t) DO st.tg[j] := st.tg[j - h]; j := j - h END;
          st.tg[j] := t
        END;
        h := h DIV 3
      END;
      (* what is shorter and reaches: as the bytes left out only bring a
         branch's target nearer, one that reaches with its own left out
         reaches with all of them (a pair's three bytes, a BRL's one) *)
      i := 0;
      WHILE i < nsite DO s := st.at[i];
        IF (rd(s) MOD 20H = 10H) & (rd(s + 1) = 3) & (i + 1 < nsite) & (st.at[i + 1] = s + 2)
            & longBr(s + 2) & ~into(s + 2, s + 5) THEN
          t := st.to[i + 1];
          IF (t > s) & fits(t - s - 5) OR (t <= s) & fits(t - s - 2) THEN
            st.act[i] := 1; st.act[i + 1] := 3
          END;
          i := i + 1
        ELSIF longBr(s) & ~into(s + 2, s + 3) THEN t := st.to[i];
          IF (t > s) & fits(t - s - 3) OR (t <= s) & fits(t - s - 2) THEN st.act[i] := 2 END
        END;
        i := i + 1
      END;
      deletions;
      IF ndel > 0 THEN
        (* the code closed up *)
        oldpc := pc; p := st.dpos[0]; w := p; j := 0;
        WHILE p < oldpc DO
          IF (j < ndel) & (p = st.dpos[j]) THEN
            IF j = 0 THEN p := p + st.dcum[0] ELSE p := p + st.dcum[j] - st.dcum[j - 1] END;
            j := j + 1
          ELSE   (* up to the next byte left out *)
            IF j < ndel THEN r := st.dpos[j] ELSE r := oldpc END;
            IF (p DIV ChunkSize = (r - 1) DIV ChunkSize) & (w DIV ChunkSize = p DIV ChunkSize) THEN
              (* within a chunk, as a procedure almost always is *)
              ch := code[p DIV ChunkSize]; po := p MOD ChunkSize; wo := w MOD ChunkSize; n := r - p;
              WHILE n > 0 DO ch.b[wo] := ch.b[po]; wo := wo + 1; po := po + 1; n := n - 1 END;
              w := w + (r - p); p := r
            ELSE
              WHILE p < r DO
                code[w DIV ChunkSize].b[w MOD ChunkSize] := code[p DIV ChunkSize].b[p MOD ChunkSize];
                w := w + 1; p := p + 1
              END
            END
          END
        END;
        pc := w; p := w; WHILE p < oldpc DO put(p, 0); p := p + 1 END;
        (* every site encoded again *)
        FOR i := 0 TO nsite - 1 DO
          IF st.act[i] # 3 THEN
            s := NewPos(st.at[i]);
            IF st.act[i] = 1 THEN   (* the condition inverted: BPL BMI, BVC BVS, BCC BCS, BNE BEQ *)
              t := NewPos(st.to[i + 1]); b := rd(s);
              IF b DIV 20H MOD 2 = 0 THEN put(s, b + 20H) ELSE put(s, b - 20H) END
            ELSE t := NewPos(st.to[i])
            END;
            IF st.act[i] = 2 THEN put(s, 80H) END;
            b := rd(s);
            IF (b = 82H) OR (b = 62H) THEN d := t - (s + 3); put(s + 1, d); put(s + 2, d DIV 100H)
            ELSIF b = 4CH THEN put(s + 1, t); put(s + 2, t DIV 100H)
            ELSE d := t - (s + 2); IF ~fits(d) THEN fault := TRUE END; put(s + 1, d)
            END
          END
        END;
        (* the relocations moved (bit 31 marks a bank's) *)
        FOR i := relocFrom TO relocC - 1 DO r := reloc.r[i]; flag := (r < 0) OR (r > 7FFFFFFFH);   (* 32 bits or more *)
          IF flag THEN r := r - 80000000H END;
          IF r >= relaxFrom THEN r := NewPos(r) END;
          IF flag THEN r := r + 80000000H END;
          reloc.r[i] := r
        END;
        moved := TRUE
      END
    END;
    fwdMax := 0; aReg := -1; nzA := FALSE;
    nsite := 0; sitesFull := FALSE; relaxFrom := pc; relocFrom := relocC
    RETURN moved
  END Relax;

  (* where the code Relax closed up started: the places from it on moved *)
  PROCEDURE RelaxedFrom*(): LONGINT;
  BEGIN RETURN movedFrom
  END RelaxedFrom;

  (* a procedure's code starts here: its sites from here on *)
  PROCEDURE BeginProc*;
  BEGIN Flush; nsite := 0; ndel := 0; sitesFull := FALSE; relaxFrom := pc; relocFrom := relocC
  END BeginProc;

  PROCEDURE Init*;
    VAR k, i: LONGINT;
  BEGIN
    FOR k := 0 TO maxChunks - 1 DO   (* a module compiled before: its code gone *)
      IF code[k] # NIL THEN FOR i := 0 TO ChunkSize - 1 DO code[k].b[i] := 0 END END
    END;
    pc := CodeOrg; longa := TRUE; longi := TRUE;
    dpage := 0; pbreg := 0; relocC := 0; fault := FALSE;
    codeLimit := maxCodeSmall;
    nheld := 0; pend := -1; aReg := -1; nzA := FALSE; fwdMax := 0;
    nsite := 0; ndel := 0; sitesFull := FALSE; relaxFrom := 0; relocFrom := 0
  END Init;

BEGIN NEW(reloc); NEW(st); relax := TRUE; nsite := 0; ndel := 0; sitesFull := FALSE; relaxFrom := 0;
  pc := CodeOrg; longa := TRUE; longi := TRUE;
  dpage := 0; pbreg := 0; relocC := 0; fault := FALSE;
  codeLimit := maxCodeSmall;
  peep := TRUE; nheld := 0; pend := -1; aReg := -1; nzA := FALSE; fwdMax := 0;
  cls := "aascccxcccBBBccnnnnxBxxsxxasxxBBBBlxxsBBnannnnnnnnnnaxxBxxrssBBBannnrSBzzzxxxnattaxanxaxBBrBB";
  mcls := "-h------d-xxddh-----dddhs-"
END OCG.
