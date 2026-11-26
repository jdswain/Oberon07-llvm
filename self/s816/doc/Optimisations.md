# Oberon 65C816 Compiler - Optimisations

## Current Optimisations

### OPT-1: Hardcoded Module Table Address
The module table is at a fixed memory address (e.g. $0E00) rather than
accessed via an indirect register. This saves one level of indirection
compared to the original Oberon RISC which uses the MT register to point
to the module table.

On RISC: `LDR RH, MT, mno*4` (register-indirect)
On 65C816: `LDA $0E00 + mno*2` (absolute addressing, address known at
compile/link time)

### OPT-2: Data in Bank 0 (Direct Page Accessible)
All module variable data is currently restricted to bank 0 addresses,
making it accessible via direct page indirect addressing modes like
`LDA (SB),Y`. This is fast (fewer cycles, shorter instructions) but
limits total data to 64K across all modules.

May need to relax this later if programs need more data space. Moving
data to bank 1+ would require long indirect addressing (`LDA [dp],Y`)
which adds a cycle and requires 3-byte pointers in the direct page.

### OPT-3: Exported Procedures Use JSL/RTL
Exported procedures are called with JSL and return with RTL, allowing
cross-bank calls. Non-exported local procedures use the cheaper JSR/RTS.


## Future Optimisations

### OPT-4: Own-Module SB Caching
When accessing own-module globals, we could skip reloading SB from the
module table if we know it hasn't changed since the last load. The
compiler could track whether SB is "dirty" (changed by a cross-module
data access or call) and only reload when necessary.

For single-module programs or code that only accesses its own globals,
this would eliminate the module table lookup entirely -- SB would be
loaded once at module entry and reused for all accesses.

Get correctness first, then optimise.

### OPT-5: Direct Global Access Without Indirection
For own-module globals with known small offsets, could use absolute
addressing directly (`LDA $1000 + offset`) instead of going through
SB. The loader would need to patch these addresses (data relocations).

### OPT-6: Register Read Elimination
Currently every global/local load goes through a virtual register
(direct page location). In many cases the value could be used directly
from the load without the intermediate STA/LDA through the register.

### OPT-7: Peephole Optimisation on Code Buffer
Look back at recently generated code to eliminate redundant loads,
stores, and mode switches (REP/SEP pairs).

### OPT-8: Register File Sizing
Recode the register file to size based on the type being stored.
Since this is a stack this should be possible. Possibly pack
registers so BYTE can be stored more.

### OPT-9: Numeric Case
If sufficient range to merrit, generate a jump table for the case rather
than the current structure.

### OPT-10: String Case
Implement String case, it shouldn't be hard with the current case
implementation.