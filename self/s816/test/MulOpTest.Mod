MODULE MulOpTest;
   IMPORT SYSTEM;
	  
   CONST
      ACIA_DATA = 0C000H;
    
   VAR
      a, b, result: INTEGER;
    
   PROCEDURE PutChar(value: CHAR);
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, value);
   END PutChar;
   
   PROCEDURE WriteString(s: ARRAY OF CHAR);
      VAR i: INTEGER;
   BEGIN 
      i := 0;
      WHILE s[i] >= " " DO 
		 PutChar(s[i]); 
		 INC(i) 
      END
   END WriteString;
  
   PROCEDURE WriteInt(value: INTEGER);
      VAR 
		 negative: BOOLEAN;
		 digits: ARRAY 10 OF INTEGER;
		 count, i: INTEGER;
   BEGIN
      IF value = 0 THEN
		 PutChar('0');
      END;
    
      negative := value < 0;
      IF negative THEN
		 value := -value;
		 PutChar('-')
      END;
    
      count := 0;
      WHILE value > 0 DO
		 digits[count] := value MOD 10;
		 value := value DIV 10;
		 INC(count)
      END;
      
      i := count - 1;
      WHILE i >= 0 DO
		 PutChar(CHR(digits[i] + ORD('0')));
		 DEC(i)
      END
   END WriteInt;
   
   PROCEDURE NewLine();
   BEGIN
      SYSTEM.PUT(0, ACIA_DATA, 0AX);
   END NewLine;
   
   PROCEDURE TestConstMul();
   BEGIN
      WriteString("=== Constant Multiplication Tests ==="); NewLine();
      
      (* Test 1: Constant * Constant *)
      result := 5 * 7;
      WriteString("5 * 7 = ");
      WriteInt(result);
      WriteString(" (expected: 35)"); NewLine();
      
      result := 12 * 3;
      WriteString("12 * 3 = ");
      WriteInt(result);
      WriteString(" (expected: 36)"); NewLine();
      
      result := 0 * 25;
      WriteString("0 * 25 = ");
      WriteInt(result);
      WriteString(" (expected: 0)"); NewLine();
      
      result := 1 * 42;
      WriteString("1 * 42 = ");
      WriteInt(result);
      WriteString(" (expected: 42)"); NewLine();
      
      (* Test negative constants *)
      result := -3 * 4;
      WriteString("-3 * 4 = ");
      WriteInt(result);
      WriteString(" (expected: -12)"); NewLine();
      
      result := 6 * (-2);
      WriteString("6 * -2 = ");
      WriteInt(result);
      WriteString(" (expected: -12)"); NewLine();
      
      result := (-5) * (-8);
      WriteString("-5 * -8 = ");
      WriteInt(result);
      WriteString(" (expected: 40)"); NewLine();
      
      NewLine()
   END TestConstMul;
   
   PROCEDURE TestPowerOfTwo();
   BEGIN
      WriteString("=== Power of Two Tests ==="); NewLine();
      
      (* Test Variable * Power of Two Constants *)
      a := 10;
      
      result := a * 1;
      WriteString("10 * 1 = ");
      WriteInt(result);
      WriteString(" (expected: 10, shift: 0)"); NewLine();
      
      result := a * 2;
      WriteString("10 * 2 = ");
      WriteInt(result);
      WriteString(" (expected: 20, shift: 1)"); NewLine();
      
      result := a * 4;
      WriteString("10 * 4 = ");
      WriteInt(result);
      WriteString(" (expected: 40, shift: 2)"); NewLine();
      
      result := a * 8;
      WriteString("10 * 8 = ");
      WriteInt(result);
      WriteString(" (expected: 80, shift: 3)"); NewLine();
      
      result := a * 16;
      WriteString("10 * 16 = ");
      WriteInt(result);
      WriteString(" (expected: 160, shift: 4)"); NewLine();
      
      result := a * 32;
      WriteString("10 * 32 = ");
      WriteInt(result);
      WriteString(" (expected: 320, shift: 5)"); NewLine();
      
      result := a * 64;
      WriteString("10 * 64 = ");
      WriteInt(result);
      WriteString(" (expected: 640, shift: 6)"); NewLine();
      
      result := a * 128;
      WriteString("10 * 128 = ");
      WriteInt(result);
      WriteString(" (expected: 1280, shift: 7)"); NewLine();
      
      result := a * 256;
      WriteString("10 * 256 = ");
      WriteInt(result);
      WriteString(" (expected: 2560, shift: 8)"); NewLine();
      
      (* Test with different variable value *)
      a := 7;
      result := a * 16;
      WriteString("7 * 16 = ");
      WriteInt(result);
      WriteString(" (expected: 112, shift: 4)"); NewLine();
      
      (* Test non-power-of-two (should use general multiplication) *)
      result := a * 3;
      WriteString("7 * 3 = ");
      WriteInt(result);
      WriteString(" (expected: 21, general mul)"); NewLine();
      
      result := a * 5;
      WriteString("7 * 5 = ");
      WriteInt(result);
      WriteString(" (expected: 35, general mul)"); NewLine();
      
      result := a * 6;
      WriteString("7 * 6 = ");
      WriteInt(result);
      WriteString(" (expected: 42, general mul)"); NewLine();
      
      NewLine()
   END TestPowerOfTwo;
   
   PROCEDURE TestVarMul();
   BEGIN
      WriteString("=== Variable * Variable Tests ==="); NewLine();
      
      a := 6;
      b := 9;
      result := a * b;
      WriteString("6 * 9 = ");
      WriteInt(result);
      WriteString(" (expected: 54)"); NewLine();
      
      a := 12;
      b := 5;
      result := a * b;
      WriteString("12 * 5 = ");
      WriteInt(result);
      WriteString(" (expected: 60)"); NewLine();
      
      a := -4;
      b := 7;
      result := a * b;
      WriteString("-4 * 7 = ");
      WriteInt(result);
      WriteString(" (expected: -28)"); NewLine();
      
      a := 8;
      b := -3;
      result := a * b;
      WriteString("8 * -3 = ");
      WriteInt(result);
      WriteString(" (expected: -24)"); NewLine();
      
      a := -6;
      b := -4;
      result := a * b;
      WriteString("-6 * -4 = ");
      WriteInt(result);
      WriteString(" (expected: 24)"); NewLine();
      
      (* Edge cases *)
      a := 0;
      b := 15;
      result := a * b;
      WriteString("0 * 15 = ");
      WriteInt(result);
      WriteString(" (expected: 0)"); NewLine();
      
      a := 1;
      b := 25;
      result := a * b;
      WriteString("1 * 25 = ");
      WriteInt(result);
      WriteString(" (expected: 25)"); NewLine();
      
      NewLine()
   END TestVarMul;
   
   PROCEDURE TestMixedCases();
   BEGIN
      WriteString("=== Mixed Cases ==="); NewLine();
      
      (* Constant * Variable (commutative) *)
      a := 9;
      result := 4 * a;
      WriteString("4 * 9 = ");
      WriteInt(result);
      WriteString(" (expected: 36, const*var)"); NewLine();
      
      result := a * 4;
      WriteString("9 * 4 = ");
      WriteInt(result);
      WriteString(" (expected: 36, var*const)"); NewLine();
      
      (* Test with larger numbers *)
      a := 123;
      result := a * 8;
      WriteString("123 * 8 = ");
      WriteInt(result);
      WriteString(" (expected: 984, power of 2)"); NewLine();
      
      result := a * 7;
      WriteString("123 * 7 = ");
      WriteInt(result);
      WriteString(" (expected: 861, general)"); NewLine();
      
      NewLine()
   END TestMixedCases;
   
BEGIN
   WriteString("Multiplication Operations Test"); NewLine();
   WriteString("============================="); NewLine();
   NewLine();
   
   TestConstMul();
   TestPowerOfTwo();
   TestVarMul();
   TestMixedCases();
   
   WriteString("Test completed."); NewLine();
END MulOpTest.