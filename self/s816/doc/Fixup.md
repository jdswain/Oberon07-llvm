# Fixup Chain System

This document explains how the fixup chain system works in the Oberon compiler for 65C816.

## Purpose

When the compiler encounters a forward branch (like in an IF statement), it doesn't know the target address yet because the code for the THEN/ELSE blocks hasn't been generated. So it generates a branch instruction with a placeholder offset and remembers where to fix it later.

## The Fixup Chain

The "chain" refers to a **linked list of branch instructions** that all need to jump to the same target address.

### 1. First Forward Branch

```c
// Generate first branch that needs fixing
codegen_gen(sBRA, Fixup, 0, 0);  // target = 0 (no previous branches)
```

- Generates: `80 00` (BRA with offset 0)
- The offset byte (at address N+1) gets value `00`
- Returns address N+1 to be stored in fixup chain

### 2. Second Forward Branch to Same Target

```c
// Generate second branch to same target  
codegen_gen(sBRA, Fixup, previous_chain_addr, 0);  // target = address of first branch's offset
```

- Generates: `80 XX` where XX is relative offset pointing back to first branch
- Creates a **backward-pointing chain link**

### 3. Chain Structure Example

```
Address | Instruction | Offset | Meaning
--------|-------------|--------|------------------
1000    | 80 00      | 00     | BRA +0 (first branch, end of chain)
...     |            |        |
2000    | 80 E2      | E2     | BRA -30 (points back to offset at 1001)
...     |            |        |
3000    | 80 C2      | C2     | BRA -62 (points back to offset at 2001)
```

The chain links **backward** through the offset bytes: 3001 → 2001 → 1001 → 0 (end)

### 4. Chain Generation in Code

In `codegen.c`, the `of()` function handles fixup chain generation:

```c
void of(uint8_t op, int v) {
  // Fixup branch: store opcode and fixup chain link
  o(op);
  if (v == 0) {
    // First forward branch in chain
    o(0);
  } else {
    // Forward branch - store relative offset to previous branch in chain
    // v is the address of the previous offset byte
    int chain_offset = v - (ORG_pc + 1);
    o(chain_offset & 0xff);
  }
}
```

### 5. Fixing the Chain

When the target address is known, `ORG_FixLink()` traverses and fixes all branches:

```c
void ORG_FixLink(LONGINT L) {
    // L = address of most recent offset byte (3001 in example)
    while (L != 0) {
        LONGINT chain_offset = (signed char)code[L];  // Read chain link
        if (chain_offset == 0) {
            L1 = 0;  // End of chain
        } else {
            L1 = L + chain_offset;  // Calculate previous offset byte address
        }
        
        fix(L, target);  // Fix this branch to point to target
        L = L1;          // Move to previous branch in chain
    }
}
```

This traverses: 3001 → 2001 → 1001, fixing each branch to point to the actual target.

### 6. Branch Offset Calculation

The `fix()` function calculates the actual branch offset:

```c
static void fix(LONGINT at, LONGINT with) {
    // For 65C816, patch the offset byte of branch instructions
    // 'at' is the address of the offset byte (branch_addr + 1)
    // 'with' is the target address
    // Offset = target - (branch_addr + 2) = target - (at + 1)
    LONGINT offset = with - (at + 1);
    LONGINT code_index = at - CODE_ORG;
    
    code[code_index] = offset & 0xFF;  // Store only the low byte
}
```

For 65C816 relative branches, the offset is calculated from the instruction **after** the branch instruction.

## Why Use a Chain?

Consider this Oberon code:

```oberon
IF (x > 5) & (y < 10) THEN
    (* THEN block *)
ELSE  
    (* ELSE block *)
END
```

This generates **multiple branches** that all need to jump to the same ELSE block:
1. Branch if `x <= 5` → ELSE
2. Branch if `y >= 10` → ELSE

Both branches need the same target address, but it's unknown until the THEN block is generated. The chain links them together so one `ORG_FixLink()` call fixes all branches to that target.

## Usage Pattern

1. **Generate forward branches**: Use `codegen_gen(sBRA, Fixup, chain_link, 0)`
2. **Store chain head**: Keep track of the most recent offset byte address
3. **Generate target code**: Emit the code that should be jumped to
4. **Fix the chain**: Call `ORG_FixLink(chain_head)` to patch all branches

## Key Data Structures

- **ORG_Item**: Contains fixup chain links in fields `a` and `b`
- **chain_link**: Address of the offset byte of the previous branch in chain
- **target**: Final address where all branches should jump

## Common Issues

1. **Wrong target address**: The most common bug is passing the wrong target to `fix()`
2. **Chain corruption**: Incorrectly linking branches can break traversal
3. **PC tracking errors**: If `ORG_pc` is wrong, both chain links and targets will be incorrect

## Debugging

Use the disassembler with branch annotations to verify:
- Branch instructions point to the correct targets
- Chain links form valid backward references
- All branches in a chain reach the same destination

Example annotated output:
```
221C: 80 31       bra  $31  ; -> $224F
```

If the target is wrong, the issue is likely in the target address calculation, not the fixup mechanism itself.