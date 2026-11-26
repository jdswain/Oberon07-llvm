MODULE TypeConversionTest;

VAR 
    byteVar: BYTE;
    intVar: INTEGER;
    byteValue: BYTE;
    intValue: INTEGER;

BEGIN
    (* Test BYTE to BYTE assignment - no conversion *)
    byteValue := 0ABH;
    byteVar := byteValue;
    
    (* Test INTEGER to BYTE assignment - truncation *)
    intValue := 01234H;  (* Should truncate to 34H *)
    byteVar := intValue;
    
    (* Test BYTE to INTEGER assignment - zero extension *)
    byteValue := 0FFH;
    intValue := byteValue;  (* Should be 00FFH *)
    
    (* Test INTEGER to INTEGER assignment - no conversion *)
    intValue := 05678H;
    intVar := intValue
END TypeConversionTest.