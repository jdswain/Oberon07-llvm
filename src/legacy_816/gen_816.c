/*
 * OC - Oberon Compiler for 65C816
 * Copyright (C) 2024-2026 Jason Swain
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

/*

WDC 65C816 code generation

*/

void gen_816(OpCode opcode, AddrMode mode, int value1, int value2)
{
  switch( opcode ) {
  case sADC:
    switch( mode ) {
    case Immediate:                      om(0x69, value1, longa); return;
    case Absolute:                       oabs(0x6d, value1); return;
    case AbsoluteLong:                   olong(0x6f, value1); return;
    case DirectPage:                     odp(0x65, value1); return;
    case DirectPageIndirect:             odp(0x72, value1); return;
    case DirectPageIndirectLong:         odp(0x67, value1); return;
    case AbsoluteIndexedX:               oabs(0x7d, value1); return;
    case AbsoluteLongIndexedX:           olong(0x7f, value1); return;
    case AbsoluteIndexedY:               oabs(0x79, value1); return;
    case DirectPageIndexedX:             odp(0x75, value1); return;
    case DirectPageIndexedIndirectX:     odp(0x61, value1); return;
    case DirectPageIndirectIndexedY:     odp(0x71, value1); return;
    case DirectPageIndirectLongIndexedY: odp(0x77, value1); return;
    case StackRelative:                  ob(0x63, value1); return;
    case StackRelativeIndirectIndexedY:  ob(0x73, value1); return;
    default:                             break;
    }
    break;
  case sAND:
    switch( mode ) {
    case Immediate:                      om(0x29, value1, longa); return;
    case Absolute:                       ow(0x2d, value1); return;
    case AbsoluteLong:                   ol(0x2f, value1); return;
    case DirectPage:                     ob(0x25, value1); return;
    case DirectPageIndirect:             ob(0x32, value1); return;
    case DirectPageIndirectLong:         ob(0x27, value1); return;
    case AbsoluteIndexedX:               ow(0x3d, value1); return;
    case AbsoluteLongIndexedX:           ol(0x3f, value1); return;
    case AbsoluteIndexedY:               ow(0x39, value1); return;
    case DirectPageIndexedX:             ob(0x35, value1); return;
    case DirectPageIndexedIndirectX:     ob(0x21, value1); return;
    case DirectPageIndirectIndexedY:     ob(0x31, value1); return;
    case DirectPageIndirectLongIndexedY: ob(0x37, value1); return;
    case StackRelative:                  ob(0x23, value1); return;
    case StackRelativeIndirectIndexedY:  ob(0x33, value1); return;
    default:                             break;
    }
    break;
  case sASL:
    switch( mode ) {
    case Implied:
    case Accumulator:                    o(0x0a); return;
    case Absolute:                       ow(0x0e, value1); return;
    case DirectPage:                     ob(0x06, value1); return;
    case AbsoluteIndexedX:               ow(0x1e, value1); return;
    case DirectPageIndexedX:             ob(0x16, value1); return;
    default:                             break;
    }
    break;
  case sBCC:
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:         or(0x90, value1); return;
    case Fixup:                          of(0x90, value1); return;
    default:                             break;
    }
    break;
  case sBCS:
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:         or(0xb0, value1); return;
    case Fixup:                          of(0xb0, value1); return;
    default:                             break;
    }
    break;
  case sBEQ:
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:         or(0xf0, value1); return;
    case Fixup:                          of(0xf0, value1); return;
    default:                             break;
    }
    break;
  case sBIT:
    switch( mode ) {
    case Immediate:                      om(0x89, value1, longa); return;
    case Absolute:                       ow(0x2c, value1); return;
    case DirectPage:                     ob(0x24, value1); return;
    case AbsoluteIndexedX:               ow(0x3c, value1); return;
    case DirectPageIndexedX:             ob(0x34, value1); return;
    default:                             break;
    }
    break;
  case sBMI:
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:         or(0x30, value1); return;
    case Fixup:                          of(0x30, value1); return;
    default:                             break;
    }
    break;
  case sBNE:
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:         or(0xd0, value1); return;
    case Fixup:                          of(0xd0, value1); return;
    default:                             break;
    }
    break;
  case sBPL:
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:         or(0x10, value1); return;
    case Fixup:                          of(0x10, value1); return;
    default:                             break;
    }
    break;
  case sBRA:
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:
      {
		int r = value1 - (ORG_pc + 1);
		// Check if we need BRL instead of BRA
		if ((r > 127) || (r < -128)) {
		  // Use correct BRL offset calculation: target - (pc + 3)
		  int brl_offset = value1 - (ORG_pc + 3);
		  ow(0x82, brl_offset);
		} else {
		  or(0x80, value1);
		}
      }
      return;
    case Fixup:                          of(0x80, value1); return;
    default:                             break;
    }
    break;
  case sBRK:
    switch( mode ) {
    case Implied:                        ob(0x00, 0x00); return;
    case Immediate:                      ob(0x00, value1); return;
    default:                             break;
    }
    break;
  case sBRL:
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:
      {
		int r = value1 - (ORG_pc + 3);  // BRL is 3 bytes, not 1
		ow(0x82, r);  // Use ow instead of orl to directly emit the calculated offset
      }
      return;
    case Fixup:                          
        ofl(0x82, value1); 
        return;
    default:                             break;
    }
    break;
  case sBVC:
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:         or(0x50, value1); return;
    default:                             break;
    }
    break;
  case sBVS:
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case ProgramCounterRelative:         or(0x70, value1); return;
    default:                             break;
    }
    break;
  case sCLC:
    switch( mode ) {
    case Implied:                        o(0x18); return;
    default:                             break;
    }
    break;
  case sCLD:
    switch( mode ) {
    case Implied:                        o(0xd8); return;
    default:                             break;
    }
    break;
  case sCLI:
    switch( mode ) {
    case Implied:                        o(0x58); return;
    default:                             break;
    }
    break;
  case sCLV:
    switch( mode ) {
    case Implied:                        o(0xb8); return;
    default:                             break;
    }
    break;
  case sCMP:
    switch( mode ) {
    case Immediate:                      om(0xc9, value1, longa); return;
    case Absolute:                       ow(0xcd, value1); return;
    case AbsoluteLong:                   ol(0xcf, value1); return;
    case DirectPage:                     ob(0xc5, value1); return;
    case DirectPageIndirect:             ob(0xd2, value1); return;
    case DirectPageIndirectLong:         ob(0xc7, value1); return;
    case AbsoluteIndexedX:               ow(0xdd, value1); return;
    case AbsoluteLongIndexedX:           ol(0xdf, value1); return;
    case AbsoluteIndexedY:               ow(0xd9, value1); return;
    case DirectPageIndexedX:             ob(0xd5, value1); return;
    case DirectPageIndexedIndirectX:     ob(0xc1, value1); return;
    case DirectPageIndirectIndexedY:     ob(0xd1, value1); return;
    case DirectPageIndirectLongIndexedY: ob(0xd7, value1); return;
    case StackRelative:
      if (value1 > 255) {
        // Large stack-relative offset: save both values to DP temps, compare via DP
        ob(0x85, 0x22);                                    // STA $22 (save compare value)
        bool cmp_save = longa;
        if (!longa) { o(0xC2); o(0x20); longa = 1; }      // REP #$20
        o(0xDA);                                            // PHX
        o(0x3B);                                            // TSC
        o(0x18);                                            // CLC
        o(0x69); o((value1+2)&0xff); o((value1+2)>>8);    // ADC #(offset+2)
        o(0xAA);                                            // TAX
        o(0xBF); o(0x00); o(0x00); o(0x00);               // LDA $000000,X
        ob(0x85, 0x24);                                     // STA $24 (save stack value)
        o(0xFA);                                            // PLX
        if (!cmp_save) { o(0xE2); o(0x20); longa = 0; }   // SEP #$20
        ob(0xA5, 0x22);                                     // LDA $22 (restore compare value)
        ob(0xC5, 0x24);                                     // CMP $24
      } else {
        ob(0xc3, value1);
      }
      return;
    case StackRelativeIndirectIndexedY:  ob(0xd3, value1); return;
    default:                             break;
    }
    break;
  case sCOP:
    switch( mode ) {
      // Note implied is not available, signature byte is required
    case Immediate:                      ob(0x02, value1); return;
    default:                             break;
    }
    break;
  case sCPX:
    switch( mode ) {
    case Immediate:                      om(0xe0, value1, longi); return;
    case Absolute:                       ow(0xec, value1); return;
    case DirectPage:                     ob(0xe4, value1); return;
    default:                             break;
    }
    break;
  case sCPY:
    switch( mode ) {
    case Immediate:                      om(0xc0, value1, longi); return;
    case Absolute:                       ow(0xcc, value1); return;
    case DirectPage:                     ob(0xc4, value1); return;
    default:                             break;
    }
    break;
  case sDEC:
    switch( mode ) {
    case Accumulator:
    case Implied:                        o(0x3a); return;
    case Absolute:                       ow(0xce, value1); return;
    case DirectPage:                     ob(0xc6, value1); return;
    case AbsoluteIndexedX:               ow(0xde, value1); return;
    case DirectPageIndexedX:             ob(0xd6, value1); return;
    default:                             break;
    }
    break;
  case sDEX:
    switch( mode ) {
    case Implied:                        o(0xca); return;
    default:                             break;
    }
    break;
  case sDEY:
    switch( mode ) {
    case Implied:                        o(0x88); return;
    default:                             break;
    }
    break;
  case sEOR:
    switch( mode ) {
    case Immediate:                      om(0x49, value1, longa); return;
    case Absolute:                       ow(0x4d, value1); return;
    case AbsoluteLong:                   ol(0x4f, value1); return;
    case DirectPage:                     ob(0x45, value1); return;
    case DirectPageIndirect:             ob(0x52, value1); return;
    case DirectPageIndirectLong:         ob(0x47, value1); return;
    case AbsoluteIndexedX:               ow(0x5d, value1); return;
    case AbsoluteLongIndexedX:           ol(0x5f, value1); return;
    case AbsoluteIndexedY:               ow(0x59, value1); return;
    case DirectPageIndexedX:             ob(0x55, value1); return;
    case DirectPageIndexedIndirectX:     ob(0x41, value1); return;
    case DirectPageIndirectIndexedY:     ob(0x51, value1); return;
    case DirectPageIndirectLongIndexedY: ob(0x57, value1); return;
    case StackRelative:                  ob(0x43, value1); return;
    case StackRelativeIndirectIndexedY:  ob(0x53, value1); return;
    default:                             break;
    }
    break;
  case sINC:
    switch( mode ) {
    case Accumulator:
    case Implied:                        o(0x1a); return;
    case Absolute:                       ow(0xee, value1); return;
    case DirectPage:                     ob(0xe6, value1); return;
    case AbsoluteIndexedX:               ow(0xfe, value1); return;
    case DirectPageIndexedX:             ob(0xf6, value1); return;
    default:                             break;
    }
    break;
  case sINX:
    switch( mode ) {
    case Implied:                        o(0xe8); return; 
    default:                             break;
    }
    break;
  case sINY:
    switch( mode ) {
    case Implied:                        o(0xc8); return;
    default:                             break;
    }
    break;
  case sJMP:
    switch( mode ) {
    case DirectPage: /* Less than $100, treat as absolute */
    case Absolute:                       ow(0x4c, value1); return;
    case AbsoluteIndirect:               ow(0x6c, value1); return;
    case AbsoluteIndexedIndirect:        ow(0x7c, value1); return;
    case AbsoluteLong:                   ol(0x5c, value1); return;
    case AbsoluteIndirectLong:           ow(0xdc, value1); return; 
    default:                             break;
    }
    break;
  case sJML:
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case AbsoluteLong:                   ol(0x5c, value1); return;
    case AbsoluteIndirect:
    case AbsoluteIndirectLong:           ow(0xdc, value1); return; 
    default:                             break;
    }
    break;
  case sJSL:
    switch( mode ) {
    case DirectPage:
    case Absolute:
    case AbsoluteLong:                   reloc[relocC++] = ORG_pc; ol(0x22, value1); return;
    default:                             break;
    }
    break;
  case sJSR:
    switch( mode ) {
    case DirectPage:
    case Absolute:                       reloc[relocC++] = ORG_pc; ow(0x20, value1); return;
    case AbsoluteIndexedIndirect:        ow(0xfc, value1); return;
    case AbsoluteLong:                   reloc[relocC++] = ORG_pc; ol(0x22, value1); return;
    default:                             break;
    }
    break;
  case sLDA:
    switch( mode ) {
    case Immediate:                      om(0xa9, value1, longa); return;
    case Absolute:                       ow(0xad, value1); return;
    case AbsoluteLong:                   ol(0xaf, value1); return;
    case DirectPage:                     ob(0xa5, value1); return;
      /* This is DirectPageIndirect, but the parser is not 
	 smart enough to figure that out */
    case AbsoluteIndirect:
    case DirectPageIndirect:             ob(0xb2, value1); return;
    case DirectPageIndirectLong:         ob(0xa7, value1); return;
    case AbsoluteIndexedX:               ow(0xbd, value1); return;
    case AbsoluteLongIndexedX:           ol(0xbf, value1); return;
    case AbsoluteIndexedY:               ow(0xb9, value1); return;
    case DirectPageIndexedX:             ob(0xb5, value1); return;
    case DirectPageIndexedIndirectX:     ob(0xa1, value1); return;
    case DirectPageIndirectIndexedY:     ob(0xb1, value1); return;
    case DirectPageIndirectLongIndexedY: ob(0xb7, value1); return;
    case StackRelative:
      if (value1 > 255) {
        // Large stack-relative offset: PHX; TSC; CLC; ADC #(off+2); TAX; LDA $000000,X; PLX
        bool lda_save = longa;
        if (!longa) { o(0xC2); o(0x20); longa = 1; }  // REP #$20
        o(0xDA);                                         // PHX (SP -= 2)
        o(0x3B);                                         // TSC
        o(0x18);                                         // CLC
        o(0x69); o((value1+2)&0xff); o((value1+2)>>8);  // ADC #(offset+2)
        o(0xAA);                                         // TAX
        if (!lda_save) { o(0xE2); o(0x20); longa = 0; } // SEP #$20
        o(0xBF); o(0x00); o(0x00); o(0x00);             // LDA $000000,X
        o(0xFA);                                         // PLX
      } else {
        ob(0xa3, value1);
      }
      return;
    case StackRelativeIndirectIndexedY:  ob(0xb3, value1); return;
    default:                             return;
    }
    break;
  case sLDX:
    switch( mode ) {
    case Immediate:                      om(0xa2, value1, longi); return;
    case Absolute:                       ow(0xae, value1); return;
    case DirectPage:                     ob(0xa6, value1); return;
    case AbsoluteIndexedY:               ow(0xbe, value1); return;
    case DirectPageIndexedY:             ob(0xb6, value1); return;
    default:                             break;
    }
    break;
  case sLDY:
    switch( mode ) {
    case Immediate:                      om(0xa0, value1, longi); return;
    case Absolute:                       ow(0xac, value1); return;
    case DirectPage:                     ob(0xa4, value1); return;
    case AbsoluteIndexedX:               ow(0xbc, value1); return;
    case DirectPageIndexedX:             ob(0xb4, value1); return;
    default:                             break;
    }
    break;
  case sLSR:
    switch( mode ) {
    case Accumulator:
    case Implied:                        o(0x4a); return;
    case Absolute:                       ow(0x4e, value1); return;
    case DirectPage:                     ob(0x46, value1); return;
    case AbsoluteIndexedX:               ow(0x5e, value1); return;
    case DirectPageIndexedX:             ob(0x56, value1); return;
    default:                             break;
    }
    break;
  case sMVN:
    switch( mode ) {
    case BlockMove:                      omove(0x54, value2, value1); return;
    default:                             break;
    }
    break;
  case sMVP:
    switch( mode ) {
    case BlockMove:                      omove(0x44, value2, value1); return;
    default:                             break;
    }
    break;
  case sNOP:
    switch( mode ) {
    case Implied:                        o(0xea); return;
    default:                             break;
    }
    break;
  case sORA:
    switch( mode ) {
    case Immediate:                      om(0x09, value1, longa); return;
    case Absolute:                       ow(0x0d, value1); return;
    case AbsoluteLong:                   ol(0x0f, value1); return;
    case DirectPage:                     ob(0x05, value1); return;
    case DirectPageIndirect:             ob(0x12, value1); return;
    case DirectPageIndirectLong:         ob(0x07, value1); return;
    case AbsoluteIndexedX:               ow(0x1d, value1); return;
    case AbsoluteLongIndexedX:           ol(0x1f, value1); return;
    case AbsoluteIndexedY:               ow(0x19, value1); return;
    case DirectPageIndexedX:             ob(0x15, value1); return;
    case DirectPageIndexedIndirectX:     ob(0x01, value1); return;
    case DirectPageIndirectIndexedY:     ob(0x11, value1); return;
    case DirectPageIndirectLongIndexedY: ob(0x17, value1); return;
    case StackRelative:                  ob(0x03, value1); return;
    case StackRelativeIndirectIndexedY:  ob(0x13, value1); return;
    default:                             break;
    }
    break;
  case sPEA:
    switch( mode ) {
    case Immediate:
    case Absolute:                        ow(0xf4, value1); return;
    default:                              break;
    }
    break;
  case sPEI:
    switch( mode ) {
    case DirectPageIndirect:              ob(0xd4, value1); return;
    default:                              break;
    }
    break;
  case sPER:
    switch( mode ) {
    case Immediate:
    case DirectPage:
    case Absolute:                        ow(0x62, value1); return;
    default:                              break;
    }
    break;
  case sPHA:
    switch( mode ) {
    case Implied:                         o(0x48); return;
    default:                              break;
    }
    break;
  case sPHB:
    switch( mode ) {
    case Implied:                         o(0x8b); return;
    default:                              break;
    }
    break;
  case sPHD:
    switch( mode ) {
    case Implied:                         o(0x0b); return;
    default:                              break;
    }
    break;
  case sPHK:
    switch( mode ) {
    case Implied:                         o(0x4b); return;
    default:                              break;
    }
    break;
  case sPHP:
    switch( mode ) {
    case Implied:                         o(0x08); return;
    default:                              break;
    }
    break;
  case sPHX:
    switch( mode ) {
    case Implied:                         o(0xda); return;
    default:                              break;
    }
    break;
  case sPHY:
    switch( mode ) {
    case Implied:                         o(0x5a); return;
    default:                              break;
    }
    break;
  case sPLA:
    switch( mode ) {
    case Implied:                         o(0x68); return;
    default:                              break;
    }
    break;
  case sPLB:
    switch( mode ) {
    case Implied:                         o(0xab); return;
    default:                              break;
    }
    break;
  case sPLD:
    switch( mode ) {
    case Implied:                         o(0x2b); return;
    default:                              break;
    }
    break;
  case sPLP:
    switch( mode ) {
    case Implied:                         o(0x28); return;
    default:                              break;
    }
    break;
  case sPLX:
    switch( mode ) {
    case Implied:                         o(0xfa); return;
    default:                              break;
    }
    break;
  case sPLY:
    switch( mode ) {
    case Implied:                         o(0x7a); return;
    default:                              break;
    }
    break;
  case sREP:
    switch( mode ) {
    case Immediate:                       ob(0xc2, value1); return;
    default:                              break;
    }
    break;
  case sROL:
    switch( mode ) {
    case Accumulator:
    case Implied:                         o(0x2a); return;
    case Absolute:                        ow(0x2e, value1); return;
    case DirectPage:                      ob(0x26, value1); return;
    case AbsoluteIndexedX:                ow(0x3e, value1); return;
    case DirectPageIndexedX:              ob(0x36, value1); return;
    default:                              break;
    }
    break;
  case sROR:
    switch( mode ) {
    case Accumulator:
    case Implied:                         o(0x6a); return;
    case Absolute:                        ow(0x6e, value1); return;
    case DirectPage:                      ob(0x66, value1); return;
    case AbsoluteIndexedX:                ow(0x7e, value1); return;
    case DirectPageIndexedX:              ob(0x76, value1); return;
    default:                              break;
    }
    break;
  case sRTI:
    switch( mode ) {
    case Implied:                         o(0x40); return;
    default:                              break;
    }
    break;
  case sRTL:
    switch( mode ) {
    case Implied:                         o(0x6b); return;
    default:                              break;
    }
    break;
  case sRTS:
    switch( mode ) {
    case Implied:                         o(0x60); return;
    default:                              break;
    }
    break;
  case sSBC:
    switch( mode ) {
    case Immediate:                      om(0xe9, value1, longa); return;
    case Absolute:                       ow(0xed, value1); return;
    case AbsoluteLong:                   ol(0xef, value1); return;
    case DirectPage:                     ob(0xe5, value1); return;
    case DirectPageIndirect:             ob(0xf2, value1); return;
    case DirectPageIndirectLong:         ob(0xe7, value1); return;
    case AbsoluteIndexedX:               ow(0xfd, value1); return;
    case AbsoluteLongIndexedX:           ol(0xff, value1); return;
    case AbsoluteIndexedY:               ow(0xf9, value1); return;
    case DirectPageIndexedX:             ob(0xf5, value1); return;
    case DirectPageIndexedIndirectX:     ob(0xe1, value1); return; 
    case DirectPageIndirectIndexedY:     ob(0xf1, value1); return;
    case DirectPageIndirectLongIndexedY: ob(0xf7, value1); return;
    case StackRelative:                  ob(0xe3, value1); return;
    case StackRelativeIndirectIndexedY:  ob(0xf3, value1); return;
    default:                              break;
    }
    break;
  case sSEC:
    switch( mode ) {
    case Implied:                         o(0x38); return;
    default:                              break;
    }
    break;
  case sSED:
    switch( mode ) {
    case Implied:                         o(0xf8); return;
    default:                              break;
    }
    break;
  case sSEI:
    switch( mode ) {
    case Implied:                         o(0x78); return;
    default:                              break;
    }
    break;
  case sSEP:
    switch( mode ) {
    case Immediate:                       ob(0xe2, value1); return;
    default:                              break;
    }
    break;
  case sSTA:
    switch( mode ) {
    case Absolute:                       ow(0x8d, value1); return;
    case AbsoluteLong:                   ol(0x8f, value1); return;
    case DirectPage:                     ob(0x85, value1); return;
    case DirectPageIndirect:             ob(0x92, value1); return;
    case DirectPageIndirectLong:         ob(0x87, value1); return;
    case AbsoluteIndexedX:               ow(0x9d, value1); return;
    case AbsoluteLongIndexedX:           ol(0x9f, value1); return;
    case AbsoluteIndexedY:               ow(0x99, value1); return;
    case DirectPageIndexedX:             ob(0x95, value1); return;
    case DirectPageIndexedIndirectX:     ob(0x81, value1); return;
    case DirectPageIndirectIndexedY:     ob(0x91, value1); return;
    case DirectPageIndirectLongIndexedY: ob(0x97, value1); return;
    case StackRelative:
      if (value1 > 255) {
        // Large stack-relative offset: save A to DP temp, compute addr, restore, store
        ob(0x85, 0x42);                                   // STA $42 (save value)
        bool sta_save = longa;
        if (!longa) { o(0xC2); o(0x20); longa = 1; }     // REP #$20
        o(0xDA);                                           // PHX (SP -= 2)
        o(0x3B);                                           // TSC
        o(0x18);                                           // CLC
        o(0x69); o((value1+2)&0xff); o((value1+2)>>8);   // ADC #(offset+2)
        o(0xAA);                                           // TAX
        if (!sta_save) { o(0xE2); o(0x20); longa = 0; }  // SEP #$20
        ob(0xA5, 0x42);                                    // LDA $42 (restore value)
        o(0x9F); o(0x00); o(0x00); o(0x00);              // STA $000000,X
        o(0xFA);                                           // PLX
      } else {
        ob(0x83, value1);
      }
      return;
    case StackRelativeIndirectIndexedY:  ob(0x93, value1); return;
    default:                              break;
    }
    break;
  case sSTP:
    switch( mode ) {
    case Implied:                         o(0xdb); return;
    default:                              break;
    }
    break;
  case sSTX:
    switch( mode ) {
    case Absolute:                        ow(0x8e, value1); return;
    case DirectPage:                      ob(0x86, value1); return;
    case DirectPageIndexedY:              ow(0x96, value1); return;
    default:                              break;
    }
    break;
  case sSTY:
    switch( mode ) {
    case Absolute:                        ow(0x8c, value1); return;
    case DirectPage:                      ob(0x84, value1); return;
    case DirectPageIndexedX:              ob(0x94, value1); return;
    default:                              break;
    }
    break;
  case sSTZ:
    switch( mode ) {
    case Absolute:                        ow(0x9c, value1); return;
    case DirectPage:                      ob(0x64, value1); return;
    case AbsoluteIndexedX:                ow(0x9e, value1); return;
    case DirectPageIndexedX:              ow(0x74, value1); return;
    default:                              break;
    }
    break;
  case sTAX:
    switch( mode ) {
    case Implied:                         o(0xaa); return;
    default:                              break;
    }
    break;
  case sTAY:
    switch( mode ) {
    case Implied:                         o(0xa8); return;
    default:                              break;
    }
    break;
  case sTAD:
  case sTCD:
    switch( mode ) {
    case Implied:                         o(0x5b); return;
    default:                              break;
    }
    break;
  case sTAS:
  case sTCS:
    switch( mode ) {
    case Implied:                         o(0x1b); return;
    default:                              break;
    }
    break;
  case sTDA:
  case sTDC:
    switch( mode ) {
    case Implied:                         o(0x7b); return;
    default:                              break;
    }
    break;
  case sTRB:
    switch( mode ) {
    case Absolute:                        ow(0x1c, value1); return;
    case DirectPage:                      ob(0x14, value1); return;
    default:                              break;
    }
    break;
  case sTSB:
    switch( mode ) {
    case Absolute:                        ow(0x0c, value1); return;
    case DirectPage:                      ob(0x04, value1); return;
    default:                              break;
    }
    break;
  case sTSA:
  case sTSC:
    switch( mode ) {
    case Implied:                         o(0x3b); return;
    default:                              break;
    }
    break;
  case sTSX:
    switch( mode ) {
    case Implied:                         o(0xba); return;
    default:                              break;
    }
    break;
  case sTXA:
    switch( mode ) {
    case Implied:                         o(0x8a); return;
    default:                              break;
    }
    break;
  case sTXS:
    switch( mode ) {
    case Implied:                         o(0x9a); return;
    default:                              break;
    }
    break;
  case sTXY:
    switch( mode ) {
    case Implied:                         o(0x9b); return;
    default:                              break;
    }
    break;
  case sTYA:
    switch( mode ) {
    case Implied:                         o(0x98); return;
    default:                              break;
    }
    break;
  case sTYX:
    switch( mode ) {
    case Implied:                         o(0xbb); return;
    default:                              break;
    }
    break;
  case sWAI:
    switch( mode ) {
    case Implied:                         o(0xcb); return;
    default:                              break;
    }
    break;
  case sWDM:
    switch( mode ) {
    case Immediate:                       ob(0x42, value1); return;
    default:                              break;
    }
    break;
  case sSWA:
  case sXBA:
    switch( mode ) {
    case Implied:                         o(0xeb); return;
    default:                              break;
    }
    break;
  case sXCE:
    switch( mode ) {
    case Implied:                         o(0xfb); return;
    default:                              break;
    }
    break;
  default:
      break;
  }
  // as_gen_error(filename, line_num, "%s %s not supported on %s",
  //	   token_to_string(opcode),
  //	   mode_to_string(mode),
  //	   cpu_to_string(cpu));
}
