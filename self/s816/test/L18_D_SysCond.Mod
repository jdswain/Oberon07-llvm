MODULE L18_D_SysCond; (* SYSTEM.COND is refused *)
  IMPORT SYSTEM, Out;
  VAR b: BOOLEAN;
BEGIN b := SYSTEM.COND(1); Out.Bool(b)
END L18_D_SysCond.
