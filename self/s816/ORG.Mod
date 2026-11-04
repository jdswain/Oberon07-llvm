MODULE ORG; (* 65C816 code generator — self-hosted port of 65Tools/oc/src/ORG.c.

   Backend #2 behind the shared frontend (ORS/ORB/ORP.Mod). Emits a
   relocatable .816 module. Register model: 8 16-bit "registers" at direct
   page $02-$1E (a stack, height RH), static base at DP $00. Instruction
   bytes go through the verified encoder OCG.Mod.

   Exposes the shared-frontend interface (Item = {mode,type,a,b,r,rdo,
   origType}; the target constants; InitSystem; the ~90 codegen entry
   points ORP calls). Where the C ORG_Enter/Return/Open signatures differ
   from what shared ORP passes, the Oberon procedures adopt ORP's
   signatures and derive what the 816 logic needs.

   ORG is three modules, a 65C816 module's code being a bank: ORGI (the
   items), ORGE (the expressions) and ORG (calls, procedures, the
   standard procedures, the module, OO), ORGE and ORG friends of the
   modules below them. ORG keeps the frontend's interface: what moved
   is called through here. *)

  IMPORT OCG, ORS, ORB, ORGFP, ORGW, Files, ORH, ORGI, ORGE;

  CONST
    WordSize* = ORGI.WordSize;
    SetMax* = ORGI.SetMax;
    ParLimit* = ORGI.ParLimit;
    IntSize* = ORGI.IntSize;
    LongSize* = ORGI.LongSize;
    RealSize* = ORGI.RealSize;
    SetSize* = ORGI.SetSize;
    NilSize* = ORGI.NilSize;
    StrSize* = ORGI.StrSize;
    PtrSize* = ORGI.PtrSize;
    IntfcSize* = ORGI.IntfcSize;

  TYPE Item* = ORGI.Item;
    (* a procedure in the map (-m): its code offset and name *)
    MapEntry = POINTER TO MapEntryDesc;
    MapEntryDesc = RECORD off: LONGINT; name: ARRAY 64 OF CHAR; next: MapEntry END;

  VAR
    mapOn*: BOOLEAN;     (* -m: Module.map, each procedure's code offset and name *)
    map, mapLast: MapEntry;   (* the map, in code order *)
    fixorgP, fixorgD, fixorgT: LONGINT;
    version: INTEGER;
    curModid: ORS.Ident;
    forDepth: LONGINT;                         (* current nested-FOR depth *)
    forPushed: ARRAY ORGI.maxForNest OF INTEGER;  (* the words this FOR's limit spilled, 0 none *)
    (* stashed at Enter for Return (shared ORP's Return(proc,x) lacks
       frame/expo/int; Enter and its Return never nest across another
       Enter, so single module vars suffice) *)
    curFrameSize: LONGINT;
    curExpo, curIntProc: BOOLEAN;


  (* --- calls & procedure frame --- *)
  PROCEDURE SaveRegs(r: LONGINT);
    VAR ri: LONGINT;
  BEGIN
    ri := 0; ORGI.Set16(TRUE, TRUE); ORGI.frame := ORGI.frame + 2 * r;
    REPEAT
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(ri));
      OCG.Pha;
      ri := ri + 1
    UNTIL ri >= r
  END SaveRegs;

  PROCEDURE RestoreRegs(r: LONGINT);
    VAR ri: LONGINT;
  BEGIN
    ri := r; ORGI.Set16(TRUE, TRUE);
    REPEAT
      ri := ri - 1;
      OCG.Pla;
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ri))
    UNTIL ri <= 0;
    ORGI.frame := ORGI.frame - 2 * r
  END RestoreRegs;

  PROCEDURE PrepCall*(VAR x: ORGI.Item; VAR r: LONGINT);
    VAR rcv: ORGI.Item;
  BEGIN
    IF x.ifaceDisp THEN
      (* interface dispatch: save outer context, then load the fat value's data
         word (the object pointer) from the interface designator as param 0.
         Call re-reads the itable from the same designator. *)
      r := ORGI.RH;
      IF ORGI.RH > 0 THEN SaveRegs(ORGI.RH); ORGI.RH := 0 END;
      ORGI.loadIfacePair(x.rcvMode, x.rcvA, x.rcvB, x.rcvR, 0, 0);
      ORGI.RH := 2
    ELSIF x.isMeth & ((x.rcvMode = ORGI.Reg) OR (x.rcvMode = ORGI.RegI)) THEN
      (* receiver already in registers [rcvR, rcvR+1] — a DeRef'd pointer
         (dynamic dispatch / SUPER) or a freshly-allocated instance (a
         constructor). Save the outer context below it, keep the receiver,
         and move it to R0/R1 as param 0; scratch/args then sit above it. *)
      r := x.rcvR;
      IF x.rcvR > 0 THEN SaveRegs(x.rcvR) END;
      IF x.rcvR # 0 THEN
        ORGI.Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.rcvR));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(0));
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.rcvR + 1));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(1))
      END;
      ORGI.RH := 2
    ELSE
      IF x.mode > ORB.Par THEN ORGI.load(x) END;
      r := ORGI.RH;
      IF ORGI.RH > 0 THEN SaveRegs(ORGI.RH); ORGI.RH := 0 END;
      IF x.isMeth THEN
        (* VAR-record receiver (static): reload it from memory as param 0 —
           addr+bank+tag — via VarParam. ParamList skips param 0. *)
        rcv.mode := x.rcvMode; rcv.a := x.rcvA; rcv.b := x.rcvB; rcv.r := x.rcvR;
        rcv.rdo := x.rcvRdo; rcv.type := x.rcvType; rcv.isMeth := FALSE;
        ORGE.VarParam(rcv, rcv.type)
      END
    END
  END PrepCall;

  PROCEDURE Call*(VAR x: ORGI.Item; r: LONGINT);
    VAR mno, exno, encoded, addrReg, bankReg: LONGINT; wide: BOOLEAN;
  BEGIN
    ORGI.Set16(TRUE, TRUE);
    IF x.ifaceDisp THEN
      (* interface dispatch: receiver (data) already in R0/R1. Re-read the
         itable from the interface designator, index it by the interface method
         index (methSlot) to get the record's vtable slot, then dispatch through
         the object's vtable exactly like dynamic dispatch (runtime slot). *)
      addrReg := ORGI.RegAddr(ORGI.RH);
      ORGI.loadIfacePair(x.rcvMode, x.rcvA, x.rcvB, x.rcvR, 4, ORGI.RH + 6);  (* itable ptr *)
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 6));
      OCG.Clc;
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, x.methSlot * 2);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 8));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 7));
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 9));
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, ORGI.RegAddr(ORGI.RH + 8));   (* slot index *)
      OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);
      OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);                    (* * SlotSize *)
      OCG.Clc;
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, ORGI.VtableOff);            (* vtable byte offset *)
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 8));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(0));            (* tag ptr = data - 4 *)
      OCG.Sec;
      OCG.gen1(OCG.SBC * 32 + OCG.mImm, 4);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 2));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(1));
      OCG.gen1(OCG.SBC * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 3));
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, ORGI.RegAddr(ORGI.RH + 2));   (* TD addr lo *)
      OCG.Clc;
      OCG.gen1(OCG.ADC * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 8));       (* + vtable byte offset *)
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 4));
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, 2);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, ORGI.RegAddr(ORGI.RH + 2));  (* TD bank *)
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 5));
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, ORGI.RegAddr(ORGI.RH + 4));   (* method address *)
      OCG.gen1(OCG.STA * 32 + OCG.mDP, addrReg);
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, 2);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, ORGI.RegAddr(ORGI.RH + 4));  (* its bank *)
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 6));
      OCG.Phk;
      OCG.gen1(OCG.PER * 32 + OCG.mImm, 0BH);                  (* return: after the RTL *)
      ORGI.Set8(TRUE, FALSE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 6));
      OCG.Pha;                                                 (* the method's bank *)
      ORGI.Set16(TRUE, FALSE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, addrReg);
      OCG.gen1(OCG.DEC * 32 + OCG.mAcc, 0);
      OCG.Pha;
      OCG.Rtl
    ELSIF x.dynDisp THEN
      (* dynamic dispatch: receiver (object pointer) is param 0 in R0/R1.
         tag := [obj-4]; the slot at tag + VtableOff + slot*SlotSize, which
         the loader has filled with the method's address and bank: the call
         goes there by RTL, the return address pushed first. Scratch above
         RH. *)
      addrReg := ORGI.RegAddr(ORGI.RH);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(0));
      OCG.Sec;
      OCG.gen1(OCG.SBC * 32 + OCG.mImm, 4);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 2));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(1));
      OCG.gen1(OCG.SBC * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 3));
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, ORGI.RegAddr(ORGI.RH + 2));   (* TD addr lo *)
      OCG.Clc;
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, ORGI.VtableOff + x.methSlot * ORGI.SlotSize);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 4));
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, 2);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, ORGI.RegAddr(ORGI.RH + 2));  (* TD bank *)
      OCG.gen1(OCG.ADC * 32 + OCG.mImm, 0);                    (* carry from lo add *)
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 5));
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, ORGI.RegAddr(ORGI.RH + 4));   (* method address *)
      OCG.gen1(OCG.STA * 32 + OCG.mDP, addrReg);
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, 2);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndLY, ORGI.RegAddr(ORGI.RH + 4));  (* its bank *)
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 6));
      OCG.Phk;
      OCG.gen1(OCG.PER * 32 + OCG.mImm, 0BH);                  (* return: after the RTL *)
      ORGI.Set8(TRUE, FALSE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 6));
      OCG.Pha;                                                 (* the method's bank *)
      ORGI.Set16(TRUE, FALSE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, addrReg);
      OCG.gen1(OCG.DEC * 32 + OCG.mAcc, 0);
      OCG.Pha;
      OCG.Rtl
    ELSIF x.mode = ORB.Const THEN
      IF x.r < 0 THEN
        mno := -x.r; exno := x.a;
        encoded := mno * 10000H + (exno MOD 10000H);
        OCG.gen1(OCG.JSL * 32 + OCG.mAbsL, encoded)
      ELSIF (x.b = 1) OR ORGI.largeMod THEN
        OCG.gen1(OCG.JSL * 32 + OCG.mAbsL, x.a)   (* far intra-module call *)
      ELSE
        OCG.gen1(OCG.JSR * 32 + OCG.mAbs, x.a)
      END
    ELSE
      IF x.mode <= ORB.Par THEN
        ORGI.load(x);
        addrReg := ORGI.RegAddr(ORGI.RH - 2); bankReg := ORGI.RegAddr(ORGI.RH - 1);
        IF ORGI.check THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, addrReg);
          OCG.gen1(OCG.ORA * 32 + OCG.mDP, bankReg);
          ORGI.Trap(ORGI.NE, 5)
        END;
        OCG.Phk;
        OCG.gen1(OCG.PER * 32 + OCG.mImm, 0BH);
        ORGI.Set8(TRUE, FALSE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, bankReg);
        OCG.Pha;
        ORGI.Set16(TRUE, FALSE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, addrReg);
        OCG.gen1(OCG.DEC * 32 + OCG.mAcc, 0);
        OCG.Pha;
        OCG.Rtl;
        ORGI.RH := ORGI.RH - 2
      ELSE
        (* the address was saved with the registers; take it back into
           the two above the arguments, which are in R0.. *)
        OCG.Pla;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 1));
        OCG.Pla;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));
        addrReg := ORGI.RegAddr(ORGI.RH); bankReg := ORGI.RegAddr(ORGI.RH + 1);
        r := r - 2; ORGI.frame := ORGI.frame - 4;
        IF ORGI.check THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, addrReg);
          OCG.gen1(OCG.ORA * 32 + OCG.mDP, bankReg);
          ORGI.Trap(ORGI.NE, 5)
        END;
        OCG.Phk;
        OCG.gen1(OCG.PER * 32 + OCG.mImm, 0BH);
        ORGI.Set8(TRUE, FALSE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, bankReg);
        OCG.Pha;
        ORGI.Set16(TRUE, FALSE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, addrReg);
        OCG.gen1(OCG.DEC * 32 + OCG.mAcc, 0);
        OCG.Pha;
        OCG.Rtl
      END
    END;
    IF x.type.base.form = ORB.NoTyp THEN
      IF r > 0 THEN RestoreRegs(r) END;
      ORGI.RH := r
    ELSE
      wide := (x.type.base.form = ORB.Pointer) OR (x.type.base.form = ORB.Real)
              OR (x.type.base.form = ORB.Proc) OR ORGI.IsLong(x.type.base);
      IF r > 0 THEN
        ORGI.Set16(TRUE, TRUE);
        IF wide THEN   (* the high word first: with r = 1 the low word lands on it *)
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(1));
          OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(r + 1))
        END;
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(0));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(r));
        RestoreRegs(r)
      END;
      x.mode := ORGI.Reg; x.r := r;
      IF wide THEN ORGI.RH := r + 2 ELSE ORGI.RH := r + 1 END
    END
  END Call;

  (* --- procedure entry / exit --- *)
  (* Shared-frontend signature: (proc, params, parblksize, locblksize,
     intProc). frame_size = parblksize + locblksize; expo = proc.expo. *)
  (* the procedure starting here, for the map: Type.Name for a method *)
  PROCEDURE AddMap(off: LONGINT): MapEntry;
    VAR e: MapEntry;
  BEGIN NEW(e); e.off := off; e.name[0] := 0X; e.next := NIL;
    IF map = NIL THEN map := e ELSE mapLast.next := e END;
    mapLast := e
    RETURN e
  END AddMap;

  PROCEDURE MapProc(proc, params: ORB.Object);
    VAR t: ORB.Type; i, j: INTEGER; e: MapEntry;
  BEGIN
    IF mapOn THEN
      e := AddMap(OCG.Here()); i := 0;
      IF (proc.class = ORB.Meth) & (params # NIL) THEN t := params.type;
        IF (t.typobj = NIL) & (t.form = ORB.Pointer) THEN t := t.base END;
        IF t.typobj # NIL THEN
          j := 0; WHILE (t.typobj.name[j] # 0X) & (i < 40) DO e.name[i] := t.typobj.name[j]; INC(i); INC(j) END;
          e.name[i] := "."; INC(i)
        END
      END;
      j := 0; WHILE (proc.name[j] # 0X) & (i < 63) DO e.name[i] := proc.name[j]; INC(i); INC(j) END;
      e.name[i] := 0X
    END
  END MapProc;

  PROCEDURE Enter*(proc, params: ORB.Object; parblksize, locblksize: LONGINT; intProc: BOOLEAN);
    VAR r, frameSize, n: LONGINT; param: ORB.Object;
      paramItem, regItem: ORGI.Item;
  BEGIN MapProc(proc, params);
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
      ORGI.Set16(TRUE, TRUE);
      IF curExpo THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.SB_DP);
        OCG.Pha;
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.BANK_DP);
        OCG.Pha;
        OCG.AddRel(OCG.Here());
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.SB_DP);
        OCG.AddRel(OCG.Here() + 80000000H);
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.BANK_DP)
      END;
      IF frameSize > 0 THEN
        OCG.Tsc;
        OCG.Sec;
        OCG.gen1(OCG.SBC * 32 + OCG.mImm, frameSize);
        OCG.Tcs
      END;
      (* the parameters, from their registers to the frame: nofpar of them
         (the receiver counted). params is the whole scope, the locals
         after them, and a local is a Var too: not stored, garbage, and
         with a big frame beyond d,S's reach *)
      r := 0; param := params; n := proc.type.nofpar; ORGI.Set16(TRUE, TRUE);
      WHILE (param # NIL) & (n > 0) & ((param.class = ORB.Var) OR (param.class = ORB.Par)) DO
        IF (param.class = ORB.Par) & (param.type.form = ORB.Array) & (param.type.len < 0) THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r + 1));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 2);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r + 2));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 4)
        ELSIF (param.class = ORB.Par) & (param.type.form = ORB.Record) THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r + 1));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 2);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r + 2));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 4);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r + 3));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 6)
        ELSIF param.class = ORB.Par THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r + 1));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 2)
        ELSIF (param.type.form = ORB.Real) OR (param.type.form = ORB.Proc) THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r + 1));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 2)
        ELSIF param.type.form = ORB.Intfc THEN
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r + 1));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 2);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r + 2));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 4);
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(r + 3));
          OCG.gen1(OCG.STA * 32 + OCG.mSR, param.val + 6)
        ELSE
          ORGI.MakeItem(paramItem, param, param.lev);
          regItem.mode := ORGI.Reg; regItem.type := param.type;
          regItem.r := r; regItem.rdo := TRUE;
          ORGI.Store(paramItem, regItem)
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
        param := param.next; DEC(n)
      END;
      ORGI.RH := 0
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
  PROCEDURE Return*(proc: ORB.Object; VAR x: ORGI.Item);
    VAR form, size: LONGINT;
  BEGIN
    form := proc.type.base.form; size := curFrameSize;
    IF form # ORB.NoTyp THEN ORGI.load(x) END;
    IF ~curIntProc THEN
      ORGI.Set16(TRUE, TRUE);
      IF size > 0 THEN
        OCG.Tsc;
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mImm, size);
        OCG.Tcs
      END;
      (* SB save/restore is only for genuinely cross-module-reachable procs
         (curExpo); an intra-module large-model proc runs with the caller's
         SB (same module) so it skips the dance. The far RETURN convention
         (RTL) is separate: needed whenever the proc is reached by a long
         call — every proc in a LARGE module is. *)
      IF curExpo THEN
        OCG.Pla;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.BANK_DP);
        OCG.Pla;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.SB_DP)
      END;
      IF curExpo OR ORGI.largeMod THEN OCG.Rtl ELSE OCG.Rts END
    ELSE
      IF size > 0 THEN
        OCG.Clc;
        OCG.gen1(OCG.ADC * 32 + OCG.mImm, size);
        OCG.Tcs
      END;
      OCG.Rti
    END;
    ORGI.RH := 0
  END Return;

  (* --- inline standard procedures --- *)
  PROCEDURE Increment*(upordown: LONGINT; VAR x, y: ORGI.Item);
    VAR zr: LONGINT; isByte, isInc, useIncDec: BOOLEAN; z: ORGI.Item;
  BEGIN
    isByte := x.type = ORB.byteType; isInc := upordown = 0;
    IF y.type.form = ORB.NoTyp THEN y.mode := ORB.Const; y.a := 1 END;
    useIncDec := (y.mode = ORB.Const) & (y.a = 1);
    IF ~ORGI.IsLong(x.type) THEN ORGI.cvt(y, FALSE) END;   (* a LONGINT step: its low word *)
    IF ORGI.IsLong(x.type) THEN
      (* x := x + y on a copy z of the designator. The step is loaded
         first so that it is the top of the stack when it is widened. *)
      IF y.mode = ORB.Const THEN y.type := ORB.longType ELSE ORGI.cvt(y, TRUE); ORGI.load(y) END;
      z := x;
      IF x.mode = ORGI.RegI THEN   (* z's value replaces a copy of the address *)
        ORGI.Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 1));
        z.r := ORGI.RH; ORGI.incR; ORGI.incR
      END;
      ORGI.load(z);
      IF isInc THEN ORGE.AddOp(ORS.plus, z, y) ELSE ORGE.AddOp(ORS.minus, z, y) END;
      ORGI.Store(x, z)
    ELSIF (x.mode = ORB.Var) & (x.r > 0) THEN
      zr := ORGI.RH;
      IF isByte THEN ORGI.Set8(TRUE, FALSE) ELSE ORGI.Set16(TRUE, TRUE) END;
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + ORGI.frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(zr));
      ORGI.incR;
      IF y.mode = ORB.Const THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(zr));
        IF useIncDec THEN
          IF isInc THEN OCG.gen1(OCG.INC * 32 + OCG.mAcc, 0) ELSE OCG.gen1(OCG.DEC * 32 + OCG.mAcc, 0) END
        ELSIF isInc THEN
          OCG.Clc; OCG.gen1(OCG.ADC * 32 + OCG.mImm, y.a)
        ELSE
          OCG.Sec; OCG.gen1(OCG.SBC * 32 + OCG.mImm, y.a)
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(zr))
      ELSE
        ORGI.load(y);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(zr));
        IF isInc THEN
          OCG.Clc; OCG.gen1(OCG.ADC * 32 + OCG.mDP, ORGI.RegAddr(y.r))
        ELSE
          OCG.Sec; OCG.gen1(OCG.SBC * 32 + OCG.mDP, ORGI.RegAddr(y.r))
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(zr)); ORGI.RH := ORGI.RH - 1
      END;
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(zr));
      OCG.gen1(OCG.STA * 32 + OCG.mSR, x.a + ORGI.frame);
      IF isByte THEN ORGI.Set16(TRUE, TRUE) END;
      ORGI.RH := ORGI.RH - 1
    ELSE
      (* through the address loadAdr leaves with its bank: a record a pointer
         points to need not be in bank 0, where abs,X would go *)
      ORGI.loadAdr(x); zr := ORGI.RH;
      IF isByte THEN ORGI.Set8(TRUE, FALSE) ELSE ORGI.Set16(TRUE, TRUE) END;
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, ORGI.RegAddr(x.r));   (* [address, bank] *)
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(zr));
      ORGI.incR;
      IF y.mode = ORB.Const THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(zr));
        IF useIncDec THEN
          IF isInc THEN OCG.gen1(OCG.INC * 32 + OCG.mAcc, 0) ELSE OCG.gen1(OCG.DEC * 32 + OCG.mAcc, 0) END
        ELSIF isInc THEN
          OCG.Clc; OCG.gen1(OCG.ADC * 32 + OCG.mImm, y.a)
        ELSE
          OCG.Sec; OCG.gen1(OCG.SBC * 32 + OCG.mImm, y.a)
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(zr))
      ELSE
        ORGI.load(y);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(zr));
        IF isInc THEN
          OCG.Clc; OCG.gen1(OCG.ADC * 32 + OCG.mDP, ORGI.RegAddr(y.r))
        ELSE
          OCG.Sec; OCG.gen1(OCG.SBC * 32 + OCG.mDP, ORGI.RegAddr(y.r))
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(zr)); ORGI.RH := ORGI.RH - 1
      END;
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(zr));
      OCG.gen1(OCG.STA * 32 + OCG.mDPIndL, ORGI.RegAddr(x.r));
      IF isByte THEN ORGI.Set16(TRUE, TRUE) END;
      ORGI.RH := ORGI.RH - 3
    END
  END Increment;

  PROCEDURE Include*(inorex: LONGINT; VAR x, y: ORGI.Item);
    VAR orig: ORGI.Item; zr, mask, skip, loopTop: LONGINT;
  BEGIN
    orig := x;
    IF (x.mode = ORB.Var) & (x.r > 0) THEN
      ORGI.Set16(TRUE, TRUE); zr := ORGI.RH;
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + ORGI.frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(zr));
      ORGI.incR;
      IF y.mode = ORB.Const THEN
        mask := ORGI.Lo16(ASL(1, y.a));
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(zr));
        IF inorex = 0 THEN OCG.gen1(OCG.ORA * 32 + OCG.mImm, mask)
        ELSE OCG.gen1(OCG.AND * 32 + OCG.mImm, ORGI.Lo16(EOR(mask, 0FFFFH)))
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(zr))
      ELSE
        ORGI.load(y);
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, 1);
        OCG.gen1(OCG.LDX * 32 + OCG.mDP, ORGI.RegAddr(y.r));
        skip := OCG.Here() + 2 + 4;
        OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, skip);
        loopTop := OCG.Here();
        OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);
        OCG.Dex;
        OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
        IF inorex = 0 THEN OCG.gen1(OCG.ORA * 32 + OCG.mDP, ORGI.RegAddr(zr))
        ELSE
          OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
          OCG.gen1(OCG.AND * 32 + OCG.mDP, ORGI.RegAddr(zr))
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(zr)); ORGI.RH := ORGI.RH - 1
      END;
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(zr));
      OCG.gen1(OCG.STA * 32 + OCG.mSR, orig.a + ORGI.frame);
      ORGI.RH := ORGI.RH - 1
    ELSE
      ORGI.loadAdr(x); zr := ORGI.RH; ORGI.Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDPIndL, ORGI.RegAddr(x.r));   (* [address, bank] *)
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(zr));
      ORGI.incR;
      IF y.mode = ORB.Const THEN
        mask := ORGI.Lo16(ASL(1, y.a));
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(zr));
        IF inorex = 0 THEN OCG.gen1(OCG.ORA * 32 + OCG.mImm, mask)
        ELSE OCG.gen1(OCG.AND * 32 + OCG.mImm, ORGI.Lo16(EOR(mask, 0FFFFH)))
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(zr))
      ELSE
        ORGI.load(y);
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, 1);
        OCG.gen1(OCG.LDX * 32 + OCG.mDP, ORGI.RegAddr(y.r));
        skip := OCG.Here() + 2 + 4;
        OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, skip);
        loopTop := OCG.Here();
        OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);
        OCG.Dex;
        OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
        IF inorex = 0 THEN OCG.gen1(OCG.ORA * 32 + OCG.mDP, ORGI.RegAddr(zr))
        ELSE
          OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
          OCG.gen1(OCG.AND * 32 + OCG.mDP, ORGI.RegAddr(zr))
        END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(zr)); ORGI.RH := ORGI.RH - 1
      END;
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(zr));
      OCG.gen1(OCG.STA * 32 + OCG.mDPIndL, ORGI.RegAddr(x.r));
      ORGI.RH := ORGI.RH - 3
    END
  END Include;

  PROCEDURE Assert*(VAR x: ORGI.Item);
  BEGIN
    (* where the condition holds, branch over the trap; where it fails,
       fall or jump into it *)
    IF x.mode # ORGI.Cond THEN ORGI.loadCond(x) END;
    x.b := ORGI.chain(x.r, x.origType, x.b);
    ORGI.FixLink(x.a);
    OCG.gen1(OCG.BRK * 32 + OCG.mImm, 7);
    ORGI.FixLink(x.b)
  END Assert;

  (* Emit the type-tag pointer {TD offset, its bank} into the two-word reg 'tag'. *)
  PROCEDURE emitTag(baseType: ORB.Type; tag: LONGINT);
    VAR sb: LONGINT;
  BEGIN
    ORGI.Set16(TRUE, TRUE);
    sb := ORGI.GetSB(-baseType.mno);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, sb);
    OCG.Clc;
    ORGE.emitTDLen(baseType);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(tag));
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.BankOf(sb));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(tag + 1))
  END emitTag;

  (* obj := HeapManager.Alloc(size, 0), its type tag written at [obj-4] (the
     [obj-4] contract): the object in registers obj.r, obj.r + 1. NEW and
     constructors allocate only so: a module that does not import
     HeapManager imports it here. FALSE (and an error) without its symbol
     file. *)
  PROCEDURE HeapNew(baseType: ORB.Type; VAR px: ORGI.Item): BOOLEAN;
    VAR argSz, argTd: ORGI.Item; allocObj: ORB.Object; tagReg, objm4Reg, rx: LONGINT; ok: BOOLEAN;
  BEGIN
    allocObj := ORB.FindImport("HeapManager", "Alloc");
    IF allocObj = NIL THEN ORB.ImportLate("HeapManager"); allocObj := ORB.FindImport("HeapManager", "Alloc") END;
    ok := allocObj # NIL;
    IF ~ok THEN ORS.Mark("NEW needs HeapManager (its symbol file)")
    ELSE
      ORGI.MakeItem(px, allocObj, 0);
      PrepCall(px, rx);
      ORGI.MakeConstItem(argSz, ORB.intType, baseType.size); ORGE.ValueParam(argSz, ORB.longType);
      ORGI.MakeConstItem(argTd, ORB.intType, 0);             ORGE.ValueParam(argTd, ORB.longType);
      Call(px, rx);                       (* px := obj (Reg, two words) *)
      ORGI.Set16(TRUE, TRUE);
      tagReg := ORGI.RH; emitTag(baseType, tagReg); ORGI.incR; ORGI.incR;
      objm4Reg := ORGI.RH;                     (* objm4 := obj - 4 *)
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(px.r));
      OCG.Sec; OCG.gen1(OCG.SBC * 32 + OCG.mImm, 4);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(objm4Reg));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(px.r + 1));
      OCG.gen1(OCG.SBC * 32 + OCG.mImm, 0);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(objm4Reg + 1));
      ORGI.incR; ORGI.incR;
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(tagReg));       (* [objm4] := tag *)
      OCG.gen1(OCG.STA * 32 + OCG.mDPIndL, ORGI.RegAddr(objm4Reg));
      OCG.gen1(OCG.LDY * 32 + OCG.mImm, 2);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(tagReg + 1));
      OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, ORGI.RegAddr(objm4Reg));
      ORGI.RH := tagReg                        (* free the two temp pairs *)
    END
  RETURN ok
  END HeapNew;

  PROCEDURE New*(VAR x: ORGI.Item);
    VAR baseType: ORB.Type; y, z, px: ORGI.Item;
  BEGIN
    baseType := x.type.base; y := x;
    IF HeapNew(baseType, px) THEN z := px; z.type := y.type; ORGI.Store(y, z) END
  END New;

  PROCEDURE Pack*(VAR x, y: ORGI.Item);
    VAR z: ORGI.Item;
  BEGIN z := x; ORGI.load(x); ORGI.load(y); ORGI.RH := ORGI.RH - 1; ORGI.Store(z, x)
  END Pack;

  PROCEDURE Unpk*(VAR x, y: ORGI.Item);
    VAR z, e0: ORGI.Item;
  BEGIN
    z := x; ORGI.load(x);
    e0.mode := ORGI.Reg; e0.r := ORGI.RH; e0.type := ORB.intType;
    ORGI.Store(y, e0);
    ORGI.incR;
    ORGI.Store(z, x)
  END Unpk;

  PROCEDURE IntEn*(VAR x: ORGI.Item);
  BEGIN
  END IntEn;

  (* SYSTEM.GET's or PUT's bank, just parsed: loaded and pushed on the
     hardware stack until GetB or PutB, its registers free for the
     address and the value parsed after it. Loaded after them instead, a
     bank that held registers (a field through a pointer) was left below
     them, and the pointer pair was the address and whatever was above
     it. frame += 2 shifts the stack-relative accesses meanwhile. *)
  PROCEDURE SpillBank*(VAR bank: ORGI.Item);
  BEGIN ORGI.load(bank); ORGI.Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(bank.r)); OCG.Pha;
    ORGI.RH := bank.r; ORGI.frame := ORGI.frame + 2
  END SpillBank;

  (* The pointer pair GetB and PutB want, (address, bank), at the top of
     the registers, which Store frees: the address loaded and, if other's
     registers are above it, moved up past them (theirs down one); then
     the bank pulled into the register after it *)
  PROCEDURE BankPair(VAR addr, other: ORGI.Item);
    VAR i: LONGINT;
  BEGIN ORGI.load(addr); ORGI.Set16(TRUE, TRUE);
    IF addr.r < ORGI.RH - 1 THEN
      OCG.gen1(OCG.LDX * 32 + OCG.mDP, ORGI.RegAddr(addr.r));
      FOR i := addr.r TO ORGI.RH - 2 DO
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(i + 1)); OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(i))
      END;
      OCG.gen1(OCG.STX * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH - 1));
      IF ((other.mode = ORGI.Reg) OR (other.mode = ORGI.RegI)) & (other.r > addr.r) THEN other.r := other.r - 1 END;
      addr.r := ORGI.RH - 1
    END;
    OCG.Pla; OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH)); ORGI.incR; ORGI.frame := ORGI.frame - 2
  END BankPair;

  PROCEDURE GetB*(VAR bank, addr, var: ORGI.Item);
  BEGIN BankPair(addr, var);
    addr.type := var.type; addr.mode := ORGI.RegI; addr.a := 0;
    ORGI.Store(var, addr)
  END GetB;

  PROCEDURE PutB*(VAR bank, addr, val: ORGI.Item);
  BEGIN BankPair(addr, val);
    addr.type := val.type; addr.mode := ORGI.RegI; addr.a := 0;
    ORGI.Store(addr, val)
  END PutB;

  PROCEDURE Get*(VAR addr, var: ORGI.Item);
  BEGIN ORS.Mark("2-arg GET not supported on 65C816")
  END Get;

  PROCEDURE Put*(VAR addr, val: ORGI.Item);
  BEGIN ORS.Mark("2-arg PUT not supported on 65C816")
  END Put;

  PROCEDURE Copy*(VAR x, y, z: ORGI.Item);
    VAR loopTop: LONGINT;
  BEGIN
    ORGI.load(x); ORGI.load(y);
    IF z.mode = ORB.Const THEN
      IF z.a > 0 THEN ORGI.load(z) ELSE ORS.Mark("bad count") END
    ELSE
      ORGI.load(z);
      IF ORGI.check THEN ORGI.Trap(ORGI.LT, 3) END
    END;
    ORGI.Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDY * 32 + OCG.mImm, 0);
    loopTop := OCG.Here();
    OCG.gen1(OCG.LDA * 32 + OCG.mDPIndY, ORGI.RegAddr(x.r));
    OCG.gen1(OCG.STA * 32 + OCG.mDPIndY, ORGI.RegAddr(y.r));
    OCG.Iny;
    OCG.Iny;
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(z.r));
    OCG.gen1(OCG.DEC * 32 + OCG.mAcc, 0);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(z.r));
    OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
    ORGI.RH := ORGI.RH - 3
  END Copy;

  PROCEDURE TRB*(VAR x, y: ORGI.Item);
  BEGIN
    IF x.mode = ORB.Const THEN
      ORGI.load(y); ORGI.Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r));
      OCG.gen1(OCG.TRB * 32 + OCG.mAbs, x.a);
      ORGI.RH := ORGI.RH - 1
    ELSE
      ORGI.load(x); ORGI.load(y); ORGI.Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r));
      OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
      OCG.gen1(OCG.AND * 32 + OCG.mDPInd, ORGI.RegAddr(x.r));
      OCG.gen1(OCG.STA * 32 + OCG.mDPInd, ORGI.RegAddr(x.r));
      ORGI.RH := ORGI.RH - 2
    END
  END TRB;

  PROCEDURE TSB*(VAR x, y: ORGI.Item);
  BEGIN
    IF x.mode = ORB.Const THEN
      ORGI.load(y); ORGI.Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r));
      OCG.gen1(OCG.TSB * 32 + OCG.mAbs, x.a);
      ORGI.RH := ORGI.RH - 1
    ELSE
      ORGI.load(x); ORGI.load(y); ORGI.Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r));
      OCG.gen1(OCG.ORA * 32 + OCG.mDPInd, ORGI.RegAddr(x.r));
      OCG.gen1(OCG.STA * 32 + OCG.mDPInd, ORGI.RegAddr(x.r));
      ORGI.RH := ORGI.RH - 2
    END
  END TSB;

  PROCEDURE Exec*(VAR addr, bank: ORGI.Item);
    VAR addrReg, bankReg: LONGINT;
  BEGIN
    ORGI.load(addr); ORGI.load(bank);
    addrReg := ORGI.RegAddr(addr.r); bankReg := ORGI.RegAddr(bank.r);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.SB_DP);
    OCG.Pha;
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.BANK_DP);
    OCG.Pha;
    OCG.Phk;
    OCG.gen1(OCG.PER * 32 + OCG.mImm, 0BH);
    ORGI.Set8(TRUE, FALSE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, bankReg);
    OCG.Pha;
    ORGI.Set16(TRUE, FALSE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, addrReg);
    OCG.gen1(OCG.DEC * 32 + OCG.mAcc, 0);
    OCG.Pha;
    OCG.Rtl;
    OCG.Pla;
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.BANK_DP);
    OCG.Pla;
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.SB_DP);
    ORGI.RH := ORGI.RH - 2
  END Exec;

  (* --- inline functions --- *)
  PROCEDURE Abs*(VAR x: ORGI.Item);
    VAR p: LONGINT;
  BEGIN
    IF x.mode = ORB.Const THEN
      IF x.a < 0 THEN x.a := -x.a END
    ELSE
      ORGI.load(x);
      IF x.type.form = ORB.Real THEN
        ORGI.Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
        OCG.gen1(OCG.AND * 32 + OCG.mImm, 7FFFH);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1))
      ELSIF ORGI.IsLong(x.type) THEN
        ORGI.Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
        p := ORGI.emitFwdBranch(OCG.BPL);
        ORGI.longNeg(x.r);
        ORGI.patch(p)
      ELSE
        ORGI.Set16(TRUE, TRUE);
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        OCG.gen1(OCG.BPL * 32 + OCG.mPCR, OCG.Here() + 2 + 6);
        OCG.gen1(OCG.EOR * 32 + OCG.mImm, 0FFFFH);
        OCG.gen1(OCG.INC * 32 + OCG.mAcc, 0);
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r))
      END
    END
  END Abs;

  PROCEDURE Odd*(VAR x: ORGI.Item);
  BEGIN
    ORGI.load(x); ORGI.Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
    OCG.gen1(OCG.AND * 32 + OCG.mImm, 1);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
    IF ORGI.IsLong(x.type) THEN ORGI.RH := ORGI.RH - 1 END;   (* the low word decides *)
    ORGI.SetCC(x, ORGI.NE); ORGI.RH := ORGI.RH - 1
  END Odd;

  PROCEDURE Floor*(VAR x: ORGI.Item);
  BEGIN
    ORGI.load(x); ORGI.Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_A_LO);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_A_HI);
    ORGFP.AddFixup(ORGFP.FP_FLOOR); OCG.gen1(OCG.JSR * 32 + OCG.mAbs, 0);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGFP.FP_A_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
    ORGI.RH := ORGI.RH - 1; x.type := ORB.intType
  END Floor;

  PROCEDURE Float*(VAR x: ORGI.Item);
  BEGIN
    ORGI.load(x); ORGI.Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGFP.FP_A_LO);
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, ORGFP.FP_A_HI);
    ORGFP.AddFixup(ORGFP.FP_FLT); OCG.gen1(OCG.JSR * 32 + OCG.mAbs, 0);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGFP.FP_A_LO);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGFP.FP_A_HI);
    ORGI.incR;
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
    x.type := ORB.realType
  END Float;

  PROCEDURE Ord*(VAR x: ORGI.Item);
  BEGIN
    IF (x.mode = ORB.Var) OR (x.mode = ORB.Par) OR (x.mode = ORGI.RegI) OR (x.mode = ORGI.Cond) THEN
      ORGI.load(x)
    END
  END Ord;

  (* CHR(x): INTEGER -> CHAR. Same materialisation as Ord (identical bytes),
     but the result is typed CHAR — the low byte is the character; a store to
     a 1-byte CHAR destination already narrows it. *)
  PROCEDURE Chr*(VAR x: ORGI.Item);
  BEGIN
    IF (x.mode = ORB.Var) OR (x.mode = ORB.Par) OR (x.mode = ORGI.RegI) OR (x.mode = ORGI.Cond) THEN
      ORGI.load(x)
    END;
    x.type := ORB.charType
  END Chr;

  PROCEDURE Len*(VAR x: ORGI.Item);
  BEGIN
    IF x.type.len >= 0 THEN
      IF x.mode = ORGI.RegI THEN ORGI.RH := x.r END;   (* the address and its bank, both *)
      x.mode := ORB.Const; x.a := x.type.len
    ELSE
      ORGI.Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mSR, x.a + 4 + ORGI.frame);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));
      x.mode := ORGI.Reg; x.r := ORGI.RH; ORGI.incR
    END
  END Len;

  (* The result of x op y, in A, into the lower of x's and y's registers,
     those above it freed. x is not always below y: a constant x is loaded
     only here, after y's registers (a pointer and its bank for r.f) were
     taken, so RH - 2 and "free the top one" do not hold. *)
  PROCEDURE binResult(VAR x, y: ORGI.Item);
  BEGIN
    IF y.r < x.r THEN x.r := y.r END;
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
    ORGI.RH := x.r + 1
  END binResult;

  PROCEDURE Shift*(fct: LONGINT; VAR x, y: ORGI.Item);
    VAR op, i, L: LONGINT;
  BEGIN
    ORGI.load(x);
    IF fct = 0 THEN op := OCG.ASL
    ELSIF fct = 1 THEN op := OCG.LSR
    ELSE op := OCG.ROL
    END;
    IF y.mode = ORB.Const THEN
      IF y.a = 1 THEN OCG.gen1(op * 32 + OCG.mDP, ORGI.RegAddr(x.r))
      ELSE
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        i := 0;
        WHILE i < y.a DO OCG.gen1(op * 32 + OCG.mImpl, 0); i := i + 1 END;
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r))
      END
    ELSE
      (* Runtime shift count: the 65C816 has no barrel shifter, so shift the
         value (in its DP register) one place at a time, counting the count
         register down. Value and count both stay in DP; nothing else is
         clobbered. Loop body is 6 bytes (op:2 + DEC:2 + BNE:2), so the
         count=0 guard branches past it to Here()+2(BEQ)+6. *)
      ORGI.load(y);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r));      (* A := count (sets Z) *)
      OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 8);   (* count = 0 -> skip *)
      L := OCG.Here();
      OCG.gen1(op * 32 + OCG.mDP, ORGI.RegAddr(x.r));           (* value shifted once *)
      OCG.gen1(OCG.DEC * 32 + OCG.mDP, ORGI.RegAddr(y.r));      (* count-- (sets Z) *)
      OCG.gen1(OCG.BNE * 32 + OCG.mPCR, L);                (* repeat while # 0 *)
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      binResult(x, y)
    END
  END Shift;

  (* AND, EOR, ORA; of a LONGINT x both words (an INTEGER y sign-extended),
     the result in the lower of the two register pairs *)
  PROCEDURE Bitwise*(fct: LONGINT; VAR x, y: ORGI.Item);
    VAR op, dst: LONGINT;
  BEGIN
    ORGI.load(x);
    IF fct = 0 THEN op := OCG.AND
    ELSIF fct = 1 THEN op := OCG.EOR
    ELSE op := OCG.ORA
    END;
    IF ORGI.IsLong(x.type) THEN
      ORGI.Set16(TRUE, TRUE);
      IF y.mode = ORB.Const THEN
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, ORGI.Lo16(y.a));
        OCG.gen1(op * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        OCG.gen1(OCG.LDA * 32 + OCG.mImm, ORGI.Hi16(y.a));
        OCG.gen1(op * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1))
      ELSE
        ORGI.load(y);
        IF ~ORGI.IsLong(y.type) THEN ORGI.cvt(y, TRUE) END;
        IF y.r < x.r THEN dst := y.r ELSE dst := x.r END;
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r));
        OCG.gen1(op * 32 + OCG.mDP, ORGI.RegAddr(x.r));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(dst));
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r + 1));
        OCG.gen1(op * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
        OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(dst + 1));
        x.r := dst; ORGI.RH := dst + 2
      END
    ELSIF y.mode = ORB.Const THEN
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, ORGI.Lo16(y.a));
      OCG.gen1(op * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r))
    ELSE
      ORGI.load(y);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r));
      OCG.gen1(op * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      binResult(x, y)
    END
  END Bitwise;

  PROCEDURE UML*(VAR x, y: ORGI.Item);
  BEGIN ORGI.load(x); ORGI.load(y); ORGI.RH := ORGI.RH - 1
  END UML;

  PROCEDURE Bit*(VAR x, y: ORGI.Item);
    VAR loopTop: LONGINT;
  BEGIN
    ORGI.load(x);
    OCG.gen1(OCG.STZ * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));
    ORGI.incR;
    x.mode := ORGI.RegI; x.a := 0; x.type := ORB.intType;
    ORGI.load(x);
    ORGI.Set16(TRUE, TRUE);
    IF y.mode = ORB.Const THEN
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      OCG.gen1(OCG.AND * 32 + OCG.mImm, ASL(1, y.a));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      ORGI.RH := ORGI.RH - 1
    ELSE
      ORGI.load(y);
      OCG.gen1(OCG.LDA * 32 + OCG.mImm, 1);
      OCG.gen1(OCG.LDX * 32 + OCG.mDP, ORGI.RegAddr(y.r));
      OCG.gen1(OCG.BEQ * 32 + OCG.mPCR, OCG.Here() + 2 + 4);
      loopTop := OCG.Here();
      OCG.gen1(OCG.ASL * 32 + OCG.mAcc, 0);
      OCG.Dex;
      OCG.gen1(OCG.BNE * 32 + OCG.mPCR, loopTop);
      OCG.gen1(OCG.AND * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      ORGI.RH := ORGI.RH - 2
    END;
    ORGI.SetCC(x, ORGI.NE)
  END Bit;

  PROCEDURE HH*(VAR x: ORGI.Item);
  BEGIN x.mode := ORGI.Reg; x.r := ORGI.RH; ORGI.incR
  END HH;

  PROCEDURE Adr*(VAR x: ORGI.Item);
  BEGIN
    IF (x.mode = ORB.Var) OR (x.mode = ORB.Par) OR (x.mode = ORGI.RegI) THEN
      ORGI.loadAdr(x); ORGI.RH := ORGI.RH - 1
    ELSIF (x.mode = ORB.Const) & (x.type.form = ORB.Proc) THEN ORGI.load(x)
    ELSIF (x.mode = ORB.Const) & (x.type.form = ORB.String) THEN ORGI.loadStringAdr(x)
    ELSIF (x.mode = ORB.Const) &
          ((x.type.form = ORB.Array) OR (x.type.form = ORB.Record)) THEN ORGI.loadStringAdr(x)
    ELSE ORS.Mark("not addressable")
    END
  END Adr;

  PROCEDURE Bank*(VAR x: ORGI.Item);
  BEGIN
    IF (x.mode = ORB.Var) OR (x.mode = ORB.Par) OR (x.mode = ORGI.RegI) THEN
      ORGI.loadAdr(x); ORGI.Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
      ORGI.RH := ORGI.RH - 1
    ELSIF (x.mode = ORB.Const) &
          ((x.type.form = ORB.Array) OR (x.type.form = ORB.Record) OR (x.type.form = ORB.String)) THEN
      ORGI.Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.BANK_DP);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));
      x.mode := ORGI.Reg; x.r := ORGI.RH; ORGI.incR
    ELSE ORS.Mark("not addressable")
    END
  END Bank;

  PROCEDURE Condition*(VAR x: ORGI.Item);
  BEGIN ORGI.SetCC(x, x.a)
  END Condition;

  (* --- module management --- *)
  PROCEDURE Open*(modid: ARRAY OF CHAR; v: INTEGER; large: BOOLEAN);
    VAR i: INTEGER;
  BEGIN
    curModid := modid; ORGI.largeMod := large;
    OCG.Init; OCG.SetLarge(large); OCG.SetPc(ORGI.CodeOrg);
    ORGE.tdx := 0; ORGI.strx := 0; ORGI.RH := 0; forDepth := 0; map := NIL; mapLast := NIL;
    fixorgP := 0; fixorgD := 0; fixorgT := 0;
    ORGE.tdFixupC := 0; ORGE.tdListC := 0; ORGE.tdRefC := 0; ORGE.vtFixC := 0;
    ORGE.itabC := 0; ORGE.itabRefC := 0;
    ORGFP.Init; ORGI.nofFar := 0;
    ORGI.check := v # 0; version := v;
    IF v = 0 THEN
      OCG.SetPc(1);
      WHILE OCG.Here() < 8 DO OCG.Patch(OCG.Here(), 0); OCG.SetPc(OCG.Here() + 1) END
    END;
    OCG.SetLongA(TRUE); OCG.SetLongI(TRUE)
  END Open;

  (* -m, for a driver in Oberon (main.c sets mapOn) *)
  PROCEDURE SetMap*(on: BOOLEAN);
  BEGIN mapOn := on
  END SetMap;

  PROCEDURE SetDataSize*(dc: LONGINT);
  BEGIN ORGI.varsize := dc
  END SetDataSize;

  PROCEDURE Header*;
    VAR e: MapEntry;
  BEGIN
    ORGI.entry := OCG.Here();
    IF mapOn THEN e := AddMap(ORGI.entry); e.name := "BEGIN" END;
    OCG.SetLongA(TRUE); OCG.SetLongI(TRUE);
    OCG.AddRel(OCG.Here());
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.SB_DP);
    OCG.AddRel(OCG.Here() + 80000000H);
    OCG.gen1(OCG.LDA * 32 + OCG.mImm, 0);
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.BANK_DP)
  END Header;


  (* Emit the .816 module — unless a fixed backend buffer overflowed while
     generating code, in which case the code/reloc tables are truncated and
     the module would be silently wrong. Mark instead so the compile fails
     cleanly (this is the clean-abort for an over-large module; the raw
     overflow used to run past the reloc array and segfault). *)
  (* modid.map: a line for each procedure, its code offset in hex and its name *)
  PROCEDURE WriteMap(modid: ARRAY OF CHAR);
    VAR f: Files.File; r: Files.Rider; name: ARRAY 40 OF CHAR; path: ARRAY 256 OF CHAR; hex: ARRAY 6 OF CHAR; i, d: INTEGER; v: LONGINT;
      e: MapEntry;
  BEGIN
    i := 0; WHILE (modid[i] # 0X) & (i < 32) DO name[i] := modid[i]; INC(i) END;
    name[i] := "."; name[i + 1] := "m"; name[i + 2] := "a"; name[i + 3] := "p"; name[i + 4] := 0X;
    ORH.FileName(name, path); f := Files.New(path); Files.Set(r, f, 0);
    e := map;
    WHILE e # NIL DO
      v := e.off;
      FOR i := 5 TO 0 BY -1 DO d := v MOD 16; v := v DIV 16;
        IF d < 10 THEN hex[i] := CHR(ORD("0") + d) ELSE hex[i] := CHR(ORD("A") + d - 10) END
      END;
      FOR i := 0 TO 5 DO Files.WriteByte(r, ORD(hex[i])) END;
      Files.WriteByte(r, 20H); i := 0;
      WHILE e.name[i] # 0X DO Files.WriteByte(r, ORD(e.name[i])); INC(i) END;
      Files.WriteByte(r, 0AH); e := e.next
    END;
    Files.Register(f)
  END WriteMap;

  PROCEDURE Close*(modid: ARRAY OF CHAR; key: LONGINT; nofent: LONGINT);
    VAR wInfo: ORGW.ModInfo;
  BEGIN
    IF mapOn THEN WriteMap(modid) END;
    IF ORGFP.Full() THEN ORS.Mark("too many REAL or LONGINT operations")
    ELSIF OCG.Faulted() THEN
      ORS.Mark("program too large: code or relocation table overflow")
    ELSE
      OCG.Rtl;   (* exit: emulator calls main with JSL, return with RTL *)
      ORGFP.EmitSubroutines; ORGFP.FixupCalls;
      wInfo.key := key; wInfo.nofent := nofent; wInfo.version := version;
      wInfo.varsize := ORGI.varsize; wInfo.strx := ORGI.strx; wInfo.tdx := ORGE.tdx; wInfo.entry := ORGI.entry;
      wInfo.fixorgP := fixorgP; wInfo.fixorgD := fixorgD; wInfo.fixorgT := fixorgT;
      wInfo.tdListC := ORGE.tdListC; wInfo.tdFixupC := ORGE.tdFixupC; wInfo.vtFixC := ORGE.vtFixC;
      ORGW.WriteModule(modid, wInfo, ORGI.wa^, ORGE.tdList)
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
  PROCEDURE Discard*(VAR x: ORGI.Item);
  BEGIN  (* free the result register left by a function-call statement *)
    IF x.mode = ORGI.Reg THEN ORGI.RH := x.r END
  END Discard;

  PROCEDURE Snapshot*(VAR x: ORGI.Item);
  BEGIN
    (* The shared frontend evaluates the FOR limit once, before L0. On this
       register machine the limit would be clobbered by the loop body (and
       by any procedure it calls), so spill a non-const limit onto the
       hardware stack. frame += 2 shifts all stack-relative accesses to
       account for it; ForClose pops it at loop exit. Call-safe because the
       push lives on the invocation's own stack. *)
    IF forDepth < ORGI.maxForNest THEN
      IF x.mode # ORB.Const THEN
        ORGI.load(x);
        ORGI.Set16(TRUE, TRUE);
        IF ORGI.IsLong(x.type) THEN   (* the high word first: the low one at 1,S *)
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1)); OCG.Pha;
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r)); OCG.Pha;
          ORGI.RH := ORGI.RH - 2; ORGI.frame := ORGI.frame + 4; forPushed[forDepth] := 2
        ELSE
          OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
          OCG.Pha;
          ORGI.RH := ORGI.RH - 1; ORGI.frame := ORGI.frame + 2; forPushed[forDepth] := 1
        END;
        x.mode := ORB.Var; x.r := 1; x.a := 1 - ORGI.frame
      ELSE forPushed[forDepth] := 0
      END;
      forDepth := forDepth + 1
    ELSE ORS.Mark("FOR loops nested too deeply")
    END
  END Snapshot;

  PROCEDURE ForClose*;
  BEGIN
    IF forDepth > 0 THEN
      forDepth := forDepth - 1;
      IF forPushed[forDepth] > 0 THEN
        ORGI.Set16(TRUE, TRUE);
        OCG.Pla;   (* discard the spilled limit *)
        IF forPushed[forDepth] = 2 THEN OCG.Pla END;
        ORGI.frame := ORGI.frame - forPushed[forDepth] * 2
      END
    END
  END ForClose;

  (* --- OO / interface entry points: deferred to M4/M5 on this target --- *)
  PROCEDURE MethodItem*(VAR x: ORGI.Item; m: ORB.Object; direct: BOOLEAN);
    VAR t: ORB.Type; found: BOOLEAN; k: ORB.Object;
  BEGIN
    (* stash the receiver designator (current x) for PrepCall to pass as
       param 0; then turn x into the callable. *)
    x.rcvMode := x.mode; x.rcvA := x.a; x.rcvB := x.b; x.rcvR := x.r;
    x.rcvRdo := x.rdo; x.rcvType := x.type;
    x.isMeth := TRUE; x.type := m.type;
    IF direct THEN
      x.dynDisp := FALSE;
      (* the type that declares m, the receiver's or an ancestor: m is
         in its module, which may be another (a SUPER call to a method
         the base only inherits) *)
      t := x.rcvType; IF t.form = ORB.Pointer THEN t := t.base END;
      found := FALSE;
      WHILE (t # NIL) & ~found DO
        k := t.meth; WHILE (k # NIL) & (k # m) DO k := k.next END;
        IF k = m THEN found := TRUE ELSE t := t.base END
      END;
      IF found & (t.mno > 0) THEN   (* imported: JSL (mno, exno), the loader's *)
        x.mode := ORB.Const; x.a := m.exno; x.r := -t.mno
      ELSE
        x.mode := ORB.Const; x.a := m.backend; x.r := 0
      END;
      (* methods always return via RTL (far convention — see Enter), so a
         direct/SUPER call must reach them with JSL even within the module *)
      x.b := 1
    ELSE
      x.dynDisp := TRUE; x.methSlot := m.val; x.mode := ORB.Const
    END
  END MethodItem;

  (* T.Name(args) constructor: allocate a fresh instance of rec (HeapNew,
     as New), keep it in registers as the receiver, and set x
     to a direct call to the init body m. The init returns the receiver. *)
  PROCEDURE InitItem*(VAR x: ORGI.Item; m: ORB.Object; rec: ORB.Type);
    VAR rh0: LONGINT; obj: ORGI.Item;
  BEGIN
    rh0 := ORGI.RH;
    IF HeapNew(rec, obj) & (obj.r # rh0) THEN
      (* the object over the registers it started from, so PrepCall only
         saves the genuine outer context *)
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(obj.r));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(rh0));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(obj.r + 1));
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(rh0 + 1))
    END;
    ORGI.RH := rh0 + 2;
    x.rcvMode := ORGI.Reg; x.rcvR := rh0; x.rcvType := rec;
    x.isMeth := TRUE; x.dynDisp := FALSE; x.type := m.type;
    x.mode := ORB.Const; x.a := m.backend; x.r := 0;
    x.b := 1  (* init bodies are methods: far/RTL convention, reach via JSL *)
  END InitItem;

  (* Find or create the itable for (rec, ifc); returns its index. Deduped so
     repeated conversions of the same pair share one table. *)
  PROCEDURE RegisterItable(rec, ifc: ORB.Type): INTEGER;
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < ORGE.itabC) & ~((ORGE.itabRec[i] = rec) & (ORGE.itabIfc[i] = ifc)) DO i := i + 1 END;
    IF i = ORGE.itabC THEN
      IF ORGE.itabC < ORGI.maxItab THEN
        ORGE.itabRec[i] := rec; ORGE.itabIfc[i] := ifc; ORGE.itabC := ORGE.itabC + 1
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
    IF ORGE.itabRefC < ORGI.maxItabRef THEN
      ORGE.itabRefLoc[ORGE.itabRefC] := OCG.Here() - 2; ORGE.itabRefIdx[ORGE.itabRefC] := idx;
      ORGE.itabRefC := ORGE.itabRefC + 1
    ELSE ORS.Mark("too many itable refs")
    END
  END emitItabOffset;

  (* Designator `i.m` for an interface value i: stash i's designator so PrepCall
     can pass its data word as the receiver and Call can re-read the itable and
     the vtable slot itable[m.val]. The value stays in memory, so this nests. *)
  PROCEDURE IfaceMethodItem*(VAR x: ORGI.Item; m: ORB.Object);
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
  PROCEDURE PtrToIface*(VAR x: ORGI.Item; ift: ORB.Type);
    VAR idx, r0: INTEGER;
  BEGIN
    IF (x.type = NIL) OR (x.type.form # ORB.Pointer) THEN
      ORGI.Set16(TRUE, TRUE); r0 := ORGI.RH;
      OCG.gen1(OCG.STZ * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));
      OCG.gen1(OCG.STZ * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 1));
      OCG.gen1(OCG.STZ * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 2));
      OCG.gen1(OCG.STZ * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 3));
      ORGI.incR; ORGI.incR; ORGI.incR; ORGI.incR
    ELSE
      ORGI.load(x);                    (* pointer (data) now in R[x.r], R[x.r+1] *)
      idx := RegisterItable(x.type.base, ift);
      ORGI.Set16(TRUE, TRUE);
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.SB_DP);
      OCG.Clc;
      emitItabOffset(idx);        (* A := SB + itable_offset *)
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH));
      OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.BANK_DP);
      OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(ORGI.RH + 1));
      r0 := x.r; ORGI.incR; ORGI.incR
    END;
    x.mode := ORGI.Reg; x.r := r0; x.type := ift; x.b := 0; x.rdo := FALSE
  END PtrToIface;

  (* interface-var := interface-value: copy all four words. *)
  PROCEDURE StoreIface*(VAR x, y: ORGI.Item);
    VAR sb, k: LONGINT;
  BEGIN
    ORGI.load(y);   (* fat value in R[y.r .. y.r+3] *)
    ORGI.Set16(TRUE, TRUE);
    IF (x.mode = ORB.Var) & (x.r <= 0) THEN
      sb := ORGI.GetSB(x.r); k := 0;
      WHILE k < 4 DO
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r + k));
        OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a + k * 2);
        OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, sb);
        k := k + 1
      END;
      ORGI.RH := y.r
    ELSIF x.mode = ORGI.RegI THEN   (* through a pointer: a field of a heap object, an element *)
      k := 0;
      WHILE k < 4 DO
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r + k));
        OCG.gen1(OCG.LDY * 32 + OCG.mImm, x.a + k * 2);
        OCG.gen1(OCG.STA * 32 + OCG.mDPIndLY, ORGI.RegAddr(x.r));
        k := k + 1
      END;
      ORGI.RH := x.r
    ELSE   (* local Var or Par: stack-frame relative *)
      k := 0;
      WHILE k < 4 DO
        OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(y.r + k));
        OCG.gen1(OCG.STA * 32 + OCG.mSR, x.a + k * 2 + ORGI.frame);
        k := k + 1
      END;
      ORGI.RH := y.r
    END
  END StoreIface;

  (* = / # on interface values: compare the data words (word 0). One side may
     be NIL (a plain zero pointer/nil). Result is a Cond item. *)
  PROCEDURE IfaceRelation*(op: INTEGER; VAR x, y: ORGI.Item);
  BEGIN
    (* both sides materialize with their data word first (a 4-word fat value or
       a 2-word pointer/NIL), so comparing words 0..1 compares the references *)
    ORGI.load(x); ORGI.load(y);
    ORGI.Set16(TRUE, TRUE);
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
    OCG.gen1(OCG.EOR * 32 + OCG.mDP, ORGI.RegAddr(y.r));
    OCG.gen1(OCG.STA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
    OCG.gen1(OCG.LDA * 32 + OCG.mDP, ORGI.RegAddr(x.r + 1));
    OCG.gen1(OCG.EOR * 32 + OCG.mDP, ORGI.RegAddr(y.r + 1));
    OCG.gen1(OCG.ORA * 32 + OCG.mDP, ORGI.RegAddr(x.r));
    ORGI.RH := x.r; x.type := ORB.boolType;
    IF op = ORS.eql THEN ORGI.SetCC(x, ORGI.EQ) ELSE ORGI.SetCC(x, ORGI.NE) END
  END IfaceRelation;

  PROCEDURE Init*;
  BEGIN
    ORGE.relmap[0] := ORGI.EQ; ORGE.relmap[1] := ORGI.NE; ORGE.relmap[2] := ORGI.LT;
    ORGE.relmap[3] := ORGI.GE; ORGE.relmap[4] := ORGI.LE; ORGE.relmap[5] := ORGI.GT;
    OCG.Init
  END Init;

  (* --- the frontend's procedures in ORGI and ORGE --- *)

  PROCEDURE CheckRegs*;
  BEGIN ORGI.CheckRegs
  END CheckRegs;

  PROCEDURE FixOne*(at: LONGINT);
  BEGIN ORGI.FixOne(at)
  END FixOne;

  PROCEDURE FixLink*(L: LONGINT);
  BEGIN ORGI.FixLink(L)
  END FixLink;

  PROCEDURE MakeConstItem*(VAR x: Item; typ: ORB.Type; val: LONGINT);
  BEGIN ORGI.MakeConstItem(x, typ, val)
  END MakeConstItem;

  PROCEDURE MakeRealItem*(VAR x: Item; val: REAL);
  BEGIN ORGI.MakeRealItem(x, val)
  END MakeRealItem;

  PROCEDURE MakeStringItem*(VAR x: Item; len: LONGINT);
  BEGIN ORGI.MakeStringItem(x, len)
  END MakeStringItem;

  PROCEDURE MakeDataItem*(VAR x: Item; typ: ORB.Type; offset, size: LONGINT);
  BEGIN ORGI.MakeDataItem(x, typ, offset, size)
  END MakeDataItem;

  PROCEDURE StrOffset*(): LONGINT;
  BEGIN RETURN ORGI.StrOffset()
  END StrOffset;

  PROCEDURE PutByte*(b: INTEGER);
  BEGIN ORGI.PutByte(b)
  END PutByte;

  PROCEDURE PatchStr*(off, val, size: LONGINT);
  BEGIN ORGI.PatchStr(off, val, size)
  END PatchStr;

  PROCEDURE CopyStr*(dstOff, srcOff, size: LONGINT);
  BEGIN ORGI.CopyStr(dstOff, srcOff, size)
  END CopyStr;

  PROCEDURE MakeRecordConst*(VAR x: Item; typ: ORB.Type; start: LONGINT);
  BEGIN ORGI.MakeRecordConst(x, typ, start)
  END MakeRecordConst;

  PROCEDURE MakeItem*(VAR x: Item; y: ORB.Object; curlev: LONGINT);
  BEGIN ORGI.MakeItem(x, y, curlev)
  END MakeItem;

  PROCEDURE Field*(VAR x: Item; y: ORB.Object);
  BEGIN ORGI.Field(x, y)
  END Field;

  PROCEDURE Index*(VAR x, y: Item);
  BEGIN ORGI.Index(x, y)
  END Index;

  PROCEDURE DeRef*(VAR x: Item);
  BEGIN ORGI.DeRef(x)
  END DeRef;

  PROCEDURE Not*(VAR x: Item);
  BEGIN ORGI.Not(x)
  END Not;

  PROCEDURE And1*(VAR x: Item);
  BEGIN ORGI.And1(x)
  END And1;

  PROCEDURE And2*(VAR x, y: Item);
  BEGIN ORGI.And2(x, y)
  END And2;

  PROCEDURE Or1*(VAR x: Item);
  BEGIN ORGI.Or1(x)
  END Or1;

  PROCEDURE Or2*(VAR x, y: Item);
  BEGIN ORGI.Or2(x, y)
  END Or2;

  PROCEDURE StrToChar*(VAR x: Item);
  BEGIN ORGI.StrToChar(x)
  END StrToChar;

  PROCEDURE Store*(VAR x, y: Item);
  BEGIN ORGI.Store(x, y)
  END Store;

  PROCEDURE StoreStruct*(VAR x, y: Item);
  BEGIN ORGI.StoreStruct(x, y)
  END StoreStruct;

  PROCEDURE CopyString*(VAR x, y: Item);
  BEGIN ORGI.CopyString(x, y)
  END CopyString;

  PROCEDURE Here*(): LONGINT;
  BEGIN RETURN ORGI.Here()
  END Here;

  PROCEDURE FJump*(VAR L: LONGINT);
  BEGIN ORGI.FJump(L)
  END FJump;

  PROCEDURE CFJump*(VAR x: Item);
  BEGIN ORGI.CFJump(x)
  END CFJump;

  PROCEDURE BJump*(L: LONGINT);
  BEGIN ORGI.BJump(L)
  END BJump;

  PROCEDURE CBJump*(VAR x: Item; L: LONGINT);
  BEGIN ORGI.CBJump(x, L)
  END CBJump;

  PROCEDURE Fixup*(VAR x: Item);
  BEGIN ORGI.Fixup(x)
  END Fixup;

  PROCEDURE BuildTD*(T: ORB.Type; VAR dc: LONGINT);
  BEGIN ORGE.BuildTD(T, dc)
  END BuildTD;

  PROCEDURE FinalizeTDs*;
  BEGIN ORGE.FinalizeTDs
  END FinalizeTDs;

  PROCEDURE TypeTest*(VAR x: Item; T: ORB.Type; varpar, isguard: BOOLEAN);
  BEGIN ORGE.TypeTest(x, T, varpar, isguard)
  END TypeTest;

  PROCEDURE Neg*(VAR x: Item);
  BEGIN ORGE.Neg(x)
  END Neg;

  PROCEDURE AddOp*(op: LONGINT; VAR x, y: Item);
  BEGIN ORGE.AddOp(op, x, y)
  END AddOp;

  PROCEDURE MulOp*(VAR x, y: Item);
  BEGIN ORGE.MulOp(x, y)
  END MulOp;

  PROCEDURE DivOp*(op: LONGINT; VAR x, y: Item);
  BEGIN ORGE.DivOp(op, x, y)
  END DivOp;

  PROCEDURE RealOp*(op: INTEGER; VAR x, y: Item);
  BEGIN ORGE.RealOp(op, x, y)
  END RealOp;

  PROCEDURE Singleton*(VAR x: Item);
  BEGIN ORGE.Singleton(x)
  END Singleton;

  PROCEDURE Set*(VAR x, y: Item);
  BEGIN ORGE.Set(x, y)
  END Set;

  PROCEDURE In*(VAR x, y: Item);
  BEGIN ORGE.In(x, y)
  END In;

  PROCEDURE SetOp*(op: LONGINT; VAR x, y: Item);
  BEGIN ORGE.SetOp(op, x, y)
  END SetOp;

  PROCEDURE Rel1*(VAR x: Item);
  BEGIN ORGE.Rel1(x)
  END Rel1;

  PROCEDURE IntRelation*(op: INTEGER; VAR x, y: Item);
  BEGIN ORGE.IntRelation(op, x, y)
  END IntRelation;

  PROCEDURE RealRelation*(op: INTEGER; VAR x, y: Item);
  BEGIN ORGE.RealRelation(op, x, y)
  END RealRelation;

  PROCEDURE StringRelation*(op: INTEGER; VAR x, y: Item);
  BEGIN ORGE.StringRelation(op, x, y)
  END StringRelation;

  PROCEDURE OpenArrayParam*(VAR x: Item);
  BEGIN ORGE.OpenArrayParam(x)
  END OpenArrayParam;

  PROCEDURE VarParam*(VAR x: Item; ftype: ORB.Type);
  BEGIN ORGE.VarParam(x, ftype)
  END VarParam;

  PROCEDURE ValueParam*(VAR x: Item; ftype: ORB.Type);
  BEGIN ORGE.ValueParam(x, ftype)
  END ValueParam;

  PROCEDURE StringParam*(VAR x: Item);
  BEGIN ORGE.StringParam(x)
  END StringParam;

  PROCEDURE For0*(VAR x, y: Item);
  BEGIN ORGE.For0(x, y)
  END For0;

  PROCEDURE For1*(VAR x, z, w: Item; VAR L: LONGINT);
  BEGIN ORGE.For1(x, z, w, L)
  END For1;

  PROCEDURE For2*(VAR x, y, w: Item);
  BEGIN ORGE.For2(x, y, w)
  END For2;

  PROCEDURE CaseLabel*(VAR x: Item; val: LONGINT; VAR chain: LONGINT);
  BEGIN ORGE.CaseLabel(x, val, chain)
  END CaseLabel;

  PROCEDURE CaseRange*(VAR x: Item; lo, hi: LONGINT; VAR chain: LONGINT);
  BEGIN ORGE.CaseRange(x, lo, hi, chain)
  END CaseRange;

END ORG.
