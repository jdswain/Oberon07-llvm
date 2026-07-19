MODULE OCGTest;  (* dump OCG.Gen encodings for byte-exact cross-check vs C *)
  IMPORT OCG, Out;

  VAR names: ARRAY 92 OF ARRAY 4 OF CHAR;

  PROCEDURE Hex(n: LONGINT);   (* lowercase, no leading zeros (C %x) *)
    VAR d: LONGINT;
  BEGIN
    IF n >= 16 THEN Hex(n DIV 16) END;
    d := n MOD 16;
    IF d < 10 THEN Out.Write(CHR(d + ORD("0")))
    ELSE Out.Write(CHR(d - 10 + ORD("a")))
    END
  END Hex;

  PROCEDURE Byte(n: LONGINT);  (* 2-digit lowercase (C %02x) *)
    VAR d: LONGINT;
  BEGIN
    d := n DIV 16 MOD 16;
    IF d < 10 THEN Out.Write(CHR(d + ORD("0"))) ELSE Out.Write(CHR(d - 10 + ORD("a"))) END;
    d := n MOD 16;
    IF d < 10 THEN Out.Write(CHR(d + ORD("0"))) ELSE Out.Write(CHR(d - 10 + ORD("a"))) END
  END Byte;

  PROCEDURE Names;
  BEGIN
    names[0]:="ADC"; names[1]:="AND"; names[2]:="ASL"; names[3]:="BCC";
    names[4]:="BCS"; names[5]:="BEQ"; names[6]:="BIT"; names[7]:="BMI";
    names[8]:="BNE"; names[9]:="BPL"; names[10]:="BRA"; names[11]:="BRK";
    names[12]:="BRL"; names[13]:="BVC"; names[14]:="BVS"; names[15]:="CLC";
    names[16]:="CLD"; names[17]:="CLI"; names[18]:="CLV"; names[19]:="CMP";
    names[20]:="COP"; names[21]:="CPX"; names[22]:="CPY"; names[23]:="DEC";
    names[24]:="DEX"; names[25]:="DEY"; names[26]:="EOR"; names[27]:="INC";
    names[28]:="INX"; names[29]:="INY"; names[30]:="JMP"; names[31]:="JML";
    names[32]:="JSL"; names[33]:="JSR"; names[34]:="LDA"; names[35]:="LDX";
    names[36]:="LDY"; names[37]:="LSR"; names[38]:="MVN"; names[39]:="MVP";
    names[40]:="NOP"; names[41]:="ORA"; names[42]:="PEA"; names[43]:="PEI";
    names[44]:="PER"; names[45]:="PHA"; names[46]:="PHB"; names[47]:="PHD";
    names[48]:="PHK"; names[49]:="PHP"; names[50]:="PHX"; names[51]:="PHY";
    names[52]:="PLA"; names[53]:="PLB"; names[54]:="PLD"; names[55]:="PLP";
    names[56]:="PLX"; names[57]:="PLY"; names[58]:="REP"; names[59]:="ROL";
    names[60]:="ROR"; names[61]:="RTI"; names[62]:="RTL"; names[63]:="RTS";
    names[64]:="SBC"; names[65]:="SEC"; names[66]:="SED"; names[67]:="SEI";
    names[68]:="SEP"; names[69]:="STA"; names[70]:="STP"; names[71]:="STX";
    names[72]:="STY"; names[73]:="STZ"; names[74]:="TAX"; names[75]:="TAY";
    names[76]:="TCD"; names[77]:="TCS"; names[78]:="TDC"; names[79]:="TRB";
    names[80]:="TSB"; names[81]:="TSC"; names[82]:="TSX"; names[83]:="TXA";
    names[84]:="TXS"; names[85]:="TXY"; names[86]:="TYA"; names[87]:="TYX";
    names[88]:="WAI"; names[89]:="WDM"; names[90]:="XBA"; names[91]:="XCE"
  END Names;

  PROCEDURE Run;
    VAR i, mode, la, li, vi, b: INTEGER;
      vs: ARRAY 7 OF LONGINT;
  BEGIN
    vs[0]:=05H; vs[1]:=80H; vs[2]:=100H; vs[3]:=1234H;
    vs[4]:=123456H; vs[5]:=0FFFFH; vs[6]:=10000H;
    FOR i := 0 TO 91 DO
      FOR la := 0 TO 1 DO
        FOR li := 0 TO 1 DO
          FOR mode := 0 TO 25 DO
            FOR vi := 0 TO 6 DO
              OCG.Init;
              OCG.SetLongA(la = 1); OCG.SetLongI(li = 1);
              OCG.Gen(i, mode, vs[vi], 11H);
              Out.WriteString(names[i]); Out.Write(" ");
              Out.WriteInt(mode); Out.Write(" ");
              Out.WriteInt(la); Out.Write(" ");
              Out.WriteInt(li); Out.Write(" ");
              Hex(vs[vi]); Out.WriteString(" :");
              b := 0;
              WHILE b < OCG.Here() DO Out.Write(" "); Byte(OCG.Get(b)); b := b + 1 END;
              Out.Ln
            END
          END
        END
      END
    END
  END Run;

BEGIN
  Names; Run
END OCGTest.
