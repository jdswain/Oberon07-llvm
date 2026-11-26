MODULE IncrementTest;

VAR
  i: INTEGER;

BEGIN
  (* Test 1: Basic INC with global variable *)
  i := 10;
  INC(i);      (* Should use INC instruction *)
  
  (* Test 2: INC with constant increment *)
  INC(i, 5);   (* Should use ADC instruction *)
  
  (* Test 3: Basic DEC with global variable *)
  DEC(i);      (* Should use DEC instruction *)
  
  (* Test 4: DEC with constant decrement *)
  DEC(i, 3);   (* Should use SBC instruction *)
  
END IncrementTest.