MODULE ORGI FRIENDS ORGE, ORG; (* 65C816 code generator, its items: the
   registers, loading and storing items, the items made, booleans, branches
   and their fixups. The first of ORG's three modules (ORGI, ORGE, ORG), a
   65C816 module's code being a bank: ORGE and ORG, its friends, assign to
   the state here (RH, frame, ...). *)

  IMPORT SYSTEM, OCG, ORS, ORB, ORGFP, ORGW, ORH;

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
    maxTD* = 160;
    CodeOrg* = 0;
    SB_DP* = 42H;           (* static base at DP $42: with BANK_DP after it, [SB],Y reaches the
                               module's variables in whatever bank they are *)
    SB_TEMP = 20H;         (* imported module var_base *)
    SB_TEMP_BANK = 22H;
    BANK_DP* = 44H;         (* own module data bank byte *)

    (* internal item modes (beyond ORB classes) *)
    Reg* = 10; RegI* = 11; Cond* = 12;

    (* condition codes *)
    MI* = 0; PL = 8; EQ* = 1; NE* = 9; LT* = 5; GE* = 13;
    LE* = 6; GT* = 14; AL* = 7; NV = 15;

    maxForNest* = 8;        (* max nested FOR loops with a non-const limit *)
    maxFar = 128;          (* max non-exported procedures assigned to variables *)
    maxEnt = 256;          (* max .816 export-table entries *)
    maxMeth* = 64;          (* max vtable slots per type *)
    maxVtFix* = 512;        (* max vtable-slot loader fixups per module *)
    maxItab* = 128;         (* max distinct (record,interface) itables per module *)
    maxItabRef* = 256;      (* max PtrToIface conversion sites per module *)
    ExtLevels* = 8;         (* a TD's ancestors: extension levels 0-7 *)
    VtableOff* = 36;        (* byte offset of vtable[0] in a TD: size(2) +
                              8 ancestors(32), levels 0-7 + nofmeth(2): 36. Each slot is 4 bytes,
                              the method's address and its bank (v3), filled by the
                              loader: modules are not all in one bank. *)
    SlotSize* = 4;

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
    varsize*: LONGINT;   (* = ORG_varsize; set by SetDataSize *)
    strx*, entry*, RH*, frame*: LONGINT;
    check*: BOOLEAN;
    largeMod*: BOOLEAN;  (* MODULE m LARGE: far (JSL/RTL) internal calls, >64K code *)
    wa*: ORGW.ModArraysPtr;           (* module-image scratch: str/data/tdFixup*/vtFix* *)
    (* far entries of procedures that are not exported; see load *)
    farProc, farEntry: ARRAY maxFar OF LONGINT;
    nofFar*: INTEGER;

  (* --- helpers --- *)

  PROCEDURE RegAddr*(reg: LONGINT): LONGINT;
  BEGIN RETURN reg * 2 + 2
  END RegAddr;

  PROCEDURE Lo16*(v: LONGINT): LONGINT;
  BEGIN RETURN v MOD 10000H
  END Lo16;

  PROCEDURE Hi16*(v: LONGINT): LONGINT;
  BEGIN RETURN v DIV 10000H MOD 10000H
  END Hi16;

  (* TRUE for LONGINT — a 32-bit (two-word) integer. Loaded/stored like REAL
     (two plain words); arithmetic differs (see AddOp/DivOp/IntRelation). *)
  PROCEDURE IsLong*(t: ORB.Type): BOOLEAN;
  BEGIN RETURN (t # NIL) & (t.form = ORB.Int) & (t.size = 4)
  END IsLong;

  PROCEDURE Set16*(a, i: BOOLEAN);
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

  PROCEDURE Set8*(a, i: BOOLEAN);
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

  PROCEDURE incR*;
  BEGIN
    IF RH < MT - 1 THEN RH := RH + 1
    ELSE ORS.Mark("register stack overflow")
    END
  END incR;

  (* DP address of the correct module's var_base. mno >= 0 (own): SB_DP,
     no code. mno < 0 (import): emit loads of the module's var_base+bank
     with relocations, return SB_TEMP. *)
  PROCEDURE GetSB*(mno: LONGINT): LONGINT;
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

  (* the bank of the variables of the static base sb (GetSB's): BANK_DP's,
     the module's own, or SB_TEMP_BANK, an import's *)
  PROCEDURE BankOf*(sb: LONGINT): LONGINT;
    VAR b: LONGINT;
  BEGIN IF sb = SB_DP THEN b := BANK_DP ELSE b := SB_TEMP_BANK END
    RETURN b
  END BankOf;

  PROCEDURE CheckRegs*;
  BEGIN
    Set16(TRUE, TRUE)
    (* Reset at end of every statement: a statement start may be a branch
       target and we must guarantee 16-bit A/index there. *)
  END CheckRegs;

  PROCEDURE SetCC*(VAR x: Item; n: LONGINT);
  BEGIN
    x.origType := x.type; x.mode := Cond; x.a := 0; x.b := 0; x.r := n
  END SetCC;

  PROCEDURE Trap*(cond, num: LONGINT);
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
  PROCEDURE emitBranch*(cond: LONGINT; type: ORB.Type; mode, target: LONGINT);
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
        (* unsigned GT: branch iff (C=1) & (Z=0). Both BEQ (equal) and BCC
           (below) skip past the BRL — anything else falls through to it. *)
        OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 2 + 5);
        OCG.gen1(OCG.BCC * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
        OCG.gen1(OCG.BRL * 32 + mode, target)
      END
    ELSIF cond = AL THEN
      OCG.gen1(OCG.BRL * 32 + mode, target)
    END
  END emitBranch;

  (* A branch on cond added to the forward chain L: the chain's new head,
     the branch's offset. A branch never taken (NV, a constant condition:
     WHILE TRUE, IF TRUE, TRUE & b, FALSE OR b) emits nothing, and the
     chain stays as it is; its head is not the operand of the instruction
     before, which the chain's fixup would overwrite. *)
  PROCEDURE chain*(cond: LONGINT; type: ORB.Type; L: LONGINT): LONGINT;
  BEGIN
    IF cond # NV THEN emitBranch(cond, type, OCG.mFix, L); L := OCG.Here() - 2 END;
    RETURN L
  END chain;

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
    VAR L1, ci, raw: LONGINT;
  BEGIN
    (* ~OCG.Faulted() backstops a chain corrupted by a code-buffer overflow
       whose garbage links happen to stay in range (Get already terminates
       out-of-range walks by returning 0). Links are RELATIVE (see OCG.ofixl):
       the previous site is L + signext16(link); a raw link of 0 ends the chain. *)
    WHILE (L # 0) & ~OCG.Faulted() DO
      ci := L - CodeOrg;
      raw := OCG.Get(ci) + OCG.Get(ci + 1) * 100H;
      IF raw >= 8000H THEN raw := raw - 10000H END;
      IF raw = 0 THEN L1 := 0 ELSE L1 := L + raw END;
      fix(L, OCG.Here());
      L := L1
    END
  END FixLink;

  PROCEDURE FixLinkWith(L0, dst: LONGINT);
    VAR L1, ci, raw: LONGINT;
  BEGIN
    WHILE L0 # 0 DO
      ci := L0 - CodeOrg;
      raw := OCG.Get(ci) + OCG.Get(ci + 1) * 100H;
      IF raw >= 8000H THEN raw := raw - 10000H END;
      IF raw = 0 THEN L1 := 0 ELSE L1 := L0 + raw END;
      fix(L0, dst);
      L0 := L1
    END
  END FixLinkWith;

  PROCEDURE merged(L0, L1: LONGINT): LONGINT;
    VAR L2, L3, ci, raw, rel: LONGINT;
  BEGIN
    ci := 0; L2 := 0;
    IF L0 # 0 THEN
      L3 := L0;
      REPEAT
        L2 := L3; ci := L2 - CodeOrg;
        raw := OCG.Get(ci) + OCG.Get(ci + 1) * 100H;
        IF raw >= 8000H THEN raw := raw - 10000H END;
        IF raw = 0 THEN L3 := 0 ELSE L3 := L2 + raw END
      UNTIL L3 = 0;
      (* point L0's tail (operand at ci, position L2) at chain L1, RELATIVE;
         L1 = 0 keeps the end sentinel *)
      IF L1 = 0 THEN rel := 0 ELSE rel := (L1 - L2) MOD 10000H END;
      OCG.Patch(ci, rel MOD 100H);
      OCG.Patch(ci + 1, rel DIV 100H MOD 100H);
      L1 := L0
    END;
    RETURN L1
  END merged;

  (* Patch a placeholder 8-bit forward branch (operand byte at 'at'). *)
  PROCEDURE patch*(at: LONGINT);
  BEGIN OCG.Patch(at, OCG.Here() - (at + 1))
  END patch;

  (* Emit a forward branch with a placeholder target; return its operand
     byte address for later patch(). *)
  PROCEDURE emitFwdBranch*(op: LONGINT): LONGINT;
  BEGIN
    OCG.gen1(op * 32 + OCG.mPCR, OCG.Here() + 2);
    RETURN OCG.Here() - 1
  END emitFwdBranch;

  (* Load two consecutive words at byte offset `off` of the interface value
     designated by (mode,a,b,r) into RegAddr(dst)/dst+1. Var/Par only. *)
  PROCEDURE loadIfacePair*(mode, a, b, r, off, dst: LONGINT);
    VAR sb: LONGINT;
  BEGIN
    Set16(TRUE, TRUE);
    IF (mode = ORB.Var) & (r <= 0) THEN
      sb := GetSB(r);
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, a + off);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, sb);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(dst));
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, a + off + 2);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, sb);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(dst + 1))
    ELSE   (* local Var or by-value Par: stack-frame relative *)
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, a + off + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(dst));
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, a + off + 2 + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(dst + 1))
    END
  END loadIfacePair;

  (* --- load: materialize item x into register(s), leaving x in Reg mode --- *)
  PROCEDURE load*(VAR x: Item);
    VAR perAddr, perOp, mno, exno, encoded, sb, falseChain, skip: LONGINT; i: INTEGER;
  BEGIN
    IF (x.mode = RegI) & (x.type # NIL) & (x.type.form = ORB.Intfc) THEN
      (* through a pointer (a field of a heap object, an element): the 4
         words to free registers, then down over the pointer *)
      Set16(TRUE, TRUE); i := 0;
      WHILE i < 4 DO
        OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a + i * 2);
        OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(x.r));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + i));
        INC(i)
      END;
      i := 0;
      WHILE i < 4 DO
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(RH + i));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(x.r + i));
        INC(i)
      END;
      x.mode := Reg; RH := x.r; incR; incR; incR; incR
    ELSIF (x.mode # Reg) & (x.type # NIL) & (x.type.form = ORB.Intfc) THEN
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
          IF x.r > 0 THEN ORS.Mark("not a global procedure")
          ELSIF (x.r = 0) & (x.b = 0) THEN
            (* A procedure that is not exported returns with RTS and runs
               on its caller's static base, but a procedure variable is
               called far, and perhaps from another module. Its value is
               therefore the address of an entry made here, which sets
               the static base as an exported procedure does and calls
               the procedure near (far in a LARGE module). Parameters and
               result are in registers, so nothing has to be moved.
               There is one entry for each procedure, made where it is
               first assigned, so that its values compare equal. *)
            Set16(TRUE, TRUE);
            i := 0;
            WHILE (i < nofFar) & (farProc[i] # x.a) DO i := i + 1 END;
            IF i < nofFar THEN perAddr := farEntry[i]
            ELSE
            IF nofFar < maxFar THEN farProc[nofFar] := x.a; farEntry[nofFar] := OCG.Here() + 2; nofFar := nofFar + 1
            ELSE ORS.Mark("too many procedures assigned")
            END;
            skip := emitFwdBranch(OCG.BRA);
            perAddr := OCG.Here();                 (* the entry *)
            OCG.gen1(OCG.LDA * 32 + OCG.mDP, SB_DP);
            OCG.Pha;
            OCG.gen1(OCG.LDA * 32 + OCG.mDP, BANK_DP);
            OCG.Pha;
            OCG.AddRel(OCG.Here());
            OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, SB_DP);
            OCG.AddRel(OCG.Here() + 80000000H);
            OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, BANK_DP);
            IF largeMod THEN OCG.gen1(OCG.JSL * 32 + OCG.mAbsL, x.a)
            ELSE OCG.gen1(OCG.JSR * 32 + OCG.mAbs, x.a)
            END;
            Set16(TRUE, TRUE);
            OCG.Pla;
            OCG.gen1(OCG.STA * 32 + OCG.mDP, BANK_DP);
            OCG.Pla;
            OCG.gen1(OCG.STA * 32 + OCG.mDP, SB_DP);
            OCG.Rtl;
            patch(skip)
            END;
            perOp := perAddr - OCG.Here() - 3;
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
            (* PER for the address in the target's bank, LDA # for that bank (not
               PHK: the target may be in another bank). The PER's relocation
               fills both: the LDA's operand is 7 bytes after the PER *)
            OCG.AddRel(OCG.Here());
            OCG.gen1(OCG.PER * 32 + OCG.mImm, encoded);
            OCG.Pla;
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
            OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1));
            x.r := RH; incR; incR
          END
        ELSIF (x.type.form = ORB.Real) OR IsLong(x.type) THEN
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
             OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) OR IsLong(x.type) THEN
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
             OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) OR IsLong(x.type) THEN
            Set16(TRUE, TRUE);
            OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, sb);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
            OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a + 2);
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, sb);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1));
            x.r := RH; incR; incR
          ELSIF x.type.size = 1 THEN
            Set8(TRUE, FALSE);
            OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, sb);
            Set16(TRUE, FALSE);
            OCG.gen1(OCG.AND * 32 + OCG.mImm, 0FFH);
            OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
            x.r := RH; incR
          ELSE
            Set16(TRUE, TRUE);
            OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
            OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, sb);
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
        IF (x.type.form = ORB.Real) OR (x.type.form = ORB.Pointer) OR (x.type.form = ORB.Proc) OR IsLong(x.type) THEN
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
           OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) OR IsLong(x.type) THEN
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
        Set16(TRUE, TRUE);   (* REP leaves the flags of the condition alone *)
        falseChain := chain(negated(x.r), x.origType, x.a);   (* the FALSE chain *)
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

  (* Adapt an integer item x to LONGINT (toLong) or INTEGER width — the
     conversion the frontend never inserts (it treats both as form Int).
     Widening sign-extends; narrowing keeps the low word. For a register operand this MUST be the top
     of the register stack (x.r+1 = RH) so the appended/dropped high word stays
     contiguous — callers only convert a freshly-loaded top item or a const. *)
  PROCEDURE cvt*(VAR x: Item; toLong: BOOLEAN);
  BEGIN
    IF (x.type # NIL) & (x.type.form = ORB.Int) THEN
      IF toLong & ~IsLong(x.type) THEN
        IF x.mode = ORB.Const THEN x.type := ORB.longType
        ELSE
          (* sign-extend: LONGINT is signed, like INTEGER. A BYTE was masked
             to 0..255 when it was loaded, so it extends with zeros. *)
          load(x); Set16(TRUE, TRUE);
          OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(RH));   (* high word := 0 *)
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
          OCG.gen1(OCG.BPL * 32 + OCG.mPCR, OCG.Here() + 2 + 2);
          OCG.gen1(OCG.DEC * 32 + OCG.mDP, RegAddr(RH));   (* negative: high word := FFFFH *)
          incR; x.type := ORB.longType
        END
      ELSIF ~toLong & IsLong(x.type) THEN
        IF x.mode = ORB.Const THEN x.type := ORB.intType
        ELSE load(x); RH := RH - 1; x.type := ORB.intType  (* keep low word *)
        END
      END
    END
  END cvt;

  (* When one operand of a binary op is LONGINT and the other is an integer
     CONSTANT, retype the constant to LONGINT so the op takes its two-word path
     and the result carries LONGINT type. Without this, e.g. "12 + longvar"
     (const on the left) would keep INTEGER type on the result and leak/corrupt
     downstream. Constants fold by value, so retyping is free. *)
  PROCEDURE promoteConst*(VAR x, y: Item);
  BEGIN
    (* a constant that does not fit a word is a LONGINT whatever it is
       combined with: 100000 * i is a LONGINT product *)
    IF (x.mode = ORB.Const) & (x.type # NIL) & (x.type.form = ORB.Int)
       & ((x.a > 0FFFFH) OR (x.a < -8000H)) THEN x.type := ORB.longType END;
    IF (y.mode = ORB.Const) & (y.type # NIL) & (y.type.form = ORB.Int)
       & ((y.a > 0FFFFH) OR (y.a < -8000H)) THEN y.type := ORB.longType END;
    IF IsLong(x.type) & (y.mode = ORB.Const) & (y.type # NIL)
       & (y.type.form = ORB.Int) & ~IsLong(y.type) THEN y.type := ORB.longType
    ELSIF IsLong(y.type) & (x.mode = ORB.Const) & (x.type # NIL)
       & (x.type.form = ORB.Int) & ~IsLong(x.type) THEN x.type := ORB.longType
    END
  END promoteConst;

  (* An INTEGER operand of a LONGINT constant widened to LONGINT, so that
     the operation takes its two-word path: i * 10000H, i + 100000. The
     operand is the newest item, at the top of the registers once loaded. *)
  PROCEDURE widenToConst*(VAR x, y: Item);
  BEGIN
    IF (y.mode = ORB.Const) & IsLong(y.type) & (x.mode # ORB.Const) & (x.type # NIL)
       & (x.type.form = ORB.Int) & ~IsLong(x.type) THEN load(x); cvt(x, TRUE)
    ELSIF (x.mode = ORB.Const) & IsLong(x.type) & (y.mode # ORB.Const) & (y.type # NIL)
       & (y.type.form = ORB.Int) & ~IsLong(y.type) THEN load(y); cvt(y, TRUE)
    END
  END widenToConst;

  (* The word above register r becomes the sign of register r. *)
  PROCEDURE signExt(r: LONGINT);
  BEGIN
    Set16(TRUE, TRUE);
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, RegAddr(r + 1));
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r));
    OCG.gen1(OCG.BPL * 32 + OCG.mPCR, OCG.Here() + 2 + 2);
    OCG.gen1(OCG.DEC * 32 + OCG.mDP, RegAddr(r + 1))
  END signExt;

  (* Load both operands of a LONGINT operation, widening an INTEGER one.
     On exit both are two-word registers and together they are the top
     four of the register stack, in either order.
     cvt widens the top of the stack only. An operand that is in registers
     already (an expression, or the address of a designator) lies below
     whatever is loaded after it, so an INTEGER x under y is widened here:
     y moves up a word to make room, or, if x is still an address, its
     value is loaded over the address and the bank word takes the sign. *)
  PROCEDURE loadLongPair*(VAR x, y: Item);
    VAR yHeld, late: BOOLEAN; n: LONGINT;
  BEGIN
    yHeld := (y.mode = Reg) OR (y.mode = RegI); late := FALSE;
    IF x.mode = ORB.Const THEN x.type := ORB.longType
    ELSIF ~IsLong(x.type) THEN
      IF ~yHeld THEN cvt(x, TRUE)
      ELSIF x.mode = Reg THEN
        IF (y.mode = RegI) OR IsLong(y.type) THEN n := 2 ELSE n := 1 END;
        Set16(TRUE, TRUE);
        WHILE n > 0 DO n := n - 1;
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r + n));
          OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(y.r + n + 1))
        END;
        y.r := y.r + 1; incR; signExt(x.r); x.type := ORB.longType
      ELSIF x.mode = RegI THEN
        load(x); RH := RH + 1;   (* load gave up the bank word; it is x's high word now *)
        signExt(x.r); x.type := ORB.longType
      ELSE late := TRUE          (* not in registers: load it after y *)
      END
    END;
    IF ~yHeld THEN load(x) END;
    cvt(y, TRUE); load(y);
    IF late THEN cvt(x, TRUE) END;
    load(x)
  END loadLongPair;

  (* Two-word register r := -r. *)
  PROCEDURE longNeg*(r: LONGINT);
  BEGIN
    Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r));
    OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
    OCG.Clc;
    OCG.gen1(OCG.ADC * 32 + OCG.mImm, 1);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(r));
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(r + 1));
    OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
    OCG.gen1(OCG.ADC * 32 + OCG.mImm, 0);              (* + carry from low *)
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(r + 1))
  END longNeg;

  (* x := x op y by the LONGINT subroutine op of ORGFP (L_MUL, L_DIV).
     rem selects the second result of L_DIV, the remainder; divisor is
     set where y must be positive. *)
  PROCEDURE longCall*(op: INTEGER; VAR x, y: Item; rem, divisor: BOOLEAN);
    VAR d, p: LONGINT;
  BEGIN
    IF divisor & (y.mode = ORB.Const) & (y.a <= 0) THEN ORS.Mark("bad divisor") END;
    loadLongPair(x, y); Set16(TRUE, TRUE);
    IF divisor & check & (y.mode # ORB.Const) THEN
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r + 1));
      p := emitFwdBranch(OCG.BMI);
      OCG.gen1(OCG.ORA * 32 + OCG.mDP, RegAddr(y.r));
      OCG.gen1(OCG.BNE * 32 + OCG.mPCR, OCG.Here() + 2 + 2);
      patch(p);
      OCG.gen1(OCG.BRK * 32 + OCG.mImm, 6)
    END;
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_A_LO);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(x.r + 1));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_A_HI);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_B_LO);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r + 1));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_B_HI);
    ORGFP.AddFixup(op); OCG.gen1(OCG.JSR * 32 + OCG.mAbs, 0);
    d := RH - 4;                                       (* the lower pair *)
    IF rem THEN
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGFP.FP_B_LO);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(d));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGFP.FP_B_HI);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(d + 1))
    ELSE
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGFP.FP_A_LO);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(d));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGFP.FP_A_HI);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(d + 1))
    END;
    RH := RH - 2; x.r := d; x.mode := Reg; x.type := ORB.longType
  END longCall;

  (* reg := the stack's bank, D's high byte: the board's banked direct page
     and stack (WDM #$B1) put the stack in that bank; unbanked, D is 0 (the
     boot ROM), and so is the bank. A local variable's address goes with it. *)
  PROCEDURE stackBank*(reg: LONGINT);
  BEGIN
    Set16(TRUE, TRUE);
    OCG.gen1(OCG.TDC * 32 + OCG.mImpl, 0);
    OCG.Xba;
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 0FFH);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(reg))
  END stackBank;

  PROCEDURE loadAdr*(VAR x: Item);
    VAR sb: LONGINT;
  BEGIN
    IF x.mode = ORB.Var THEN
      IF x.r > 0 THEN
        Set16(TRUE, TRUE);
        OCG.Tsc;
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mImm, x.a + frame);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
        stackBank(RH + 1)
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

  PROCEDURE loadCond*(VAR x: Item);
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

  PROCEDURE loadStringAdr*(VAR x: Item);
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
    (* the IEEE-32 bit pattern as an integer: the host's (ORH), INTEGER
       being as wide as REAL on a POSIX host and LONGINT on the 65C816 *)
    x.a := ORH.RealBits(val)
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
      cvt(y, FALSE);   (* a LONGINT index: its low word *)
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
        IF x.r > 0 THEN stackBank(RH)   (* a local: the stack's bank *)
        ELSE OCG.gen1(OCG.LDA * 32 + OCG.mDP, BankOf(sb)); OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH))
        END;
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
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, BANK_DP); OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
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
        OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, sb);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
        OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a + 2);
        OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, sb);
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
    x.a := chain(negated(x.r), x.origType, x.a);
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
    x.b := chain(x.r, x.origType, x.b);
    FixLink(x.a); x.a := 0
  END Or1;

  PROCEDURE Or2*(VAR x, y: Item);
  BEGIN
    IF y.mode # Cond THEN loadCond(y) END;
    x.a := y.a; x.b := merged(y.b, x.b); x.r := y.r; x.origType := y.origType
  END Or2;

  (* --- assignment --- *)
  PROCEDURE StrToChar*(VAR x: Item);
  BEGIN x.type := ORB.charType; x.a := wa.str[x.a]
  END StrToChar;

  PROCEDURE Store*(VAR x, y: Item);
    VAR sb: LONGINT;
  BEGIN
    IF (x.type # NIL) & (x.type.form = ORB.Int) THEN cvt(y, IsLong(x.type)) END;
    load(y);
    IF x.mode = ORB.Var THEN
      IF x.r > 0 THEN
        IF (x.type.form = ORB.Pointer) OR (x.type.form = ORB.NilTyp)
           OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) OR IsLong(x.type) THEN
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
           OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) OR IsLong(x.type) THEN
          Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
          OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
          OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, sb);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r + 1));
          OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a + 2);
          OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, sb);
          RH := RH - 1
        ELSIF (x.type.size = 1) & (y.type.size >= 1) THEN
          Set8(TRUE, FALSE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
          OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
          OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, sb);
          Set16(TRUE, FALSE)
        ELSE
          Set16(TRUE, TRUE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, RegAddr(y.r));
          OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a);
          OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, sb)
        END
      END
    ELSIF x.mode = ORB.Par THEN
      Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH));
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 2 + frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH + 1));
      IF (x.type.form = ORB.Pointer) OR (x.type.form = ORB.NilTyp)
         OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) OR IsLong(x.type) THEN
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
         OR (x.type.form = ORB.Real) OR (x.type.form = ORB.Proc) OR IsLong(x.type) THEN
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
        (* s DIV 2 words, then an odd size's last byte alone: a word there
           would write the byte after (the next element of an array of
           65-byte records) *)
        wordCount := s DIV 2; Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDY * 32 + OCG.mImm, 0);
        IF wordCount > 0 THEN
          OCG.gen1(OCG.LDX * 32 + OCG.mImm, wordCount);
          loopTop := OCG.Here();
          OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, srcReg);   (* [dp],Y: the pointers' banks *)
          OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, dstReg);
          OCG.Iny;
          OCG.Iny;
          OCG.Dex;
          OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop)
        END;
        IF ODD(s) THEN
          Set8(TRUE, FALSE);
          OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, srcReg);
          OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, dstReg);
          Set16(TRUE, FALSE)
        END
      ELSIF openSrc THEN
        (* LEN(y) * elemSize bytes: its DIV 2 words, computed in A->X, the
           odd byte (LSR's carry, kept by PHP) alone after them. X (the word
           counter) and Y (the byte index) are 16-bit. LEN(y) is at the
           param's length slot, y.a + 4 + frame (same as Len). *)
        Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDY * 32 + OCG.mImm, 0);
        OCG.gen1(OCG.LDA * 32 + OCG.mSR, y.a + 4 + frame);   (* A := element count *)
        i := 0;
        WHILE i < k DO OCG.gen1(OCG.ASL * 32 + OCG.mImpl, 0); i := i + 1 END; (* *elemSize *)
        OCG.gen1(OCG.LSR * 32 + OCG.mImpl, 0);               (* DIV 2 = wordCount, C odd *)
        OCG.gen1(OCG.PHP * 32 + OCG.mImpl, 0);
        OCG.Tax;               (* X := wordCount (sets Z) *)
        OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 11);  (* none -> past the loop (9 bytes) *)
        loopTop := OCG.Here();
        OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, srcReg);   (* [dp],Y: the pointers' banks *)
        OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, dstReg);
        OCG.Iny;
        OCG.Iny;
        OCG.Dex;
        OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
        OCG.gen1(OCG.PLP * 32 + OCG.mImpl, 0);
        OCG.gen1(OCG.BCC * 32 + OCG.mPCR, OCG.Here() + 10);  (* even -> past the byte (8 bytes) *)
        Set8(TRUE, FALSE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, srcReg);
        OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, dstReg);
        Set16(TRUE, FALSE)
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
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, BANK_DP); OCG.gen1(OCG.STA * 32 + OCG.mDP, RegAddr(RH)); incR;
    Set8(TRUE, FALSE); Set16(FALSE, TRUE);
    OCG.gen1(OCG.LDY * 32 + OCG.mImm, 0);
    loopStart := OCG.Here();
    OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, RegAddr(y.r));   (* the string, in the module's data: [dp],Y *)
    OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, RegAddr(x.r));  (* [dp],Y: x's bank *)
    OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 2 + 3);
    OCG.Iny;
    OCG.gen1(OCG.BRA * 32 + OCG.mPCR, loopStart);
    RH := RH - 4
  END CopyString;

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
    x.a := chain(negated(x.r), x.origType, x.a);
    FixLink(x.b)
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

BEGIN NEW(wa)
END ORGI.
