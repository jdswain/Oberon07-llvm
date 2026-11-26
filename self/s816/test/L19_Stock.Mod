MODULE L19_Stock; (* code for a stock 65C816 (oc816 -816) run as on one:
   L19_StockRun calls L19_Stock816.Run with the core's banked direct page
   and stack off, D and S in a block of bank 0, D off a page. Its sum,
   61034 as an INTEGER, is right only if L19_Stock816 was compiled with
   -816: code for the banked core gets it wrong *)
  IMPORT SYSTEM, Out, MemoryManager, L19_StockRun, L19_Stock816;
  VAR p: PROCEDURE; blk: LONGINT;
BEGIN
  blk := MemoryManager.AllocIn(MemoryManager.Data, 2048, 1000H, 0E000H, MemoryManager.Sys);
  IF blk = 0 THEN Out.String("no block in bank 0"); Out.Ln
  ELSE p := L19_Stock816.Run; L19_StockRun.Call(SYSTEM.VAL(LONGINT, p), blk);
    Out.String("sum "); Out.Int(L19_Stock816.sum, 0); Out.Ln
  END
END L19_Stock.
